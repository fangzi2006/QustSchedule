/// 桌面小组件配置页与快照规划边界测试。
///
/// 覆盖：
/// - 取消页内模拟预览后，展示小窗/分屏对着桌面调节引导卡与一键添加到桌面按钮；
/// - 各小组件形态精准按需显示开关（Next 移除无效的已结束课程/信息密度/标题栏）、0% 透明隐藏圆角滑块；
/// - 预设与密度解耦、滑块拖动不触发冗余快照构建、恢复默认支持一键撤销；
/// - 360×640 窄屏 + 2.0× 系统超大字体零溢出；
/// - 周末/周日同步覆盖完整 14 天周视图与学期结束后周数推进规划边界。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/widget_settings_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/reschedule.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:qustschedule/src/widget_gateway.dart';
import 'package:qustschedule/src/widget_planner.dart';
import 'package:qustschedule/src/widget_service.dart';
import 'package:qustschedule/src/widget_style.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';

const String _baseUrl = 'https://jw.example.edu.cn/jwglxt';

class _FakeGateway implements DesktopWidgetGateway {
  int syncCount = 0;
  DesktopWidgetKind? lastPinnedKind;
  Map<DesktopWidgetKind, int> pinnedCounts = const <DesktopWidgetKind, int>{};

  @override
  Future<bool> syncSnapshot(String payloadJson) async {
    syncCount++;
    return true;
  }

  @override
  Future<void> clearSnapshot() async {}

  @override
  Future<bool> requestPinWidget(DesktopWidgetKind kind) async {
    lastPinnedKind = kind;
    return true;
  }

  @override
  Future<Map<DesktopWidgetKind, int>> getPinnedCounts() async => pinnedCounts;
}

class _CountingWidgetService extends DesktopWidgetService {
  _CountingWidgetService({
    required super.model,
    required super.gateway,
    super.now,
  }) : super(debounce: const Duration(milliseconds: 5));

  int buildSnapshotCalls = 0;

  @override
  WidgetSnapshot? buildSnapshot() {
    buildSnapshotCalls++;
    return super.buildSnapshot();
  }
}

AppModel _createModel() {
  final model = AppModel(
    service: ScheduleService(
      credentials: InMemoryCredentialStore(),
      cookieStorage: FakeSessionRepository(),
      backendFactory: (_) => FakeBackend(),
      baseUrl: _baseUrl,
    ),
    preferences: Preferences.inMemory(),
    schoolBaseUrl: _baseUrl,
  );
  model.hydrateForTest(
    schedule: sampleSchedule(),
    termStart: DateTime(2026, 9, 7),
    week: 1,
  );
  return model;
}

Widget _wrapApp(Widget child, {double systemTextScale = 1.0}) {
  return MaterialApp(
    theme: buildLightTheme(),
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(systemTextScale)),
      child: inner!,
    ),
    home: child,
  );
}

