/// AppModel 的周次与学期逻辑测试。
///
/// 这里覆盖的是"周视图能不能对上真实校历"的三件事：
///  1. maxWeek 取自课表实际最晚周次（不是拿 25 兜底）；
///  2. 校准后反推出的开学日被持久化，重开 app 仍生效；
///  3. 学期下拉默认折叠，且当前学期一定在选项里。
library;

import 'dart:async';
import 'dart:convert';

import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_cache.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/term_calendar.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:flutter_test/flutter_test.dart';
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

/// 同时拿到状态机与它背后的假后端（验证"后台刷新"这类行为需要能控制 fetch）。
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
    schoolBaseUrl: _baseUrl,
  );
  return (model: model, backend: fake, credentials: credentials);
}

AppModel buildModel({Preferences? preferences}) =>
    buildRig(preferences: preferences).model;

/// boot() 需要三个存储都已就绪，才不会去碰 path_provider / 平台通道。
AppModel bootRig({
  FakeBackend? backend,
  FakeSessionRepository? repository,
  FakeScheduleCache? cache,
  Preferences? preferences,
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
    // repository 单独传一份，让 boot() 判定"已就绪"，不去碰 path_provider。
    repository: repo,
    preferences: preferences ?? Preferences.inMemory(),
    scheduleCache: cache ?? FakeScheduleCache(),
    schoolBaseUrl: _baseUrl,
  );
}

