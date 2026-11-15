import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/changelog_page.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/tactile_button.dart';

void main() {
  group('二级页平滑转场与交互测试', () {
    setUp(() {
      ChangelogPage.resetCache();
      rootBundle.evict('CHANGELOG.md');
    });

    tearDown(() {
      ChangelogPage.resetCache();
      rootBundle.evict('CHANGELOG.md');
    });

    Widget buildTestApp({
      required Widget home,
      TargetPlatform platform = TargetPlatform.android,
    }) {
      return MaterialApp(
        theme: buildLightTheme().copyWith(platform: platform),
        scrollBehavior: AppScrollBehavior(),
        home: home,
      );
    }

    testWidgets('完整入场与完整退场连续全屏滑行、背层联动、收尾柔和减速且不使用离屏合成', (tester) async {
      const firstKey = ValueKey<String>('first-page');
      const secondKey = ValueKey<String>('second-page');

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            key: firstKey,
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => Scaffold(
                          key: secondKey,
                          appBar: AppBar(
                            leading: const TactileBackButton(),
                            title: const Text('二级页'),
                          ),
                          body: const Center(child: Text('内容')),
                        ),
                      ),
                    );
                  },
                  child: const Text('打开二级页'),
                ),
              ),
            ),
          ),
        ),
      );

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(tester.getTopLeft(find.byKey(firstKey)).dx, 0.0);

      await tester.tap(find.text('打开二级页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      final enterX0 = tester.getTopLeft(find.byKey(secondKey)).dx;
      expect(enterX0, greaterThan(width * 0.95));

      final enterPositions = <double>[enterX0];
      final firstExitPositions = <double>[
        tester.getTopLeft(find.byKey(firstKey)).dx,
      ];
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        if (i == 1) {
          expect(find.byType(SnapshotWidget), findsNothing);
          expect(
            find.ancestor(
              of: find.text('内容'),
              matching: find.byType(FadeTransition),
            ),
            findsNothing,
          );
          expect(
            find.ancestor(of: find.text('内容'), matching: find.byType(Opacity)),
            findsNothing,
          );
          expect(
            find.ancestor(
              of: find.text('内容'),
              matching: find.byType(SlideTransition),
            ),
            findsAtLeastNWidgets(1),
          );
        }
        enterPositions.add(tester.getTopLeft(find.byKey(secondKey)).dx);
        firstExitPositions.add(tester.getTopLeft(find.byKey(firstKey)).dx);
      }
      await tester.pumpAndSettle();

      expect(tester.getTopLeft(find.byKey(secondKey)).dx, 0.0);
      for (var i = 1; i < enterPositions.length; i++) {
        expect(enterPositions[i], lessThanOrEqualTo(enterPositions[i - 1]));
        expect(
          firstExitPositions[i],
          lessThanOrEqualTo(firstExitPositions[i - 1]),
        );
      }
      expect(firstExitPositions[3], lessThan(-10.0));

      final enterFirstStep = enterPositions[0] - enterPositions[1];
      final enterLastStep = enterPositions[5] - enterPositions[6];
      expect(enterFirstStep, greaterThan(enterLastStep * 2));

      await tester.tap(find.byType(BackButton));
      await tester.pump();

      final exitStartX = tester.getTopLeft(find.byKey(secondKey)).dx;
      expect(exitStartX, closeTo(0.0, 0.01));

      final exitPositions = <double>[exitStartX];
      final firstReturnPositions = <double>[
        tester.getTopLeft(find.byKey(firstKey)).dx,
      ];
      const stepMs = 40;
      for (var elapsed = stepMs; elapsed < 240; elapsed += stepMs) {
        await tester.pump(const Duration(milliseconds: stepMs));
        exitPositions.add(tester.getTopLeft(find.byKey(secondKey)).dx);
        firstReturnPositions.add(tester.getTopLeft(find.byKey(firstKey)).dx);
      }
      await tester.pump(const Duration(milliseconds: 35));
      final nearEndX = tester.getTopLeft(find.byKey(secondKey)).dx;
      expect(nearEndX, greaterThan(width * 0.96));

      for (var i = 1; i < exitPositions.length; i++) {
        expect(exitPositions[i], greaterThan(exitPositions[i - 1]));
        expect(
          firstReturnPositions[i],
          greaterThan(firstReturnPositions[i - 1]),
        );
      }

      final exitFirstStep = exitPositions[1] - exitPositions[0];
      final exitLastStep =
          exitPositions.last - exitPositions[exitPositions.length - 2];
      expect(exitFirstStep, greaterThan(exitLastStep * 2));

      await tester.pumpAndSettle();
      expect(find.byKey(secondKey), findsNothing);
      expect(tester.getTopLeft(find.byKey(firstKey)).dx, 0.0);
    });

    testWidgets('入场中途返回、同路由往返折返（forward -> reverse -> forward）及直接拖拽回退均平滑无跳变', (
      tester,
    ) async {
      const firstKey = ValueKey<String>('first-page');
      const secondKey = ValueKey<String>('second-page');
      late _ExposedControllerRoute<void> activeRoute;

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            key: firstKey,
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    activeRoute = _ExposedControllerRoute<void>(
                      builder: (_) => Scaffold(
                        key: secondKey,
                        appBar: AppBar(
                          leading: const TactileBackButton(),
                          title: const Text('可控二级页'),
                        ),
                        body: const SizedBox.expand(),
                      ),
                    );
                    Navigator.of(context).push(activeRoute);
                  },
                  child: const Text('推入可控页'),
                ),
              ),
            ),
          ),
        ),
      );

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      await tester.tap(find.text('推入可控页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));

      // 1. 半途逆转（forward -> reverse）且折返瞬间零跳变
      final dxBeforeReverse = tester.getTopLeft(find.byKey(secondKey)).dx;
      final firstDxBeforeReverse = tester.getTopLeft(find.byKey(firstKey)).dx;
      expect(dxBeforeReverse, greaterThan(20.0));
      expect(dxBeforeReverse, lessThan(width - 20.0));

      final ctrl = activeRoute.exposedController!;
      ctrl.reverse();
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(secondKey)).dx,
        closeTo(dxBeforeReverse, 0.01),
      );
      expect(
        tester.getTopLeft(find.byKey(firstKey)).dx,
        closeTo(firstDxBeforeReverse, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 50));

      final dxBeforeReforward = tester.getTopLeft(find.byKey(secondKey)).dx;
      final firstDxBeforeReforward = tester.getTopLeft(find.byKey(firstKey)).dx;
      expect(dxBeforeReforward, greaterThan(dxBeforeReverse));
      expect(dxBeforeReforward, lessThan(width));

      // 2. 退场半途再次转回入场（reverse -> forward）：折返点零跳变，且单调平滑归零
      ctrl.forward();
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(secondKey)).dx,
        closeTo(dxBeforeReforward, 0.01),
      );
      expect(
        tester.getTopLeft(find.byKey(firstKey)).dx,
        closeTo(firstDxBeforeReforward, 0.01),
      );

      var prevDx = tester.getTopLeft(find.byKey(secondKey)).dx;
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        final dx = tester.getTopLeft(find.byKey(secondKey)).dx;
        expect(dx, lessThanOrEqualTo(prevDx + 0.01));
        prevDx = dx;
      }
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(secondKey)).dx, 0.0);

      // 3. 完成状态直接向回拖拽（controller.value = 0.8 -> 0.6 -> 0.4 -> 0.2）
      final draggedXs = <double>[];
      for (final raw in <double>[0.8, 0.6, 0.4, 0.2]) {
        ctrl.value = raw;
        await tester.pump();
        draggedXs.add(tester.getTopLeft(find.byKey(secondKey)).dx);
      }
      for (var i = 1; i < draggedXs.length; i++) {
        expect(draggedXs[i], greaterThan(draggedXs[i - 1] + 5.0));
      }

      ctrl.forward();
      await tester.pumpAndSettle();
      expect(tester.getTopLeft(find.byKey(secondKey)).dx, 0.0);

      // 4. 退回首页后再测一次入场半途直接点击 BackButton 完整退场至屏外
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('推入可控页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      final midPopStart = tester.getTopLeft(find.byKey(secondKey)).dx;
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      expect(
        tester.getTopLeft(find.byKey(secondKey)).dx,
        closeTo(midPopStart, 0.01),
      );
      await tester.pump(const Duration(milliseconds: 32));
      expect(
        tester.getTopLeft(find.byKey(secondKey)).dx,
        greaterThan(midPopStart),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(secondKey), findsNothing);
      expect(tester.getTopLeft(find.byKey(firstKey)).dx, 0.0);
    });

    testWidgets('动画没播放完但是用户已经在新页面上操作：点击、滚动与连续进下一级均立即响应', (tester) async {
      var actionTapCount = 0;
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (pageContext) => Scaffold(
                          appBar: AppBar(
                            leading: const TactileBackButton(),
                            title: const Text('列表页'),
                          ),
                          body: ListView(
                            controller: scrollController,
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.all(16),
                                child: TactileActionButton(
                                  onPressed: () => actionTapCount++,
                                  label: const Text('立即操作'),
                                ),
                              ),
                              ListTile(
                                title: const Text('打开三级页'),
                                onTap: () {
                                  Navigator.of(pageContext).push(
                                    MaterialPageRoute<void>(
                                      builder: (_) => Scaffold(
                                        appBar: AppBar(
                                          leading: const TactileBackButton(),
                                          title: const Text('三级页'),
                                        ),
                                        body: const Center(child: Text('三级内容')),
                                      ),
                                    ),
                                  );
                                },
                              ),
                              for (var i = 0; i < 30; i++)
                                ListTile(title: Text('条目 $i')),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('进入列表页'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('进入列表页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));

      await tester.tap(find.text('立即操作'));
      await tester.pump();
      expect(actionTapCount, 1);

      expect(scrollController.offset, 0.0);
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pump();
      final offsetMidTransition = scrollController.offset;
      expect(offsetMidTransition, greaterThan(100.0));

      await tester.pumpAndSettle();
      expect(scrollController.offset, closeTo(offsetMidTransition, 0.5));

      scrollController.jumpTo(0);
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await tester.tap(find.text('进入列表页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      await tester.tap(find.text('打开三级页'));
      await tester.pumpAndSettle();
      expect(find.text('三级内容'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('列表页'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('进入列表页'), findsOneWidget);
    });

    testWidgets('ChangelogPage 入场期间可滚动、快进快退无异常且退出动画期间停止后台批次追加', (tester) async {
      ChangelogPage.resetCache();
      addTearDown(ChangelogPage.resetCache);

      final manyReleases = <ReleaseLog>[
        for (var v = 12; v >= 1; v--)
          ReleaseLog(
            version: '$v.0.0',
            date: '2026-11-${v.toString().padLeft(2, '0')}',
            description: '版本 **$v** 更新亮点说明，用于验证转场与分段加载交互。\n包含多项体验与性能优化改进。',
            sections: const <LogSection>[
              LogSection(
                title: '优化',
                items: <String>[
                  '性能优化条目一：全宽水平位移与连续双向缓动曲线',
                  '性能优化条目二：去除离屏透明缓冲与整页纹理快照',
                  '性能优化条目三：入场期间允许即时点击、拖拽与列表滚动',
                  '性能优化条目四：入场未完成时中途返回无缝接续退场',
                ],
              ),
              LogSection(
                title: '修复',
                items: <String>[
                  '修复更新日志页在退出动画期间仍调度增量解析的问题',
                  '修复首页作为根路由未参与背层联动视差的问题',
                ],
              ),
            ],
          ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ChangelogPage(initialReleases: manyReleases),
                          ),
                        );
                      },
                      child: const Text('打开模拟日志'),
                    ),
                    ElevatedButton(
                      onPressed: () => ChangelogPage.open(context),
                      child: const Text('打开真实日志'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // 1. 冷打开真实 CHANGELOG.md，在入场未结束时直接返回
      await tester.tap(find.text('打开真实日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      expect(find.text('更新日志'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('打开模拟日志'), findsOneWidget);

      // 2. 入场期间只渲染首批 2 条，但允许用户直接滑动且不回跳
      await tester.tap(find.text('打开模拟日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));

      expect(find.text('v12.0.0'), findsOneWidget);
      expect(find.text('v11.0.0'), findsOneWidget);
      expect(find.text('v10.0.0'), findsNothing);

      final listFinder = find.byType(ListView);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: listFinder, matching: find.byType(Scrollable)),
      );
      await tester.drag(listFinder, const Offset(0, -140));
      await tester.pump();
      final offsetDuringEnter = scrollable.position.pixels;
      expect(offsetDuringEnter, greaterThan(80.0));

      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, closeTo(offsetDuringEnter, 1.0));
      expect(find.byType(CircularProgressIndicator), findsNothing);

      // 返回上一页应完整滑出屏外并顺利销毁
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final changelogScaffold = find.ancestor(
        of: find.text('更新日志'),
        matching: find.byType(Scaffold),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 225));
      expect(
        tester.getTopLeft(changelogScaffold).dx,
        greaterThan(width * 0.95),
      );
      await tester.pumpAndSettle();
      expect(find.text('更新日志'), findsNothing);

      // 3. 等入场刚好完成后立即点击返回，验证退出期间不会继续后台追加远端批次
      await tester.tap(find.text('打开模拟日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 265));
      expect(find.text('v12.0.0'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 35));
        expect(find.text('v1.0.0'), findsNothing);
      }
      await tester.pumpAndSettle();
      expect(find.text('更新日志'), findsNothing);
    });

    testWidgets('ChangelogPage 首屏未满屏下拉立即追加与冷打开中途取消返回（reverse -> forward）正常加载', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final shortManyReleases = <ReleaseLog>[
        for (var v = 10; v >= 1; v--)
          ReleaseLog(
            version: '$v.0.0',
            date: '2026-11-${v.toString().padLeft(2, '0')}',
            description: '版本 **$v**',
            sections: const <LogSection>[
              LogSection(title: '优化', items: <String>['短条目']),
            ],
          ),
      ];
      late _ExposedControllerRoute<void> changelogRoute;

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ElevatedButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => ChangelogPage(
                              initialReleases: shortManyReleases,
                            ),
                          ),
                        );
                      },
                      child: const Text('打开短日志'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        changelogRoute = _ExposedControllerRoute<void>(
                          builder: (_) => const ChangelogPage(),
                        );
                        Navigator.of(context).push(changelogRoute);
                      },
                      child: const Text('冷打开日志'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      // 1. 高窗口下首屏未满屏，入场期间下拉过冲立即追加新批次
      await tester.tap(find.text('打开短日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));
      expect(find.text('v8.0.0'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pump();
      expect(find.text('v8.0.0'), findsOneWidget);
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // 2. 冷打开异步加载中触发取消返回（reverse -> forward）不会卡在转圈
      await tester.tap(find.text('冷打开日志'));
      await tester.pump();
      final ctrl = changelogRoute.exposedController!;
      ctrl.reverse();
      await tester.pump(const Duration(milliseconds: 20));
      ctrl.forward();
      await tester.pumpAndSettle();

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('1.5.0'), findsAtLeastNWidgets(1));
    });
  });
}

class _ExposedControllerRoute<T> extends MaterialPageRoute<T> {
  _ExposedControllerRoute({required super.builder});

  AnimationController? exposedController;

  @override
  AnimationController createAnimationController() {
    exposedController = super.createAnimationController();
    return exposedController!;
  }
}
