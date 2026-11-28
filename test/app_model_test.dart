/// AppModel 的周次、学期、缓存、调课与静默同步逻辑测试。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/academic_cache.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_cache.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/school.dart';
import 'package:qustschedule/src/term_calendar.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:qustschedule/src/updater/update_models.dart';
import 'package:qustschedule/src/updater/update_service.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';

const String _baseUrl = 'https://jw.example.edu.cn/jwglxt';

Schedule scheduleWithWeeks(List<int> weeks) => Schedule(
  termId: '2026-2027-1',
  maxWeeks: 25,
  entries: <ScheduleEntry>[
    for (final week in weeks)
      ScheduleEntry(
        id: 'w$week',
        name: '第$week周课',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: <int>[week],
      ),
  ],
);

Terms termsWith(int count) => Terms(
  currentId: '2026-2027-1',
  items: <Term>[
    for (var index = 0; index < count; index++)
      Term(
        id: '2026-2027-${index + 1}',
        name: '学期 $index',
        year: 2026,
        semester: (index % 2) + 1,
      ),
  ],
);

({AppModel model, FakeBackend backend, InMemoryCredentialStore credentials})
buildRig({Preferences? preferences, FakeBackend? backend}) {
  final fake = backend ?? FakeBackend();
  final credentials = InMemoryCredentialStore();
  final model = AppModel(
    service: ScheduleService(
      credentials: credentials,
      cookieStorage: FakeSessionRepository(),
      backendFactory: (_) => fake,
      baseUrl: _baseUrl,
    ),
    preferences: preferences ?? Preferences.inMemory(),
    examCache: InMemoryExamCache(),
    gradesCache: InMemoryGradesCache(),
    schoolBaseUrl: _baseUrl,
  );
  return (model: model, backend: fake, credentials: credentials);
}

AppModel buildModel({Preferences? preferences}) =>
    buildRig(preferences: preferences).model;

AppModel bootRig({
  FakeBackend? backend,
  FakeSessionRepository? repository,
  FakeScheduleCache? cache,
  Preferences? preferences,
  ExamCache? examCache,
  GradesCache? gradesCache,
}) {
  final fake = backend ?? FakeBackend();
  final repo = repository ?? FakeSessionRepository();
  return AppModel(
    service: ScheduleService(
      credentials: InMemoryCredentialStore(),
      cookieStorage: repo,
      backendFactory: (_) => fake,
      baseUrl: _baseUrl,
    ),
    repository: repo,
    preferences: preferences ?? Preferences.inMemory(),
    scheduleCache: cache ?? FakeScheduleCache(),
    examCache: examCache ?? InMemoryExamCache(),
    gradesCache: gradesCache ?? InMemoryGradesCache(),
    schoolBaseUrl: _baseUrl,
  );
}