void main() {
  group('账号本地记忆（凭据 key 依赖它）', () {
    test('冷启动：本地记着账号时，不联网也能显示学号', () async {
      // 没有 Cookie 快照、也没有保存的凭据 → 停在登录页；但账号应该已经从设置里读出来，
      // 不用等任何网络请求（否则调试页永远是"-"，直到某次刷新成功）。
      final prefs = Preferences.inMemory(
        lastAccounts: <String, String>{_baseUrl: '2407720102'},
      );
      final model = bootRig(preferences: prefs);
      await model.boot();

      expect(model.status, AppStatus.needLogin);
      expect(model.studentId, '2407720102');
    });

    test('登录成功后记住账号', () async {
      final prefs = Preferences.inMemory();
      final rig = buildRig(preferences: prefs);
      await rig.model.signIn('2407720102', 'pw');

      expect(prefs.accountOf(_baseUrl), '2407720102');
      expect(rig.model.studentId, '2407720102');
    });

    test('冷启动遇到会话过期：用本地记住的账号 + 保存的密码自动重登', () async {
      // 用户报告的确切场景：长时间不用 → Cookie 失效 → 冷启动刷新。
      final credentials = InMemoryCredentialStore();
      await credentials.save(
        '$_baseUrl|2407720102',
        const Credentials('2407720102', 'pw'),
      );
      final prefs = Preferences.inMemory(
        lastAccounts: <String, String>{_baseUrl: '2407720102'},
      );
      final repo = FakeSessionRepository(snapshotOf(_baseUrl));
      final backend = FakeBackend(studentId: '', studentName: '')
        ..fetchBehavior = (call, termId) async {
          if (call == 1) {
            throw AcademicError(ErrorCode.sessionExpired, '登录已失效');
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
        schoolBaseUrl: _baseUrl,
      );

      await model.boot();

      expect(backend.loginCount, 1, reason: 'Cookie 失效应触发自动重登');
      expect(model.schedule?.entries, isNotEmpty, reason: '重登后课表要更新');
      expect(model.studentId, isNotEmpty);
    });

    test('退出登录清掉记住的账号', () async {
      final prefs = Preferences.inMemory(
        lastAccounts: <String, String>{_baseUrl: '2407720102'},
      );
      final rig = buildRig(preferences: prefs);
      await rig.model.signOut();

      expect(prefs.accountOf(_baseUrl), isEmpty);
      expect(rig.model.studentId, isEmpty);
    });
  });

  test('maxWeek 取自课表最晚周次，而不是 25 的兜底值', () {
    final model = buildModel();
    model.hydrateForTest(schedule: scheduleWithWeeks(<int>[1, 5, 17]));

    expect(model.maxWeek, 17);
  });

  test('课表为空时 maxWeek 回落到 20（仍可切换周次）', () {
    final model = buildModel();
    model.hydrateForTest(
      schedule: const Schedule(
        termId: '2026-2027-1',
        maxWeeks: 25,
        entries: <ScheduleEntry>[],
      ),
    );

    expect(model.maxWeek, 20);
  });

  test('周次切换会被 clamp 到 1..maxWeek', () {
    final model = buildModel();
    model.hydrateForTest(schedule: scheduleWithWeeks(<int>[1, 3]), week: 1);

    model.goToWeek(0);
    expect(model.week, 1);
    model.goToWeek(99);
    expect(model.week, model.maxWeek);
  });

  test('weekEntries 只返回本周该上的课', () {
    final model = buildModel();
    model.hydrateForTest(schedule: scheduleWithWeeks(<int>[1, 2, 3]), week: 2);

    expect(model.weekEntries.map((entry) => entry.name), <String>['第2周课']);
  });

  test('校准后开学日被反推并持久化，重新打开仍生效', () async {
    final prefs = Preferences.inMemory();
    final model = buildModel(preferences: prefs);
    model.hydrateForTest(
      schedule: scheduleWithWeeks(<int>[1, 2, 3, 4, 5, 6, 7, 8]),
    );

    await model.calibrateCurrentWeek(5);

    expect(model.currentWeekOfToday, 5, reason: '校准后今天就是第 5 周');
    final saved = prefs.termStartOf('2026-2027-1');
    expect(saved, isNotNull);
    expect(weekOf(saved!, DateTime.now()), 5);
  });

  test('未校准时按学期估算开学日（秋季 = 9 月初所在周的周一）', () {
    final model = buildModel();
    model.hydrateForTest(
      schedule: scheduleWithWeeks(<int>[1, 2]),
      terms: termsWith(4),
    );

    final start = model.termStart;
    expect(start, isNotNull);
    expect(start!.weekday, DateTime.monday);
    expect(start.month, greaterThanOrEqualTo(8));
  });

  test('resetCalendar 回到估算值（清掉校准）', () async {
    final prefs = Preferences.inMemory();
    final model = buildModel(preferences: prefs);
    model.hydrateForTest(schedule: scheduleWithWeeks(<int>[1, 2, 3, 4, 5]));

    await model.calibrateCurrentWeek(4);
    expect(model.currentWeekOfToday, 4);

    await model.resetCalendar();
    expect(model.currentWeekOfToday, isNot(4));
    expect(prefs.termStartOf('2026-2027-1'), isNotNull, reason: '重置后写入估算值');
  });

  group('全局节数', () {
    test('改分段节数后网格行数与时间轴同步变化', () async {
      final rig = buildRig();
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
      expect(rig.model.startLabelOf(12), isNotEmpty, reason: '补齐的第 12 节也要有时间');

      await rig.model.setSectionCounts(<PeriodGroup, int>{
        PeriodGroup.morning: 4,
        PeriodGroup.afternoon: 2,
        PeriodGroup.evening: 0,
      });
      expect(rig.model.sectionCount, 6);
      expect(rig.model.gridSectionCount, 6);
      expect(rig.model.activeSections, hasLength(6));
    });

    test('数据节次超过节数时网格取大值（不丢课）', () {
      final model = buildModel();
      model.hydrateForTest(
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

      expect(model.sectionCount, 10);
      expect(model.gridSectionCount, 13);
      expect(model.hasSectionsBeyondTimetable, isTrue);
    });
  });

  group('后台刷新（不遮挡课表）', () {
    test('刷新期间状态仍是 ready、课表不清空，只出提示', () async {
      final rig = buildRig();
      rig.model.hydrateForTest(schedule: sampleSchedule());
      final completer = Completer<Schedule>();
      rig.backend.fetchBehavior = (call, termId) => completer.future;

      final pending = rig.model.refresh();
      await Future<void>.delayed(Duration.zero);

      expect(rig.model.status, AppStatus.ready, reason: '不能退回 loading 遮住课表');
      expect(rig.model.refreshing, isTrue);
      expect(rig.model.hint, '更新中…');
      expect(rig.model.schedule, isNotNull);

      completer.complete(sampleSchedule());
      await pending;
      expect(rig.model.refreshing, isFalse);
      expect(rig.model.hint, '已更新');
      rig.model.dispose();
    });

    test('刷新失败：保留旧课表，提示错误而不是整页报错', () async {
      final rig = buildRig();
      rig.model.hydrateForTest(schedule: sampleSchedule());
      rig.backend.fetchBehavior = (call, termId) async => throw pageChanged();

      await rig.model.refresh();

      expect(rig.model.status, AppStatus.ready);
      expect(rig.model.schedule, isNotNull);
      expect(rig.model.hintIsError, isTrue);
      expect(rig.model.hint, contains('更新失败'));
      rig.model.dispose();
    });

    test('提示可以手动关掉', () async {
      final rig = buildRig();
      rig.model.hydrateForTest(schedule: sampleSchedule());
      final completer = Completer<Schedule>();
      rig.backend.fetchBehavior = (call, termId) => completer.future;
      final pending = rig.model.refresh();
      await Future<void>.delayed(Duration.zero);
      expect(rig.model.hint, isNotEmpty);

      rig.model.clearHint();
      expect(rig.model.hint, isEmpty);

      completer.complete(sampleSchedule());
      await pending;
      rig.model.dispose();
    });
  });

  group('状态弹窗的数据来源', () {
    test('首次加载走 loading + "获取中…"，成功后提示自动消失', () async {
      final rig = buildRig();
      final completer = Completer<Schedule>();
      rig.backend.fetchBehavior = (call, termId) => completer.future;

      final pending = rig.model.loadScheduleForTest();
      await Future<void>.delayed(Duration.zero);

      expect(rig.model.status, AppStatus.loading);
      expect(rig.model.hint, '获取中…');
      expect(rig.model.refreshing, isTrue);
      expect(rig.model.schedule, isNull);

      completer.complete(sampleSchedule());
      await pending;

      expect(rig.model.status, AppStatus.ready);
      expect(rig.model.hint, isEmpty, reason: '成功后弹窗不该继续挂着');
      expect(rig.model.refreshing, isFalse);
      rig.model.dispose();
    });

    test('首次加载失败：状态 failed，关掉弹窗回登录页', () async {
      final rig = buildRig();
      rig.backend.fetchBehavior = (call, termId) async => throw pageChanged();

      await rig.model.loadScheduleForTest();

      expect(rig.model.status, AppStatus.failed);
      expect(rig.model.message, isNotEmpty);
      expect(rig.model.schedule, isNull);

      rig.model.dismissError();
      expect(rig.model.status, AppStatus.needLogin, reason: '没有课表可回，只能去登录');
      rig.model.dispose();
    });

    test('有旧课表时关掉错误弹窗退回 ready，课表还在', () async {
      final rig = buildRig();
      rig.model.hydrateForTest(schedule: sampleSchedule());
      rig.model.setStatusForTest(
        AppStatus.failed,
        message: '出错了',
        code: 'PAGE_CHANGED',
      );
      expect(rig.model.schedule, isNotNull);

      rig.model.dismissError();
      expect(rig.model.status, AppStatus.ready);
      expect(rig.model.schedule, isNotNull);
      rig.model.dispose();
    });
  });

  group('冷启动免登：身份补齐', () {
    test('Cookie 有效但读不到姓名时，用 checkSession 补一次', () async {
      // 模拟"课表能取、但客户端还不知道我是谁"
      final rig = buildRig(
        backend: FakeBackend(studentId: '', studentName: ''),
      );
      await rig.model.loadScheduleForTest();

      expect(rig.backend.checkSessionCount, 1);
      expect(rig.model.studentName, '房子洋');
      expect(rig.model.studentId, '2407720102');
      expect(rig.model.signedIn, isTrue);
      rig.model.dispose();
    });

    test('已经知道身份时不再多发请求', () async {
      final rig = buildRig();
      await rig.model.loadScheduleForTest();

      expect(rig.backend.checkSessionCount, 0, reason: '身份齐全就不该多打一次接口');
      rig.model.dispose();
    });

    test('身份读不到时至少用账号顶上，不显示未登录', () async {
      final rig = buildRig(
        backend: FakeBackend(
          studentId: '',
          studentName: '',
          checkSessionReadsIdentity: false,
        ),
      );
      rig.model.username = '2407720102';
      await rig.model.loadScheduleForTest();

      expect(rig.model.studentId, '2407720102');
      expect(rig.model.signedIn, isTrue);
      rig.model.dispose();
    });
  });

  group('修改密码', () {
    test('新密码通过验证后写入安全存储', () async {
      final rig = buildRig();
      await rig.model.loadScheduleForTest();

      await rig.model.changePassword('brand-new-pass');

      final saved = await rig.credentials.get('$_baseUrl|2407720102');
      expect(saved, isNotNull);
      expect(saved!.password, 'brand-new-pass');
      expect(rig.backend.loginCount, 1);
      rig.model.dispose();
    });

    test('新密码被拒时抛错，且不覆盖原来的凭据', () async {
      final rig = buildRig();
      await rig.model.loadScheduleForTest();
      rig.backend.loginBehavior = (call, credentials) async =>
          throw AcademicError(ErrorCode.invalidCredentials, '用户名或密码不正确');

      await expectLater(
        rig.model.changePassword('wrong'),
        throwsA(isA<AcademicError>()),
      );
      expect(await rig.credentials.has('$_baseUrl|2407720102'), isFalse);
      rig.model.dispose();
    });
  });

  group('教务地址簿', () {
    test('新增去重，切换会记住当前地址', () async {
      final prefs = Preferences.inMemory();
      final model = buildModel(preferences: prefs);
      expect(model.schools, isNotEmpty);

      await model.addSchool('https://jw2.example.edu.cn/jwglxt');
      await model.addSchool('https://jw2.example.edu.cn/jwglxt/');
      expect(
        model.schools.where((item) => item.contains('jw2')).length,
        1,
        reason: '末尾斜杠算同一个地址',
      );

      model.changeSchool('https://jw2.example.edu.cn/jwglxt');
      expect(model.schoolBaseUrl, 'https://jw2.example.edu.cn/jwglxt');
      await Future<void>.delayed(Duration.zero);
      expect(prefs.currentSchool, contains('jw2'));
    });

    test('删除地址只删地址簿，不动当前会话', () async {
      final prefs = Preferences.inMemory(
        schools: <String>[
          'https://a.example.edu.cn/jwglxt',
          'https://b.example.edu.cn/jwglxt',
        ],
        currentSchool: 'https://a.example.edu.cn/jwglxt',
      );
      final model = buildModel(preferences: prefs);

      await model.removeSchool('https://b.example.edu.cn/jwglxt');
      expect(model.schools.any((item) => item.contains('/b.')), isFalse);
      expect(model.schools.any((item) => item.contains('/a.')), isTrue);
      expect(
        prefs.currentSchool,
        'https://a.example.edu.cn/jwglxt',
        reason: '当前地址不该被删',
      );
    });
  });

  group('课表本地缓存与静默更新', () {
    test('有缓存且距上次抓取在最小间隔内：直接展示缓存，不联网', () async {
      final fake = FakeBackend();
      final model = bootRig(
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

      await model.boot();

      expect(model.status, AppStatus.ready);
      expect(model.schedule, isNotNull);
      expect(model.schedule!.entries, isNotEmpty);
      expect(fake.fetchCount, 0, reason: '刚抓过（在最小间隔内），不应再联网');
      model.dispose();
    });

    test('有缓存且超过最小间隔：先展示缓存，同时后台静默刷新一次', () async {
      final fake = FakeBackend();
      final model = bootRig(
        backend: fake,
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        cache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: sampleSchedule(),
            fetchedAt: DateTime.now().subtract(const Duration(hours: 1)),
          ),
        ),
      );

      await model.boot();
      await Future<void>.delayed(Duration.zero);

      expect(model.status, AppStatus.ready);
      expect(model.schedule, isNotNull);
      expect(fake.fetchCount, 1, reason: '超过最小间隔应后台静默刷一次');
      model.dispose();
    });

    test('换校后旧学校的缓存被丢弃，不展示', () async {
      final model = bootRig(
        cache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: 'https://other.example.edu.cn/jwglxt',
            schedule: sampleSchedule(),
            fetchedAt: DateTime.now(),
          ),
        ),
      );

      await model.boot();

      expect(model.status, AppStatus.needLogin, reason: '缓存是别的学校的，不能拿来看');
      expect(model.schedule, isNull);
      model.dispose();
    });

    test('抓课表成功后回写缓存', () async {
      final cache = FakeScheduleCache();
      final model = bootRig(cache: cache);

      await model.loadScheduleForTest();

      expect(cache.saveCount, 1);
      expect(cache.lastSaved?.schedule.termId, '2026-2027-1');
      expect(cache.lastSaved?.baseUrl, _baseUrl);
      model.dispose();
    });

    test('退出登录清空缓存', () async {
      final cache = FakeScheduleCache(
        CachedSchedule(
          baseUrl: _baseUrl,
          schedule: sampleSchedule(),
          fetchedAt: DateTime.now(),
        ),
      );
      final model = bootRig(cache: cache);
      model.hydrateForTest(schedule: sampleSchedule());

      await model.signOut();

      expect(cache.clearCount, 1);
      expect(cache.cached, isNull);
      model.dispose();
    });
  });

  group('静默更新开关与间隔', () {
    test('关掉静默更新后，即使超过间隔也不后台刷新', () async {
      final fake = FakeBackend();
      final model = bootRig(
        backend: fake,
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

      await model.boot();
      await Future<void>.delayed(Duration.zero);

      expect(model.status, AppStatus.ready);
      expect(model.schedule, isNotNull);
      expect(fake.fetchCount, 0, reason: '开关关掉就不该静默刷新');
      model.dispose();
    });

    test('间隔可设置：调大后刚抓过不久就不刷新', () async {
      final fake = FakeBackend();
      final model = bootRig(
        backend: fake,
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

      await model.boot();
      await Future<void>.delayed(Duration.zero);

      expect(model.autoRefreshIntervalMinutes, 60);
      expect(fake.fetchCount, 0, reason: '20 分钟 < 60 分钟间隔，不刷新');
      model.dispose();
    });

    test('setAutoRefreshIntervalMinutes 写入并夹取', () async {
      final prefs = Preferences.inMemory();
      final model = bootRig(preferences: prefs);

      await model.setAutoRefreshIntervalMinutes(999);
      expect(model.autoRefreshIntervalMinutes, maxAutoRefreshIntervalMinutes);

      await model.setAutoRefreshIntervalMinutes(15);
      expect(model.autoRefreshIntervalMinutes, 15);
      model.dispose();
    });
  });

  group('调课（渲染层 overlay，按日期）', () {
    test('按日期调课只改渲染，不覆盖原始课表数据', () async {
      final model = bootRig();
      model.hydrateForTest(schedule: sampleSchedule(), week: 1);

      // sampleSchedule 的课在周一（day=1）第 1 节，weeks [1..4]。
      // 把第 1 周周一那天（用 termStart 算出月日）调到周六。
      final start = model.termStart!; // 周一
      final to = start.add(const Duration(days: 5)); // 周六
      await model.addReschedule(
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: to.month,
        toDay: to.day,
      );

      // 原始数据原封不动。
      expect(model.schedule!.entries.single.day, 1);

      // 渲染层：第 1 周被挪到周六。
      final rendered = model.entriesForWeek(1);
      expect(rendered.single.day, 6);
      expect(rendered.single.startPeriod, 1);
      model.dispose();
    });

    test('删除调课后恢复原时间', () async {
      final model = bootRig();
      model.hydrateForTest(schedule: sampleSchedule(), week: 1);

      final start = model.termStart!;
      final to = start.add(const Duration(days: 5));
      final rule = await model.addReschedule(
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: to.month,
        toDay: to.day,
      );
      expect(model.entriesForWeek(1).single.day, 6);

      await model.removeReschedule(rule.id);
      expect(model.entriesForWeek(1).single.day, 1);
      expect(model.reschedules, isEmpty);
      model.dispose();
    });

    test('编辑调课：updateReschedule 改目标日期、保留 id，渲染跟随', () async {
      final model = bootRig();
      model.hydrateForTest(schedule: sampleSchedule(), week: 1);

      final start = model.termStart!;
      final rule = await model.addReschedule(
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: start.add(const Duration(days: 5)).month,
        toDay: start.add(const Duration(days: 5)).day,
      );
      expect(model.entriesForWeek(1).single.day, 6);

      // 把目标日改到 3 天后（周四 = day 4），来源不变。
      final newTo = start.add(const Duration(days: 3));
      await model.updateReschedule(
        rule.id,
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: newTo.month,
        toDay: newTo.day,
      );
      // 仍是同一条（id 不变、数量不变），不是新增。
      expect(model.reschedules, hasLength(1));
      expect(model.reschedules.single.id, rule.id);
      expect(model.reschedules.single.toDay, newTo.day);
      // 渲染跟随新目标日。
      expect(model.entriesForWeek(1).single.day, 4);
      model.dispose();
    });

    test('没匹配到日期的规则不影响渲染', () async {
      final model = bootRig();
      model.hydrateForTest(schedule: sampleSchedule(), week: 1);

      final start = model.termStart!;
      // 调到一个月后、不属于该课的某天（不影响该课实际日期）。
      final other = start.add(const Duration(days: 10));
      final otherTo = other.add(const Duration(days: 1));
      await model.addReschedule(
        fromMonth: other.month,
        fromDay: other.day,
        toMonth: otherTo.month,
        toDay: otherTo.day,
      );
      expect(model.entriesForWeek(1).single.day, 1);
      model.dispose();
    });

    test('跨周调课：调到目标周的课不再被同 id 的原周实例顶掉', () async {
      final model = bootRig();
      // sampleSchedule：一门课周一第 1-2 节，跨第 1-4 周（同 id 的 4 个实例）。
      model.hydrateForTest(schedule: sampleSchedule(), week: 1);

      final start = model.termStart!; // 第 1 周周一
      final to = start.add(const Duration(days: 9)); // 第 2 周周三
      await model.addReschedule(
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: to.month,
        toDay: to.day,
      );

      // 第 1 周唯一的实例被调走 → 本周空。
      expect(model.entriesForWeek(1), isEmpty);

      // 第 2 周：原本周一的实例仍在，且调过来的周三实例也显示
      //（旧实现按 id 去重，这里会被同 id 的原周实例顶掉 → 周三不显示）。
      final week2 = model.entriesForWeek(2);
      expect(week2.length, 2);
      expect(week2.where((e) => e.day == 3).length, 1, reason: '调过来的周三实例必须显示');
      expect(
        week2.where((e) => e.day == 1).length,
        1,
        reason: '原本第 2 周周一的实例仍在',
      );

      // 原始课表数据一个字节都没动。
      expect(model.schedule!.entries.single.day, 1);
      expect(model.schedule!.entries.single.weeks, <int>[1, 2, 3, 4]);
      model.dispose();
    });

    test('合并无冲突：调课与目标日原有课都显示', () async {
      final model = bootRig();
      model.hydrateForTest(
        schedule: Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: const <ScheduleEntry>[
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
              startPeriod: 5,
              endPeriod: 6,
              weeks: <int>[1],
            ),
          ],
        ),
        week: 1,
      );

      final start = model.termStart!;
      final wed = start.add(const Duration(days: 2)); // 周三
      await model.addReschedule(
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: wed.month,
        toDay: wed.day,
      );

      final view = model.rescheduleViewFor(1);
      // 高数调到周三（1-2 节），英语本就在周三（5-6 节），不冲突，都在。
      expect(view.entries.length, 2);
      expect(view.entries.every((e) => e.day == 3), isTrue);
      expect(view.hasConflictOn(3), isFalse);
      expect(view.conflicts, isEmpty);
      model.dispose();
    });

    test('合并冲突：调课优先显示，原课被抑制并记为该天冲突', () async {
      final model = bootRig();
      model.hydrateForTest(
        schedule: Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: const <ScheduleEntry>[
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
          ],
        ),
        week: 1,
      );

      final start = model.termStart!;
      final wed = start.add(const Duration(days: 2)); // 周三
      // 把高数（周一 1-2）调到周三，正好压在英语（周三 1-2）上。
      await model.addReschedule(
        fromMonth: start.month,
        fromDay: start.day,
        toMonth: wed.month,
        toDay: wed.day,
      );

      final view = model.rescheduleViewFor(1);
      // 只显示调课（高数到周三），英语被顶掉。
      expect(view.entries.map((e) => e.id), <String>['a']);
      expect(view.entries.single.day, 3);

      // 冲突记录：周三、被顶掉的是英语、赢家是高数。
      expect(view.hasConflictOn(3), isTrue);
      expect(view.hasConflictOn(1), isFalse);
      final conflict = view.conflicts[3]!.single;
      expect(conflict.displaced.id, 'b');
      expect(conflict.winner.id, 'a');

      // 原始课表两门课都原样在（周一高数、周三英语），未被改动。
      expect(model.schedule!.entries.firstWhere((e) => e.id == 'a').day, 1);
      expect(model.schedule!.entries.firstWhere((e) => e.id == 'b').day, 3);
      model.dispose();
    });
  });

  test('课表缓存往返带上备注（实践课程 / 其他课程）', () {
    final schedule = Schedule(
      termId: '2026-2027-1',
      maxWeeks: 16,
      entries: const <ScheduleEntry>[
        ScheduleEntry(
          id: 'a',
          name: '高等数学',
          day: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: <int>[1],
        ),
      ],
      remarks: const <ScheduleRemark>[
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
    // 模拟真实缓存：序列化 → jsonEncode → 落盘 → 读回 → jsonDecode → 反序列化。
    final encoded = FileScheduleCache.encodeForTest(schedule);
    final back = FileScheduleCache.decodeForTest(
      jsonDecode(jsonEncode(encoded)),
    );
    expect(back, isNotNull);
    expect(back!.remarks, hasLength(2));
    final practical = back.remarks.firstWhere((r) => r.practical);
    expect(practical.content, '生产实习');
    expect(practical.courseName, '金工实习');
    expect(practical.teacher, '王老师');
    expect(practical.weeks, '第18周');
    expect(practical.location, '东校区 车间A');
    final other = back.remarks.firstWhere((r) => !r.practical);
    expect(other.content, '线上自主学习');
    expect(other.teacher, isNull);
  });

  group('回到前台（AppLifecycleListener.onShow）', () {
    // 用"本周一"推出两个时间点，保证与跑测试的真实日期无关：
    //   start       = 上周一 → 今天落在第 2 周
    //   lastSeenDay = 上周日 → 上次看见的是第 1 周
    final today = dayOnly(DateTime.now());
    final start = mondayOf(today).subtract(const Duration(days: 7));
    final lastWeekDay = mondayOf(today).subtract(const Duration(days: 1));

    test('跨天且原本停在当前周：周次跟到新的当前周', () async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: scheduleWithWeeks(<int>[1, 2, 3]),
        week: 1,
        termStart: start,
      );
      // 刚刷新过：只验证跨天，不触发网络请求。
      model.seedLifecycleForTest(
        lastSeenDay: lastWeekDay,
        lastFetchedAt: DateTime.now(),
      );

      await model.onAppShown();

      expect(model.currentWeekOfToday, 2, reason: '前提：今天应在第 2 周');
      expect(model.week, 2, reason: '原本停在当前周，跨天后应跟过去');
      model.dispose();
    });

    test('跨天但用户手翻到了别的周：不被拽回当前周', () async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: scheduleWithWeeks(<int>[1, 2, 3]),
        week: 3,
        termStart: start,
      );
      model.seedLifecycleForTest(
        lastSeenDay: lastWeekDay,
        lastFetchedAt: DateTime.now(),
      );

      await model.onAppShown();

      expect(model.week, 3, reason: '用户主动翻到的周不该被覆盖');
      model.dispose();
    });

    test('没跨天：周次不动', () async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: scheduleWithWeeks(<int>[1, 2, 3]),
        week: 1,
        termStart: start,
      );
      model.seedLifecycleForTest(
        lastSeenDay: today,
        lastFetchedAt: DateTime.now(),
      );

      await model.onAppShown();

      expect(model.week, 1);
      model.dispose();
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
      expect(due(lastFetchedAt: null), isTrue, reason: '不知道上次抓取时间就放行一次');
      expect(
        due(lastFetchedAt: now.subtract(const Duration(minutes: 29))),
        isFalse,
        reason: '未到最小间隔',
      );
      expect(
        due(lastFetchedAt: now.subtract(const Duration(minutes: 31))),
        isTrue,
      );
    });
  });
}
