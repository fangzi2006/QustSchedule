/// 界面测试：登录页、周视图课表页、调试页。
///
/// 这里不碰网络与平台通道：AppModel 注入内存凭据存储 + 假后端 + 内存设置。
library;

import 'dart:async';
import 'dart:typed_data' show Float64List;
import 'dart:ui' as ui;

import 'package:qustschedule/main.dart' show pageForStatus;
import 'package:qustschedule/pages/about_page.dart';
import 'package:qustschedule/pages/academic_page.dart';
import 'package:qustschedule/pages/captcha_page.dart';
import 'package:qustschedule/pages/debug_page.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/login_page.dart';
import 'package:qustschedule/pages/reminder_page.dart';
import 'package:qustschedule/pages/reschedule_page.dart';
import 'package:qustschedule/pages/schedule_page.dart';
import 'package:qustschedule/pages/school_address_page.dart';
import 'package:qustschedule/pages/settings_page.dart';
import 'package:qustschedule/pages/timetable_edit_page.dart';
import 'package:qustschedule/pages/timetable_list_page.dart';
import 'package:qustschedule/pages/update_proxy_page.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/app_bottom_sheet.dart';
import 'package:qustschedule/widgets/app_menu.dart';
import 'package:qustschedule/widgets/app_snack_bar.dart';
import 'package:qustschedule/widgets/changelog_category_badge.dart';
import 'package:qustschedule/widgets/course_tile.dart';
import 'package:qustschedule/widgets/floating_dock.dart';
import 'package:qustschedule/widgets/section_title.dart';
import 'package:qustschedule/widgets/tactile_button.dart';
import 'package:qustschedule/widgets/time_wheel_picker.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/reminder_gateway.dart';
import 'package:qustschedule/src/reminder_planner.dart';
import 'package:qustschedule/src/reminder_service.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/term_calendar.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/gestures.dart'
    show PointerDeviceKind, PointerScrollEvent, kSecondaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show ContainerLayer, PaintingContext, RenderObject, RenderParagraph;
import 'package:flutter/services.dart' show SystemChannels;
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';
import 'support/fake_reminder_gateway.dart';

AppModel buildModel({FakeBackend? backend}) {
  final fake = backend ?? FakeBackend();
  return AppModel(
    service: ScheduleService(
      credentials: InMemoryCredentialStore(),
      cookieStorage: FakeSessionRepository(),
      backendFactory: (_) => fake,
      baseUrl: 'https://jw.example.edu.cn/jwglxt',
    ),
    preferences: Preferences.inMemory(),
    schoolBaseUrl: 'https://jw.example.edu.cn/jwglxt',
  );
}

Widget wrap(Widget child) => MaterialApp(home: child);

/// 读出外壳横向轨道当前的**位置**（0 = 课表页正中，1 = 设置页正中）。
///
/// 外壳改成水平平移后，页面的"可见程度"不再由透明度表示，而是由它在
/// 横向轨道上的位置表示：位置 0 就是课表页完全在屏内，1 就是设置页完全在屏内。
/// 这里直接读实际变换后的偏移量，比断言 widget 树可靠：卡在半页时位置是
/// 0.5 这样的中间值。
double shellPagePosition(WidgetTester tester) {
  final Transform transform = tester.widget<Transform>(
    find.byKey(const ValueKey<String>('shell-page-0')),
  );
  final double width = tester.getSize(find.byType(HomeShell)).width;
  if (width <= 0) return 0;
  return -transform.transform.getTranslation().x / width;
}

/// 外壳当前停在第几页（0 = 课表，1 = 设置）。
///
/// 位置离整页足够近才算停稳：停在半页（0.5 附近）说明动画被打断了。
int shellCurrentPage(WidgetTester tester) {
  final double position = shellPagePosition(tester);
  return (position - position.round()).abs() < 0.02 ? position.round() : -1;
}

AnimatedOpacity todayFab(WidgetTester tester) => tester.widget<AnimatedOpacity>(
  find.byKey(const ValueKey<String>('today-fab')),
);

/// 用 push 的方式打开编辑页：保存后 pop 有上一页可回，不会弹到根路由之外。
Future<void> pushEditor(WidgetTester tester, AppModel model, String id) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      TimetableEditPage(model: model, timetableId: id),
                ),
              ),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑'));
  await tester.pumpAndSettle();
}

