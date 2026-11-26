import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/about_page.dart';
import 'package:qustschedule/pages/changelog_page.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/app_menu.dart'
    show AppMenuItem, AppMenuScope, showAppMenu;
import 'package:qustschedule/widgets/page_skeleton.dart';
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
      bool wrapMenuScope = true,
    }) {
      return MaterialApp(
        theme: buildLightTheme(
          routeWrapper: wrapMenuScope
              ? (BuildContext context, Widget child) =>
                    AppMenuScope(child: child)
              : null,
        ).copyWith(platform: platform),
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

    testWidgets('ChangelogPage 入场动画与并行加载互不干扰：滑入期仅轻量骨架、中途返回零建树、落稳直出且退场内容常驻', (
      tester,
    ) async {
      ChangelogPage.resetCache();
      addTearDown(ChangelogPage.resetCache);

      final manyReleases = <ReleaseLog>[
        for (var v = 12; v >= 1; v--)
          ReleaseLog(
            version: '$v.0.0',
            date: '2026-11-${v.toString().padLeft(2, '0')}',
            description: '版本 **$v** 更新亮点说明，用于验证入场转场与并行加载解耦。\n包含多项体验与性能优化改进。',
            sections: const <LogSection>[
              LogSection(
                title: '优化',
                items: <String>[
                  '性能优化条目一：后台 Isolate 并行解码解析，UI 线程零正则开销',
                  '性能优化条目二：260ms 滑入期仅渲染超轻量静态骨架，杜绝中途重排卡顿',
                ],
              ),
              LogSection(
                title: '修复',
                items: <String>['修复入场中途取消返回（reverse -> forward）状态监听失效的问题'],
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

      // 1. 冷打开真实 CHANGELOG.md：滑入期仅展示超轻量骨架且不挂载 SelectionArea，中途点击返回立即响应
      await tester.tap(find.text('打开真实日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(find.text('更新日志'), findsOneWidget);
      expect(find.byType(CardListTransitionPlaceholder), findsOneWidget);
      expect(find.byType(SelectionArea), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('打开模拟日志'), findsOneWidget);

      // 2. 预加载数据推入：260ms 滑入期同样绝不把重文本/SelectionArea 压入 Frame 0，落稳瞬间直出
      await tester.tap(find.text('打开模拟日志'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 90));
      expect(find.byType(CardListTransitionPlaceholder), findsOneWidget);
      expect(find.byType(SelectionArea), findsNothing);
      expect(find.text('v12.0.0'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.byType(CardListTransitionPlaceholder), findsNothing);
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('v12.0.0'), findsOneWidget);

      // 落稳后原生 ListView.separated 可正常滚动至全部版本
      await tester.scrollUntilVisible(
        find.text('v1.0.0'),
        400,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('v1.0.0'), findsOneWidget);

      // 3. 退场动画期间保持已挂载内容常驻不回退为骨架，且完整滑出屏外销毁
      final width =
          tester.view.physicalSize.width / tester.view.devicePixelRatio;
      final changelogScaffold = find.ancestor(
        of: find.text('更新日志'),
        matching: find.byType(Scaffold),
      );
      await tester.tap(find.byType(BackButton));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      expect(find.byType(SelectionArea), findsOneWidget);
      expect(find.byType(CardListTransitionPlaceholder), findsNothing);
      await tester.pump(const Duration(milliseconds: 145));
      expect(
        tester.getTopLeft(changelogScaffold).dx,
        greaterThan(width * 0.95),
      );
      await tester.pumpAndSettle();
      expect(find.text('更新日志'), findsNothing);
    });

    testWidgets(
      'ChangelogPage 与 LicenseTextPage 冷打开并行加载及入场取消返回（reverse -> forward）正常落稳直出',
      (tester) async {
        ChangelogPage.resetCache();
        LicenseTextPage.resetCache();
        addTearDown(() {
          ChangelogPage.resetCache();
          LicenseTextPage.resetCache();
        });

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
                          changelogRoute = _ExposedControllerRoute<void>(
                            builder: (_) => const ChangelogPage(),
                          );
                          Navigator.of(context).push(changelogRoute);
                        },
                        child: const Text('冷打开日志'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute<void>(
                              builder: (_) => const LicenseTextPage(),
                            ),
                          );
                        },
                        child: const Text('冷打开协议'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

        // 1. ChangelogPage 冷打开中途触发取消返回（forward -> reverse -> forward -> completed）
        await tester.tap(find.text('冷打开日志'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 50));
        expect(find.byType(CardListTransitionPlaceholder), findsOneWidget);
        expect(find.byType(SelectionArea), findsNothing);

        final ctrl = changelogRoute.exposedController!;
        ctrl.reverse();
        await tester.pump(const Duration(milliseconds: 20));
        ctrl.forward();
        await tester.pumpAndSettle();

        expect(find.byType(CardListTransitionPlaceholder), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(SelectionArea), findsOneWidget);
        final latestVersion = parseChangelog(
          await rootBundle.loadString('CHANGELOG.md'),
        ).first.version;
        expect(find.text('v$latestVersion'), findsOneWidget);

        await tester.tap(find.byType(BackButton));
        await tester.pumpAndSettle();

        // 2. LicenseTextPage 冷打开：滑入期展示文档骨架，后台并行解码重排，落稳瞬间直出
        await tester.tap(find.text('冷打开协议'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 80));
        expect(find.byType(DocumentTransitionPlaceholder), findsOneWidget);
        expect(find.byType(SelectionArea), findsNothing);

        await tester.pumpAndSettle();
        expect(find.byType(DocumentTransitionPlaceholder), findsNothing);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(find.byType(SelectionArea), findsOneWidget);
        expect(
          find.textContaining('GNU GENERAL PUBLIC LICENSE'),
          findsOneWidget,
        );
      },
    );

    testWidgets('ChangelogPage 与 LicenseTextPage 入场失败落稳后展示错误与重试，点击重试正常恢复', (
      tester,
    ) async {
      ChangelogPage.resetCache();
      LicenseTextPage.resetCache();
      addTearDown(() {
        ChangelogPage.resetCache();
        LicenseTextPage.resetCache();
        tester.binding.defaultBinaryMessenger.setMockMessageHandler(
          'flutter/assets',
          null,
        );
      });

      var changelogAttempts = 0;
      var licenseAttempts = 0;
      tester.binding.defaultBinaryMessenger.setMockMessageHandler(
        'flutter/assets',
        (message) async {
          final key = utf8.decode(
            message!.buffer.asUint8List(
              message.offsetInBytes,
              message.lengthInBytes,
            ),
          );
          if (key == 'CHANGELOG.md') {
            changelogAttempts++;
            if (changelogAttempts == 1) return null;
            final bytes = utf8.encode(
              '## [9.9.9] - 2026-11-22\n\n### 新增\n\n- 更新日志重试恢复\n',
            );
            return ByteData.sublistView(Uint8List.fromList(bytes));
          }
          if (key == 'LICENSE') {
            licenseAttempts++;
            if (licenseAttempts == 1) return null;
            final bytes = utf8.encode('GPL LICENSE RECOVERED\n\nParagraph 2\n');
            return ByteData.sublistView(Uint8List.fromList(bytes));
          }
          return null;
        },
      );

      await tester.pumpWidget(
        buildTestApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  ElevatedButton(
                    onPressed: () => ChangelogPage.open(context),
                    child: const Text('open-changelog-err'),
                  ),
                  ElevatedButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const LicenseTextPage(),
                      ),
                    ),
                    child: const Text('open-license-err'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // 1. ChangelogPage 滑入中加载失败 -> 滑入期仍保持骨架，落稳后显示错误并支持点击重试恢复
      await tester.tap(find.text('open-changelog-err'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(CardListTransitionPlaceholder), findsOneWidget);
      expect(find.text('重试'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('重试'), findsOneWidget);
      expect(find.textContaining('无法加载更新日志'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsNothing);
      expect(find.text('v9.9.9'), findsOneWidget);
      expect(find.text('更新日志重试恢复'), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // 2. LicenseTextPage 滑入中加载失败 -> 落稳后展示错误与重试按钮，点击重试正常恢复
      await tester.tap(find.text('open-license-err'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.byType(DocumentTransitionPlaceholder), findsOneWidget);
      expect(find.text('重试'), findsNothing);

      await tester.pumpAndSettle();
      expect(find.text('协议文件读取失败'), findsOneWidget);
      expect(find.text('重试'), findsOneWidget);

      await tester.tap(find.text('重试'));
      await tester.pumpAndSettle();
      expect(find.text('重试'), findsNothing);
      expect(find.text('GPL LICENSE RECOVERED'), findsOneWidget);
    });

    testWidgets('推入与退场转场逐帧绘制阴影与背层遮罩期间，RepaintBoundary 隔离页面图层不重复重绘进出双方页面', (
      tester,
    ) async {
      const firstKey = ValueKey<String>('repaint-first-page');
      const secondKey = ValueKey<String>('repaint-second-page');
      const thirdKey = ValueKey<String>('repaint-third-page');

      var firstPaints = 0;
      var secondPaints = 0;
      var thirdPaints = 0;
      late BuildContext firstContext;
      late BuildContext secondContext;
      late BuildContext thirdContext;

      await tester.pumpWidget(
        buildTestApp(
          home: _PaintCounterBox(
            onPaint: () => firstPaints++,
            child: Scaffold(
              key: firstKey,
              body: Builder(
                builder: (context) {
                  firstContext = context;
                  return const Center(child: Text('首页内容'));
                },
              ),
            ),
          ),
        ),
      );

      expect(firstPaints, 1);

      // 1. 推入二级页（1st -> 2nd）：首页有 _RouteScrimPainter + 视差位移，二级页有 _EdgeShadowPainter + 位移
      Navigator.of(firstContext).push(
        MaterialPageRoute<void>(
          builder: (_) => _PaintCounterBox(
            onPaint: () => secondPaints++,
            child: Scaffold(
              key: secondKey,
              body: Builder(
                builder: (context) {
                  secondContext = context;
                  return const Center(child: Text('二级内容'));
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(firstPaints, 1);
      expect(secondPaints, 1);

      var prevSecondDx = tester.getTopLeft(find.byKey(secondKey)).dx;
      var prevFirstDx = tester.getTopLeft(find.byKey(firstKey)).dx;

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 35));
        final secondDx = tester.getTopLeft(find.byKey(secondKey)).dx;
        final firstDx = tester.getTopLeft(find.byKey(firstKey)).dx;
        expect(secondDx, lessThan(prevSecondDx));
        expect(firstDx, lessThan(prevFirstDx));
        prevSecondDx = secondDx;
        prevFirstDx = firstDx;
      }
      // 整个 260ms 推入动画的每一帧，进出双方页面内容均 0 次重绘。
      expect(firstPaints, 1);
      expect(secondPaints, 1);

      // 结构断言：RepaintBoundary 位于路由 SlideTransition 与 CustomPaint 内部并直接包裹 AppMenuScope，
      // 且无离屏透明/快照（不误匹配 ModalRoute 外部自带的 RepaintBoundary）。
      for (final pageKey in <Key>[firstKey, secondKey]) {
        final scope = find.ancestor(
          of: find.byKey(pageKey),
          matching: find.byType(AppMenuScope),
        );
        expect(scope, findsOneWidget);

        final slide = find.ancestor(
          of: scope,
          matching: find.byType(SlideTransition),
        );
        expect(slide, findsAtLeastNWidgets(1));

        // 路由级 RepaintBoundary 必须是 SlideTransition 的后代且是 AppMenuScope 的祖先。
        final innerBoundary = find.descendant(
          of: slide.first,
          matching: find.ancestor(
            of: scope,
            matching: find.byType(RepaintBoundary),
          ),
        );
        expect(innerBoundary, findsOneWidget);

        // 同时确认该 RepaintBoundary 位于 _RouteScrimPainter 的 CustomPaint 内部。
        final innerCustomPaint = find.descendant(
          of: slide.first,
          matching: find.ancestor(
            of: innerBoundary,
            matching: find.byType(CustomPaint),
          ),
        );
        expect(innerCustomPaint, findsAtLeastNWidgets(1));
      }
      expect(find.byType(SnapshotWidget), findsNothing);
      expect(
        find.ancestor(
          of: find.byKey(secondKey),
          matching: find.byType(FadeTransition),
        ),
        findsNothing,
      );
      expect(
        find.ancestor(
          of: find.byKey(secondKey),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );

      await tester.pumpAndSettle();
      expect(firstPaints, 1);
      expect(secondPaints, 1);

      // 2. 从二级页再推入三级页（2nd -> 3rd）：二级页同时挂载 _EdgeShadowPainter 与 _RouteScrimPainter
      Navigator.of(secondContext).push(
        MaterialPageRoute<void>(
          builder: (_) => _PaintCounterBox(
            onPaint: () => thirdPaints++,
            child: Scaffold(
              key: thirdKey,
              body: Builder(
                builder: (context) {
                  thirdContext = context;
                  return const Center(child: Text('三级内容'));
                },
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(secondPaints, 1);
      expect(thirdPaints, 1);

      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 35));
      }
      expect(secondPaints, 1);
      expect(thirdPaints, 1);
      await tester.pumpAndSettle();
      expect(secondPaints, 1);
      expect(thirdPaints, 1);

      // 3. 退场三级页（3rd -> 2nd）：三级页全程 0 次重绘，恢复露出的二级页在逐帧滑出期间亦 0 次重绘
      Navigator.of(thirdContext).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(thirdPaints, 1);
      final secondAfterThirdPopStart = secondPaints;
      expect(secondAfterThirdPopStart, lessThanOrEqualTo(2));
      var prevThirdDx = tester.getTopLeft(find.byKey(thirdKey)).dx;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 35));
        final thirdDx = tester.getTopLeft(find.byKey(thirdKey)).dx;
        expect(thirdDx, greaterThan(prevThirdDx));
        prevThirdDx = thirdDx;
      }
      expect(secondPaints, secondAfterThirdPopStart);
      expect(thirdPaints, 1);
      await tester.pumpAndSettle();

      // 4. 退场二级页回首页（2nd -> 1st）：二级页全程 0 次重绘，首页恢复露出后在逐帧退场期间 0 次重绘
      final secondBeforePop = secondPaints;
      Navigator.of(secondContext).pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1));
      expect(secondPaints, secondBeforePop);
      final firstAfterPopStart = firstPaints;
      expect(firstAfterPopStart, lessThanOrEqualTo(2));
      var prevPopSecondDx = tester.getTopLeft(find.byKey(secondKey)).dx;
      var prevPopFirstDx = tester.getTopLeft(find.byKey(firstKey)).dx;
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 35));
        final secondDx = tester.getTopLeft(find.byKey(secondKey)).dx;
        final firstDx = tester.getTopLeft(find.byKey(firstKey)).dx;
        expect(secondDx, greaterThan(prevPopSecondDx));
        expect(firstDx, greaterThan(prevPopFirstDx));
        prevPopSecondDx = secondDx;
        prevPopFirstDx = firstDx;
      }
      expect(firstPaints, firstAfterPopStart);
      expect(secondPaints, secondBeforePop);
      await tester.pumpAndSettle();
      expect(find.byKey(secondKey), findsNothing);
    });

    testWidgets(
      'RepaintBoundary 包裹 AppMenuScope 时，入场滑行中途展开菜单仍逐帧零延迟跟随且不触发页面重绘',
      (tester) async {
        const triggerKey = ValueKey<String>('mid-slide-menu-trigger');
        var staticBodyPaints = 0;
        late BuildContext homeContext;

        await tester.pumpWidget(
          buildTestApp(
            home: Scaffold(
              body: Builder(
                builder: (context) {
                  homeContext = context;
                  return const Center(child: Text('首页'));
                },
              ),
            ),
          ),
        );

        Navigator.of(homeContext).push(
          MaterialPageRoute<void>(
            builder: (_) => Scaffold(
              body: Column(
                children: <Widget>[
                  Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Builder(
                        builder: (btnContext) => GestureDetector(
                          key: triggerKey,
                          onTap: () => showAppMenu<String>(
                            context: btnContext,
                            items: const <AppMenuItem<String>>[
                              AppMenuItem<String>(value: 'a', label: '跟随菜单项 A'),
                              AppMenuItem<String>(value: 'b', label: '跟随菜单项 B'),
                            ],
                            onSelected: (_) {},
                          ),
                          child: const SizedBox(
                            width: 80,
                            height: 40,
                            child: Center(child: Text('展开菜单')),
                          ),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: _PaintCounterBox(
                      onPaint: () => staticBodyPaints++,
                      child: const Center(child: Text('静态内容区域')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        await tester.pump();
        await tester.pump(const Duration(milliseconds: 60));
        expect(staticBodyPaints, 1);

        // 在入场滑行中途打开 AppMenuScope 锚定菜单。
        final triggerCenter = tester.getCenter(find.byKey(triggerKey));
        await tester.tapAt(triggerCenter);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 30));

        final menuItem = find.text('跟随菜单项 A');
        expect(menuItem, findsOneWidget);

        // 等待菜单展开缩放接近稳态后，核对后续多帧滑行期间菜单与触发按钮相对横坐标恒定（无 1 帧滞后）。
        var prevTriggerDx = tester.getTopLeft(find.byKey(triggerKey)).dx;
        var prevMenuDx = tester.getTopLeft(menuItem).dx;
        expect(prevTriggerDx, greaterThan(40));

        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 25));
          final triggerDx = tester.getTopLeft(find.byKey(triggerKey)).dx;
          final menuDx = tester.getTopLeft(menuItem).dx;
          expect(triggerDx, lessThan(prevTriggerDx));
          expect(menuDx, lessThan(prevMenuDx));
          final triggerDelta = triggerDx - prevTriggerDx;
          final menuDelta = menuDx - prevMenuDx;
          // 菜单相对触发器的位移差应与页面滑动步长一致，证明保留图层下 FollowerLayer 实时读取最新 TransformLayer。
          expect((menuDelta - triggerDelta).abs(), lessThan(2.0));
          prevTriggerDx = triggerDx;
          prevMenuDx = menuDx;
        }

        // 整个滑行与菜单跟随期间，页面静态内容区域 0 次重绘。
        expect(staticBodyPaints, 1);

        await tester.pumpAndSettle();
        expect(find.text('跟随菜单项 A'), findsOneWidget);
        expect(staticBodyPaints, 1);
      },
    );

    testWidgets('buildLightTheme 默认不传 routeWrapper 时正常滑行且不插入 AppMenuScope', (
      tester,
    ) async {
      const firstKey = ValueKey<String>('plain-first');
      const secondKey = ValueKey<String>('plain-second');

      await tester.pumpWidget(
        buildTestApp(
          wrapMenuScope: false,
          home: Scaffold(
            key: firstKey,
            body: Builder(
              builder: (context) => Center(
                child: ElevatedButton(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const Scaffold(
                          key: secondKey,
                          body: Center(child: Text('无菜单作用域二级页')),
                        ),
                      ),
                    );
                  },
                  child: const Text('PushPlain'),
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('PushPlain'));
      await tester.pumpAndSettle();

      expect(find.byKey(secondKey), findsOneWidget);
      expect(find.byType(AppMenuScope), findsNothing);
      final slide = find.ancestor(
        of: find.byKey(secondKey),
        matching: find.byType(SlideTransition),
      );
      expect(slide, findsAtLeastNWidgets(1));
      expect(
        find.descendant(
          of: slide.first,
          matching: find.ancestor(
            of: find.byKey(secondKey),
            matching: find.byType(RepaintBoundary),
          ),
        ),
        findsAtLeastNWidgets(1),
      );
    });
  });
}

class _PaintCounterBox extends SingleChildRenderObjectWidget {
  const _PaintCounterBox({required this.onPaint, super.child});

  final VoidCallback onPaint;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderPaintCounterBox(onPaint);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderPaintCounterBox renderObject,
  ) {
    renderObject.onPaint = onPaint;
  }
}

class _RenderPaintCounterBox extends RenderProxyBox {
  _RenderPaintCounterBox(this.onPaint);

  VoidCallback onPaint;

  @override
  void paint(PaintingContext context, Offset offset) {
    onPaint();
    super.paint(context, offset);
  }
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
