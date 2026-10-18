/// 编排层测试：需求 1（保存后免密取课表）与需求 2（失效自动重登）。
///
/// 每个用例都盯着一个具体的失败模式，不是"跑通就算过"：
///  - 只有 SESSION_EXPIRED 触发重登（PAGE_CHANGED 不触发，防白耗失败次数）；
///  - 重登失败必须回滚旧 Cookie；
///  - 并发只登一次（单 flight）；
///  - 熔断打开后不再登录；
///  - 验证码走回调，取消时不留半死状态。
library;

import 'package:qustschedule/src/schedule_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';

const String _baseUrl = 'https://jw.example.edu.cn/jwglxt';

class _Harness {
  _Harness({
    FakeBackend? backend,
    FakeSessionRepository? storage,
    InMemoryCredentialStore? credentials,
    Future<String?> Function(CaptchaState state)? captchaHandler,
    int autoLoginLimit = 2,
    String baseUrl = _baseUrl,
  }) : backend = backend ?? FakeBackend(),
       storage = storage ?? FakeSessionRepository(),
       credentials = credentials ?? InMemoryCredentialStore() {
    service = ScheduleService(
      credentials: this.credentials,
      cookieStorage: this.storage,
      captchaHandler: captchaHandler ?? (_) async => null,
      autoLoginLimit: autoLoginLimit,
      baseUrl: baseUrl,
      backendFactory: (config) {
        this.config = config;
        return this.backend;
      },
    );
  }

  final FakeBackend backend;
  final FakeSessionRepository storage;
  final InMemoryCredentialStore credentials;
  late final ScheduleService service;

  /// 编排层实际传给客户端的配置（用来验证 onRequest 等接线）。
  ZfClientConfig? config;

  static const String accountKey = '$_baseUrl|2407720102';
}