/// 第 1-2 周与第 15-16 周各一门课：中间的第 8 周是空的，用来测周过滤。
Schedule sparseSchedule() => const Schedule(
  termId: '2026-2027-1',
  maxWeeks: 16,
  entries: <ScheduleEntry>[
    ScheduleEntry(
      id: 'early',
      name: '期初课',
      teacher: '张老师',
      location: 'M1-101',
      day: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: <int>[1, 2],
    ),
    ScheduleEntry(
      id: 'late',
      name: '期末课',
      day: 3,
      startPeriod: 5,
      endPeriod: 6,
      weeks: <int>[15, 16],
    ),
  ],
);

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
      // 6 条线路统一命名，第一条是默认线路。
      expect(find.text('青岛科技大学（线路 1）'), findsOneWidget);
    });
  });

  group('周视图课表页', () {
    testWidgets('按周过滤课程、顶栏一行排布与日期范围实时切换、空周给出空态与校准入口', (tester) async {
      Future<void> pumpWeek(int week, {DateTime? termStart}) async {
        final model = buildModel();
        model.hydrateForTest(
          schedule: sparseSchedule(),
          week: week,
          termStart: termStart,
        );
        // 先卸载上一张课表，避免复用旧 State（翻页控制器的初始页）。
        await tester.pumpWidget(const SizedBox());
        await tester.pumpWidget(wrap(SchedulePage(model: model)));
      }

      await pumpWeek(1, termStart: DateTime(2026, 3, 2));
      expect(find.text('期初课'), findsOneWidget);
      expect(find.text('期末课'), findsNothing, reason: '第 1 周不上期末课');
      expect(find.text('第 1 周'), findsOneWidget);
      expect(find.text(' / 共 16 周'), findsOneWidget);
      expect(find.text('3/2 – 3/8'), findsOneWidget);
      expect(find.textContaining('的课表'), findsNothing);
      expect(find.text('我的课表'), findsNothing);

      final weekCenter = tester.getCenter(find.text('第 1 周'));
      final refresh = tester.getCenter(find.byIcon(Icons.refresh_rounded));
      final more = tester.getCenter(find.byIcon(Icons.more_horiz_rounded));
      expect((weekCenter.dy - refresh.dy).abs(), lessThan(12));
      expect((refresh.dy - more.dy).abs(), lessThan(2));
      expect(weekCenter.dx, lessThan(refresh.dx));

      final previous = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
      );
      expect(previous.onPressed, isNull, reason: '第 1 周上一周按钮禁用');

      // 滑动翻到第 2 周：顶栏周次与日期范围同步更新
      await tester.fling(find.byType(PageView), const Offset(-400, 0), 1000);
      await tester.pumpAndSettle();
      expect(find.text('第 2 周'), findsOneWidget);
      expect(find.text('3/9 – 3/15'), findsOneWidget);

      await pumpWeek(16);
      expect(find.text('期末课'), findsOneWidget);
      expect(find.text('期初课'), findsNothing);
      expect(find.text('第 16 周'), findsOneWidget);

      await pumpWeek(8);
      expect(find.text('第 8 周没有课'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '校准周次'), findsOneWidget);
    });

    testWidgets('调课冲突与课表时间冲突：表头冲突标记、详情弹窗与卡片冲突打点', (tester) async {
      final rescheduleModel = buildModel();
      rescheduleModel.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: <ScheduleEntry>[
            ScheduleEntry(
              id: 'a',
              name: '高等数学',
              day: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: <int>[1],
            ),
            ScheduleEntry(
              id: 'b',
              name: '大学英语',
              day: 3,
              startPeriod: 1,
              endPeriod: 2,
              weeks: <int>[1],
            ),
          ],
        ),
        week: 1,
        termStart: DateTime(2026, 3, 2), // 周一
      );
      await rescheduleModel.addReschedule(
        fromMonth: 3,
        fromDay: 2,
        toMonth: 3,
        toDay: 4,
      );
      await tester.pumpWidget(wrap(SchedulePage(model: rescheduleModel)));
      await tester.pump();

      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('大学英语'), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('course-conflict-badge')),
        findsOneWidget,
      );
      expect(find.byTooltip('周三有调课冲突，点击查看'), findsOneWidget);
      expect(find.byTooltip('周一有调课冲突，点击查看'), findsNothing);

      await tester.tap(find.byTooltip('周三有调课冲突，点击查看'));
      await tester.pumpAndSettle();
      expect(find.text('未显示'), findsOneWidget);
      expect(find.text('大学英语'), findsOneWidget);
      expect(find.textContaining('该时段显示了调课'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final timeConflictModel = buildModel();
      timeConflictModel.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: <ScheduleEntry>[
            ScheduleEntry(
              id: 'a',
              name: '高等数学',
              teacher: '张三',
              location: '第一教室',
              day: 3,
              startPeriod: 1,
              endPeriod: 2,
              weeks: <int>[1],
            ),
            ScheduleEntry(
              id: 'b',
              name: '线性代数',
              teacher: '李四',
              location: '第二教室',
              day: 3,
              startPeriod: 2,
              endPeriod: 3,
              weeks: <int>[1],
            ),
          ],
        ),
        week: 1,
      );
      await tester.pumpWidget(wrap(SchedulePage(model: timeConflictModel)));

      expect(find.byTooltip('周三有课程时间冲突'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('course-conflict-badge')),
        findsNWidgets(2),
      );
    });

    testWidgets('卡片高度固定且内容垂直居中，课表备注跟随开关显示与隐藏', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = buildModel();
      model.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: <ScheduleEntry>[
            ScheduleEntry(
              id: 'a',
              name: '传感器与检测技术',
              teacher: '陈丽敏',
              location: '高密校区 高密线上教室4',
              day: 1,
              startPeriod: 1,
              endPeriod: 1,
              weeks: <int>[1],
            ),
          ],
          remarks: <ScheduleRemark>[
            ScheduleRemark(
              practical: true,
              content: '生产实习',
              courseName: '金工实习',
            ),
            ScheduleRemark(practical: false, content: '线上自主学习'),
          ],
        ),
        week: 1,
        termStart: DateTime(2026, 3, 2),
      );
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      final card = tester.getRect(find.byType(CourseBlock));
      expect(card.height, closeTo(56, 1), reason: '高度固定为一格');

      final title = find.descendant(
        of: find.byType(CourseBlock),
        matching: find.text('传感器与检测技术'),
      );
      final location = find.descendant(
        of: find.byType(CourseBlock),
        matching: find.text('高密线上教室4'),
      );
      final contentMid =
          (tester.getTopLeft(title).dy + tester.getBottomLeft(location).dy) / 2;
      expect(contentMid, closeTo(card.center.dy, 4), reason: '内容垂直居中');

      expect(find.text('备注'), findsOneWidget);
      expect(find.text('实践课程'), findsOneWidget);
      expect(find.text('其他课程'), findsOneWidget);
      expect(find.text('生产实习'), findsOneWidget);
      expect(find.text('线上自主学习'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('备注'),
        ),
        findsOneWidget,
      );

      await model.setShowScheduleRemarks(false);
      await tester.pumpAndSettle();
      expect(find.text('备注'), findsNothing);
      expect(find.text('生产实习'), findsNothing);
    });

    testWidgets('加载中与出错都走状态弹窗，课表页不被整屏转圈或错误页替换', (tester) async {
      final loadingModel = buildModel();
      loadingModel.setStatusForTest(AppStatus.loading);
      await tester.pumpWidget(wrap(HomeShell(model: loadingModel)));
      await tester.pump();

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('获取中…'), findsOneWidget);
      expect(find.byType(SchedulePage), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      model.setStatusForTest(
        AppStatus.failed,
        message: '网络不稳定或教务系统暂时无响应，请稍后重试。',
        code: 'NETWORK_RETRYABLE',
      );
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      expect(find.text('网络不稳定或教务系统暂时无响应，请稍后重试。'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '重试'), findsOneWidget);
      expect(find.widgetWithText(TextButton, '关闭'), findsOneWidget);
      expect(find.text('期初课'), findsOneWidget, reason: '课表还在，没被错误页顶掉');
    });
  });

  group('课表翻页（一次滑动一页）', () {
    double pagerPage(WidgetTester tester) {
      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      return (state.position as PageMetrics).page!;
    }

    Schedule weeklySchedule() => const Schedule(
      termId: '2026-2027-1',
      maxWeeks: 5,
      entries: <ScheduleEntry>[
        ScheduleEntry(
          id: 'w1',
          name: '第一周课',
          day: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: <int>[1],
        ),
        ScheduleEntry(
          id: 'w2',
          name: '第二周课',
          day: 2,
          startPeriod: 3,
          endPeriod: 4,
          weeks: <int>[2],
        ),
        ScheduleEntry(
          id: 'w3',
          name: '第三周课',
          day: 4,
          startPeriod: 5,
          endPeriod: 6,
          weeks: <int>[3],
        ),
      ],
    );

    Future<void> pumpPhone(WidgetTester tester, AppModel model) async {
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      model.hydrateForTest(schedule: weeklySchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pumpAndSettle();
      expect(pagerPage(tester), 0);
    }

    testWidgets('快速横扫只翻一页、连滑两下各翻一页且落页弹簧在 ~300ms 内停稳', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      await tester.fling(find.byType(PageView), const Offset(-450, 0), 1200);

      var frames = 0;
      var last = -1.0;
      while (frames < 80) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        final pixels = state.position.pixels;
        if ((pixels - last).abs() < 0.01) break;
        last = pixels;
      }
      await tester.pumpAndSettle();

      expect(state.position.pixels, 400);
      expect(frames, lessThan(24), reason: '落页弹簧调快过');
      expect(pagerPage(tester), 1, reason: '一次滑动只走一页');
      expect(model.week, 2);
      expect(find.text('第 2 周'), findsOneWidget);

      await tester.fling(find.byType(PageView), const Offset(450, 0), 1200);
      await tester.pumpAndSettle();
      expect(pagerPage(tester), 0);
      expect(model.week, 1);

      // 连着滑两下，每下各翻一页
      await tester.fling(find.byType(PageView), const Offset(-260, 0), 1200);
      await tester.pump(const Duration(milliseconds: 40));
      await tester.fling(find.byType(PageView), const Offset(-260, 0), 1200);
      await tester.pumpAndSettle();

      expect(pagerPage(tester), 2, reason: '两下 = 两页');
      expect(model.week, 3);
    });

    testWidgets('缓慢拖动起拖无死区、三分之一阈值翻页、途中只更新顶栏与空态周次且停稳再写状态', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      // 1. 起拖无死区 + 慢拖不到三分之一回原页
      var gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 6,
      );
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      expect(pagerPage(tester), greaterThan(0.07));

      await gesture.moveBy(const Offset(-60, 0)); // 共 100px = 0.25 页
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(pagerPage(tester), 0);
      expect(model.week, 1);

      // 2. 过三分之一翻页，且途中只更新顶栏、停稳再写 model.week
      gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 12,
      );
      for (var i = 0; i < 5; i++) {
        await gesture.moveBy(const Offset(-50, 0)); // 共 250px > 0.5 页
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(pagerPage(tester), greaterThan(0.5));
      expect(find.text('第 2 周'), findsOneWidget, reason: '顶栏跟着手势走');
      expect(model.week, 1, reason: '手势期间不写周次状态');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(pagerPage(tester), 1);
      expect(model.week, 2);

      // 3. 滑到空周时，空态提示写的是那一页自己的周次
      model.hydrateForTest(schedule: sparseSchedule(), week: 15);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pumpAndSettle();

      gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 15,
      );
      await gesture.moveBy(const Offset(400, 0)); // 往回滑到第 14 周（空周）
      await tester.pump();
      expect(find.text('第 14 周没有课'), findsOneWidget);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('点箭头翻页在 180ms 内完成，且翻页途中按一下仍翻到下一页', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midway = pagerPage(tester);
      expect(midway, greaterThan(0.5));
      expect(midway, lessThan(1));

      await tester.pump(const Duration(milliseconds: 80)); // 累计 180ms
      expect(pagerPage(tester), 1);

      // 翻页途中按一下再抬手，仍然翻到下一页
      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 7,
      );
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pagerPage(tester), 2);
      expect(model.week, 3);
    });

    testWidgets('格子的竖向滚动慢拖跟手且竖向拖拽只滚格子不翻周', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      final grid = tester.state<ScrollableState>(find.byType(Scrollable).at(1));
      expect(grid.position.pixels, 0);
      final before = tester.getRect(find.text('第一周课'));

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('第一周课')),
        pointer: 14,
      );
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();
      expect(grid.position.pixels, greaterThan(30));

      await gesture.moveBy(const Offset(0, -140));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.getRect(find.text('第一周课')).top, lessThan(before.top));
      expect(pagerPage(tester), 0);
      expect(model.week, 1);
    });

    testWidgets('跨多周跳转（含“今”回本周）以一致的 180ms 节奏先滑过前 2 页再无缝跳过中间页并滑入目标页', (
      tester,
    ) async {
      final model = buildModel();
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      model.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        termStart: mondayOf(DateTime.now()),
      );
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pumpAndSettle();
      expect(pagerPage(tester), 0);

      // 1. 正向跨多周（第 1 周 -> 第 12 周）：从第 1 页连续滑过前 2 页，不直接瞬切
      model.goToWeek(12);
      await tester.pump();
      expect(pagerPage(tester), 0);
      expect(find.text('第 12 周'), findsOneWidget);

      // 前段（~50ms / 180ms）仍在前 2 页滑出阶段（0 < page < 2）
      await tester.pump(const Duration(milliseconds: 50));
      expect(pagerPage(tester), greaterThan(0.2));
      expect(pagerPage(tester), lessThan(2.0));

      // 跨过前 2 页后（~120ms / 180ms）已无缝跳过第 4~10 周，落在最后 1 页（10 < page < 11）滑向第 12 周
      await tester.pump(const Duration(milliseconds: 70));
      expect(pagerPage(tester), greaterThan(10.0));
      expect(pagerPage(tester), lessThan(11.0));

      await tester.pump(const Duration(milliseconds: 70));
      await tester.pumpAndSettle();
      expect(pagerPage(tester), 11);
      expect(model.week, 12);

      // 2. 点击右下角“今”按钮跨多周回到本周（第 12 周 -> 第 1 周）：走同一套前 2 页 + 跳过中间页 + 末页滑入
      await tester.tap(find.text('今'));
      await tester.pump();
      expect(pagerPage(tester), 11);
      expect(find.text('第 1 周'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 50));
      expect(pagerPage(tester), greaterThan(9.0));
      expect(pagerPage(tester), lessThan(10.8));

      await tester.pump(const Duration(milliseconds: 70));
      expect(pagerPage(tester), greaterThan(0.0));
      expect(pagerPage(tester), lessThan(1.0));

      await tester.pumpAndSettle();
      expect(pagerPage(tester), 0);
      expect(model.week, 1);

      // 3. 反向跨多周（先跳第 12 周再回第 2 周）与跨 2 周（第 2 周 -> 第 4 周）：同样保持 180ms 节奏
      model.goToWeek(12);
      await tester.pumpAndSettle();
      model.goToWeek(2);
      await tester.pump();
      expect(pagerPage(tester), 11);
      expect(find.text('第 2 周'), findsOneWidget);

      await tester.pump(const Duration(milliseconds: 50));
      expect(pagerPage(tester), greaterThan(9.0));
      expect(pagerPage(tester), lessThan(10.8));

      await tester.pump(const Duration(milliseconds: 70));
      expect(pagerPage(tester), greaterThan(1.0));
      expect(pagerPage(tester), lessThan(2.0));

      await tester.pumpAndSettle();
      expect(pagerPage(tester), 1);
      expect(model.week, 2);

      model.goToWeek(4);
      await tester.pump();
      expect(pagerPage(tester), 1);

      await tester.pump(const Duration(milliseconds: 190));
      expect(pagerPage(tester), 3);
      expect(model.week, 4);
    });
  });

  group('周次与内容分开通知（性能契约）', () {
    testWidgets('换周只发周次通知，重载相同课表不触发偏好通知，内容或身份变了才通知', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      var modelNotified = 0;
      var weekNotified = 0;
      var prefsNotified = 0;
      model.addListener(() => modelNotified++);
      model.weekNotifier.addListener(() => weekNotified++);
      model.prefsNotifier.addListener(() => prefsNotified++);

      model.goToWeek(2);
      expect(weekNotified, 1);
      expect(modelNotified, 0);

      model.hydrateForTest(schedule: sparseSchedule(), week: 2);
      expect(prefsNotified, 0, reason: '内容没变，设置页不该重建');
      expect(modelNotified, greaterThan(0));

      model.hydrateForTest(
        schedule: sparseSchedule(),
        week: 2,
        studentName: '另一位同学',
      );
      expect(prefsNotified, greaterThan(0), reason: '身份变了必须刷新设置页');
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

  group('时间轴与课程块', () {
    testWidgets('左侧时间轴三行居中显示节次与作息时间，点击课程块弹出详情', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      expect(find.text('节'), findsNothing);
      expect(find.text('08:30'), findsOneWidget);
      expect(find.text('09:20'), findsOneWidget);

      final period = tester.widget<Text>(find.text('1'));
      final start = tester.widget<Text>(find.text('08:30'));
      final end = tester.widget<Text>(find.text('09:15'));

      expect(period.style!.fontSize, greaterThan(start.style!.fontSize!));
      expect(start.style!.fontSize, end.style!.fontSize);
      expect(start.style!.color, end.style!.color);
      expect(start.style!.color, const Color(0xFF8C929B));
      expect(
        tester.getCenter(find.text('1')).dy,
        lessThan(tester.getCenter(find.text('08:30')).dy),
      );
      expect(
        tester.getCenter(find.text('08:30')).dy,
        lessThan(tester.getCenter(find.text('09:15')).dy),
      );

      await tester.tap(find.byType(CourseBlock).first);
      await tester.pumpAndSettle();

      expect(find.text('周次'), findsOneWidget);
      expect(find.text('1-2 周'), findsWidgets);
      expect(find.text('张老师'), findsNWidgets(2));
      expect(find.text('本周'), findsOneWidget);
    });

    testWidgets('最小格子高度 + 系统字号放大：时间轴不溢出（黄黑条纹回归）', (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final model = AppModel(
        service: ScheduleService(
          credentials: InMemoryCredentialStore(),
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => FakeBackend(),
          baseUrl: 'https://jw.example.edu.cn/jwglxt',
        ),
        preferences: Preferences.inMemory(cellHeight: minCellHeight),
        schoolBaseUrl: 'https://jw.example.edu.cn/jwglxt',
      );
      model.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: <ScheduleEntry>[
            ScheduleEntry(
              id: 'night',
              name: '晚课',
              teacher: '王五',
              location: '高密校区 M1-239',
              day: 1,
              startPeriod: 10,
              endPeriod: 10,
              weeks: <int>[1],
            ),
          ],
        ),
        week: 1,
      );
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: SchedulePage(model: model),
        ),
      );
      await tester.pump(const Duration(milliseconds: 32));

      expect(find.text('10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('课程块显示哪些信息', () {
    const sampleEntry = ScheduleEntry(
      id: 'x',
      name: '高等数学',
      teacher: '张三',
      location: '崂山校区明德楼302教室',
      day: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: <int>[1],
    );

    Widget sized({
      required double width,
      required double height,
      bool showTeacher = true,
      bool showLocation = true,
      double textScale = 1,
      ScheduleEntry? entry,
    }) => wrap(
      Center(
        child: SizedBox(
          width: width,
          height: height,
          child: CourseBlock(
            entry: entry ?? sampleEntry,
            showTeacher: showTeacher,
            showLocation: showLocation,
            textScale: textScale,
            onTap: () {},
          ),
        ),
      ),
    );

    Text lineOf(WidgetTester tester, String text) => tester.widget<Text>(
      find.descendant(of: find.byType(CourseBlock), matching: find.text(text)),
    );

    testWidgets('宽格子显示课名/教师/房间号，支持开关隐藏与文字缩放', (tester) async {
      const longEntry = ScheduleEntry(
        id: 'x',
        name: '高等数学',
        teacher: '张三',
        location: '崂山校区明德楼302教室东配楼',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: <int>[1],
      );
      await tester.pumpWidget(sized(width: 120, height: 120, entry: longEntry));

      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('张三'), findsOneWidget);
      expect(find.text('明德楼302教室东配楼'), findsOneWidget);
      expect(find.textContaining('崂山校区'), findsNothing);
      expect(lineOf(tester, '张三').maxLines, 1);
      expect(lineOf(tester, '高等数学').textAlign, TextAlign.center);

      // 地点只留房间号（高密校区 M1-239 -> M1-239）且支持文字缩放
      await tester.pumpWidget(
        sized(
          width: 140,
          height: 140,
          textScale: 1.3,
          entry: const ScheduleEntry(
            id: 'loc',
            name: '高等数学',
            teacher: '张三',
            location: '高密校区 M1-239',
            day: 1,
            startPeriod: 1,
            endPeriod: 1,
            weeks: <int>[1],
          ),
        ),
      );
      expect(
        find.descendant(
          of: find.byType(CourseBlock),
          matching: find.text('M1-239'),
        ),
        findsOneWidget,
      );
      expect(lineOf(tester, '高等数学').style!.fontSize, closeTo(11 * 1.3, 0.01));

      // 关掉教师与地点：格子里只剩课名
      await tester.pumpWidget(
        sized(width: 120, height: 120, showTeacher: false, showLocation: false),
      );
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('张三'), findsNothing);
      expect(find.text('明德楼302教室'), findsNothing);
    });

    testWidgets('窄格子与高格子自适应取舍：窄格先砍教师与优先省略课名，高格不设行数上限', (tester) async {
      await tester.pumpWidget(sized(width: 44, height: 56));
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('张三'), findsNothing, reason: '教师优先级低于地点，先让位');
      expect(find.text('明德楼302教室'), findsOneWidget);
      expect(lineOf(tester, '高等数学').maxLines, 1);

      const entry = ScheduleEntry(
        id: 'x',
        name: '创新方法与设计',
        teacher: '刘悦',
        location: '高密校区 高密线上教室6',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: <int>[1],
      );
      await tester.pumpWidget(
        sized(width: 56, height: 60, entry: entry, textScale: 0.95),
      );
      final title = lineOf(tester, '创新方法与设计');
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);
      expect(find.text('高密线上教室6'), findsOneWidget);

      await tester.pumpWidget(sized(width: 34, height: 220, entry: entry));
      expect(lineOf(tester, '创新方法与设计').maxLines, greaterThan(3));
      expect(find.text('刘悦'), findsOneWidget);
      expect(lineOf(tester, '高密线上教室6').maxLines, greaterThanOrEqualTo(2));
    });

    testWidgets('排版扫雷（含 M3 字距与系统粗体临界宽度）：不溢出，也不"有空间却省略"', (tester) async {
      const baseM3 = TextStyle(fontSize: 14, height: 1.43, letterSpacing: 0.25);
      const entries = <ScheduleEntry>[
        ScheduleEntry(
          id: 'a',
          name: '创新方法与设计',
          teacher: '刘悦',
          location: '高密校区 高密线上教室6',
          day: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: <int>[1],
        ),
        ScheduleEntry(
          id: 'b',
          name: '高等数学',
          teacher: '张三',
          location: '高密校区 M1-239',
          day: 1,
          startPeriod: 1,
          endPeriod: 2,
          weeks: <int>[1],
        ),
        sampleEntry,
      ];
      final failures = <String>[];
      for (final entry in entries) {
        for (final scale in <double>[0.8, 1.0, 1.4, 1.6]) {
          for (final scaler in <TextScaler>[
            TextScaler.noScaling,
            const TextScaler.linear(1.6),
          ]) {
            for (final width in <double>[30.0, 44.0, 64.0, 100.0]) {
              for (final height in <double>[56.0, 72.0, 100.0, 160.0]) {
                await tester.pumpWidget(
                  MediaQuery(
                    data: MediaQueryData(textScaler: scaler),
                    child: wrap(
                      Center(
                        child: SizedBox(
                          width: width,
                          height: height,
                          child: CourseBlock(
                            entry: entry,
                            textScale: scale,
                            onTap: () {},
                          ),
                        ),
                      ),
                    ),
                  ),
                );
                if (tester.takeException() != null) {
                  failures.add(
                    'OVERFLOW ${entry.name} scale=$scale w=$width h=$height',
                  );
                }
              }
            }
          }
        }
      }

      // 真机 M3 DefaultTextStyle + 系统粗体临界宽度抽样验证
      for (final bold in <bool>[false, true]) {
        for (final width in <double>[
          30.0,
          36.0,
          36.5,
          42.0,
          48.0,
          48.5,
          54.0,
          84.0,
          84.5,
          90.0,
        ]) {
          for (final height in <double>[72, 96, 140]) {
            await tester.pumpWidget(
              MaterialApp(
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(boldText: bold),
                  child: child!,
                ),
                home: Center(
                  child: SizedBox(
                    width: width,
                    height: height,
                    child: DefaultTextStyle(
                      style: baseM3,
                      child: CourseBlock(entry: entries.first, onTap: () {}),
                    ),
                  ),
                ),
              ),
            );
            final exception = tester.takeException();
            if (exception != null) {
              failures.add('M3 OVERFLOW w=$width h=$height bold=$bold');
              continue;
            }
            final colFinder = find.descendant(
              of: find.byType(CourseBlock),
              matching: find.byType(Column),
            );
            if (colFinder.evaluate().isEmpty) continue;
            final unused =
                (height - 6) - tester.getSize(colFinder.first).height;
            var ellipsized = false;
            for (final element
                in find
                    .descendant(
                      of: find.byType(CourseBlock),
                      matching: find.byType(RichText),
                    )
                    .evaluate()) {
              final paragraph = element.renderObject! as RenderParagraph;
              if (paragraph.didExceedMaxLines) ellipsized = true;
            }
            if (ellipsized && unused > 12 * 1.25 + 4) {
              failures.add(
                'SPACE+ELLIPSIS w=$width h=$height bold=$bold '
                'unused=${unused.toStringAsFixed(1)}',
              );
            }
          }
        }
      }
      expect(failures, isEmpty, reason: failures.take(8).join('\n'));
    });
  });

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

      final openFade = tester.widget<FadeTransition>(
        find
            .ancestor(of: triggerFinder, matching: find.byType(FadeTransition))
            .first,
      );
      expect(openFade.opacity.value, lessThan(0.05));

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
      final closedFade = tester.widget<FadeTransition>(
        find
            .ancestor(of: triggerFinder, matching: find.byType(FadeTransition))
            .first,
      );
      expect(closedFade.opacity.value, 1.0);
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
        double triggerOpacity() => tester
            .widget<FadeTransition>(
              find
                  .ancestor(
                    of: triggerFinder,
                    matching: find.byType(FadeTransition),
                  )
                  .first,
            )
            .opacity
            .value;

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

      double triggerOpacityOf(Finder finder) => tester
          .widget<FadeTransition>(
            find
                .ancestor(of: finder, matching: find.byType(FadeTransition))
                .first,
          )
          .opacity
          .value;

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

  group('作息表编辑与新建', () {
    testWidgets('未改动时保存键禁用，节次按三段分组，快捷设置排在上方且展开为高度动画，改动后可保存', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      final original = model.timetables.first;
      await pushEditor(tester, model, original.id);

      final check = find.widgetWithIcon(IconButton, Icons.check_rounded);
      expect(tester.widget<IconButton>(check).onPressed, isNull);

      expect(find.text('上午'), findsOneWidget);
      expect(find.text('下午'), findsOneWidget);
      expect(find.text('晚上'), findsOneWidget);
      expect(find.textContaining('4 节 · 08:30'), findsOneWidget);

      final quickY = tester.getTopLeft(find.text('快捷设置时间')).dy;
      final sectionsY = tester.getTopLeft(find.text('节次时间')).dy;
      expect(quickY, lessThan(sectionsY));

      await tester.tap(find.text('名称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '夏季作息');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();

      expect(model.timetables.any((table) => table.name == '夏季作息'), isFalse);
      expect(tester.widget<IconButton>(check).onPressed, isNotNull);

      // 快捷设置展开是高度动画
      final card = find
          .ancestor(of: find.text('快捷设置时间'), matching: find.byType(Card))
          .first;
      final collapsed = tester.getSize(card).height;
      await tester.tap(find.text('快捷设置时间'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final halfway = tester.getSize(card).height;
      await tester.pumpAndSettle();
      final expanded = tester.getSize(card).height;
      expect(halfway, greaterThan(collapsed));
      expect(halfway, lessThan(expanded));

      await tester.scrollUntilVisible(
        find.text('第 10 节'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('第 10 节'), findsOneWidget);

      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(model.timetables.any((table) => table.name == '夏季作息'), isTrue);
      expect(find.byType(TimetableEditPage), findsNothing);
    });

    testWidgets('新建作息表无三点菜单或删除键、未保存返回弹确认不创建、点对勾后才创建', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(TimetableListPage(model: model)));
      final before = model.timetables.length;

      await tester.tap(find.byIcon(Icons.add_rounded).first);
      await tester.pumpAndSettle();

      expect(find.text('新建作息表'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
        findsNothing,
      );
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.delete_outline_rounded),
        ),
        findsNothing,
      );

      await tester.tap(find.text('名称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '冬季作息');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();
      expect(find.text('冬季作息'), findsOneWidget);
      expect(model.timetables.length, before);

      // 未保存就返回：弹确认且不创建
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('放弃修改？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '放弃'));
      await tester.pumpAndSettle();
      expect(model.timetables.length, before);
      expect(find.byType(TimetableEditPage), findsNothing);

      // 再次新建并点对勾保存
      await tester.tap(find.widgetWithText(OutlinedButton, '新建作息表'));
      await tester.pumpAndSettle();
      final check = find.widgetWithIcon(IconButton, Icons.check_rounded);
      expect(tester.widget<IconButton>(check).onPressed, isNotNull);
      await tester.tap(check);
      await tester.pumpAndSettle();
      expect(model.timetables.length, before + 1);
      expect(find.byType(TimetableEditPage), findsNothing);
    });

    testWidgets('编辑已有作息表不显示三点菜单，右上角直接显示删除按钮', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      final first = model.timetables.first;
      await pushEditor(tester, model, first.id);

      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.more_vert_rounded),
        ),
        findsNothing,
      );
      final deleteBtn = find.descendant(
        of: find.byType(AppBar),
        matching: find.widgetWithIcon(IconButton, Icons.delete_outline_rounded),
      );
      expect(deleteBtn, findsOneWidget);
      expect(tester.widget<IconButton>(deleteBtn).onPressed, isNull);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await model.upsertTimetable(
        Timetable(
          id: 't2',
          name: '春夏作息',
          effectiveFrom: first.effectiveFrom,
          sections: first.sections,
        ),
      );
      await pushEditor(tester, model, 't2');
      expect(tester.widget<IconButton>(deleteBtn).onPressed, isNotNull);

      await tester.tap(deleteBtn);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, '删除'));
      await tester.pumpAndSettle();
      expect(model.timetables.any((t) => t.id == 't2'), isFalse);
    });
  });

  group('课表节数（三段滚轮）', () {
    testWidgets('点开底部滚轮改节数：取消不改动，按确定才生效', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(TimetableListPage(model: model)));

      expect(find.textContaining('共 10 节'), findsOneWidget);
      expect(find.textContaining('上午 4'), findsOneWidget);

      // 1. 取消不改动
      await tester.tap(find.text('课表节数'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('4 节').first, const Offset(0, -40));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();
      expect(model.sectionCount, 10);

      // 2. 按确定才生效
      await tester.tap(find.text('课表节数'));
      await tester.pumpAndSettle();
      expect(find.text('上午'), findsOneWidget);
      expect(find.text('下午'), findsOneWidget);
      expect(find.text('晚上'), findsOneWidget);

      await tester.drag(find.text('4 节').first, const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(find.textContaining('共 11 节'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '确定'));
      await tester.pumpAndSettle();

      expect(model.sectionCounts[PeriodGroup.morning], 5);
      expect(model.sectionCount, 11);
      expect(find.textContaining('共 11 节'), findsOneWidget);
    });
  });

  group('课表页右上角提示', () {
    testWidgets('提示出现时不遮挡课表，且弹窗宽度跟随文字（短提示紧凑、长提示扩展到上限）', (tester) async {
      final rig = buildModel();
      rig.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        termStart: DateTime(2026, 3, 2),
      );
      await tester.pumpWidget(wrap(HomeShell(model: rig)));

      rig.setHintForTest('更新中…');
      await tester.pump();
      expect(find.text('更新中…'), findsOneWidget);
      expect(find.text('期初课'), findsOneWidget);
      expect(find.text('第 1 周'), findsOneWidget);
      rig.clearHint();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('更新中…'), findsNothing);

      Future<double> widthFor(String hint) async {
        rig.setHintForTest(hint, scope: HintScope.schedule);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250));
        return tester
            .getSize(
              find.descendant(
                of: find.byType(SchedulePage),
                matching: find.byType(AnimatedSwitcher),
              ),
            )
            .width;
      }

      final shortW = await widthFor('已更新');
      rig.clearHint();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      final longW = await widthFor('课表更新失败：连接教务系统超时，请检查网络后重试。' * 3);

      expect(shortW, lessThan(120));
      expect(longW, greaterThan(shortW));
      expect(longW, inInclusiveRange(150, 200));
    });

    testWidgets('提示气泡页面作用域隔离与随页面平移，点击学业更新全局气泡自动平移切到学业页并清除提示', (tester) async {
      final rig = buildModel();
      rig.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        termStart: DateTime(2026, 3, 2),
      );
      await tester.pumpWidget(wrap(HomeShell(model: rig)));

      rig.setHintForTest('课表更新中…', scope: HintScope.schedule);
      await tester.pump();
      expect(find.text('课表更新中…'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('课表更新中…')).dx,
        inInclusiveRange(0, 800),
      );

      rig.setHintForTest('学业更新中…', scope: HintScope.academic);
      await tester.pump();
      expect(find.text('学业更新中…'), findsNothing);

      rig.setHintForTest('正在重新登录…', scope: HintScope.global);
      await tester.pump();
      expect(find.text('正在重新登录…'), findsOneWidget);
      rig.clearGlobalHint();
      await tester.pump();
      expect(find.text('正在重新登录…'), findsNothing);

      // 触发学业更新全局气泡并点击：自动切换到学业页并清除全局气泡
      rig.showAcademicUpdateHintForTest('考试安排有更新');
      await tester.pump();
      expect(find.text('考试安排有更新'), findsOneWidget);

      await tester.tap(find.text('考试安排有更新'));
      await tester.pump();
      await tester.pumpAndSettle();

      expect(find.text('考试安排有更新'), findsNothing);
      expect(find.text('学业概览'), findsOneWidget);
      expect(tester.getTopLeft(find.text('课表更新中…')).dx, lessThan(0));
      expect(find.text('学业更新中…'), findsOneWidget);
      expect(
        tester.getTopLeft(find.text('学业更新中…')).dx,
        inInclusiveRange(0, 800),
      );
    });
  });

  group('设置页账号区与教务地址簿', () {
    testWidgets('设置页账号区展示修改密码与退出登录、姓名空时回退已登录，且可打开教务地址簿', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SettingsPage(model: model)));

      await tester.dragUntilVisible(
        find.text('退出登录'),
        find.byType(ListView),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();

      expect(find.text('修改密码'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      expect(find.text('退出并忘记密码'), findsNothing);
      expect(find.text('测试学生'), findsOneWidget);
      expect(find.text('未登录'), findsNothing);

      model.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        studentName: '',
        studentId: '',
      );
      await tester.pumpAndSettle();
      expect(find.text('已登录'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('教务地址'),
        find.byType(ListView),
        const Offset(0, 60),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('教务地址'));
      await tester.pumpAndSettle();
      expect(find.byType(SchoolAddressPage), findsOneWidget);
    });

    testWidgets('教务地址簿列出使用中地址、新增弹窗防软键盘挤压且可添加新地址', (tester) async {
      final model = buildModel();
      await tester.pumpWidget(wrap(SchoolAddressPage(model: model)));

      expect(find.text('使用中'), findsOneWidget);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();

      final dialog = find.byType(AlertDialog);
      final addBtn = find.widgetWithText(FilledButton, '添加');
      final beforeDialog = tester.getRect(dialog);
      final beforeAddBtn = tester.getRect(addBtn);

      final chip = tester.widget<ActionChip>(find.byType(ActionChip).first);
      expect(chip.materialTapTargetSize, MaterialTapTargetSize.shrinkWrap);
      expect(chip.visualDensity, VisualDensity.compact);

      tester.view.viewInsets = const FakeViewPadding(bottom: 300);
      addTearDown(tester.view.resetViewInsets);
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(tester.getRect(dialog).height, beforeDialog.height);
      expect(tester.getRect(addBtn), beforeAddBtn);

      tester.view.resetViewInsets();
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byType(TextField),
        'https://jw2.example.edu.cn/jwglxt',
      );
      await tester.tap(addBtn);
      await tester.pumpAndSettle();

      expect(model.schools.any((item) => item.contains('jw2')), isTrue);
      await tester.scrollUntilVisible(
        find.text('https://jw2.example.edu.cn/jwglxt'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('https://jw2.example.edu.cn/jwglxt'), findsOneWidget);
    });

    testWidgets('切换线路时不会闪回登录页：全程停在课表页', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(
        wrap(
          ListenableBuilder(
            listenable: model,
            builder: (context, _) => pageForStatus(model),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);

      await model.signIn('20240001', 'pw');
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);

      final future = model.changeSchool('https://jwglxt5.qust.edu.cn/jwglxt');
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(LoginPage), findsNothing);
      }
      await future;
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(model.schoolBaseUrl, 'https://jwglxt5.qust.edu.cn/jwglxt');
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('节次时间（开始+结束一起设）', () {
    testWidgets('点节次行弹出起止滚轮确定写回，且滚轮接管覆盖整个候选值区域', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await pushEditor(tester, model, model.timetables.first.id);

      await tester.tap(find.text('第 1 节'));
      await tester.pumpAndSettle();

      expect(find.text('开始'), findsOneWidget);
      expect(find.text('结束'), findsOneWidget);
      expect(find.textContaining('08:30 – 09:15'), findsOneWidget);

      final wheels = tester
          .widgetList<Listener>(
            find.descendant(
              of: find.byType(CupertinoPicker),
              matching: find.byType(Listener),
            ),
          )
          .where(
            (Listener listener) =>
                listener.onPointerSignal != null && listener.child is Center,
          )
          .toList();
      expect(wheels, isNotEmpty);
      for (final listener in wheels) {
        expect(listener.behavior, HitTestBehavior.opaque);
      }

      await tester.tap(find.widgetWithText(TextButton, '确定'));
      await tester.pumpAndSettle();

      final first = model.timetables.first.sections.first;
      expect(formatClock(first.startMinutes), '08:30');
      expect(formatClock(first.endMinutes), '09:15');
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

  group('"今"按钮与过渡动画打断', () {
    testWidgets('"今"按钮：看本周隐藏、非本周浮出，且翻页动画途中点击能打断并回到本周', (tester) async {
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      final model = buildModel();
      final today = DateTime.now();
      model.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        termStart: mondayOf(today),
      );
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pumpAndSettle();

      expect(todayFab(tester).opacity, 0);

      model.goToWeek(2);
      await tester.pumpAndSettle();
      expect(todayFab(tester).opacity, 1);

      await tester.tap(find.text('今'));
      await tester.pumpAndSettle();
      expect(model.week, 1);
      expect(todayFab(tester).opacity, 0);

      // 翻页动画途中点击"今"打断回到本周
      await tester.fling(find.byType(PageView), const Offset(-260, 0), 1200);
      await tester.pump(const Duration(milliseconds: 40));
      expect(find.text('第 2 周'), findsOneWidget);
      expect(model.week, 1);

      await tester.tap(find.text('今'));
      await tester.pumpAndSettle();
      expect(model.week, 1);
      expect(find.text('第 1 周'), findsOneWidget);
      expect(todayFab(tester).opacity, 0);
    });

    testWidgets('过渡动画可打断：翻周未播完连点下一周生效，切到设置中途点回课表终态正确', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      final next = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);
      await tester.tap(next);
      await tester.pump();
      await tester.tap(next);
      await tester.pump();
      expect(model.week, 3);
      await tester.pumpAndSettle();
      expect(model.week, 3);

      final dock = find.byType(FloatingDock);
      await tester.tap(find.descendant(of: dock, matching: find.text('设置')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      await tester.tap(find.descendant(of: dock, matching: find.text('课表')));
      await tester.pump();
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 0);
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
      m3.setHintForTest('登录中…');
      m3.setStatusForTest(AppStatus.needLogin, message: '已取消登录');
      await tester.pumpWidget(wrap(pageForStatus(m3)));
      await tester.pumpAndSettle();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('登录中…'), findsNothing);
      expect(find.text('已取消登录'), findsOneWidget);

      // 4. 登录中停在登录页，进度走弹窗
      await tester.pumpWidget(const SizedBox());
      final m4 = buildModel();
      m4.setStatusForTest(AppStatus.signingIn);
      await tester.pumpWidget(wrap(pageForStatus(m4)));
      await tester.pump();
      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('登录中…'), findsOneWidget);
    });
  });

  group('课程提醒', () {
    Future<
      ({AppModel model, FakeReminderGateway gateway, ReminderService service})
    >
    buildReminderRig({
      bool enabled = false,
      ReminderRuntimeStatus? status,
    }) async {
      final model = buildModel();
      if (enabled) await model.setReminderEnabled(true);
      model.hydrateForTest(
        schedule: sampleSchedule(),
        termStart: DateTime(2026, 9, 7),
        week: 1,
      );
      final gateway = FakeReminderGateway(
        statusValue:
            status ??
            const ReminderRuntimeStatus(
              notificationPermission: true,
              notificationsEnabled: true,
              exactAlarmAllowed: true,
              scheduled: 3,
              style: 'banner',
              nextTriggerMs: 1789000000000,
            ),
      );
      final service = ReminderService(
        model: model,
        gateway: gateway,
        now: () => DateTime(2026, 9, 7, 6),
      );
      return (model: model, gateway: gateway, service: service);
    }

    testWidgets('Android 下设置页才有「课程提醒」入口', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final rig = await buildReminderRig();
      await tester.pumpWidget(
        wrap(SettingsPage(model: rig.model, reminders: rig.service)),
      );

      expect(find.text('课程提醒'), findsOneWidget);
      expect(find.text('未开启'), findsOneWidget);

      await tester.pumpWidget(
        wrap(SettingsPage(model: rig.model, reminders: null)),
      );
      expect(find.text('课程提醒'), findsNothing);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(
        wrap(SettingsPage(model: rig.model, reminders: rig.service)),
      );
      expect(find.text('课程提醒'), findsNothing);

      rig.service.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('提醒页展示滑块与诊断、开关与流体云同步排程、快捷无边框胶囊与拖动抬手落盘', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final rig = await buildReminderRig();
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: ReminderPage(model: rig.model, service: rig.service),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('上课前提醒'), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      final slider = tester.widget<Slider>(
        find.byKey(const Key('reminder-lead-slider')),
      );
      expect(slider.min, 1);
      expect(slider.max, 60);
      expect(slider.value, 10);
      for (final minutes in reminderLeadOptions) {
        expect(
          find.widgetWithText(TactileSurfaceButton, '$minutes 分钟'),
          findsOneWidget,
        );
      }

      // 1. 打开开关 → 偏好生效并下发排程
      await tester.tap(find.byKey(const Key('reminder-enabled-switch')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(rig.model.reminderEnabled, isTrue);
      expect(rig.gateway.lastPayload['leadMinutes'], 10);
      expect(rig.gateway.toasts, isEmpty);

      // 2. 点击快捷无边框胶囊「20 分钟」
      await tester.tap(find.text('20 分钟'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(rig.model.reminderLeadMinutes, 20);
      expect(rig.gateway.lastPayload['leadMinutes'], 20);

      // 3. 拖滑块中不落盘，抬手才下发一次
      final beforeSyncs = rig.gateway.syncedPayloads.length;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byKey(const Key('reminder-lead-slider'))),
      );
      await gesture.moveBy(const Offset(60, 0));
      await tester.pump();
      expect(rig.gateway.syncedPayloads.length, beforeSyncs);
      await gesture.up();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(rig.gateway.syncedPayloads.length, greaterThan(beforeSyncs));

      // 4. 打开流体云开关再关回
      await tester.tap(find.byKey(const Key('reminder-fluid-switch')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(rig.model.reminderStyle, ReminderStyle.fluid);
      expect(rig.gateway.lastPayload['style'], 'fluid');

      await tester.tap(find.byKey(const Key('reminder-fluid-switch')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(rig.model.reminderStyle, ReminderStyle.banner);
      expect(rig.gateway.stopFluidCount, 1);

      // 5. 滚到底部验证诊断信息展示
      await tester.scrollUntilVisible(
        find.text('1 分钟后测试提醒'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('3 条'), findsOneWidget);
      expect(find.text('精确闹钟'), findsWidgets);

      rig.service.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('立即显示通知、5 秒/1 分钟测试提醒及重排进行中按钮不禁用', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final rig = await buildReminderRig(enabled: true);
      await tester.pumpWidget(
        wrap(ReminderPage(model: rig.model, service: rig.service)),
      );
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(
        find.text('1 分钟后测试提醒'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('立即显示通知'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(rig.gateway.previewRequests, <String>['banner|10|false']);

      await tester.tap(find.text('5 秒后测试提醒'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(rig.gateway.testRequests, contains('banner|5'));

      await tester.tap(find.text('1 分钟后测试提醒'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(rig.gateway.testRequests, contains('banner|60'));

      // 操作进行中按钮不禁用
      final gate = Completer<void>();
      rig.gateway.syncGate = gate;
      await tester.tap(find.text('立即重排'));
      await tester.pump();
      final button = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, '立即重排'),
      );
      expect(button.onPressed, isNotNull);
      gate.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      rig.service.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('自启动项手动确认跳转与从系统设置返回后自动刷新权限状态', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final rig = await buildReminderRig(
        enabled: true,
        status: const ReminderRuntimeStatus(autoStartVendorPage: false),
      );
      await tester.pumpWidget(
        wrap(ReminderPage(model: rig.model, service: rig.service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('已禁止 · 无法收到任何提醒'), findsOneWidget);

      // 从系统设置返回后刷新权限状态
      rig.gateway.statusValue = const ReminderRuntimeStatus(
        notificationPermission: true,
        notificationsEnabled: true,
        exactAlarmAllowed: true,
        autoStartVendorPage: false,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('已允许 · 横幅与锁屏需手动开启'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '去设置').first);
      await tester.pumpAndSettle();
      expect(rig.gateway.notificationSettingsCount, 1);

      // 自启动项手动确认
      await tester.scrollUntilVisible(
        find.text('自启动'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('该权限不可检测，需自行确认'), findsOneWidget);
      final tile = find.ancestor(
        of: find.text('自启动'),
        matching: find.byType(ListTile),
      );
      await tester.ensureVisible(tile);
      await tester.pumpAndSettle();
      await tester.tap(find.descendant(of: tile, matching: find.text('去设置')));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));

      expect(rig.gateway.autostartSettingsCount, 1);
      expect(rig.gateway.toasts, contains('请在设置顶部搜索「自启动」，开启本应用开关'));

      rig.service.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  });

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

        // 3. 教务地址页右侧删除按钮只弹「删除教务地址」，不触发「切换教务地址」。
        final schoolModel = buildModel();
        await tester.pumpWidget(
          MaterialApp(
            theme: buildLightTheme(),
            home: SchoolAddressPage(model: schoolModel),
          ),
        );
        await tester.pumpAndSettle();

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

      // 按住「下一周」向右拉向右侧操作区，再开合「更多」菜单，恢复后 5 个槽位仍完整合绘。
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

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsOneWidget);
      await tester.tapAt(const Offset(12, 12));
      await tester.pumpAndSettle();

      scheduleCanvas.ops.clear();
      debugDisableShadows = false;
      try {
        scheduleScope.paint(scheduleCtx, Offset.zero);
      } finally {
        debugDisableShadows = prevScheduleShadows;
      }
      expect(scheduleCanvas.ops.where((e) => e == 'shadow').length, 5);
      expect(scheduleCanvas.ops.where((e) => e == 'surface').length, 5);
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

  @override
  void save() => _delegate.save();

  @override
  void saveLayer(Rect? bounds, Paint paint) =>
      _delegate.saveLayer(bounds, paint);

  @override
  void restore() => _delegate.restore();

  @override
  int getSaveCount() => _delegate.getSaveCount();

  @override
  void translate(double dx, double dy) => _delegate.translate(dx, dy);

  @override
  void scale(double sx, [double? sy]) => _delegate.scale(sx, sy);

  @override
  void transform(Float64List matrix4) => _delegate.transform(matrix4);

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

  @override
  void paintChild(RenderObject child, Offset offset) {
    child.paint(this, offset);
  }
}
