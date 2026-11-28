/// 界面测试：周视图课表网格、WeekPager 翻页、课程块预排版、气泡提示与「今」按钮。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderParagraph;
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/main.dart' show pageForStatus;
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/login_page.dart';
import 'package:qustschedule/pages/schedule_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/term_calendar.dart';
import 'package:qustschedule/widgets/course_tile.dart';
import 'package:qustschedule/widgets/floating_dock.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';
import 'support/widget_test_helpers.dart';

void main() {
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
      expect(find.text(' / 共 18 周'), findsOneWidget);
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
      expect(find.text('获取中...'), findsOneWidget);
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

    testWidgets('切校断网失败弹窗点击「重试」：立刻切到加载转圈，恢复网络后成功切换并提示已更新', (tester) async {
      const targetUrl = 'https://jw-target.example.edu.cn/jwglxt';
      final backend = FakeBackend();
      final model = buildModel(backend: backend);
      addTearDown(model.dispose);

      await model.signIn('20240001', 'pw');
      expect(model.status, AppStatus.ready);

      var online = false;
      final loginGate = Completer<void>();
      backend.loginBehavior = (call, creds) async {
        if (!online) {
          throw const AcademicError(ErrorCode.networkRetryable, '网络不可达');
        }
        await loginGate.future;
        backend.cookies = snapshotOf(targetUrl, value: 'retry-ok');
        return const AuthenticatedState(
          studentId: '20240001',
          studentName: '测试学生',
        );
      };

      await model.changeSchool(targetUrl);
      expect(model.status, AppStatus.failed);

      await tester.pumpWidget(wrap(HomeShell(model: model)));
      await tester.pumpAndSettle();

      expect(find.textContaining('切换失败'), findsOneWidget);
      final retryButton = find.widgetWithText(FilledButton, '重试');
      expect(retryButton, findsOneWidget);

      // 恢复网络并点击「重试」，应立刻离开红框进入加载转圈态
      online = true;
      await tester.tap(retryButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(model.status, AppStatus.loading);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 完成登录与课表拉取：切到目标教务，错误弹窗消失并短暂展示「已更新」
      loginGate.complete();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(model.status, AppStatus.ready);
      expect(model.schoolBaseUrl, targetUrl);
      expect(find.textContaining('切换失败'), findsNothing);
      expect(find.text('已更新'), findsOneWidget);

      // 推进 1.5s 定时器让「已更新」自动消失，避免测试退出时残留 pending timer
      await tester.pump(const Duration(seconds: 2));
      await tester.pumpAndSettle();
    });

    testWidgets('有离线课表且触发熔断/会话失效时留在 HomeShell 展示「重新登录」弹窗，点击后才跳登录页', (
      tester,
    ) async {
      final model = buildModel();
      addTearDown(model.dispose);
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      model.setStatusForTest(
        AppStatus.failed,
        message: '自动登录已暂停（多次失败或密码已变更），请重新登录。',
        code: 'SESSION_EXPIRED',
      );

      await tester.pumpWidget(
        wrap(
          ListenableBuilder(
            listenable: model.routeNotifier,
            builder: (context, _) => pageForStatus(model),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(HomeShell), findsOneWidget, reason: '有离线课表时不强踢回登录页');
      expect(find.text('期初课'), findsOneWidget);
      expect(find.text('自动登录已暂停（多次失败或密码已变更），请重新登录。'), findsOneWidget);
      final reloginBtn = find.widgetWithText(FilledButton, '重新登录');
      expect(reloginBtn, findsOneWidget);

      await tester.tap(reloginBtn);
      await tester.pumpAndSettle();
      expect(model.status, AppStatus.needLogin);
      expect(find.byType(LoginPage), findsOneWidget);
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

  group('课表页右上角提示', () {
    testWidgets('提示出现时不遮挡课表，且弹窗宽度跟随文字（短提示紧凑、长提示扩展到上限）', (tester) async {
      final rig = buildModel();
      rig.hydrateForTest(
        schedule: sparseSchedule(),
        week: 1,
        termStart: DateTime(2026, 3, 2),
      );
      await tester.pumpWidget(wrap(HomeShell(model: rig)));

      rig.setHintForTest('更新中...');
      await tester.pump();
      expect(find.text('更新中...'), findsOneWidget);
      expect(find.text('期初课'), findsOneWidget);
      expect(find.text('第 1 周'), findsOneWidget);
      rig.clearHint();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('更新中...'), findsNothing);

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

      rig.setHintForTest('正在重新登录...', scope: HintScope.global);
      await tester.pump();
      expect(find.text('正在重新登录...'), findsOneWidget);
      rig.clearGlobalHint();
      await tester.pump();
      expect(find.text('正在重新登录...'), findsNothing);

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
}
