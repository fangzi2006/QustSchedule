/// 界面测试：设置页、作息表编辑、三段节数滚轮、教务地址簿、课程提醒与桌面小组件入口。
library;

import 'dart:async';

import 'package:flutter/cupertino.dart' show CupertinoPicker;
import 'package:flutter/foundation.dart'
    show TargetPlatform, debugDefaultTargetPlatformOverride;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/main.dart' show pageForStatus;
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/login_page.dart';
import 'package:qustschedule/pages/reminder_page.dart';
import 'package:qustschedule/pages/school_address_page.dart';
import 'package:qustschedule/pages/settings_page.dart';
import 'package:qustschedule/pages/timetable_edit_page.dart';
import 'package:qustschedule/pages/timetable_list_page.dart';
import 'package:qustschedule/pages/widget_settings_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/reminder_gateway.dart';
import 'package:qustschedule/src/reminder_planner.dart';
import 'package:qustschedule/src/reminder_service.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:qustschedule/src/widget_service.dart';
import 'package:qustschedule/src/widget_style.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/tactile_button.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';
import 'support/fake_reminder_gateway.dart';
import 'support/fake_widget_gateway.dart';
import 'support/widget_test_helpers.dart';

void main() {
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

  group('设置页账号区与教务地址簿', () {
    testWidgets('设置页账号区展示修改密码与退出登录、姓名空时回退已登录，且可打开教务地址簿', (tester) async {
      final model = buildModel();
      model.hydrateForTest(schedule: sparseSchedule(), week: 1);
      await tester.pumpWidget(wrap(SettingsPage(model: model)));

      await tester.dragUntilVisible(
        find.text('自动检查新版本'),
        find.byType(ListView),
        const Offset(0, -60),
      );
      await tester.pumpAndSettle();
      expect(find.text('自动检查新版本'), findsOneWidget);
      expect(find.text('启动应用时检测是否有新版本安装包'), findsOneWidget);

      await tester.dragUntilVisible(
        find.text('自动同步课表与学业'),
        find.byType(ListView),
        const Offset(0, 80),
      );
      await tester.pumpAndSettle();
      expect(find.text('自动同步课表与学业'), findsOneWidget);
      expect(find.text('打开 App 时自动同步数据'), findsOneWidget);
      expect(find.text('最小同步间隔'), findsOneWidget);

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
      await tester.tap(find.byTooltip('新增地址'));
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

    testWidgets('登录页在当前线路无账号时预填历史登录学号', (tester) async {
      final prefs = Preferences.inMemory(
        lastAccounts: <String, String>{
          'https://legacy.example.edu.cn/jwglxt': '20240999',
        },
      );
      final model = AppModel(
        service: ScheduleService(
          credentials: InMemoryCredentialStore(),
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => FakeBackend(),
          baseUrl: 'https://jw.example.edu.cn/jwglxt',
        ),
        preferences: prefs,
        schoolBaseUrl: 'https://jw.example.edu.cn/jwglxt',
      );
      addTearDown(model.dispose);
      model.setStatusForTest(AppStatus.needLogin);

      await tester.pumpWidget(wrap(LoginPage(model: model)));
      await tester.pumpAndSettle();

      final usernameField = tester.widget<TextFormField>(
        find.byType(TextFormField).first,
      );
      expect(usernameField.controller?.text, '20240999');
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

      await tester.scrollUntilVisible(
        find.text('课程提醒'),
        120,
        scrollable: find.byType(Scrollable).first,
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

      // 2.1 在途同步尚未返回时连续切换胶囊，最后档位必须排队落地不丢失
      final leadGate = Completer<void>();
      rig.gateway.syncGate = leadGate;
      await tester.tap(find.text('15 分钟'));
      await tester.pump();
      await tester.tap(find.text('30 分钟'));
      await tester.pump();
      rig.gateway.syncGate = null;
      leadGate.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 3));
      expect(rig.model.reminderLeadMinutes, 30);
      expect(rig.gateway.lastPayload['leadMinutes'], 30);

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

    testWidgets('提醒页仅保留通知权限检查并在返回后自动刷新权限状态', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final rig = await buildReminderRig(
        enabled: true,
        status: const ReminderRuntimeStatus(autoStartVendorPage: false),
      );
      await tester.pumpWidget(
        wrap(ReminderPage(model: rig.model, service: rig.service)),
      );
      await tester.pumpAndSettle();
      expect(find.text('通知权限'), findsOneWidget);
      expect(find.text('已禁止 · 无法收到任何提醒'), findsOneWidget);
      expect(find.text('忽略电池优化'), findsNothing);
      expect(find.text('自启动'), findsNothing);

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

      expect(find.widgetWithText(TextButton, '去设置'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, '去设置'));
      await tester.pumpAndSettle();
      expect(rig.gateway.notificationSettingsCount, 1);

      rig.service.dispose();
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('设置页「提醒与小组件」板块顺序、权限跳转及返回自动刷新状态', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final rig = await buildReminderRig(
        enabled: true,
        status: const ReminderRuntimeStatus(
          notificationPermission: true,
          notificationsEnabled: true,
          exactAlarmAllowed: false,
          batteryOptimizationIgnored: false,
          autoStartVendorPage: false,
        ),
      );
      final widgetService = DesktopWidgetService(
        model: rig.model,
        gateway: FakeDesktopWidgetGateway(
          pinnedCounts: const <DesktopWidgetKind, int>{
            DesktopWidgetKind.week: 1,
          },
        ),
        debounce: const Duration(seconds: 5),
        now: () => DateTime(2026, 9, 7, 9, 0),
      );
      addTearDown(() {
        widgetService.dispose();
        rig.service.dispose();
        debugDefaultTargetPlatformOverride = null;
      });

      await tester.pumpWidget(
        wrap(
          SettingsPage(
            model: rig.model,
            reminders: rig.service,
            desktopWidgets: widgetService,
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 板块位置：课表 < 提醒与小组件 < 账号
      final scheduleY = tester.getTopLeft(find.text('课表')).dy;
      final sectionY = tester.getTopLeft(find.text('提醒与小组件')).dy;
      final accountY = tester.getTopLeft(find.text('账号')).dy;
      expect(sectionY, greaterThan(scheduleY));
      expect(sectionY, lessThan(accountY));

      // 卡片内顺序：课程提醒 -> 桌面小组件 -> 忽略电池优化 -> 精确闹钟 -> 自启动
      final reminderY = tester.getTopLeft(find.text('课程提醒')).dy;
      final widgetY = tester.getTopLeft(find.text('桌面小组件')).dy;
      final batteryY = tester.getTopLeft(find.text('忽略电池优化')).dy;
      final exactAlarmY = tester.getTopLeft(find.text('精确闹钟')).dy;
      final autostartY = tester.getTopLeft(find.text('自启动')).dy;
      expect(reminderY, lessThan(widgetY));
      expect(widgetY, lessThan(batteryY));
      expect(batteryY, lessThan(exactAlarmY));
      expect(exactAlarmY, lessThan(autostartY));

      expect(find.text('受省电策略限制 · 后台可能被清理'), findsOneWidget);
      expect(find.text('未允许 · 息屏时可能推迟数分钟'), findsOneWidget);
      expect(find.text('该权限不可检测，需自行确认'), findsOneWidget);

      Future<void> tapPermissionAction(String title) async {
        final tile = find.ancestor(
          of: find.text(title),
          matching: find.byType(ListTile),
        );
        await tester.ensureVisible(tile);
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: tile, matching: find.text('去设置')));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 3));
      }

      await tapPermissionAction('忽略电池优化');
      expect(rig.gateway.batterySettingsCount, 1);

      await tapPermissionAction('精确闹钟');
      expect(rig.gateway.exactAlarmSettingsCount, 1);

      await tapPermissionAction('自启动');
      expect(rig.gateway.autostartSettingsCount, 1);
      expect(rig.gateway.toasts, contains('请在设置顶部搜索「自启动」，开启本应用开关'));

      // 模拟开启忽略电池优化并自动开启精确闹钟后切回 App
      rig.gateway.statusValue = const ReminderRuntimeStatus(
        notificationPermission: true,
        notificationsEnabled: true,
        exactAlarmAllowed: true,
        batteryOptimizationIgnored: true,
        autoStartVendorPage: false,
      );
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      expect(find.text('已忽略'), findsOneWidget);
      expect(find.text('已允许'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('桌面小组件', () {
    testWidgets('Android 下设置页显示入口，配置页支持切换类型、套用预设、改字段并安全退出', (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final model = buildModel();
      model.hydrateForTest(
        schedule: sampleSchedule(),
        termStart: DateTime(2026, 9, 7),
        week: 1,
      );
      final gateway = FakeDesktopWidgetGateway(
        pinnedCounts: const <DesktopWidgetKind, int>{DesktopWidgetKind.week: 1},
      );
      final service = DesktopWidgetService(
        model: model,
        gateway: gateway,
        debounce: const Duration(seconds: 5),
        now: () => DateTime(2026, 9, 7, 9, 0),
      );
      addTearDown(() {
        service.dispose();
        model.dispose();
        debugDefaultTargetPlatformOverride = null;
      });

      await tester.pumpWidget(
        wrap(SettingsPage(model: model, desktopWidgets: service)),
      );
      await tester.scrollUntilVisible(
        find.text('桌面小组件'),
        120,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('桌面小组件'), findsOneWidget);

      await tester.tap(find.text('桌面小组件'));
      await tester.pumpAndSettle();
      expect(find.byType(WidgetSettingsPage), findsOneWidget);
      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.textContaining('小窗或分屏'), findsOneWidget);

      // 套用「通透磨砂」只更新今日课表并立即触发原生同步，不影响本周课表
      final beforeSync = gateway.syncCount;
      await tester.tap(find.text('通透磨砂'));
      await tester.pumpAndSettle();
      expect(
        model.widgetStyleOf(DesktopWidgetKind.today).preset,
        WidgetStylePreset.frostedGlass,
      );
      expect(
        model.widgetStyleOf(DesktopWidgetKind.week).preset,
        WidgetStylePreset.minimalWhite,
      );
      expect(gateway.syncCount, greaterThan(beforeSync));

      // 切换到「本周课表」并验证专属「周末列显示」切换
      await tester.tap(find.text('本周课表').first);
      await tester.pumpAndSettle();
      final listScrollable = find.byType(Scrollable).first;
      final weekendOption = find.text('始终显示');
      await tester.scrollUntilVisible(
        weekendOption,
        300,
        scrollable: listScrollable,
      );
      await tester.ensureVisible(weekendOption);
      await tester.pumpAndSettle();
      await tester.tap(weekendOption);
      await tester.pumpAndSettle();
      expect(
        model.widgetStyleOf(DesktopWidgetKind.week).weekendMode,
        WeekendColumnMode.show,
      );

      // 点击添加到桌面（滚回顶部预览卡片）
      final pinBtn = find.text('添加到桌面');
      await tester.scrollUntilVisible(pinBtn, -300, scrollable: listScrollable);
      await tester.ensureVisible(pinBtn);
      await tester.pumpAndSettle();
      await tester.tap(pinBtn);
      await tester.pumpAndSettle();
      expect(gateway.lastPinnedKind, DesktopWidgetKind.week);

      // 返回设置页，再切换为非 Android 平台验证入口隐藏
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(WidgetSettingsPage), findsNothing);

      debugDefaultTargetPlatformOverride = TargetPlatform.windows;
      await tester.pumpWidget(
        wrap(SettingsPage(model: model, desktopWidgets: service)),
      );
      expect(find.text('桌面小组件'), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
