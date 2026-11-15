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

    testWidgets('转场不使用整页 SnapshotWidget 或整页 FadeTransition/Opacity 离屏合成', (
      tester,
    ) async {
      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => Scaffold(
                        appBar: AppBar(
                          leading: const TactileBackButton(),
                          title: const Text('二级页'),
                        ),
                        body: const Center(child: Text('内容')),
                      ),
                    ),
                  );
                },
                child: const Text('进入'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('进入'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

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

      await tester.pumpAndSettle();
    });

    testWidgets('完整入场与完整退场连续全屏滑行、背层联动且收尾柔和减速', (tester) async {
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
                          body: const SizedBox.expand(),
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

      // 发起入场：第 1 个 pump() 完成 Navigator/Overlay 挂载，随后第 1 帧 (1ms) 应紧贴右侧屏外起点
      await tester.tap(find.text('打开二级页'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));

      // 起点（~1ms）应接近右侧屏外 width（>95% 屏宽），不会像旧版那样突兀闪入 72%
      final enterX0 = tester.getTopLeft(find.byKey(secondKey)).dx;
      expect(enterX0, greaterThan(width * 0.95));

      final enterPositions = <double>[enterX0];
      final firstExitPositions = <double>[
        tester.getTopLeft(find.byKey(firstKey)).dx,
      ];
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        enterPositions.add(tester.getTopLeft(find.byKey(secondKey)).dx);
        firstExitPositions.add(tester.getTopLeft(find.byKey(firstKey)).dx);
      }
      await tester.pumpAndSettle();

      // 到达终点 0.0，且首页在过程期间同步左移视差
      expect(tester.getTopLeft(find.byKey(secondKey)).dx, 0.0);
      for (var i = 1; i < enterPositions.length; i++) {
        expect(enterPositions[i], lessThanOrEqualTo(enterPositions[i - 1]));
        expect(
          firstExitPositions[i],
          lessThanOrEqualTo(firstExitPositions[i - 1]),
        );
      }
      // 首页应实际参与了背层左移视差（中间帧为负偏移）
      expect(firstExitPositions[3], lessThan(-10.0));

      // 入场首段位移明显大于末段位移（快启缓收，不突然加速撞停）
      final enterFirstStep = enterPositions[0] - enterPositions[1];
      final enterLastStep = enterPositions[5] - enterPositions[6];
      expect(enterFirstStep, greaterThan(enterLastStep * 2));

      // 发起正常返回（点击返回按钮）
      await tester.tap(find.byType(BackButton));
      await tester.pump();

      final exitStartX = tester.getTopLeft(find.byKey(secondKey)).dx;
      expect(exitStartX, closeTo(0.0, 0.01));

      final exitPositions = <double>[exitStartX];
      final firstReturnPositions = <double>[
        tester.getTopLeft(find.byKey(firstKey)).dx,
      ];
      // reverseTransitionDuration = 240ms，逐帧采集至 230ms（即将退场前）
      const stepMs = 40;
      for (var elapsed = stepMs; elapsed < 240; elapsed += stepMs) {
        await tester.pump(const Duration(milliseconds: stepMs));
        exitPositions.add(tester.getTopLeft(find.byKey(secondKey)).dx);
        firstReturnPositions.add(tester.getTopLeft(find.byKey(firstKey)).dx);
      }
      // 200ms -> 235ms 临近终点前仍在屏外边缘滑行
      await tester.pump(const Duration(milliseconds: 35));
      final nearEndX = tester.getTopLeft(find.byKey(secondKey)).dx;
      expect(nearEndX, greaterThan(width * 0.96));

      // 单调向右滑出，且首页单调回正
      for (var i = 1; i < exitPositions.length; i++) {
        expect(exitPositions[i], greaterThan(exitPositions[i - 1]));
        expect(
          firstReturnPositions[i],
          greaterThan(firstReturnPositions[i - 1]),
        );
      }

      // 关键：返回过程应起步快、收尾减速（末段速度远小于首段，彻底告别“返回越跑越快+半路切断”）
      final exitFirstStep = exitPositions[1] - exitPositions[0];
      final exitLastStep =
          exitPositions.last - exitPositions[exitPositions.length - 2];
      expect(exitFirstStep, greaterThan(exitLastStep * 2));

      await tester.pumpAndSettle();
      expect(find.byKey(secondKey), findsNothing);
      expect(tester.getTopLeft(find.byKey(firstKey)).dx, 0.0);
    });

    testWidgets('动画没播放完就返回：从当前视觉位置平滑无缝折返至屏外，不跳变不闪退', (tester) async {
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
                          body: const SizedBox.expand(),
                        ),
                      ),
                    );
                  },
                  child: const Text('进入'),
                ),
              ),
            ),
          ),
        ),
      );

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      await tester.tap(find.text('进入'));
      await tester.pump();
      // 入场播放约 90ms（尚未完成 260ms 入场）
      await tester.pump(const Duration(milliseconds: 90));

      final dxBeforePop = tester.getTopLeft(find.byKey(secondKey)).dx;
      final firstDxBeforePop = tester.getTopLeft(find.byKey(firstKey)).dx;
      expect(dxBeforePop, greaterThan(20.0));
      expect(dxBeforePop, lessThan(width - 20.0));
      expect(firstDxBeforePop, lessThan(-5.0));

      // 入场动画进行到一半直接点击返回按钮
      await tester.tap(find.byType(BackButton));
      await tester.pump();

      // 折返瞬间零跳变：位置与背层位置应与折返前完全连续
      final dxRightAfterPop = tester.getTopLeft(find.byKey(secondKey)).dx;
      final firstDxRightAfterPop = tester.getTopLeft(find.byKey(firstKey)).dx;
      expect(dxRightAfterPop, closeTo(dxBeforePop, 0.01));
      expect(firstDxRightAfterPop, closeTo(firstDxBeforePop, 0.01));

      // 逐帧向屏外平滑退回，不反向回弹、不提前消失
      double prevX = dxRightAfterPop;
      double prevFirstX = firstDxRightAfterPop;
      final reverseSamples = <double>[prevX];
      for (var step = 0; step < 5; step++) {
        await tester.pump(const Duration(milliseconds: 16));
        if (find.byKey(secondKey).evaluate().isEmpty) break;
        final x = tester.getTopLeft(find.byKey(secondKey)).dx;
        final firstX = tester.getTopLeft(find.byKey(firstKey)).dx;
        expect(x, greaterThanOrEqualTo(prevX - 0.01));
        expect(firstX, greaterThanOrEqualTo(prevFirstX - 0.01));
        reverseSamples.add(x);
        prevX = x;
        prevFirstX = firstX;
      }
      expect(reverseSamples.last, greaterThan(dxBeforePop));

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
      // 入场刚过 70ms（动画仍在播放中）
      await tester.pump(const Duration(milliseconds: 70));

      // 1. 新页面上的按钮立即响应点击
      await tester.tap(find.text('立即操作'));
      await tester.pump();
      expect(actionTapCount, 1);

      // 2. 新页面上的列表在动画播放期间即可顺滑滚动
      expect(scrollController.offset, 0.0);
      await tester.drag(find.byType(ListView), const Offset(0, -180));
      await tester.pump();
      final offsetMidTransition = scrollController.offset;
      expect(offsetMidTransition, greaterThan(100.0));

      // 入场结束之后滚动位置保持稳定，不会回跳
      await tester.pumpAndSettle();
      expect(scrollController.offset, closeTo(offsetMidTransition, 0.5));

      // 3. 返回顶部并在半途直接点击打开三级页
      scrollController.jumpTo(0);
      await tester.pump();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // 重新进入并在 70ms 时连续点击跳转三级页
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

    testWidgets('ChangelogPage 进出平滑、入场未完成即可滚动且中途返回无异常重建', (tester) async {
      ChangelogPage.resetCache();
      addTearDown(ChangelogPage.resetCache);

      final manyReleases = <ReleaseLog>[
        for (var v = 10; v >= 1; v--)
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

      // 场景 A：冷打开真实 CHANGELOG.md，在入场未结束时直接返回（无异常、无残留状态）
      await tester.tap(find.text('打开真实日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 45));
      expect(find.text('更新日志'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('打开模拟日志'), findsOneWidget);

      // 场景 B：入场期间不触发后台分段构建，但允许用户直接滑动且不回跳
      await tester.tap(find.text('打开模拟日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));

      // 入场进行中：只渲染首批 2 条，未后台偷跑剩余批次
      expect(find.text('v10.0.0'), findsOneWidget);
      expect(find.text('v9.0.0'), findsOneWidget);
      expect(find.text('v8.0.0'), findsNothing);

      final listFinder = find.byType(ListView);
      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: listFinder, matching: find.byType(Scrollable)),
      );
      await tester.drag(listFinder, const Offset(0, -140));
      await tester.pump();
      final offsetDuringEnter = scrollable.position.pixels;
      expect(offsetDuringEnter, greaterThan(80.0));

      // 等待入场结束与剩余批次加载完成，滚动位置保持稳定
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
      expect(find.text('打开模拟日志'), findsOneWidget);
    });

    testWidgets('桌面端 Windows 平台三级页面连续推入与退场（模拟 关于 -> 更新日志）保持全屏滑行且无半路截断', (
      tester,
    ) async {
      ChangelogPage.resetCache();
      addTearDown(ChangelogPage.resetCache);

      const secondKey = ValueKey<String>('about-mock');
      await tester.pumpWidget(
        buildTestApp(
          platform: TargetPlatform.windows,
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (ctx2) => Scaffold(
                          key: secondKey,
                          appBar: AppBar(
                            leading: const TactileBackButton(),
                            title: const Text('关于'),
                          ),
                          body: Center(
                            child: ElevatedButton(
                              onPressed: () => ChangelogPage.open(ctx2),
                              child: const Text('更新日志入口'),
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                  child: const Text('进关于页'),
                ),
              ),
            ),
          ),
        ),
      );

      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;

      await tester.tap(find.text('进关于页'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('更新日志入口'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));

      // 关于页作为二级页背层同步左移，ChangelogPage 正在入场
      final aboutDxMid = tester.getTopLeft(find.byKey(secondKey)).dx;
      expect(aboutDxMid, lessThan(-10.0));
      await tester.pumpAndSettle();

      // 从 ChangelogPage 返回到关于页：关于页平滑回正至 0，ChangelogPage 滑出屏外
      final changelogScaffold = find.ancestor(
        of: find.text('更新日志'),
        matching: find.byType(Scaffold),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 220));
      expect(
        tester.getTopLeft(changelogScaffold).dx,
        greaterThan(width * 0.94),
      );
      await tester.pumpAndSettle();

      expect(find.text('更新日志'), findsNothing);
      expect(tester.getTopLeft(find.byKey(secondKey)).dx, 0.0);
    });

    testWidgets('ChangelogPage 退出动画期间停止后台批次追加，连续快进快退无异常', (tester) async {
      final manyReleases = <ReleaseLog>[
        for (var v = 12; v >= 1; v--)
          ReleaseLog(
            version: '$v.0.0',
            date: '2026-11-${v.toString().padLeft(2, '0')}',
            description: '版本 **$v**',
            sections: const <LogSection>[
              LogSection(title: '新增', items: <String>['功能条目']),
            ],
          ),
      ];

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ChangelogPage(initialReleases: manyReleases),
                      ),
                    );
                  },
                  child: const Text('打开日志'),
                ),
              ),
            ),
          ),
        ),
      );

      // 快进快退再快进：入场 60ms -> 返回 60ms -> 再次进入 -> 等待完成
      await tester.tap(find.text('打开日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.pumpAndSettle();
      expect(find.text('更新日志'), findsNothing);

      await tester.tap(find.text('打开日志'));
      await tester.pump();
      // 等入场刚好完成（260ms）后立即点击返回，验证退出期间不会继续后台追加远端批次
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

    testWidgets('同路由往返折返（forward -> reverse -> forward）及直接拖拽回退均连续不卡死', (
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

      // 1. 半途逆转（forward -> reverse）
      final ctrl = activeRoute.exposedController!;
      ctrl.reverse();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final dxBeforeReforward = tester.getTopLeft(find.byKey(secondKey)).dx;
      final firstDxBeforeReforward = tester.getTopLeft(find.byKey(firstKey)).dx;
      expect(dxBeforeReforward, greaterThan(0.0));
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

      // 3. 完成状态直接向回拖拽（controller.value = 0.8 -> 0.6 -> 0.4 -> 0.2），不卡死也不跳变
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
    });

    testWidgets('高窗口下 ChangelogPage 首屏未满屏时，入场期间下拉立即加载并可滚动', (tester) async {
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

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) =>
                            ChangelogPage(initialReleases: shortManyReleases),
                      ),
                    );
                  },
                  child: const Text('打开短日志'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开短日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 70));

      // 第 0 批只有 2 张短卡片，未超出 1400px 视口；直接下拉过冲应立即追加新批次并支持后续滚动
      expect(find.text('v8.0.0'), findsNothing);
      await tester.drag(find.byType(ListView), const Offset(0, -160));
      await tester.pump();
      expect(find.text('v8.0.0'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('冷打开 ChangelogPage 异步加载中触发取消返回（reverse -> forward）不会卡在转圈', (
      tester,
    ) async {
      late _ExposedControllerRoute<void> changelogRoute;

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    changelogRoute = _ExposedControllerRoute<void>(
                      builder: (_) => const ChangelogPage(),
                    );
                    Navigator.of(context).push(changelogRoute);
                  },
                  child: const Text('冷打开日志'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('冷打开日志'));
      await tester.pump();
      // 尚未等 asset 回调完成即先逆向（模拟手势返回取消前阶段）
      final ctrl = changelogRoute.exposedController!;
      ctrl.reverse();
      await tester.pump(const Duration(milliseconds: 20));
      // 取消返回，继续前向完成入场
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
