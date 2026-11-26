/// 界面测试：AppSnackBar、TactileButton、AppMenu、四层合绘、单层 SelectionArea 与底部弹窗容器。
library;

import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show ContainerLayer, MatrixUtils, PaintingContext;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/about_page.dart';
import 'package:qustschedule/pages/debug_page.dart';
import 'package:qustschedule/pages/reschedule_page.dart';
import 'package:qustschedule/pages/schedule_page.dart';
import 'package:qustschedule/pages/school_address_page.dart';
import 'package:qustschedule/pages/settings_page.dart';
import 'package:qustschedule/pages/timetable_edit_page.dart';
import 'package:qustschedule/pages/timetable_list_page.dart';
import 'package:qustschedule/pages/update_proxy_page.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/app_bottom_sheet.dart';
import 'package:qustschedule/widgets/app_menu.dart';
import 'package:qustschedule/widgets/app_snack_bar.dart';
import 'package:qustschedule/widgets/course_tile.dart';
import 'package:qustschedule/widgets/tactile_button.dart';
import 'package:qustschedule/widgets/time_wheel_picker.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';
import 'support/widget_test_helpers.dart';

void main() {
  group('AppSnackBar 现代悬浮胶囊', () {
    testWidgets('渲染图标/文字/操作按钮、避让 Dock、连续调用替换旧提示且支持左右滑动关闭', (tester) async {
      bool actionPressed = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => showAppSnackBar(
                      context,
                      message: '测试轻量胶囊',
                      type: AppSnackBarType.success,
                      action: SnackBarAction(
                        label: '撤销',
                        onPressed: () => actionPressed = true,
                      ),
                    ),
                    child: const Text('触发提示'),
                  ),
                  ElevatedButton(
                    onPressed: () => showAppSnackBar(
                      context,
                      message: 'Dock 避让测试',
                      type: AppSnackBarType.info,
                      aboveDock: true,
                      duration: const Duration(seconds: 10),
                    ),
                    child: const Text('触发避让提示'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('触发提示'));
      await tester.pumpAndSettle();
      expect(find.text('测试轻量胶囊'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_rounded), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(actionPressed, isTrue);

      // 连续调用自动清理上一个，并验证 aboveDock 边距与左右滑动关闭
      await tester.tap(find.text('触发提示'));
      await tester.pump();
      await tester.tap(find.text('触发避让提示'));
      await tester.pumpAndSettle();
      expect(find.text('测试轻量胶囊'), findsNothing);
      expect(find.text('Dock 避让测试'), findsOneWidget);

      final SnackBar snackBar = tester.widget(find.byType(SnackBar));
      expect((snackBar.margin as EdgeInsets).bottom, greaterThan(60));
      expect(snackBar.dismissDirection, DismissDirection.horizontal);

      await tester.tap(find.text('Dock 避让测试'));
      await tester.pump();
      expect(find.text('Dock 避让测试'), findsOneWidget);

      await tester.fling(find.text('Dock 避让测试'), const Offset(500, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('Dock 避让测试'), findsNothing);
    });

    testWidgets('短文案紧凑圆胶囊且底距舒适，长报错胶囊淡红描边并自动换用 20dp 圆角', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () => showAppSnackBar(
                      context,
                      message: '密码已更新',
                      type: AppSnackBarType.success,
                    ),
                    child: const Text('触发短胶囊'),
                  ),
                  ElevatedButton(
                    onPressed: () => showAppSnackBar(
                      context,
                      message: '这是一条非常非常长的错误提示信息，用来验证超出单行宽度限制时会自动换用二十像素圆角且不会发生任何排版溢出',
                      type: AppSnackBarType.error,
                    ),
                    child: const Text('触发长报错'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('触发短胶囊'));
      await tester.pumpAndSettle();
      final SnackBar shortSnack = tester.widget(find.byType(SnackBar));
      expect(
        (shortSnack.margin as EdgeInsets).bottom,
        greaterThanOrEqualTo(40),
      );
      final shortPill = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(tester.getSize(find.byWidget(shortPill)).width, lessThan(220));
      expect(
        (shortPill.decoration as BoxDecoration).borderRadius,
        BorderRadius.circular(999),
      );

      await tester.tap(find.text('触发长报错'));
      await tester.pumpAndSettle();
      final longPill = tester.widget<DecoratedBox>(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.byType(DecoratedBox),
        ),
      );
      expect(
        tester.getSize(find.byWidget(longPill)).width,
        lessThanOrEqualTo(420),
      );
      final longDec = longPill.decoration as BoxDecoration;
      expect(longDec.borderRadius, BorderRadius.circular(20));
      expect(
        (longDec.border! as Border).top.color,
        buildLightTheme().colorScheme.error.withValues(alpha: 0.40),
      );
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('触控按钮、长按菜单与架构性能回归', () {
    testWidgets('背景按钮纯白带阴影、卡片内无阴影、按下放大反馈无下沉、非菜单按钮不包 ClipRRect 且失活卸载安全', (
      tester,
    ) async {
      var childBuilds = 0;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TactileIconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () {},
                  ),
                  TactileIconButton(
                    icon: const Icon(Icons.delete_outline_rounded),
                    surfaceStyle: TactileSurfaceStyle.tinted,
                    onPressed: () {},
                  ),
                  TactileActionButton(
                    variant: TactileActionVariant.tonal,
                    onPressed: () {},
                    label: const Text('检查更新'),
                  ),
                  TactileSurfaceButton(
                    onTap: () {},
                    child: Builder(
                      builder: (_) {
                        childBuilds++;
                        return const Text('普通操作');
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final bgSurface = find.ancestor(
        of: find.byIcon(Icons.refresh_rounded),
        matching: find.byType(TactileSurfaceButton),
      );
      final bgDecor = tester.widget<DecoratedBox>(
        find
            .descendant(of: bgSurface, matching: find.byType(DecoratedBox))
            .first,
      );
      final bgBox = bgDecor.decoration as BoxDecoration;
      expect(bgBox.color, Colors.white);
      expect(bgBox.boxShadow, isNotEmpty);
      expect(bgBox.border, isNull);

      final cardSurface = find.ancestor(
        of: find.byIcon(Icons.delete_outline_rounded),
        matching: find.byType(TactileSurfaceButton),
      );
      final cardDecor = tester.widget<DecoratedBox>(
        find
            .descendant(of: cardSurface, matching: find.byType(DecoratedBox))
            .first,
      );
      final cardBox = cardDecor.decoration as BoxDecoration;
      expect(cardBox.boxShadow, isNull);
      expect(cardBox.border, isNull);

      // 非菜单按钮不包 ClipRRect / FadeTransition，且不受 activeAppMenuMorph 影响。
      final plainSurface = find.ancestor(
        of: find.text('普通操作'),
        matching: find.byType(TactileSurfaceButton),
      );
      expect(
        find.descendant(of: plainSurface, matching: find.byType(ClipRRect)),
        findsNothing,
      );
      expect(
        find.descendant(
          of: plainSurface,
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(childBuilds, 1);
      activeAppMenuMorph.value = (null, 0.5);
      await tester.pump();
      activeAppMenuMorph.value = (null, 0.0);
      await tester.pump();
      expect(childBuilds, 1);

      // 按下放大反馈且保持原有底色与阴影无下沉、无边框。
      final restScale = tester
          .widgetList<Transform>(
            find.descendant(of: bgSurface, matching: find.byType(Transform)),
          )
          .last
          .transform
          .storage[0];
      expect(restScale, closeTo(1.0, 0.001));

      final gesture = await tester.startGesture(tester.getCenter(bgSurface));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      final pressedDecor = tester.widget<DecoratedBox>(
        find
            .descendant(of: bgSurface, matching: find.byType(DecoratedBox))
            .first,
      );
      final pressedBox = pressedDecor.decoration as BoxDecoration;
      final pressedScale = tester
          .widgetList<Transform>(
            find.descendant(of: bgSurface, matching: find.byType(Transform)),
          )
          .elementAt(1)
          .transform
          .storage[0];
      expect(pressedScale, greaterThan(1.20));
      expect(pressedBox.color, bgBox.color);
      expect(pressedBox.boxShadow?.first.color, bgBox.boxShadow?.first.color);
      expect(pressedBox.border, isNull);
      await gesture.up();
      await tester.pumpAndSettle();

      // 失活卸载同帧触发菜单形变通知不抛出 inactive element 异常。
      var showButton = true;
      late StateSetter setHostState;
      final dummyAnchorKey = GlobalKey();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                setHostState = setState;
                return Column(
                  children: <Widget>[
                    SizedBox(key: dummyAnchorKey, width: 10, height: 10),
                    if (showButton)
                      TactileSurfaceButton(
                        onMenuOpen: (_, _) {},
                        child: const Text('菜单按钮'),
                      ),
                    if (showButton)
                      _DisposeNotifyHelper(
                        onDispose: () {
                          final ro = dummyAnchorKey.currentContext
                              ?.findRenderObject();
                          activeAppMenuMorph.value = (ro, 0.5);
                        },
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      );
      setHostState(() => showButton = false);
      await tester.pump();
      activeAppMenuMorph.value = (null, 0.0);
      expect(tester.takeException(), isNull);
    });

    testWidgets('触感按钮在跨帧按压与微抖动后松手仍可靠触发单次点击，可滚动容器内滑出容差取消按压而固定按钮保持拖跟', (
      tester,
    ) async {
      var filledCount = 0;
      var tonalCount = 0;
      var outlinedCount = 0;
      var textCount = 0;
      var iconCount = 0;
      var backCount = 0;
      var directTapCount = 0;
      var menuShortTapCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  TactileActionButton(
                    variant: TactileActionVariant.filled,
                    onPressed: () => filledCount++,
                    label: const Text('主按钮'),
                  ),
                  TactileActionButton(
                    onPressed: () => tonalCount++,
                    label: const Text('确认操作'),
                  ),
                  TactileActionButton(
                    variant: TactileActionVariant.outlined,
                    onPressed: () => outlinedCount++,
                    label: const Text('次按钮'),
                  ),
                  TactileActionButton(
                    variant: TactileActionVariant.text,
                    onPressed: () => textCount++,
                    label: const Text('取消操作'),
                  ),
                  TactileIconButton(
                    icon: const Icon(Icons.refresh_rounded),
                    onPressed: () => iconCount++,
                  ),
                  TactileBackButton(onPressed: () => backCount++),
                  TactileSurfaceButton(
                    onTap: () => directTapCount++,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text('直接触控'),
                    ),
                  ),
                  TactileSurfaceButton(
                    onMenuOpen: (_, _) => menuShortTapCount++,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      child: Text('菜单短按'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> humanTap(Finder target) async {
        final gesture = await tester.startGesture(tester.getCenter(target));
        await tester.pump(const Duration(milliseconds: 24));
        await tester.pump(const Duration(milliseconds: 36));
        await gesture.moveBy(const Offset(1.5, 1.5));
        await tester.pump(const Duration(milliseconds: 30));
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await humanTap(find.text('主按钮'));
      await humanTap(find.text('确认操作'));
      await humanTap(find.text('次按钮'));
      await humanTap(find.text('取消操作'));
      await humanTap(find.byIcon(Icons.refresh_rounded));
      await humanTap(find.byType(BackButton));
      await humanTap(find.text('直接触控'));
      await humanTap(find.text('菜单短按'));
      expect(<int>[
        filledCount,
        tonalCount,
        outlinedCount,
        textCount,
        iconCount,
        backCount,
        directTapCount,
        menuShortTapCount,
      ], everyElement(1));

      double buttonMaxScale(Finder target) {
        final transforms = tester.widgetList<Transform>(
          find.ancestor(of: target, matching: find.byType(Transform)),
        );
        var maxScale = 1.0;
        for (final t in transforms) {
          final s = t.transform.getMaxScaleOnAxis();
          if (s > maxScale) maxScale = s;
        }
        return maxScale;
      }

      // 设置页最小更新间隔加减号（无边框加减号、无阴影、位于可滚动容器内）：按住滑动取消按压态且不触发步进。
      final settingsModel = buildModel();
      await settingsModel.setAutoRefresh(true);
      final beforeInterval = settingsModel.autoRefreshIntervalMinutes;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: SettingsPage(model: settingsModel, reminders: null),
        ),
      );
      await tester.pumpAndSettle();

      final minusBtn = find.widgetWithIcon(
        TactileIconButton,
        Icons.remove_rounded,
      );
      final minusDecor = tester.widget<DecoratedBox>(
        find
            .descendant(of: minusBtn, matching: find.byType(DecoratedBox))
            .first,
      );
      expect((minusDecor.decoration as BoxDecoration).boxShadow, isNull);

      final addBtn = find.byIcon(Icons.add_rounded);
      final addDownPos = tester.getCenter(addBtn);
      final addGesture = await tester.startGesture(addDownPos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(buttonMaxScale(addBtn), greaterThan(1.05));

      await addGesture.moveTo(addDownPos + const Offset(-28, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(buttonMaxScale(addBtn), lessThan(1.03));
      await addGesture.up();
      await tester.pumpAndSettle();
      expect(settingsModel.autoRefreshIntervalMinutes, beforeInterval);

      // 固定位置按钮：滑走时仍保持原有按住放大效果。
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            appBar: AppBar(
              actions: <Widget>[
                TactileIconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  onPressed: () {},
                ),
              ],
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final fixedBtn = find.byIcon(Icons.refresh_rounded);
      final fixedDownPos = tester.getCenter(fixedBtn);
      final fixedGesture = await tester.startGesture(fixedDownPos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(buttonMaxScale(fixedBtn), greaterThan(1.05));

      await fixedGesture.moveTo(fixedDownPos + const Offset(-28, 0));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(buttonMaxScale(fixedBtn), greaterThan(1.05));
      await fixedGesture.up();
      await tester.pumpAndSettle();
      expect(buttonMaxScale(fixedBtn), closeTo(1.0, 0.005));
    });

    testWidgets('长按触发按钮展开菜单：不弹 Tooltip、初始命中项单次震动、按住及滑出边界保持放大与橡皮筋跟随', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var hapticCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              hapticCount++;
            }
            return null;
          });

      try {
        String? picked;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: Scaffold(
              appBar: AppBar(
                actions: <Widget>[
                  Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: TactileSurfaceButton(
                      minSize: const Size(36, 36),
                      tooltip: '更多',
                      onMenuOpen: (anchorCtx, dragPointer) {
                        showAppMenu<String>(
                          context: anchorCtx,
                          dragPointer: dragPointer,
                          items: const <AppMenuItem<String>>[
                            AppMenuItem<String>(value: 'a', label: '选项甲'),
                            AppMenuItem<String>(value: 'b', label: '选项乙'),
                            AppMenuItem<String>(value: 'c', label: '选项丙'),
                          ],
                          onSelected: (v) => picked = v,
                        );
                      },
                      child: const SizedBox(
                        width: 36,
                        height: 36,
                        child: Icon(Icons.more_horiz_rounded),
                      ),
                    ),
                  ),
                ],
              ),
              body: const SizedBox.expand(),
            ),
          ),
        );
        await tester.pumpAndSettle();

        (double scale, Offset translation) menuTransformState() {
          final box = tester.renderObject<RenderMenuMorphBox>(
            find.byElementPredicate(
              (e) => e.renderObject is RenderMenuMorphBox,
            ),
          );
          return (box.contentScale, box.currentRubberOffset);
        }

        final trigger = find.byIcon(Icons.more_horiz_rounded);
        final downPos = tester.getCenter(trigger);
        final gesture = await tester.startGesture(downPos);

        // 等待长按触发：此时应立刻且仅有 1 次震动。
        await tester.pump(const Duration(milliseconds: 220));
        expect(hapticCount, 1);

        // 展开前几帧内原地微抖动，不应误判到底部选项「选项丙」或二次震动。
        await gesture.moveTo(downPos + const Offset(0, 2));
        await tester.pump(const Duration(milliseconds: 16));
        await gesture.moveTo(downPos + const Offset(0, 4));
        await tester.pump(const Duration(milliseconds: 16));
        expect(hapticCount, 1);
        expect(
          tester.widget<Text>(find.text('选项甲')).style?.fontWeight,
          FontWeight.w600,
        );
        expect(
          tester.widget<Text>(find.text('选项丙')).style?.fontWeight,
          isNot(FontWeight.w600),
        );

        // 超过 Tooltip 默认长按阈值后仍不弹出「更多」提示，且保持在「选项甲」。
        await tester.pump(const Duration(milliseconds: 520));
        expect(find.text('更多'), findsNothing);
        expect(hapticCount, 1);
        expect(menuTransformState().$1, inInclusiveRange(1.03, 1.06));

        // 滑出菜单边界外仍维持放大效果并带有橡皮筋跟随偏移。
        await gesture.moveTo(const Offset(24, 420));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 180));
        final outsideState = menuTransformState();
        expect(outsideState.$1, inInclusiveRange(1.03, 1.06));
        expect(outsideState.$2.distance, greaterThan(0.5));

        // 滑回「选项乙」应增加 1 次切换震动，再滑到「选项丙」松手提交 'c'。
        await gesture.moveTo(tester.getCenter(find.text('选项乙')));
        await tester.pump(const Duration(milliseconds: 20));
        expect(hapticCount, 2);

        await gesture.moveTo(tester.getCenter(find.text('选项丙')));
        await tester.pump(const Duration(milliseconds: 20));
        expect(hapticCount, 3);

        await gesture.up();
        await tester.pumpAndSettle();
        expect(picked, 'c');
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('卡片列表右侧操作按钮（作息表更多菜单、调课/教务地址/代理删除）点击与长按均不穿透触发外层卡片操作', (
      tester,
    ) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      var hapticCount = 0;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'HapticFeedback.vibrate') {
              hapticCount++;
            }
            return null;
          });

      try {
        // 1. 作息时间表列表卡片右侧更多按钮：短按与长按均只展开菜单而不跳转编辑页。
        final model = buildModel();
        model.hydrateForTest(schedule: sparseSchedule(), week: 1);
        await model.upsertTimetable(
          Timetable(
            id: 'extra-winter',
            name: '冬季作息',
            effectiveFrom: DateTime(2026, 10, 1),
            sections: model.activeTimetable!.sections,
          ),
        );

        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: TimetableListPage(model: model),
          ),
        );
        await tester.pumpAndSettle();

        final moreButtons = find.byIcon(Icons.more_vert_rounded);
        await tester.tap(moreButtons.last);
        await tester.pumpAndSettle();
        expect(find.byType(TimetableEditPage), findsNothing);
        await tester.tap(find.text('删除'));
        await tester.pumpAndSettle();
        expect(find.text('删除作息表'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, '取消'));
        await tester.pumpAndSettle();

        hapticCount = 0;
        final hold = await tester.startGesture(
          tester.getCenter(moreButtons.last),
        );
        await tester.pump(const Duration(milliseconds: 220));
        await tester.pump(const Duration(milliseconds: 520));
        expect(find.byType(TimetableEditPage), findsNothing);
        expect(find.text('更多'), findsNothing);
        expect(hapticCount, 1);
        await hold.up();
        await tester.pumpAndSettle();
        expect(find.text('删除作息表'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, '取消'));
        await tester.pumpAndSettle();

        // 2. 调课页右侧删除按钮直接删除，不弹出修改底部弹窗。
        final rescheduleModel = buildModel();
        rescheduleModel.hydrateForTest(schedule: sparseSchedule(), week: 1);
        await rescheduleModel.addReschedule(
          fromMonth: 10,
          fromDay: 1,
          toMonth: 10,
          toDay: 8,
        );
        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: ReschedulePage(model: rescheduleModel),
          ),
        );
        await tester.pumpAndSettle();

        await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
        await tester.pumpAndSettle();
        expect(rescheduleModel.reschedules, isEmpty);
        expect(find.byType(BottomSheet), findsNothing);

        // 3. 教务地址页内置默认地址无删除按钮；自定义地址右侧删除按钮只弹「删除教务地址」，不触发「切换教务地址」。
        final schoolModel = buildModel();
        await schoolModel.addSchool('https://jw2.example.edu.cn/jwglxt');
        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: SchoolAddressPage(model: schoolModel),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byIcon(Icons.delete_outline_rounded), findsOneWidget);
        await tester.tap(find.byIcon(Icons.delete_outline_rounded).first);
        await tester.pumpAndSettle();
        expect(find.text('删除教务地址'), findsOneWidget);
        expect(find.text('切换教务地址'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, '取消'));
        await tester.pumpAndSettle();

        // 4. 更新代理页自定义节点右侧删除按钮只弹「删除代理」，不切换所选代理。
        final proxyModel = buildModel();
        await proxyModel.addCustomUpdateProxy(
          'https://custom-proxy.example.com/',
        );
        final beforeProxy = proxyModel.selectedUpdateProxy;
        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: UpdateProxyPage(model: proxyModel),
          ),
        );
        await tester.pumpAndSettle();

        final deleteProxyBtn = find.byIcon(Icons.delete_outline_rounded).first;
        await tester.ensureVisible(deleteProxyBtn);
        await tester.pumpAndSettle();
        await tester.tap(deleteProxyBtn);
        await tester.pumpAndSettle();
        expect(find.text('删除代理'), findsOneWidget);
        expect(proxyModel.selectedUpdateProxy, beforeProxy);
      } finally {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('CourseBlock 布局预算 LRU 缓存命中同一规格课程块，且使用 RepaintBoundary 隔离点击重绘', (
      tester,
    ) async {
      CourseBlock.clearBlockPlanCacheForTest();
      final baseline = CourseBlock.debugBlockPlanSolveCountForTest;
      const entry = ScheduleEntry(
        id: 'c1',
        name: '高等数学（一）',
        teacher: '李四',
        location: 'M1-101',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: <int>[1, 2],
      );

      Widget buildCell(ScheduleEntry e, Key key) => wrap(
        Center(
          child: SizedBox(
            width: 68,
            height: 112,
            child: CourseBlock(key: key, entry: e, onTap: () {}),
          ),
        ),
      );

      await tester.pumpWidget(buildCell(entry, const ValueKey<int>(1)));
      expect(CourseBlock.debugBlockPlanSolveCountForTest, baseline + 1);
      expect(
        find.descendant(
          of: find.byType(CourseBlock),
          matching: find.byType(RepaintBoundary),
        ),
        findsOneWidget,
      );

      const sameLayoutEntry = ScheduleEntry(
        id: 'c2',
        name: '高等数学（一）',
        teacher: '李四',
        location: 'M1-101',
        day: 2,
        startPeriod: 3,
        endPeriod: 4,
        weeks: <int>[3],
      );
      await tester.pumpWidget(
        buildCell(sameLayoutEntry, const ValueKey<int>(2)),
      );
      expect(CourseBlock.debugBlockPlanSolveCountForTest, baseline + 1);

      const changedEntry = ScheduleEntry(
        id: 'c3',
        name: '线性代数',
        teacher: '李四',
        location: 'M1-101',
        day: 2,
        startPeriod: 3,
        endPeriod: 4,
        weeks: <int>[3],
      );
      await tester.pumpWidget(buildCell(changedEntry, const ValueKey<int>(3)));
      expect(CourseBlock.debugBlockPlanSolveCountForTest, baseline + 2);
    });

    testWidgets('课程详情弹窗改用单层 SelectionArea 与纯 Text：仅字段值可选中复制，大量扩展字段可正常滚动与长按选字', (
      tester,
    ) async {
      final longDetails = <ScheduleDetail>[
        for (var i = 1; i <= 20; i++)
          ScheduleDetail(id: 'ext-$i', label: '扩展项$i', value: '字段值内容-$i'),
      ];
      final schedule = Schedule(
        termId: '2026-2027-1',
        maxWeeks: 18,
        entries: <ScheduleEntry>[
          ScheduleEntry(
            id: 'early',
            name: '期初课',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: const <int>[1, 2],
            teacher: '张老师',
            location: 'A101',
            details: longDetails,
          ),
        ],
      );
      final model = buildModel();
      model.hydrateForTest(schedule: schedule, week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(CourseBlock).first);
      await tester.pumpAndSettle();

      final sheet = find.byType(BottomSheet);
      expect(
        find.descendant(of: sheet, matching: find.byType(SelectableText)),
        findsNothing,
      );
      expect(
        find.descendant(of: sheet, matching: find.byType(SelectionArea)),
        findsOneWidget,
      );

      final headerTitle = find.descendant(
        of: sheet,
        matching: find.text('期初课'),
      );
      final weekLabel = find.descendant(of: sheet, matching: find.text('周次'));
      final weekValue = find.descendant(
        of: sheet,
        matching: find.text('1-2 周'),
      );

      SelectionContainer nearestSelectionContainer(Finder target) => tester
          .widgetList<SelectionContainer>(
            find.ancestor(
              of: target,
              matching: find.byType(SelectionContainer),
            ),
          )
          .first;

      expect(nearestSelectionContainer(headerTitle).registrar, isNull);
      expect(nearestSelectionContainer(weekLabel).registrar, isNull);
      expect(nearestSelectionContainer(weekValue).registrar, isNotNull);

      String? copiedText;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method == 'Clipboard.setData') {
            copiedText =
                (call.arguments as Map<dynamic, dynamic>)['text'] as String?;
          }
          return null;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );

      await tester.longPress(weekValue);
      await tester.pumpAndSettle();

      final selectableRegion = tester.state<SelectableRegionState>(
        find.descendant(of: sheet, matching: find.byType(SelectableRegion)),
      );
      selectableRegion.selectAll(SelectionChangedCause.toolbar);
      await tester.pump();
      Actions.invoke(weekValue.evaluate().first, CopySelectionTextIntent.copy);
      await tester.pump();

      expect(copiedText, contains('1-2 周'));
      expect(copiedText, contains('张老师'));
      expect(copiedText, isNot(contains('期初课')));
      expect(copiedText, isNot(contains('周次')));

      final scrollView = find.descendant(
        of: sheet,
        matching: find.byType(SingleChildScrollView),
      );
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: scrollView, matching: find.byType(Scrollable)),
      );
      expect(scrollable.position.maxScrollExtent, greaterThan(0));

      await tester.drag(scrollView, const Offset(0, -600));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('字段值内容-20'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('字段值内容-20'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    testWidgets('锚定菜单完成测量后退出 IntrinsicWidth，圆形与宽胶囊触发器共享开合变形逻辑且无缩小残影', (
      tester,
    ) async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: Schedule(
          termId: '2026-2027-1',
          maxWeeks: 20,
          entries: sparseSchedule().entries,
        ),
        week: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: SchedulePage(model: model),
        ),
      );
      await tester.pumpAndSettle();

      final circleIcon = find.byIcon(Icons.more_horiz_rounded);
      final circleTriggerFinder = find.ancestor(
        of: circleIcon,
        matching: find.byType(TactileSurfaceButton),
      );
      final circleTriggerRect = tester.getRect(circleTriggerFinder);

      await tester.tap(circleIcon);
      await tester.pump();
      await tester.pump();

      final circleMorphBox = tester.renderObject<RenderMenuMorphBox>(
        find.byElementPredicate((e) => e.renderObject is RenderMenuMorphBox),
      );
      expect(circleMorphBox.morphRadius, closeTo(18.0, 0.3));
      expect(circleMorphBox.contentScale, greaterThanOrEqualTo(0.60));

      double minTriggerScale = 2.0;
      void recordTriggerScale() {
        final transforms = tester.widgetList<Transform>(
          find.descendant(
            of: circleTriggerFinder,
            matching: find.byType(Transform),
          ),
        );
        for (final t in transforms) {
          final sx = t.transform.storage[0];
          if (sx < minTriggerScale) minTriggerScale = sx;
        }
      }

      await tester.pump(const Duration(milliseconds: 36));
      recordTriggerScale();
      final midOpenRect = circleMorphBox.morphRect;
      expect(midOpenRect.width, greaterThan(circleTriggerRect.width));
      expect(midOpenRect.height, greaterThan(circleTriggerRect.height));

      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Overlay),
          matching: find.byType(IntrinsicWidth),
        ),
        findsNothing,
      );
      final settledRect = circleMorphBox.morphRect;
      expect(circleMorphBox.morphRadius, closeTo(20.0, 0.01));
      expect(circleMorphBox.isSettled, isTrue);
      expect(circleMorphBox.isClipping, isFalse);
      expect(circleMorphBox.shadowAlpha, greaterThan(0));

      await tester.tapAt(const Offset(16, 200));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 56));
      recordTriggerScale();
      expect(circleMorphBox.morphRect.width, lessThan(settledRect.width));
      expect(minTriggerScale, greaterThanOrEqualTo(1.0 - 1e-6));
      await tester.pumpAndSettle();

      // 宽胶囊（第 1 周）触发器：测量后无 IntrinsicWidth，滚动列表保留裁剪。
      await tester.tap(find.text('第 1 周'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(Overlay),
          matching: find.byType(IntrinsicWidth),
        ),
        findsNothing,
      );
      final weekMorphBox = tester.renderObject<RenderMenuMorphBox>(
        find.byElementPredicate((e) => e.renderObject is RenderMenuMorphBox),
      );
      expect(weekMorphBox.alignment, Alignment.topCenter);
      expect(weekMorphBox.isSettled, isTrue);
      expect(weekMorphBox.isClipping, isTrue);
    });

    testWidgets('展开中途直接点击视觉缩放后的菜单项仍精准命中该项，且收起中途同按钮重开连续接管速度与几何', (tester) async {
      String? picked;
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            appBar: AppBar(
              actions: <Widget>[
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: TactileSurfaceButton(
                    minSize: const Size(36, 36),
                    onMenuOpen: (anchorCtx, dragPointer) {
                      showAppMenu<String>(
                        context: anchorCtx,
                        dragPointer: dragPointer,
                        items: const <AppMenuItem<String>>[
                          AppMenuItem<String>(value: 'a', label: '选项甲'),
                          AppMenuItem<String>(value: 'b', label: '选项乙'),
                          AppMenuItem<String>(value: 'c', label: '选项丙'),
                          AppMenuItem<String>(value: 'd', label: '选项丁'),
                        ],
                        onSelected: (v) => picked = v,
                      );
                    },
                    child: const SizedBox(
                      width: 36,
                      height: 36,
                      child: Icon(Icons.more_horiz_rounded),
                    ),
                  ),
                ),
              ],
            ),
            body: const SizedBox.expand(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final triggerFinder = find.byIcon(Icons.more_horiz_rounded);

      await tester.tap(triggerFinder);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 52));
      final morphOpen = tester.renderObject<RenderMenuMorphBox>(
        find.byElementPredicate((e) => e.renderObject is RenderMenuMorphBox),
      );
      expect(morphOpen.contentScale, lessThan(0.95));
      await tester.tapAt(tester.getCenter(find.text('选项丙')));
      await tester.pumpAndSettle();
      expect(picked, 'c');

      picked = null;
      await tester.tap(triggerFinder);
      await tester.pumpAndSettle();

      await tester.tapAt(const Offset(16, 220));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 48));
      final closingMorph = tester.renderObject<RenderMenuMorphBox>(
        find.byElementPredicate((e) => e.renderObject is RenderMenuMorphBox),
      );
      final heightBeforeReopen = closingMorph.morphRect.height;
      expect(heightBeforeReopen, greaterThan(50.0));

      await tester.tap(triggerFinder);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final reopenedMorph = tester.renderObject<RenderMenuMorphBox>(
        find.byElementPredicate((e) => e.renderObject is RenderMenuMorphBox),
      );
      expect(
        reopenedMorph.morphRect.height,
        greaterThan(heightBeforeReopen * 0.65),
      );
      await tester.pumpAndSettle();
      expect(reopenedMorph.isSettled, isTrue);

      await tester.tap(find.text('选项乙'));
      await tester.pumpAndSettle();
      expect(picked, 'b');
      expect(tester.takeException(), isNull);
    });

    testWidgets('TactileAppBar 解除硬裁剪并按“静态标题 → 全部阴影 → 纯白融合 → 按钮前景”四层顺序绘制', (
      tester,
    ) async {
      // 1. 验证二级页顶栏：返回按钮、静态标题与右侧双按钮严格分四层绘制。
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            appBar: TactileAppBar(
              leading: TactileBackButton(onPressed: () {}),
              title: const Text('测试页面标题'),
              actions: <Widget>[
                TactileIconButton(
                  icon: const Icon(Icons.speed_rounded),
                  onPressed: () {},
                ),
                Padding(
                  padding: const EdgeInsets.only(left: 6, right: 10),
                  child: TactileIconButton(
                    icon: const Icon(Icons.add_rounded),
                    onPressed: () {},
                  ),
                ),
              ],
            ),
            body: const SizedBox.shrink(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        tester.widget<AppBar>(find.byType(AppBar)).clipBehavior,
        Clip.none,
      );

      final scopeRender = tester.renderObject(find.byType(TactileSurfaceScope));
      final secondaryCanvas = _RecordingPaintCanvas();
      final secondaryCtx = _RecordingPaintingContext(
        ContainerLayer(),
        scopeRender.paintBounds,
        secondaryCanvas,
      );
      final prevDisableShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        scopeRender.paint(secondaryCtx, Offset.zero);
      } finally {
        debugDisableShadows = prevDisableShadows;
      }

      final ops = secondaryCanvas.ops;
      // 第 1 层：静态标题文本最先绘制（位于所有阴影与白底之下）
      final titleIndex = ops.indexOf('paragraph');
      final firstShadowIndex = ops.indexOf('shadow');
      final lastShadowIndex = ops.lastIndexOf('shadow');
      final firstSurfaceIndex = ops.indexOf('surface');
      final lastSurfaceIndex = ops.lastIndexOf('surface');
      final lastParagraphIndex = ops.lastIndexOf('paragraph');

      expect(titleIndex, greaterThanOrEqualTo(0));
      expect(firstShadowIndex, greaterThan(titleIndex));
      expect(ops.where((e) => e == 'shadow').length, 3);
      expect(ops.where((e) => e == 'surface').length, 3);
      expect(firstSurfaceIndex, greaterThan(lastShadowIndex));
      expect(lastParagraphIndex, greaterThan(lastSurfaceIndex));
      expect(
        ops
            .sublist(firstShadowIndex, lastShadowIndex + 1)
            .every((e) => e == 'shadow'),
        isTrue,
      );
      expect(
        ops
            .sublist(firstSurfaceIndex, lastSurfaceIndex + 1)
            .every((e) => e == 'surface'),
        isTrue,
      );

      // 2. 验证课表页顶栏：[←][第 N 周][→] 与 [刷新][更多] 全部纳入同一融合组且支持按压拖拽重叠
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pumpAndSettle();

      expect(
        tester.widget<AppBar>(find.byType(AppBar)).clipBehavior,
        Clip.none,
      );
      final scheduleScope = tester.renderObject(
        find.byType(TactileSurfaceScope),
      );
      final scheduleCanvas = _RecordingPaintCanvas();
      final scheduleCtx = _RecordingPaintingContext(
        ContainerLayer(),
        scheduleScope.paintBounds,
        scheduleCanvas,
      );
      final prevScheduleShadows = debugDisableShadows;
      debugDisableShadows = false;
      try {
        scheduleScope.paint(scheduleCtx, Offset.zero);
      } finally {
        debugDisableShadows = prevScheduleShadows;
      }

      final sOps = scheduleCanvas.ops;
      expect(sOps.where((e) => e == 'shadow').length, 5);
      expect(sOps.where((e) => e == 'surface').length, 5);
      expect(sOps.lastIndexOf('shadow'), lessThan(sOps.indexOf('surface')));
      expect(
        sOps.lastIndexOf('surface'),
        lessThan(sOps.lastIndexOf('paragraph')),
      );

      // 按住「下一周」向右拉向右侧操作区，再分别开合「第 1 周」与「更多」菜单，
      // 恢复后 5 个槽位仍完整合绘且菜单按钮前景坐标不向左上角偏移。
      final nextBtn = find.widgetWithIcon(
        TactileIconButton,
        Icons.chevron_right_rounded,
      );
      final gesture = await tester.startGesture(tester.getCenter(nextBtn));
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.moveBy(const Offset(18, 8));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tester.tap(find.text('第 1 周'));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);
      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();

      scheduleCanvas.ops.clear();
      scheduleCanvas.paragraphOrigins.clear();
      debugDisableShadows = false;
      try {
        scheduleScope.paint(scheduleCtx, Offset.zero);
      } finally {
        debugDisableShadows = prevScheduleShadows;
      }
      expect(scheduleCanvas.ops.where((e) => e == 'shadow').length, 5);
      expect(scheduleCanvas.ops.where((e) => e == 'surface').length, 5);
      expect(scheduleCanvas.paragraphOrigins, isNotEmpty);
      expect(
        scheduleCanvas.paragraphOrigins.every((p) => p.dx > 0 && p.dy > 0),
        isTrue,
      );
      expect(scheduleCanvas.paragraphOrigins.last.dx, greaterThan(700));
      expect(tester.takeException(), isNull);
    });
  });

  group('文本可选中统一与底部弹窗公用容器', () {
    testWidgets('调试页概览与原始课表均改用单层 SelectionArea，不再使用 SelectableText', (
      tester,
    ) async {
      final backend = FakeBackend()
        ..lastScheduleRawBody = '{"kbList":[{"kcmc":"高等数学"}]}'
        ..lastScheduleRows = <Map<String, dynamic>>[
          <String, dynamic>{
            'kcmc': '高等数学',
            'xqj': '1',
            'jcs': '1-2',
            'zcd': '1-16周',
          },
        ];
      final model = buildModel(backend: backend);
      await model.signIn('20240001', 'pw');
      await tester.pumpWidget(wrap(DebugPage(model: model)));

      expect(find.byType(SelectableText), findsNothing);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('教务地址'),
          matching: find.byType(SelectionContainer),
        ),
        findsWidgets,
      );

      await tester.tap(find.widgetWithText(Tab, '原始课表'));
      await tester.pumpAndSettle();

      expect(find.byType(SelectableText), findsNothing);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget);

      // 展开原始行，确认内部的 JSON Text 也不使用 SelectableText
      await tester.tap(find.text('高等数学'));
      await tester.pumpAndSettle();
      expect(find.byType(SelectableText), findsNothing);
      expect(find.textContaining('"kcmc": "高等数学"'), findsOneWidget);
    });

    testWidgets('关于页开源协议页面使用单层 SelectionArea + Text，不再使用 SelectableText', (
      tester,
    ) async {
      final model = buildModel();
      await tester.pumpWidget(wrap(AboutPage(model: model)));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -400));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('开源协议'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('开源协议'));
      await tester.pumpAndSettle();

      expect(find.byType(LicenseTextPage), findsOneWidget);
      expect(find.byType(SelectableText), findsNothing);
      expect(find.byType(SelectionArea), findsOneWidget);
    });

    testWidgets('showAppModalBottomSheet 与 ScrollableBottomSheetFrame 统一弹窗结构', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  TextButton(
                    onPressed: () => showAppModalBottomSheet<void>(
                      context: context,
                      builder: (_) => ScrollableBottomSheetFrame(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < 40; i++)
                              ListTile(title: Text('弹窗条目 $i')),
                          ],
                        ),
                      ),
                    ),
                    child: const Text('打开弹窗'),
                  ),
                  TextButton(
                    onPressed: () =>
                        showTimeWheel(context, initialMinutes: 8 * 60),
                    child: const Text('打开时间轮'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开弹窗'));
      await tester.pumpAndSettle();

      expect(find.byType(ScrollableBottomSheetFrame), findsOneWidget);
      expect(find.byType(SingleChildScrollView), findsOneWidget);
      final frameSize = tester.getSize(find.byType(ScrollableBottomSheetFrame));
      final screenHeight = tester.getSize(find.byType(MaterialApp)).height;
      expect(frameSize.height, lessThanOrEqualTo(screenHeight * 0.8 + 0.1));

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();

      await tester.tap(find.text('打开时间轮'));
      await tester.pumpAndSettle();
      expect(find.text('选择时间'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}

class _DisposeNotifyHelper extends StatefulWidget {
  const _DisposeNotifyHelper({required this.onDispose});
  final VoidCallback onDispose;

  @override
  State<_DisposeNotifyHelper> createState() => _DisposeNotifyHelperState();
}

class _DisposeNotifyHelperState extends State<_DisposeNotifyHelper> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class _RecordingPaintCanvas extends Fake implements ui.Canvas {
  _RecordingPaintCanvas() : _delegate = ui.Canvas(ui.PictureRecorder());

  final ui.Canvas _delegate;
  final List<String> ops = <String>[];
  final List<Offset> paragraphOrigins = <Offset>[];
  final List<Matrix4> _matrixStack = <Matrix4>[Matrix4.identity()];

  @override
  void save() {
    _matrixStack.add(_matrixStack.last.clone());
    _delegate.save();
  }

  @override
  void saveLayer(Rect? bounds, Paint paint) {
    _matrixStack.add(_matrixStack.last.clone());
    _delegate.saveLayer(bounds, paint);
  }

  @override
  void restore() {
    if (_matrixStack.length > 1) _matrixStack.removeLast();
    _delegate.restore();
  }

  @override
  int getSaveCount() => _delegate.getSaveCount();

  @override
  void translate(double dx, double dy) {
    _matrixStack.last.multiply(Matrix4.translationValues(dx, dy, 0.0));
    _delegate.translate(dx, dy);
  }

  @override
  void scale(double sx, [double? sy]) {
    _matrixStack.last.multiply(Matrix4.diagonal3Values(sx, sy ?? sx, 1.0));
    _delegate.scale(sx, sy);
  }

  @override
  void transform(Float64List matrix4) {
    _matrixStack.last.multiply(Matrix4.fromFloat64List(matrix4));
    _delegate.transform(matrix4);
  }

  @override
  void clipRect(
    Rect rect, {
    ui.ClipOp clipOp = ui.ClipOp.intersect,
    bool doAntiAlias = true,
  }) => _delegate.clipRect(rect, clipOp: clipOp, doAntiAlias: doAntiAlias);

  @override
  void clipRRect(RRect rrect, {bool doAntiAlias = true}) =>
      _delegate.clipRRect(rrect, doAntiAlias: doAntiAlias);

  @override
  void drawColor(Color color, BlendMode blendMode) =>
      _delegate.drawColor(color, blendMode);

  @override
  void drawPaint(Paint paint) => _delegate.drawPaint(paint);

  @override
  void drawRect(Rect rect, Paint paint) => _delegate.drawRect(rect, paint);

  @override
  void drawPath(Path path, Paint paint) => _delegate.drawPath(path, paint);

  @override
  void drawRRect(RRect rrect, Paint paint) {
    if (paint.maskFilter != null) {
      ops.add('shadow');
    } else if (paint.color == Colors.white) {
      ops.add('surface');
    }
    _delegate.drawRRect(rrect, paint);
  }

  @override
  void drawParagraph(ui.Paragraph paragraph, Offset offset) {
    ops.add('paragraph');
    paragraphOrigins.add(MatrixUtils.transformPoint(_matrixStack.last, offset));
    _delegate.drawParagraph(paragraph, offset);
  }
}

class _RecordingPaintingContext extends PaintingContext {
  _RecordingPaintingContext(
    super.containerLayer,
    super.estimatedBounds,
    this._canvas,
  );

  final _RecordingPaintCanvas _canvas;

  @override
  ui.Canvas get canvas => _canvas;

  @override
  PaintingContext createChildContext(ContainerLayer childLayer, Rect bounds) =>
      _RecordingPaintingContext(childLayer, bounds, _canvas);
}