void main() {
  group('账号本地记忆与会话生命周期', () {
    test('冷启动直接从本地记忆与缓存恢复学号与姓名，不发起多余网络请求', () async {
      // 无缓存无会话时停在 needLogin，但能读出本地记住的学号
      final prefsOnlyId = Preferences.inMemory(
        lastAccounts: <String, String>{_baseUrl: '20240001'},
      );
      final modelNoCache = bootRig(preferences: prefsOnlyId);
      addTearDown(modelNoCache.dispose);
      await modelNoCache.boot();
      expect(modelNoCache.status, AppStatus.needLogin);
      expect(modelNoCache.studentId, '20240001');

      // 有课表缓存且本地已记住学号与姓名时，冷启动无需调 checkSession
      final prefsFull = Preferences.inMemory(
        lastAccounts: <String, String>{_baseUrl: '20240001'},
        lastStudentNames: <String, String>{_baseUrl: '张三'},
      );
      final cache = FakeScheduleCache(
        CachedSchedule(
          baseUrl: _baseUrl,
          schedule: sampleSchedule(),
          fetchedAt: DateTime.now(),
        ),
      );
      final backend = FakeBackend(studentId: '', studentName: '');
      final modelCached = bootRig(
        preferences: prefsFull,
        cache: cache,
        backend: backend,
      );
      addTearDown(modelCached.dispose);

      await modelCached.boot();
      expect(modelCached.studentId, '20240001');
      expect(modelCached.studentName, '张三');
      expect(backend.checkSessionCount, 0);
    });

    test('登录成功后记住账号与姓名，退出登录一并清空账号、姓名、课表缓存与学业状态', () async {
      final prefs = Preferences.inMemory();
      final cache = FakeScheduleCache(
        CachedSchedule(
          baseUrl: _baseUrl,
          schedule: sampleSchedule(),
          fetchedAt: DateTime.now(),
        ),
      );
      final model = bootRig(preferences: prefs, cache: cache);
      addTearDown(model.dispose);

      await model.signIn('20240001', 'pw');
      expect(prefs.accountOf(_baseUrl), '20240001');
      expect(prefs.studentNameOf(_baseUrl), '测试学生');
      expect(model.studentId, '20240001');
      expect(model.studentName, '测试学生');

      model.hydrateForTest(
        schedule: sampleSchedule(),
        exams: [ExamItem(courseName: '测试考试', startTime: DateTime(2026, 1, 1))],
        grades: const [
          GradeItem(courseName: '测试课程', credit: 2.0, rawScore: '85'),
        ],
        isNotEvaluated: true,
      );

      await model.signOut();
      expect(prefs.accountOf(_baseUrl), isEmpty);
      expect(prefs.studentNameOf(_baseUrl), isEmpty);
      expect(model.studentId, isEmpty);
      expect(model.studentName, isEmpty);
      expect(cache.clearCount, 1);
      expect(cache.cached, isNull);
      expect(model.academicTermId, isEmpty);
      expect(model.exams, isEmpty);
      expect(model.grades, isEmpty);
      expect(model.isNotEvaluated, isFalse);
    });

    test('冷启动遇到会话过期：用本地记住的账号 + 保存的密码自动重登', () async {
      final credentials = InMemoryCredentialStore();
      await credentials.save(
        '$_baseUrl|20240001',
        const Credentials('20240001', 'pw'),
      );
      final prefs = Preferences.inMemory(
        lastAccounts: <String, String>{_baseUrl: '20240001'},
      );
      final repo = FakeSessionRepository(snapshotOf(_baseUrl));
      final backend = FakeBackend(studentId: '', studentName: '')
        ..fetchBehavior = (call, termId) async {
          if (call == 1) {
            throw const AcademicError(ErrorCode.sessionExpired, '登录已失效');
          }
          return sampleSchedule(termId ?? '2026-2027-1');
        };
      final model = AppModel(
        service: ScheduleService(
          credentials: credentials,
          cookieStorage: repo,
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        repository: repo,
        preferences: prefs,
        scheduleCache: FakeScheduleCache(),
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(model.dispose);

      await model.boot();
      expect(backend.loginCount, 1);
      expect(model.schedule?.entries, isNotEmpty);
      expect(model.studentId, isNotEmpty);
    });
  });

  group('周次、校历校准与全局节数', () {
    test('maxWeek 默认保底 18、超出 18 自动扩充、goToWeek 边界夹取与 weekEntries 按周过滤', () {
      final model = buildModel();
      addTearDown(model.dispose);

      model.hydrateForTest(
        schedule: scheduleWithWeeks(<int>[1, 5, 17]),
        week: 5,
      );
      expect(model.maxWeek, 18);
      expect(model.weekEntries.map((e) => e.name), <String>['第5周课']);

      model.goToWeek(0);
      expect(model.week, 1);
      model.goToWeek(99);
      expect(model.week, 18);

      model.hydrateForTest(
        schedule: scheduleWithWeeks(<int>[1, 5, 21]),
        week: 5,
      );
      expect(model.maxWeek, 21);

      model.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 25,
          entries: <ScheduleEntry>[],
        ),
      );
      expect(model.maxWeek, 18);
    });

    test('开学日默认按学期估算，calibrateCurrentWeek 校准持久化，resetCalendar 恢复估算', () async {
      final prefs = Preferences.inMemory();
      final model = buildModel(preferences: prefs);
      addTearDown(model.dispose);
      model.hydrateForTest(
        schedule: scheduleWithWeeks(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
        terms: termsWith(4),
      );

      final estimated = model.termStart;
      expect(estimated, isNotNull);
      expect(estimated!.weekday, DateTime.monday);
      expect(estimated.month, greaterThanOrEqualTo(8));

      await model.calibrateCurrentWeek(22);
      expect(model.currentWeekOfToday, 22);
      expect(model.maxWeek, 22);
      final saved = prefs.termStartOf('2026-2027-1');
      expect(saved, isNotNull);
      expect(weekOf(saved!, DateTime.now()), 22);

      await model.resetCalendar();
      expect(model.currentWeekOfToday, isNot(22));
      expect(model.maxWeek, 18);
      expect(prefs.termStartOf('2026-2027-1'), isNotNull);
    });

    test('分段节数变更同步网格与时间轴，课程节次超出配置时 gridSectionCount 自动托底', () async {
      final rig = buildRig();
      addTearDown(rig.model.dispose);
      rig.model.hydrateForTest(schedule: scheduleWithWeeks(<int>[1]));

      expect(rig.model.sectionCount, 10);
      expect(rig.model.gridSectionCount, 10);
      expect(rig.model.startLabelOf(10), isNotEmpty);

      await rig.model.setSectionCounts(<PeriodGroup, int>{
        PeriodGroup.morning: 5,
        PeriodGroup.afternoon: 5,
        PeriodGroup.evening: 2,
      });
      expect(rig.model.sectionCount, 12);
      expect(rig.model.gridSectionCount, 12);
      expect(rig.model.activeSections, hasLength(12));
      expect(rig.model.startLabelOf(12), isNotEmpty);

      // 课程节次超出配置时 gridSectionCount 取大值不丢课
      rig.model.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: <ScheduleEntry>[
            ScheduleEntry(
              id: 'x',
              name: '晚课',
              day: 1,
              startPeriod: 12,
              endPeriod: 13,
              weeks: <int>[1],
            ),
          ],
        ),
      );
      await rig.model.setSectionCounts(<PeriodGroup, int>{
        PeriodGroup.morning: 4,
        PeriodGroup.afternoon: 4,
        PeriodGroup.evening: 2,
      });
      expect(rig.model.sectionCount, 10);
      expect(rig.model.gridSectionCount, 13);
      expect(rig.model.hasSectionsBeyondTimetable, isTrue);
    });
  });

  group('后台刷新、首次加载与身份补齐', () {
    test('后台刷新期间保持 ready、支持手动关闭提示，失败时保留旧课表提示错误，旧学期自动升级到新学期', () async {
      final rig = buildRig();
      addTearDown(rig.model.dispose);
      rig.model.hydrateForTest(schedule: sampleSchedule('2025-2026-2'));
      expect(rig.model.termId, '2025-2026-2');

      final completer = Completer<Schedule>();
      rig.backend.fetchBehavior = (call, termId) {
        expect(termId, isNull);
        return completer.future;
      };

      final pending = rig.model.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(rig.model.status, AppStatus.ready);
      expect(rig.model.refreshing, isTrue);
      expect(rig.model.hint, '更新中...');
      expect(rig.model.schedule, isNotNull);

      rig.model.clearHint();
      expect(rig.model.hint, isEmpty);

      completer.complete(sampleSchedule('2026-2027-1'));
      await pending;
      expect(rig.model.refreshing, isFalse);
      expect(rig.model.termId, '2026-2027-1');
      expect(rig.model.hint, '已更新');

      // 刷新失败保留旧课表并提示错误
      rig.backend.fetchBehavior = (call, termId) async => throw pageChanged();
      await rig.model.refresh();
      expect(rig.model.status, AppStatus.ready);
      expect(rig.model.schedule, isNotNull);
      expect(rig.model.hintIsError, isTrue);
      expect(rig.model.hint, contains('更新失败'));
    });

    test('重登刷新时提示先切到正在重新登录，登录完切回更新中，取回后已更新', () async {
      final rig = buildRig();
      addTearDown(rig.model.dispose);
      rig.model.hydrateForTest(schedule: sampleSchedule());
      rig.model.username = '20240001';
      rig.model.service.accountHint = '20240001';
      await rig.credentials.save(
        '$_baseUrl|20240001',
        const Credentials('20240001', 'pw'),
      );
      final loginCompleter = Completer<AuthState>();
      final scheduleCompleter = Completer<Schedule>();
      final hints = <String>[];
      rig.model.hints.addListener(() {
        if (rig.model.hint.isNotEmpty &&
            (hints.isEmpty || hints.last != rig.model.hint)) {
          hints.add(rig.model.hint);
        }
      });

      rig.backend.fetchBehavior = (call, termId) {
        if (call == 1) throw expired();
        return scheduleCompleter.future;
      };
      rig.backend.loginBehavior = (call, creds) => loginCompleter.future;

      final pending = rig.model.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(hints, contains('正在重新登录...'));

      loginCompleter.complete(
        const AuthenticatedState(studentId: '20240001', studentName: '张三'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(hints.last, '更新中...');

      scheduleCompleter.complete(sampleSchedule());
      await pending;
      expect(rig.model.hint, '已更新');
    });

    test('首次加载走 loading 与获取中提示；失败进入 failed，dismissError 无课表回 needLogin、有旧课表回 ready', () async {
      final rig = buildRig();
      addTearDown(rig.model.dispose);
      final completer = Completer<Schedule>();
      rig.backend.fetchBehavior = (call, termId) => completer.future;

      final pending = rig.model.loadScheduleForTest();
      await Future<void>.delayed(Duration.zero);
      expect(rig.model.status, AppStatus.loading);
      expect(rig.model.hint, '获取中...');
      expect(rig.model.refreshing, isTrue);

      completer.complete(sampleSchedule());
      await pending;
      expect(rig.model.status, AppStatus.ready);
      expect(rig.model.hint, isEmpty);
      expect(rig.model.refreshing, isFalse);

      // 有旧课表时 dismissError 退回 ready
      rig.model.setStatusForTest(
        AppStatus.failed,
        message: '出错了',
        code: 'PAGE_CHANGED',
      );
      rig.model.dismissError();
      expect(rig.model.status, AppStatus.ready);

      // 无旧课表时失败 → dismissError 回 needLogin
      final rigEmpty = buildRig();
      addTearDown(rigEmpty.model.dispose);
      rigEmpty.backend.fetchBehavior = (call, termId) async =>
          throw pageChanged();
      await rigEmpty.model.loadScheduleForTest();
      expect(rigEmpty.model.status, AppStatus.failed);
      rigEmpty.model.dismissError();
      expect(rigEmpty.model.status, AppStatus.needLogin);
    });

    test('冷启动身份补齐：缺失时调 checkSession 补齐，已知身份不重复请求，接口无返回则回退本地账号', () async {
      // 1. 缺失身份时调 checkSession 补齐
      final rig1 = buildRig(
        backend: FakeBackend(studentId: '', studentName: ''),
      );
      addTearDown(rig1.model.dispose);
      await rig1.model.loadScheduleForTest();
      expect(rig1.backend.checkSessionCount, 1);
      expect(rig1.model.studentName, '测试学生');
      expect(rig1.model.studentId, '20240001');
      expect(rig1.model.signedIn, isTrue);

      // 2. 已知身份时不重复请求
      final rig2 = buildRig();
      addTearDown(rig2.model.dispose);
      await rig2.model.loadScheduleForTest();
      expect(rig2.backend.checkSessionCount, 0);

      // 3. 接口也读不到身份时用本地 username 兜底
      final rig3 = buildRig(
        backend: FakeBackend(
          studentId: '',
          studentName: '',
          checkSessionReadsIdentity: false,
        ),
      );
      addTearDown(rig3.model.dispose);
      rig3.model.username = '20240001';
      await rig3.model.loadScheduleForTest();
      expect(rig3.model.studentId, '20240001');
      expect(rig3.model.signedIn, isTrue);
    });

    test('修改密码：通过验证后写入安全存储，被拒时抛错且不覆盖原凭据', () async {
      final rig = buildRig();
      addTearDown(rig.model.dispose);
      await rig.model.loadScheduleForTest();

      await rig.model.changePassword('brand-new-pass');
      final saved = await rig.credentials.get('$_baseUrl|20240001');
      expect(saved?.password, 'brand-new-pass');
      expect(rig.backend.loginCount, 1);

      rig.backend.loginBehavior = (call, credentials) async =>
          throw const AcademicError(ErrorCode.invalidCredentials, '用户名或密码不正确');
      await expectLater(
        rig.model.changePassword('wrong'),
        throwsA(isA<AcademicError>()),
      );
      expect(
        (await rig.credentials.get('$_baseUrl|20240001'))?.password,
        'brand-new-pass',
      );
    });

    test('修改密码：Cookie 恢复客户端且 sessionInfo.username 为空串时回退本地已保存账号', () async {
      final prefs = Preferences.inMemory();
      await prefs.setIdentityOf(
        _baseUrl,
        studentId: '20240001',
        studentName: '测试学生',
      );
      final credentials = InMemoryCredentialStore();
      await credentials.save(
        '$_baseUrl|20240001',
        const Credentials('20240001', 'old-pass'),
      );
      Credentials? recordedLogin;
      final backend = FakeBackend(
        studentId: '',
        studentName: '',
        loginBehavior: (call, creds) async {
          recordedLogin = creds;
          return const AuthenticatedState(
            studentId: '20240001',
            studentName: '测试学生',
          );
        },
      );
      final repo = FakeSessionRepository(snapshotOf(_baseUrl));
      final cache = FakeScheduleCache(
        CachedSchedule(
          baseUrl: _baseUrl,
          fetchedAt: DateTime.now(),
          schedule: sampleSchedule(),
        ),
      );
      final model = AppModel(
        service: ScheduleService(
          credentials: credentials,
          cookieStorage: repo,
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        repository: repo,
        preferences: prefs,
        scheduleCache: cache,
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(model.dispose);

      await model.boot();
      await model.refresh();

      // Cookie 有效且本地已有姓名学号时：客户端已创建，但 sessionInfo.username 仍为 ''。
      expect(model.service.sessionInfo, isNotNull);
      expect(model.service.sessionInfo!.username, isEmpty);
      expect(backend.checkSessionCount, 0);
      expect(backend.loginCount, 0);

      await model.changePassword('brand-new-pass');
      expect(recordedLogin?.username, '20240001');
      expect(recordedLogin?.password, 'brand-new-pass');
      expect(
        (await credentials.get('$_baseUrl|20240001'))?.password,
        'brand-new-pass',
      );
    });
  });

  group('教务地址簿', () {
    test('addSchool 末尾斜杠去重，removeSchool 只删地址簿不动当前会话', () async {
      final prefs = Preferences.inMemory();
      final model = buildModel(preferences: prefs);
      addTearDown(model.dispose);

      await model.addSchool('https://jw2.example.edu.cn/jwglxt');
      await model.addSchool('https://jw2.example.edu.cn/jwglxt/');
      expect(model.schools.where((item) => item.contains('jw2')).length, 1);

      final beforeCurrent = prefs.currentSchool;
      await model.removeSchool('https://jw2.example.edu.cn/jwglxt');
      expect(model.schools.any((item) => item.contains('jw2')), isFalse);
      expect(prefs.currentSchool, beforeCurrent);
    });

    test('loginPrefillUsername 优先级与退出登录清空语义', () async {
      final prefs = Preferences.inMemory(
        lastAccounts: <String, String>{
          'https://old.example.edu.cn/jwglxt': '20230001',
        },
      );
      final model = buildModel(preferences: prefs);
      addTearDown(model.dispose);

      // 当前线路未登录过时，登录页预填回退到最近一次历史账号，但不污染 studentId
      expect(model.username, isEmpty);
      expect(model.studentId, isEmpty);
      expect(model.loginPrefillUsername, '20230001');

      // 当前线路有已记账号时优先于其他线路
      await prefs.setIdentityOf(_baseUrl, studentId: '20240002');
      expect(model.loginPrefillUsername, '20240002');

      // 内存中已输入/恢复的 username 优先级最高
      model.username = '20250003';
      expect(model.loginPrefillUsername, '20250003');

      // 单校退出登录后清掉该校记录，预填回空（不留残留学号）
      final singlePrefs = Preferences.inMemory();
      final singleModel = buildModel(preferences: singlePrefs);
      addTearDown(singleModel.dispose);
      await singleModel.signIn('20240001', 'pw');
      expect(singleModel.loginPrefillUsername, '20240001');
      await singleModel.signOut();
      expect(singleModel.username, isEmpty);
      expect(singleModel.loginPrefillUsername, isEmpty);
    });

    test('旧版 schema 14 升级冷启动：自动切回内置默认地址、作废旧缓存并预填历史学号', () async {
      const legacyUrl = 'https://jwglxt1.qust.edu.cn/jwglxt';
      final legacyPrefs = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 14,
          'schools': <String>[legacyUrl],
          'currentSchool': legacyUrl,
          'lastAccounts': <String, String>{legacyUrl: '20240001'},
          'lastStudentNames': <String, String>{legacyUrl: '张三'},
        }),
      );
      final repo = FakeSessionRepository()
        ..snapshot = snapshotOf(legacyUrl, value: 'old-sid');
      final cache = FakeScheduleCache(
        CachedSchedule(
          baseUrl: legacyUrl,
          schedule: sampleSchedule(),
          fetchedAt: DateTime.now(),
        ),
      );
      final model = AppModel(
        service: ScheduleService(
          credentials: InMemoryCredentialStore(),
          cookieStorage: repo,
          backendFactory: (_) => FakeBackend(),
        ),
        repository: repo,
        preferences: legacyPrefs,
        scheduleCache: cache,
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
      );
      addTearDown(model.dispose);

      await model.boot();

      expect(model.schoolBaseUrl, defaultSchool.baseUrl);
      expect(model.status, AppStatus.needLogin);
      expect(model.schedule, isNull);
      expect(repo.snapshot, isNull);
      expect(model.studentId, isEmpty);
      expect(model.username, isEmpty);
      expect(model.loginPrefillUsername, '20240001');
    });

    test('切换线路沿用当前账号原地加载登录（不经过 needLogin/signingIn），并将账号落到新地址下', () async {
      final prefs = Preferences.inMemory();
      final model = buildModel(preferences: prefs);
      addTearDown(model.dispose);
      await model.signIn('20240001', 'pw');
      expect(model.status, AppStatus.ready);

      final seen = <AppStatus>[];
      model.addListener(() => seen.add(model.status));

      await model.changeSchool('https://jwglxt2.qust.edu.cn/jwglxt');

      expect(model.schoolBaseUrl, 'https://jwglxt2.qust.edu.cn/jwglxt');
      expect(seen, isNot(contains(AppStatus.needLogin)));
      expect(seen, isNot(contains(AppStatus.signingIn)));
      expect(seen, contains(AppStatus.loading));
      expect(model.status, AppStatus.ready);
      expect(model.username, '20240001');
      expect(model.schedule, isNotNull);
      expect(prefs.accountOf('https://jwglxt2.qust.edu.cn/jwglxt'), '20240001');
    });

    test('切换线路异常回滚：无保存密码或新线路登录失败时均保留原线路并提示错误', () async {
      // 1. 读不到保存的密码
      final modelNoPwd = buildModel();
      addTearDown(modelNoPwd.dispose);
      final beforeNoPwd = modelNoPwd.schoolBaseUrl;
      await modelNoPwd.changeSchool('https://jwglxt3.qust.edu.cn/jwglxt');
      expect(modelNoPwd.schoolBaseUrl, beforeNoPwd);
      expect(modelNoPwd.status, isNot(AppStatus.needLogin));
      expect(modelNoPwd.hintIsError, isTrue);
      expect(modelNoPwd.hint, contains('没有找到已保存的密码'));

      // 2. 新线路登录被拒
      final backend = FakeBackend();
      final rig = buildRig(backend: backend);
      addTearDown(rig.model.dispose);
      await rig.model.signIn('20240001', 'pw');
      final beforeFail = rig.model.schoolBaseUrl;
      backend.loginBehavior = (int call, Credentials credentials) async =>
          throw const AcademicError(ErrorCode.invalidCredentials, '账号或密码不正确');

      await rig.model.changeSchool('https://jwglxt6.qust.edu.cn/jwglxt');
      expect(rig.model.schoolBaseUrl, beforeFail);
      expect(rig.model.status, isNot(AppStatus.needLogin));
      expect(rig.model.message, contains('切换失败'));
    });
  });

  group('课表本地缓存与静默更新策略', () {
    test('最小间隔内直接展示缓存不联网，跨地址缓存丢弃，抓课表成功回写缓存且往返保留备注', () async {
      // 1. 最小间隔内直接展示缓存
      final fake = FakeBackend();
      final modelFresh = bootRig(
        backend: fake,
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        cache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: sampleSchedule(),
            fetchedAt: DateTime.now(),
          ),
        ),
      );
      addTearDown(modelFresh.dispose);
      await modelFresh.boot();
      expect(modelFresh.status, AppStatus.ready);
      expect(modelFresh.schedule?.entries, isNotEmpty);
      expect(fake.fetchCount, 0);

      // 2. 跨地址缓存丢弃
      final modelOtherSchool = bootRig(
        cache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: 'https://other.example.edu.cn/jwglxt',
            schedule: sampleSchedule(),
            fetchedAt: DateTime.now(),
          ),
        ),
      );
      addTearDown(modelOtherSchool.dispose);
      await modelOtherSchool.boot();
      expect(modelOtherSchool.status, AppStatus.needLogin);
      expect(modelOtherSchool.schedule, isNull);

      // 3. 抓课表成功回写缓存
      final writeCache = FakeScheduleCache();
      final modelSave = bootRig(cache: writeCache);
      addTearDown(modelSave.dispose);
      await modelSave.loadScheduleForTest();
      expect(writeCache.saveCount, 1);
      expect(writeCache.lastSaved?.baseUrl, _baseUrl);

      // 4. 缓存序列化往返保留实践/其他课程备注
      const scheduleWithRemarks = Schedule(
        termId: '2026-2027-1',
        maxWeeks: 16,
        entries: <ScheduleEntry>[
          ScheduleEntry(
            id: 'a',
            name: '高等数学',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1],
          ),
        ],
        remarks: <ScheduleRemark>[
          ScheduleRemark(
            practical: true,
            content: '生产实习',
            courseName: '金工实习',
            teacher: '王老师',
            weeks: '第18周',
            location: '东校区 车间A',
          ),
          ScheduleRemark(practical: false, content: '线上自主学习'),
        ],
      );
      final encoded = FileScheduleCache.encodeForTest(scheduleWithRemarks);
      final back = FileScheduleCache.decodeForTest(
        jsonDecode(jsonEncode(encoded)),
      );
      expect(back?.remarks, hasLength(2));
      final practical = back!.remarks.firstWhere((r) => r.practical);
      expect(practical.courseName, '金工实习');
      expect(practical.teacher, '王老师');
      expect(practical.location, '东校区 车间A');
    });

    test('超过最小间隔时冷启动静默刷新并串联学业同步；关闭开关或未达自定义间隔时不刷新，且支持间隔夹取', () async {
      // 1. 超过间隔：冷启动静默刷新并串联学业同步
      final fakeExpired = FakeBackend();
      final modelExpired = bootRig(
        backend: fakeExpired,
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        preferences: Preferences.inMemory(
          autoRefresh: true,
          autoRefreshIntervalMinutes: 30,
        ),
        cache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: sampleSchedule('2026-2027-1'),
            fetchedAt: DateTime.now().subtract(const Duration(hours: 3)),
          ),
        ),
      );
      addTearDown(modelExpired.dispose);
      await modelExpired.boot();
      await Future<void>.delayed(Duration.zero);
      expect(modelExpired.status, AppStatus.ready);
      expect(fakeExpired.fetchCount, 1);
      expect(modelExpired.academicSyncForTest, isNotNull);
      await modelExpired.academicSyncForTest;
      expect(modelExpired.exams, isNotEmpty);
      expect(modelExpired.grades, isNotEmpty);

      // 2. 关闭静默更新开关：不刷新
      final fakeDisabled = FakeBackend();
      final modelDisabled = bootRig(
        backend: fakeDisabled,
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        preferences: Preferences.inMemory(autoRefresh: false),
        cache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: sampleSchedule(),
            fetchedAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        ),
      );
      addTearDown(modelDisabled.dispose);
      await modelDisabled.boot();
      await Future<void>.delayed(Duration.zero);
      expect(fakeDisabled.fetchCount, 0);

      // 3. 自定义间隔未到期时不刷新，且 setAutoRefreshIntervalMinutes 边界夹取
      final fakeInterval = FakeBackend();
      final modelInterval = bootRig(
        backend: fakeInterval,
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        preferences: Preferences.inMemory(autoRefreshIntervalMinutes: 60),
        cache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: sampleSchedule(),
            fetchedAt: DateTime.now().subtract(const Duration(minutes: 20)),
          ),
        ),
      );
      addTearDown(modelInterval.dispose);
      await modelInterval.boot();
      await Future<void>.delayed(Duration.zero);
      expect(fakeInterval.fetchCount, 0);

      await modelInterval.setAutoRefreshIntervalMinutes(9999);
      expect(
        modelInterval.autoRefreshIntervalMinutes,
        maxAutoRefreshIntervalMinutes,
      );
      await modelInterval.setAutoRefreshIntervalMinutes(15);
      expect(
        modelInterval.autoRefreshIntervalMinutes,
        minAutoRefreshIntervalMinutes,
      );
    });
  });

  group('调课（渲染层 overlay，按日期）', () {
    test('调课增删改与非匹配规则：只改渲染不改原始数据', () async {
      final model = bootRig();
      addTearDown(model.dispose);
      model.hydrateForTest(schedule: sampleSchedule(), week: 1);

      final start = model.termStart!;
      final sat = start.add(const Duration(days: 5));
      final rule = await model.addReschedule(
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: sat.month,
        toDay: sat.day,
      );
      expect(model.schedule!.entries.single.day, 1);
      expect(model.entriesForWeek(1).single.day, 6);

      // 编辑目标日到周四，保留 id
      final thu = start.add(const Duration(days: 3));
      await model.updateReschedule(
        rule.id,
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: thu.month,
        toDay: thu.day,
      );
      expect(model.reschedules, hasLength(1));
      expect(model.reschedules.single.id, rule.id);
      expect(model.entriesForWeek(1).single.day, 4);

      // 删除调课后恢复原时间
      await model.removeReschedule(rule.id);
      expect(model.entriesForWeek(1).single.day, 1);
      expect(model.reschedules, isEmpty);

      // 未匹配到日期的规则不影响渲染
      final other = start.add(const Duration(days: 10));
      final otherTo = other.add(const Duration(days: 1));
      await model.addReschedule(
        fromMonth: other.month,
        fromDay: other.day,
        toMonth: otherTo.month,
        toDay: otherTo.day,
      );
      expect(model.entriesForWeek(1).single.day, 1);
    });

    test('跨周调课：调到目标周的课不再被同 id 的原周实例顶掉', () async {
      final model = bootRig();
      addTearDown(model.dispose);
      model.hydrateForTest(schedule: sampleSchedule(), week: 1);

      final start = model.termStart!;
      final to = start.add(const Duration(days: 9)); // 第 2 周周三
      await model.addReschedule(
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: to.month,
        toDay: to.day,
      );

      expect(model.entriesForWeek(1), isEmpty);
      final week2 = model.entriesForWeek(2);
      expect(week2.length, 2);
      expect(week2.where((e) => e.day == 3).length, 1);
      expect(week2.where((e) => e.day == 1).length, 1);
      expect(model.schedule!.entries.single.day, 1);
    });

    test('调课合并：无冲突共存，冲突时调课优先显示并记录该天被顶课程', () async {
      final model = bootRig();
      addTearDown(model.dispose);
      model.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: <ScheduleEntry>[
            ScheduleEntry(
              id: 'a',
              name: '高等数学',
              day: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: <int>[1],
            ),
            ScheduleEntry(
              id: 'b',
              name: '大学英语',
              day: 3,
              startPeriod: 1,
              endPeriod: 2,
              weeks: <int>[1],
            ),
            ScheduleEntry(
              id: 'c',
              name: '线性代数',
              day: 3,
              startPeriod: 5,
              endPeriod: 6,
              weeks: <int>[1],
            ),
          ],
        ),
        week: 1,
      );

      final start = model.termStart!;
      final wed = start.add(const Duration(days: 2));
      await model.addReschedule(
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: wed.month,
        toDay: wed.day,
      );

      final view = model.rescheduleViewFor(1);
      // 高数 (1-2) 顶掉英语 (1-2)，与线性代数 (5-6) 共存
      expect(view.entries.map((e) => e.id).toSet(), <String>{'a', 'c'});
      expect(view.hasConflictOn(3), isTrue);
      expect(view.hasConflictOn(1), isFalse);
      final conflict = view.conflicts[3]!.single;
      expect(conflict.displaced.id, 'b');
      expect(conflict.winner.id, 'a');
    });
  });

  group('回到前台与自动更新调度', () {
    final today = dayOnly(DateTime.now());
    final start = mondayOf(today).subtract(const Duration(days: 7));
    final lastWeekDay = mondayOf(today).subtract(const Duration(days: 1));

    test('onAppShown：跨天且停在当前周时自动推进并通知学业页，手翻其他周或未跨天保持原周次', () async {
      // 1. 跨天且原本停在当前周：周次跟到新的当前周，并通知学业页刷新日期
      final modelFollow = buildModel();
      addTearDown(modelFollow.dispose);
      modelFollow.hydrateForTest(
        schedule: scheduleWithWeeks(<int>[1, 2, 3]),
        week: 1,
        termStart: start,
      );
      modelFollow.seedLifecycleForTest(
        lastSeenDay: lastWeekDay,
        lastFetchedAt: DateTime.now(),
      );
      var academicNotifyCount = 0;
      modelFollow.academicNotifier.addListener(() => academicNotifyCount++);

      await modelFollow.onAppShown();
      expect(modelFollow.currentWeekOfToday, 2);
      expect(modelFollow.week, 2);
      expect(academicNotifyCount, 1);

      // 2. 跨天但用户手翻到了别的周：不被拽回当前周
      final modelManual = buildModel();
      addTearDown(modelManual.dispose);
      modelManual.hydrateForTest(
        schedule: scheduleWithWeeks(<int>[1, 2, 3]),
        week: 3,
        termStart: start,
      );
      modelManual.seedLifecycleForTest(
        lastSeenDay: lastWeekDay,
        lastFetchedAt: DateTime.now(),
      );
      await modelManual.onAppShown();
      expect(modelManual.week, 3);

      // 3. 没跨天：周次不动
      final modelSameDay = buildModel();
      addTearDown(modelSameDay.dispose);
      modelSameDay.hydrateForTest(
        schedule: scheduleWithWeeks(<int>[1, 2, 3]),
        week: 1,
        termStart: start,
      );
      modelSameDay.seedLifecycleForTest(
        lastSeenDay: today,
        lastFetchedAt: DateTime.now(),
      );
      await modelSameDay.onAppShown();
      expect(modelSameDay.week, 1);
    });

    test('静默刷新的判定：开关 / 正在刷 / 无课表 / 间隔', () {
      final now = DateTime(2026, 10, 21, 12);
      bool due({
        bool autoRefresh = true,
        bool refreshing = false,
        bool hasSchedule = true,
        DateTime? lastFetchedAt,
        int interval = 30,
      }) => AppModel.shouldRefreshOnShow(
        autoRefresh: autoRefresh,
        refreshing: refreshing,
        hasSchedule: hasSchedule,
        lastFetchedAt: lastFetchedAt,
        intervalMinutes: interval,
        now: now,
      );

      final longAgo = now.subtract(const Duration(hours: 5));
      expect(due(autoRefresh: false, lastFetchedAt: longAgo), isFalse);
      expect(due(refreshing: true, lastFetchedAt: longAgo), isFalse);
      expect(due(hasSchedule: false, lastFetchedAt: longAgo), isFalse);
      expect(due(lastFetchedAt: null), isTrue);
      expect(
        due(lastFetchedAt: now.subtract(const Duration(minutes: 29))),
        isFalse,
      );
      expect(
        due(lastFetchedAt: now.subtract(const Duration(minutes: 31))),
        isTrue,
      );
    });

    test('checkAutoUpdate：autoCheckUpdate 关闭时跳过，开启时同一会话只检查一次', () async {
      final modelOff = buildModel(
        preferences: Preferences.inMemory(autoCheckUpdate: false),
      );
      addTearDown(modelOff.dispose);
      var offInvoked = false;
      modelOff.checkAutoUpdate(
        onHasUpdate: (_) => offInvoked = true,
        initialDelay: Duration.zero,
      );
      await Future<void>.delayed(Duration.zero);
      expect(offInvoked, isFalse);
      expect(modelOff.hasCheckedAutoUpdate, isFalse);

      final modelOn = buildModel(
        preferences: Preferences.inMemory(autoCheckUpdate: true),
      );
      addTearDown(modelOn.dispose);
      var callbackCount = 0;
      final mockService = _MockUpdateService(hasUpdate: true);
      modelOn.checkAutoUpdate(
        onHasUpdate: (_) => callbackCount++,
        updateService: mockService,
        initialDelay: Duration.zero,
      );
      await Future<void>.delayed(Duration.zero);
      expect(callbackCount, 1);
      expect(modelOn.hasCheckedAutoUpdate, isTrue);

      modelOn.checkAutoUpdate(
        onHasUpdate: (_) => callbackCount++,
        updateService: mockService,
        initialDelay: Duration.zero,
      );
      await Future<void>.delayed(Duration.zero);
      expect(callbackCount, 1);
      expect(mockService.callCount, 1);
    });
  });

  group('学业学期隔离与静默同步串联', () {
    test('setAcademicTerm 隔离各学期数据，快速连续切换时旧请求晚到不得覆盖新学期数据', () async {
      final oldTermExams = Completer<List<ExamItem>>();
      final oldTermGrades = Completer<List<GradeItem>>();
      final backend = FakeBackend(
        termsBehavior: (_) async => const Terms(
          currentId: '2026-2027-1',
          items: <Term>[
            Term(
              id: '2026-2027-1',
              name: '2026-2027-1',
              year: 2026,
              semester: 1,
            ),
            Term(
              id: '2026-2027-2',
              name: '2026-2027-2',
              year: 2026,
              semester: 2,
            ),
          ],
        ),
      );
      backend.examsBehavior = (_, termId) {
        if (termId == '2026-2027-1') return oldTermExams.future;
        return Future<List<ExamItem>>.value(const <ExamItem>[
          ExamItem(courseName: '新学期考试'),
        ]);
      };
      backend.gradesBehavior = (_, termId) {
        if (termId == '2026-2027-1') return oldTermGrades.future;
        return Future<List<GradeItem>>.value(const <GradeItem>[
          GradeItem(courseName: '新学期成绩', credit: 2.0, rawScore: '95'),
        ]);
      };

      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);
      await model.signIn('20240001', 'pw');

      model.setAcademicTerm('2026-2027-1');
      await Future<void>.delayed(Duration.zero);
      model.setAcademicTerm('2026-2027-2');
      await Future<void>.delayed(const Duration(milliseconds: 20));

      oldTermExams.complete(const <ExamItem>[ExamItem(courseName: '旧学期考试')]);
      oldTermGrades.complete(const <GradeItem>[
        GradeItem(courseName: '旧学期成绩', credit: 2.0, rawScore: '80'),
      ]);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(model.academicTermId, '2026-2027-2');
      expect(model.academicLoading, isFalse);
      expect(model.exams.map((e) => e.courseName), ['新学期考试']);
      expect(model.grades.map((g) => g.courseName), ['新学期成绩']);
    });

    test('syncSilently 课表完成后异步非阻塞派发学业同步，学业完成或后台重登均保持静默不篡改课表提示', () async {
      final backend = FakeBackend();
      final academicCompleter = Completer<void>();
      var examsCall = 0;
      backend.examsBehavior = (call, termId) async {
        examsCall++;
        if (examsCall == 1) {
          throw const AcademicError(ErrorCode.sessionExpired, '会话失效');
        }
        await academicCompleter.future;
        return sampleExams();
      };
      backend.gradesBehavior = (call, termId) async {
        await academicCompleter.future;
        return sampleGrades();
      };

      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);
      await rig.credentials.save(
        '${model.service.baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      model.service.accountHint = '20240001';
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      final hints = <String>[];
      model.hints.addListener(() {
        if (model.hint.isNotEmpty &&
            (hints.isEmpty || hints.last != model.hint)) {
          hints.add(model.hint);
        }
      });

      await model.syncSilently();
      expect(model.hint, '已更新');
      expect(academicCompleter.isCompleted, isFalse);
      final academicSync = model.academicSyncForTest;
      expect(academicSync, isNotNull);

      academicCompleter.complete();
      await academicSync;

      expect(backend.loginCount, 1);
      expect(model.exams, isNotEmpty);
      expect(model.grades, isNotEmpty);
      expect(model.refreshing, isFalse);
      expect(model.hint, '已更新');
      for (final h in hints) {
        expect(h, isNot(contains('考试')));
        expect(h, isNot(contains('成绩')));
        expect(h, isNot(contains('重新登录')));
      }
    });

    test(
      '手动 refresh() 不派发学业同步；syncSilently 双线并行解耦（课表失败不连累学业），退登不写回残留',
      () async {
        final backend = FakeBackend();
        final rig = buildRig(backend: backend);
        final model = rig.model;
        addTearDown(model.dispose);
        model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

        // 1. 手动 refresh() 不派发学业同步
        await model.refresh();
        expect(model.academicSyncForTest, isNull);
        expect(backend.examsCount, 0);

        // 2. syncSilently 课表失败时，并行起飞的学业线照常独立完成，互不连累
        backend.fetchBehavior = (call, termId) async =>
            throw const AcademicError(ErrorCode.networkRetryable, '网络超时');
        await model.syncSilently();
        expect(model.scheduleHintIsError, isTrue);
        expect(model.academicSyncForTest, isNotNull);
        await model.academicSyncForTest;
        expect(backend.examsCount, 1);
        expect(model.exams, isNotEmpty);

        // 3. 学业同步进行中退出登录，完成后不得写回残留数据
        backend.fetchBehavior = null;
        final academicCompleter = Completer<void>();
        backend.examsBehavior = (call, termId) async {
          await academicCompleter.future;
          return sampleExams();
        };
        await model.syncSilently();
        expect(model.academicSyncForTest, isNotNull);

        await model.signOut();
        expect(model.status, AppStatus.needLogin);
        academicCompleter.complete();
        await Future<void>.delayed(Duration.zero);
        expect(model.exams, isEmpty);
        expect(model.grades, isEmpty);
      },
    );

    test('syncSilently 真正并行拉起双线、跨学期自动补跑、且课表收尾不误清学业喜报', () async {
      final examCache = InMemoryExamCache();
      await examCache.save('2026-2027-1', const <ExamItem>[
        ExamItem(courseName: '旧考试'),
      ]);
      final gradesCache = InMemoryGradesCache();
      final scheduleGate = Completer<Schedule>();
      final requestedExamTerms = <String?>[];
      final backend = FakeBackend()
        ..fetchBehavior = ((_, _) => scheduleGate.future)
        ..examsBehavior = (_, termId) async {
          requestedExamTerms.add(termId);
          if (termId == '2026-2027-2') {
            return const <ExamItem>[ExamItem(courseName: '新学期考试')];
          }
          return const <ExamItem>[ExamItem(courseName: '新变动考试')];
        };

      final model = AppModel(
        service: ScheduleService(
          credentials: InMemoryCredentialStore(),
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        preferences: Preferences.inMemory(),
        examCache: examCache,
        gradesCache: gradesCache,
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(model.dispose);
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      // 1. 课表尚未返回前，学业静默线就已经并行发出请求并弹出独立喜报
      final syncFuture = model.syncSilently();
      await model.academicSyncForTest;
      expect(requestedExamTerms, <String?>['2026-2027-1']);
      expect(model.globalHint, '考试安排有更新');
      expect(model.isAcademicUpdateHint, isTrue);

      // 2. 随后课表完成（同学期）收尾，绝不能误清刚弹出的跨页学业喜报
      scheduleGate.complete(sampleSchedule('2026-2027-1'));
      await syncFuture;
      expect(model.scheduleHint, '已更新');
      expect(model.globalHint, '考试安排有更新');
      expect(model.isAcademicUpdateHint, isTrue);

      // 3. 跨到新学期时：先并行查旧学期，课表返回新学期后自动为学业补跑新学期
      requestedExamTerms.clear();
      backend.fetchBehavior = (_, _) async => sampleSchedule('2026-2027-2');
      await model.syncSilently();
      await model.academicSyncForTest;
      expect(
        requestedExamTerms,
        containsAll(<String>['2026-2027-1', '2026-2027-2']),
      );
      expect(model.termId, '2026-2027-2');
      expect(model.exams.single.courseName, '新学期考试');
    });

    test('跨页学业喜报被重登气泡遮挡时延后开始 2 秒计时；静默同步取消验证码留在课表页不踢登录页', () async {
      // 1. 喜报被系统全局气泡遮挡时暂不倒计时，解除遮挡后才开始完整计时
      final rig = buildRig();
      final model = rig.model;
      addTearDown(model.dispose);
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      model.hints.showHint('正在重新登录...', scope: HintScope.global);
      model.hints.showAcademicUpdateHint(
        '成绩有更新',
        duration: const Duration(milliseconds: 80),
      );
      expect(model.globalHint, '正在重新登录...');
      expect(model.isAcademicUpdateHint, isFalse);

      // 遮挡超过 80ms 后喜报仍健在
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(model.hints.academicUpdateHint, '成绩有更新');

      // 解除遮挡：喜报露面并开始 80ms 倒计时
      model.hints.clearGlobalHint();
      expect(model.globalHint, '成绩有更新');
      expect(model.isAcademicUpdateHint, isTrue);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(model.globalHint, isEmpty);

      // 2. 静默同步遇验证码取消：已有本地课表时留在 ready 并轻提示，不踢回登录页、不扣熔断次数
      await rig.credentials.save(
        '${model.service.baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      model.service.accountHint = '20240001';
      model.session.username = '20240001';
      rig.backend.fetchBehavior = (_, _) async => throw expired();
      rig.backend.loginBehavior = (_, _) async => const CaptchaState(
        continuationId: 'silent-cap',
        imageBase64: 'iVBORw0KGgo=',
        mimeType: 'image/png',
      );

      final silentFuture = model.syncSilently();
      for (var i = 0; i < 30 && model.status != AppStatus.needCaptcha; i++) {
        await Future<void>.delayed(Duration.zero);
      }
      expect(model.status, AppStatus.needCaptcha);

      model.cancelCaptcha();
      await silentFuture;
      expect(model.status, AppStatus.ready);
      expect(model.schedule, isNotNull);
      expect(model.scheduleHint, '已取消自动登录');
      expect(model.service.breakerOpen, isFalse);
    });

    test('同学期静默更新与手动刷新保留当前查看周次，若新课表 maxWeek 变小则自动收敛', () async {
      const longSchedule = Schedule(
        termId: '2026-2027-1',
        maxWeeks: 22,
        entries: <ScheduleEntry>[
          ScheduleEntry(
            id: 'e1',
            name: '长周期课程',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 22],
          ),
        ],
      );
      final backend = FakeBackend(
        fetchBehavior: (call, termId) async => longSchedule,
      );
      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);
      model.hydrateForTest(schedule: longSchedule);

      final targetWeek = model.currentWeekOfToday == 8 ? 9 : 8;
      model.goToWeek(targetWeek);
      await model.syncSilently();
      expect(model.week, targetWeek);
      await model.refresh();
      expect(model.week, targetWeek);

      // 新课表最大周次回落至默认保底 18 时，当前查看周次（> 18）自动收敛到 18
      model.goToWeek(20);
      backend.fetchBehavior = (call, termId) async => const Schedule(
        termId: '2026-2027-1',
        maxWeeks: 18,
        entries: <ScheduleEntry>[
          ScheduleEntry(
            id: 'e2',
            name: '短周期课程',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1, 2, 3, 4, 5],
          ),
        ],
      );
      await model.refresh();
      expect(model.maxWeek, 18);
      expect(model.week, 18);
    });
  });

  group('第一批稳定性与竞态回归', () {
    Future<void> waitUntil(
      bool Function() predicate, {
      int maxTurns = 50,
    }) async {
      for (var i = 0; i < maxTurns && !predicate(); i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('手动登录遇验证码时正确提交验证码并支持重试与取消', () async {
      final submittedCodes = <String>[];
      final backend = FakeBackend(
        loginBehavior: (call, credentials) async => const CaptchaState(
          continuationId: 'manual-1',
          imageBase64: 'iVBORw0KGgo=',
          mimeType: 'image/png',
        ),
        submitBehavior: (call, code) async {
          submittedCodes.add(code);
          if (code == 'wrong') {
            return const CaptchaState(
              continuationId: 'manual-2',
              imageBase64: 'iVBORw0KGgo=',
              mimeType: 'image/png',
            );
          }
          return const AuthenticatedState(
            studentId: '20240001',
            studentName: '测试学生',
          );
        },
      );
      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);

      await model.signIn('20240001', 'pw');
      expect(model.status, AppStatus.needCaptcha);
      expect(model.captcha?.continuationId, 'manual-1');
      expect(model.session.hasPendingReloginCaptcha, isFalse);

      // 错误验证码会触发真实 submitCaptcha 且停留在 needCaptcha 等待新验证码
      await model.submitCaptcha('wrong');
      expect(backend.submitCount, 1);
      expect(submittedCodes, <String>['wrong']);
      expect(model.status, AppStatus.needCaptcha);
      expect(model.captcha?.continuationId, 'manual-2');
      expect(model.session.hasPendingReloginCaptcha, isFalse);

      // 正确验证码成功登录并拉取课表
      await model.submitCaptcha('good');
      expect(backend.submitCount, 2);
      expect(submittedCodes, <String>['wrong', 'good']);
      expect(model.status, AppStatus.ready);
      expect(model.captcha, isNull);
      expect(model.schedule, isNotNull);

      // 再次手动登录遇验证码时取消应退回 needLogin 且清掉验证码状态
      await model.signOut();
      await model.signIn('20240001', 'pw');
      expect(model.status, AppStatus.needCaptcha);
      model.cancelCaptcha();
      expect(model.status, AppStatus.needLogin);
      expect(model.captcha, isNull);
    });

    test('课表自动重登验证码竞态：取消不覆盖 needLogin，静默刷新失败退回 failed，成功不重复写盘', () async {
      final backend = FakeBackend();
      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);
      await rig.credentials.save(
        '${model.service.baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      model.service.accountHint = '20240001';
      model.session.username = '20240001';
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      // 1. 静默刷新遇会话过期 -> 自动重登触发验证码 -> 用户取消 -> 状态应保持 needLogin
      var fetchCall = 0;
      backend.fetchBehavior = (call, termId) async {
        fetchCall++;
        if (fetchCall == 1) {
          throw const AcademicError(ErrorCode.sessionExpired, '会话失效');
        }
        return sampleSchedule('2026-2027-1');
      };
      backend.loginBehavior = (call, credentials) async => const CaptchaState(
        continuationId: 'relogin-cancel',
        imageBase64: 'iVBORw0KGgo=',
        mimeType: 'image/png',
      );

      final cancelLoad = model.refresh();
      await waitUntil(() => model.status == AppStatus.needCaptcha);
      expect(model.status, AppStatus.needCaptcha);
      expect(model.session.hasPendingReloginCaptcha, isTrue);

      model.cancelCaptcha();
      expect(model.status, AppStatus.needLogin);
      expect(model.session.hasPendingReloginCaptcha, isFalse);

      await cancelLoad;
      expect(model.status, AppStatus.needLogin);
      expect(model.refreshing, isFalse);
      expect(model.scheduleState.scheduleLoad, isNull);
      expect(model.globalHint, isEmpty);
      expect(model.scheduleHint, isEmpty);

      // 2. 静默刷新重登验证码提交失败时，不能卡在 AppStatus.signingIn
      model.service.resetBreaker();
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));
      fetchCall = 0;
      backend.submitBehavior = (call, code) async => const CaptchaState(
        continuationId: 'retry',
        imageBase64: 'iVBORw0KGgo=',
        mimeType: 'image/png',
      );
      final failRefresh = model.refresh();
      await waitUntil(() => model.status == AppStatus.needCaptcha);
      expect(model.status, AppStatus.needCaptcha);

      await model.submitCaptcha('bad');
      await failRefresh;
      expect(model.status, AppStatus.failed);
      expect(model.captcha, isNull);
      expect(model.refreshing, isFalse);
      expect(model.scheduleState.scheduleLoad, isNull);

      // 3. 静默刷新重登验证码提交成功后只做一次收尾，状态回到 ready
      model.service.resetBreaker();
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));
      fetchCall = 0;
      backend.submitBehavior = (call, code) async {
        backend.cookies = snapshotOf(_baseUrl, value: 'recovered');
        return const AuthenticatedState(
          studentId: '20240001',
          studentName: '测试学生',
        );
      };
      final okRefresh = model.refresh();
      await waitUntil(() => model.status == AppStatus.needCaptcha);
      expect(model.status, AppStatus.needCaptcha);

      await model.submitCaptcha('ok');
      await okRefresh;
      expect(model.status, AppStatus.ready);
      expect(model.captcha, isNull);
      expect(model.refreshing, isFalse);
      expect(model.scheduleState.scheduleLoad, isNull);
      expect(model.globalHint, isEmpty);
    });

    test('非课表（学业）请求自动重登：静默重登与验证码重登收尾均正确复位刷新状态与全局提示', () async {
      final examCache = InMemoryExamCache();
      final backend = FakeBackend();
      final rig = buildRig(backend: backend);
      // 用带可观察缓存的 rig 测全局更新提示保留
      final customModel = AppModel(
        service: ScheduleService(
          credentials: rig.credentials,
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        preferences: Preferences.inMemory(),
        examCache: examCache,
        gradesCache: InMemoryGradesCache(),
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(customModel.dispose);
      await rig.credentials.save(
        '${customModel.service.baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      customModel.service.accountHint = '20240001';
      customModel.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      // 1. 静默重登（无验证码）且无新增学业变动：结束后 refreshing 与 globalHint 必须清零
      var examCalls = 0;
      backend.examsBehavior = (call, termId) async {
        examCalls++;
        if (examCalls == 1) {
          throw const AcademicError(ErrorCode.sessionExpired, '会话失效');
        }
        return sampleExams();
      };
      await customModel.loadAcademicData(
        termId: '2026-2027-1',
        forceRefresh: true,
        showHint: true,
      );
      expect(backend.loginCount, 1);
      expect(customModel.refreshing, isFalse);
      expect(customModel.globalHint, isEmpty);
      expect(customModel.academicHint, '已更新');

      // 2. 学业请求重登遇验证码（此时 scheduleLoad == null）：提交验证码不得卡在 signingIn
      examCalls = 0;
      backend.loginBehavior = (call, credentials) async => const CaptchaState(
        continuationId: 'acad-cap',
        imageBase64: 'iVBORw0KGgo=',
        mimeType: 'image/png',
      );
      backend.submitBehavior = (call, code) async {
        backend.cookies = snapshotOf(_baseUrl, value: 'acad-ok');
        return const AuthenticatedState(
          studentId: '20240001',
          studentName: '测试学生',
        );
      };
      // 修改考试返回数据以验证 globalHint 不会误伤新建的「考试安排有更新」提示
      backend.examsBehavior = (call, termId) async {
        examCalls++;
        if (examCalls == 1) {
          throw const AcademicError(ErrorCode.sessionExpired, '会话失效');
        }
        return const <ExamItem>[ExamItem(courseName: '新考试科目')];
      };

      final acadFuture = customModel.loadAcademicData(
        termId: '2026-2027-1',
        forceRefresh: true,
        showHint: true,
      );
      await waitUntil(() => customModel.status == AppStatus.needCaptcha);
      expect(customModel.status, AppStatus.needCaptcha);
      expect(customModel.scheduleState.scheduleLoad, isNull);
      expect(customModel.session.hasPendingReloginCaptcha, isTrue);

      await customModel.submitCaptcha('1234');
      await acadFuture;
      expect(customModel.status, AppStatus.ready);
      expect(customModel.captcha, isNull);
      expect(customModel.refreshing, isFalse);
      expect(customModel.globalHint, '考试安排有更新');
      expect(customModel.isAcademicUpdateHint, isTrue);

      // 3. 学业请求重登验证码被用户取消时，切到 needLogin 且不残留错误学业气泡
      customModel.service.resetBreaker();
      examCalls = 0;
      final cancelAcadFuture = customModel.loadAcademicData(
        termId: '2026-2027-1',
        forceRefresh: true,
        showHint: true,
      );
      await waitUntil(() => customModel.status == AppStatus.needCaptcha);
      expect(customModel.status, AppStatus.needCaptcha);

      customModel.cancelCaptcha();
      await cancelAcadFuture;
      expect(customModel.status, AppStatus.needLogin);
      expect(customModel.refreshing, isFalse);
      expect(customModel.globalHint, isEmpty);
      expect(customModel.academicHint, isEmpty);
    });

    test('AcademicController 登出与切校时取消在途请求与静默同步，切校回滚保留原数据', () async {
      final examsGate = Completer<void>();
      final gradesGate = Completer<void>();
      final backend = FakeBackend();
      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);
      await rig.credentials.save(
        '${model.service.baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      model.service.accountHint = '20240001';
      model.session.username = '20240001';
      model.hydrateForTest(
        schedule: sampleSchedule('2026-2027-1'),
        exams: sampleExams('2026-2027-1'),
        grades: sampleGrades('2026-2027-1'),
      );

      // 1. 切换学校失败回滚时，原校学业数据仍完整保留
      backend.loginBehavior = (call, credentials) async =>
          throw const AcademicError(ErrorCode.networkRetryable, '切换失败');
      await model.changeSchool(
        'https://jw2.example.edu.cn/jwglxt',
        relogin: true,
      );
      expect(model.status, AppStatus.failed);
      expect(model.exams, isNotEmpty);
      expect(model.grades, isNotEmpty);
      model.dismissError();
      expect(model.status, AppStatus.ready);

      // 2. 在途 loadAcademicData 期间切校（relogin: false），旧请求晚到不得回填残留状态
      backend.loginBehavior = null;
      backend.examsBehavior = (_, _) async {
        await examsGate.future;
        return sampleExams('2026-2027-1');
      };
      backend.gradesBehavior = (_, _) async {
        await gradesGate.future;
        return sampleGrades('2026-2027-1');
      };

      final inFlight = model.loadAcademicData(
        termId: '2026-2027-1',
        forceRefresh: true,
        showHint: true,
      );
      await Future<void>.delayed(Duration.zero);
      expect(model.academicLoading, isTrue);

      await model.changeSchool(
        'https://jw2.example.edu.cn/jwglxt',
        relogin: false,
      );
      expect(model.academicLoading, isFalse);
      expect(model.academicHint, isEmpty);
      expect(model.exams, isEmpty);
      expect(model.grades, isEmpty);

      examsGate.complete();
      gradesGate.complete();
      await inFlight;
      expect(model.exams, isEmpty);
      expect(model.grades, isEmpty);
      expect(model.academicLoading, isFalse);
      expect(model.academicHint, isEmpty);

      // 3. 在途静默同步 syncQuietly 期间切校（relogin: true）后，旧同步晚到不得触发旧校更新气泡
      final quietExamsGate = Completer<void>();
      final oldExamCache = InMemoryExamCache();
      await oldExamCache.save('2026-2027-1', const <ExamItem>[
        ExamItem(courseName: '旧校考试'),
      ]);
      final quietModel = AppModel(
        service: ScheduleService(
          credentials: rig.credentials,
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        preferences: Preferences.inMemory(),
        examCache: oldExamCache,
        gradesCache: InMemoryGradesCache(),
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(quietModel.dispose);
      await rig.credentials.save(
        '${quietModel.service.baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      quietModel.service.accountHint = '20240001';
      quietModel.session.username = '20240001';
      quietModel.hydrateForTest(
        schedule: sampleSchedule('2026-2027-1'),
        exams: const <ExamItem>[ExamItem(courseName: '旧校考试')],
      );

      var quietMode = true;
      backend.examsBehavior = (_, _) async {
        if (quietMode) {
          await quietExamsGate.future;
          return const <ExamItem>[ExamItem(courseName: '旧校新考试')];
        }
        return const <ExamItem>[];
      };
      backend.gradesBehavior = (_, _) async => const <GradeItem>[];

      await quietModel.syncSilently();
      final quietSync = quietModel.academicSyncForTest;
      expect(quietSync, isNotNull);

      quietMode = false;
      await quietModel.changeSchool(
        'https://jw3.example.edu.cn/jwglxt',
        relogin: true,
      );
      expect(quietModel.exams, isEmpty);

      quietExamsGate.complete();
      await quietSync;
      expect(quietModel.exams, isEmpty);
      expect(quietModel.globalHint, isEmpty);
    });

    test('AcademicController 单次加载仅读取一次本地缓存（含未命中与未评教分支）', () async {
      final countingExam = _CountingExamCache();
      final countingGrades = _CountingGradesCache();
      await countingGrades.save('2026-2027-1', sampleGrades());

      final backend = FakeBackend()
        ..examsBehavior = ((_, _) async => sampleExams())
        ..gradesBehavior = (_, _) async =>
            throw const AcademicError(ErrorCode.notEvaluated, '未完成教学评价');

      final model = AppModel(
        service: ScheduleService(
          credentials: InMemoryCredentialStore(),
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        preferences: Preferences.inMemory(),
        examCache: countingExam,
        gradesCache: countingGrades,
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(model.dispose);
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      // 1. forceRefresh 且后端返回 notEvaluated：
      // Controller 仅读 examCache 1 次、gradesCache 1 次（service.fetchGrades 内部另有 1 次读取保持既有行为，总计 <= 2）
      await model.loadAcademicData(termId: '2026-2027-1', forceRefresh: true);
      expect(countingExam.loadCalls, 1);
      expect(countingGrades.loadCalls, 2);
      expect(model.isNotEvaluated, isTrue);
      expect(model.grades, isNotEmpty);

      // 2. forceRefresh=false 命中缓存：各自只再读 1 次
      countingExam.loadCalls = 0;
      countingGrades.loadCalls = 0;
      await model.loadAcademicData(termId: '2026-2027-1', forceRefresh: false);
      expect(countingExam.loadCalls, 1);
      expect(countingGrades.loadCalls, 1);
    });

    test(
      'PreferencesController.flushAppearance 与 rebindOpened 重置外观草稿并取消防抖定时器',
      () async {
        final prefs1 = Preferences.inMemory();
        final rig = buildRig(preferences: prefs1);
        final model = rig.model;
        addTearDown(model.dispose);
        model.hydrateForTest(schedule: sampleSchedule());

        // 1. flushAppearance 落盘后清空草稿
        model.setCellHeight(74.0);
        model.setCourseTextScale(1.18);
        await model.flushAppearance();
        expect(prefs1.cellHeight, 74.0);
        expect(prefs1.courseTextScale, 1.18);

        final prefsReboundAfterFlush = Preferences.inMemory();
        model.prefs.rebindOpened(prefsReboundAfterFlush);
        expect(model.cellHeight, prefsReboundAfterFlush.cellHeight);
        expect(model.courseTextScale, prefsReboundAfterFlush.courseTextScale);

        // 2. 未触发防抖时调用 rebindOpened：必须取消定时器并丢弃旧草稿，不得污染新 Preferences
        model.setCellHeight(82.0);
        model.setCourseTextScale(1.25);
        final prefs2 = Preferences.inMemory();
        await prefs2.setCellHeight(56.0);
        await prefs2.setCourseTextScale(0.92);
        model.prefs.rebindOpened(prefs2);

        expect(model.cellHeight, 56.0);
        expect(model.courseTextScale, 0.92);
        await Future<void>.delayed(const Duration(milliseconds: 350));
        expect(prefs2.cellHeight, 56.0);
        expect(prefs2.courseTextScale, 0.92);
      },
    );

    test('signOut 打断在途课表重登验证码时，状态立即切至 needLogin 且不经过 failed、不写脏课表', () async {
      final backend = FakeBackend();
      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);
      await rig.credentials.save(
        '${model.service.baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      model.service.accountHint = '20240001';
      model.session.username = '20240001';
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      var scheduleCalls = 0;
      backend.fetchBehavior = (call, termId) async {
        scheduleCalls++;
        if (scheduleCalls == 1) {
          throw const AcademicError(ErrorCode.sessionExpired, '会话过期');
        }
        return sampleSchedule('2026-2027-2');
      };
      backend.loginBehavior = (call, credentials) async => const CaptchaState(
        continuationId: 'relogin-signout-race',
        imageBase64: 'iVBORw0KGgo=',
        mimeType: 'image/png',
      );

      final seenStatuses = <AppStatus>[model.status];
      model.routeNotifier.addListener(() {
        seenStatuses.add(model.status);
      });

      final load = model.refresh();
      await waitUntil(() => model.status == AppStatus.needCaptcha);

      await model.signOut();
      await load;

      expect(seenStatuses, isNot(contains(AppStatus.failed)));
      expect(model.status, AppStatus.needLogin);
      expect(model.username, isEmpty);
      expect(model.schedule, isNull);
      expect(model.captcha, isNull);
      expect(model.refreshing, isFalse);
      expect(model.scheduleState.scheduleLoad, isNull);
    });

    test('cancelCaptcha 后立即手动 signIn，在途 _loadSchedule 失败不得覆盖手动登录', () async {
      final backend = FakeBackend();
      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);
      await rig.credentials.save(
        '${model.service.baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      model.service.accountHint = '20240001';
      model.session.username = '20240001';
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      final loginGate = Completer<void>();
      var scheduleCalls = 0;
      backend.fetchBehavior = (call, termId) async {
        scheduleCalls++;
        if (scheduleCalls == 1) {
          throw const AcademicError(ErrorCode.sessionExpired, '会话过期');
        }
        return sampleSchedule('2026-2027-2');
      };
      backend.loginBehavior = (call, credentials) async {
        if (call == 1) {
          return const CaptchaState(
            continuationId: 'relogin-cancel-race',
            imageBase64: 'iVBORw0KGgo=',
            mimeType: 'image/png',
          );
        }
        await loginGate.future;
        backend.cookies = snapshotOf(_baseUrl, value: 'manual-ok');
        return AuthenticatedState(
          studentId: credentials.username,
          studentName: '新账号',
        );
      };

      final seenStatuses = <AppStatus>[model.status];
      model.routeNotifier.addListener(() {
        seenStatuses.add(model.status);
      });

      final load = model.refresh();
      await waitUntil(() => model.status == AppStatus.needCaptcha);

      // 同步连发 cancelCaptcha + 手动 signIn，确保晚到异常不得踩成 failed
      model.cancelCaptcha();
      final manualSignIn = model.signIn('20240002', 'pw2');
      expect(model.status, AppStatus.signingIn);
      expect(model.captcha, isNull);

      await load;
      expect(model.status, AppStatus.signingIn);
      expect(seenStatuses, isNot(contains(AppStatus.failed)));

      loginGate.complete();
      await manualSignIn;
      expect(model.status, AppStatus.ready);
      expect(model.username, '20240002');
      expect(model.errorCode, isEmpty);
    });

    test('AcademicController 在途请求被 resetOnSignOut 取消后不得污染磁盘缓存', () async {
      final examsGate = Completer<void>();
      final oldExamCache = InMemoryExamCache();
      final oldGradesCache = InMemoryGradesCache();
      final backend = FakeBackend()
        ..examsBehavior = ((_, _) async {
          await examsGate.future;
          return const <ExamItem>[ExamItem(courseName: '旧校未隔离考试')];
        })
        ..gradesBehavior = (_, _) async => sampleGrades('2026-2027-1');

      final model = AppModel(
        service: ScheduleService(
          credentials: InMemoryCredentialStore(),
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        preferences: Preferences.inMemory(),
        examCache: oldExamCache,
        gradesCache: oldGradesCache,
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(model.dispose);
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      final inFlight = model.loadAcademicData(
        termId: '2026-2027-1',
        forceRefresh: true,
      );
      await Future<void>.delayed(Duration.zero);

      await model.changeSchool(
        'https://jw2.example.edu.cn/jwglxt',
        relogin: false,
      );

      examsGate.complete();
      await inFlight;

      expect(await oldExamCache.load('2026-2027-1'), isNull);
      expect(await oldGradesCache.load('2026-2027-1'), isNull);
    });

    test('在途网络重登学业请求被缓存命中切学期打断后，收尾仍复位 refreshing 与 globalHint', () async {
      final loginGate = Completer<void>();
      final examCache = InMemoryExamCache();
      final gradesCache = InMemoryGradesCache();
      await examCache.save('2026-2027-2', const <ExamItem>[
        ExamItem(courseName: '第二学期缓存考试'),
      ]);
      await gradesCache.save('2026-2027-2', sampleGrades('2026-2027-2'));

      final backend = FakeBackend();
      var examCalls = 0;
      backend.examsBehavior = (call, termId) async {
        examCalls++;
        if (examCalls == 1) {
          throw const AcademicError(ErrorCode.sessionExpired, '会话过期');
        }
        return sampleExams(termId ?? '2026-2027-1');
      };
      backend.gradesBehavior = (call, termId) async =>
          sampleGrades(termId ?? '2026-2027-1');
      backend.loginBehavior = (call, credentials) async {
        await loginGate.future;
        backend.cookies = snapshotOf(_baseUrl, value: 'relogin-ok');
        return const AuthenticatedState(
          studentId: '20240001',
          studentName: '测试学生',
        );
      };

      final credentials = InMemoryCredentialStore();
      await credentials.save(
        '${_baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      final service = ScheduleService(
        credentials: credentials,
        cookieStorage: FakeSessionRepository(),
        backendFactory: (_) => backend,
        baseUrl: _baseUrl,
      )..accountHint = '20240001';

      final model = AppModel(
        service: service,
        preferences: Preferences.inMemory(),
        examCache: examCache,
        gradesCache: gradesCache,
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(model.dispose);
      model.session.username = '20240001';
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      final load1 = model.loadAcademicData(
        termId: '2026-2027-1',
        forceRefresh: true,
        showHint: true,
      );
      await waitUntil(() => model.globalHint == '正在重新登录...');
      expect(model.refreshing, isFalse);
      expect(model.academicLoading, isTrue);

      await model.loadAcademicData(termId: '2026-2027-2', forceRefresh: false);
      expect(model.exams.single.courseName, '第二学期缓存考试');

      loginGate.complete();
      await load1;

      expect(model.refreshing, isFalse);
      expect(model.globalHint, isEmpty);
      expect(model.exams.single.courseName, '第二学期缓存考试');
    });

    test(
      'PreferencesController.flushAppearance 并发遇 rebindOpened 时不得写入新绑定实例',
      () async {
        final prefs1 = Preferences.inMemory();
        final prefs2 = Preferences.inMemory();
        final defaultCellHeight = prefs2.cellHeight;
        final defaultTextScale = prefs2.courseTextScale;

        final rig = buildRig(preferences: prefs1);
        final model = rig.model;
        addTearDown(model.dispose);
        model.hydrateForTest(schedule: sampleSchedule());

        model.setCellHeight(84.0);
        model.setCourseTextScale(1.32);
        final flushing = model.flushAppearance();
        model.prefs.rebindOpened(prefs2);
        await flushing;

        expect(prefs1.cellHeight, 84.0);
        expect(prefs1.courseTextScale, 1.32);
        expect(prefs2.cellHeight, defaultCellHeight);
        expect(prefs2.courseTextScale, defaultTextScale);
      },
    );

    test(
      'changeSchool(relogin: true) 切校重置认证代数与在飞刷新状态，旧校失败与迟到验证码回调均不篡改新态',
      () async {
        final oldScheduleGate = Completer<void>();
        final loginGate = Completer<void>();
        final backend = FakeBackend();
        backend.fetchBehavior = (call, termId) async {
          if (call == 1) {
            await oldScheduleGate.future;
            throw const AcademicError(ErrorCode.networkRetryable, '旧校网络超时');
          }
          return sampleSchedule('2026-2027-2');
        };
        backend.loginBehavior = (call, creds) async {
          await loginGate.future;
          return const AuthenticatedState(
            studentId: '20240001',
            studentName: '测试学生',
          );
        };

        final rig = buildRig(backend: backend);
        final model = rig.model;
        addTearDown(model.dispose);
        await rig.credentials.save(
          '${_baseUrl.toLowerCase()}|20240001',
          const Credentials('20240001', 'pw'),
        );
        model.session.username = '20240001';
        model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));
        model.session.setCaptcha(
          const CaptchaState(
            continuationId: 'c1',
            imageBase64: '',
            mimeType: 'image/png',
          ),
        );

        final oldRefresh = model.refresh();
        await waitUntil(() => backend.fetchCount == 1);
        expect(model.refreshing, isTrue);

        final switchFuture = model.changeSchool(
          'https://jw2.example.edu.cn/jwglxt',
          relogin: true,
        );
        await waitUntil(() => model.status == AppStatus.loading);
        expect(model.refreshing, isFalse);
        expect(model.captcha, isNull);

        oldScheduleGate.complete();
        await oldRefresh;
        expect(model.status, AppStatus.loading);
        expect(model.scheduleHint, isEmpty);

        loginGate.complete();
        await switchFuture;
        expect(model.status, AppStatus.ready);
        expect(model.schoolBaseUrl, 'https://jw2.example.edu.cn/jwglxt');
      },
    );
  });

  group('网络失败重试与切校事务性回滚', () {
    test('断网切校失败后：持续断网重试再入 failed，恢复网络后 retry 成功切到目标教务并提示已更新', () async {
      const targetUrl = 'https://jw-target.example.edu.cn/jwglxt';
      final backend = FakeBackend();
      final prefs = Preferences.inMemory();
      final rig = buildRig(preferences: prefs, backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);

      await model.signIn('20240001', 'pw');
      expect(model.status, AppStatus.ready);

      // 1. 断网切校失败 → 回滚原线路并记录待重试目标
      var online = false;
      backend.loginBehavior = (call, creds) async {
        if (!online) {
          throw const AcademicError(ErrorCode.networkRetryable, '网络不可达');
        }
        backend.cookies = snapshotOf(targetUrl, value: 'target-cookie');
        return const AuthenticatedState(
          studentId: '20240001',
          studentName: '测试学生',
        );
      };

      await model.changeSchool(targetUrl);
      expect(model.status, AppStatus.failed);
      expect(model.schoolBaseUrl, _baseUrl);
      expect(model.hasPendingSchoolSwitch, isTrue);
      expect(model.canRetryError, isTrue);

      // 2. 持续断网时点重试：先进入 loading 再回到 failed，仍保留待重试目标
      final offlineStatuses = <AppStatus>[];
      void recordOffline() => offlineStatuses.add(model.status);
      model.addListener(recordOffline);
      await model.retry();
      model.removeListener(recordOffline);
      expect(offlineStatuses, contains(AppStatus.loading));
      expect(model.status, AppStatus.failed);
      expect(model.schoolBaseUrl, _baseUrl);
      expect(model.hasPendingSchoolSwitch, isTrue);

      // 3. 恢复网络后点重试：切到目标教务并进入 ready，显示短暂已更新提示
      online = true;
      final onlineStatuses = <AppStatus>[];
      void recordOnline() => onlineStatuses.add(model.status);
      model.addListener(recordOnline);
      await model.retry();
      model.removeListener(recordOnline);
      expect(onlineStatuses, contains(AppStatus.loading));
      expect(model.status, AppStatus.ready);
      expect(model.schoolBaseUrl, targetUrl);
      expect(prefs.currentSchool, targetUrl);
      expect(model.hasPendingSchoolSwitch, isFalse);
      expect(model.scheduleHint, '已更新');
    });

    test(
      '冷启动仅加载本地缓存时断网切校失败：不误删磁盘 Cookie 与课表缓存，恢复 accountHint，关闭后原校可正常刷新',
      () async {
        const targetUrl = 'https://jw-target.example.edu.cn/jwglxt';
        final backend = FakeBackend();
        final repo = FakeSessionRepository(
          snapshotOf(_baseUrl, value: 'disk-cookie'),
        );
        final cache = FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: sampleSchedule('2026-2027-1'),
            fetchedAt: DateTime.now(),
          ),
        );
        final prefs = Preferences.inMemory(
          lastAccounts: <String, String>{_baseUrl: '20240001'},
          lastStudentNames: <String, String>{_baseUrl: '张三'},
        );
        final credentials = InMemoryCredentialStore();
        await credentials.save(
          '${_baseUrl.toLowerCase()}|20240001',
          const Credentials('20240001', 'pw'),
        );

        final model = AppModel(
          service: ScheduleService(
            credentials: credentials,
            cookieStorage: repo,
            backendFactory: (_) => backend,
            baseUrl: _baseUrl,
          ),
          repository: repo,
          preferences: prefs,
          scheduleCache: cache,
          examCache: InMemoryExamCache(),
          gradesCache: InMemoryGradesCache(),
          schoolBaseUrl: _baseUrl,
        );
        addTearDown(model.dispose);

        await model.boot();
        expect(model.status, AppStatus.ready);
        expect(model.service.exportCurrentCookies(), isNull);
        expect(repo.clearCount, 0);

        backend.loginBehavior = (call, creds) async =>
            throw const AcademicError(ErrorCode.networkRetryable, '断网');
        await model.changeSchool(targetUrl);

        expect(model.status, AppStatus.failed);
        expect(model.schoolBaseUrl, _baseUrl);
        expect(repo.clearCount, 0, reason: '切校试登不得调用 bootstrap 误删原校磁盘 Cookie');
        expect(repo.saveCount, 0, reason: '内存无旧客户端时不覆盖磁盘 Cookie');
        expect((await repo.load())?.cookies.first.value, 'disk-cookie');
        expect(cache.clearCount, 0, reason: '切校失败不得提前清空原校课表缓存');
        expect(model.service.accountHint, '20240001');

        // 点关闭回到原校 ready，原校刷新可继续使用完好的 Cookie/凭据
        model.dismissError();
        expect(model.status, AppStatus.ready);
        expect(model.hasPendingSchoolSwitch, isFalse);

        backend.loginBehavior = null;
        await model.refresh();
        expect(model.status, AppStatus.ready);
        expect(model.scheduleHint, '已更新');
      },
    );

    test('同校手动重登不清空本地课表缓存，热会话切校失败回滚会回写内存 Cookie', () async {
      const targetUrl = 'https://jw-target.example.edu.cn/jwglxt';
      final backend = FakeBackend();
      final repo = FakeSessionRepository();
      final cache = FakeScheduleCache();
      final credentials = InMemoryCredentialStore();
      final model = AppModel(
        service: ScheduleService(
          credentials: credentials,
          cookieStorage: repo,
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        repository: repo,
        preferences: Preferences.inMemory(),
        scheduleCache: cache,
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(model.dispose);

      await model.signIn('20240001', 'pw');
      expect(cache.clearCount, 0);
      expect(cache.saveCount, 1);

      // 同校再次登录不应清空 scheduleCache
      await model.signIn('20240001', 'pw');
      expect(cache.clearCount, 0);

      // 热会话（内存持有 Cookie）切校失败，回滚写回内存 Cookie
      final saveBeforeSwitch = repo.saveCount;
      backend.loginBehavior = (call, creds) async =>
          throw const AcademicError(ErrorCode.networkRetryable, '断网');
      await model.changeSchool(targetUrl);
      expect(model.status, AppStatus.failed);
      expect(repo.clearCount, 0);
      expect(repo.saveCount, saveBeforeSwitch + 1);
      expect(model.service.accountHint, '20240001');
    });

    test(
      '切校遇 WebLoginState 回滚原校、保留学业与缓存且不保留待重试目标；遇 CaptchaState 延迟清学业且取消可无损回滚',
      () async {
        const targetUrl = 'https://jw-target.example.edu.cn/jwglxt';
        final backend = FakeBackend();
        final cache = FakeScheduleCache();
        final credentials = InMemoryCredentialStore();
        final model = AppModel(
          service: ScheduleService(
            credentials: credentials,
            cookieStorage: FakeSessionRepository(),
            backendFactory: (_) => backend,
            baseUrl: _baseUrl,
          ),
          preferences: Preferences.inMemory(),
          scheduleCache: cache,
          examCache: InMemoryExamCache(),
          gradesCache: InMemoryGradesCache(),
          schoolBaseUrl: _baseUrl,
        );
        addTearDown(model.dispose);

        await credentials.save(
          '${_baseUrl.toLowerCase()}|20240001',
          const Credentials('20240001', 'pw'),
        );
        model.session.username = '20240001';
        model.service.accountHint = '20240001';
        model.hydrateForTest(
          schedule: sampleSchedule('2026-2027-1'),
          exams: sampleExams('2026-2027-1'),
          grades: sampleGrades('2026-2027-1'),
        );

        // 1. WebLoginState → 回滚原校、保留学业数据、清除待重试目标、不提供重试
        backend.loginBehavior = (call, creds) async => const WebLoginState(
          continuationId: 'web-1',
          url: 'https://sso.example.edu.cn',
          completionUrl: targetUrl,
        );
        await model.changeSchool(targetUrl);
        expect(model.status, AppStatus.failed);
        expect(model.errorCode, ErrorCode.webLoginRequired.wire);
        expect(model.schoolBaseUrl, _baseUrl);
        expect(model.hasPendingSchoolSwitch, isFalse);
        expect(model.canRetryError, isFalse);
        expect(model.exams, isNotEmpty);
        expect(model.grades, isNotEmpty);
        expect(cache.clearCount, 0);

        final loginsBeforeNoopRetry = backend.loginCount;
        await model.retry();
        expect(backend.loginCount, loginsBeforeNoopRetry);
        model.dismissError();
        expect(model.status, AppStatus.ready);

        // 2. CaptchaState → 尚未通过验证码时不清空旧学业与缓存；取消验证码无损回滚到原校 ready
        backend.loginBehavior = (call, creds) async => const CaptchaState(
          continuationId: 'cap-switch',
          imageBase64: '',
          mimeType: 'image/png',
        );
        await model.changeSchool(targetUrl);
        expect(model.status, AppStatus.needCaptcha);
        expect(model.exams, isNotEmpty);
        expect(model.grades, isNotEmpty);
        expect(cache.clearCount, 0);

        model.cancelCaptcha();
        expect(model.status, AppStatus.ready);
        expect(model.schoolBaseUrl, _baseUrl);
        expect(model.exams, isNotEmpty);
        expect(model.grades, isNotEmpty);
        expect(model.service.accountHint, '20240001');

        // 3. CaptchaState 提交成功后，再清理旧学业与旧课表缓存并完成切校
        await model.changeSchool(targetUrl);
        expect(model.status, AppStatus.needCaptcha);
        backend.submitBehavior = (call, code) async => const AuthenticatedState(
          studentId: '20240001',
          studentName: '测试学生',
        );
        await model.submitCaptcha('1234');
        expect(model.status, AppStatus.ready);
        expect(model.schoolBaseUrl, targetUrl);
        expect(model.exams, isEmpty);
        expect(model.grades, isEmpty);
        expect(cache.clearCount, 1);
        expect(model.scheduleHint, '已更新');
      },
    );

    test('切校读取安全存储密码异步窗口内连点 retry / changeSchool 不会重入发起两次切校', () async {
      const targetUrl = 'https://jw-target.example.edu.cn/jwglxt';
      final backend = FakeBackend();
      final credGate = Completer<Credentials?>();
      final credStore = _DelayedCredentialStore(
        initial: <String, Credentials>{
          '${_baseUrl.toLowerCase()}|20240001': const Credentials(
            '20240001',
            'pw',
          ),
        },
        getGate: () => credGate.future,
      );
      final model = AppModel(
        service: ScheduleService(
          credentials: credStore,
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        preferences: Preferences.inMemory(),
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
        schoolBaseUrl: _baseUrl,
      );
      addTearDown(model.dispose);

      model.session.username = '20240001';
      model.service.accountHint = '20240001';
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      final first = model.changeSchool(targetUrl);
      final second = model.changeSchool(targetUrl);
      final third = model.retry();

      credGate.complete(const Credentials('20240001', 'pw'));
      await Future.wait<void>(<Future<void>>[first, second, third]);

      expect(credStore.getCount, 1);
      expect(backend.loginCount, 1);
      expect(model.status, AppStatus.ready);
      expect(model.schoolBaseUrl, targetUrl);
    });

    test('普通 failed 前台重试与切校登录后拉课表失败：不卡 loading，失败留 failed，成功提示已更新', () async {
      const targetUrl = 'https://jw-target.example.edu.cn/jwglxt';
      final backend = FakeBackend();
      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);

      await model.signIn('20240001', 'pw');

      // 1. 普通 failed（有课表）点击重试：失败时更新为 failed，成功后进入 ready 且展示「已更新」
      model.setStatusForTest(
        AppStatus.failed,
        message: '网络不稳定',
        code: ErrorCode.networkRetryable.wire,
      );
      backend.fetchBehavior = (call, termId) async => throw const AcademicError(
        ErrorCode.serverError,
        '维护中',
        httpStatus: 503,
      );
      final failStatuses = <AppStatus>[];
      void rec1() => failStatuses.add(model.status);
      model.addListener(rec1);
      await model.retry();
      model.removeListener(rec1);
      expect(failStatuses, contains(AppStatus.loading));
      expect(model.status, AppStatus.failed);
      expect(model.errorCode, ErrorCode.serverError.wire);

      backend.fetchBehavior = (call, termId) async =>
          sampleSchedule('2026-2027-2');
      await model.retry();
      expect(model.status, AppStatus.ready);
      expect(model.termId, '2026-2027-2');
      expect(model.scheduleHint, '已更新');

      // 2. 切校 signIn 成功但拉取新课表失败：不卡在 loading，进入 failed，再次 retry 拉取新校课表成功
      backend.fetchBehavior = (call, termId) async =>
          throw const AcademicError(ErrorCode.networkRetryable, '拉课表超时');
      await model.changeSchool(targetUrl);
      expect(model.schoolBaseUrl, targetUrl);
      expect(model.status, AppStatus.failed);
      expect(model.hasPendingSchoolSwitch, isFalse);

      backend.fetchBehavior = (call, termId) async =>
          sampleSchedule('2026-2027-2');
      await model.retry();
      expect(model.status, AppStatus.ready);
      expect(model.schoolBaseUrl, targetUrl);
      expect(model.scheduleHint, '已更新');
    });

    test('熔断/密码错时课表页与学业页文案完全一致，留在当前页保留离线课表并提供重新登录入口', () async {
      final backend = FakeBackend();
      final rig = buildRig(backend: backend);
      final model = rig.model;
      addTearDown(model.dispose);

      await model.signIn('20240001', 'pw');
      expect(model.status, AppStatus.ready);

      // 模拟密码已变更：自动重登返回 INVALID_CREDENTIALS 并立刻熔断
      backend.examsBehavior = (call, termId) async => throw expired();
      backend.gradesBehavior = (call, termId) async => throw expired();
      backend.fetchBehavior = (call, termId) async => throw expired();
      backend.loginBehavior = (call, creds) async => throw badCredentials();

      // 1. 学业页首次刷新：收到密码错误 → 展示与 humanizeError 一致的文案且标记需要重新登录
      await model.refreshAcademicData();
      expect(
        model.academicError,
        HintNoticeController.humanizeError(badCredentials()),
      );
      expect(model.academicNeedsRelogin, isTrue);
      expect(model.service.breakerOpen, isTrue);

      // 2. 熔断已打开后，再次在学业页与课表页分别刷新：两页文案完全一致（均为熔断暂停提示）
      await model.refreshAcademicData();
      const expectedBreakerText = '自动登录已暂停（多次失败或密码已变更），请重新登录。';
      expect(model.academicError, expectedBreakerText);
      expect(model.academicNeedsRelogin, isTrue);

      await model.refresh();
      expect(model.status, AppStatus.failed);
      expect(model.schedule, isNotNull, reason: '离线课表保留不丢失');
      expect(model.message, expectedBreakerText);
      expect(model.message, model.academicError);
      expect(model.needsReloginError, isTrue);

      // 3. 点击重新登录（retry → retryAfterSessionLoss）：进入登录页但仍保留离线课表引用
      await model.retry();
      expect(model.status, AppStatus.needLogin);
      expect(model.message, expectedBreakerText);
      expect(model.schedule, isNotNull);
    });
  });

  group('accountKey 大小写归一化与 PreferencesController 销毁生命周期', () {
    test(
      '含大写自定义线路 URL 在 signIn / 冷启动 boot / changeSchool 之间共用同一规范化 accountKey',
      () async {
        const upperUrl = 'https://JW-CUSTOM.Example.Edu.Cn/jwglxt';
        const upperUrl2 = 'https://JW2.Example.Edu.Cn/jwglxt';
        final credentials = InMemoryCredentialStore();

        // 1. signIn 使用大小写混合 URL 登录，session.accountKey() 必须与存储键完全一致。
        final signInBackend = FakeBackend();
        final signInRepo = FakeSessionRepository();
        final signInService = ScheduleService(
          credentials: credentials,
          cookieStorage: signInRepo,
          backendFactory: (_) => signInBackend,
          baseUrl: upperUrl,
        );
        final signInModel = AppModel(
          service: signInService,
          repository: signInRepo,
          preferences: Preferences.inMemory(),
          scheduleCache: FakeScheduleCache(),
          examCache: InMemoryExamCache(),
          gradesCache: InMemoryGradesCache(),
          schoolBaseUrl: upperUrl,
        );
        addTearDown(signInModel.dispose);

        await signInModel.signIn('20240001', 'pw_upper');
        expect(signInModel.status, AppStatus.ready);
        expect(
          signInModel.session.accountKey(),
          buildAccountKey(upperUrl, '20240001'),
        );
        expect(await credentials.has(signInModel.session.accountKey()), isTrue);

        // 2. 冷启动 boot（无 Cookie 快照、无课表缓存，仅 lastAccounts 与已保存凭据）：
        //    通过 session.accountKey() 命中凭据并自动登录进入 ready。
        late final FakeBackend bootBackend;
        bootBackend = FakeBackend(
          fetchBehavior: (call, termId) async {
            if (bootBackend.loginCount == 0) {
              throw expired();
            }
            return sampleSchedule(termId ?? '2026-2027-1');
          },
        );
        final bootRepo = FakeSessionRepository();
        final bootModel = AppModel(
          service: ScheduleService(
            credentials: credentials,
            cookieStorage: bootRepo,
            backendFactory: (_) => bootBackend,
            baseUrl: upperUrl,
          ),
          repository: bootRepo,
          preferences: Preferences.inMemory(
            customSchools: <String>[upperUrl, upperUrl2],
            customSchool: upperUrl,
            lastAccounts: <String, String>{upperUrl: '20240001'},
          ),
          scheduleCache: FakeScheduleCache(),
          examCache: InMemoryExamCache(),
          gradesCache: InMemoryGradesCache(),
          schoolBaseUrl: upperUrl,
        );
        addTearDown(bootModel.dispose);

        await bootModel.boot();
        expect(bootModel.status, AppStatus.ready);
        expect(bootBackend.loginCount, 1);

        // 3. changeSchool(relogin: true) 从大写 URL 切换时能读到已保存密码完成切校。
        await bootModel.changeSchool(upperUrl2, relogin: true);
        expect(bootModel.status, AppStatus.ready);
        expect(bootModel.schoolBaseUrl, upperUrl2);
        expect(bootBackend.loginCount, 2);
        expect(
          await credentials.has(buildAccountKey(upperUrl2, '20240001')),
          isTrue,
        );
      },
    );

    test('末尾斜杠差异（signIn 带斜杠后 boot 无斜杠）与历史末尾斜杠凭据键回退均能命中并进入 ready', () async {
      const slashUrl = 'https://jw.custom.edu.cn/jwglxt/';
      const cleanUrl = 'https://jw.custom.edu.cn/jwglxt';
      final credentials = InMemoryCredentialStore();

      final signInBackend = FakeBackend();
      final signInModel = AppModel(
        service: ScheduleService(
          credentials: credentials,
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => signInBackend,
          baseUrl: slashUrl,
        ),
        repository: FakeSessionRepository(),
        preferences: Preferences.inMemory(),
        scheduleCache: FakeScheduleCache(),
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
        schoolBaseUrl: slashUrl,
      );
      addTearDown(signInModel.dispose);

      await signInModel.signIn('20240001', 'pw_slash');
      expect(signInModel.status, AppStatus.ready);
      expect(
        signInModel.session.accountKey(),
        buildAccountKey(cleanUrl, '20240001'),
      );
      expect(
        await credentials.has('https://jw.custom.edu.cn/jwglxt|20240001'),
        isTrue,
      );

      late final FakeBackend bootBackend;
      bootBackend = FakeBackend(
        fetchBehavior: (call, termId) async {
          if (bootBackend.loginCount == 0) {
            throw expired();
          }
          return sampleSchedule(termId ?? '2026-2027-1');
        },
      );
      final bootModel = AppModel(
        service: ScheduleService(
          credentials: credentials,
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => bootBackend,
          baseUrl: cleanUrl,
        ),
        repository: FakeSessionRepository(),
        preferences: Preferences.inMemory(
          customSchools: <String>[cleanUrl],
          customSchool: cleanUrl,
          lastAccounts: <String, String>{slashUrl: '20240001'},
        ),
        scheduleCache: FakeScheduleCache(),
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
        schoolBaseUrl: cleanUrl,
      );
      addTearDown(bootModel.dispose);

      await bootModel.boot();
      expect(bootModel.status, AppStatus.ready);
      expect(bootBackend.loginCount, 1);

      // 历史版本按带末尾斜杠键存储的凭据在规范化后仍可被冷启动回退读取
      final legacyCreds = InMemoryCredentialStore();
      await legacyCreds.save(
        'https://jw-legacy.edu.cn/jwglxt/|20240002',
        const Credentials('20240002', 'pw_legacy'),
      );
      late final FakeBackend legacyBackend;
      legacyBackend = FakeBackend(
        fetchBehavior: (call, termId) async {
          if (legacyBackend.loginCount == 0) {
            throw expired();
          }
          return sampleSchedule(termId ?? '2026-2027-1');
        },
      );
      final legacyModel = AppModel(
        service: ScheduleService(
          credentials: legacyCreds,
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => legacyBackend,
          baseUrl: 'https://jw-legacy.edu.cn/jwglxt',
        ),
        repository: FakeSessionRepository(),
        preferences: Preferences.inMemory(
          customSchools: const <String>['https://jw-legacy.edu.cn/jwglxt'],
          customSchool: 'https://jw-legacy.edu.cn/jwglxt',
          lastAccounts: const <String, String>{
            'https://jw-legacy.edu.cn/jwglxt/': '20240002',
          },
        ),
        scheduleCache: FakeScheduleCache(),
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
        schoolBaseUrl: 'https://jw-legacy.edu.cn/jwglxt',
      );
      addTearDown(legacyModel.dispose);

      await legacyModel.boot();
      expect(legacyModel.status, AppStatus.ready);
      expect(legacyBackend.loginCount, 1);
    });

    test(
      '多末尾斜杠（signIn 带 /// 后 boot 无斜杠）与 http→https 协议归一化后仍可恢复凭据进入 ready',
      () async {
        // 1. F2-A：3 个末尾斜杠 signIn 后以无斜杠 URL boot，Preferences.accountOf 与凭据键一致命中
        const multiSlashUrl = 'https://jw.custom.edu.cn/jwglxt///';
        const cleanUrl = 'https://jw.custom.edu.cn/jwglxt';
        expect(sameSchool(multiSlashUrl, cleanUrl), isTrue);

        final multiCreds = InMemoryCredentialStore();
        final multiSignInPrefs = Preferences.inMemory();
        final multiSignInModel = AppModel(
          service: ScheduleService(
            credentials: multiCreds,
            cookieStorage: FakeSessionRepository(),
            backendFactory: (_) => FakeBackend(),
            baseUrl: multiSlashUrl,
          ),
          repository: FakeSessionRepository(),
          preferences: multiSignInPrefs,
          scheduleCache: FakeScheduleCache(),
          examCache: InMemoryExamCache(),
          gradesCache: InMemoryGradesCache(),
          schoolBaseUrl: multiSlashUrl,
        );
        addTearDown(multiSignInModel.dispose);

        await multiSignInModel.signIn('20240001', 'pw_multi');
        expect(multiSignInModel.status, AppStatus.ready);
        expect(multiSignInPrefs.accountOf(cleanUrl), '20240001');

        late final FakeBackend multiBootBackend;
        multiBootBackend = FakeBackend(
          fetchBehavior: (call, termId) async {
            if (multiBootBackend.loginCount == 0) {
              throw expired();
            }
            return sampleSchedule(termId ?? '2026-2027-1');
          },
        );
        final multiBootModel = AppModel(
          service: ScheduleService(
            credentials: multiCreds,
            cookieStorage: FakeSessionRepository(),
            backendFactory: (_) => multiBootBackend,
            baseUrl: cleanUrl,
          ),
          repository: FakeSessionRepository(),
          preferences: Preferences.inMemory(
            customSchools: const <String>[multiSlashUrl],
            customSchool: multiSlashUrl,
            lastAccounts: const <String, String>{multiSlashUrl: '20240001'},
          ),
          scheduleCache: FakeScheduleCache(),
          examCache: InMemoryExamCache(),
          gradesCache: InMemoryGradesCache(),
          schoolBaseUrl: cleanUrl,
        );
        addTearDown(multiBootModel.dispose);

        await multiBootModel.boot();
        expect(multiBootModel.status, AppStatus.ready);
        expect(multiBootBackend.loginCount, 1);

        // 2. F2-B：旧凭据存在 http://...|20240001，Preferences 将 currentSchool 规范化为 https://...
        const httpQust = 'http://jwglxt.qust.edu.cn/jwglxt';
        const httpsQust = 'https://jwglxt.qust.edu.cn/jwglxt';
        final schemeCreds = InMemoryCredentialStore();
        await schemeCreds.save(
          '$httpQust|20240001',
          const Credentials('20240001', 'pw_http'),
        );
        late final FakeBackend schemeBootBackend;
        schemeBootBackend = FakeBackend(
          fetchBehavior: (call, termId) async {
            if (schemeBootBackend.loginCount == 0) {
              throw expired();
            }
            return sampleSchedule(termId ?? '2026-2027-1');
          },
        );
        final schemePrefs = Preferences.inMemory(
          customSchool: httpQust,
          lastAccounts: const <String, String>{httpQust: '20240001'},
        );
        expect(schemePrefs.currentSchool, httpsQust);

        final schemeModel = AppModel(
          service: ScheduleService(
            credentials: schemeCreds,
            cookieStorage: FakeSessionRepository(),
            backendFactory: (_) => schemeBootBackend,
          ),
          repository: FakeSessionRepository(),
          preferences: schemePrefs,
          scheduleCache: FakeScheduleCache(),
          examCache: InMemoryExamCache(),
          gradesCache: InMemoryGradesCache(),
        );
        addTearDown(schemeModel.dispose);

        await schemeModel.boot();
        expect(schemeModel.schoolBaseUrl, httpsQust);
        expect(schemeModel.status, AppStatus.ready);
        expect(schemeBootBackend.loginCount, 1);
      },
    );

    test('PreferencesController.dispose 取消挂起外观草稿、阻止销毁后写盘并保持幂等与正常防抖', () async {
      final tempDir = Directory.systemTemp.createTempSync('prefs_dispose_test');
      addTearDown(() {
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });
      final prefsFile = File('${tempDir.path}/prefs.json');
      final prefs = await Preferences.openFile(prefsFile);

      final model = buildRig(preferences: prefs).model;
      model.hydrateForTest(schedule: sampleSchedule());

      // 1. 销毁前：正常防抖（300ms）与显式 flushAppearance() 仍正常落盘。
      model.setCellHeight(72.0);
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(prefsFile.existsSync(), isTrue);
      expect(prefs.cellHeight, 72.0);

      model.setCourseTextScale(1.15);
      await model.flushAppearance();
      expect(prefs.courseTextScale, 1.15);

      // 2. 留有未落盘的外观草稿时立即 dispose() 并删除目录：
      //    不得在 dispose 后触发异步 writeJson 或 onWriteError。
      var errorCallbackCalled = false;
      prefs.onWriteError = (_) => errorCallbackCalled = true;
      model.setCellHeight(96.0);
      model.setCourseTextScale(1.30);
      model.dispose();

      // 立即删除目录；若 dispose() 仍发起了异步 flushAppearance()，后续微任务会触发写盘失败。
      tempDir.deleteSync(recursive: true);
      await Future<void>.delayed(const Duration(milliseconds: 350));

      expect(errorCallbackCalled, isFalse);
      expect(model.storageNoticeEvent, 0);
      expect(tempDir.existsSync(), isFalse);

      // 3. 二次 PreferencesController.dispose 与 dispose 后调用草稿/落盘方法均为安全空操作。
      model.setCellHeight(80.0);
      model.setCourseTextScale(1.0);
      await model.flushAppearance();
      model.prefs.dispose();
      model.prefs.dispose();
    });
  });
}

class _DelayedCredentialStore extends InMemoryCredentialStore {
  _DelayedCredentialStore({required this.initial, required this.getGate});

  final Map<String, Credentials> initial;
  final Future<Credentials?> Function() getGate;
  int getCount = 0;

  @override
  Future<Credentials?> get(String key) async {
    getCount++;
    final gated = await getGate();
    return gated ?? initial[key];
  }
}

class _CountingExamCache extends InMemoryExamCache {
  int loadCalls = 0;

  @override
  Future<CachedTermExams?> load(String termId) {
    loadCalls++;
    return super.load(termId);
  }
}

class _CountingGradesCache extends InMemoryGradesCache {
  int loadCalls = 0;

  @override
  Future<CachedTermGrades?> load(String termId) {
    loadCalls++;
    return super.load(termId);
  }
}

class _MockUpdateService extends UpdateService {
  _MockUpdateService({required this.hasUpdate});
  final bool hasUpdate;
  int callCount = 0;

  @override
  Future<UpdateCheckResult> checkForUpdatesWithFallback({
    required String currentVersion,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
  }) async {
    callCount++;
    return UpdateCheckResult(
      status: hasUpdate ? UpdateStatus.hasUpdate : UpdateStatus.noUpdate,
      release: hasUpdate
          ? const ReleaseInfo(
              tagName: 'v2.0.0',
              version: '2.0.0',
              name: 'v2.0.0',
              body: '',
              publishedAt: null,
              assets: [],
              htmlUrl: '',
            )
          : null,
    );
  }
}
