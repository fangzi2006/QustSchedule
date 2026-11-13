/// 编排层测试：需求 1（保存后免密取课表）与需求 2（失效自动重登）。
///
/// 每个用例都盯着一个具体的失败模式，不是"跑通就算过"：
///  - 只有 SESSION_EXPIRED 触发重登（PAGE_CHANGED 不触发，防白耗失败次数）；
///  - 重登失败必须回滚旧 Cookie；
///  - 并发只登一次（单 flight）；
///  - 熔断打开后不再登录；
///  - 验证码走回调，取消时不留半死状态。
library;

import 'dart:async';

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

  static const String accountKey = '$_baseUrl|20240001';
}

void main() {
  group('需求 1：Cookie 优先', () {
    test('Cookie 有效时直接取课表，不触发登录', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );

      final schedule = await h.service.getSchedule();

      expect(schedule.entries, isNotEmpty);
      expect(h.backend.fetchCount, 1);
      expect(h.backend.loginCount, 0, reason: 'Cookie 有效就不该登录');
      expect(h.config?.requestTimeoutMs, 10000, reason: '客户端超时应统一设为 10 秒');
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

    test('换地址后旧快照被丢弃并清盘（避免把旧线路会话带过去）', () async {
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
        const Credentials('20240001', 'pw'),
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
        const Credentials('20240001', 'old-pw'),
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
        const Credentials('20240001', 'pw'),
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
        const Credentials('20240001', 'pw'),
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
        const Credentials('20240001', 'pw'),
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
        const Credentials('20240001', 'pw'),
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
        const Credentials('20240001', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async => throw expired();

      await expectLater(h.service.getSchedule(), throwsA(isA<AcademicError>()));
      expect(h.service.breakerOpen, isTrue);

      final state = await h.service.signIn('20240001', 'pw');
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
        const Credentials('20240001', 'pw'),
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
        const Credentials('20240001', 'pw'),
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
    test('自动重登会按序触发 relogin 与 fetching_schedule 阶段', () async {
      final h = _Harness();
      final stages = <String>[];
      h.service.onStage = stages.add;
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return sampleSchedule();
      };

      await h.service.getSchedule();

      expect(stages, [
        ScheduleService.stageRelogin,
        ScheduleService.stageFetchingSchedule,
      ]);
    });

    test('Cookie 有效时不触发 relogin 阶段', () async {
      final h = _Harness();
      final stages = <String>[];
      h.service.onStage = stages.add;

      await h.service.getSchedule();

      expect(stages, isEmpty);
    });

    test('考试与成绩查询遇 Cookie 失效重登时同样触发 relogin 阶段（行为一致性）', () async {
      final h = _Harness();
      final stages = <String>[];
      h.service.onStage = stages.add;
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );

      h.backend.examsBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return const <ExamItem>[];
      };

      await h.service.fetchExams();
      expect(stages, contains(ScheduleService.stageRelogin));

      stages.clear();
      h.backend.gradesBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return const <GradeItem>[];
      };

      await h.service.fetchGrades();
      expect(stages, contains(ScheduleService.stageRelogin));
    });
  });

  group('登录与课表可单独使用', () {
    test('只用登录：signIn 记住密码并落盘 Cookie', () async {
      final h = _Harness();

      final state = await h.service.signIn('20240001', 'pw');

      expect(state, isA<AuthenticatedState>());
      final saved = await h.credentials.get(_Harness.accountKey);
      expect(saved?.username, '20240001');
      expect(saved?.password, 'pw');
      expect(h.storage.saveCount, 1);
    });

    test('只用登录：remember=false 时不写安全存储', () async {
      final h = _Harness();

      await h.service.signIn('20240001', 'pw', remember: false);

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
      await h.service.signIn('20240001', 'pw');

      await h.service.signOut(forgetCredentials: true);

      expect(h.storage.clearCount, 1);
      expect(await h.credentials.has(_Harness.accountKey), isFalse);
    });

    test('学期列表失效时同样走回退登录', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
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

  group('凭据 key：冷启动必须能算出账号', () {
    test('accountHint 补齐账号 → Cookie 失效后能用保存的账密重登', () async {
      // 身份为空：模拟真机冷启动——Cookie 快照里没有用户名。
      final h = _Harness(
        backend: FakeBackend(studentId: '', studentName: ''),
        storage: FakeSessionRepository(snapshotOf(_baseUrl)),
      );
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async {
        if (call == 1) {
          throw AcademicError(ErrorCode.sessionExpired, '登录已失效');
        }
        return sampleSchedule(termId ?? '2026-2027-1');
      };
      // 冷启动：Cookie 快照在，但快照里没有用户名，只能靠本地账号拼 key。
      h.service.accountHint = '20240001';
      await h.service.bootstrap();

      final schedule = await h.service.getSchedule();

      expect(schedule.entries, isNotEmpty);
      expect(h.backend.loginCount, 1, reason: '应该用保存的账密自动重登');
    });

    test('没有账号就取不到凭据（修复前的失败模式）', () async {
      // 身份为空：模拟真机冷启动——Cookie 快照里没有用户名。
      final h = _Harness(
        backend: FakeBackend(studentId: '', studentName: ''),
        storage: FakeSessionRepository(snapshotOf(_baseUrl)),
      );
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      h.backend.fetchBehavior = (call, termId) async {
        throw AcademicError(ErrorCode.sessionExpired, '登录已失效');
      };
      await h.service.bootstrap();

      await expectLater(
        h.service.getSchedule(),
        throwsA(
          isA<AcademicError>()
              .having((error) => error.code, 'code', ErrorCode.sessionExpired)
              .having(
                (error) => error.message,
                'message',
                contains('没有保存账号密码'),
              ),
        ),
      );
      expect(h.backend.loginCount, 0, reason: '账号为空时连凭据 key 都算不出来');
    });
  });

  group('需求 2（扩展）：考试与成绩查询的失效回退登录与全局阻塞互斥锁', () {
    test('fetchExams Cookie 失效 → 用保存的账密重登 → 重试一次成功 → 新 Cookie 落盘', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var examsCall = 0;
      h.backend.examsBehavior = (call, termId) async {
        examsCall++;
        if (examsCall == 1) throw expired();
        return sampleExams();
      };

      final exams = await h.service.fetchExams();

      expect(exams, isNotEmpty);
      expect(h.backend.examsCount, 2, reason: '失效后重试一次');
      expect(h.backend.loginCount, 1, reason: '必须触发自动重登');
      expect(h.storage.snapshot!.cookies.single.value, 'fresh');
    });

    test('fetchGrades Cookie 失效 → 用保存的账密重登 → 重试一次成功 → 新 Cookie 落盘', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var gradesCall = 0;
      h.backend.gradesBehavior = (call, termId) async {
        gradesCall++;
        if (gradesCall == 1) throw expired();
        return sampleGrades();
      };

      final grades = await h.service.fetchGrades();

      expect(grades, isNotEmpty);
      expect(h.backend.gradesCount, 2, reason: '失效后重试一次');
      expect(h.backend.loginCount, 1, reason: '必须触发自动重登');
      expect(h.storage.snapshot!.cookies.single.value, 'fresh');
    });

    test('没有保存账密时 fetchExams / fetchGrades 抛 SESSION_EXPIRED 且不尝试登录', () async {
      final h = _Harness();
      h.backend.examsBehavior = (call, termId) async => throw expired();
      h.backend.gradesBehavior = (call, termId) async => throw expired();

      await expectLater(
        h.service.fetchExams(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.sessionExpired,
          ),
        ),
      );
      await expectLater(
        h.service.fetchGrades(),
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

    test('全局阻塞互斥：并发 fetchExams 与 fetchGrades 遇失效，只登一次、共享单 flight', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var examsCall = 0;
      h.backend.examsBehavior = (call, termId) async {
        examsCall++;
        if (examsCall == 1) throw expired();
        return sampleExams();
      };
      var gradesCall = 0;
      h.backend.gradesBehavior = (call, termId) async {
        gradesCall++;
        if (gradesCall == 1) throw expired();
        return sampleGrades();
      };
      h.backend.loginBehavior = (call, credentials) async {
        await Future<void>.delayed(const Duration(milliseconds: 40));
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        h.service.fetchExams(),
        h.service.fetchGrades(),
      ]);

      expect(results[0], isA<List<ExamItem>>());
      expect(results[1], isA<List<GradeItem>>());
      expect(h.backend.loginCount, 1, reason: '并发失效必须共享同一次重登，不得重复登录');
      expect(h.backend.examsCount, 2);
      expect(h.backend.gradesCount, 2);
    });

    test('全局阻塞互斥：重登进行中到达的新查询被阻塞等待，不得一边登录一边查询数据', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var examsCall = 0;
      h.backend.examsBehavior = (call, termId) async {
        examsCall++;
        if (examsCall == 1) throw expired();
        return sampleExams();
      };

      final loginCompleter = Completer<void>();
      h.backend.loginBehavior = (call, credentials) async {
        await loginCompleter.future;
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      // 1. 发起 fetchExams，触发重登挂起
      final examsFuture = h.service.fetchExams();
      // 等待宏任务调度，确保 examsBehavior 执行并进入重登
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(h.backend.loginCount, 1);
      expect(
        h.service.reloginFlightForTest,
        isNotNull,
        reason: '重登正在 flight 中',
      );

      // 2. 在重登未完成期间，调用 fetchGrades
      bool gradesFinished = false;
      final gradesFuture = h.service.fetchGrades().then((v) {
        gradesFinished = true;
        return v;
      });

      // 让出事件循环，检查 fetchGrades 是否被阻止在网络请求之前
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(h.backend.gradesCount, 0, reason: '重登进行中不得发起查询请求（防止一边登录一边查询）');
      expect(gradesFinished, isFalse);

      // 3. 完成重登，让等待的请求继续
      loginCompleter.complete();
      final exams = await examsFuture;
      final grades = await gradesFuture;

      expect(exams, isNotEmpty);
      expect(grades, isNotEmpty);
      expect(h.backend.loginCount, 1, reason: '全程只登一次');
      expect(h.backend.gradesCount, 1, reason: '重登完成后使用新凭据直接查询一次即成功');
    });

    test('全局阻塞互斥：重登失败时等待的查询一同抛出错误，不盲发查询请求', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      h.backend.examsBehavior = (call, termId) async => throw expired();

      final loginCompleter = Completer<void>();
      h.backend.loginBehavior = (call, credentials) async {
        await loginCompleter.future;
        throw badCredentials();
      };

      final examsFuture = h.service.fetchExams();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      final gradesFuture = h.service.fetchGrades();
      await Future<void>.delayed(const Duration(milliseconds: 10));

      expect(h.backend.gradesCount, 0);

      loginCompleter.complete();

      await expectLater(
        examsFuture,
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.invalidCredentials,
          ),
        ),
      );
      await expectLater(
        gradesFuture,
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.invalidCredentials,
          ),
        ),
      );

      expect(h.backend.gradesCount, 0, reason: '重登失败后不该再发送无效凭据请求');
    });

    test('全局阻塞互斥：getSchedule 与 fetchExams / fetchGrades 并发失效共享单次重登', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var scheduleCall = 0;
      h.backend.fetchBehavior = (call, termId) async {
        scheduleCall++;
        if (scheduleCall == 1) throw expired();
        return sampleSchedule();
      };
      var examsCall = 0;
      h.backend.examsBehavior = (call, termId) async {
        examsCall++;
        if (examsCall == 1) throw expired();
        return sampleExams();
      };
      var gradesCall = 0;
      h.backend.gradesBehavior = (call, termId) async {
        gradesCall++;
        if (gradesCall == 1) throw expired();
        return sampleGrades();
      };
      h.backend.loginBehavior = (call, credentials) async {
        await Future<void>.delayed(const Duration(milliseconds: 30));
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        h.service.getSchedule(),
        h.service.fetchExams(),
        h.service.fetchGrades(),
      ]);

      expect(results[0], isA<Schedule>());
      expect(results[1], isA<List<ExamItem>>());
      expect(results[2], isA<List<GradeItem>>());
      expect(h.backend.loginCount, 1, reason: '课表与考试成绩并发失效只能触发一次登录');
    });

    test('重登中途 signOut 清理会话：重登结果不写回 cookieStorage，防复活', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      h.backend.examsBehavior = (call, termId) async => throw expired();

      final loginCompleter = Completer<void>();
      h.backend.loginBehavior = (call, credentials) async {
        await loginCompleter.future;
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      final examsFuture = h.service.fetchExams();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(h.backend.loginCount, 1);

      // 用户在重登等待中主动退出登录
      await h.service.signOut();

      // 放行后台登录完成
      loginCompleter.complete();
      await expectLater(examsFuture, throwsA(isA<AcademicError>()));

      // 验证 cookieStorage 没有被后台重登污染复活
      final storedSnapshot = await h.storage.load();
      expect(storedSnapshot, isNull, reason: '已退出登录不得写回 Cookie 快照');
    });

    test('并发查询初始化共享同一个 backend 客户端创建任务', () async {
      final h = _Harness();
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        h.service.fetchTerms(),
        h.service.fetchExams(),
        h.service.fetchGrades(),
      ]);

      expect(results[0], isA<Terms>());
      expect(results[1], isA<List<ExamItem>>());
      expect(results[2], isA<List<GradeItem>>());
      expect(h.backend.termsCount, 1);
      expect(h.backend.examsCount, 1);
      expect(h.backend.gradesCount, 1);
    });

    test('手选登录 signIn 遇到正在进行的后台自动重登会先行等待，避免双重并发登录', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var examsCall = 0;
      h.backend.examsBehavior = (call, termId) async {
        examsCall++;
        if (examsCall == 1) throw expired();
        return sampleExams();
      };

      final loginCompleter = Completer<void>();
      h.backend.loginBehavior = (call, credentials) async {
        await loginCompleter.future;
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      final examsFuture = h.service.fetchExams();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(h.backend.loginCount, 1);

      // 手动登录介入
      final signInFuture = h.service.signIn('20240001', 'new-pw');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      // 此时因为等待 reloginFlight，signIn 尚未发起第二次 client.login
      expect(h.backend.loginCount, 1, reason: 'signIn 必须等待当前自动重登完成，不得直接冲撞');

      loginCompleter.complete();
      await examsFuture;
      final state = await signInFuture;
      expect(state, isA<AuthenticatedState>());
    });

    test('经验证码完成 signIn 后仍会保存凭据与 accountHint（remember=false 则不存密码）', () async {
      final h1 = _Harness();
      h1.backend.loginBehavior = (call, credentials) async =>
          const CaptchaState(
            continuationId: 'c1',
            imageBase64: 'iVBORw0KGgo=',
            mimeType: 'image/png',
          );
      final first = await h1.service.signIn('20240001', 'pw');
      expect(first, isA<CaptchaState>());
      expect(await h1.credentials.has(_Harness.accountKey), isFalse);

      final done1 = await h1.service.submitCaptcha('1234');
      expect(done1, isA<AuthenticatedState>());
      final saved = await h1.credentials.get(_Harness.accountKey);
      expect(saved?.username, '20240001');
      expect(saved?.password, 'pw');
      expect(h1.service.accountHint, '20240001');
      expect(h1.storage.saveCount, 1);

      final h2 = _Harness();
      h2.backend.loginBehavior = (call, credentials) async =>
          const CaptchaState(
            continuationId: 'c2',
            imageBase64: 'iVBORw0KGgo=',
            mimeType: 'image/png',
          );
      await h2.service.signIn('20240001', 'pw', remember: false);
      await h2.service.submitCaptcha('1234');
      expect(await h2.credentials.has(_Harness.accountKey), isFalse);
      expect(h2.service.accountHint, '20240001');
    });
  });
}