void main() {
  group('需求 1：Cookie 优先', () {
    test('Cookie 有效时直接取课表，不触发登录', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );

      final schedule = await h.service.getSchedule();

      expect(schedule.entries, isNotEmpty);
      expect(h.backend.fetchCount, 1);
      expect(h.backend.loginCount, 0, reason: 'Cookie 有效就不该登录');
    });

    test('有快照时 bootstrap 原样返回；快照的 Cookie 会被带进客户端', () async {
      final storage = FakeSessionRepository(
        snapshotOf(_baseUrl, value: 'saved'),
      );
      final h = _Harness(storage: storage);

      final snapshot = await h.service.bootstrap();

      expect(snapshot, isNotNull);
      expect(snapshot!.cookies.single.value, 'saved');
    });

    test('换校后旧快照被丢弃并清盘（避免把 A 校会话带去 B 校）', () async {
      final storage = FakeSessionRepository(
        snapshotOf('https://old.example.edu.cn/jwglxt'),
      );
      final h = _Harness(storage: storage);

      final snapshot = await h.service.bootstrap();

      expect(snapshot, isNull);
      expect(storage.clearCount, 1);
    });

    test('空 Cookie 快照视为没有会话', () async {
      final storage = FakeSessionRepository(
        CookieStoreSnapshot(
          version: 1,
          baseUrl: _baseUrl,
          savedAt: 1,
          cookies: const <CookieRecord>[],
        ),
      );
      final h = _Harness(storage: storage);

      expect(await h.service.bootstrap(), isNull);
      expect(storage.clearCount, 1);
    });
  });

  group('需求 2：失效回退登录', () {
    test('Cookie 失效 → 用保存的账密重登 → 重试一次成功 → 新 Cookie 落盘', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return sampleSchedule();
      };

      final schedule = await h.service.getSchedule();

      expect(schedule.entries, isNotEmpty);
      expect(h.backend.fetchCount, 2, reason: '失效后只重试一次');
      expect(h.backend.loginCount, 1);
      expect(
        h.storage.saveCount,
        greaterThanOrEqualTo(1),
        reason: '新 Cookie 必须落盘',
      );
      expect(h.storage.snapshot!.cookies.single.value, 'fresh');
    });

    test('没有保存账密时抛 SESSION_EXPIRED 且不尝试登录', () async {
      final h = _Harness();
      h.backend.fetchBehavior = (call, termId) async => throw expired();

      await expectLater(
        h.service.getSchedule(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.sessionExpired,
          ),
        ),
      );
      expect(h.backend.loginCount, 0);
    });

    test('重登被拒（密码已改）→ 旧 Cookie 回滚，错误上抛', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'old-pw'),
      );
      h.backend.fetchBehavior = (call, termId) async => throw expired();
      h.backend.loginBehavior = (call, credentials) async =>
          throw badCredentials();

      await expectLater(
        h.service.getSchedule(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.invalidCredentials,
          ),
        ),
      );
      expect(h.backend.importCount, 1, reason: '失败必须恢复旧 Cookie');
      expect(h.backend.lastImported!.cookies.single.value, 'old');
    });

    test('重登成功但重试仍失败（页面结构变化）→ 回滚并上抛原错误', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );
      var call = 0;
      h.backend.fetchBehavior = (_, termId) async {
        call++;
        if (call == 1) throw expired();
        throw pageChanged();
      };

      await expectLater(
        h.service.getSchedule(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.pageChanged,
          ),
        ),
      );
      expect(h.backend.importCount, 1);
    });

    test('PAGE_CHANGED 不触发重登（重登解决不了，还会白耗失败次数）', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async => throw pageChanged();

      await expectLater(
        h.service.getSchedule(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.pageChanged,
          ),
        ),
      );
      expect(h.backend.loginCount, 0);
      expect(h.backend.fetchCount, 1);
    });

    test('单 flight：并发 3 次取课表，只登一次、只重试一次', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );
      h.backend.loginBehavior = (call, credentials) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };
      h.backend.fetchBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return sampleSchedule();
      };

      final results = await Future.wait(<Future<Schedule>>[
        h.service.getSchedule(),
        h.service.getSchedule(),
        h.service.getSchedule(),
      ]);

      expect(results, hasLength(3));
      expect(h.backend.loginCount, 1, reason: '并发必须共享同一次登录');
      expect(h.backend.fetchCount, 2);
    });

    test('熔断：超出窗口内自动登录次数后不再登录，直接要求手动登录', () async {
      final h = _Harness(autoLoginLimit: 1);
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );

      // 第一次：失效 → 重登成功 → 重试又失效（第二轮回抛）
      var round = 0;
      h.backend.fetchBehavior = (call, termId) async {
        round++;
        // 第 1、2 次都失效 → 触发一次重登，重试仍失效
        if (round <= 2) throw expired();
        return sampleSchedule();
      };
      h.backend.loginBehavior = (call, credentials) async {
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh$call');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      // 第一次：允许一次自动登录（limit=1），但重试仍失效 → 报错，熔断还没开
      await expectLater(h.service.getSchedule(), throwsA(isA<AcademicError>()));
      final loginsAfterFirst = h.backend.loginCount;
      expect(loginsAfterFirst, 1);
      expect(h.service.breakerOpen, isFalse, reason: '窗口内第 1 次自动登录仍应允许');

      // 第二次：已达上限 → 直接熔断，不再登录
      h.backend.fetchBehavior = (call, termId) async => throw expired();
      await expectLater(
        h.service.getSchedule(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.sessionExpired,
          ),
        ),
      );
      expect(h.backend.loginCount, loginsAfterFirst, reason: '熔断后不得再登录');
      expect(h.service.breakerOpen, isTrue);
    });

    test('手动登录成功会解除熔断', () async {
      final h = _Harness(autoLoginLimit: 0);
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async => throw expired();

      await expectLater(h.service.getSchedule(), throwsA(isA<AcademicError>()));
      expect(h.service.breakerOpen, isTrue);

      final state = await h.service.signIn('2407720102', 'pw');
      expect(state, isA<AuthenticatedState>());
      expect(h.service.breakerOpen, isFalse);
    });

    test('自动重登遇验证码：回调拿到的码被提交，成功后继续取课表', () async {
      String? receivedCode;
      final h = _Harness(
        captchaHandler: (state) async {
          expect(state.imageBase64, isNotEmpty);
          return '1234';
        },
      );
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return sampleSchedule();
      };
      h.backend.loginBehavior = (call, credentials) async => const CaptchaState(
        continuationId: 'c1',
        imageBase64: 'iVBORw0KGgo=',
        mimeType: 'image/png',
      );
      h.backend.submitBehavior = (call, code) async {
        receivedCode = code;
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      final schedule = await h.service.getSchedule();

      expect(receivedCode, '1234');
      expect(h.backend.submitCount, 1);
      expect(schedule.entries, isNotEmpty);
    });

    test('自动重登遇验证码但用户取消：抛 CAPTCHA_REQUIRED 并回滚', () async {
      final h = _Harness(captchaHandler: (state) async => null);
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async => throw expired();
      h.backend.loginBehavior = (call, credentials) async => const CaptchaState(
        continuationId: 'c1',
        imageBase64: 'iVBORw0KGgo=',
        mimeType: 'image/png',
      );

      await expectLater(
        h.service.getSchedule(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.captchaRequired,
          ),
        ),
      );
      expect(h.backend.importCount, 1);
      expect(h.backend.submitCount, 0);
    });
  });

  group('调试数据（DebugPage 的数据源）', () {
    test('onRequest 被注入，请求记录进 service.requestLog', () async {
      final h = _Harness();
      await h.service.getSchedule();

      expect(h.config, isNotNull);
      expect(h.config!.onRequest, isNotNull, reason: '必须在建客户端时注入记录器');

      h.config!.onRequest!(
        const RequestLog(
          method: 'GET',
          url: 'https://jw.example.edu.cn/jwglxt/xtgl/index_initMenu.html',
          status: 200,
          purpose: RequestPurpose.query,
        ),
      );
      expect(h.service.requestLog, hasLength(1));
      expect(h.service.requestLog.single.status, 200);
      expect(h.service.requestLog.single.method, 'GET');
    });

    test('客户端拿到的原始课表数据经 service 透出', () async {
      final h = _Harness();
      h.backend.lastScheduleRawBody = '{"kbList":[{"kcmc":"x"}]}';
      h.backend.lastScheduleRows = <Map<String, dynamic>>[
        <String, dynamic>{'kcmc': 'x', 'xqj': '1'},
      ];

      await h.service.getSchedule();

      expect(h.service.lastScheduleRawBody, '{"kbList":[{"kcmc":"x"}]}');
      expect(h.service.lastScheduleRows, hasLength(1));
      expect(h.service.lastScheduleRows.single['kcmc'], 'x');
    });
  });

  group('阶段回调（供 UI 显示"正在重新登录"）', () {
    test('自动重登会触发 relogin 阶段', () async {
      final h = _Harness();
      final stages = <String>[];
      h.service.onStage = stages.add;
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return sampleSchedule();
      };

      await h.service.getSchedule();

      expect(stages, contains(ScheduleService.stageRelogin));
    });

    test('Cookie 有效时不触发 relogin 阶段', () async {
      final h = _Harness();
      final stages = <String>[];
      h.service.onStage = stages.add;

      await h.service.getSchedule();

      expect(stages, isEmpty);
    });
  });

  group('登录与课表可单独使用', () {
    test('只用登录：signIn 记住密码并落盘 Cookie', () async {
      final h = _Harness();

      final state = await h.service.signIn('2407720102', 'pw');

      expect(state, isA<AuthenticatedState>());
      final saved = await h.credentials.get(_Harness.accountKey);
      expect(saved?.username, '2407720102');
      expect(saved?.password, 'pw');
      expect(h.storage.saveCount, 1);
    });

    test('只用登录：remember=false 时不写安全存储', () async {
      final h = _Harness();

      await h.service.signIn('2407720102', 'pw', remember: false);

      expect(await h.credentials.has(_Harness.accountKey), isFalse);
      expect(h.storage.saveCount, 1, reason: 'Cookie 仍要保存');
    });

    test('只用课表：完全不碰凭据也能取（有有效 Cookie 时）', () async {
      final h = _Harness();

      final schedule = await h.service.getSchedule();

      expect(schedule.entries, isNotEmpty);
      expect(h.backend.loginCount, 0);
    });

    test('退出登录清空快照；forget 一并删凭据', () async {
      final h = _Harness();
      await h.service.signIn('2407720102', 'pw');

      await h.service.signOut(forgetCredentials: true);

      expect(h.storage.clearCount, 1);
      expect(await h.credentials.has(_Harness.accountKey), isFalse);
    });

    test('学期列表失效时同样走回退登录', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('2407720102', 'pw'),
      );
      var termsCall = 0;
      h.backend.termsBehavior = (call) async {
        termsCall++;
        if (termsCall == 1) throw expired();
        return const Terms(
          currentId: '2026-2027-1',
          items: <Term>[Term(id: '2026-2027-1', name: '当前学期')],
        );
      };

      final terms = await h.service.fetchTerms();

      expect(terms.currentId, '2026-2027-1');
      expect(h.backend.loginCount, 1);
    });
  });
}
