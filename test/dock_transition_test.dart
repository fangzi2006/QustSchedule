/// Dock 栏翻页打断动画与连续衔接测试。
///
/// 覆盖两类核心打断场景：
///  1. 目标页抢跑交互：滑行未停稳即可点击开关、滚动列表、直接进入二级页（含零时长不透明路由覆盖兜底），
///     同时离场页已锁死、按住 Dock 拖拽预览期间不误触；
///  2. Dock 自身连续打断：同向续速改目标、反向干脆折返无反冲、半途拖拽接管，以及
///     跨页（课表 ↔ 设置）路过学业页时不误判落点且保持按需懒建。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/academic_page.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/settings_page.dart';
import 'package:qustschedule/pages/timetable_list_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/app_menu.dart';
import 'package:qustschedule/widgets/floating_dock.dart';
import 'package:qustschedule/widgets/tactile_button.dart';
import 'package:zf_academic/zf_academic_io.dart' hide Page;

import 'support/fake_backend.dart';

AppModel _buildModel({FakeBackend? backend}) {
  final fake = backend ?? FakeBackend();
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
    week: 1,
    termStart: DateTime(2026, 9, 7),
  );
  return model;
}

Widget _wrapHome(AppModel model) {
  return MaterialApp(
    theme: buildLightTheme(),
    home: HomeShell(model: model),
  );
}

double _shellPosition(WidgetTester tester) {
  final Transform transform = tester.widget<Transform>(
    find.byKey(const ValueKey<String>('shell-page-0')),
  );
  final double width = tester.getSize(find.byType(HomeShell)).width;
  if (width <= 0) return 0;
  return -transform.transform.getTranslation().x / width;
}

Finder _dockLabel(String label) =>
    find.descendant(of: find.byType(FloatingDock), matching: find.text(label));

