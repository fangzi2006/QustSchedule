/// 编排层测试：需求 1（保存后免密取课表）与需求 2（失效自动重登）。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/school.dart';
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

  ZfClientConfig? config;

  static const String accountKey = '$_baseUrl|20240001';
}

void main() {
  group('需求 1：Cookie 优先与快照校验', () {
    test('Cookie 有效时直接取课表（无论是否存凭据），不触发登录且超时设为 10 秒', () async {
      final h1 = _Harness();
      await h1.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      final schedule1 = await h1.service.getSchedule();
      expect(schedule1.entries, isNotEmpty);
      expect(h1.backend.fetchCount, 1);
      expect(h1.backend.loginCount, 0);
      expect(h1.config?.requestTimeoutMs, 10000);
      expect(h1.config?.paceHosts, defaultAcademicPaceHosts);
      expect(h1.config?.paceHosts?['jw.cqiivc.com'], 1200);

      // 不保存任何凭据时同样能直接用有效 Cookie 取课表
      final h2 = _Harness();
      final schedule2 = await h2.service.getSchedule();
      expect(schedule2.entries, isNotEmpty);
      expect(h2.backend.loginCount, 0);
    });

    test('bootstrap 快照校验：同源非空原样返回，换地址或空 Cookie 清盘丢弃', () async {
      final validStorage = FakeSessionRepository(
        snapshotOf(_baseUrl, value: 'saved'),
      );
      final hValid = _Harness(storage: validStorage);
      final snapshot = await hValid.service.bootstrap();
      expect(snapshot, isNotNull);
      expect(snapshot!.cookies.single.value, 'saved');

      final oldUrlStorage = FakeSessionRepository(
        snapshotOf('https://old.example.edu.cn/jwglxt'),
      );
      final hOldUrl = _Harness(storage: oldUrlStorage);
      expect(await hOldUrl.service.bootstrap(), isNull);
      expect(oldUrlStorage.clearCount, 1);

      final emptyCookieStorage = FakeSessionRepository(
        const CookieStoreSnapshot(
          version: 1,
          baseUrl: _baseUrl,
          savedAt: 1,
          cookies: <CookieRecord>[],
        ),
      );
      final hEmpty = _Harness(storage: emptyCookieStorage);
      expect(await hEmpty.service.bootstrap(), isNull);
      expect(emptyCookieStorage.clearCount, 1);
    });
  });

  group('需求 2：失效回退登录与熔断', () {
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
      expect(h.backend.fetchCount, 2);
      expect(h.backend.loginCount, 1);
      expect(h.storage.saveCount, greaterThanOrEqualTo(1));
      expect(h.storage.snapshot!.cookies.single.value, 'fresh');
    });

    test(
      '没有保存账密时 getSchedule / fetchExams / fetchGrades 抛 SESSION_EXPIRED 且不登录',
      () async {
        final h = _Harness();
        h.backend.fetchBehavior = (call, termId) async => throw expired();
        h.backend.examsBehavior = (call, termId) async => throw expired();
        h.backend.gradesBehavior = (call, termId) async => throw expired();

        for (final action in <Future<Object?> Function()>[
          h.service.getSchedule,
          h.service.fetchExams,
          h.service.fetchGrades,
        ]) {
          await expectLater(
            action(),
            throwsA(
              isA<AcademicError>().having(
                (e) => e.code,
                'code',
                ErrorCode.sessionExpired,
              ),
            ),
          );
        }
        expect(h.backend.loginCount, 0);
      },
    );

    test('重登被拒时回滚旧 Cookie；重登成功持久化后业务重试失败则保留新 Cookie 不回滚', () async {
      // 场景 A：重登被拒（密码已改）→ 回滚旧 Cookie
      final h1 = _Harness();
      await h1.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'old-pw'),
      );
      h1.backend.fetchBehavior = (call, termId) async => throw expired();
      h1.backend.loginBehavior = (call, credentials) async =>
          throw badCredentials();

      await expectLater(
        h1.service.getSchedule(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.invalidCredentials,
          ),
        ),
      );
      expect(h1.backend.importCount, 1);
      expect(h1.backend.lastImported!.cookies.single.value, 'old');

      // 场景 B：重登已成功换上新 Cookie，紧接着业务重试报页面结构变化 → 保留新 Cookie 不倒灌过期旧 Cookie
      final h2 = _Harness();
      await h2.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var call = 0;
      h2.backend.fetchBehavior = (_, termId) async {
        call++;
        if (call == 1) throw expired();
        throw pageChanged();
      };

      await expectLater(
        h2.service.getSchedule(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.pageChanged,
          ),
        ),
      );
      expect(h2.backend.importCount, 0);
      expect(h2.backend.cookies.cookies.single.value, 'fresh');
      expect(h2.storage.snapshot!.cookies.single.value, 'fresh');
    });

    test('PAGE_CHANGED 不触发重登（防白耗失败次数）', () async {
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

    test('单 flight：并发多次取课表及跨接口（课表/考试/成绩）并发失效均共享单次重登', () async {
      // 1. 并发 3 次 getSchedule
      final h1 = _Harness();
      await h1.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      h1.backend.loginBehavior = (call, credentials) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        h1.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };
      h1.backend.fetchBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return sampleSchedule();
      };

      final schedules = await Future.wait(<Future<Schedule>>[
        h1.service.getSchedule(),
        h1.service.getSchedule(),
        h1.service.getSchedule(),
      ]);
      expect(schedules, hasLength(3));
      expect(h1.backend.loginCount, 1);
      expect(h1.backend.fetchCount, 2);

      // 2. getSchedule + fetchExams + fetchGrades 并发失效共享单次重登
      final h2 = _Harness();
      await h2.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var scheduleCall = 0;
      h2.backend.fetchBehavior = (call, termId) async {
        if (++scheduleCall == 1) throw expired();
        return sampleSchedule();
      };
      var examsCall = 0;
      h2.backend.examsBehavior = (call, termId) async {
        if (++examsCall == 1) throw expired();
        return sampleExams();
      };
      var gradesCall = 0;
      h2.backend.gradesBehavior = (call, termId) async {
        if (++gradesCall == 1) throw expired();
        return sampleGrades();
      };
      h2.backend.loginBehavior = (call, credentials) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        h2.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      final mixed = await Future.wait<dynamic>(<Future<dynamic>>[
        h2.service.getSchedule(),
        h2.service.fetchExams(),
        h2.service.fetchGrades(),
      ]);
      expect(mixed[0], isA<Schedule>());
      expect(mixed[1], isA<List<ExamItem>>());
      expect(mixed[2], isA<List<GradeItem>>());
      expect(h2.backend.loginCount, 1);
    });

    test('熔断：超出窗口内自动登录次数后不再登录，手动 signIn 成功后解除熔断', () async {
      final h = _Harness(autoLoginLimit: 1);
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );

      var round = 0;
      h.backend.fetchBehavior = (call, termId) async {
        round++;
        if (round <= 2) throw expired();
        return sampleSchedule();
      };
      h.backend.loginBehavior = (call, credentials) async {
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh$call');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      await expectLater(h.service.getSchedule(), throwsA(isA<AcademicError>()));
      expect(h.backend.loginCount, 1);
      expect(h.service.breakerOpen, isFalse);

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
      expect(h.backend.loginCount, 1);
      expect(h.service.breakerOpen, isTrue);

      final state = await h.service.signIn('20240001', 'pw');
      expect(state, isA<AuthenticatedState>());
      expect(h.service.breakerOpen, isFalse);
    });

    test('自动重登遇验证码：回调提交成功后重试，用户取消则抛 CAPTCHA_REQUIRED 并回滚', () async {
      String? receivedCode;
      final hOk = _Harness(
        captchaHandler: (state) async {
          expect(state.imageBase64, isNotEmpty);
          return '1234';
        },
      );
      await hOk.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      hOk.backend.fetchBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return sampleSchedule();
      };
      hOk.backend.loginBehavior = (call, credentials) async =>
          const CaptchaState(
            continuationId: 'c1',
            imageBase64: 'iVBORw0KGgo=',
            mimeType: 'image/png',
          );
      hOk.backend.submitBehavior = (call, code) async {
        receivedCode = code;
        hOk.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      final schedule = await hOk.service.getSchedule();
      expect(receivedCode, '1234');
      expect(hOk.backend.submitCount, 1);
      expect(schedule.entries, isNotEmpty);

      // 用户取消验证码
      final hCancel = _Harness(captchaHandler: (state) async => null);
      await hCancel.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      hCancel.backend.fetchBehavior = (call, termId) async => throw expired();
      hCancel.backend.loginBehavior = (call, credentials) async =>
          const CaptchaState(
            continuationId: 'c1',
            imageBase64: 'iVBORw0KGgo=',
            mimeType: 'image/png',
          );

      await expectLater(
        hCancel.service.getSchedule(),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.captchaRequired,
          ),
        ),
      );
      expect(hCancel.backend.importCount, 1);
      expect(hCancel.backend.submitCount, 0);
    });
  });

  group('调试数据、阶段回调与多接口重登', () {
    test('onRequest 请求记录、原始课表透出及重登阶段回调一致性', () async {
      final h = _Harness();
      final stages = <String>[];
      h.service.onStage = stages.add;
      h.backend.lastScheduleRawBody = '{"kbList":[{"kcmc":"x"}]}';
      h.backend.lastScheduleRows = <Map<String, dynamic>>[
        <String, dynamic>{'kcmc': 'x', 'xqj': '1'},
      ];

      // Cookie 有效时不触发 relogin 阶段，且透出原始课表并注入 onRequest
      await h.service.getSchedule();
      expect(stages, isEmpty);
      expect(h.service.lastScheduleRawBody, '{"kbList":[{"kcmc":"x"}]}');
      expect(h.service.lastScheduleRows.single['kcmc'], 'x');
      expect(h.config?.onRequest, isNotNull);

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

      // 课表、考试、成绩遇 Cookie 失效重登时按序触发阶段回调
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var fetchCall = 0;
      h.backend.fetchBehavior = (call, termId) async {
        if (++fetchCall == 1) throw expired();
        return sampleSchedule();
      };
      await h.service.getSchedule();
      expect(stages, [
        ScheduleService.stageRelogin,
        ScheduleService.stageReloginFinished,
        ScheduleService.stageFetchingSchedule,
      ]);

      stages.clear();
      var examsCall = 0;
      h.backend.examsBehavior = (call, termId) async {
        if (++examsCall == 1) throw expired();
        return const <ExamItem>[];
      };
      await h.service.fetchExams();
      expect(stages, [
        ScheduleService.stageRelogin,
        ScheduleService.stageReloginFinished,
      ]);
    });

    test('登录与退出：signIn（直接或经验证码，remember=true/false）与 signOut 清理', () async {
      final h = _Harness();
      final state = await h.service.signIn('20240001', 'pw');
      expect(state, isA<AuthenticatedState>());
      final saved = await h.credentials.get(_Harness.accountKey);
      expect(saved?.username, '20240001');
      expect(saved?.password, 'pw');
      expect(h.storage.saveCount, 1);

      await h.service.signOut(forgetCredentials: true);
      expect(h.storage.clearCount, 1);
      expect(await h.credentials.has(_Harness.accountKey), isFalse);

      // remember=false 不写安全存储，但仍落盘 Cookie
      await h.service.signIn('20240001', 'pw', remember: false);
      expect(await h.credentials.has(_Harness.accountKey), isFalse);
      expect(h.storage.saveCount, 2);

      // 经验证码完成 signIn 后仍按 remember 规则保存凭据与 accountHint
      final hCaptcha = _Harness();
      hCaptcha.backend.loginBehavior = (call, credentials) async =>
          const CaptchaState(
            continuationId: 'c1',
            imageBase64: 'iVBORw0KGgo=',
            mimeType: 'image/png',
          );
      expect(
        await hCaptcha.service.signIn('20240001', 'pw'),
        isA<CaptchaState>(),
      );
      expect(await hCaptcha.credentials.has(_Harness.accountKey), isFalse);
      expect(
        await hCaptcha.service.submitCaptcha('1234'),
        isA<AuthenticatedState>(),
      );
      expect(
        (await hCaptcha.credentials.get(_Harness.accountKey))?.password,
        'pw',
      );
      expect(hCaptcha.service.accountHint, '20240001');
    });

    test(
      'fetchTerms / fetchExams / fetchGrades 遇 Cookie 失效均走自动重登并落盘新 Cookie',
      () async {
        final h = _Harness(autoLoginLimit: 5);
        await h.credentials.save(
          _Harness.accountKey,
          const Credentials('20240001', 'pw'),
        );

        var termsCall = 0;
        h.backend.termsBehavior = (call) async {
          if (++termsCall == 1) throw expired();
          return const Terms(
            currentId: '2026-2027-1',
            items: <Term>[Term(id: '2026-2027-1', name: '当前学期')],
          );
        };
        var examsCall = 0;
        h.backend.examsBehavior = (call, termId) async {
          if (++examsCall == 1) throw expired();
          return sampleExams();
        };
        var gradesCall = 0;
        h.backend.gradesBehavior = (call, termId) async {
          if (++gradesCall == 1) throw expired();
          return sampleGrades();
        };

        expect((await h.service.fetchTerms()).currentId, '2026-2027-1');
        expect(await h.service.fetchExams(), isNotEmpty);
        expect(await h.service.fetchGrades(), isNotEmpty);
        expect(h.backend.loginCount, 3);
        expect(h.storage.snapshot!.cookies.single.value, 'fresh');
      },
    );

    test('冷启动快照无用户名时靠 accountHint 拼出凭据 key；未设置则无法重登', () async {
      // 未设 accountHint：取不到凭据
      final hMissing = _Harness(
        backend: FakeBackend(studentId: '', studentName: ''),
        storage: FakeSessionRepository(snapshotOf(_baseUrl)),
      );
      await hMissing.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      hMissing.backend.fetchBehavior = (call, termId) async => throw expired();
      await hMissing.service.bootstrap();

      await expectLater(
        hMissing.service.getSchedule(),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.sessionExpired)
              .having((e) => e.message, 'message', contains('没有保存账号密码')),
        ),
      );
      expect(hMissing.backend.loginCount, 0);

      // 设置 accountHint：自动重登成功
      final hHint = _Harness(
        backend: FakeBackend(studentId: '', studentName: ''),
        storage: FakeSessionRepository(snapshotOf(_baseUrl)),
      );
      await hHint.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      hHint.backend.fetchBehavior = (call, termId) async {
        if (call == 1) throw expired();
        return sampleSchedule(termId ?? '2026-2027-1');
      };
      hHint.service.accountHint = '20240001';
      await hHint.service.bootstrap();

      final schedule = await hHint.service.getSchedule();
      expect(schedule.entries, isNotEmpty);
      expect(hHint.backend.loginCount, 1);
    });
  });

  group('全局阻塞互斥锁与并发安全', () {
    test('重登进行中到达的新查询被阻塞等待：重登成功则继续查询，失败则一同抛错不盲发请求', () async {
      // 1. 重登成功分支
      final hOk = _Harness();
      await hOk.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var examsCall = 0;
      hOk.backend.examsBehavior = (call, termId) async {
        if (++examsCall == 1) throw expired();
        return sampleExams();
      };
      final loginCompleter = Completer<void>();
      hOk.backend.loginBehavior = (call, credentials) async {
        await loginCompleter.future;
        hOk.backend.cookies = snapshotOf(_baseUrl, value: 'fresh');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      final examsFuture = hOk.service.fetchExams();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(hOk.service.reloginFlightForTest, isNotNull);

      final gradesFuture = hOk.service.fetchGrades();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(hOk.backend.gradesCount, 0);

      loginCompleter.complete();
      expect(await examsFuture, isNotEmpty);
      expect(await gradesFuture, isNotEmpty);
      expect(hOk.backend.loginCount, 1);
      expect(hOk.backend.gradesCount, 1);

      // 2. 重登失败分支
      final hFail = _Harness();
      await hFail.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      hFail.backend.examsBehavior = (call, termId) async => throw expired();
      final failCompleter = Completer<void>();
      hFail.backend.loginBehavior = (call, credentials) async {
        await failCompleter.future;
        throw badCredentials();
      };

      final failExams = hFail.service.fetchExams();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      final failGrades = hFail.service.fetchGrades();
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(hFail.backend.gradesCount, 0);

      failCompleter.complete();
      await expectLater(failExams, throwsA(isA<AcademicError>()));
      await expectLater(failGrades, throwsA(isA<AcademicError>()));
      expect(hFail.backend.gradesCount, 0);
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
      await h.service.signOut();

      loginCompleter.complete();
      await expectLater(examsFuture, throwsA(isA<AcademicError>()));
      expect(await h.storage.load(), isNull);
    });

    test('并发查询初始化共享同一个 backend 创建任务，且手动 signIn 等待进行中的自动重登', () async {
      final h = _Harness();
      final initResults = await Future.wait<dynamic>(<Future<dynamic>>[
        h.service.fetchTerms(),
        h.service.fetchExams(),
        h.service.fetchGrades(),
      ]);
      expect(initResults, hasLength(3));
      expect(h.backend.termsCount, 1);

      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      var examsCall = 0;
      h.backend.examsBehavior = (call, termId) async {
        if (++examsCall == 1) throw expired();
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

      final signInFuture = h.service.signIn('20240001', 'new-pw');
      await Future<void>.delayed(const Duration(milliseconds: 10));
      expect(h.backend.loginCount, 1);

      loginCompleter.complete();
      await examsFuture;
      expect(await signInFuture, isA<AuthenticatedState>());
    });
  });

  group('精细化熔断保护（网络波动不计次、密码错立刻熔断、健康重登清零、并发去重）', () {
    test('自动重登遇到网络/超时/5xx/403 波动不消耗熔断额度，网络恢复后仍可正常自动重登', () async {
      final h = _Harness(autoLoginLimit: 1);
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );

      final transientErrors = <AcademicError>[
        const AcademicError(ErrorCode.networkRetryable, '网络不可达'),
        const AcademicError(ErrorCode.timeout, '请求超时'),
        const AcademicError(ErrorCode.serverError, '服务端异常', httpStatus: 503),
        const AcademicError(
          ErrorCode.accessForbidden,
          '禁止外网访问',
          httpStatus: 403,
        ),
      ];

      h.backend.fetchBehavior = (call, termId) async => throw expired();
      for (final err in transientErrors) {
        h.backend.loginBehavior = (call, credentials) async => throw err;
        await expectLater(
          h.service.getSchedule(),
          throwsA(isA<AcademicError>().having((e) => e.code, 'code', err.code)),
        );
        expect(h.service.breakerOpen, isFalse);
      }

      // 网络恢复：仍允许自动重登且成功
      var fetchStep = 0;
      h.backend.fetchBehavior = (call, termId) async {
        if (++fetchStep == 1) throw expired();
        return sampleSchedule();
      };
      h.backend.loginBehavior = (call, credentials) async {
        h.backend.cookies = snapshotOf(_baseUrl, value: 'recovered');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      final schedule = await h.service.getSchedule();
      expect(schedule.entries, isNotEmpty);
      expect(h.service.breakerOpen, isFalse);
    });

    test('自动重登遇到 INVALID_CREDENTIALS（密码错误）立即打开熔断，绝不再自动试错防锁号', () async {
      final h = _Harness(autoLoginLimit: 2);
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'wrong-pw'),
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
      expect(h.backend.loginCount, 1);
      expect(h.service.breakerOpen, isTrue);

      // 再次触发：直接被熔断拦截，不再请求 login
      await expectLater(
        h.service.getSchedule(),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.sessionExpired)
              .having((e) => e.message, 'message', contains('自动登录次数过多')),
        ),
      );
      expect(h.backend.loginCount, 1);
    });

    test('单次自动重登且紧接着业务请求成功会清空失败计数，不误伤后续正常重登', () async {
      final h = _Harness(autoLoginLimit: 1);
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );

      // 连续 3 轮：每轮都是会话过期 → 自动重登成功 → 紧接着查课表成功
      for (var round = 1; round <= 3; round++) {
        var step = 0;
        h.backend.fetchBehavior = (call, termId) async {
          if (++step == 1) throw expired();
          return sampleSchedule('2026-2027-$round');
        };
        h.backend.loginBehavior = (call, credentials) async {
          h.backend.cookies = snapshotOf(_baseUrl, value: 'ok-$round');
          return const AuthenticatedState(studentId: '1', studentName: 'n');
        };
        final schedule = await h.service.getSchedule();
        expect(schedule.termId, '2026-2027-$round');
        expect(h.service.breakerOpen, isFalse);
      }
      expect(h.backend.loginCount, 3);
    });

    test('并发考试与成绩共享同一次重登后若均立即再过期，按重登世代去重仅计 1 次失败', () async {
      final h = _Harness(autoLoginLimit: 2);
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      h.backend.examsBehavior = (call, termId) async => throw expired();
      h.backend.gradesBehavior = (call, termId) async => throw expired();
      h.backend.loginBehavior = (call, credentials) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        h.backend.cookies = snapshotOf(_baseUrl, value: 'loop-$call');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };

      // 第 1 轮：考试与成绩并发都撞过期、共享 1 次重登、重登后仍均报过期 → 去重只计 1 次
      await Future.wait<void>(<Future<void>>[
        expectLater(h.service.fetchExams(), throwsA(isA<AcademicError>())),
        expectLater(h.service.fetchGrades(), throwsA(isA<AcademicError>())),
      ]);
      expect(h.backend.loginCount, 1);
      expect(h.service.breakerOpen, isFalse);

      // 第 2 轮：仍允许尝试第 2 次重登（未因并发被错误算成 2 次而提前熔断）
      await expectLater(h.service.fetchExams(), throwsA(isA<AcademicError>()));
      expect(h.backend.loginCount, 2);
      expect(h.service.breakerOpen, isFalse);

      // 第 3 轮：达到 2 次上限，正式熔断拦截
      await expectLater(
        h.service.fetchExams(),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.sessionExpired)
              .having((e) => e.message, 'message', contains('自动登录次数过多')),
        ),
      );
      expect(h.backend.loginCount, 2);
      expect(h.service.breakerOpen, isTrue);
    });

    test('switchSchool 指向同校但大小写或末尾斜杠（含多斜杠）不同时更新 baseUrl 且保留现有会话', () async {
      final h = _Harness(baseUrl: 'https://JW.Example.Edu.Cn/jwglxt');
      await h.service.getSchedule();
      expect(h.service.hasCookies, isTrue);

      h.service.switchSchool('https://jw.example.edu.cn/jwglxt///');
      expect(h.service.baseUrl, 'https://jw.example.edu.cn/jwglxt///');
      expect(h.service.hasCookies, isTrue);
      expect(sameSchool(h.service.baseUrl, _baseUrl), isTrue);
      expect(
        buildAccountKey(h.service.baseUrl, '20240001'),
        'https://jw.example.edu.cn/jwglxt|20240001',
      );
    });

    test('http 登录后同校切换至 https 时仍可读取已保存凭据，且 signOut 连同旧 http 凭据一并清理', () async {
      const httpUrl = 'http://jwglxt.qust.edu.cn/jwglxt';
      const httpsUrl = 'https://jwglxt.qust.edu.cn/jwglxt';
      final h = _Harness(baseUrl: httpUrl);

      await h.service.signIn('20240001', 'pw_http', remember: true);
      expect(await h.credentials.has('$httpUrl|20240001'), isTrue);

      // 模拟历史末尾斜杠遗留键一并存在时也应被 signOut 清理。
      await h.credentials.save(
        '$httpUrl/|20240001',
        const Credentials('20240001', 'pw_http_slash'),
      );

      h.service.switchSchool(httpsUrl);
      expect(h.service.baseUrl, httpsUrl);

      final saved = await h.service.readSavedCredentials();
      expect(saved?.username, '20240001');
      expect(saved?.password, 'pw_http');

      await h.service.signOut(forgetCredentials: true);
      expect(await h.credentials.has('$httpUrl|20240001'), isFalse);
      expect(await h.credentials.has('$httpUrl/|20240001'), isFalse);
      expect(await h.credentials.has('$httpsUrl|20240001'), isFalse);
    });

    test('默认 10 分钟 3 次熔断 + 严格白名单计次（劫持/页面残缺/验证异常/取消验证码均不计次）', () async {
      final credentials = InMemoryCredentialStore();
      await credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      final backend = FakeBackend();
      final service = ScheduleService(
        credentials: credentials,
        cookieStorage: FakeSessionRepository(),
        captchaHandler: (_) async => null,
        baseUrl: _baseUrl,
        backendFactory: (_) => backend,
      );
      expect(service.autoLoginLimit, 3);

      // 1. 各类非真认证失败 + 取消验证码连续触发多次，均不得消耗熔断次数
      backend.fetchBehavior = (_, _) async => throw expired();
      final nonAuthErrors = <AcademicError>[
        const AcademicError(ErrorCode.untrustedUrl, '校园网未认证跳转'),
        const AcademicError(ErrorCode.pageChanged, '弱网返回残缺登录页'),
        const AcademicError(ErrorCode.validationFailed, '登录响应无法验证'),
        const AcademicError(ErrorCode.staleContext, '上下文过期'),
      ];
      for (final err in nonAuthErrors) {
        backend.loginBehavior = (_, _) async => throw err;
        await expectLater(
          service.getSchedule(),
          throwsA(isA<AcademicError>().having((e) => e.code, 'code', err.code)),
        );
        expect(service.breakerOpen, isFalse);
      }

      // 用户在验证码页主动取消 4 次也不得熔断
      backend.loginBehavior = (_, _) async => const CaptchaState(
        continuationId: 'c-cancel',
        imageBase64: 'iVBORw0KGgo=',
        mimeType: 'image/png',
      );
      for (var i = 0; i < 4; i++) {
        await expectLater(
          service.getSchedule(),
          throwsA(
            isA<AcademicError>().having(
              (e) => e.code,
              'code',
              ErrorCode.captchaRequired,
            ),
          ),
        );
        expect(service.breakerOpen, isFalse);
      }

      // 2. 真实认证失败（重登后紧接再过期）需累计满 3 次才打开熔断
      backend.loginBehavior = (call, _) async {
        backend.cookies = snapshotOf(_baseUrl, value: 'loop-$call');
        return const AuthenticatedState(
          studentId: '20240001',
          studentName: 'n',
        );
      };
      final loginsBeforeLoop = backend.loginCount;
      for (var round = 1; round <= 3; round++) {
        await expectLater(
          service.getSchedule(),
          throwsA(
            isA<AcademicError>().having(
              (e) => e.code,
              'code',
              ErrorCode.sessionExpired,
            ),
          ),
        );
        expect(backend.loginCount, loginsBeforeLoop + round);
        expect(service.breakerOpen, isFalse);
      }

      // 第 4 次被熔断拦截，不再请求 login
      await expectLater(
        service.getSchedule(),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.sessionExpired)
              .having((e) => e.message, 'message', contains('自动登录次数过多')),
        ),
      );
      expect(backend.loginCount, loginsBeforeLoop + 3);
      expect(service.breakerOpen, isTrue);
    });

    test('并发时间差防重复重登：慢半拍旧请求见会话版本号已升级直接复用新凭证重试', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );

      final slowExamGate = Completer<void>();
      var scheduleCall = 0;
      h.backend.fetchBehavior = (_, _) async {
        if (++scheduleCall == 1) throw expired();
        return sampleSchedule();
      };
      var examsCall = 0;
      h.backend.examsBehavior = (_, _) async {
        if (++examsCall == 1) {
          // 模拟带着旧凭证在路上慢半拍，等课表重登彻底结束后才返回旧过期错
          await slowExamGate.future;
          throw expired();
        }
        return sampleExams();
      };

      // 同时出发
      final scheduleFuture = h.service.getSchedule();
      final examsFuture = h.service.fetchExams();

      // 等课表完成重登并拿到新凭证
      expect((await scheduleFuture).entries, isNotEmpty);
      expect(h.backend.loginCount, 1);
      expect(h.service.reloginFlightForTest, isNull);

      // 放行慢半拍的考试旧请求：它返回过期错后应检测到会话版本号已升级，直接复用新凭证重试，绝不二次登录
      slowExamGate.complete();
      expect(await examsFuture, isNotEmpty);
      expect(h.backend.loginCount, 1);
      expect(h.backend.examsCount, 2);
      expect(h.backend.cookies.cookies.single.value, 'fresh');
    });

    test('静默重登不广播 relogin；若半路有可见任务加入等待则立即升格广播，结束自行摘牌', () async {
      final h = _Harness();
      await h.credentials.save(
        _Harness.accountKey,
        const Credentials('20240001', 'pw'),
      );
      final stages = <String>[];
      h.service.onStage = stages.add;

      // 1. 纯静默请求（reportReloginStage: false）重登全程不发任何阶段回调
      var examsCall = 0;
      h.backend.examsBehavior = (_, _) async {
        if (++examsCall == 1) throw expired();
        return sampleExams();
      };
      await h.service.fetchExams(null, false);
      expect(h.backend.loginCount, 1);
      expect(stages, isEmpty);

      // 2. 静默请求先触发重登，半路课表可见请求加入等待 → 立即升格广播 relogin，结束自行广播 relogin_finished
      final loginGate = Completer<void>();
      h.backend.loginBehavior = (_, _) async {
        await loginGate.future;
        h.backend.cookies = snapshotOf(_baseUrl, value: 'fresh-2');
        return const AuthenticatedState(studentId: '1', studentName: 'n');
      };
      examsCall = 0;
      final silentFuture = h.service.fetchExams(null, false);
      await Future<void>.delayed(Duration.zero);
      expect(h.service.reloginFlightForTest, isNotNull);
      expect(stages, isEmpty);

      final visibleSchedule = h.service.getSchedule();
      await Future<void>.delayed(Duration.zero);
      expect(stages, [ScheduleService.stageRelogin]);

      loginGate.complete();
      await Future.wait<dynamic>(<Future<dynamic>>[
        silentFuture,
        visibleSchedule,
      ]);
      expect(stages, [
        ScheduleService.stageRelogin,
        ScheduleService.stageReloginFinished,
        ScheduleService.stageFetchingSchedule,
      ]);
    });
  });
}
