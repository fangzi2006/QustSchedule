/// 界面测试：课表页三点菜单、周次校准/切换与外观调节面板。
library;

import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/academic_page.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/reschedule_page.dart';
import 'package:qustschedule/pages/schedule_page.dart';
import 'package:qustschedule/pages/school_address_page.dart';
import 'package:qustschedule/pages/settings_page.dart';
import 'package:qustschedule/pages/timetable_list_page.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/app_menu.dart';
import 'package:qustschedule/widgets/course_tile.dart';
import 'package:qustschedule/widgets/floating_dock.dart';
import 'package:qustschedule/widgets/tactile_button.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/widget_test_helpers.dart';

void main() {
  group('课表页三点菜单', () {
    testWidgets('菜单项精简、原地变形展开几何与触发按钮隐退恢复，关闭旧版水波纹且无多余返回键', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      expect(find.byType(BackButton), findsNothing);

      final triggerFinder = find.byIcon(Icons.more_horiz_rounded);
      final triggerRect = tester.getRect(triggerFinder);

      await tester.tap(triggerFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 370));

      final label = find.text('校准当前周次');
      final morphBox = tester.renderObject<RenderMenuMorphBox>(
        find.byElementPredicate((e) => e.renderObject is RenderMenuMorphBox),
      );
      expect(morphBox.contentOpacity, 1);
      expect(morphBox.shellOpacity, 1);
      expect(morphBox.isSettled, isTrue);
      expect(morphBox.morphRadius, closeTo(20.0, 0.01));

      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);
      expect(find.text('作息时间表'), findsOneWidget);
      expect(find.text('教务地址'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('调试信息'), findsNothing);
      expect(find.text('退出登录'), findsNothing);
      expect(find.byType(BackButton), findsNothing);
      expect(find.byType(CloseButton), findsNothing);

      expect(
        TactileSurfaceButton.debugMorphOpacityOf(tester.element(triggerFinder)),
        lessThan(0.05),
      );

      final inkWell = tester.widget<InkWell>(
        find
            .ancestor(of: find.text('教务地址'), matching: find.byType(InkWell))
            .first,
      );
      expect(inkWell.splashFactory, NoSplash.splashFactory);
      expect(inkWell.splashColor, Colors.transparent);
      expect(inkWell.highlightColor, Colors.transparent);
      expect(inkWell.hoverColor, Colors.transparent);

      final card = find
          .ancestor(of: label, matching: find.byType(Material))
          .last;
      final tile = find
          .ancestor(of: label, matching: find.byType(InkWell))
          .first;
      final cardRect = tester.getRect(card);
      final tileRect = tester.getRect(tile);
      expect(tileRect.top - cardRect.top, closeTo(4.0, 0.5));
      expect((tileRect.left - cardRect.left).abs(), lessThan(1));
      expect((cardRect.right - tileRect.right).abs(), lessThan(1));
      expect(cardRect.width, greaterThanOrEqualTo(168));
      expect(tileRect.height, greaterThanOrEqualTo(46));
      expect(cardRect.contains(triggerRect.center), isTrue);

      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(
        TactileSurfaceButton.debugMorphOpacityOf(tester.element(triggerFinder)),
        1.0,
      );
    });

    testWidgets('点击导航、按住上下滑选、滑出边界松手不误选、分割线无缝吸附与长按直滑选中', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      // 1. 点击菜单项进入「作息时间表」
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作息时间表'));
      await tester.pumpAndSettle();
      expect(find.byType(TimetableListPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 2. 滑出边界外松手：既不选中也不关闭，回弹后仍可按住上下滑选
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      final label = find.text('校准当前周次');
      final cardRect = tester.getRect(
        find.ancestor(of: label, matching: find.byType(Material)).last,
      );
      var gesture = await tester.startGesture(tester.getCenter(label));
      await gesture.moveTo(Offset(cardRect.left - 80, cardRect.center.dy));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);

      // 按住从「校准当前周次」滑到「教务地址」松手选中
      gesture = await tester.startGesture(tester.getCenter(label));
      await gesture.moveTo(tester.getCenter(find.text('教务地址')));
      await tester.pump();
      expect(find.byType(SchoolAddressPage), findsNothing);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(SchoolAddressPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 3. 长按右上角按钮下拉直滑入短菜单选中「教务地址」
      gesture = await tester.startGesture(
        tester.getCenter(find.byIcon(Icons.more_horiz_rounded)),
      );
      await tester.pump(const Duration(milliseconds: 220));
      await tester.pumpAndSettle();
      await gesture.moveTo(tester.getCenter(find.text('教务地址')));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(SchoolAddressPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      // 4. 滑到教务地址与外观之间的分割线上松手无缝吸附选中
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      final dividerRect = tester.getRect(find.byType(Divider).last);
      gesture = await tester.startGesture(tester.getCenter(label));
      await gesture.moveTo(
        Offset(dividerRect.center.dx, dividerRect.center.dy + 0.2),
      );
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsOneWidget);
    });

    testWidgets(
      '展开中途（60ms / 20ms / 16ms）打断关闭时菜单卡片与触发按钮平滑收起，且未展开到的目标占位框区域点击仅关菜单',
      (tester) async {
        final model = buildModel();
        model.hydrateForTest(schedule: sparseSchedule(), week: 1);
        await tester.pumpWidget(wrap(HomeShell(model: model)));
        await tester.pumpAndSettle();

        final triggerFinder = find.byIcon(Icons.more_horiz_rounded);

        RenderMenuMorphBox menuMorphBox() =>
            tester.renderObject<RenderMenuMorphBox>(
              find.byElementPredicate(
                (e) => e.renderObject is RenderMenuMorphBox,
              ),
            );
        double shellOpacity() => menuMorphBox().shellOpacity;
        double cardScale() => menuMorphBox().contentScale;
        double triggerOpacity() => TactileSurfaceButton.debugMorphOpacityOf(
          tester.element(triggerFinder),
        );

        // 先测完整菜单终态矩形，验证 20ms 展开初期点击视觉卡片外、目标占位框内仅关闭菜单不误触
        await tester.tap(triggerFinder);
        await tester.pumpAndSettle();
        final fullCardRect = tester.getRect(
          find
              .ancestor(of: find.text('调课'), matching: find.byType(Material))
              .last,
        );
        await tester.tapAt(const Offset(20, 200));
        await tester.pumpAndSettle();

        await tester.tap(triggerFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final morphedCardRect = tester.getRect(
          find
              .ancestor(of: find.text('调课'), matching: find.byType(Material))
              .last,
        );
        final probePoint = Offset(
          fullCardRect.left + 12,
          fullCardRect.bottom - 12,
        );
        expect(fullCardRect.contains(probePoint), isTrue);
        expect(morphedCardRect.contains(probePoint), isFalse);
        await tester.tapAt(probePoint);
        await tester.pumpAndSettle();
        expect(find.text('调课'), findsNothing);
        expect(find.byType(ReschedulePage), findsNothing);

        // 1. 60ms 中途打断：平滑缩回
        await tester.tap(triggerFinder);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));

        final scaleAt60 = cardScale();
        final triggerAt60 = triggerOpacity();
        expect(scaleAt60, inInclusiveRange(0.60, 0.95));
        expect(shellOpacity(), closeTo(1.0, 0.01));
        expect(triggerAt60, lessThan(0.30));

        await tester.tapAt(const Offset(20, 200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 64));
        expect(find.text('校准当前周次'), findsOneWidget);
        expect(cardScale(), lessThan(scaleAt60 - 0.10));
        expect(triggerOpacity(), greaterThan(triggerAt60));

        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(triggerOpacity(), 1.0);

        // 2. 极早期（20ms）打断与系统返回键（50ms）打断
        await tester.tap(triggerFinder);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 20));
        final opacityAt20 = shellOpacity();
        await tester.tapAt(const Offset(20, 200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(shellOpacity(), greaterThan(opacityAt20 * 0.75));
        await tester.pumpAndSettle();

        await tester.tap(triggerFinder);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        await Navigator.of(tester.element(find.byType(HomeShell))).maybePop();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 56));
        expect(find.text('校准当前周次'), findsOneWidget);
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);

        // 3. 16ms 打断、关闭途中重开再打断
        await tester.tap(triggerFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        await tester.tapAt(const Offset(20, 200));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 48));
        expect(find.text('校准当前周次'), findsOneWidget);

        await tester.tap(triggerFinder);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 40));
        await tester.tapAt(const Offset(20, 200));
        await tester.pumpAndSettle();
        expect(find.text('校准当前周次'), findsNothing);
        expect(triggerOpacity(), 1.0);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets('长按拖出与可滚动周次长菜单及拖动/点击 Dock 在展开或打开时打断均平滑收起且直接切页', (tester) async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: Schedule(
          termId: '2026-2027-1',
          maxWeeks: 20,
          entries: sparseSchedule().entries,
        ),
        week: 1,
      );
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      final moreTrigger = find.byIcon(Icons.more_horiz_rounded);
      final weekTrigger = find.text('第 1 周');

      double triggerOpacityOf(Finder finder) =>
          TactileSurfaceButton.debugMorphOpacityOf(tester.element(finder));

      // 1. 长按交接展开途中被返回键打断
      final holdPos = tester.getCenter(moreTrigger);
      final dragOpen = await tester.startGesture(holdPos);
      await tester.pump(const Duration(milliseconds: 250));
      await dragOpen.moveTo(const Offset(24, 240));
      await tester.pump(const Duration(milliseconds: 20));
      expect(find.text('校准当前周次'), findsOneWidget);

      await Navigator.of(tester.element(find.byType(HomeShell))).maybePop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      expect(find.text('校准当前周次'), findsOneWidget);
      await dragOpen.up();
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(triggerOpacityOf(moreTrigger), 1.0);

      // 2. 下拉交接快速抬起后不卡死 _activePointer
      final quickRelease = await tester.startGesture(holdPos);
      await quickRelease.moveBy(const Offset(0, 18));
      await quickRelease.up();
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);
      await tester.tapAt(const Offset(20, 200));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);

      // 3. 可滚动 20 周长菜单在 50ms 展开中途点外部打断
      await tester.tap(weekTrigger);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('第 2 周'), findsOneWidget);
      await tester.tapAt(const Offset(20, 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      expect(find.text('第 2 周'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsNothing);
      expect(triggerOpacityOf(weekTrigger), 1.0);

      // 4. 菜单展开中途或已打开时直接拖动/点击 FloatingDock 切页并同步收起菜单
      final dock = find.byType(FloatingDock);
      final dockSchedule = tester.getCenter(
        find.descendant(of: dock, matching: find.text('课表')),
      );
      final dockAcademic = tester.getCenter(
        find.descendant(of: dock, matching: find.text('学业')),
      );
      final dockSettings = tester.getCenter(
        find.descendant(of: dock, matching: find.text('设置')),
      );

      await tester.tap(moreTrigger);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final dockDrag = await tester.startGesture(dockSchedule);
      await tester.pump(const Duration(milliseconds: 16));
      await dockDrag.moveTo(dockSettings);
      await tester.pump(const Duration(milliseconds: 32));
      expect(find.text('校准当前周次'), findsOneWidget);
      await dockDrag.up();
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(shellPagePosition(tester), 2);
      expect(find.byType(SettingsPage), findsOneWidget);

      await tester.tapAt(dockSchedule);
      await tester.pumpAndSettle();
      await tester.tap(moreTrigger);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(dockAcademic);
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(shellPagePosition(tester), 1);
      expect(find.byType(AcademicPage), findsOneWidget);
    });

    testWidgets('可滚动周次长菜单沿中轴线展开、左对齐紧凑窄宽、当前周次对勾常态且滚动不误选', (tester) async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: Schedule(
          termId: '2026-2027-1',
          maxWeeks: 20,
          entries: sparseSchedule().entries,
        ),
        week: 3,
      );
      final lightTheme = buildLightTheme();
      final scheme = lightTheme.colorScheme;
      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: SchedulePage(model: model),
        ),
      );
      await tester.pumpAndSettle();

      final weekTrigger = find.ancestor(
        of: find.text('第 3 周'),
        matching: find.byType(TactileSurfaceButton),
      );
      final triggerRect = tester.getRect(weekTrigger);

      await tester.tap(find.text('第 3 周'));
      await tester.pumpAndSettle();

      final menuMaterial = find
          .ancestor(of: find.text('第 2 周'), matching: find.byType(Material))
          .first;
      final menuRect = tester.getRect(menuMaterial);
      expect(menuRect.center.dx, closeTo(triggerRect.center.dx, 1.0));
      expect(menuRect.top, closeTo(triggerRect.top, 1.0));
      expect(menuRect.width, lessThan(168.0));

      final morphBox = tester.renderObject<RenderMenuMorphBox>(
        find.byElementPredicate((e) => e.renderObject is RenderMenuMorphBox),
      );
      expect(morphBox.alignment, Alignment.topCenter);

      Finder findMenuItemText(String label) =>
          find.descendant(of: menuMaterial, matching: find.text(label));

      BoxDecoration? findMenuTileDecoration(String label) {
        final textFinder = findMenuItemText(label);
        if (textFinder.evaluate().isEmpty) return null;
        final boxes = tester.widgetList<DecoratedBox>(
          find.ancestor(
            of: textFinder.first,
            matching: find.byType(DecoratedBox),
          ),
        );
        for (final box in boxes) {
          final dec = box.decoration;
          if (dec is BoxDecoration &&
              dec.borderRadius == BorderRadius.circular(14)) {
            return dec;
          }
        }
        return null;
      }

      final week3Text = findMenuItemText('第 3 周').first;
      final week5Text = findMenuItemText('第 5 周').first;
      expect(
        tester.getTopLeft(week3Text).dx - menuRect.left,
        closeTo(18.0, 1.0),
      );
      expect(
        find.descendant(
          of: menuMaterial,
          matching: find.byIcon(Icons.check_rounded),
        ),
        findsOneWidget,
      );
      expect(findMenuTileDecoration('第 3 周')!.color, Colors.transparent);
      expect(findMenuTileDecoration('第 5 周')!.color, Colors.transparent);

      // 按住「第 5 周」出现选择胶囊，然后向上滚走取消按住状态且不误切周次
      final holdGesture = await tester.startGesture(
        tester.getCenter(week5Text),
      );
      await tester.pump(const Duration(milliseconds: 150));
      final pressedDec = findMenuTileDecoration('第 5 周');
      expect(pressedDec!.color, scheme.primary.withValues(alpha: 0.11));

      await holdGesture.moveBy(const Offset(0, -140));
      await tester.pump();
      await holdGesture.up();
      await tester.pumpAndSettle();

      expect(model.week, 3);
      final afterScrollDec = findMenuTileDecoration('第 5 周');
      if (afterScrollDec != null) {
        expect(afterScrollDec.color, Colors.transparent);
      }

      await tester.drag(find.text('第 5 周'), const Offset(0, -230));
      await tester.pumpAndSettle();
      expect(find.text('第 12 周'), findsOneWidget);
      await tester.tap(find.text('第 12 周'));
      await tester.pumpAndSettle();
      expect(model.week, 12);
    });

    testWidgets('外部遮罩拦截与二级页/非不透明路由隔离：点卡片或外部仅关菜单，Dock 边缘橡皮筋收起菜单', (
      tester,
    ) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      // 1. 菜单展开或动画中途点击课程卡片、横向翻周、点翻周箭头：只关闭菜单不穿透触发
      final courseCenter = tester.getCenter(find.byType(CourseBlock).first);
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tapAt(courseCenter);
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tapAt(courseCenter);
      await tester.pumpAndSettle();
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.flingFrom(
        tester.getCenter(find.byType(PageView).first),
        const Offset(-300, 0),
        800,
      );
      await tester.pumpAndSettle();
      expect(model.week, 1);

      // 2. 从 Dock 左侧向外拖动触发边缘橡皮筋：菜单收起且无异常
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      final dockSchedulePos = tester.getCenter(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('课表'),
        ),
      );
      final dockSettingsPos = tester.getCenter(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('设置'),
        ),
      );
      final edgeDrag = await tester.startGesture(dockSchedulePos);
      await edgeDrag.moveBy(const Offset(-90, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 180));
      await tester.pump();
      expect(find.text('校准当前周次'), findsNothing);
      await edgeDrag.up();
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 0);

      // 3. 二级页面与非不透明浮层路由展开菜单时点击底层 Dock 坐标位置仍拦截
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作息时间表'));
      await tester.pumpAndSettle();
      expect(find.byType(TimetableListPage), findsOneWidget);

      await tester.tap(find.byIcon(Icons.more_vert_rounded).first);
      await tester.pumpAndSettle();
      expect(find.text('至少保留一张'), findsOneWidget);
      await tester.tapAt(dockSettingsPos);
      await tester.pumpAndSettle();
      expect(find.text('至少保留一张'), findsNothing);
      expect(find.byType(TimetableListPage), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 0);

      final nav = Navigator.of(tester.element(find.byType(HomeShell)));
      nav.push<void>(
        PageRouteBuilder<void>(
          opaque: false,
          pageBuilder: (_, _, _) => Scaffold(
            backgroundColor: Colors.transparent,
            appBar: AppBar(
              actions: <Widget>[
                TactileSurfaceButton(
                  minSize: const Size(36, 36),
                  onMenuOpen: (ctx, ptr) {
                    showAppMenu<String>(
                      context: ctx,
                      dragPointer: ptr,
                      items: const <AppMenuItem<String>>[
                        AppMenuItem<String>(value: 'x', label: '浮层菜单项'),
                      ],
                      onSelected: (_) {},
                    );
                  },
                  child: const SizedBox(
                    width: 36,
                    height: 36,
                    child: Icon(Icons.more_vert_rounded),
                  ),
                ),
              ],
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.more_vert_rounded));
      await tester.pumpAndSettle();
      expect(find.text('浮层菜单项'), findsOneWidget);
      await tester.tapAt(dockSettingsPos);
      await tester.pumpAndSettle();
      expect(find.text('浮层菜单项'), findsNothing);
      expect(shellPagePosition(tester), 0);
    });

    testWidgets('桌面端悬停、滚轮与右键交互：菜单外拦截悬停与滚动，Dock 悬停与点击仍保持最高优先级', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      final scheduleScroll = tester.state<ScrollableState>(
        find.descendant(
          of: find.byType(SchedulePage),
          matching: find.byWidgetPredicate(
            (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
          ),
        ),
      );
      final initialScrollOffset = scheduleScroll.position.pixels;

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);

      final mouse = await tester.createGesture(
        kind: PointerDeviceKind.mouse,
        pointer: 41,
      );
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: Offset.zero);
      await tester.pump();

      final gridCenter = tester.getCenter(find.byType(PageView).first);
      await mouse.moveTo(gridCenter);
      await tester.pump();
      await tester.sendEventToBinding(
        PointerScrollEvent(
          position: gridCenter,
          scrollDelta: const Offset(0, 180),
        ),
      );
      await tester.pumpAndSettle();
      expect(scheduleScroll.position.pixels, initialScrollOffset);
      expect(find.text('校准当前周次'), findsOneWidget);

      double dockScale() => tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(FloatingDock),
              matching: find.byType(Transform),
            ),
          )
          .last
          .transform
          .getMaxScaleOnAxis();
      final dockScaleBefore = dockScale();

      final dockSettingsPos = tester.getCenter(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('设置'),
        ),
      );
      await mouse.moveTo(dockSettingsPos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 120));
      expect(dockScale(), greaterThan(dockScaleBefore));
      expect(find.text('校准当前周次'), findsOneWidget);

      final secondaryMouse = TestPointer(42, PointerDeviceKind.mouse);
      await tester.sendEventToBinding(
        secondaryMouse.down(
          tester.getCenter(find.text('校准当前周次')),
          buttons: kSecondaryButton,
        ),
      );
      await tester.sendEventToBinding(secondaryMouse.up());
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);

      await tester.sendEventToBinding(
        secondaryMouse.down(
          tester.getCenter(find.byType(CourseBlock).first),
          buttons: kSecondaryButton,
        ),
      );
      await tester.sendEventToBinding(secondaryMouse.up());
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await mouse.down(dockSettingsPos);
      await tester.pump();
      await mouse.up();
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
      expect(shellPagePosition(tester), 2);
    });
  });

  group('外观面板', () {
    testWidgets('双滑块默认值、圆形滑柄样式、拖动实时放大课表与恢复默认', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();

      expect(find.text('课表格子高度'), findsOneWidget);
      expect(find.text('课程文字大小'), findsOneWidget);

      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders, hasLength(2));
      expect(sliders.first.value, defaultCellHeight);
      expect(sliders.last.value, defaultCourseTextScale);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);

      final theme = tester
          .widget<SliderTheme>(
            find
                .ancestor(
                  of: find.byType(Slider).first,
                  matching: find.byType(SliderTheme),
                )
                .first,
          )
          .data;
      expect(theme.thumbShape, isA<RoundSliderThumbShape>());
      expect(theme.tickMarkShape, SliderTickMarkShape.noTickMark);
      expect(theme.trackShape, isNot(isA<GappedSliderTrackShape>()));

      final before = tester.getSize(find.byType(CourseBlock).first);
      await tester.drag(find.byType(Slider).first, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(model.cellHeight, greaterThan(defaultCellHeight));
      expect(
        tester.widget<Slider>(find.byType(Slider).first).value,
        model.cellHeight,
      );

      await tester.drag(find.byType(Slider).last, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(model.courseTextScale, greaterThan(defaultCourseTextScale));
      expect(
        tester.getSize(find.byType(CourseBlock).first).height,
        greaterThan(before.height),
      );

      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();
      expect(model.cellHeight, defaultCellHeight);
      expect(model.courseTextScale, defaultCourseTextScale);
    });
  });
}