void main() {
  group('Dock 翻页打断动画测试', () {
    testWidgets('滑行中途即可点击目标页开关与滚动列表，底层翻页动画继续平滑落位', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));
      expect(model.showTeacher, isTrue);

      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 96));

      // 此时翻页动画尚未停稳（距 2.0 仍有明显位移），但设置页已滑入视口且立即可交互。
      final midPos = _shellPosition(tester);
      expect(midPos, greaterThan(1.2));
      expect(midPos, lessThan(1.92));

      // 1. 动画途中直接点击开关立即生效。
      await tester.tap(find.text('显示教师'));
      await tester.pump();
      expect(model.showTeacher, isFalse);

      // 点击后底层翻页动画仍未瞬移截断，继续平滑前进。
      final afterTapPos = _shellPosition(tester);
      expect(afterTapPos, greaterThanOrEqualTo(midPos));
      expect(afterTapPos, lessThan(1.98));

      // 2. 动画途中直接滚动设置页列表立即跟手。
      final settingsScrollable = find.descendant(
        of: find.byType(SettingsPage),
        matching: find.byType(Scrollable),
      );
      final scrollableState = tester.state<ScrollableState>(settingsScrollable);
      expect(scrollableState.position.pixels, closeTo(0.0, 0.5));

      await tester.drag(settingsScrollable, const Offset(0, -180));
      await tester.pump();
      final scrolledMid = scrollableState.position.pixels;
      expect(scrolledMid, greaterThan(80.0));

      // 3. 等所有动画自然落稳：轨道稳停设置页 2.0，滚动位置保留。
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
      expect(scrollableState.position.pixels, greaterThan(80.0));
      expect(find.byType(AcademicPage), findsNothing);
    });

    testWidgets('滑行中途直接点进二级页再返回，首页稳稳落在目标页且绝不卡半路', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 96));
      final midPos = _shellPosition(tester);
      expect(midPos, greaterThan(1.2));
      expect(midPos, lessThan(1.92));

      // 翻页未完成时直接点击「作息时间表」推入二级页。
      await tester.tap(find.text('作息时间表'));
      await tester.pumpAndSettle();
      expect(find.byType(TimetableListPage), findsOneWidget);

      // 返回首页：必须完整落位在设置页 2.0。
      Navigator.of(tester.element(find.byType(TimetableListPage))).pop();
      await tester.pumpAndSettle();
      expect(find.byType(TimetableListPage), findsNothing);
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
    });

    testWidgets('滑行中途被零时长不透明二级页瞬间覆盖停帧，返回后仍稳妥落位目标页', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 24));

      final midPos = _shellPosition(tester);
      expect(midPos, greaterThan(0.05));
      expect(midPos, lessThan(1.4));

      // 模拟零时长不透明路由瞬间遮挡首页（首页 TickerMode 立刻变 false）。
      final nav = Navigator.of(tester.element(find.byType(HomeShell)));
      nav.push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Scaffold(body: Text('瞬间覆盖页')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('瞬间覆盖页'), findsOneWidget);

      // 立刻返回首页：即使不额外等待动画，轨道也已在后台静默收敛到 2.0。
      nav.pop();
      await tester.pump();
      expect(find.text('瞬间覆盖页'), findsNothing);
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
    });

    testWidgets('离场页立刻锁死防误触，按住 Dock 拖拽预览期间屏蔽内容区、松手即解锁', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      // 1. 点击设置后 32ms：课表页仍在左半屏可视，但已锁死不可误点。
      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(_shellPosition(tester), lessThan(1.5));

      final courseFinder = find.text('电力电子技术');
      expect(courseFinder, findsOneWidget);
      await tester.tap(courseFinder, warnIfMissed: false);
      await tester.pump();
      // 未弹出课程详情底部弹窗。
      expect(find.text('上课地点'), findsNothing);

      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));

      // 2. 按住 Dock 向左拖动预览到课表但不松手：内容区被屏蔽。
      final drag = await tester.startGesture(
        tester.getCenter(_dockLabel('设置')),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await drag.moveTo(tester.getCenter(_dockLabel('课表')));
      await tester.pump(const Duration(milliseconds: 48));

      // 拖动中尝试用另一指针点击设置页「显示教师」不应生效。
      await tester.tap(find.text('显示教师'), warnIfMissed: false);
      await tester.pump();
      expect(model.showTeacher, isTrue);

      // 松手后回到课表页并立即解锁可交互。
      await drag.up();
      await tester.pump();
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      // 确认课表页已恢复交互（点击课程块可打开详情）。
      await tester.tap(find.text('电力电子技术'));
      await tester.pumpAndSettle();
      expect(find.text('高密校区 M1-239'), findsWidgets);
      Navigator.of(tester.element(find.byType(HomeShell))).pop();
      await tester.pumpAndSettle();
    });

    testWidgets('跨页直达（课表↔设置）全程单调不误停学业页，反向折返无反冲，同向续速平滑无跳变', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      // 1. 跨页 0 -> 2：逐帧检查严格单调递增，不卡停在 1.0，不提前建学业页。
      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      double prev = _shellPosition(tester);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 12));
        final cur = _shellPosition(tester);
        expect(cur, greaterThanOrEqualTo(prev - 1e-4));
        expect(cur, lessThanOrEqualTo(2.001));
        prev = cur;
      }
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
      expect(find.byType(AcademicPage), findsNothing);

      // 2. 反向折返：从 2 点回 0，48ms 半途再点回 2，验证位置连续无跳变且立即掉头无反冲。
      await tester.tap(_dockLabel('课表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final turnPos = _shellPosition(tester);
      expect(turnPos, greaterThan(0.2));
      expect(turnPos, lessThan(1.8));

      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      final immediatelyAfterTurn = _shellPosition(tester);
      // 折返瞬间无跳变。
      expect((immediatelyAfterTurn - turnPos).abs(), lessThan(0.08));

      double revPrev = immediatelyAfterTurn;
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 12));
        final cur = _shellPosition(tester);
        // 立刻向 2.0 前进，不往 0.0 方向继续反冲。
        expect(cur, greaterThanOrEqualTo(revPrev - 1e-4));
        expect(cur, lessThanOrEqualTo(2.001));
        revPrev = cur;
      }
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));

      // 3. 回到 0 后验证同向续速：点 学业(1) 32ms 中途改点 设置(2)，保持同向单调无过冲。
      await tester.tap(_dockLabel('课表'));
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      await tester.tap(_dockLabel('学业'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      final beforeRedirect = _shellPosition(tester);
      expect(beforeRedirect, greaterThan(0.1));
      expect(beforeRedirect, lessThan(0.95));

      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      final afterRedirect = _shellPosition(tester);
      expect((afterRedirect - beforeRedirect).abs(), lessThan(0.08));

      // 第一步（16ms）因继承同向速度应明显继续向右推进，无刹停顿挫。
      await tester.pump(const Duration(milliseconds: 16));
      final firstStep = _shellPosition(tester);
      expect(firstStep - afterRedirect, greaterThan(0.12));

      double forwardPrev = firstStep;
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 12));
        final cur = _shellPosition(tester);
        expect(cur, greaterThanOrEqualTo(forwardPrev - 1e-4));
        expect(cur, lessThanOrEqualTo(2.001));
        forwardPrev = cur;
      }
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
      expect(find.byType(AcademicPage), findsOneWidget);
    });

    testWidgets('滑行中途按住 Dock 拖拽接管无跳变，松手平滑落位新目标页', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final midPos = _shellPosition(tester);
      expect(midPos, greaterThan(0.3));
      expect(midPos, lessThan(1.8));

      // 在 Dock 上按住并拖到「学业」，接管滑行中的透镜。
      final drag = await tester.startGesture(
        tester.getCenter(_dockLabel('设置')),
      );
      await tester.pump();
      await drag.moveTo(tester.getCenter(_dockLabel('学业')));
      await tester.pump(const Duration(milliseconds: 32));
      await drag.up();
      await tester.pump();
      await tester.pumpAndSettle();

      expect(_shellPosition(tester), closeTo(1.0, 0.001));
      expect(find.byType(AcademicPage), findsOneWidget);
    });

    testWidgets('从设置切回课表滑行中途，高索引离场页放行命中且课表页立即可点击', (tester) async {
      final model = _buildModel();
      model.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: <ScheduleEntry>[
            ScheduleEntry(
              id: 'e-fri',
              name: '信号与系统',
              teacher: '王老师',
              location: '弘毅楼 502',
              day: 5,
              startPeriod: 1,
              endPeriod: 2,
              weeks: <int>[1, 2],
            ),
          ],
        ),
        week: 1,
        termStart: DateTime(2026, 9, 7),
      );
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      await tester.tap(_dockLabel('设置'));
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));

      // 从 2 -> 0 切回课表：96ms 时尚未停稳，但右侧周五列已进入视口，
      // 必须穿透 Stack 上层的设置页直接命中课表页课程块。
      await tester.tap(_dockLabel('课表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 96));
      final midPos = _shellPosition(tester);
      expect(midPos, greaterThan(0.08));
      expect(midPos, lessThan(0.8));

      await tester.tap(find.text('信号与系统'));
      await tester.pumpAndSettle();
      expect(find.text('弘毅楼 502'), findsWidgets);
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      Navigator.of(tester.element(find.byType(HomeShell))).pop();
      await tester.pumpAndSettle();
    });

    testWidgets('偏心按下再松手对齐按钮中心时同向续速无回撤且无跳变', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      // 在「设置」按钮偏左 18px 处按下，40ms 后抬起触发对齐按钮中心。
      final settingsCenter = tester.getCenter(_dockLabel('设置'));
      final tap = await tester.startGesture(settingsCenter.translate(-18, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final beforeUp = _shellPosition(tester);
      expect(beforeUp, greaterThan(0.2));
      expect(beforeUp, lessThan(1.5));

      await tap.up();
      await tester.pump();
      final rightAfterUp = _shellPosition(tester);
      expect((rightAfterUp - beforeUp).abs(), lessThan(0.05));

      // 松手后下一帧继续高速推进（无速度归零顿挫），且全程单调无越界。
      await tester.pump(const Duration(milliseconds: 16));
      final nextFrame = _shellPosition(tester);
      expect(nextFrame - rightAfterUp, greaterThan(0.15));

      double prev = nextFrame;
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 12));
        final cur = _shellPosition(tester);
        expect(cur, greaterThanOrEqualTo(prev - 1e-4));
        expect(cur, lessThanOrEqualTo(2.001));
        prev = cur;
      }
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
    });

    testWidgets('编程式 animateToIndex 中途被用户点 Dock 打断可平滑折返并落位正确', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      final dockState = tester.state<FloatingDockState>(
        find.byType(FloatingDock, skipOffstage: false),
      );
      dockState.animateToIndex(2);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final midPos = _shellPosition(tester);
      expect(midPos, greaterThan(0.3));
      expect(midPos, lessThan(1.8));

      await tester.tap(_dockLabel('课表'));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));
    });

    testWidgets('未松手拖拽 Dock 期间被零时长不透明路由覆盖，返回后视觉与逻辑页一致；遮挡期间编程切页直接落位', (
      tester,
    ) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      // 按住 Dock 拖到「设置」但不松手（尚未提交切页，逻辑页仍为课表 0）。
      final drag = await tester.startGesture(
        tester.getCenter(_dockLabel('课表')),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await drag.moveTo(tester.getCenter(_dockLabel('设置')));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      expect(_shellPosition(tester), greaterThan(0.5));

      final nav = Navigator.of(tester.element(find.byType(HomeShell)));
      nav.push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Scaffold(body: Text('遮挡页')),
        ),
      );
      await tester.pump();
      await tester.pump();
      await drag.cancel();

      // 返回首页：未提交的预览拖拽必须回正到逻辑页 0（课表），且课表立即可点。
      nav.pop();
      await tester.pump();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));
      await tester.pumpAndSettle();
      await tester.tap(find.text('电力电子技术'));
      await tester.pumpAndSettle();
      expect(find.text('高密校区 M1-239'), findsWidgets);
      nav.pop();
      await tester.pumpAndSettle();

      // 在不透明路由遮挡期间调用编程切页 animateToIndex(2)，返回时已直接落位 2.0。
      nav.push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Scaffold(body: Text('再次遮挡页')),
        ),
      );
      await tester.pump();
      await tester.pump();
      final dockState = tester.state<FloatingDockState>(
        find.byType(FloatingDock, skipOffstage: false),
      );
      dockState.animateToIndex(2);
      await tester.pump();

      nav.pop();
      await tester.pump();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
    });
  });

  group('页面作用域菜单：翻页锚定跟随与跨页防误展开测试', () {
    testWidgets('Dock 翻页滑行中途打开右对齐与居中菜单，菜单随目标页滑入正确落位而非留在点击坐标', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      final moreTrigger = find.ancestor(
        of: find.byIcon(Icons.more_horiz_rounded),
        matching: find.byType(TactileSurfaceButton),
      );
      final weekTrigger = find.ancestor(
        of: find.text('第 1 周'),
        matching: find.byType(TactileSurfaceButton),
      );
      final settledMoreRect = tester.getRect(moreTrigger);
      final settledWeekRect = tester.getRect(weekTrigger);

      // 切到设置页落稳，再切回课表页并在滑行中途打开「更多」菜单（含真实手指按住 32ms 抬起）。
      await tester.tap(_dockLabel('设置'));
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));

      await tester.tap(_dockLabel('课表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final midPos = _shellPosition(tester);
      expect(midPos, greaterThan(0.15));
      expect(midPos, lessThan(1.0));

      final midMoreRect = tester.getRect(moreTrigger);
      expect(settledMoreRect.right - midMoreRect.right, greaterThan(100.0));

      // 模拟真实点击（按下 32ms 后抬起，期间页面仍在高速右移）。
      final tapMore = await tester.startGesture(midMoreRect.center);
      await tester.pump(const Duration(milliseconds: 32));
      await tapMore.up();
      await tester.pump();
      await tester.pump();

      // 菜单已展开且保持右对齐（未被翻页中段坐标误判成左对齐），并跟随页面最终落回按钮正上方。
      final morphBox = tester.renderObject<RenderMenuMorphBox>(
        find.byElementPredicate((e) => e.renderObject is RenderMenuMorphBox),
      );
      expect(morphBox.alignment, Alignment.topRight);

      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));
      final moreMenuMaterial = find
          .ancestor(of: find.text('校准当前周次'), matching: find.byType(Material))
          .first;
      final moreMenuRect = tester.getRect(moreMenuMaterial);
      expect(moreMenuRect.right, closeTo(settledMoreRect.right, 1.0));
      expect(moreMenuRect.top, closeTo(settledMoreRect.top, 1.0));

      // 关闭后再测居中展开的周次菜单：从学业页(1)切回课表页(0)滑行中途打开，最终居中对齐周次按钮。
      await tester.tapAt(const Offset(20, 200));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);

      await tester.tap(_dockLabel('学业'));
      await tester.pumpAndSettle();
      await tester.tap(_dockLabel('课表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      final midWeekRect = tester.getRect(weekTrigger);
      expect(midWeekRect.center.dx, greaterThan(0.0));
      expect(
        settledWeekRect.center.dx - midWeekRect.center.dx,
        greaterThan(20.0),
      );

      await tester.tapAt(midWeekRect.center);
      await tester.pumpAndSettle();
      final weekMenuMaterial = find
          .ancestor(of: find.text('第 2 周'), matching: find.byType(Material))
          .first;
      final weekMenuRect = tester.getRect(weekMenuMaterial);
      expect(weekMenuRect.center.dx, closeTo(settledWeekRect.center.dx, 1.0));
      expect(weekMenuRect.top, closeTo(settledWeekRect.top, 1.0));

      await tester.tap(find.text('第 2 周'));
      await tester.pumpAndSettle();
      expect(model.week, 2);
    });

    testWidgets('二级页入场滑行中途打开菜单，菜单随二级页滑入正确位置', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      await tester.tap(_dockLabel('设置'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作息时间表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      expect(find.byType(TimetableListPage), findsOneWidget);

      final menuTrigger = find
          .ancestor(
            of: find.byIcon(Icons.more_vert_rounded).first,
            matching: find.byType(TactileSurfaceButton),
          )
          .first;
      final midTriggerRect = tester.getRect(menuTrigger);
      final screenWidth = tester.getSize(find.byType(MaterialApp)).width;
      // 二级页尚未完全落位，按钮已滑入视口可点，但仍明显偏右。
      expect(midTriggerRect.center.dx, lessThan(screenWidth));

      await tester.tapAt(midTriggerRect.center);
      await tester.pumpAndSettle();

      final settledTriggerRect = tester.getRect(menuTrigger);
      expect(
        midTriggerRect.right - settledTriggerRect.right,
        greaterThan(15.0),
      );
      final menuMaterial = find
          .ancestor(of: find.text('至少保留一张'), matching: find.byType(Material))
          .first;
      final menuRect = tester.getRect(menuMaterial);
      expect(menuRect.right, closeTo(settledTriggerRect.right, 1.0));
      expect(menuRect.top, closeTo(settledTriggerRect.top, 1.0));
    });

    testWidgets('切页时已展开菜单随原页面一同划走并平滑收起，绝不滞留在新页面上', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      final menuMaterial = find
          .ancestor(of: find.text('校准当前周次'), matching: find.byType(Material))
          .first;
      final initialLeft = tester.getRect(menuMaterial).left;

      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      // 收起途中菜单跟随课表页明显向左划走，而不是定在原地覆盖设置页。
      expect(find.text('校准当前周次'), findsOneWidget);
      final movingLeft = tester.getRect(menuMaterial).left;
      expect(movingLeft, lessThan(initialLeft - 40.0));

      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
    });

    testWidgets(
      '长按可展开菜单的同时翻页（定时触发前/已长按展开未松手/拖拽 Dock/编程切页/推入二级页），菜单绝不在其他页展开或残留',
      (tester) async {
        final model = _buildModel();
        addTearDown(model.dispose);

        await tester.pumpWidget(_wrapHome(model));
        await tester.pumpAndSettle();

        final moreTrigger = find.byIcon(Icons.more_horiz_rounded);

        // 1. 长按定时（190ms）触发前点 Dock 切到设置页：超时后绝不在设置页弹出。
        final hold1 = await tester.startGesture(tester.getCenter(moreTrigger));
        await tester.pump(const Duration(milliseconds: 60));
        await tester.tap(_dockLabel('设置'));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('校准当前周次'), findsNothing);
        await hold1.up();
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(_shellPosition(tester), closeTo(2.0, 0.001));

        // 回到课表页。
        await tester.tap(_dockLabel('课表'));
        await tester.pumpAndSettle();

        // 2. 长按期间另一手指按住拖动 Dock 到设置页：全程绝不弹出菜单。
        final hold2 = await tester.startGesture(tester.getCenter(moreTrigger));
        await tester.pump(const Duration(milliseconds: 60));
        final dockDrag = await tester.startGesture(
          tester.getCenter(_dockLabel('课表')),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await dockDrag.moveTo(tester.getCenter(_dockLabel('设置')));
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('校准当前周次'), findsNothing);
        await dockDrag.up();
        await hold2.up();
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(_shellPosition(tester), closeTo(2.0, 0.001));

        // 回到课表页。
        await tester.tap(_dockLabel('课表'));
        await tester.pumpAndSettle();

        // 3. 长按已经展开菜单且手指仍按住（_activePointer != null）时，另一手指点 Dock 切页：
        //    菜单必须立刻收起且原手指继续滑动/松手不会误选任何菜单项。
        final hold3 = await tester.startGesture(tester.getCenter(moreTrigger));
        await tester.pump(const Duration(milliseconds: 220));
        expect(find.text('校准当前周次'), findsOneWidget);

        await tester.tap(_dockLabel('设置'));
        await tester.pump();
        await hold3.moveBy(const Offset(0, 60));
        await tester.pump(const Duration(milliseconds: 32));
        await hold3.up();
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(find.byType(TimetableListPage), findsNothing);
        expect(_shellPosition(tester), closeTo(2.0, 0.001));

        // 回到课表页。
        await tester.tap(_dockLabel('课表'));
        await tester.pumpAndSettle();

        // 4. 长按期间由编程式切页（animateToIndex）离开页面，后续下拉与松手均不展开菜单。
        final dockState = tester.state<FloatingDockState>(
          find.byType(FloatingDock, skipOffstage: false),
        );
        final hold4 = await tester.startGesture(tester.getCenter(moreTrigger));
        await tester.pump(const Duration(milliseconds: 50));
        dockState.animateToIndex(2);
        await tester.pump(const Duration(milliseconds: 220));
        await hold4.moveBy(const Offset(0, 32));
        await tester.pump();
        await hold4.up();
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(_shellPosition(tester), closeTo(2.0, 0.001));

        // 回到课表页。
        await tester.tap(_dockLabel('课表'));
        await tester.pumpAndSettle();

        // 5. 长按期间推入二级页，长按定时取消且菜单绝不盖在二级页上。
        final hold5 = await tester.startGesture(tester.getCenter(moreTrigger));
        await tester.pump(const Duration(milliseconds: 50));
        final nav = Navigator.of(tester.element(find.byType(HomeShell)));
        nav.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('二级覆盖页')),
          ),
        );
        await tester.pump(const Duration(milliseconds: 250));
        expect(find.text('校准当前周次'), findsNothing);
        await hold5.up();
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        nav.pop();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      '点击菜单后在展开动画开始之前翻页（同帧切页/首帧测量前切页/双指按下先翻页后抬起/离场页直调 showAppMenu），菜单绝不展开',
      (tester) async {
        final model = _buildModel();
        addTearDown(model.dispose);

        await tester.pumpWidget(_wrapHome(model));
        await tester.pumpAndSettle();

        final moreTrigger = find.byIcon(Icons.more_horiz_rounded);

        // 1. 点击菜单后 0 帧（initState 尚未运行、展开动画尚未开始）立即点击 Dock 翻页。
        await tester.tap(moreTrigger);
        await tester.tap(_dockLabel('设置'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.text('校准当前周次'), findsNothing);
        }
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(_shellPosition(tester), closeTo(2.0, 0.001));
        expect(
          TactileSurfaceButton.debugMorphOpacityOf(tester.element(moreTrigger)),
          1.0,
        );

        // 回到课表页。
        await tester.tap(_dockLabel('课表'));
        await tester.pumpAndSettle();

        // 2. 点击菜单后仅走 1 帧（测量帧，展开动画尚未开始）立即点 Dock 翻页。
        await tester.tap(moreTrigger);
        await tester.pump();
        await tester.tap(_dockLabel('设置'));
        for (var i = 0; i < 10; i++) {
          await tester.pump(const Duration(milliseconds: 16));
          expect(find.text('校准当前周次'), findsNothing);
        }
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(_shellPosition(tester), closeTo(2.0, 0.001));

        // 回到课表页。
        await tester.tap(_dockLabel('课表'));
        await tester.pumpAndSettle();

        // 3. 手指 1 按下菜单按钮未抬起，手指 2 点击 Dock 翻页，随后手指 1 抬起：绝不展开。
        final finger1 = await tester.startGesture(
          tester.getCenter(moreTrigger),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tap(_dockLabel('设置'));
        await finger1.up();
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(_shellPosition(tester), closeTo(2.0, 0.001));

        // 4. 离开课表页后直接对课表页按钮的 BuildContext 调用 showAppMenu：必须被通用作用域拦截。
        final scheduleTriggerContext = tester.element(
          find.ancestor(
            of: moreTrigger,
            matching: find.byType(TactileSurfaceButton),
          ),
        );
        var selected = false;
        await showAppMenu<String>(
          context: scheduleTriggerContext,
          items: const <AppMenuItem<String>>[
            AppMenuItem<String>(value: 'x', label: '不应出现的离场菜单项'),
          ],
          onSelected: (_) => selected = true,
        );
        await tester.pumpAndSettle();
        expect(find.text('不应出现的离场菜单项'), findsNothing);
        expect(selected, isFalse);
      },
    );

    testWidgets('Dock 切页提交顺序：离场页 AppMenuScope 不产生 false->true->false 瞬时回弹脉冲', (
      tester,
    ) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      final scheduleCtx = tester.element(find.byIcon(Icons.more_horiz_rounded));
      final scope = AppMenuScope.maybeControllerOf(scheduleCtx)!;
      final transitions = <bool>[];
      void record() => transitions.add(scope.isActive);
      scope.activeListenable.addListener(record);
      addTearDown(() => scope.activeListenable.removeListener(record));

      // 1. 点击设置切页：课表页只应从 true -> false 一次，绝不在松手时先闪回 true 再变 false。
      await tester.tap(_dockLabel('设置'));
      await tester.pumpAndSettle();
      expect(transitions, <bool>[false]);

      // 回到课表页后测试拖拽切页。
      await tester.tap(_dockLabel('课表'));
      await tester.pumpAndSettle();
      transitions.clear();

      final drag = await tester.startGesture(
        tester.getCenter(_dockLabel('课表')),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await drag.moveTo(tester.getCenter(_dockLabel('设置')));
      await tester.pump(const Duration(milliseconds: 32));
      await drag.up();
      await tester.pumpAndSettle();
      expect(transitions, <bool>[false]);
    });

    testWidgets('Dock 未松手按压/拖拽期间推入动画二级页或弹窗，松手不偷偷切页；纵向滑动未抬手不提前提交，双指触碰不串扰拖拽', (
      tester,
    ) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      // 1. 按住 Dock 拖向「设置」期间推入常规动画二级页（TickerMode 尚未关闭且无 PointerCancel），
      //    松手后绝不能在二级页背后偷偷切到设置页。
      final drag = await tester.startGesture(
        tester.getCenter(_dockLabel('课表')),
      );
      await tester.pump(const Duration(milliseconds: 16));
      await drag.moveTo(tester.getCenter(_dockLabel('设置')));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      expect(_shellPosition(tester), greaterThan(0.5));

      final nav = Navigator.of(tester.element(find.byType(HomeShell)));
      nav.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('动画二级页')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      await drag.up();
      await tester.pumpAndSettle();

      nav.pop();
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      // 2. 在 Dock 按住「设置」后先垂直上滑超出 touchSlop 但尚未松手：
      //    未抬手前绝不提前提交设置页，且可继续横向拖回课表页松手保持在课表页。
      final settingsPos = tester.getCenter(_dockLabel('设置'));
      final schedulePos = tester.getCenter(_dockLabel('课表'));
      final verticalThenDrag = await tester.startGesture(settingsPos);
      await tester.pump(const Duration(milliseconds: 16));
      await verticalThenDrag.moveBy(const Offset(0, -28));
      await tester.pump(const Duration(milliseconds: 16));
      // 尚未松手：课表页与设置页均处于锁定状态，绝不提前提交或解锁设置页。
      final scheduleCtx = tester.element(find.byIcon(Icons.more_horiz_rounded));
      final settingsCtx = tester.element(find.byType(SettingsPage));
      expect(AppMenuScope.isActiveOf(scheduleCtx), isFalse);
      expect(AppMenuScope.isActiveOf(settingsCtx), isFalse);
      // 继续水平拖回课表并松手：应稳妥落回课表页 0.0。
      await verticalThenDrag.moveTo(
        Offset(schedulePos.dx, settingsPos.dy - 28),
      );
      await tester.pump(const Duration(milliseconds: 48));
      await verticalThenDrag.up();
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      // 2b. 按住 Dock 预览「设置」期间弹出非不透明 Dialog（TickerMode 仍为 true），
      //     松手绝不在 Dialog 背后偷偷切换到设置页。
      final pressDuringDialog = await tester.startGesture(settingsPos);
      await tester.pump(const Duration(milliseconds: 32));
      showDialog<void>(
        context: tester.element(find.byType(HomeShell)),
        builder: (_) => const AlertDialog(content: Text('遮罩弹窗')),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      await pressDuringDialog.up();
      await tester.pumpAndSettle();
      expect(find.text('遮罩弹窗'), findsOneWidget);
      Navigator.of(tester.element(find.text('遮罩弹窗'))).pop();
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      // 3. 单指拖动 Dock 至「设置」中途，第二根手指轻触或取消在「课表」上，不打断第一指拖拽。
      final finger1 = await tester.startGesture(schedulePos);
      await tester.pump(const Duration(milliseconds: 16));
      await finger1.moveTo(settingsPos);
      await tester.pump(const Duration(milliseconds: 48));
      final finger2 = await tester.startGesture(schedulePos);
      await tester.pump(const Duration(milliseconds: 16));
      await finger2.cancel();
      await tester.pump(const Duration(milliseconds: 16));
      await finger1.up();
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(2.0, 0.001));
    });

    testWidgets(
      '覆盖新路由时旧页收起中菜单立即清理不浮在二级页上，首帧取消长按菜单不残留 activeTactileDragStart，预测返回手势自动收起菜单',
      (tester) async {
        final model = _buildModel();
        addTearDown(model.dispose);

        await tester.pumpWidget(_wrapHome(model));
        await tester.pumpAndSettle();

        final moreTrigger = find.byIcon(Icons.more_horiz_rounded);

        // 1. 打开菜单并点击「作息时间表」推入二级页：旧页菜单在推入动画中途绝不浮在二级页上。
        await tester.tap(moreTrigger);
        await tester.pumpAndSettle();
        expect(find.text('作息时间表'), findsOneWidget);

        await tester.tap(find.text('作息时间表'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 48));
        expect(find.byType(TimetableListPage), findsOneWidget);
        expect(find.text('校准当前周次'), findsNothing);
        await tester.pumpAndSettle();

        // 2. 在二级页打开菜单后触发 Navigator 用户返回手势（didStartUserGesture）：
        //    即使 route.animation.status 尚未进入 reverse，菜单也应自动收起且期间禁止打开。
        final subTrigger = find.byIcon(Icons.more_vert_rounded).first;
        await tester.tap(subTrigger);
        await tester.pumpAndSettle();
        expect(find.text('至少保留一张'), findsOneWidget);

        final nav = Navigator.of(
          tester.element(find.byType(TimetableListPage)),
        );
        nav.didStartUserGesture();
        await tester.pump();
        expect(AppMenuScope.isActiveOf(tester.element(subTrigger)), isFalse);
        await tester.pumpAndSettle();
        expect(find.text('至少保留一张'), findsNothing);
        nav.didStopUserGesture();
        await tester.pump();
        expect(AppMenuScope.isActiveOf(tester.element(subTrigger)), isTrue);

        nav.pop();
        await tester.pumpAndSettle();

        // 3. 长按触发菜单的第 0 帧（initState 前）切页取消，绝不泄漏 activeTactileDragStart。
        activeTactileDragStart = null;
        final hold = await tester.startGesture(tester.getCenter(moreTrigger));
        await tester.pump(const Duration(milliseconds: 195));
        // 尚未走下一帧 build（initState 尚未运行）直接点击 Dock 切页取消。
        await tester.tap(_dockLabel('设置'));
        expect(activeTactileDragStart, isNull);
        await hold.up();
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(activeTactileDragStart, isNull);
      },
    );

    testWidgets('翻页中途下拉交接选单、切走又立刻切回重开同按钮、二级页反转取消后重开均正常', (tester) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      final moreTrigger = find.ancestor(
        of: find.byIcon(Icons.more_horiz_rounded),
        matching: find.byType(TactileSurfaceButton),
      );

      // 1. 从设置切回课表滑行中途，按住「更多」下拉交接展开并滑选「作息时间表」。
      await tester.tap(_dockLabel('设置'));
      await tester.pumpAndSettle();
      await tester.tap(_dockLabel('课表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final midRect = tester.getRect(moreTrigger);
      final pull = await tester.startGesture(midRect.center);
      await tester.pump(const Duration(milliseconds: 16));
      await pull.moveBy(const Offset(0, 22));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final menuTimetableItem = find.text('作息时间表').last;
      expect(menuTimetableItem, findsOneWidget);
      await pull.moveTo(tester.getCenter(menuTimetableItem));
      await tester.pump(const Duration(milliseconds: 16));
      await pull.up();
      await tester.pumpAndSettle();
      expect(find.byType(TimetableListPage), findsOneWidget);

      Navigator.of(tester.element(find.byType(TimetableListPage))).pop();
      await tester.pumpAndSettle();

      // 2. 展开菜单后切去设置，48ms 内立刻切回课表并重开同按钮，无缝衔接不丢状态。
      await tester.tap(moreTrigger);
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);

      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      expect(find.text('校准当前周次'), findsOneWidget);

      await tester.tap(_dockLabel('课表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      await tester.tapAt(tester.getCenter(moreTrigger));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      // 3. 切去设置 -> 切回课表 -> 同帧点开菜单后第 0 帧立刻再切去设置：
      //    原按钮不透明度与菜单收起状态保持一致，不残留。
      await tester.tap(_dockLabel('设置'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      await tester.tap(_dockLabel('课表'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.tapAt(tester.getCenter(moreTrigger));
      await tester.tap(_dockLabel('设置'));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(
        TactileSurfaceButton.debugMorphOpacityOf(tester.element(moreTrigger)),
        1.0,
      );
    });

    testWidgets('按住或拖动 FloatingDock 期间推入零时长路由（不透明与非不透明），不触发构建期重入且松手不偷偷切页', (
      tester,
    ) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      final nav = Navigator.of(tester.element(find.byType(HomeShell)));
      final settingsPos = tester.getCenter(_dockLabel('设置'));
      final schedulePos = tester.getCenter(_dockLabel('课表'));

      // 1. 按住「设置」预览期间推入零时长非不透明 PageRouteBuilder（TickerMode 仍为 true，
      //    didChangeDependencies 触发于构建期且先于任何动画状态回调）。
      final holdNonOpaque = await tester.startGesture(settingsPos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(_shellPosition(tester), greaterThan(0.1));
      nav.push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Center(child: Text('零时长非不透明遮罩')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('零时长非不透明遮罩'), findsOneWidget);
      await tester.pumpAndSettle();
      // 零时长非不透明路由覆盖后，即使手指仍未松开，未提交按压也已回正到原页 0.0。
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      await holdNonOpaque.up();
      await tester.pumpAndSettle();
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('零时长非不透明遮罩'), findsNothing);
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      // 2. 按住并拖动 Dock 至「设置」期间推入零时长不透明 PageRouteBuilder。
      final dragOpaque = await tester.startGesture(schedulePos);
      await tester.pump(const Duration(milliseconds: 16));
      await dragOpaque.moveTo(settingsPos);
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 48));
      expect(_shellPosition(tester), greaterThan(0.5));

      nav.push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Scaffold(body: Text('零时长不透明遮罩')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('零时长不透明遮罩'), findsOneWidget);

      await dragOpaque.up();
      await tester.pumpAndSettle();
      nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('零时长不透明遮罩'), findsNothing);
      expect(_shellPosition(tester), closeTo(0.0, 0.001));

      // 返回首页后课表页与 Dock 交互均完全恢复正常。
      await tester.tap(find.text('电力电子技术'));
      await tester.pumpAndSettle();
      expect(find.text('高密校区 M1-239'), findsWidgets);
      nav.pop();
      await tester.pumpAndSettle();
    });

    testWidgets('菜单已展开或处于第 0 帧预测量期时推入零时长路由（不透明与非不透明）或在构建期关闭作用域，不触发构建期重入且清理彻底', (
      tester,
    ) async {
      final model = _buildModel();
      addTearDown(model.dispose);

      await tester.pumpWidget(_wrapHome(model));
      await tester.pumpAndSettle();

      final nav = Navigator.of(tester.element(find.byType(HomeShell)));
      final moreTrigger = find.byIcon(Icons.more_horiz_rounded);

      // 1. 菜单已展开时推入零时长非不透明路由。
      await tester.tap(moreTrigger);
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);

      nav.push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Center(child: Text('零时长非不透明页')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('零时长非不透明页'), findsOneWidget);
      expect(find.text('校准当前周次'), findsNothing);

      nav.pop();
      await tester.pumpAndSettle();
      expect(
        TactileSurfaceButton.debugMorphOpacityOf(tester.element(moreTrigger)),
        1.0,
      );

      // 2. 菜单已展开时推入零时长不透明路由（TickerMode 与 ModalRoute 同时切换）。
      await tester.tap(moreTrigger);
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);

      nav.push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Scaffold(body: Text('零时长不透明页')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('零时长不透明页'), findsOneWidget);
      expect(find.text('校准当前周次'), findsNothing);

      nav.pop();
      await tester.pumpAndSettle();
      expect(
        TactileSurfaceButton.debugMorphOpacityOf(tester.element(moreTrigger)),
        1.0,
      );

      // 3. 菜单处于第 0 帧（initState / 预测量之前）推入零时长非不透明路由。
      await tester.tap(moreTrigger);
      nav.push(
        PageRouteBuilder<void>(
          opaque: false,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Center(child: Text('第0帧非不透明页')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('第0帧非不透明页'), findsOneWidget);
      expect(find.text('校准当前周次'), findsNothing);

      nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(
        TactileSurfaceButton.debugMorphOpacityOf(tester.element(moreTrigger)),
        1.0,
      );

      // 4. 菜单处于第 0 帧（预测量之前）推入零时长不透明路由。
      await tester.tap(moreTrigger);
      nav.push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Scaffold(body: Text('第0帧不透明页')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('第0帧不透明页'), findsOneWidget);
      expect(find.text('校准当前周次'), findsNothing);

      nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(
        TactileSurfaceButton.debugMorphOpacityOf(tester.element(moreTrigger)),
        1.0,
      );

      // 4b. 菜单处于首帧测量后尚未展开（仅 pump 1 帧）推入零时长不透明路由。
      await tester.tap(moreTrigger);
      await tester.pump();
      nav.push(
        PageRouteBuilder<void>(
          opaque: true,
          transitionDuration: Duration.zero,
          reverseTransitionDuration: Duration.zero,
          pageBuilder: (_, _, _) => const Scaffold(body: Text('首帧不透明页')),
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(find.text('首帧不透明页'), findsOneWidget);
      expect(find.text('校准当前周次'), findsNothing);

      nav.pop();
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(
        TactileSurfaceButton.debugMorphOpacityOf(tester.element(moreTrigger)),
        1.0,
      );

      // 5. 返回后菜单可再次正常打开与关闭。
      await tester.tap(moreTrigger);
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);
      await tester.tapAt(const Offset(20, 200));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
    });

    testWidgets(
      '构建期直接更新 AppMenuScope(active: false)、TickerMode(enabled: false) 或卸载作用域清理菜单不触发构建期重入',
      (tester) async {
        Widget buildHarness({
          required bool active,
          required bool tickers,
          bool mountScope = true,
        }) {
          return MaterialApp(
            theme: buildLightTheme(),
            home: TickerMode(
              enabled: tickers,
              child: mountScope
                  ? AppMenuScope(
                      active: active,
                      child: Scaffold(
                        body: Center(
                          child: Builder(
                            builder: (context) => TactileSurfaceButton(
                              onMenuOpen: (anchorContext, dragPointer) {
                                showAppMenu<String>(
                                  context: anchorContext,
                                  dragPointer: dragPointer,
                                  items: const <AppMenuItem<String>>[
                                    AppMenuItem<String>(
                                      value: 'a',
                                      label: '测试菜单项A',
                                    ),
                                  ],
                                  onSelected: (_) {},
                                );
                              },
                              child: const Text('打开测试菜单'),
                            ),
                          ),
                        ),
                      ),
                    )
                  : const Scaffold(body: SizedBox.shrink()),
            ),
          );
        }

        // 1. 第 0 帧预测量前通过 pumpWidget 将 AppMenuScope.active 设为 false（构建期触发 didUpdateWidget）。
        await tester.pumpWidget(buildHarness(active: true, tickers: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开测试菜单'));
        await tester.pumpWidget(buildHarness(active: false, tickers: true));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('测试菜单项A'), findsNothing);

        // 2. 菜单已展开时通过 pumpWidget 将 TickerMode.enabled 设为 false（构建期触发 didChangeDependencies / _onTickerModeChanged）。
        await tester.pumpWidget(buildHarness(active: true, tickers: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开测试菜单'));
        await tester.pumpAndSettle();
        expect(find.text('测试菜单项A'), findsOneWidget);

        await tester.pumpWidget(buildHarness(active: true, tickers: false));
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('测试菜单项A'), findsNothing);

        // 3. 菜单已展开时直接卸载 AppMenuScope（在 finalizeTree / dispose 期清理 OverlayEntry）。
        await tester.pumpWidget(buildHarness(active: true, tickers: true));
        await tester.pumpAndSettle();
        await tester.tap(find.text('打开测试菜单'));
        await tester.pumpAndSettle();
        expect(find.text('测试菜单项A'), findsOneWidget);

        await tester.pumpWidget(
          buildHarness(active: true, tickers: true, mountScope: false),
        );
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('测试菜单项A'), findsNothing);
      },
    );

    testWidgets(
      '构建期外部更新 FloatingDock.index 时不向干净兄弟节点同步重入通知，且覆盖路由后继续拖拽不再触发预览提示',
      (tester) async {
        final progressNotifier = ValueNotifier<double>(0.0);
        addTearDown(progressNotifier.dispose);
        late void Function(int) setIndex;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: _DockSiblingReentrancyHost(
              progressNotifier: progressNotifier,
              onReady: (setter) => setIndex = setter,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(progressNotifier.value, closeTo(0.0, 0.001));

        // 外部 setState 直接切换 FloatingDock.index，兄弟 AnimatedBuilder 在本帧保持干净，
        // _reportPillProgress 必须延后至帧末通知而不抛 setState/markNeedsBuild during build。
        setIndex(2);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(progressNotifier.value, closeTo(1.0, 0.01));
      },
    );

    testWidgets(
      '声明式 Navigator(pages:) 构建期推入零时长非不透明页时 Dock 中止不重入、拖拽移动被忽略，且已展开菜单首帧即隐身不闪烁',
      (tester) async {
        final progressNotifier = ValueNotifier<double>(0.0);
        addTearDown(progressNotifier.dispose);
        var hintCount = 0;
        late void Function(bool) setOverlay;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: _DeclarativeNavReentrancyHost(
              progressNotifier: progressNotifier,
              onHint: (_) => hintCount++,
              onReady: (setter) => setOverlay = setter,
            ),
          ),
        );
        await tester.pumpAndSettle();

        // 1. 拖动 FloatingDock 中途通过声明式 pages 构建期推入零时长非不透明路由。
        final dockDrag = await tester.startGesture(
          tester.getCenter(find.text('页A')),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await dockDrag.moveTo(tester.getCenter(find.text('页B')));
        await tester.pump(const Duration(milliseconds: 16));
        await tester.pump(const Duration(milliseconds: 48));
        expect(progressNotifier.value, greaterThan(0.2));
        final hintsBeforePush = hintCount;

        setOverlay(true);
        await tester.pump();
        await dockDrag.moveTo(tester.getCenter(find.text('页C')));
        await tester.pump();
        expect(hintCount, hintsBeforePush);
        await tester.pumpAndSettle();
        expect(find.text('声明式覆盖页'), findsOneWidget);
        expect(progressNotifier.value, closeTo(0.0, 0.01));
        await dockDrag.up();
        await tester.pumpAndSettle();

        setOverlay(false);
        await tester.pumpAndSettle();

        // 2. 菜单已展开时构建期推入声明式零时长非不透明路由：首帧单次 pump 后菜单即不可见（无 1 帧闪烁）。
        await tester.tap(find.text('声明式打开菜单'));
        await tester.pumpAndSettle();
        expect(find.text('声明式菜单项'), findsOneWidget);

        setOverlay(true);
        await tester.pump();
        final morphBoxes = find.byElementPredicate(
          (e) => e.renderObject is RenderMenuMorphBox,
        );
        if (morphBoxes.evaluate().isNotEmpty) {
          final ro = tester.renderObject<RenderMenuMorphBox>(morphBoxes.first);
          expect(ro.shellOpacity, lessThanOrEqualTo(0.001));
          expect(ro.contentOpacity, lessThanOrEqualTo(0.001));
        }
        await tester.pumpAndSettle();
        expect(find.text('声明式菜单项'), findsNothing);
      },
    );

    testWidgets(
      '局部关闭 TickerMode 首帧零闪烁、快速收起交接重开后第 0 帧关闭作用域及整棵 MaterialApp/Overlay 卸载均清理彻底无异常',
      (tester) async {
        late void Function({bool? active, bool? tickers}) updateHost;

        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: _LocalMenuScopeHost(onReady: (fn) => updateHost = fn),
          ),
        );
        await tester.pumpAndSettle();

        // 1. 仅局部 setState 关闭 TickerMode（不重建 Overlay）：首帧即隐藏无闪烁。
        await tester.tap(find.text('局部菜单按钮'));
        await tester.pumpAndSettle();
        expect(find.text('局部菜单项'), findsOneWidget);

        updateHost(tickers: false);
        await tester.pump();
        final morphBoxes = find.byElementPredicate(
          (e) => e.renderObject is RenderMenuMorphBox,
        );
        if (morphBoxes.evaluate().isNotEmpty) {
          final ro = tester.renderObject<RenderMenuMorphBox>(morphBoxes.first);
          expect(ro.shellOpacity, lessThanOrEqualTo(0.001));
        }
        await tester.pumpAndSettle();
        expect(find.text('局部菜单项'), findsNothing);

        // 2. 收起中途快速重开同按钮（触发 handoffClosingSession）后第 0 帧局部失活作用域。
        updateHost(tickers: true);
        await tester.pumpAndSettle();
        await tester.tap(find.text('局部菜单按钮'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 32));
        await tester.tap(find.text('局部菜单按钮'));
        updateHost(active: false);
        await tester.pump();
        await tester.pumpAndSettle();
        expect(find.text('局部菜单项'), findsNothing);
        expect(activeAppMenuMorph.value.$1, isNull);
        expect(
          TactileSurfaceButton.debugMorphOpacityOf(
            tester.element(find.text('局部菜单按钮')),
          ),
          1.0,
        );

        // 3. 重新展开后直接卸载整棵 MaterialApp/Overlay：不访问失活元素、不泄露 Ticker 或 OverlayEntry。
        updateHost(active: true);
        await tester.pumpAndSettle();
        await tester.tap(find.text('局部菜单按钮'));
        await tester.pumpAndSettle();
        expect(find.text('局部菜单项'), findsOneWidget);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(find.text('局部菜单项'), findsNothing);
      },
    );
  });
}