void main() {
  group('WidgetSettingsPage 小窗引导与配置逻辑', () {
    testWidgets('展示小窗调节引导并取消页内模拟预览，各小组件配置项精准按需显示且支持恢复撤销', (tester) async {
      final model = _createModel();
      final gateway = _FakeGateway()
        ..pinnedCounts = const <DesktopWidgetKind, int>{
          DesktopWidgetKind.today: 2,
        };
      final service = _CountingWidgetService(
        model: model,
        gateway: gateway,
        now: () => DateTime(2026, 9, 9, 10, 40),
      );
      addTearDown(() {
        service.dispose();
        model.dispose();
      });

      await tester.pumpWidget(
        _wrapApp(WidgetSettingsPage(model: model, widgetService: service)),
      );
      await tester.pumpAndSettle();

      // 页面初始化不再额外构图预览快照，展示小窗调节引导与真实桌面数量。
      expect(service.buildSnapshotCalls, 0);
      expect(find.textContaining('小窗或分屏'), findsOneWidget);
      expect(find.text('桌面上已有 2 个「今日课表」'), findsOneWidget);

      final mainScrollable = find.byType(Scrollable).first;

      // 今日课表：可见「课后自动切明日预告」「已结束课程」「显示上课时间」「卡片圆角」。
      await tester.scrollUntilVisible(
        find.text('课后自动切明日预告'),
        200,
        scrollable: mainScrollable,
      );
      expect(find.text('课后自动切明日预告'), findsOneWidget);
      expect(find.text('已结束课程'), findsOneWidget);
      expect(find.text('显示上课时间'), findsOneWidget);

      // 切换密度为紧凑后再套用预设：预设不得覆盖用户的密度选择。
      await tester.scrollUntilVisible(
        find.text('紧凑'),
        -200,
        scrollable: mainScrollable,
      );
      await tester.tap(find.text('紧凑'));
      await tester.pumpAndSettle();
      expect(
        model.widgetStyleOf(DesktopWidgetKind.today).density,
        WidgetDensity.compact,
      );

      // 切到「纯净透明」预设（0% 透明）→ 保留紧凑密度并隐藏「卡片圆角」滑块。
      await tester.scrollUntilVisible(
        find.text('纯净透明'),
        -200,
        scrollable: mainScrollable,
      );
      await tester.tap(find.text('纯净透明'));
      await tester.pumpAndSettle();
      expect(find.text('卡片圆角'), findsNothing);
      expect(model.widgetStyleOf(DesktopWidgetKind.today).backgroundOpacity, 0);
      expect(
        model.widgetStyleOf(DesktopWidgetKind.today).density,
        WidgetDensity.compact,
      );

      // 选中「壁纸取色」主题 → 展示 Android 12+ 说明。
      await tester.tap(find.text('壁纸取色'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Android 12+'), findsWidgets);

      // 持续拖动透明度滑块 10 帧期间，绝不触发 buildSnapshot 重建（仅松手抬指后同步 1 次）。
      final buildsBeforeDrag = service.buildSnapshotCalls;
      final opacitySlider = find.byType(Slider).first;
      final gesture = await tester.startGesture(
        tester.getCenter(opacitySlider),
      );
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump();
      }
      expect(service.buildSnapshotCalls, buildsBeforeDrag);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(service.buildSnapshotCalls, buildsBeforeDrag + 1);

      // 恢复默认样式 → 弹 SnackBar 并支持一键撤销。
      final styleBeforeReset = model.widgetStyleOf(DesktopWidgetKind.today);
      await tester.scrollUntilVisible(
        find.text('恢复「今日课表」默认样式'),
        200,
        scrollable: mainScrollable,
      );
      await tester.tap(find.text('恢复「今日课表」默认样式'));
      await tester.pumpAndSettle();
      expect(
        model.widgetStyleOf(DesktopWidgetKind.today),
        DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.today),
      );
      expect(find.text('撤销'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(model.widgetStyleOf(DesktopWidgetKind.today), styleBeforeReset);

      // 切换到「下一节课」：验证不合理的「已结束课程」「信息密度」「显示顶部标题栏」均已移除。
      await tester.scrollUntilVisible(
        find.text('下一节课'),
        -300,
        scrollable: mainScrollable,
      );
      await tester.tap(find.text('下一节课'));
      await tester.pumpAndSettle();
      expect(find.text('尚未添加到桌面'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('融合考试安排'),
        200,
        scrollable: mainScrollable,
      );
      expect(find.text('优先展示当天考试，近期无课时展示 7 天内倒计时'), findsOneWidget);
      expect(find.text('已结束课程'), findsNothing);
      expect(find.text('信息密度'), findsNothing);
      expect(find.text('显示顶部标题栏'), findsNothing);

      // 切换到「本周课表」验证专属选项并点击添加到桌面。
      await tester.scrollUntilVisible(
        find.text('本周课表'),
        -300,
        scrollable: mainScrollable,
      );
      await tester.tap(find.text('本周课表'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('添加到桌面'));
      await tester.pumpAndSettle();
      expect(gateway.lastPinnedKind, DesktopWidgetKind.week);

      await tester.scrollUntilVisible(
        find.text('周末列显示'),
        200,
        scrollable: mainScrollable,
      );
      expect(find.text('始终隐藏'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360x640 窄屏 + 2.0x 系统超大字体下配置页三类切换与滚动零溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final model = _createModel();
      final gateway = _FakeGateway();
      final service = _CountingWidgetService(
        model: model,
        gateway: gateway,
        now: () => DateTime(2026, 9, 9, 10, 40),
      );
      addTearDown(() {
        service.dispose();
        model.dispose();
      });

      await tester.pumpWidget(
        _wrapApp(
          WidgetSettingsPage(model: model, widgetService: service),
          systemTextScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final label in const <String>['本周课表', '下一节课', '今日课表']) {
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('快照规划边界：假期周次识别与周日 14 天跨周覆盖', () {
    test('假期新鲜快照正确标注超 maxWeek 周次，周日同步预计算覆盖完整 14 天第 3 周', () {
      final springStart = DateTime(2026, 3, 2); // 第 1 周周一，18 周末为 2026-07-05
      final vacationNow = DateTime(2026, 7, 8, 10, 0); // 第 19 周（暑假）
      final vacationSnap = buildWidgetSnapshot(
        termId: '2025-2026-2',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 'c1',
            name: '大学物理',
            location: 'M1-101',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[18],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: springStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: vacationNow,
      );
      expect(vacationSnap.days, isNotEmpty);
      expect(vacationSnap.days.first.week, greaterThan(vacationSnap.maxWeek));

      // 周日（第 1 周）生成的快照，第 8 天（第 3 周周一）仍应落在 weeks 列表内。
      final fallStart = DateTime(2026, 9, 7);
      final sundayW1 = DateTime(2026, 9, 13, 10, 0);
      final sundaySnap = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 'mon3',
            name: '复变函数',
            location: 'M1-303',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[3],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: fallStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: sundayW1,
      );
      expect(sundaySnap.weeks.map((w) => w.week), containsAll(<int>[1, 2, 3]));
    });
  });
}
