/// 提醒编排层测试：什么时候该下发、什么时候该取消、失败怎么办。
///
/// 全部走 [FakeReminderGateway]，不碰平台通道，也不依赖真实时间。
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/reminder_gateway.dart';
import 'package:qustschedule/src/reminder_planner.dart';
import 'package:qustschedule/src/reminder_service.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';
import 'support/fake_reminder_gateway.dart';

const String _baseUrl = 'https://jw.example.edu.cn/jwglxt';

/// 2026-09-07 是周一，课表第 1 周。
final DateTime _now = DateTime(2026, 9, 7, 6);

AppModel buildModel({Preferences? preferences}) => AppModel(
  service: ScheduleService(
    credentials: InMemoryCredentialStore(),
    cookieStorage: FakeSessionRepository(),
    backendFactory: (_) => FakeBackend(),
    baseUrl: _baseUrl,
  ),
  preferences: preferences,
  schoolBaseUrl: _baseUrl,
);

({AppModel model, FakeReminderGateway gateway, ReminderService service})
buildRig({
  bool enabled = true,
  int lead = 10,
  bool hydrate = true,
  Duration debounce = const Duration(milliseconds: 1),
}) {
  final model = buildModel(
    preferences: Preferences.inMemory(
      reminderEnabled: enabled,
      reminderLeadMinutes: lead,
    ),
  );
  if (hydrate) {
    model.hydrateForTest(
      schedule: sampleSchedule(),
      termStart: DateTime(2026, 9, 7),
      week: 1,
    );
  }
  final gateway = FakeReminderGateway();
  final service = ReminderService(
    model: model,
    gateway: gateway,
    debounce: debounce,
    now: () => _now,
  );
  addTearDown(() {
    service.dispose();
    model.dispose();
  });
  return (model: model, gateway: gateway, service: service);
}

void main() {
  group('同步与指纹', () {
    test('开启且有课表时下发一次，指纹未变不重复下发，force 强制重排', () async {
      final rig = buildRig();
      final result = await rig.service.syncNow();

      expect(result, isNotNull);
      expect(result!.ok, isTrue);
      expect(rig.gateway.syncedPayloads.length, 1);
      // 第 1 周的周一与第 2 周的周一（14 天窗口内）
      expect(rig.gateway.lastEventCount, 2);
      expect(rig.gateway.lastPayload['leadMinutes'], 10);
      expect(rig.service.lastPlan?.fingerprint, isNotEmpty);

      // 指纹没变时不重复下发
      await rig.service.syncNow();
      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 1);

      // force 时忽略指纹，强制重排（force-stop 后恢复靠它）
      await rig.service.syncNow(force: true);
      expect(rig.gateway.syncedPayloads.length, 2);
    });

    test('改提前量或切换形态均更新指纹并重新下发', () async {
      final rig = buildRig();
      await rig.service.syncNow();
      await rig.model.setReminderLeadMinutes(20);
      await rig.service.syncNow();

      expect(rig.gateway.syncedPayloads.length, 2);
      expect(rig.gateway.lastPayload['leadMinutes'], 20);
      expect(rig.gateway.lastPayload['fingerprint'], isNotEmpty);

      await rig.model.setReminderStyle(ReminderStyle.fluid);
      await rig.service.syncNow();

      expect(rig.gateway.syncedPayloads.length, 3);
      expect(rig.gateway.lastPayload['style'], 'fluid');
    });

    test('原生失败时保留指纹不清空，下次还会重试', () async {
      final rig = buildRig();
      rig.gateway.syncResult = const ReminderSyncResult.failure('boom');

      final first = await rig.service.syncNow();
      expect(first?.ok, isFalse);
      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 2, reason: '失败必须重试');

      rig.gateway.syncResult = const ReminderSyncResult(scheduled: 2);
      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 3);
      // 成功后记住指纹，再同步就跳过。
      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 3);
    });
  });

  group('取消', () {
    test('关闭开关或没有课表时取消提醒，且重复取消只调一次原生', () async {
      final rig = buildRig();
      await rig.service.syncNow();
      expect(rig.gateway.cancelCount, 0);

      await rig.model.setReminderEnabled(false);
      final result = await rig.service.syncNow();

      expect(result, isNull);
      expect(rig.gateway.cancelCount, 1);
      expect(rig.gateway.syncedPayloads.length, 1, reason: '关闭后不再下发');

      // 重复同步不会重复调用原生取消
      await rig.service.syncNow();
      expect(rig.gateway.cancelCount, 1);

      // 没有课表时同样取消且幂等
      final noScheduleRig = buildRig(hydrate: false);
      expect(await noScheduleRig.service.syncNow(), isNull);
      await noScheduleRig.service.syncNow();
      expect(noScheduleRig.gateway.cancelCount, 1);
      expect(noScheduleRig.gateway.syncedPayloads, isEmpty);
    });

    test('cancelAll 之后再同步会重新下发（换账号场景）', () async {
      final rig = buildRig();
      await rig.service.syncNow();
      await rig.service.cancelAll();
      expect(rig.gateway.cancelCount, 1);

      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 2);
    });
  });

  group('冷启动保护', () {
    test('偏好还没读到时不动作（不能把默认 false 当用户关闭）', () async {
      final model = buildModel(preferences: null);
      final gateway = FakeReminderGateway();
      final service = ReminderService(model: model, gateway: gateway);
      addTearDown(() {
        service.dispose();
        model.dispose();
      });

      expect(model.preferencesLoaded, isFalse);
      expect(await service.syncNow(), isNull);
      expect(gateway.syncedPayloads, isEmpty);
      expect(gateway.cancelCount, 0);
    });
  });

  group('防抖', () {
    test('连续通知只合并成一次下发', () async {
      final rig = buildRig(debounce: const Duration(milliseconds: 30));
      // 还没有任何下发：这几次通知应当被合并。
      unawaited(rig.model.setShowTeacher(false));
      unawaited(rig.model.setShowLocation(false));
      expect(rig.gateway.syncedPayloads, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(rig.gateway.syncedPayloads.length, 1);
    });
  });

  group('权限与测试提醒', () {
    test('测试提醒与预览提醒按当前形态和提前量派发', () async {
      final rig = buildRig(lead: 25);
      await rig.service.previewReminder();
      expect(rig.gateway.previewRequests, <String>['banner|25|false']);
      expect(rig.gateway.testRequests, isEmpty);
      expect(rig.gateway.syncedPayloads, isEmpty);

      await rig.service.sendTestReminder();
      await rig.model.setReminderStyle(ReminderStyle.fluid);
      await rig.service.sendTestReminder(delaySeconds: 30);

      expect(rig.gateway.testRequests, <String>['banner|60', 'fluid|30']);
    });

    test('stopFluid、打开自启动与权限设置调用会转发并刷新状态', () async {
      final rig = buildRig();
      rig.gateway.autostartVendorPage = true;

      await rig.service.stopFluid();
      expect(await rig.service.openAutostartSettings(), isTrue);
      await rig.service.requestNotificationPermission();
      await rig.service.openNotificationSettings();
      await rig.service.openExactAlarmSettings();
      await rig.service.openBatterySettings();

      expect(rig.gateway.stopFluidCount, 1);
      expect(rig.gateway.autostartSettingsCount, 1);
      expect(rig.gateway.notificationRequests, 1);
      expect(rig.gateway.notificationSettingsCount, 1);
      expect(rig.gateway.exactAlarmSettingsCount, 1);
      expect(rig.gateway.batterySettingsCount, 1);
      expect(rig.gateway.statusCount, 6);
      expect(rig.service.lastStatus, isNotNull);
    });
  });
}