class _DockSiblingReentrancyHost extends StatefulWidget {
  const _DockSiblingReentrancyHost({
    required this.progressNotifier,
    required this.onReady,
  });

  final ValueNotifier<double> progressNotifier;
  final void Function(void Function(int)) onReady;

  @override
  State<_DockSiblingReentrancyHost> createState() =>
      _DockSiblingReentrancyHostState();
}

class _DockSiblingReentrancyHostState
    extends State<_DockSiblingReentrancyHost> {
  int _index = 0;

  @override
  void initState() {
    super.initState();
    widget.onReady((next) => setState(() => _index = next));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: AnimatedBuilder(
              animation: widget.progressNotifier,
              builder: (_, _) =>
                  Center(child: Text('pos=${widget.progressNotifier.value}')),
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingDock(
              index: _index,
              onPillProgress: (p) => widget.progressNotifier.value = p,
              items: const <FloatingDockItem>[
                FloatingDockItem(
                  icon: Icons.home,
                  activeIcon: Icons.home,
                  label: '页A',
                ),
                FloatingDockItem(
                  icon: Icons.star,
                  activeIcon: Icons.star,
                  label: '页B',
                ),
                FloatingDockItem(
                  icon: Icons.settings,
                  activeIcon: Icons.settings,
                  label: '页C',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ZeroDurationTestPage extends Page<void> {
  const _ZeroDurationTestPage({
    required this.child,
    this.opaque = true,
    super.key,
  });

  final Widget child;
  final bool opaque;

  @override
  Route<void> createRoute(BuildContext context) {
    return PageRouteBuilder<void>(
      settings: this,
      opaque: opaque,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: Duration.zero,
      pageBuilder: (_, _, _) => child,
    );
  }
}

class _DeclarativeNavReentrancyHost extends StatefulWidget {
  const _DeclarativeNavReentrancyHost({
    required this.progressNotifier,
    required this.onReady,
    this.onHint,
  });

  final ValueNotifier<double> progressNotifier;
  final void Function(void Function(bool)) onReady;
  final ValueChanged<int>? onHint;

  @override
  State<_DeclarativeNavReentrancyHost> createState() =>
      _DeclarativeNavReentrancyHostState();
}

class _DeclarativeNavReentrancyHostState
    extends State<_DeclarativeNavReentrancyHost> {
  bool _showOverlay = false;

  @override
  void initState() {
    super.initState();
    widget.onReady((v) => setState(() => _showOverlay = v));
  }

  @override
  Widget build(BuildContext context) {
    return Navigator(
      pages: <Page<void>>[
        _ZeroDurationTestPage(
          key: const ValueKey<String>('home'),
          child: AppMenuScope(
            child: Scaffold(
              body: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: widget.progressNotifier,
                      builder: (_, _) => Center(
                        child: Builder(
                          builder: (ctx) => TactileSurfaceButton(
                            onMenuOpen: (anchorCtx, ptr) {
                              showAppMenu<String>(
                                context: anchorCtx,
                                dragPointer: ptr,
                                items: const <AppMenuItem<String>>[
                                  AppMenuItem<String>(
                                    value: '1',
                                    label: '声明式菜单项',
                                  ),
                                ],
                                onSelected: (_) {},
                              );
                            },
                            child: const Text('声明式打开菜单'),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: FloatingDock(
                      index: 0,
                      onPillProgress: (p) => widget.progressNotifier.value = p,
                      onTargetIndexHint: widget.onHint,
                      items: const <FloatingDockItem>[
                        FloatingDockItem(
                          icon: Icons.home,
                          activeIcon: Icons.home,
                          label: '页A',
                        ),
                        FloatingDockItem(
                          icon: Icons.star,
                          activeIcon: Icons.star,
                          label: '页B',
                        ),
                        FloatingDockItem(
                          icon: Icons.settings,
                          activeIcon: Icons.settings,
                          label: '页C',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (_showOverlay)
          const _ZeroDurationTestPage(
            key: ValueKey<String>('overlay'),
            opaque: false,
            child: Center(child: Text('声明式覆盖页')),
          ),
      ],
      onDidRemovePage: (_) {},
    );
  }
}

class _LocalMenuScopeHost extends StatefulWidget {
  const _LocalMenuScopeHost({required this.onReady});

  final void Function(void Function({bool? active, bool? tickers})) onReady;

  @override
  State<_LocalMenuScopeHost> createState() => _LocalMenuScopeHostState();
}

class _LocalMenuScopeHostState extends State<_LocalMenuScopeHost> {
  bool _active = true;
  bool _tickers = true;

  @override
  void initState() {
    super.initState();
    widget.onReady(({bool? active, bool? tickers}) {
      setState(() {
        if (active != null) _active = active;
        if (tickers != null) _tickers = tickers;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    return TickerMode(
      enabled: _tickers,
      child: AppMenuScope(
        active: _active,
        child: Scaffold(
          body: Center(
            child: Builder(
              builder: (context) => TactileSurfaceButton(
                onMenuOpen: (anchorContext, dragPointer) {
                  showAppMenu<String>(
                    context: anchorContext,
                    dragPointer: dragPointer,
                    items: const <AppMenuItem<String>>[
                      AppMenuItem<String>(value: 'x', label: '局部菜单项'),
                    ],
                    onSelected: (_) {},
                  );
                },
                child: const Text('局部菜单按钮'),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
