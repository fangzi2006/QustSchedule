/// 界面测试：登录页、周视图课表页、调试页。
///
/// 这里不碰网络与平台通道：AppModel 注入内存凭据存储 + 假后端 + 内存设置。
library;

import 'package:qustschedule/main.dart' show pageForStatus;
import 'package:qustschedule/pages/debug_page.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/login_page.dart';
import 'package:qustschedule/pages/schedule_page.dart';
import 'package:qustschedule/pages/school_address_page.dart';
import 'package:qustschedule/pages/settings_page.dart';
import 'package:qustschedule/pages/timetable_edit_page.dart';
import 'package:qustschedule/pages/timetable_list_page.dart';
import 'package:qustschedule/widgets/course_tile.dart';
import 'package:qustschedule/widgets/floating_dock.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/term_calendar.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';

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
    testWidgets('渲染账号、密码与登录按钮', (tester) async {
      final model = buildModel();
      // 登录页只在 needLogin 时出现；booting 会带一个无限转圈的进度，
      // pumpAndSettle 会等不到头。
      model.setStatusForTest(AppStatus.needLogin);
      await tester.pumpWidget(wrap(LoginPage(model: model)));

      expect(find.text('青科课表通'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '账号'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '密码'), findsOneWidget);
      expect(find.widgetWithText(FilledButton, '登录'), findsOneWidget);
      expect(find.textContaining('记住密码'), findsNothing, reason: '密码总是保存，不需要开关');
    });

    testWidgets('空提交显示表单校验错误，不发请求', (tester) async {
      final backend = FakeBackend();
      final model = buildModel(backend: backend);
      // 登录页只在 needLogin 时出现；booting 会带一个无限转圈的进度，
      // pumpAndSettle 会等不到头。
      model.setStatusForTest(AppStatus.needLogin);
      await tester.pumpWidget(wrap(LoginPage(model: model)));

      await tester.tap(find.widgetWithText(FilledButton, '登录'));
      await tester.pump();

      expect(find.text('请输入账号'), findsOneWidget);
      expect(find.text('请输入密码'), findsOneWidget);
      expect(backend.loginCount, 0);
    });

    testWidgets('可展开高级设置并看到换校入口', (tester) async {
      final model = buildModel();
      // 登录页只在 needLogin 时出现；booting 会带一个无限转圈的进度，
      // pumpAndSettle 会等不到头。
      model.setStatusForTest(AppStatus.needLogin);
      await tester.pumpWidget(wrap(LoginPage(model: model)));

      await tester.tap(find.text('其他学校 / 高级'));
      await tester.pumpAndSettle();

      expect(find.text('教务系统地址'), findsOneWidget);
      // 6 条线路统一命名，第一条是默认线路。
      expect(find.text('青岛科技大学（线路 1）'), findsOneWidget);
    });
  });

  group('周视图课表页', () {
    testWidgets('只显示当前这一周要上的课', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      expect(find.text('期初课'), findsOneWidget);
      expect(find.text('期末课'), findsNothing, reason: '第 1 周不上期末课');
      expect(find.text('第 1 周'), findsOneWidget);
      expect(find.text(' / 共 16 周'), findsOneWidget);
    });

    testWidgets('切到第 16 周只显示期末课', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 16);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      expect(find.text('期末课'), findsOneWidget);
      expect(find.text('期初课'), findsNothing);
      expect(find.text('第 16 周'), findsOneWidget);
    });

    testWidgets('没有课的周给出空态与校准入口', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 8);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      expect(find.text('第 8 周没有课'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, '校准周次'), findsOneWidget);
    });

    testWidgets('顶部只有一行：周次在左、刷新与更多在右，不写"某某的课表"', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      expect(find.textContaining('的课表'), findsNothing);
      expect(find.text('我的课表'), findsNothing);

      final week = tester.getCenter(find.text('第 1 周'));
      final refresh = tester.getCenter(find.byIcon(Icons.refresh_rounded));
      final more = tester.getCenter(find.byIcon(Icons.more_horiz_rounded));

      expect((week.dy - refresh.dy).abs(), lessThan(12), reason: '周次与刷新要在同一行');
      expect((refresh.dy - more.dy).abs(), lessThan(2));
      expect(week.dx, lessThan(refresh.dx), reason: '周次靠左，按钮靠右');
    });

    testWidgets('上一周按钮在第 1 周禁用', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      final previous = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left_rounded),
      );
      expect(previous.onPressed, isNull);
    });

    testWidgets('周次条显示日期范围', (tester) async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        termStart: DateTime(2026, 3, 2),
      );
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      expect(find.text('3/2 – 3/8'), findsOneWidget);
    });

    testWidgets('调课冲突：表头该天可点，点开列出被顶掉的原课', (tester) async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: const <ScheduleEntry>[
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
      // 把高数（周一 3/2）调到周三（3/4），压在英语同一时段上。
      await model.addReschedule(fromMonth: 3, fromDay: 2, toMonth: 3, toDay: 4);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pump();

      // 网格：只显示调课（高数到周三），英语被顶掉、不在网格里。
      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('大学英语'), findsNothing);
      // 调过来的高数卡片也要打冲突点——它是顶掉原课的"冲突课程"。
      expect(
        find.byKey(const ValueKey<String>('course-conflict-badge')),
        findsOneWidget,
      );

      // 表头：周三出现冲突提示（Tooltip 文案稳定，作查找锚点），周一没有。
      expect(find.byTooltip('周三有调课冲突，点击查看'), findsOneWidget);
      expect(find.byTooltip('周一有调课冲突，点击查看'), findsNothing);

      // 点开 → 详情列出被顶掉的英语，并标注"未显示"、说明谁占了位置。
      await tester.tap(find.byTooltip('周三有调课冲突，点击查看'));
      await tester.pumpAndSettle();
      expect(find.text('未显示'), findsOneWidget);
      expect(find.text('大学英语'), findsOneWidget);
      expect(find.textContaining('该时段显示了调课'), findsOneWidget);
    });

    testWidgets('课表时间冲突：表头该天黄底 + 冲突卡片打点', (tester) async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: const <ScheduleEntry>[
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
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      // 两节课同在周三、节次重叠 → 表头周三出现"课程时间冲突"提示（黄底）。
      expect(find.byTooltip('周三有课程时间冲突'), findsOneWidget);
      // 两张冲突卡片各打一个冲突点（右上角小圆点，不占文字流）。
      expect(
        find.byKey(const ValueKey<String>('course-conflict-badge')),
        findsNWidgets(2),
      );
    });

    testWidgets('高度固定、内容垂直居中：不再因内容长短改高度', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final model = buildModel();
      model.hydrateForTest(
        schedule: Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: const <ScheduleEntry>[
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
        ),
        week: 1,
        termStart: DateTime(2026, 3, 2),
      );
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      // 卡片高度固定 = 1 格（60-4=56），不会因为内容多而长高。
      final card = tester.getRect(find.byType(CourseBlock));
      expect(card.height, closeTo(56, 1), reason: '高度固定为一格');

      // 内容垂直居中：标题顶 + 地点底的中间 ≈ 卡片中线。
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
    });

    testWidgets('课表备注：有就显示在下方，开关关掉就不显示', (tester) async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: Schedule(
          termId: '2026-2027-1',
          maxWeeks: 16,
          entries: const <ScheduleEntry>[
            ScheduleEntry(
              id: 'a',
              name: '高等数学',
              day: 1,
              startPeriod: 1,
              endPeriod: 2,
              weeks: <int>[1],
            ),
          ],
          remarks: const <ScheduleRemark>[
            ScheduleRemark(
              practical: true,
              content: '生产实习',
              courseName: '金工实习',
            ),
            ScheduleRemark(practical: false, content: '线上自主学习'),
          ],
        ),
        week: 1,
      );
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      // 有备注 → 下方"备注"区分实践课程 / 其他课程。
      expect(find.text('备注'), findsOneWidget);
      expect(find.text('实践课程'), findsOneWidget);
      expect(find.text('其他课程'), findsOneWidget);
      expect(find.text('生产实习'), findsOneWidget);
      expect(find.text('线上自主学习'), findsOneWidget);
      // 备注在课表的滚动内容里（跟着网格一起滚），不是固定钉在屏幕上。
      expect(
        find.descendant(
          of: find.byType(SingleChildScrollView),
          matching: find.text('备注'),
        ),
        findsOneWidget,
      );

      // 关掉开关 → 整块消失。
      await model.setShowScheduleRemarks(false);
      await tester.pumpAndSettle();
      expect(find.text('备注'), findsNothing);
      expect(find.text('生产实习'), findsNothing);
    });

    testWidgets('加载中不整屏转圈，进度只在状态弹窗里', (tester) async {
      final model = buildModel();
      model.setStatusForTest(AppStatus.loading);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pump();

      // 全屏只有一个进度圈：状态弹窗里的那个。课表页本身照常铺开。
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('获取中…'), findsOneWidget);
      expect(find.byType(SchedulePage), findsOneWidget);
    });

    testWidgets('错误以弹窗出现，课表页不被整页替换', (tester) async {
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
    /// 翻页层当前页码（0 起）：整数 = 停稳，带小数 = 卡在两页之间。
    double pagerPage(WidgetTester tester) {
      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      return (state.position as PageMetrics).page!;
    }

    /// 每周一门名字不同的课。
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

    /// 用 400 宽的手机视口：一页 400px，手指横扫半屏就能把页面拖过半页，
    /// 正是"滑一下跳过一页"最容易发生的尺度（默认 800 宽测不出来）。
    Future<void> pumpPhone(WidgetTester tester, AppModel model) async {
      tester.view.physicalSize = const Size(400, 640);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      model.hydrateForTest(schedule: weeklySchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pumpAndSettle();
      expect(pagerPage(tester), 0);
    }

    testWidgets('快速横扫，只翻一页（不跳页）', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      // 450px 已超过一整页：这一下把页面拖到 1.1 页左右。
      // 框架默认落点算"当前位置 + 半页"→ round(1.6) = 第 3 周，直接跳过第 2 周。
      await tester.fling(find.byType(PageView), const Offset(-450, 0), 1200);
      await tester.pumpAndSettle();

      expect(pagerPage(tester), 1, reason: '一次滑动只走一页');
      expect(model.week, 2, reason: '周次跟画面一致');
      expect(find.text('第 2 周'), findsOneWidget);
    });

    testWidgets('反方向快速滑动也只翻一页', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);
      await tester.fling(find.byType(PageView), const Offset(-450, 0), 1200);
      await tester.pumpAndSettle();
      expect(pagerPage(tester), 1);

      await tester.fling(find.byType(PageView), const Offset(450, 0), 1200);
      await tester.pumpAndSettle();

      expect(pagerPage(tester), 0);
      expect(model.week, 1);
    });

    testWidgets('连着滑两下，每下各翻一页（不丢页）', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      await tester.fling(find.byType(PageView), const Offset(-260, 0), 1200);
      // 第一下还在吸附途中就起第二下：这一下要从"第一下要落的页"继续算。
      await tester.pump(const Duration(milliseconds: 40));
      await tester.fling(find.byType(PageView), const Offset(-260, 0), 1200);
      await tester.pumpAndSettle();

      expect(pagerPage(tester), 2, reason: '两下 = 两页');
      expect(model.week, 3);
    });

    testWidgets('慢慢拖不到三分之一松手：回到原页', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 6,
      );
      for (var i = 0; i < 2; i++) {
        await gesture.moveBy(const Offset(-50, 0)); // 共 100px = 0.25 页
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pagerPage(tester), 0);
      expect(model.week, 1);
    });

    testWidgets('慢慢拖过三分之一就翻页（比框架的"过半才翻"更容易）', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 12,
      );
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(-50, 0)); // 共 150px = 0.375 页
        await tester.pump(const Duration(milliseconds: 100));
      }
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pagerPage(tester), 1);
      expect(model.week, 2);
    });

    testWidgets('缓慢拖动时第一段位移就生效（起拖不留死区）', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 11,
      );
      // 一次事件走 40px：这一段原来会被框架的起拖阈值吃掉（页面纹丝不动），
      // 现在从"按下那一点"算位移，页面立刻跟上 0.1 页。
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();

      expect(pagerPage(tester), greaterThan(0.07));

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('点箭头翻页在 180ms 内完成（比原来的 220ms 更快）', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      final midway = pagerPage(tester);
      expect(midway, greaterThan(0.5));
      expect(midway, lessThan(1), reason: '100ms 时还在路上');

      await tester.pump(const Duration(milliseconds: 80)); // 累计 180ms
      expect(pagerPage(tester), 1, reason: '150ms 的动画此时应该已经停稳');
    });

    testWidgets('松手后落页在 ~300ms 内停稳', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      final state = tester.state<ScrollableState>(
        find.byType(Scrollable).first,
      );
      await tester.fling(find.byType(PageView), const Offset(-200, 0), 1200);

      // 数到位置不再变化为止（虚拟时钟下的帧数，可复现）。
      var frames = 0;
      var last = -1.0;
      while (frames < 80) {
        await tester.pump(const Duration(milliseconds: 16));
        frames++;
        final pixels = state.position.pixels;
        if ((pixels - last).abs() < 0.01) break;
        last = pixels;
      }

      expect(state.position.pixels, 400, reason: '仍然准确落在第 2 周');
      expect(frames, lessThan(24), reason: '落页弹簧调快过：默认弹簧要 40 帧以上（~640ms）');
    });

    testWidgets('滑动途中只更新顶栏，周次留到停稳再写', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 8,
      );
      // 第一下只是把框架的起拖阈值走完（这段位移框架自己吃掉），第二下才是拖动。
      await gesture.moveBy(const Offset(-40, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-220, 0)); // 累计 0.55 页
      await tester.pump();

      expect(pagerPage(tester), greaterThan(0.5));
      expect(find.text('第 2 周'), findsOneWidget, reason: '顶栏跟着手势走');
      // 跨页那一刻不写 model：写一次就是整页重建，正好砸在滑动最密的一帧上
      // （实测同一帧从 3~5ms 变成 100ms 量级）。周次等停稳再落定。
      expect(model.week, 1, reason: '手势期间不写周次状态');

      await gesture.up();
      await tester.pumpAndSettle();
      expect(model.week, 2, reason: '停稳后落定');
      expect(find.text('第 2 周'), findsOneWidget);
    });

    testWidgets('翻页途中按一下，仍然翻到下一页', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      await tester.tap(
        find.widgetWithIcon(IconButton, Icons.chevron_right_rounded),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));

      // 按下不动再抬手：不是拖拽，不该把翻页按住不动或退回去。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 7,
      );
      await tester.pump(const Duration(milliseconds: 40));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(pagerPage(tester), 1);
      expect(model.week, 2);
    });

    testWidgets('格子的竖向滚动也从按下那一点算位移（慢拖跟手）', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      final grid = tester.state<ScrollableState>(find.byType(Scrollable).at(1));
      expect(grid.position.pixels, 0);

      final gesture = await tester.startGesture(
        tester.getCenter(find.text('第一周课')),
        pointer: 14,
      );
      // 一次事件走 40px：原来这 40px 里有近 20px 被起拖阈值吃掉，
      // 手指走了一截内容才动。
      await gesture.moveBy(const Offset(0, -40));
      await tester.pump();

      expect(grid.position.pixels, greaterThan(30), reason: '40px 的位移应该基本都算进去');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('滑到空周时，空态提示写的是那一页自己的周次', (tester) async {
      // sparseSchedule：第 1-2 周、15-16 周有课，第 3-14 周是空周。
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 15);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pumpAndSettle();

      // 手势期 model 的周次还落后半页（状态等停稳才落定），
      // 空态提示不能跟着 model 走，否则会写着"第 15 周没有课"却停在第 14 周。
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
        pointer: 15,
      );
      await gesture.moveBy(const Offset(600, 0)); // 往回滑到第 14 周（空周）
      await tester.pump();

      expect(find.text('第 14 周没有课'), findsOneWidget);

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('竖向拖拽只滚格子，不翻周', (tester) async {
      final model = buildModel();
      await pumpPhone(tester, model);

      final before = tester.getRect(find.text('第一周课'));
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('第一周课')),
        pointer: 9,
      );
      await gesture.moveBy(const Offset(0, -60));
      await tester.pump();
      await gesture.moveBy(const Offset(0, -120));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(tester.getRect(find.text('第一周课')).top, lessThan(before.top));
      expect(pagerPage(tester), 0);
      expect(model.week, 1);
    });
  });

  group('周次与内容分开通知（性能契约）', () {
    testWidgets('换周只发周次通知，不牵动整张课表', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      var modelNotified = 0;
      var weekNotified = 0;
      model.addListener(() => modelNotified++);
      model.weekNotifier.addListener(() => weekNotified++);

      model.goToWeek(2);

      // 周次是"看哪一页"，不是课表内容：换周不该让整张课表重建一次
      // （实测一次整页重建 37ms，而换周只需要 13ms 重建顶栏）。
      expect(weekNotified, 1, reason: '顶栏要跟着换周');
      expect(modelNotified, 0, reason: '内容没变，整页重建是白花的钱');
    });

    testWidgets('内容变了仍然通知整个 model', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      var modelNotified = 0;
      model.addListener(() => modelNotified++);

      model.hydrateForTest(schedule: sparseSchedule(), week: 2);

      expect(modelNotified, greaterThan(0), reason: '内容变了必须重建界面');
    });

    testWidgets('重载同一份课表不触发偏好通知（后台刷新不该重建设置页）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      var prefsNotified = 0;
      model.prefsNotifier.addListener(() => prefsNotified++);

      // 后台刷新成功、内容一模一样。设置页显示的东西一个字都没变，
      // 就不该让它整页重建一次（17~19ms），更不能重建两次。
      // `_applyCalendar` 每次加载课表都会走到，所以那里必须按"起始日真的变了"判断。
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      expect(prefsNotified, 0, reason: '内容没变，设置页不该重建');

      // 真变了就得通知，否则设置页停在旧名字上。
      model.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        studentName: '另一位同学',
      );
      expect(prefsNotified, greaterThan(0), reason: '身份变了必须刷新设置页');
    });
  });

  group('两页外壳与设置', () {
    testWidgets('冷启动首帧不建设置页，第一次切过去才建（之后就常挂）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));

      // 冷启动首帧只建课表页：设置页整棵建出来要占首帧构建的三分之一以上。
      expect(find.byType(SettingsPage), findsNothing);
      expect(shellPagePosition(tester), 0, reason: '横向轨道停在课表页这一端');

      // 光验第一帧是不够的：曾经试过"首帧之后延一帧预建"，那种写法在第 1 帧
      // 这里照样是 findsNothing，测试就白过了 —— 而它实际上把 40~100ms 的构建
      // 砸在用户刚看到课表、正要滑动的那一帧上（启动卡顿）。
      // 所以这里连空闲帧一起验：只要用户还没碰 dock，这页就不许建。
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(
        find.byType(SettingsPage),
        findsNothing,
        reason: '空闲帧也不许预建：代价会落在用户正在看课表的那一帧上',
      );

      Future<void> tapDock(String label) async {
        await tester.tap(
          find.descendant(
            of: find.byType(FloatingDock),
            matching: find.text(label),
          ),
        );
        await tester.pumpAndSettle();
      }

      await tapDock('设置');
      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('作息时间表'), findsOneWidget);

      // 切回课表再切过去：进过一次就常挂，Element 不能换（换了一身状态就没了）。
      await tapDock('课表');
      final element = tester.element(find.byType(SettingsPage));
      await tapDock('设置');
      expect(
        tester.element(find.byType(SettingsPage)),
        same(element),
        reason: '同一个 Element 才说明这张页一直挂着、状态没被重建',
      );
    });

    testWidgets('dock 在课表与设置之间切换', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));

      expect(find.text('第 1 周'), findsOneWidget);
      expect(shellPagePosition(tester), 0, reason: '初始停在课表页');

      await tester.tap(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SettingsPage), findsOneWidget);
      expect(find.text('作息时间表'), findsOneWidget);
      expect(shellPagePosition(tester), 1, reason: '整页滑到设置页');

      await tester.tap(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('课表'),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('第 1 周'), findsOneWidget);
      // 回归断言：切回课表时它必须真的滑回原位，而不是停在两页中间。
      expect(shellPagePosition(tester), 0, reason: '整页滑回课表页');
    });

    testWidgets('设置页「关于」组：开源许可可打开', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SettingsPage(model: model)));

      // 关于组在页面底部，懒加载列表要滚到才会构建。
      await tester.scrollUntilVisible(
        find.text('开源许可'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('开源许可'));
      await tester.pumpAndSettle();

      expect(find.byType(LicensePage), findsOneWidget);
    });

    testWidgets('设置页显示当前作息表与学期校准信息', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SettingsPage(model: model)));

      expect(find.text('作息时间表'), findsOneWidget);
      expect(find.textContaining('秋冬作息'), findsOneWidget);
      expect(find.text('学期周次校准'), findsOneWidget);
      expect(find.textContaining('今天第'), findsOneWidget);
    });

    testWidgets('教师 / 地点开关：默认开，点了就关并影响课表格子', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));

      expect(model.showTeacher, isTrue);
      expect(model.showLocation, isTrue);
      expect(find.text('张老师'), findsOneWidget, reason: '默认格子里有教师');

      await tester.tap(
        find.descendant(
          of: find.byType(FloatingDock),
          matching: find.text('设置'),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('显示教师'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('显示上课地点'));
      await tester.pumpAndSettle();

      expect(model.showTeacher, isFalse);
      expect(model.showLocation, isFalse);
      expect(find.text('张老师'), findsNothing);

      // 回到课表：格子里只剩课名。
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
    });

    testWidgets('时间表列表标出「使用中」的那张', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(TimetableListPage(model: model)));

      expect(find.text('使用中'), findsOneWidget);
      expect(find.textContaining('节'), findsWidgets);
    });

    testWidgets('编辑页可展开快捷设置并看到总节数与应用按钮', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      final id = model.timetables.first.id;
      await tester.pumpWidget(
        wrap(TimetableEditPage(model: model, timetableId: id)),
      );

      expect(find.text('从哪天开始使用'), findsOneWidget);

      // 卡片在节次列表下方，先滚进视口（ListView 懒加载）。
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
      // 节数已经挪到「课表节数」，面板里只读展示合计，不再有分段节数设置。
      expect(find.textContaining('合计 10 节'), findsOneWidget);
      expect(find.text('上午节数'), findsNothing);
      expect(find.text('下午节数'), findsNothing);
      expect(find.text('晚上节数'), findsNothing);
    });
  });

  group('时间轴与课程块', () {
    testWidgets('左侧时间轴显示作息时间', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      // 默认作息第 1 节 08:30 开始。
      expect(find.text('08:30'), findsOneWidget);
      expect(find.text('09:20'), findsOneWidget, reason: '第 2 节 09:20');
    });

    testWidgets('时间轴是三行居中：节数大、起止时间灰', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      // 表头不写"节"字。
      expect(find.text('节'), findsNothing);

      final period = tester.widget<Text>(find.text('1'));
      final start = tester.widget<Text>(find.text('08:30'));
      final end = tester.widget<Text>(find.text('09:15'));

      expect(
        period.style!.fontSize,
        greaterThan(start.style!.fontSize!),
        reason: '节数用更大的字体，且排在第一行',
      );
      expect(start.style!.fontSize, end.style!.fontSize);
      expect(start.style!.color, end.style!.color);
      expect(start.style!.color, const Color(0xFF8C929B), reason: '时间用灰色');

      // 三行居中：节数在时间上方，且都在这一行的垂直中线附近。
      expect(
        tester.getCenter(find.text('1')).dy,
        lessThan(tester.getCenter(find.text('08:30')).dy),
      );
      expect(
        tester.getCenter(find.text('08:30')).dy,
        lessThan(tester.getCenter(find.text('09:15')).dy),
      );
    });

    testWidgets('最小格子高度 + 系统字号放大：时间轴不溢出（黄黑条纹回归）', (tester) async {
      // 这条守的是黄黑溢出条纹：格子高度调到最小 56、系统字号 1.3 时，
      // 节数 `10` 在 34px 宽的时间列里放不下（全角数字 2×18.2 > 34）→ 折成两行
      // 40px，加两个时刻 8.21×2 = 56.42，比一行 56 高出 0.42px → 调试模式画条纹。
      // 现在整列套 FittedBox(scaleDown)，永远压进一格。
      await tester.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      final model = AppModel(
        service: ScheduleService(
          credentials: InMemoryCredentialStore(),
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => FakeBackend(),
          baseUrl: 'https://jw.example.edu.cn/jwglxt',
        ),
        // 直接把格子高度放进初始设置：走 model.setCellHeight 会挂一个防抖定时器，
        // 测试结束时它还算 pending。
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

      expect(find.text('10'), findsOneWidget, reason: '第 10 节的节数在时间轴上');
      expect(tester.takeException(), isNull, reason: '时间轴三行必须压进一格，不能溢出');
    });

    testWidgets('点击课程块弹出详情（含周次与教师）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      await tester.tap(find.byType(CourseBlock).first);
      await tester.pumpAndSettle();

      expect(find.text('周次'), findsOneWidget);
      expect(find.text('1-2 周'), findsWidgets);
      // 格子里显示一次、详情里一次。
      expect(find.text('张老师'), findsNWidgets(2));
      expect(find.text('本周'), findsOneWidget);
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

    /// 把课程块塞进固定尺寸里，行数分配才有确定的输入。
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

    testWidgets('宽格子：课名、教师、地点都在，长地点换成多行显示', (tester) async {
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
      // 卡片里只显示房间号：校区前缀不占格子（详情弹窗里仍是完整地点）。
      expect(find.text('明德楼302教室东配楼'), findsOneWidget);
      expect(find.textContaining('崂山校区'), findsNothing, reason: '校区前缀省掉');
      expect(lineOf(tester, '张三').maxLines, 1);
      expect(
        lineOf(tester, '高等数学').textAlign,
        TextAlign.center,
        reason: '格子里的文字居中',
      );
    });

    testWidgets('地点只留房间号：各种形态都按预期裁剪', (tester) async {
      const cases = <String, String>{
        '高密校区 M1-239': 'M1-239',
        '高密校区 高密线上教室6': '高密线上教室6',
        '崂山校区明德楼302教室': '明德楼302教室',
        'M1-101': 'M1-101',
        '线上': '线上',
      };
      for (final entry in cases.entries) {
        await tester.pumpWidget(
          sized(
            width: 140,
            height: 120,
            entry: ScheduleEntry(
              id: 'loc',
              name: '高等数学',
              teacher: '张三',
              location: entry.key,
              day: 1,
              startPeriod: 1,
              endPeriod: 1,
              weeks: const <int>[1],
            ),
          ),
        );
        expect(
          find.descendant(
            of: find.byType(CourseBlock),
            matching: find.text(entry.value),
          ),
          findsOneWidget,
          reason: '「${entry.key}」在卡片里显示为「${entry.value}」',
        );
      }
    });

    testWidgets('窄格子：先砍教师，课名与地点还在', (tester) async {
      // 高度压到最小格高：自适应排版下 72px 已能装下"课名 1 行 + 教师 + 地点"，
      // 56px 才真正装不下，走到"课名压 1 行 → 教师让位"。
      await tester.pumpWidget(sized(width: 44, height: 56));

      expect(find.text('高等数学'), findsOneWidget, reason: '课名保底一行');
      expect(find.text('张三'), findsNothing, reason: '教师优先级低于地点，先让位');
      expect(find.text('明德楼302教室'), findsOneWidget, reason: '地点还在');
      expect(lineOf(tester, '高等数学').maxLines, 1, reason: '课名降到一行');
    });

    testWidgets('装不下优先省略课名：课名压 1 行出省略号，地点还在', (tester) async {
      // 格子高度固定、字号固定，只靠"排几行"取舍。
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

      // 课名最先被省略：压到 1 行 + 省略号。
      final title = lineOf(tester, '创新方法与设计');
      expect(title.maxLines, 1, reason: '优先省略课名');
      expect(title.overflow, TextOverflow.ellipsis);
      // 地点比课名更保：仍然完整显示在格子里（校区前缀已省掉）。
      expect(find.text('高密线上教室6'), findsOneWidget, reason: '地点优先于课名');
    });

    testWidgets('自适应：格子够高时完整显示，不再写死行数上限', (tester) async {
      // 课名 7 个字在 34px 宽的格子里自然要折 4 行以上：
      // 旧实现有"课名最多 3 行"的上限，下面留着空间也截成"创新方法与…"。
      const longName = ScheduleEntry(
        id: 'long',
        name: '创新方法与设计',
        teacher: '刘悦',
        location: '高密校区 高密线上教室6',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: <int>[1],
      );
      await tester.pumpWidget(sized(width: 34, height: 220, entry: longName));

      expect(find.text('创新方法与设计'), findsOneWidget);
      expect(
        lineOf(tester, '创新方法与设计').maxLines,
        greaterThan(3),
        reason: '行数不设上限：格子装得下就完整显示',
      );
      expect(find.text('刘悦'), findsOneWidget);
      expect(
        lineOf(tester, '高密线上教室6').maxLines,
        greaterThanOrEqualTo(2),
        reason: '地点（只剩房间号）也完整显示、该换行就换行',
      );
    });

    testWidgets('关掉教师与地点：格子里只剩课名', (tester) async {
      await tester.pumpWidget(
        sized(width: 120, height: 120, showTeacher: false, showLocation: false),
      );

      expect(find.text('高等数学'), findsOneWidget);
      expect(find.text('张三'), findsNothing);
      expect(find.text('明德楼302教室'), findsNothing);
    });

    testWidgets('文字缩放只乘在卡片文字上', (tester) async {
      await tester.pumpWidget(sized(width: 140, height: 140, textScale: 1.3));
      final title = lineOf(tester, '高等数学');
      expect(title.style!.fontSize, closeTo(11 * 1.3, 0.01));
    });

    testWidgets('扫雷：不溢出，也不"有空间却省略"', (tester) async {
      // 行高靠 TextPainter 实测（引擎会给每行 ascent/descent 取整，公式会算小）。
      // 这组扫雷守两条底线：
      //  1. 任何组合都不溢出（溢出会被 ClipRect 裁掉，表现为文字被切）；
      //  2. 任何组合都不出现"卡片还有空间、文字却是省略号"——某字段被省略时，
      //     剩余垂直空间必须小于一行（否则说明预算与真实渲染脱节、该回填却没回填）。
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
            TextScaler.linear(1.6),
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
                final exception = tester.takeException();
                if (exception != null) {
                  failures.add(
                    'OVERFLOW ${entry.name} scale=$scale w=$width h=$height '
                    'scaler=${scaler.scale(10)}',
                  );
                  continue;
                }
                final colFinder = find.descendant(
                  of: find.byType(CourseBlock),
                  matching: find.byType(Column),
                );
                if (colFinder.evaluate().isEmpty) continue;
                final colH = tester.getSize(colFinder.first).height;
                final unused = (height - 6) - colH;
                var ellipsized = false;
                for (final element
                    in find
                        .descendant(
                          of: find.byType(CourseBlock),
                          matching: find.byType(Text),
                        )
                        .evaluate()) {
                  final w = element.widget;
                  if (w is! Text) continue;
                  final data = w.data ?? '';
                  // 房间号是"裸字母数字 token 且含数字"，由 FittedBox 整体缩放、不省略。
                  final isRoom =
                      RegExp(r'^[A-Za-z0-9]+(?:[-\u2011][A-Za-z0-9]+)*$')
                          .hasMatch(data) &&
                      data.contains(RegExp(r'\d'));
                  if (isRoom) continue;
                  final tp = TextPainter(
                    text: TextSpan(text: data, style: w.style),
                    textDirection: TextDirection.ltr,
                    textScaler: scaler,
                  )..layout(maxWidth: width - 6);
                  final natural = tp.computeLineMetrics().length;
                  tp.dispose();
                  if ((w.maxLines ?? 1 << 30) < natural) ellipsized = true;
                }
                // 有省略时，剩余空间必须小于"一整行"——否则说明本该显示的整行被省了。
                // 新排序"课名最先省略"，而课名行是最高的一行；剩余空间若够课名一整行，
                // 回填会把它补回来，所以这里以"课名一行 + 容差"为阈值。
                final oneLine = 12 * scale * scaler.scale(1.0) * 1.25 + 4;
                if (ellipsized && unused > oneLine) {
                  failures.add(
                    'SPACE+ELLIPSIS ${entry.name} scale=$scale w=$width '
                    'h=$height scaler=${scaler.scale(10)} '
                    'unused=${unused.toStringAsFixed(1)}',
                  );
                }
              }
            }
          }
        }
      }
      expect(failures, isEmpty, reason: failures.take(8).join('\n'));
    });

    testWidgets('真机样式扫雷：M3 DefaultTextStyle + 系统粗体下不溢出、也不错省', (tester) async {
      // 这一条补的是上面扫雷的**盲区**：flutter_test 根部的 DefaultTextStyle 是
      // monospace / letterSpacing null，而真机上是 Material 3 的 bodyMedium
      // （fontSize 14 / height 1.43 / **letterSpacing 0.25**）。每字符多 0.25px
      // 足以让行数在临界宽度上多出一整行：
      //   「创新方法与设计」实测 测量(无字距) 3 行 → 渲染(有字距) 4 行，
      //   临界宽度 36.0~36.5 / 48.0~48.75 / 84.0~84.5；
      // 而 320 宽屏 7 列时格宽 ≈ 36.86，正踩在边界上——这就是"特定情况"。
      // 再加系统"粗体文字"（MediaQuery.boldText）会让字形更宽。
      const base = TextStyle(fontSize: 14, height: 1.43, letterSpacing: 0.25);
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
      final failures = <String>[];
      for (final bold in <bool>[false, true]) {
        // 0.5px 步长扫过整段格宽：字距只改 0.25px/字符，临界宽度是离散的几个
        // 小区间（实测可用宽 ≈ 24 / 36~36.5 / 48~48.75 / 84~84.5，卡宽再加 6），
        // 用整数宽度采样会整段跳过它们。
        for (var width = 30.0; width <= 94.0; width += 0.5) {
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
                      style: base,
                      child: CourseBlock(entry: entry, onTap: () {}),
                    ),
                  ),
                ),
              ),
            );
            final exception = tester.takeException();
            if (exception != null) {
              failures.add(
                'OVERFLOW w=$width h=$height bold=$bold -> '
                '${exception.toString().split('\n').first}',
              );
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
            // 用渲染结果本身判断"有没有被省略"（didExceedMaxLines），
            // 不去猜实现给了多少 maxLines——这样测试和实现是两套独立推理。
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
            // 课名一行 15px；剩余空间够一整行却还在省略号 → 预算又算错了。
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
    testWidgets('去掉调试与退出，加上作息时间表 / 教务地址 / 外观', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();

      expect(find.text('校准当前周次'), findsOneWidget);
      expect(find.text('作息时间表'), findsOneWidget);
      expect(find.text('教务地址'), findsOneWidget);
      expect(find.text('外观'), findsOneWidget);
      expect(find.text('调试信息'), findsNothing, reason: '调试收进设置页');
      expect(find.text('退出登录'), findsNothing, reason: '危险操作只在设置页');
    });

    testWidgets('菜单没有外边距，且 120ms 就展开完', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump(); // 起动画
      await tester.pump(const Duration(milliseconds: 140));

      final label = find.text('校准当前周次');
      final card = find
          .ancestor(of: label, matching: find.byType(Material))
          .last;
      final tile = find
          .ancestor(of: label, matching: find.byType(InkWell))
          .first;
      final cardRect = tester.getRect(card);
      final tileRect = tester.getRect(tile);

      expect(
        (tileRect.top - cardRect.top).abs(),
        lessThan(1),
        reason: '上面不该留白',
      );
      expect(
        (tileRect.left - cardRect.left).abs(),
        lessThan(1),
        reason: '左右不该留白',
      );
      expect((cardRect.right - tileRect.right).abs(), lessThan(1));

      final fade = tester.widget<FadeTransition>(
        find.ancestor(of: label, matching: find.byType(FadeTransition)).first,
      );
      expect(fade.opacity.value, 1, reason: '140ms 内必须完全展开（旧实现要 300ms）');
    });

    testWidgets('作息时间表 / 教务地址都能从菜单进到对应页面', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('作息时间表'));
      await tester.pumpAndSettle();
      expect(find.byType(TimetableListPage), findsOneWidget);

      await tester.pageBack();
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('教务地址'));
      await tester.pumpAndSettle();
      expect(find.byType(SchoolAddressPage), findsOneWidget);
    });

    testWidgets('展开动画途中可随时打断（点菜单项或点外部）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // 动画才走一半年，直接点空白处打断收起。
      await tester.tapAt(const Offset(20, 200));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
    });
  });

  group('外观面板', () {
    Future<void> openSheet(WidgetTester tester, AppModel model) async {
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.text('外观'));
      await tester.pumpAndSettle();
    }

    testWidgets('两个滑块，默认值就是当前值', (tester) async {
      final model = buildModel();
      await openSheet(tester, model);

      expect(find.text('课表格子高度'), findsOneWidget);
      expect(find.text('课程文字大小'), findsOneWidget);

      final sliders = tester.widgetList<Slider>(find.byType(Slider)).toList();
      expect(sliders, hasLength(2));
      expect(sliders.first.value, defaultCellHeight);
      expect(sliders.last.value, defaultCourseTextScale);
      expect(find.text('60'), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
    });

    testWidgets('拖滑块改高度与字号，课表在后面实时变大', (tester) async {
      final model = buildModel();
      await openSheet(tester, model);
      final before = tester.getSize(find.byType(CourseBlock).first);

      await tester.drag(find.byType(Slider).first, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(model.cellHeight, greaterThan(defaultCellHeight));

      // 回归：面板没订阅 model 时，值变了但 Slider 自己不重建 → 拇指卡在旧位置。
      final thumb = tester.widget<Slider>(find.byType(Slider).first);
      expect(thumb.value, model.cellHeight, reason: '滑块要跟着走，不能只改背后');

      await tester.drag(find.byType(Slider).last, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(model.courseTextScale, greaterThan(defaultCourseTextScale));

      final after = tester.getSize(find.byType(CourseBlock).first);
      expect(after.height, greaterThan(before.height), reason: '行高变了，格子跟着变高');
    });

    testWidgets('滑块使用圆形滑柄与对齐轨道', (tester) async {
      final model = buildModel();
      await openSheet(tester, model);

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
    });

    testWidgets('恢复默认把两个值都退回默认', (tester) async {
      final model = buildModel();
      await openSheet(tester, model);

      await tester.drag(find.byType(Slider).first, const Offset(80, 0));
      await tester.pumpAndSettle();
      expect(model.cellHeight, isNot(defaultCellHeight));

      await tester.tap(find.text('恢复默认'));
      await tester.pumpAndSettle();

      expect(model.cellHeight, defaultCellHeight);
      expect(model.courseTextScale, defaultCourseTextScale);
    });
  });

  group('dock 按住滑动', () {
    testWidgets('按钮在胶囊里垂直居中，不贴上沿', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      final dock = find.byType(FloatingDock);
      // 胶囊 = dock 里那个带高度和圆角的 Container。
      final capsule = tester.getRect(
        find.descendant(of: dock, matching: find.byType(Container)).first,
      );
      final label = tester.getRect(
        find.descendant(of: dock, matching: find.text('课表')),
      );

      // Stack 默认 topStart，不给 alignment 时整排按钮贴着胶囊上沿，
      // 指示块也就跟着错位（上沿贴住胶囊上沿）。
      expect((label.center.dy - capsule.center.dy).abs(), lessThan(2));
    });

    testWidgets('从课表往右拖到设置，再拖回来', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 0);

      Future<void> dragDock(bool right) async {
        final label = right ? '课表' : '设置';
        final gesture = await tester.startGesture(
          tester.getCenter(
            find.descendant(
              of: find.byType(FloatingDock),
              matching: find.text(label),
            ),
          ),
        );
        await gesture.moveBy(Offset(right ? 30 : -30, 0));
        await tester.pump();
        await gesture.moveBy(Offset(right ? 90 : -90, 0));
        await tester.pump();
        await gesture.up();
        await tester.pumpAndSettle();
      }

      await dragDock(true);
      expect(shellPagePosition(tester), 1, reason: '松手切到设置页');

      await dragDock(false);
      expect(shellPagePosition(tester), 0, reason: '再拖回来');
    });

    testWidgets('dock 拖动过程中页面同步位移（不等到松手）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      final dock = find.byType(FloatingDock);
      final capsule = tester.getRect(
        find.descendant(of: dock, matching: find.byType(Container)).first,
      );
      // 从第一项正中起手，拖到两项正中之间。
      final gesture = await tester.startGesture(
        Offset(capsule.left + capsule.width * 0.25, capsule.center.dy),
      );
      await gesture.moveBy(Offset(capsule.width * 0.25, 0));
      await tester.pump();

      // 还没松手，页面就该已经滑出去一半左右了。
      final double mid = shellPagePosition(tester);
      expect(mid, greaterThan(0.05), reason: '拖动中页面跟着走，不等松手');
      expect(mid, lessThan(0.95), reason: '只拖了一半，不该整页翻过去');

      await gesture.up();
      await tester.pumpAndSettle();
      // 松手后吸附到整页：要么停在课表，要么停在设置，不能停在中间。
      expect(shellCurrentPage(tester), isNot(-1), reason: '松手后吸附到整页');
    });

    testWidgets('dock：点击后指示块落到按钮上，全程不回弹', (tester) async {
      // 锁三件事：
      //  1. 按下时指示块就开始动（页面才有东西可跟）；
      //  2. 松手后落到**按钮**上，而不是停在手指那一点；
      //  3. 全程单调，不会先弹回旧位置（旧实现的 onDragCancel 在"点击赢仲裁"
      //     时会报一次 0，阴影就是那样闪两下的）。
      final progress = <double>[];
      await tester.pumpWidget(
        wrap(
          Center(
            child: FloatingDock(
              index: 0,
              items: const <FloatingDockItem>[
                FloatingDockItem(
                  icon: Icons.grid_view_outlined,
                  activeIcon: Icons.grid_view_rounded,
                  label: '课表',
                ),
                FloatingDockItem(
                  icon: Icons.settings_outlined,
                  activeIcon: Icons.settings_rounded,
                  label: '设置',
                ),
              ],
              onPillProgress: progress.add,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 点在"设置"按钮内、但明显偏离中心的位置。
      final label = tester.getRect(find.text('设置'));
      final gesture = await tester.startGesture(
        Offset(label.left + 4, label.center.dy),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      expect(progress, isNotEmpty, reason: '按下就开始报位置，页面才能跟着走');

      await gesture.up();
      await tester.pumpAndSettle();

      expect(progress.last, 1.0, reason: '松手后落到设置按钮上，不是停在点击处');
      for (var i = 1; i < progress.length; i++) {
        expect(
          progress[i],
          greaterThanOrEqualTo(progress[i - 1] - 1e-6),
          reason: '位置只能往前，不许弹回（第 $i 次：${progress[i - 1]} → ${progress[i]}）',
        );
      }
    });

    testWidgets('按住 dock 不滑动，页面也跟着切过去（不用等拖动）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      final dock = find.byType(FloatingDock);
      final gesture = await tester.startGesture(
        tester.getCenter(find.descendant(of: dock, matching: find.text('设置'))),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));
      expect(
        shellPagePosition(tester),
        greaterThan(0.0),
        reason: '按下的瞬间页面就该开始平移，不能等用户滑一下',
      );

      await tester.pump(const Duration(milliseconds: 300));
      expect(shellPagePosition(tester), 1, reason: '按住不动也会滑到设置页');
      expect(shellCurrentPage(tester), 1);

      // 松手：终态不动（不会因为再报一次目标而重新计一遍动画）。
      await gesture.up();
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 1);
      expect(find.byType(SettingsPage), findsOneWidget);
    });

    testWidgets('内容区的横向手势不切换页面（只有 dock 能切）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      // 在页面**内容区**横向拖一段：不该把课表页换成设置页。
      // 外壳这一层没有注册任何手势（见 _ShellPager 的说明），所以这里的拖动
      // 只会落到内容自己的手势上（课表页内部的翻周）。
      final gesture = await tester.startGesture(
        tester.getCenter(find.text('第 1 周')),
      );
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      await gesture.moveBy(const Offset(-300, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(shellCurrentPage(tester), 0, reason: '内容区横向拖动不能切到设置页');
      expect(find.byType(SettingsPage), findsNothing);
    });

    testWidgets('两页之间是水平平移，不是淡入淡出', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      // 外壳这一层不该再有 Opacity 式的淡入淡出：那是整页离屏合成的开销来源。
      expect(
        find.descendant(
          of: find.byType(HomeShell),
          matching: find.byType(Opacity),
        ),
        findsNothing,
        reason: '两页之间靠位移切换，不该再有透明度渐变',
      );

      // 拖动过程中页面应当停在两页之间 —— 这说明是连续位移，不是瞬间切换。
      //
      // 起手点必须在**左边那一项**上：从"设置"上起手时指示块本来就在右端，
      // 进度已经是 1，"大于 0" 这种断言会白过（它量不到任何位移）。
      final dock = find.byType(FloatingDock);
      final gesture = await tester.startGesture(
        tester.getCenter(find.descendant(of: dock, matching: find.text('课表'))),
      );
      await gesture.moveBy(const Offset(40, 0));
      await tester.pump();
      final double mid = shellPagePosition(tester);
      expect(
        mid,
        allOf(greaterThan(0.0), lessThan(1.0)),
        reason: '往右拖，页面跟着挪到两页之间（不是瞬间切过去）',
      );
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('均分判定：轻微右滑不误切（阈值在胶囊中线）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 0);

      final dock = find.byType(FloatingDock);
      final capsule = tester.getRect(
        find.descendant(of: dock, matching: find.byType(Container)).first,
      );
      // 从胶囊左 1/4 起手，只滑到 45% 处（仍在中线左侧），松手不该切页。
      // 判定按均分点而不是按钮中心：否则滑过左按钮中心就会误判到设置页。
      final start = Offset(
        capsule.left + capsule.width * 0.25,
        capsule.center.dy,
      );
      final gesture = await tester.startGesture(start);
      await gesture.moveBy(Offset(capsule.width * 0.20, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(shellPagePosition(tester), 0, reason: '左半段内松手，仍留在课表');
    });
  });

  group('作息表编辑（保存语义）', () {
    testWidgets('未改动时保存键禁用；改动后可保存并真正写盘', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      final original = model.timetables.first;
      await pushEditor(tester, model, original.id);

      final check = find.widgetWithIcon(IconButton, Icons.check_rounded);
      expect(
        tester.widget<IconButton>(check).onPressed,
        isNull,
        reason: '没改动就不该能保存',
      );

      await tester.tap(find.text('名称'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).last, '夏季作息');
      await tester.tap(find.widgetWithText(FilledButton, '确定'));
      await tester.pumpAndSettle();

      expect(
        model.timetables.any((table) => table.name == '夏季作息'),
        isFalse,
        reason: '只改草稿，还没点保存',
      );
      expect(tester.widget<IconButton>(check).onPressed, isNotNull);

      await tester.tap(check);
      await tester.pumpAndSettle();

      expect(model.timetables.any((table) => table.name == '夏季作息'), isTrue);
      expect(find.byType(TimetableEditPage), findsNothing, reason: '保存后返回列表');
    });

    testWidgets('节次按上午/下午/晚上分组，第 10 节不换行', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await pushEditor(tester, model, model.timetables.first.id);

      expect(find.text('上午'), findsOneWidget);
      expect(find.text('下午'), findsOneWidget);
      expect(find.text('晚上'), findsOneWidget);
      expect(find.textContaining('4 节 · 08:30'), findsOneWidget);

      // 第 10 节在列表底部，滚进视口后应存在，且不能折到第二行。
      await tester.scrollUntilVisible(
        find.text('第 10 节'),
        240,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('第 10 节'), findsOneWidget);
    });

    testWidgets('快捷设置排在节次时间上方', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await pushEditor(tester, model, model.timetables.first.id);

      final quick = tester.getTopLeft(find.text('快捷设置时间')).dy;
      final sections = tester.getTopLeft(find.text('节次时间')).dy;
      expect(quick, lessThan(sections));
    });
  });

  group('课表节数（三段滚轮）', () {
    testWidgets('点开底部滚轮改节数，按确定才生效', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(TimetableListPage(model: model)));

      expect(find.textContaining('共 10 节'), findsOneWidget);
      expect(find.textContaining('上午 4'), findsOneWidget);

      await tester.tap(find.text('课表节数'));
      await tester.pumpAndSettle();

      // 三列滚轮 + 实时合计
      expect(find.text('上午'), findsOneWidget);
      expect(find.text('下午'), findsOneWidget);
      expect(find.text('晚上'), findsOneWidget);
      expect(find.textContaining('共 10 节'), findsWidgets);

      // 上午那一列往上拖一格（itemExtent = 40）→ 5 节
      await tester.drag(find.text('4 节').first, const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(find.textContaining('共 11 节'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '确定'));
      await tester.pumpAndSettle();

      expect(model.sectionCounts[PeriodGroup.morning], 5);
      expect(model.sectionCount, 11);
      expect(
        find.textContaining('共 11 节'),
        findsOneWidget,
        reason: '列表页摘要同步更新',
      );
    });

    testWidgets('取消不改动', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(TimetableListPage(model: model)));

      await tester.tap(find.text('课表节数'));
      await tester.pumpAndSettle();
      await tester.drag(find.text('4 节').first, const Offset(0, -40));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, '取消'));
      await tester.pumpAndSettle();

      expect(model.sectionCount, 10, reason: '没点确定就不该改');
    });
  });

  group('课表页右上角提示', () {
    testWidgets('提示出现时课表仍然可见（不遮挡）', (tester) async {
      final rig = buildModel();
      rig.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        termStart: DateTime(2026, 3, 2),
      );
      // 提示现在挂在外壳上（两页共用），所以这里要用 HomeShell 而不是单页。
      await tester.pumpWidget(wrap(HomeShell(model: rig)));

      rig.setHintForTest('更新中…');
      await tester.pump();

      expect(find.text('更新中…'), findsOneWidget);
      expect(find.text('期初课'), findsOneWidget, reason: '课表不能被遮住');
      expect(find.text('第 1 周'), findsOneWidget);
      rig.clearHint();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('更新中…'), findsNothing);
    });

    testWidgets('提示弹窗宽度跟随文字：短提示紧凑、长提示才扩展到上限', (tester) async {
      final rig = buildModel();
      rig.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        termStart: DateTime(2026, 3, 2),
      );
      await tester.pumpWidget(wrap(HomeShell(model: rig)));

      // AnimatedSwitcher 的尺寸即弹窗尺寸（Stack 包着 _Bubble，宽度取内容宽）。
      Future<double> widthFor(String hint) async {
        rig.setHintForTest(hint);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 250)); // 等切换过渡结束
        return tester.getSize(find.byType(AnimatedSwitcher)).width;
      }

      final shortW = await widthFor('已更新');
      // 先清空再换长文，避免过渡期间 Stack 取新旧最大值干扰测量。
      rig.clearHint();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      final longW = await widthFor('课表更新失败：连接教务系统超时，请检查网络后重试。' * 3);

      // 短提示保持紧凑（远小于 200 上限）；长提示扩展到上限附近。
      expect(shortW, lessThan(200), reason: '短提示不应被撑到接近上限');
      expect(shortW, lessThan(120), reason: '短提示应当紧凑');
      expect(longW, greaterThan(shortW), reason: '长提示应比短提示宽');
      expect(longW, lessThanOrEqualTo(200));
      expect(longW, greaterThan(150), reason: '长提示应扩展到接近上限');
    });
  });

  group('设置页账号区', () {
    testWidgets('只有一个退出入口，并多出修改密码', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SettingsPage(model: model)));

      // 课表组变长后账号区可能被顶到屏外，先滚到可见再断言。
      await tester.dragUntilVisible(
        find.text('退出登录'),
        find.byType(ListView),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();

      expect(find.text('修改密码'), findsOneWidget);
      expect(find.text('退出登录'), findsOneWidget);
      expect(find.text('退出并忘记密码'), findsNothing);
      expect(find.text('退出登录（保留密码）'), findsNothing);
      expect(find.text('忘记密码'), findsNothing);
      expect(find.text('房子洋'), findsOneWidget);
      expect(find.text('未登录'), findsNothing);
    });

    testWidgets('已登录但姓名读不到时显示已登录，而不是未登录', (tester) async {
      final model = buildModel();
      model.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        studentName: '',
        studentId: '',
      );
      await tester.pumpWidget(wrap(SettingsPage(model: model)));

      await tester.dragUntilVisible(
        find.text('已登录'),
        find.byType(ListView),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();

      expect(find.text('未登录'), findsNothing);
      expect(find.text('已登录'), findsOneWidget);
    });

    testWidgets('教务地址一行可点开地址簿', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SettingsPage(model: model)));

      // 设置页课表组变长（静默更新 / 显示备注等开关）后，教务地址可能被顶到屏外，
      // 先滚到可见再点。
      await tester.dragUntilVisible(
        find.text('教务地址'),
        find.byType(ListView),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('教务地址'));
      await tester.pumpAndSettle();
      expect(find.byType(SchoolAddressPage), findsOneWidget);
    });

    testWidgets('展开动画途中可随时打断（点菜单项或点外部）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SchedulePage(model: model)));

      await tester.tap(find.byIcon(Icons.more_horiz_rounded));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));

      // 动画才走一半年，直接点空白处打断收起。
      await tester.tapAt(const Offset(20, 200));
      await tester.pumpAndSettle();
      expect(find.text('校准当前周次'), findsNothing);
    });
  });

  group('教务地址簿页面', () {
    testWidgets('列出已保存地址，标出使用中，可新增', (tester) async {
      final model = buildModel();
      await tester.pumpWidget(wrap(SchoolAddressPage(model: model)));

      expect(find.text('使用中'), findsOneWidget);
      // 出厂就带 6 条线路：底部的"新增"按钮在小屏上要滚一下才可见。
      final addButton = find.widgetWithText(OutlinedButton, '新增教务地址');
      await tester.scrollUntilVisible(
        addButton,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(addButton, findsOneWidget);

      await tester.tap(addButton);
      await tester.pumpAndSettle();
      expect(find.text('新增教务地址'), findsWidgets);
      expect(find.text('添加'), findsOneWidget);

      await tester.enterText(
        find.byType(TextField),
        'https://jw2.example.edu.cn/jwglxt',
      );
      await tester.tap(find.widgetWithText(FilledButton, '添加'));
      await tester.pumpAndSettle();

      expect(model.schools.any((item) => item.contains('jw2')), isTrue);
      expect(find.text('https://jw2.example.edu.cn/jwglxt'), findsOneWidget);
    });

    testWidgets('切换线路时不会闪回登录页：全程停在课表页', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      // 与生产一致地监听状态：根路由是 `pageForStatus(model)`。
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

      // 切线路会沿用当前账号自动登录，先让模型处于"登录过"的状态。
      await model.signIn('2407720102', 'pw');
      await tester.pumpAndSettle();
      expect(find.byType(HomeShell), findsOneWidget);

      final future = model.changeSchool('https://jwglxt5.qust.edu.cn/jwglxt');
      // 逐帧看：换线路的整个过程里，登录页一帧都不许出现。
      for (var i = 0; i < 24; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        expect(
          find.byType(LoginPage),
          findsNothing,
          reason: '第 $i 帧闪了登录页（状态应保持 loading，而不是 needLogin/signingIn）',
        );
      }
      await future;
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsNothing);
      expect(find.byType(HomeShell), findsOneWidget);
      expect(model.schoolBaseUrl, 'https://jwglxt5.qust.edu.cn/jwglxt');

      // 让提示/弹窗里的一次性定时器走完，避免残留 Timer 触发测试框架断言。
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('节次时间（开始+结束一起设）', () {
    testWidgets('点节次行弹出起止滚轮，确定后写回该节', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await pushEditor(tester, model, model.timetables.first.id);

      await tester.tap(find.text('第 1 节'));
      await tester.pumpAndSettle();

      // 两列时间轮：开始 / 结束
      expect(find.text('开始'), findsOneWidget);
      expect(find.text('结束'), findsOneWidget);
      expect(find.textContaining('08:30 – 09:15'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, '确定'));
      await tester.pumpAndSettle();

      // 没改滚动位置，值不变——关键是这条链路能走通且不报错。
      final first = model.timetables.first.sections.first;
      expect(formatClock(first.startMinutes), '08:30');
      expect(formatClock(first.endMinutes), '09:15');
    });

    testWidgets('滚轮接管覆盖整个轮子（否则指哪儿决定滚几格）', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await pushEditor(tester, model, model.timetables.first.id);

      await tester.tap(find.text('第 1 节'));
      await tester.pumpAndSettle();

      // 只挑我们自己挂在候选值上的那几个：`Scrollable` 内部也有一个
      // 带 onPointerSignal 的 Listener（就是它抢走了本该由我们处理的事件）。
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
      expect(wheels, isNotEmpty, reason: '每个候选值都应该挂上滚轮接管');
      for (final listener in wheels) {
        // deferToChild 只有文字本身算命中：鼠标落在选中高亮块上时事件会被
        // Scrollable 吃掉，同一个轮子滚一格还是滚好几格取决于指哪儿。
        expect(listener.behavior, HitTestBehavior.opaque);
      }
    });
  });

  group('调试页', () {
    testWidgets('四个页签都能渲染概览信息', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 3);
      await tester.pumpWidget(wrap(DebugPage(model: model)));

      expect(find.widgetWithText(Tab, '概览'), findsOneWidget);
      expect(find.widgetWithText(Tab, '请求'), findsOneWidget);
      expect(find.widgetWithText(Tab, '原始课表'), findsOneWidget);
      expect(find.widgetWithText(Tab, '解析结果'), findsOneWidget);
      expect(find.text('https://jw.example.edu.cn/jwglxt'), findsOneWidget);
    });

    testWidgets('请求记录：200 的错误页不会被打成"正常"', (tester) async {
      final model = buildModel();
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
      await tester.tap(find.widgetWithText(Tab, '请求'));
      await tester.pumpAndSettle();

      // 状态码是 200，但正文是错误页：标题要带上判定，不能只显示 200 了事。
      expect(find.textContaining('返回错误页'), findsOneWidget);
    });

    testWidgets('原始课表页在未获取时给出明确提示', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(DebugPage(model: model)));

      await tester.tap(find.widgetWithText(Tab, '原始课表'));
      await tester.pumpAndSettle();

      expect(find.text('还没有获取过课表'), findsOneWidget);
    });

    testWidgets('解析结果页列出每条记录与周次', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(DebugPage(model: model)));

      await tester.tap(find.widgetWithText(Tab, '解析结果'));
      await tester.pumpAndSettle();

      expect(find.text('期初课'), findsOneWidget);
      expect(find.textContaining('1-2 周'), findsOneWidget);
    });
  });

  group('新建作息表（点对勾才保存）', () {
    testWidgets('进编辑页时还没进列表，点对勾后才创建', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(TimetableListPage(model: model)));
      final before = model.timetables.length;

      await tester.tap(find.widgetWithText(OutlinedButton, '新建作息表'));
      await tester.pumpAndSettle();

      expect(find.byType(TimetableEditPage), findsOneWidget);
      expect(model.timetables.length, before, reason: '还没点对勾，不该落盘');

      final check = find.widgetWithIcon(IconButton, Icons.check_rounded);
      expect(
        tester.widget<IconButton>(check).onPressed,
        isNotNull,
        reason: '新表一进来就可以直接保存',
      );

      await tester.tap(check);
      await tester.pumpAndSettle();

      expect(model.timetables.length, before + 1);
      expect(find.byType(TimetableEditPage), findsNothing);
    });

    testWidgets('新表未保存就返回：弹确认且不创建', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(TimetableListPage(model: model)));
      final before = model.timetables.length;

      await tester.tap(find.widgetWithText(OutlinedButton, '新建作息表'));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('放弃修改？'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, '放弃'));
      await tester.pumpAndSettle();

      expect(model.timetables.length, before);
      expect(find.byType(TimetableEditPage), findsNothing);
    });
  });

  group('"今"按钮', () {
    testWidgets('看本周时不出现，翻到别的周才浮出来', (tester) async {
      final model = buildModel();
      final today = DateTime.now();
      model.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        termStart: mondayOf(today),
      );
      await tester.pumpWidget(wrap(SchedulePage(model: model)));
      await tester.pumpAndSettle();

      expect(todayFab(tester).opacity, 0, reason: '正在看本周，不需要按钮');

      model.goToWeek(2);
      await tester.pumpAndSettle();
      expect(todayFab(tester).opacity, 1);

      await tester.tap(find.text('今'));
      await tester.pumpAndSettle();
      expect(model.week, 1);
      expect(todayFab(tester).opacity, 0, reason: '回到本周后自动收起');
    });

    testWidgets('翻页动画途中点击"今"能打断动画并回到本周', (tester) async {
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

      // 从第 1 周滑向第 2 周，动画过半但尚未停稳（model.week 仍为 1）。
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
  });

  group('折叠动效', () {
    testWidgets('快捷设置展开是高度动画，不是直接跳变', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await pushEditor(tester, model, model.timetables.first.id);

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

      expect(expanded, greaterThan(collapsed));
      expect(halfway, greaterThan(collapsed));
      expect(halfway, lessThan(expanded), reason: '中途高度应介于起止之间，说明在动画');
    });
  });

  group('页面路由（状态 → 页面）', () {
    testWidgets('登录失败且没拿到课表：留在登录页，错误走弹窗', (tester) async {
      final model = buildModel();
      model.setStatusForTest(
        AppStatus.failed,
        message: '账号或密码不正确',
        code: 'INVALID_CREDENTIALS',
      );

      await tester.pumpWidget(wrap(pageForStatus(model)));
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget, reason: '打错密码不该被丢到空课表');
      expect(find.byType(HomeShell), findsNothing);
      expect(find.text('账号或密码不正确'), findsOneWidget, reason: '错误以弹窗出现');
      expect(
        find.widgetWithText(FilledButton, '重试'),
        findsNothing,
        reason: '没有课表时不该给"重试查课表"',
      );
    });

    testWidgets('已经有课表时失败：留在课表页', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      model.setStatusForTest(
        AppStatus.failed,
        message: '教务页面变了',
        code: 'PAGE_CHANGED',
      );

      await tester.pumpWidget(wrap(pageForStatus(model)));
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget);
      expect(find.text('教务页面变了'), findsOneWidget);
    });

    testWidgets('登录页残留的提示不会变成永远转的圈', (tester) async {
      final model = buildModel();
      model.setHintForTest('登录中…');
      model.setStatusForTest(AppStatus.needLogin, message: '已取消登录');

      await tester.pumpWidget(wrap(pageForStatus(model)));
      // 弹窗若还在转圈，pumpAndSettle 会超时——这就是这条用例的意义。
      await tester.pumpAndSettle();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('登录中…'), findsNothing);
      expect(find.text('已取消登录'), findsOneWidget, reason: '说明性文案留在内联横幅里');
    });

    testWidgets('登录中停在登录页，进度走弹窗', (tester) async {
      final model = buildModel();
      model.setStatusForTest(AppStatus.signingIn);

      await tester.pumpWidget(wrap(pageForStatus(model)));
      await tester.pump();

      expect(find.byType(LoginPage), findsOneWidget);
      expect(find.text('登录中…'), findsOneWidget);
    });
  });

  group('过渡动画可打断', () {
    testWidgets('翻周动画未播完时再点一次「下一周」，两次点击都生效', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      final next = find.widgetWithIcon(IconButton, Icons.chevron_right_rounded);
      await tester.tap(next);
      await tester.pump(); // 动画刚开始，远未结束
      await tester.tap(next);
      await tester.pump();

      // 以前这里有 _syncing 布尔锁，第二次点击会被整个丢掉（只翻一周）。
      expect(model.week, 3);
      await tester.pumpAndSettle();
      expect(model.week, 3);
    });

    testWidgets('切到设置的中途点回课表，动画被接管且终态正确', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();
      expect(shellPagePosition(tester), 0);

      final dock = find.byType(FloatingDock);
      await tester.tap(find.descendant(of: dock, matching: find.text('设置')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60)); // 停在动画中途
      await tester.tap(find.descendant(of: dock, matching: find.text('课表')));
      await tester.pump();
      await tester.pumpAndSettle();

      // 中断后不能停在两页中间（更不该闪回设置页），最终必须干净地回到课表。
      expect(shellPagePosition(tester), 0, reason: '整页滑回课表');
    });
  });
}
