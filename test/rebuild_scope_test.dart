/// 状态频道隔离与 UI 重建范围验证。
///
/// 确保局部提示、刷新转圈、切周与学业更新只在各自最窄的监听区间内刷新，
/// 不会波及顶层路由外壳、[HomeShell]、[SchedulePage] 或课表格子。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/main.dart' show pageForStatus;
import 'package:qustschedule/pages/academic_page.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/schedule_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/widgets/course_tile.dart';
import 'package:qustschedule/widgets/status_popup.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';

AppModel _buildReadyModel() {
  final fake = FakeBackend();
  final model = AppModel(
    service: ScheduleService(
      credentials: InMemoryCredentialStore(),
      cookieStorage: FakeSessionRepository(),
      backendFactory: (_) => fake,
      baseUrl: 'https://jw.example.edu.cn/jwglxt',
    ),
    preferences: Preferences.inMemory(),
    schoolBaseUrl: 'https://jw.example.edu.cn/jwglxt',
  );
  model.hydrateForTest(
    schedule: sampleSchedule(),
    terms: const Terms(
      currentId: '2026-2027-1',
      items: <Term>[
        Term(id: '2026-2027-1', name: '2026-2027-1'),
        Term(id: '2025-2026-2', name: '2025-2026-2'),
      ],
    ),
    week: 1,
    termStart: DateTime(2026, 9, 7),
    exams: sampleExams(),
    grades: sampleGrades(),
  );
  return model;
}

/// 在单次动作与 pump 期间收集重建过的 Widget 类型。
Future<Set<Type>> _captureRebuiltWidgetTypes(
  WidgetTester tester,
  void Function() action,
) async {
  final rebuilt = <Type>{};
  final previous = debugOnRebuildDirtyWidget;
  debugOnRebuildDirtyWidget = (Element element, bool builtOnce) {
    rebuilt.add(element.widget.runtimeType);
    previous?.call(element, builtOnce);
  };
  try {
    action();
    await tester.pump();
  } finally {
    debugOnRebuildDirtyWidget = previous;
  }
  return rebuilt;
}

void main() {
  test('提示、刷新状态、切周与学业通道相互隔离，不触发根模型广播', () {
    final model = _buildReadyModel();
    addTearDown(model.dispose);

    var rootCount = 0;
    var routeCount = 0;
    var hintsCount = 0;
    var scheduleCount = 0;
    var academicCount = 0;
    var refreshCount = 0;
    var weekCount = 0;
    var prefsCount = 0;

    model.addListener(() => rootCount++);
    model.routeNotifier.addListener(() => routeCount++);
    model.hints.addListener(() => hintsCount++);
    model.scheduleState.addListener(() => scheduleCount++);
    model.academicNotifier.addListener(() => academicCount++);
    model.refreshingNotifier.addListener(() => refreshCount++);
    model.weekNotifier.addListener(() => weekCount++);
    model.prefsNotifier.addListener(() => prefsCount++);

    model.setHintForTest('更新中…', scope: HintScope.schedule);
    expect(hintsCount, 1);
    expect(rootCount, 0);
    expect(routeCount, 0);
    expect(scheduleCount, 0);
    expect(academicCount, 0);
    expect(refreshCount, 0);
    expect(weekCount, 0);
    expect(prefsCount, 0);

    model.clearHint();
    expect(hintsCount, 2);
    expect(rootCount, 0);
    expect(routeCount, 0);

    model.scheduleState.setRefreshing(true);
    model.scheduleState.setRefreshing(false);
    expect(refreshCount, 2);
    expect(rootCount, 0);
    expect(routeCount, 0);
    expect(scheduleCount, 0);

    model.goToWeek(2);
    expect(weekCount, 1);
    expect(rootCount, 0);
    expect(routeCount, 0);
    expect(scheduleCount, 0);

    model.academic.notifyDayChanged();
    expect(academicCount, 1);
    expect(rootCount, 0);
    expect(routeCount, 0);
    expect(scheduleCount, 0);
  });

  testWidgets('提示气泡、刷新转圈与切周不会重建顶层路由外壳、HomeShell、SchedulePage 或课程卡片', (
    tester,
  ) async {
    final model = _buildReadyModel();
    addTearDown(model.dispose);

    var routeBuildCount = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: ListenableBuilder(
          listenable: model.routeNotifier,
          builder: (_, _) {
            routeBuildCount++;
            return pageForStatus(model);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    final initialRouteBuilds = routeBuildCount;
    expect(find.byType(HomeShell), findsOneWidget);
    expect(find.byType(CourseBlock), findsWidgets);

    // 1. 课表局部提示显示与清除：只更新弹窗，不重建外壳、课表页及课程卡片。
    final showScheduleHintRebuilt = await _captureRebuiltWidgetTypes(
      tester,
      () => model.setHintForTest('课表已更新', scope: HintScope.schedule),
    );
    expect(find.text('课表已更新'), findsOneWidget);
    expect(showScheduleHintRebuilt.contains(StatusPopup), isTrue);
    expect(showScheduleHintRebuilt.contains(HomeShell), isFalse);
    expect(showScheduleHintRebuilt.contains(SchedulePage), isFalse);
    expect(showScheduleHintRebuilt.contains(CourseBlock), isFalse);
    expect(showScheduleHintRebuilt.contains(AcademicPage), isFalse);
    expect(routeBuildCount, initialRouteBuilds);

    final clearHintRebuilt = await _captureRebuiltWidgetTypes(
      tester,
      model.clearHint,
    );
    expect(find.text('课表已更新'), findsNothing);
    expect(clearHintRebuilt.contains(HomeShell), isFalse);
    expect(clearHintRebuilt.contains(SchedulePage), isFalse);
    expect(clearHintRebuilt.contains(CourseBlock), isFalse);
    expect(routeBuildCount, initialRouteBuilds);

    // 2. 全局提示（如学业更新气泡）：同样不触发课表页、课程卡片及顶层路由重算。
    final showGlobalHintRebuilt = await _captureRebuiltWidgetTypes(
      tester,
      () => model.showAcademicUpdateHintForTest('成绩已更新'),
    );
    expect(find.text('成绩已更新'), findsOneWidget);
    expect(showGlobalHintRebuilt.contains(HomeShell), isFalse);
    expect(showGlobalHintRebuilt.contains(SchedulePage), isFalse);
    expect(showGlobalHintRebuilt.contains(CourseBlock), isFalse);
    expect(routeBuildCount, initialRouteBuilds);
    await tester.pump(const Duration(seconds: 3));

    // 3. 刷新转圈切换：不重建顶层路由外壳、HomeShell 与课表卡片。
    final refreshRebuilt = await _captureRebuiltWidgetTypes(
      tester,
      () => model.scheduleState.setRefreshing(true),
    );
    expect(refreshRebuilt.contains(HomeShell), isFalse);
    expect(refreshRebuilt.contains(SchedulePage), isFalse);
    expect(refreshRebuilt.contains(CourseBlock), isFalse);
    expect(routeBuildCount, initialRouteBuilds);
    model.scheduleState.setRefreshing(false);
    await tester.pump();

    // 4. 切换周次：不触发顶层路由外壳或 HomeShell 重建。
    final weekRebuilt = await _captureRebuiltWidgetTypes(
      tester,
      () => model.goToWeek(2),
    );
    expect(weekRebuilt.contains(HomeShell), isFalse);
    expect(routeBuildCount, initialRouteBuilds);
  });
}
