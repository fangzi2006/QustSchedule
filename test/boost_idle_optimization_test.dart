/// `/boost` 冷启动、空闲帧调度（IdleScheduler）、预热与缓存记忆化回归测试。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/about_page.dart';
import 'package:qustschedule/pages/academic_page.dart';
import 'package:qustschedule/pages/appearance_sheet.dart';
import 'package:qustschedule/pages/captcha_page.dart';
import 'package:qustschedule/pages/changelog_page.dart';
import 'package:qustschedule/pages/debug_page.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/reminder_page.dart';
import 'package:qustschedule/pages/reschedule_page.dart';
import 'package:qustschedule/pages/schedule_page.dart';
import 'package:qustschedule/pages/settings_page.dart';
import 'package:qustschedule/pages/widget_settings_page.dart';
import 'package:qustschedule/src/academic_cache.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/credentials_repository.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/reminder_gateway.dart';
import 'package:qustschedule/src/reminder_service.dart';
import 'package:qustschedule/src/reschedule.dart';
import 'package:qustschedule/src/route_settled.dart';
import 'package:qustschedule/src/safe_json_file.dart';
import 'package:qustschedule/src/schedule_cache.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/session_repository.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:qustschedule/src/updater/update_service.dart';
import 'package:qustschedule/src/widget_planner.dart';
import 'package:qustschedule/src/widget_service.dart';
import 'package:qustschedule/src/widget_style.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/course_tile.dart';
import 'package:qustschedule/widgets/desktop_widget_preview.dart';
import 'package:qustschedule/widgets/floating_dock.dart';
import 'package:qustschedule/widgets/page_skeleton.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';
import 'support/fake_reminder_gateway.dart';
import 'support/fake_widget_gateway.dart';

const String _baseUrl = 'https://jw.example.edu.cn/jwglxt';

/// 最小合法 1x1 透明 PNG，避免 CaptchaPage 测试里触发无效图片解码警告。
const String _validTinyPngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

class _SpyCredentialStore extends InMemoryCredentialStore {
  int hasCalls = 0;
  int getCalls = 0;

  @override
  Future<bool> has(String accountKey) {
    hasCalls++;
    return super.has(accountKey);
  }

  @override
  Future<Credentials?> get(String accountKey) {
    getCalls++;
    return super.get(accountKey);
  }
}

class _ConcurrentSecureStorage extends Fake implements FlutterSecureStorage {
  final List<String> startedKeys = <String>[];
  final Map<String, Completer<String?>> completers =
      <String, Completer<String?>>{};

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) {
    startedKeys.add(key);
    final c = Completer<String?>();
    completers[key] = c;
    return c.future;
  }
}

AppModel _buildTestModel({
  FakeBackend? backend,
  FakeSessionRepository? repository,
  FakeScheduleCache? scheduleCache,
  Preferences? preferences,
  ExamCache? examCache,
  GradesCache? gradesCache,
  CredentialStore? credentials,
}) {
  final fake = backend ?? FakeBackend();
  final repo = repository ?? FakeSessionRepository();
  final creds = credentials ?? InMemoryCredentialStore();
  return AppModel(
    service: ScheduleService(
      credentials: creds,
      cookieStorage: repo,
      backendFactory: (_) => fake,
      baseUrl: _baseUrl,
    ),
    repository: repo,
    credentials: creds,
    preferences: preferences ?? Preferences.inMemory(),
    scheduleCache: scheduleCache ?? FakeScheduleCache(),
    examCache: examCache ?? InMemoryExamCache(),
    gradesCache: gradesCache ?? InMemoryGradesCache(),
    schoolBaseUrl: _baseUrl,
  );
}

Widget _wrapApp(Widget child) => MaterialApp(
  theme: buildLightTheme(),
  locale: const Locale('zh', 'CN'),
  supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
  localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  home: child,
);

