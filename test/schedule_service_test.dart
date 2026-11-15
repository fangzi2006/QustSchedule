/// 编排层测试：需求 1（保存后免密取课表）与需求 2（失效自动重登）。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/schedule_service.dart';
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

    test('重登被拒或重登后重试仍失败时回滚旧 Cookie 并原样上抛错误', () async {
      // 场景 A：重登被拒（密码已改）
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

      // 场景 B：重登成功但重试仍失败（页面结构变化）
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
      expect(h2.backend.importCount, 1);
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
        ScheduleService.stageFetchingSchedule,
      ]);

      stages.clear();
      var examsCall = 0;
      h.backend.examsBehavior = (call, termId) async {
        if (++examsCall == 1) throw expired();
        return const <ExamItem>[];
      };
      await h.service.fetchExams();
      expect(stages, contains(ScheduleService.stageRelogin));
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
}
