/// 界面测试：登录页、验证码页、顶层状态路由、HomeShell 外壳、Dock 手势与调试页。
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/main.dart' show pageForStatus;
import 'package:qustschedule/pages/academic_page.dart';
import 'package:qustschedule/pages/captcha_page.dart';
import 'package:qustschedule/pages/debug_page.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/login_page.dart';
import 'package:qustschedule/pages/school_address_page.dart';
import 'package:qustschedule/pages/settings_page.dart';
import 'package:qustschedule/pages/timetable_edit_page.dart';
import 'package:qustschedule/pages/timetable_list_page.dart';
import 'package:qustschedule/pages/update_proxy_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/changelog_category_badge.dart';
import 'package:qustschedule/widgets/floating_dock.dart';
import 'package:qustschedule/widgets/section_title.dart';
import 'package:qustschedule/widgets/tactile_button.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';
import 'support/widget_test_helpers.dart';

void main() {
  group('登录页', () {
    testWidgets('渲染账号密码表单、空提交校验不发请求、可展开高级设置', (tester) async {
      final backend = FakeBackend();
      final model = buildModel(backend: backend);
      // 登录页只在 needLogin 时出现；booting 会带一个无限转圈的进度，
      // pumpAndSettle 会等不到头。
      model.setStatusForTest(AppStatus.needLogin);
      await tester.pumpWidget(wrap(LoginPage(model: model)));

      expect(find.text('青科课表通'), findsOneWidget);
      expect(find.byType(Image), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '账号'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '密码'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
      expect(find.textContaining('记住密码'), findsNothing, reason: '密码总是保存，不需要开关');

      // 空提交：显示表单校验错误，不发请求。
      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();

      expect(find.text('请输入账号'), findsOneWidget);
      expect(find.text('请输入密码'), findsOneWidget);
      expect(backend.loginCount, 0);

      // 展开高级设置能看到教务地址入口。
      await tester.tap(find.text('教务地址 / 高级'));
      await tester.pumpAndSettle();

      expect(find.text('教务系统地址'), findsOneWidget);
      // 默认预设仅保留外网可登录的青科大线路。
      expect(find.text('青岛科技大学'), findsOneWidget);
    });
  });

  group('验证码页面容错与界面样式统一', () {
    testWidgets('验证码 Base64 数据异常时安全降级展示错误占位，不崩溃', (tester) async {
      final backend = FakeBackend(
        loginBehavior: (_, _) async => const CaptchaState(
          continuationId: 'c1',
          imageBase64: 'not-valid-base64!!!',
          mimeType: 'image/png',
        ),
      );
      final model = buildModel(backend: backend);
      await model.signIn('20240001', 'pw');
      expect(model.status, AppStatus.needCaptcha);

      await tester.pumpWidget(wrap(CaptchaPage(model: model)));
      await tester.pump();

      expect(find.text('验证码图片无法显示'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('输入框提示文字采用低对比度淡化色且验证码页局部样式不丢失主题淡化色', (tester) async {
      final lightTheme = buildLightTheme();
      final themeHintStyle = lightTheme.inputDecorationTheme.hintStyle;
      expect(themeHintStyle, isNotNull);
      expect(themeHintStyle!.fontSize, 14);
      expect(themeHintStyle.fontWeight, FontWeight.w400);
      expect(themeHintStyle.color?.a, lessThanOrEqualTo(0.45));

      final backend = FakeBackend(
        loginBehavior: (_, _) async => const CaptchaState(
          continuationId: 'c1',
          imageBase64: 'not-valid-base64!!!',
          mimeType: 'image/png',
        ),
      );
      final model = buildModel(backend: backend);
      addTearDown(model.dispose);
      await model.signIn('20240001', 'pw');

      await tester.pumpWidget(
        MaterialApp(
          theme: lightTheme,
          home: CaptchaPage(model: model),
        ),
      );
      await tester.pump();

      final field = tester.widget<TextField>(find.byType(TextField));
      final fieldHintStyle = field.decoration?.hintStyle;
      expect(fieldHintStyle?.letterSpacing, 0);
      expect(fieldHintStyle?.fontSize, 15);
      expect(fieldHintStyle?.color, themeHintStyle.color);
    });

    testWidgets(
      'AppColors 回退与纯白容器面、SectionTitle 紧凑标题、ChangelogCategoryBadge 语义色及 UpdateProxyPage 零阴影卡片',
      (tester) async {
        await tester.pumpWidget(
          const MaterialApp(
            home: SizedBox.shrink(key: Key('bare-theme-probe')),
          ),
        );
        final bareContext = tester.element(
          find.byKey(const Key('bare-theme-probe')),
        );
        expect(AppColors.of(bareContext).success, AppColors.light.success);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: Scaffold(
              body: Wrap(
                key: const Key('light-theme-probe'),
                children: <Widget>[
                  for (final title in const ['新增', '优化', '修复', '碎碎念', '其他'])
                    ChangelogCategoryBadge(title: title),
                ],
              ),
            ),
          ),
        );
        final themedContext = tester.element(
          find.byKey(const Key('light-theme-probe')),
        );
        final themedData = Theme.of(themedContext);
        expect(AppColors.of(themedContext), same(AppColors.light));
        expect(themedData.colorScheme.surfaceContainerLowest, Colors.white);
        expect(
          tester.widget<Text>(find.text('新增')).style?.color,
          AppColors.light.categoryAdd,
        );

        final model = buildModel();
        model.hydrateForTest(schedule: sparseSchedule(), week: 1);
        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: UpdateProxyPage(model: model),
          ),
        );
        await tester.pumpAndSettle();

        final sectionFinder = find.widgetWithText(SectionTitle, '首选加速节点');
        final sectionText = tester.widget<Text>(
          find.descendant(of: sectionFinder, matching: find.byType(Text)),
        );
        expect(sectionText.style?.fontSize, 12);
        expect(sectionText.style?.fontWeight, FontWeight.w500);

        final cards = tester.widgetList<Card>(find.byType(Card)).toList();
        expect(cards, isNotEmpty);
        for (final card in cards) {
          expect(card.elevation, isNull);
        }
        expect(find.byType(TactileActionButton), findsAtLeastNWidgets(1));
      },
    );

    testWidgets('SettingsPage 修改密码失败走 error 风格 SnackBar 且不再弹 AlertDialog', (
      tester,
    ) async {
      final backend = FakeBackend(
        loginBehavior: (call, _) async {
          if (call == 1) {
            return const AuthenticatedState(
              studentId: '20240001',
              studentName: '测试学生',
            );
          }
          throw const AcademicError(ErrorCode.invalidCredentials, '新密码验证未通过');
        },
      );
      final model = buildModel(backend: backend);
      await model.signIn('20240001', 'oldpw');

      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: SettingsPage(model: model),
        ),
      );

      await tester.dragUntilVisible(
        find.text('修改密码'),
        find.byType(ListView),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('修改密码'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.enterText(find.byType(TextFormField).at(0), 'newpw123');
      await tester.enterText(find.byType(TextFormField).at(1), 'newpw123');
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.textContaining('修改失败：'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('页面路由（状态 → 页面）', () {
    testWidgets('pageForStatus：无课表失败留登录页、有课表失败留课表页、残留提示不死转、登录中弹窗进度', (
      tester,
    ) async {
      // 1. 登录失败且没拿到课表：留在登录页，错误走弹窗
      final m1 = buildModel();
      m1.setStatusForTest(
        AppStatus.failed,
        message: '账号或密码不正确',
        code: 'INVALID_CREDENTIALS',
      );
      await tester.pumpWidget(wrap(pageForStatus(m1)));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text('账号或密码不正确'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重试'), findsNothing);

      // 2. 已经有课表时失败：留在课表页
      await tester.pumpWidget(const SizedBox());
      final m2 = buildModel();
      m2.hydrateForTest(schedule: sparseSchedule(), week: 1);
      m2.setStatusForTest(
        AppStatus.failed,
        message: '教务页面变了',
        code: 'PAGE_CHANGED',
      );
      await tester.pumpWidget(wrap(pageForStatus(m2)));
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.text('教务页面变了'), findsOneWidget);

      // 3. 登录页残留提示不变成永远转的圈
      await tester.pumpWidget(const SizedBox());
      final m3 = buildModel();
      m3.setHintForTest('登录中...');
      m3.setStatusForTest(AppStatus.needLogin, message: '已取消登录');
      await tester.pumpWidget(wrap(pageForStatus(m3)));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('登录中...'), findsNothing);
      expect(find.text('已取消登录'), findsOneWidget);

      // 4. 登录中停在登录页，进度走弹窗
      await tester.pumpWidget(const SizedBox());
      final m4 = buildModel();
      m4.setStatusForTest(AppStatus.signingIn);
      await tester.pumpWidget(wrap(pageForStatus(m4)));
      await tester.pump();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('登录中...'), findsOneWidget);
    });
  });

  group('两页外壳与设置', () {
    testWidgets('冷启动首帧按需懒建页面并常挂，dock 在课表、学业与设置之间切换', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));

      expect(find.byType(SettingsPage), findsNothing);
      expect(find.byType(AcademicPage), findsNothing);
      expect(shellPagePosition(tester), 0);

      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.byType(SettingsPage), findsNothing);
      expect(find.byType(AcademicPage), findsNothing);

      Future<void> tapDock(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(FloatingDock),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }

      // 直达设置页时不提前构建学业页
      await tapDock('设置');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.byType(AcademicPage), findsNothing);
      expect(find.text('作息时间表'), findsOneWidget);
      expect(shellPagePosition(tester), 2);

      final element = tester.element(find.byType(SettingsPage));
      await tapDock('课表');
      expect(shellPagePosition(tester), 0);

      await tapDock('学业');
      expect(find.byType(AcademicPage), findsOneWidget);
      expect(shellPagePosition(tester), 1);

      await tapDock('设置');
      expect(tester.element(find.byType(SettingsPage)), same(element));
    });

    testWidgets('设置页显示作息与校准信息、打开开源许可，且教师与地点开关实时影响课表格子', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));

      expect(model.showTeacher, isTrue);
      expect(model.showLocation, isTrue);
      expect(find.text('张老师'), findsOneWidget);

      await tester.tap(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('作息时间表'), findsOneWidget);
      expect(find.textContaining('秋冬作息'), findsOneWidget);
      expect(find.text('学期周次校准'), findsOneWidget);
      expect(find.textContaining('今天第'), findsOneWidget);

      await tester.tap(find.text('显示教师'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示上课地点'));
      await tester.pumpAndSettle();
      expect(model.showTeacher, isFalse);
      expect(model.showLocation, isFalse);

      // 回到课表：格子里只剩课名
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('课表'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('期初课'), findsOneWidget);
      expect(find.text('张老师'), findsNothing);
      expect(find.text('M1-101'), findsNothing);

      // 切回设置页并打开「关于」→「开源许可」
      await tester.tap(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();

      final aboutTile = find.widgetWithText(ListTile, '关于');
      await tester.scrollUntilVisible(
        aboutTile,
        120,
        scrollable: find.descendant(
          of: find.byType(SettingsPage),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(aboutTile);
      await tester.pumpAndSettle();
      await tester.tap(find.text('开源许可'));
      await tester.pumpAndSettle();
      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('时间表列表标出「使用中」且编辑页可展开快捷设置看到总节数与应用按钮', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(TimetableListPage(model: model)));

      expect(find.text('使用中'), findsOneWidget);
      expect(find.textContaining('节'), findsWidgets);

      final id = model.timetables.first.id;
      await tester.pumpWidget(
        wrap(TimetableEditPage(model: model, timetableId: id)),
      );

      expect(find.text('从哪天开始使用'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('快捷设置时间'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('快捷设置时间'));
      await tester.pumpAndSettle();

      expect(find.text('每节课时长'), findsOneWidget);
      expect(find.text('小课间'), findsOneWidget);
      expect(find.text('大课间休息'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '应用'), findsOneWidget);
      expect(find.textContaining('合计 10 节'), findsOneWidget);
      expect(find.text('上午节数'), findsNothing);
      expect(find.text('下午节数'), findsNothing);
      expect(find.text('晚上节数'), findsNothing);
    });
  });

  group('dock 按住滑动', () {
    testWidgets('按钮垂直居中、图标在上文字在下、58dp 高度窄屏自适应且顶栏按钮统一 36×36', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      final dock = find.byType(FloatingDock);
      final capsule = tester.getRect(
        find.descendant(of: dock, matching: find.byType(Container)).first,
      );
      expect(capsule.height, closeTo(58, 0.5));
      final labelFinder = find.descendant(of: dock, matching: find.text('课表'));
      final buttonBox = tester.getRect(
        find
            .ancestor(of: labelFinder, matching: find.byType(ConstrainedBox))
            .first,
      );
      expect(buttonBox.top, greaterThan(capsule.top + 3));
      expect((buttonBox.center.dy - capsule.center.dy).abs(), lessThan(2));

      final scheduleIcon = tester.getCenter(
        find.descendant(of: dock, matching: find.byType(Icon)).first,
      );
      final scheduleLabel = tester.getCenter(labelFinder);
      expect(scheduleIcon.dy, lessThan(scheduleLabel.dy));
      expect((scheduleIcon.dx - scheduleLabel.dx).abs(), lessThan(1.0));

      // 窄屏压缩宽度（240dp）下自适应缩紧间距且不溢出
      const items = <FloatingDockItem>[
        FloatingDockItem(
          icon: Icons.calendar_today_outlined,
          activeIcon: Icons.calendar_today,
          label: '课表',
        ),
        FloatingDockItem(
          icon: Icons.school_outlined,
          activeIcon: Icons.school,
          label: '学业',
        ),
        FloatingDockItem(
          icon: Icons.tune_outlined,
          activeIcon: Icons.tune,
          label: '设置',
        ),
      ];
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: SizedBox(
                width: 240,
                child: FloatingDock(items: items, index: 0),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final narrowCapsule = tester.getRect(
        find.descendant(of: dock, matching: find.byType(Container)).first,
      );
      expect(narrowCapsule.width, lessThanOrEqualTo(240));

      // 学业页与二级页顶栏按钮均统一使用 36×36 TactileSurfaceButton
      await tester.pumpWidget(wrap(AcademicPage(model: model)));
      await tester.pumpAndSettle();
      final academicRefresh = find.widgetWithIcon(
        TactileIconButton,
        Icons.refresh_rounded,
      );
      expect(tester.getSize(academicRefresh), const Size(36, 36));

      await tester.pumpWidget(wrap(SchoolAddressPage(model: model)));
      await tester.pumpAndSettle();
      expect(find.byType(TactileBackButton), findsOneWidget);
      final addBtn = find.widgetWithIcon(TactileIconButton, Icons.add_rounded);
      expect(tester.getSize(addBtn), const Size(36, 36));
    });

    testWidgets('按住即平移、拖动同步位移、分段阈值判定且内容区横向手势不切页', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 0);
      expect(
        find.descendant(
          of: find.byType(HomeShell),
          matching: find.byType(Opacity),
        ),
        findsNothing,
      );

      final dock = find.byType(FloatingDock);
      final capsule = tester.getRect(
        find.descendant(of: dock, matching: find.byType(Container)).first,
      );
      final schedulePos = tester.getCenter(
        find.descendant(of: dock, matching: find.text('课表')),
      );
      final settingsPos = tester.getCenter(
        find.descendant(of: dock, matching: find.text('设置')),
      );

      // 1. 均分判定：首段轻微右滑不误切，拖动中页面同步连续位移
      var gesture = await tester.startGesture(
        Offset(capsule.left + capsule.width * 0.10, capsule.center.dy),
      );
      await gesture.moveBy(Offset(capsule.width * 0.12, 0));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(shellPagePosition(tester), allOf(greaterThan(0.0), lessThan(1.0)));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 0);

      // 2. 按住「设置」不滑动，页面也立即开始平移切到设置页；再拖回课表页
      gesture = await tester.startGesture(settingsPos);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(shellPagePosition(tester), greaterThan(0.0));
      await tester.pump(const Duration(milliseconds: 300));
      expect(shellCurrentPage(tester), 2);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 2);
      expect(find.byType(SettingsPage), findsOneWidget);

      final gestureBack = await tester.startGesture(settingsPos);
      await gestureBack.moveTo(schedulePos);
      await tester.pump();
      await gestureBack.up();
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 0);

      // 3. 内容区的横向手势不切换外壳页面
      gesture = await tester.startGesture(tester.getCenter(find.text('第 1 周')));
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shellCurrentPage(tester), 0);
    });

    testWidgets('点击指示块单调落位不回弹，光学透镜层裁剪着色、快速拉伸同步更新与主题色切换缓存重建', (tester) async {
      final progress = <double>[];
      const items = <FloatingDockItem>[
        FloatingDockItem(
          icon: Icons.grid_view_outlined,
          activeIcon: Icons.grid_view_rounded,
          label: '课表',
        ),
        FloatingDockItem(
          icon: Icons.school_outlined,
          activeIcon: Icons.school_rounded,
          label: '学业',
        ),
        FloatingDockItem(
          icon: Icons.settings_outlined,
          activeIcon: Icons.settings_rounded,
          label: '设置',
        ),
      ];

      Widget buildDock(Color seed, {double? width, int index = 0}) =>
          MaterialApp(
            theme: ThemeData(
              useMaterial3: true,
              colorScheme: ColorScheme.fromSeed(seedColor: seed),
            ),
            home: Scaffold(
              body: Center(
                child: SizedBox(
                  width: width,
                  child: FloatingDock(
                    index: index,
                    items: items,
                    onPillProgress: progress.add,
                  ),
                ),
              ),
            ),
          );

      await tester.pumpWidget(buildDock(Colors.blue));
      await tester.pumpAndSettle();

      final dock = find.byType(FloatingDock);
      final scheme = Theme.of(tester.element(dock)).colorScheme;
      final rowFinder = find.descendant(of: dock, matching: find.byType(Row));
      expect(
        find.descendant(of: rowFinder, matching: find.byType(Transform)),
        findsNothing,
      );
      for (final label in const ['课表', '学业', '设置']) {
        final text = tester.widget<Text>(
          find.descendant(of: dock, matching: find.text(label)),
        );
        expect(text.style?.color, scheme.onSurfaceVariant);
      }

      final stackFinder = find
          .descendant(of: dock, matching: find.byType(Stack))
          .first;
      final stackSize = tester.getSize(stackFinder);
      final stackTopLeft = tester.getTopLeft(stackFinder);
      ClipPath clipWidget() => tester.widget<ClipPath>(
        find.descendant(of: dock, matching: find.byType(ClipPath)),
      );

      final item0Local =
          tester.getCenter(
            find.descendant(of: dock, matching: find.text('课表')),
          ) -
          stackTopLeft;
      final item2Local =
          tester.getCenter(
            find.descendant(of: dock, matching: find.text('设置')),
          ) -
          stackTopLeft;
      expect(
        clipWidget().clipper!.getClip(stackSize).contains(item0Local),
        isFalse,
      );
      expect(
        clipWidget().clipper!.getClip(stackSize).contains(item2Local),
        isTrue,
      );

      // 点在"设置"按钮偏左位置：按下即报进度、松手单调落位不回弹，且透镜裁剪同步更新
      final settingsLabelRect = tester.getRect(find.text('设置'));
      final gesture = await tester.startGesture(
        Offset(settingsLabelRect.left + 4, settingsLabelRect.center.dy),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(progress, isNotEmpty);

      final customPaints = tester.widgetList<CustomPaint>(
        find.descendant(of: dock, matching: find.byType(CustomPaint)),
      );
      for (final cp in customPaints) {
        final painter = cp.painter;
        if (painter == null) continue;
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        painter.paint(canvas, stackSize);
        recorder.endRecording().dispose();
      }

      await gesture.up();
      await tester.pumpAndSettle();
      expect(progress.last, 1.0);
      for (var i = 1; i < progress.length; i++) {
        expect(progress[i], greaterThanOrEqualTo(progress[i - 1] - 1e-6));
      }
      expect(
        clipWidget().clipper!.getClip(stackSize).contains(item2Local),
        isFalse,
      );

      // 主题色切换 + 宽度压缩重布局：字形缓存重建与裁剪路径同步无异常
      await tester.pumpWidget(buildDock(Colors.teal, width: 220, index: 1));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });

    test('dock 指示胶囊路径采用 FlClash 原生连续圆角并安全处理空/异常矩形', () {
      for (final bad in <Rect>[
        Rect.zero,
        const Rect.fromLTWH(0, 0, 0, 46),
        const Rect.fromLTWH(0, 0, 74, 0),
        const Rect.fromLTRB(20, 10, 10, 50),
        const Rect.fromLTWH(0, 0, double.nan, 46),
        const Rect.fromLTWH(double.nan, 0, 74, 46),
        const Rect.fromLTWH(0, 0, double.infinity, 46),
        const Rect.fromLTWH(0, double.negativeInfinity, 74, 46),
      ]) {
        final emptyPath = FloatingDock.buildLensPathForTest(bad);
        expect(emptyPath.computeMetrics(), isEmpty);
        expect(emptyPath.getBounds().isEmpty, isTrue);
      }

      for (final rect in const <Rect>[
        Rect.fromLTWH(6, 6, 74, 46),
        Rect.fromLTWH(0, -1.8, 85.84, 61.64),
        Rect.fromLTWH(20, 2.5, 111.6, 53.0),
        Rect.fromLTWH(0, 0, 30, 60),
      ]) {
        final path = FloatingDock.buildLensPathForTest(rect);
        final bounds = path.getBounds();
        expect(bounds.left, closeTo(rect.left, 0.05));
        expect(bounds.top, closeTo(rect.top, 0.05));
        expect(bounds.right, closeTo(rect.right, 0.05));
        expect(bounds.bottom, closeTo(rect.bottom, 0.05));

        final metrics = path.computeMetrics().toList();
        expect(metrics, hasLength(1));
        expect(metrics.first.isClosed, isTrue);
        expect(path.contains(rect.center), isTrue);
        expect(path.contains(Offset(rect.center.dx, rect.top + 0.05)), isTrue);
        expect(
          path.contains(Offset(rect.center.dx, rect.bottom - 0.05)),
          isTrue,
        );
        expect(path.contains(Offset(rect.left + 0.5, rect.top + 0.5)), isFalse);

        final radius = rect.shortestSide / 2;
        final expectedBorder = RoundedSuperellipseBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
        ).getOuterPath(rect);
        expect(
          Path.combine(
            PathOperation.xor,
            path,
            expectedBorder,
          ).computeMetrics(),
          isEmpty,
        );
      }

      const rest = Rect.fromLTWH(0, 0, 74, 46);
      final superellipsePath = FloatingDock.buildLensPathForTest(rest);
      final rrectPath = Path()
        ..addRRect(RRect.fromRectAndRadius(rest, const Radius.circular(23)));
      expect(
        Path.combine(
          PathOperation.xor,
          superellipsePath,
          rrectPath,
        ).computeMetrics(),
        isNotEmpty,
      );

      const wideStretch = Rect.fromLTWH(-65, -2, 230, 62);
      const stackSize = Size(200, 58);
      final wideClip = FloatingDock.buildOutsideLensClipForTest(
        wideStretch,
        stackSize,
      );
      expect(wideClip.contains(const Offset(-50, 29)), isFalse);
      expect(wideClip.contains(wideStretch.center), isFalse);
      expect(wideClip.contains(const Offset(185, 29)), isTrue);
    });
  });

  group('调试页', () {
    testWidgets('四个页签渲染概览/200 错误页判定/未获取课表提示/解析结果，并提供清除学业数据按钮', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 3);
      model.requestLog.add(
        const RequestLog(
          method: 'GET',
          url: 'https://jw.example.edu.cn/jwglxt/kbcx/xskbcx_cxXsKb.html',
          status: 200,
          purpose: RequestPurpose.query,
          issue: '返回错误页',
        ),
      );
      await tester.pumpWidget(wrap(DebugPage(model: model)));

      expect(find.widgetWithText(Tab, '概览'), findsOneWidget);
      expect(find.widgetWithText(Tab, '请求'), findsOneWidget);
      expect(find.widgetWithText(Tab, '原始课表'), findsOneWidget);
      expect(find.widgetWithText(Tab, '解析结果'), findsOneWidget);
      expect(find.text('https://jw.example.edu.cn/jwglxt'), findsOneWidget);

      // 概览页底部清除学业数据按钮
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      final clearBtn = find.widgetWithText(FilledButton, '清除学业数据');
      expect(find.text('学业数据与通知调试'), findsOneWidget);
      await tester.tap(clearBtn);
      await tester.pump();
      expect(find.text('已清除学业缓存与内存数据，更新学业数据可查看通知'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));

      await tester.tap(find.widgetWithText(Tab, '请求'));
      await tester.pumpAndSettle();
      expect(find.textContaining('返回错误页'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, '原始课表'));
      await tester.pumpAndSettle();
      expect(find.text('还没有获取过课表'), findsOneWidget);

      await tester.tap(find.widgetWithText(Tab, '解析结果'));
      await tester.pumpAndSettle();
      expect(find.text('期初课'), findsOneWidget);
      expect(find.textContaining('1-2 周'), findsOneWidget);
    });
  });
}