void main() {
  tearDown(() {
    ChangelogPage.resetCache();
    LicenseTextPage.resetCache();
    CourseBlock.clearBlockPlanCacheForTest();
    rootBundle.clear();
  });

  group('路由落稳调度与冷启动 I/O 优化', () {
    testWidgets(
      'scheduleAfterRouteSettled 等待入场转场完成，中途退场取消、取消返回（reverse -> forward）仍正常触发',
      (tester) async {
        late _ControllableRoute<void> controlledRoute;
        await tester.pumpWidget(
          _wrapApp(
            Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => const _RouteSettledProbePage(),
                          ),
                        );
                      },
                      child: const Text('push'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        controlledRoute = _ControllableRoute<void>(
                          builder: (_) => const _RouteSettledProbePage(),
                        );
                        Navigator.of(context).push(controlledRoute);
                      },
                      child: const Text('push-controlled'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        _RouteSettledProbePage.ranCount = 0;
        await tester.tap(find.text('push'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 120));
        // 入场动画未结束前绝不抢跑执行。
        expect(_RouteSettledProbePage.ranCount, 0);

        // 在转场中途直接 pop 退场，已注册任务应立即取消，之后也不会补跑。
        Navigator.of(tester.element(find.byType(_RouteSettledProbePage))).pop();
        await tester.pumpAndSettle();
        await tester.pump(const Duration(milliseconds: 300));
        expect(_RouteSettledProbePage.ranCount, 0);

        // 入场中途触发取消返回（forward -> reverse -> forward -> completed），不应作废任务。
        await tester.tap(find.text('push-controlled'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(_RouteSettledProbePage.ranCount, 0);
        controlledRoute.exposedController!.reverse();
        await tester.pump(const Duration(milliseconds: 30));
        controlledRoute.exposedController!.forward();
        await tester.pumpAndSettle();
        expect(_RouteSettledProbePage.ranCount, 1);

        // 若调用方未显式 cancel 但 isMounted 变为 false，回调阶段应安全忽略并不再触发。
        var simulatedMounted = true;
        var orphanRan = false;
        final orphanHandle = scheduleAfterRouteSettled(
          context: tester.element(find.byType(_RouteSettledProbePage)),
          isMounted: () => simulatedMounted,
          task: () => orphanRan = true,
        );
        simulatedMounted = false;
        await tester.pump();
        expect(orphanRan, isFalse);
        expect(orphanHandle.isDone, isTrue);
      },
    );

    test('SecureCredentialStore.get 并发同时发起账号与密码 Keystore 读取', () async {
      final storage = _ConcurrentSecureStorage();
      final store = SecureCredentialStore(storage);

      final future = store.get('20240001');
      expect(storage.startedKeys.length, 2);

      storage.completers[storage.startedKeys[0]]!.complete('20240001');
      storage.completers[storage.startedKeys[1]]!.complete('secret');

      final creds = await future;
      expect(creds, isNotNull);
      expect(creds!.username, '20240001');
      expect(creds.password, 'secret');
    });

    test('SafeJsonFile 超过 16KB 阈值时经 Isolate 解码且保留 .bak 自愈', () async {
      final tempDir = await Directory.systemTemp.createTemp('boost_json_iso_');
      try {
        final file = File('${tempDir.path}/large.json');
        final store = SafeJsonFile(file);

        final bigItems = List<String>.generate(
          400,
          (i) => 'item_${i}_${'z' * 40}',
        );
        final v1 = <String, Object?>{'ver': 1, 'items': bigItems};
        final encodedV1 = jsonEncode(v1);
        expect(encodedV1.length, greaterThan(isolateJsonDecodeThreshold));

        await store.writeJson(() => v1);
        final v2 = <String, Object?>{'ver': 2, 'items': bigItems};
        await store.writeJson(() => v2);

        final readOk = await store.readJson(isValid: (d) => d is Map);
        expect((readOk.data as Map)['ver'], 2);
        expect((readOk.data as Map)['items'], hasLength(400));

        // 破坏主文件后验证能异步从大 .bak 自愈恢复第 1 版。
        await file.writeAsString('{broken payload...');
        final healed = await store.readJson(isValid: (d) => d is Map);
        expect(healed.recoveredFromBackup, isTrue);
        expect((healed.data as Map)['ver'], 1);
      } finally {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      }
    });

    testWidgets('AppModel.boot 仅查询一次支持目录、免重复 credentials.has() 并在空闲帧恢复学业缓存', (
      tester,
    ) async {
      late Directory tempDir;
      var supportDirCalls = 0;

      await tester.runAsync(() async {
        tempDir = await Directory.systemTemp.createTemp('boost_app_boot_');
        final examCache = await FileExamCache.open(directory: tempDir);
        await examCache.save('2026-2027-1', sampleExams());
        final sessionRepo = await FileSessionRepository.open(
          directory: tempDir,
        );
        await sessionRepo.save(snapshotOf(_baseUrl));
        final scheduleCache = await FileScheduleCache.open(directory: tempDir);
        await scheduleCache.save(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: sampleSchedule(),
            fetchedAt: DateTime.now(),
          ),
        );
      });

      final backend = FakeBackend();
      final spyCreds = _SpyCredentialStore();
      final model = AppModel(
        service: ScheduleService(
          credentials: spyCreds,
          cookieStorage: LateSessionRepository(),
          backendFactory: (_) => backend,
          baseUrl: _baseUrl,
        ),
        credentials: spyCreds,
        schoolBaseUrl: _baseUrl,
        supportDirectoryLoader: () async {
          supportDirCalls++;
          return tempDir;
        },
      );

      await tester.runAsync(() async {
        await model.boot();
      });

      // 5 份仓库共享同一支持目录结果，且跳过冗余 credentials.has()。
      expect(supportDirCalls, 1);
      expect(spyCreds.hasCalls, 0);
      // 首帧启动阶段尚未同步读取学业缓存，推迟至空闲帧恢复。
      expect(model.exams, isEmpty);

      // 让 IdleScheduler 在空闲帧触发恢复并完成文件读取。
      await tester.pump();
      await tester.runAsync(() async {
        await model.academicSyncForTest;
        await Future<void>.delayed(const Duration(milliseconds: 100));
      });
      await tester.pump();
      expect(model.exams.length, 2);

      model.dispose();
      await tester.runAsync(() async {
        if (tempDir.existsSync()) {
          await tempDir.delete(recursive: true);
        }
      });
    });

    test(
      'UpdateService.cleanOldUpdateFiles 异步清理过期产物与 .part 碎片并保留当前版本',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'boost_update_clean_',
        );
        try {
          final oldApk = File('${dir.path}/QustSchedule_1.4.0.apk')
            ..writeAsStringSync('old');
          final currentExe = File('${dir.path}/QustSchedule_1.5.0.exe')
            ..writeAsStringSync('cur');
          final newerExe = File('${dir.path}/QustSchedule_1.6.0.exe')
            ..writeAsStringSync('new');
          final partFile = File('${dir.path}/QustSchedule_1.6.0.exe.part')
            ..writeAsStringSync('part');

          final deleted = await UpdateService.cleanOldUpdateFiles(
            currentVersion: '1.5.0',
            targetDirectory: dir,
          );

          expect(deleted, 3);
          expect(oldApk.existsSync(), isFalse);
          expect(currentExe.existsSync(), isFalse);
          expect(partFile.existsSync(), isFalse);
          expect(newerExe.existsSync(), isTrue);
        } finally {
          if (dir.existsSync()) {
            await dir.delete(recursive: true);
          }
        }
      },
    );
  });

  group('控制器记忆化与课表邻近周空闲预热', () {
    test('ScheduleController 与 AcademicController 记忆化命中及变更失效', () async {
      final prefs = Preferences.inMemory();
      await prefs.setTermStart('2026-2027-1', DateTime(2026, 9, 7));
      final model = _buildTestModel(
        preferences: prefs,
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        scheduleCache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: const Schedule(
              termId: '2026-2027-1',
              maxWeeks: 16,
              entries: <ScheduleEntry>[
                ScheduleEntry(
                  id: 'w1',
                  name: '线性代数',
                  teacher: '张老师',
                  location: '弘毅楼 101',
                  day: 1,
                  startPeriod: 1,
                  endPeriod: 2,
                  weeks: <int>[1, 2],
                ),
                ScheduleEntry(
                  id: 'w1b',
                  name: '电路原理',
                  teacher: '王老师',
                  location: '弘毅楼 102',
                  day: 1,
                  startPeriod: 1,
                  endPeriod: 2,
                  weeks: <int>[1, 2],
                ),
              ],
            ),
            fetchedAt: DateTime.now(),
          ),
        ),
      );
      await model.boot();

      final initialRev = model.scheduleDataRevision;
      expect(model.scheduleState.debugRescheduleComputes, 0);
      expect(model.scheduleState.debugConflictComputes, 0);

      final v1 = model.rescheduleViewFor(1);
      final c1 = model.conflictLayoutForWeek(1);
      expect(model.scheduleState.debugRescheduleComputes, 1);
      expect(model.scheduleState.debugConflictComputes, 1);

      // 同周重复访问直接命中缓存。
      expect(identical(model.rescheduleViewFor(1), v1), isTrue);
      expect(identical(model.conflictLayoutForWeek(1), c1), isTrue);
      expect(model.scheduleState.debugRescheduleComputes, 1);
      expect(model.scheduleState.debugConflictComputes, 1);

      // 调课规则变动后版本号递增，立即作废缓存重新计算。
      await model.addReschedule(
        fromMonth: 9,
        fromDay: 7,
        toMonth: 9,
        toDay: 14,
      );
      expect(model.scheduleDataRevision, greaterThan(initialRev));
      model.conflictLayoutForWeek(1);
      expect(model.scheduleState.debugRescheduleComputes, 2);
      expect(model.scheduleState.debugConflictComputes, 2);

      // AcademicController.gradeStats 按列表引用记忆化。
      await model.loadAcademicData(termId: '2026-2027-1');
      final statsA = model.gradeStats;
      final statsB = model.gradeStats;
      expect(identical(statsA, statsB), isTrue);
      expect(model.grades.length, 2);

      model.dispose();
    });

    testWidgets('课表页静止后空闲帧预热第 2 周课程块，左滑翻周直接命中布局缓存', (tester) async {
      const schedule = Schedule(
        termId: '2026-2027-1',
        maxWeeks: 8,
        entries: <ScheduleEntry>[
          ScheduleEntry(
            id: 'c1',
            name: '大学物理A',
            teacher: '赵老师',
            location: '高密校区 M2-105',
            day: 2,
            startPeriod: 3,
            endPeriod: 4,
            weeks: <int>[1],
          ),
          ScheduleEntry(
            id: 'c2',
            name: '数据结构与算法设计实践',
            teacher: '钱老师',
            location: '崂山校区 D3-402',
            day: 3,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[2],
          ),
        ],
      );
      final model = _buildTestModel(
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        scheduleCache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: schedule,
            fetchedAt: DateTime.now(),
          ),
        ),
      );
      await model.boot();
      model.goToWeek(1);

      CourseBlock.clearBlockPlanCacheForTest();
      final baseline = CourseBlock.debugBlockPlanSolveCountForTest;
      await tester.pumpWidget(_wrapApp(SchedulePage(model: model)));
      await tester.pump();
      final afterWeek1 = CourseBlock.debugBlockPlanSolveCountForTest;
      expect(afterWeek1, baseline + 1);

      // 等待邻近周空闲帧分片预热完成第 2 周的排版计算。
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      final afterPrewarm = CourseBlock.debugBlockPlanSolveCountForTest;
      expect(afterPrewarm, greaterThanOrEqualTo(baseline + 2));

      // 切到第 2 周并稳定渲染时，不再产生新的 _BlockPlan.solve 计算。
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('数据结构与算法设计实践'), findsOneWidget);
      expect(CourseBlock.debugBlockPlanSolveCountForTest, afterPrewarm);

      model.dispose();
    });

    testWidgets('邻近周预热被轻滑取消并回弹同一周后仍能恢复完成预热', (tester) async {
      const schedule = Schedule(
        termId: '2026-2027-1',
        maxWeeks: 8,
        entries: <ScheduleEntry>[
          ScheduleEntry(
            id: 'c1',
            name: '高等数学A',
            teacher: '赵老师',
            location: '高密校区 M2-105',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1],
          ),
          ScheduleEntry(
            id: 'c2',
            name: '离散数学实验',
            teacher: '孙老师',
            location: '崂山校区 S1-301',
            day: 4,
            startPeriod: 5,
            endPeriod: 6,
            weeks: <int>[2],
          ),
        ],
      );
      final model = _buildTestModel(
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        scheduleCache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: schedule,
            fetchedAt: DateTime.now(),
          ),
        ),
      );
      await model.boot();
      model.goToWeek(1);

      CourseBlock.clearBlockPlanCacheForTest();
      final baseline = CourseBlock.debugBlockPlanSolveCountForTest;
      await tester.pumpWidget(_wrapApp(SchedulePage(model: model)));
      await tester.pump();
      expect(CourseBlock.debugBlockPlanSolveCountForTest, baseline + 1);

      // 预热句柄尚未完成时轻微拖动页面后松手回弹停回第 1 周。
      await tester.drag(find.byType(PageView), const Offset(-20, 0));
      await tester.pumpAndSettle();
      expect(model.week, 1);
      expect(
        CourseBlock.debugBlockPlanSolveCountForTest,
        greaterThanOrEqualTo(baseline + 2),
      );

      // 再翻到第 2 周应直接命中预热缓存。
      final solvedBeforeFlip = CourseBlock.debugBlockPlanSolveCountForTest;
      await tester.tap(find.byIcon(Icons.chevron_right_rounded));
      await tester.pumpAndSettle();
      expect(find.textContaining('离散数学实验'), findsOneWidget);
      expect(CourseBlock.debugBlockPlanSolveCountForTest, solvedBeforeFlip);

      model.dispose();
    });
  });

  group('外壳按需挂载与各二级页面优化验收', () {
    testWidgets('HomeShell 冷启动保持离屏页按需挂载且不重建 HomeShell，切入学业才加载', (tester) async {
      final backend = FakeBackend();
      final model = _buildTestModel(
        backend: backend,
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        scheduleCache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: sampleSchedule(),
            fetchedAt: DateTime.now(),
          ),
        ),
      );
      await model.boot();

      var homeShellBuilds = 0;
      await tester.pumpWidget(
        _wrapApp(
          Builder(
            builder: (context) {
              homeShellBuilds++;
              return HomeShell(model: model);
            },
          ),
        ),
      );

      // 首帧及停留在课表页期间，离屏设置页与学业页均保持按需未挂载，零额外网络请求。
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.byType(AcademicPage), findsNothing);
      expect(backend.examsCount, 0);
      expect(backend.gradesCount, 0);

      final baselineBuilds = homeShellBuilds;
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(SettingsPage), findsNothing);
      expect(find.byType(AcademicPage), findsNothing);
      expect(homeShellBuilds, baselineBuilds);
      expect(backend.examsCount, 0);
      expect(backend.gradesCount, 0);

      // 真正点击 Dock「学业」激活标签页后，按需建页并发起学业网络请求。
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('学业'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(AcademicPage), findsOneWidget);
      expect(backend.examsCount, 1);
      expect(backend.gradesCount, 1);

      model.dispose();
    });

    testWidgets('AcademicPage 使用懒加载 Sliver，大量成绩时首帧仅构建视口附近卡片', (tester) async {
      final manyGrades = <GradeItem>[
        for (var i = 0; i < 60; i++)
          GradeItem(
            courseName: '课程编号_${i.toString().padLeft(2, '0')}',
            courseCode: 'C$i',
            credit: 2.0,
            gradePoint: 3.8,
            rawScore: '88',
            numericScore: 88,
            courseNature: '必修',
            courseCategory: '专业必修',
            examNature: '正常考试',
            termId: '2026-2027-1',
          ),
      ];
      final backend = FakeBackend(
        examsBehavior: (_, _) async => const <ExamItem>[],
        gradesBehavior: (_, _) async => manyGrades,
      );
      final model = _buildTestModel(backend: backend);
      await model.boot();
      await model.loadAcademicData(termId: '2026-2027-1');

      await tester.pumpWidget(_wrapApp(AcademicPage(model: model)));
      await tester.pumpAndSettle();

      // 首页仅构建可视区和缓存区元素，最后第 59 条记录不应被同步建树。
      expect(find.text('课程编号_00'), findsOneWidget);
      expect(find.text('课程编号_59'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('课程编号_59'),
        400,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('课程编号_59'), findsOneWidget);

      model.dispose();
    });

    testWidgets('AppearanceSheet 与 ReschedulePage 仅响应 prefsNotifier，隔离无关模型通知', (
      tester,
    ) async {
      final model = _buildTestModel();
      await model.boot();

      await tester.pumpWidget(
        _wrapApp(
          Builder(
            builder: (context) => Scaffold(
              body: Column(
                children: <Widget>[
                  ElevatedButton(
                    onPressed: () => showAppearanceSheet(context, model),
                    child: const Text('open-sheet'),
                  ),
                  Expanded(child: ReschedulePage(model: model)),
                ],
              ),
            ),
          ),
        ),
      );

      // 1. 验证 ReschedulePage 对提示与周次通知零重建，对调课偏好变化正常更新。
      model.hints.showHint('无关提示', error: true);
      model.goToWeek(3);
      await tester.pump();
      expect(find.text('暂无调课记录'), findsOneWidget);

      await model.addReschedule(
        fromMonth: 10,
        fromDay: 1,
        toMonth: 10,
        toDay: 8,
      );
      await tester.pump();
      expect(find.text('暂无调课记录'), findsNothing);
      expect(find.textContaining('10 月 1 日'), findsOneWidget);

      // 2. 打开 AppearanceSheet 后验证 Slider 渲染且可关闭清理。
      await tester.tap(find.text('open-sheet'));
      await tester.pumpAndSettle();
      final sliders = find.byType(Slider);
      expect(sliders, findsNWidgets(2));

      Navigator.of(tester.element(sliders.first)).pop();
      await tester.pumpAndSettle();
      model.dispose();
    });

    testWidgets('CaptchaPage 缓存验证码 Base64 解码字节，无关重建不重复解码', (tester) async {
      var decodeCalls = 0;
      final backend = FakeBackend(
        loginBehavior: (_, _) async => const CaptchaState(
          continuationId: 'c1',
          imageBase64: _validTinyPngBase64,
          mimeType: 'image/png',
        ),
      );
      final model = _buildTestModel(backend: backend);
      await model.signIn('20240001', 'pw');
      expect(model.status, AppStatus.needCaptcha);

      final hostNotifier = ValueNotifier<int>(0);
      await tester.pumpWidget(
        _wrapApp(
          ValueListenableBuilder<int>(
            valueListenable: hostNotifier,
            builder: (context, _, _) => CaptchaPage(
              model: model,
              base64Decoder: (raw) {
                decodeCalls++;
                return base64Decode(raw);
              },
            ),
          ),
        ),
      );
      await tester.pump();
      expect(decodeCalls, 1);

      // 仅宿主重建时 Base64 未变化，禁止再次触发解码。
      hostNotifier.value = 1;
      await tester.pump();
      hostNotifier.value = 2;
      await tester.pump();
      expect(decodeCalls, 1);

      // 刷新拿到新验证码字符串后才触发第二次解码。
      await model.refreshCaptcha();
      await tester.pump();
      expect(decodeCalls, 2);

      hostNotifier.dispose();
      model.dispose();
    });

    testWidgets('DebugPage 原始行折叠态不生成缩进 JSON，展开后才懒格式化', (tester) async {
      final backend = FakeBackend();
      backend.lastScheduleRawBody = '{"kbList":[]}';
      backend.lastScheduleRows = List<Map<String, dynamic>>.generate(
        25,
        (i) => <String, dynamic>{
          'kcmc': '课程_$i',
          'xqj': '1',
          'jcs': '1-2',
          'zcd': '1-16周',
          'uniqueMarker': 'SECRET_INDENT_MARKER_$i',
        },
      );
      final model = _buildTestModel(
        backend: backend,
        repository: FakeSessionRepository(snapshotOf(_baseUrl)),
        scheduleCache: FakeScheduleCache(
          CachedSchedule(
            baseUrl: _baseUrl,
            schedule: sampleSchedule(),
            fetchedAt: DateTime.now(),
          ),
        ),
      );
      await model.boot();
      await model.loadScheduleForTest();

      await tester.pumpWidget(_wrapApp(DebugPage(model: model)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('原始课表'));
      await tester.pumpAndSettle();

      // 折叠态看不到内部缩进字段名。
      expect(find.textContaining('SECRET_INDENT_MARKER_0'), findsNothing);
      expect(find.text('复制这行 JSON'), findsNothing);

      await tester.tap(find.textContaining('课程_0').first);
      await tester.pumpAndSettle();

      expect(find.textContaining('SECRET_INDENT_MARKER_0'), findsOneWidget);
      expect(find.text('复制这行 JSON'), findsOneWidget);

      model.dispose();
    });

    testWidgets('LicenseTextPage 分段重排预处理、支持 loadParagraphs 缓存复用与懒列表渲染', (
      tester,
    ) async {
      final paragraphs = LicenseTextPage.reflowParagraphs(
        'Line one\r\ncontinued.\r\n\r\nSecond paragraph\nline two.\n\n  \nThird.\n',
      );
      expect(paragraphs, <String>[
        'Line one continued.',
        'Second paragraph line two.',
        'Third.',
      ]);

      LicenseTextPage.resetCache();
      final first = await tester.runAsync(
        () => LicenseTextPage.loadParagraphs(),
      );
      final second = await tester.runAsync(
        () => LicenseTextPage.loadParagraphs(),
      );
      expect(first, isNotNull);
      expect(first, isNotEmpty);
      expect(identical(first, second), isTrue);

      await tester.pumpWidget(_wrapApp(const LicenseTextPage()));
      // 命中缓存后首帧直接渲染文本，不先展示全屏转圈。
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('GNU GENERAL PUBLIC LICENSE'), findsOneWidget);
      expect(find.byType(ListView), findsOneWidget);
    });

    test('reflowLicenseBytes 可在真实后台 Isolate 中解码并分段重排协议全文', () async {
      final rawBytes = Uint8List.fromList(
        utf8.encode('First line\r\nwrapped.\r\n\r\nSecond\nparagraph.\n'),
      );
      final paragraphs = await Isolate.run(() => reflowLicenseBytes(rawBytes));
      expect(paragraphs, <String>['First line wrapped.', 'Second paragraph.']);
    });

    testWidgets('ReminderPage 入场动画与原生状态查询并行执行：滑入期不抢跑重绘，落稳瞬间直出结果', (
      tester,
    ) async {
      final model = _buildTestModel();
      final gateway = FakeReminderGateway();
      final service = ReminderService(
        model: model,
        gateway: gateway,
        debounce: const Duration(milliseconds: 1),
      );

      await tester.pumpWidget(
        _wrapApp(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ReminderPage(model: model, service: service),
                    ),
                  );
                },
                child: const Text('open-reminder'),
              ),
            ),
          ),
        ),
      );

      expect(gateway.statusCount, 0);
      await tester.tap(find.text('open-reminder'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      // 后台线程状态查询立即与 260ms 滑入动画并行启动，但动画期间不提前提交 UI 状态变更。
      expect(gateway.statusCount, 1);
      expect(find.text('查询中...'), findsWidgets);

      await tester.pumpAndSettle();
      // 落稳瞬间直接消费并行查询结果，不发起二次查询，UI 立刻展示真实权限状态。
      expect(gateway.statusCount, 1);
      expect(find.text('查询中...'), findsNothing);

      service.dispose();
      model.dispose();
    });

    testWidgets('ReminderPage 慢速初始查询晚于落稳返回时不丢失，且不会覆盖中途用户触发的新状态', (
      tester,
    ) async {
      final model = _buildTestModel();
      final firstCompleter = Completer<ReminderRuntimeStatus>();
      final gateway = _SlowFirstStatusGateway(firstCompleter);
      final service = ReminderService(
        model: model,
        gateway: gateway,
        debounce: const Duration(milliseconds: 1),
      );

      await tester.pumpWidget(
        _wrapApp(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ReminderPage(model: model, service: service),
                    ),
                  );
                },
                child: const Text('open-slow-reminder'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-slow-reminder'));
      await tester.pumpAndSettle();
      // 初始查询仍未返回，落稳后继续显示查询中。
      expect(gateway.statusCount, 1);
      expect(find.text('查询中...'), findsWidgets);

      // 慢查询在落稳后完成，UI 立即更新（scheduled = 7, exactAlarmAllowed = true）。
      firstCompleter.complete(
        const ReminderRuntimeStatus(
          notificationPermission: true,
          notificationsEnabled: true,
          exactAlarmAllowed: true,
          batteryOptimizationIgnored: true,
          scheduled: 7,
          style: 'banner',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('查询中...'), findsNothing);
      expect(find.text('7 条'), findsOneWidget);
      expect(find.text('精确闹钟'), findsOneWidget);

      // 退回后再测一次：慢初始查询尚未返回时用户主动切换开关，晚到的旧结果不得覆盖新状态。
      Navigator.of(tester.element(find.byType(ReminderPage))).pop();
      await tester.pumpAndSettle();

      final staleCompleter = Completer<ReminderRuntimeStatus>();
      final gateway2 = _SlowFirstStatusGateway(
        staleCompleter,
        statusValue: const ReminderRuntimeStatus(
          notificationPermission: true,
          notificationsEnabled: true,
          exactAlarmAllowed: false,
          batteryOptimizationIgnored: false,
          scheduled: 2,
          style: 'banner',
        ),
      );
      final service2 = ReminderService(
        model: model,
        gateway: gateway2,
        debounce: const Duration(milliseconds: 1),
      );
      await tester.pumpWidget(
        _wrapApp(
          Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ReminderPage(model: model, service: service2),
                    ),
                  );
                },
                child: const Text('open-race-reminder'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('open-race-reminder'));
      await tester.pumpAndSettle();
      expect(gateway2.statusCount, 1);

      // 用户点击开关触发新一次刷新（返回 scheduled = 2, exactAlarmAllowed = false）。
      await tester.tap(find.byType(Switch).first);
      await tester.pumpAndSettle();
      expect(gateway2.statusCount, 2);
      expect(find.text('2 条'), findsOneWidget);
      expect(find.text('精确闹钟'), findsNothing);

      // 此时初始慢查询携带过期 scheduled = 99 / exactAlarmAllowed = true 晚到，应被 epoch 守卫丢弃。
      staleCompleter.complete(
        const ReminderRuntimeStatus(
          notificationPermission: true,
          notificationsEnabled: true,
          exactAlarmAllowed: true,
          batteryOptimizationIgnored: true,
          scheduled: 99,
          style: 'banner',
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('2 条'), findsOneWidget);
      expect(find.text('99 条'), findsNothing);
      expect(find.text('精确闹钟'), findsNothing);

      service2.dispose();
      service.dispose();
      model.dispose();
    });

    testWidgets(
      'ChangelogPage、WidgetSettingsPage 与 DebugPage 推入期间保持轻量骨架零重子树干扰，落稳直出完整内容',
      (tester) async {
        final model = _buildTestModel();
        await model.boot();
        final widgetGateway = FakeDesktopWidgetGateway(
          pinnedCounts: const <DesktopWidgetKind, int>{
            DesktopWidgetKind.today: 2,
          },
        );
        final widgetService = DesktopWidgetService(
          model: model,
          gateway: widgetGateway,
          debounce: const Duration(milliseconds: 1),
        );

        final releases = <ReleaseLog>[
          for (var i = 1; i <= 6; i++)
            ReleaseLog(
              version: '1.$i.0',
              date: '2026-0$i-01',
              description: '版本说明_$i',
              sections: <LogSection>[
                LogSection(title: '优化', items: <String>['改进项_$i']),
              ],
            ),
        ];

        await tester.pumpWidget(
          _wrapApp(
            Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ChangelogPage(initialReleases: releases),
                          ),
                        );
                      },
                      child: const Text('open-changelog'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => WidgetSettingsPage(
                              model: model,
                              widgetService: widgetService,
                            ),
                          ),
                        );
                      },
                      child: const Text('open-widget-settings'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DebugPage(model: model),
                          ),
                        );
                      },
                      child: const Text('open-debug'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // 1. ChangelogPage：滑入期间仅骨架占位，绝不提前挂载 SelectionArea 或大段文本
        await tester.tap(find.text('open-changelog'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(CardListTransitionPlaceholder), findsOneWidget);
        expect(find.byType(SelectionArea), findsNothing);
        expect(find.text('v1.1.0'), findsNothing);

        await tester.pumpAndSettle();
        expect(find.byType(SelectionArea), findsOneWidget);
        expect(find.text('v1.1.0'), findsOneWidget);
        expect(find.text('v1.3.0'), findsOneWidget);

        Navigator.of(tester.element(find.byType(ChangelogPage))).pop();
        await tester.pumpAndSettle();

        // 2. WidgetSettingsPage：滑入期间并行查询已添加数量且不构建重预览舞台，落稳瞬间直出
        expect(widgetGateway.pinnedQueryCount, 0);
        await tester.tap(find.text('open-widget-settings'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(widgetGateway.pinnedQueryCount, 1);
        expect(
          find.byType(PreviewSettingsTransitionPlaceholder),
          findsOneWidget,
        );
        expect(find.byType(DesktopWidgetPreview), findsNothing);

        await tester.pumpAndSettle();
        expect(widgetGateway.pinnedQueryCount, 1);
        expect(find.byType(DesktopWidgetPreview), findsOneWidget);
        expect(find.textContaining('桌面上已有 2 个'), findsOneWidget);

        Navigator.of(tester.element(find.byType(WidgetSettingsPage))).pop();
        await tester.pumpAndSettle();

        // 3. DebugPage：滑入期间不构建 TabBarView/SelectionArea，落稳后直出
        await tester.tap(find.text('open-debug'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(find.byType(CardListTransitionPlaceholder), findsOneWidget);
        expect(find.byType(TabBarView), findsNothing);

        await tester.pumpAndSettle();
        expect(find.byType(TabBarView), findsOneWidget);
        expect(find.byType(SelectionArea), findsOneWidget);

        widgetService.dispose();
        model.dispose();
      },
    );

    testWidgets(
      'RouteSettledStateMixin 处于 offstage 时保持未落稳，解除 offstage 后必定触发一次 onRouteSettled 且 ReminderPage 安全提交',
      (tester) async {
        var settledCalls = 0;
        final model = _buildTestModel();
        final completer = Completer<ReminderRuntimeStatus>();
        final gateway = _SlowFirstStatusGateway(completer);
        final service = ReminderService(
          model: model,
          gateway: gateway,
          debounce: const Duration(milliseconds: 1),
        );
        addTearDown(() {
          service.dispose();
          model.dispose();
        });

        late MaterialPageRoute<void> offstageRoute;
        await tester.pumpWidget(
          _wrapApp(
            Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () {
                    offstageRoute = MaterialPageRoute<void>(
                      builder: (_) => _OffstageSettledSpyPage(
                        onSettled: () => settledCalls++,
                        child: ReminderPage(model: model, service: service),
                      ),
                    );
                    Navigator.of(context).push(offstageRoute);
                  },
                  child: const Text('push-offstage'),
                ),
              ),
            ),
          ),
        );

        await tester.tap(find.text('push-offstage'));
        await tester.pump();
        // 模拟 Hero 预测量或外部将路由置为 offstage（此时 animationProxy 切换为 kAlwaysCompleteAnimation）
        offstageRoute.offstage = true;
        await tester.pump(const Duration(milliseconds: 300));
        expect(settledCalls, 0);

        // 路由仍处于 offstage 期间异步查询完成，不得提前提交 UI
        completer.complete(
          const ReminderRuntimeStatus(
            notificationPermission: true,
            notificationsEnabled: true,
            exactAlarmAllowed: true,
            batteryOptimizationIgnored: true,
            scheduled: 5,
            style: 'banner',
          ),
        );
        await tester.pump();
        expect(settledCalls, 0);

        // 解除 offstage 后必须稳定触发一次 onRouteSettled 且 ReminderPage 正常提交状态
        offstageRoute.offstage = false;
        await tester.pumpAndSettle();

        expect(settledCalls, 1);
        expect(find.text('5 条'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    test(
      'computeWidgetSettingsSnapshots 可在真实后台 Isolate 中并行计算含课程/调课/考试的真实快照与示例快照',
      () async {
        final clock = samplePreviewClock();
        final input = WidgetSnapshotInput.signedIn(
          termId: '2026-2027-1',
          entries: const <ScheduleEntry>[
            ScheduleEntry(
              id: 'c1',
              name: '高等数学',
              day: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: <int>[1, 2, 3, 4],
              location: '弘毅楼 C101',
              teacher: '张老师',
            ),
          ],
          reschedules: const <RescheduleRule>[
            RescheduleRule(
              id: 'r1',
              fromMonth: 9,
              fromDay: 7,
              toMonth: 9,
              toDay: 12,
            ),
          ],
          termStart: DateTime(2026, 9, 7),
          timetables: defaultTimetables(),
          sectionCounts: defaultSectionCounts,
          maxWeek: 20,
          styles: DesktopWidgetConfigSet.defaults(),
          now: DateTime(2026, 9, 7, 8, 0),
          exams: <ExamItem>[
            ExamItem(
              courseName: '高等数学期末',
              startTime: DateTime(2026, 9, 9, 9, 0),
              endTime: DateTime(2026, 9, 9, 11, 0),
              rawTimeStr: '2026-09-09(09:00-11:00)',
              classroom: '弘毅楼 A201',
              seatNumber: '12',
              examForm: '闭卷',
            ),
          ],
        );

        final result = await Isolate.run(
          () => computeWidgetSettingsSnapshots(clock, input),
        );
        expect(result.sample.days, isNotEmpty);
        expect(result.real, isNotNull);
        expect(result.real!.signedIn, isTrue);
        expect(result.real!.days, isNotEmpty);
      },
    );

    testWidgets(
      'WidgetSettingsPage 推入路由走后台并行快照准备（0 次同步 buildSnapshot），DebugPage 滑入末期切换 Tab 落稳一致',
      (tester) async {
        final model = _buildTestModel();
        await model.boot();
        final gateway = FakeDesktopWidgetGateway(
          pinnedCounts: const <DesktopWidgetKind, int>{
            DesktopWidgetKind.today: 2,
          },
        );
        final widgetService = _SpySnapshotWidgetService(
          model: model,
          gateway: gateway,
        );
        addTearDown(() {
          widgetService.dispose();
          model.dispose();
        });

        await tester.pumpWidget(
          _wrapApp(
            Builder(
              builder: (context) => Scaffold(
                body: Column(
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => WidgetSettingsPage(
                              model: model,
                              widgetService: widgetService,
                            ),
                          ),
                        );
                      },
                      child: const Text('push-widget-bg'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => DebugPage(model: model),
                          ),
                        );
                      },
                      child: const Text('push-debug-tab'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        // 1. 推入 WidgetSettingsPage：滑入期间并行走 captureSnapshotInput，落稳时不阻塞 UI 线程同步构建
        await tester.tap(find.text('push-widget-bg'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(widgetService.captureInputCalls, 1);
        expect(widgetService.syncBuildCalls, 0);

        await tester.pumpAndSettle();
        expect(widgetService.syncBuildCalls, 0);
        expect(find.byType(DesktopWidgetPreview), findsOneWidget);

        Navigator.of(tester.element(find.byType(WidgetSettingsPage))).pop();
        await tester.pumpAndSettle();

        // 2. DebugPage 在 240ms（TabBarView 挂载前 20ms）点击「原始课表」Tab，落稳后准确落在目标页签
        await tester.tap(find.text('push-debug-tab'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 240));
        await tester.tap(find.text('原始课表'));
        await tester.pump(const Duration(milliseconds: 20));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('还没有获取过课表'), findsOneWidget);
      },
    );

    testWidgets('过渡占位骨架在 200px 极窄分屏下零溢出且屏蔽无障碍语义遍历', (tester) async {
      tester.view.physicalSize = const Size(200, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      for (final placeholder in const <Widget>[
        CardListTransitionPlaceholder(),
        DocumentTransitionPlaceholder(),
        PreviewSettingsTransitionPlaceholder(),
      ]) {
        await tester.pumpWidget(_wrapApp(Scaffold(body: placeholder)));
        expect(tester.takeException(), isNull);
        expect(
          find.descendant(
            of: find.byWidget(placeholder),
            matching: find.byType(ExcludeSemantics),
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('WidgetSettingsPage 落稳帧通过 SliverChildBuilderDelegate 懒构建屏外分组', (
      tester,
    ) async {
      final model = _buildTestModel();
      await model.boot();
      final widgetService = DesktopWidgetService(
        model: model,
        gateway: FakeDesktopWidgetGateway(
          pinnedCounts: const <DesktopWidgetKind, int>{
            DesktopWidgetKind.today: 2,
          },
        ),
        debounce: const Duration(milliseconds: 1),
      );
      addTearDown(() {
        widgetService.dispose();
        model.dispose();
      });

      await tester.pumpWidget(
        _wrapApp(
          WidgetSettingsPage(model: model, widgetService: widgetService),
        ),
      );
      await tester.pumpAndSettle();

      final customScrollView = tester.widget<CustomScrollView>(
        find.byType(CustomScrollView),
      );
      final settingsSliverList =
          (customScrollView.slivers.last as SliverPadding).child! as SliverList;
      expect(settingsSliverList.delegate, isA<SliverChildBuilderDelegate>());

      // 首屏可见顶部引导与精选预设，但屏外底部的「内容显示」与「恢复默认」尚未建树。
      expect(find.text('精选预设'), findsOneWidget);
      expect(find.text('内容显示'), findsNothing);
      expect(find.text('恢复「今日课表」默认样式'), findsNothing);

      // 向下滚动后按需构建屏外分组与底部恢复按钮。
      await tester.scrollUntilVisible(
        find.text('恢复「今日课表」默认样式'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('内容显示'), findsOneWidget);
      expect(find.text('恢复「今日课表」默认样式'), findsOneWidget);
    });

    testWidgets('WidgetSettingsPage 入场滑行中途源数据更新不抢占 UI 线程同步建快照，落稳后自动补齐最新数据', (
      tester,
    ) async {
      final model = _buildTestModel();
      await model.boot();
      final widgetService = _SpySnapshotWidgetService(
        model: model,
        gateway: FakeDesktopWidgetGateway(
          pinnedCounts: const <DesktopWidgetKind, int>{
            DesktopWidgetKind.today: 2,
          },
        ),
        debounce: const Duration(seconds: 10),
        now: () => DateTime(2026, 9, 9, 10, 0),
      );
      addTearDown(() {
        widgetService.dispose();
        model.dispose();
      });

      await tester.pumpWidget(
        _wrapApp(
          Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => WidgetSettingsPage(
                      model: model,
                      widgetService: widgetService,
                    ),
                  ),
                ),
                child: const Text('打开小组件设置'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开小组件设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // 入场动画进行中：后台已完成初始快照捕获，但 UI 线程未执行同步 buildSnapshot。
      expect(find.byType(PreviewSettingsTransitionPlaceholder), findsOneWidget);
      expect(widgetService.captureInputCalls, 1);
      expect(widgetService.syncBuildCalls, 0);

      // 在 260ms 滑入中途更新课表源数据并触发 model.notifyListeners()：
      // 绝不在滑入帧同步执行 buildSnapshot() 或中途切换页面主体。
      model.hydrateForTest(
        schedule: sampleSchedule(),
        termStart: DateTime(2026, 9, 7),
        week: 1,
      );
      await tester.pump(const Duration(milliseconds: 40));
      expect(widgetService.syncBuildCalls, 0);
      expect(find.byType(PreviewSettingsTransitionPlaceholder), findsOneWidget);

      // 动画落稳后一次性补齐最新真实快照并自动切换为「实时课表」。
      await tester.pumpAndSettle();
      expect(widgetService.syncBuildCalls, 1);
      expect(find.text('实时课表'), findsOneWidget);

      // 先卸载页面并释放 10s 防抖定时器，避免触发测试框架 pending timer 断言。
      await tester.pumpWidget(const SizedBox.shrink());
      widgetService.dispose();
    });

    testWidgets('WidgetSettingsPage 在窄分屏与桌面大视口下跨 0% 不透明度边界拖动滑块不丢手势、无溢出', (
      tester,
    ) async {
      for (final size in const <Size>[Size(360, 520), Size(1280, 900)]) {
        tester.view.physicalSize = size;
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        final model = _buildTestModel();
        await model.boot();
        final widgetService = DesktopWidgetService(
          model: model,
          gateway: FakeDesktopWidgetGateway(
            pinnedCounts: const <DesktopWidgetKind, int>{
              DesktopWidgetKind.today: 2,
            },
          ),
          debounce: const Duration(milliseconds: 1),
        );

        await tester.pumpWidget(
          _wrapApp(
            WidgetSettingsPage(model: model, widgetService: widgetService),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        final scrollable = find.byType(Scrollable).first;
        // 先滚动构建出「背景不透明度」与对应滑块，再确保滑块完整落在吸顶预览区下方。
        await tester.scrollUntilVisible(
          find.text('背景不透明度'),
          80,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        final opacitySlider = find.byType(Slider).first;
        final headerBottom = tester.getBottomLeft(find.text('添加到桌面')).dy + 16;
        // 若滑块仍被底部截断则继续上拉，若被吸顶预览压住则下移露出。
        for (var guard = 0; guard < 8; guard++) {
          final rect = tester.getRect(opacitySlider);
          if (rect.top >= headerBottom && rect.bottom <= size.height - 4) {
            break;
          }
          final dy = rect.bottom > size.height - 4 ? -48.0 : 48.0;
          await tester.drag(scrollable, Offset(0, dy));
          await tester.pumpAndSettle();
        }
        expect(find.text('背景不透明度'), findsOneWidget);
        expect(find.text('卡片圆角'), findsOneWidget);

        // 持续按住「背景不透明度」滑块拖至 0%（折叠卡片圆角）再拉回约 50% 后松手落盘。
        final sliderRect = tester.getRect(opacitySlider);
        final gesture = await tester.startGesture(sliderRect.center);
        await tester.pump();
        await gesture.moveTo(Offset(sliderRect.left + 8, sliderRect.center.dy));
        await tester.pump();
        expect(find.text('0%'), findsOneWidget);
        expect(find.text('卡片圆角'), findsNothing);
        expect(tester.takeException(), isNull);

        await gesture.moveTo(sliderRect.center);
        await tester.pump();
        expect(find.text('卡片圆角'), findsOneWidget);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          model.widgetStyleOf(DesktopWidgetKind.today).backgroundOpacity,
          greaterThan(0.2),
        );

        // 滚至底部校验懒构建的「排版与字号」与「恢复默认」均正常。
        await tester.scrollUntilVisible(
          find.text('恢复「今日课表」默认样式'),
          240,
          scrollable: scrollable,
        );
        await tester.pumpAndSettle();
        expect(find.text('恢复「今日课表」默认样式'), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        widgetService.dispose();
        model.dispose();
      }
    });
  });
}

class _OffstageSettledSpyPage extends StatefulWidget {
  const _OffstageSettledSpyPage({required this.onSettled, required this.child});

  final VoidCallback onSettled;
  final Widget child;

  @override
  State<_OffstageSettledSpyPage> createState() =>
      _OffstageSettledSpyPageState();
}

class _OffstageSettledSpyPageState extends State<_OffstageSettledSpyPage>
    with RouteSettledStateMixin<_OffstageSettledSpyPage> {
  @override
  void onRouteSettled() {
    widget.onSettled();
    super.onRouteSettled();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _SpySnapshotWidgetService extends DesktopWidgetService {
  _SpySnapshotWidgetService({
    required super.model,
    required super.gateway,
    super.debounce,
    super.now,
  });

  int captureInputCalls = 0;
  int syncBuildCalls = 0;

  @override
  WidgetSnapshotInput? captureSnapshotInput() {
    captureInputCalls++;
    return super.captureSnapshotInput();
  }

  @override
  WidgetSnapshot? buildSnapshot() {
    syncBuildCalls++;
    return super.buildSnapshot();
  }
}

class _ControllableRoute<T> extends MaterialPageRoute<T> {
  _ControllableRoute({required super.builder});

  AnimationController? exposedController;

  @override
  AnimationController createAnimationController() {
    exposedController = super.createAnimationController();
    return exposedController!;
  }
}

class _SlowFirstStatusGateway extends FakeReminderGateway {
  _SlowFirstStatusGateway(this._firstCompleter, {super.statusValue});

  final Completer<ReminderRuntimeStatus> _firstCompleter;

  @override
  Future<ReminderRuntimeStatus> status() {
    if (statusCount == 0) {
      statusCount++;
      return _firstCompleter.future;
    }
    return super.status();
  }
}

class _RouteSettledProbePage extends StatefulWidget {
  const _RouteSettledProbePage();

  static int ranCount = 0;

  @override
  State<_RouteSettledProbePage> createState() => _RouteSettledProbePageState();
}

class _RouteSettledProbePageState extends State<_RouteSettledProbePage> {
  RouteSettledHandle? _handle;
  bool _scheduled = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_scheduled) return;
    _scheduled = true;
    _handle = scheduleAfterRouteSettled(
      context: context,
      isMounted: () => mounted,
      task: () => _RouteSettledProbePage.ranCount++,
    );
  }

  @override
  void dispose() {
    _handle?.cancel();
    _handle = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('probe')));
  }
}
