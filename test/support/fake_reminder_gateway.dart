/// 假的提醒通道：记录每次调用，让编排逻辑可以离线验证。
///
/// 不碰 `MethodChannel`（测试环境没有原生侧），也不校验 payload 结构——
/// 那是 `reminder_planner_test.dart` 的事。
library;

import 'dart:async';
import 'dart:convert';

import 'package:qustschedule/src/reminder_gateway.dart';

class FakeReminderGateway implements ReminderGateway {
  FakeReminderGateway({
    this.statusValue = const ReminderRuntimeStatus(
      notificationPermission: true,
      notificationsEnabled: true,
      exactAlarmAllowed: true,
      style: 'banner',
    ),
  });

  /// 下一次 `sync` 的返回值；改成 `ReminderSyncResult.failure` 可模拟原生失败。
  ReminderSyncResult syncResult = const ReminderSyncResult(
    scheduled: 3,
    style: 'banner',
    exactAlarmAllowed: true,
  );

  /// `status()` 的返回值，测试可直接改。
  ReminderRuntimeStatus statusValue;

  final List<String> syncedPayloads = <String>[];
  final List<String> testRequests = <String>[];
  final List<String> previewRequests = <String>[];

  int cancelCount = 0;
  int statusCount = 0;
  int notificationRequests = 0;
  int exactAlarmSettingsCount = 0;
  int batterySettingsCount = 0;
  int autostartSettingsCount = 0;
  int stopFluidCount = 0;

  /// `openAutostartSettings()` 的返回值：true = 厂商自启动页。
  bool autostartVendorPage = false;

  /// 最近一次 payload 解出来的事件数（省得每个断言都 jsonDecode）。
  int get lastEventCount {
    if (syncedPayloads.isEmpty) return 0;
    final decoded = jsonDecode(syncedPayloads.last) as Map<String, dynamic>;
    return (decoded['events'] as List<dynamic>).length;
  }

  Map<String, dynamic> get lastPayload =>
      jsonDecode(syncedPayloads.last) as Map<String, dynamic>;

  /// 挂住 `sync`：用于验证"操作进行中界面不该重建/禁用按钮"。
  ///
  /// 置为 `Completer()` 后 `sync` 会一直等，测试再 `complete()` 放行。
  Completer<void>? syncGate;

  @override
  Future<ReminderSyncResult> sync(String payloadJson) async {
    syncedPayloads.add(payloadJson);
    final gate = syncGate;
    if (gate != null) await gate.future;
    return syncResult;
  }

  @override
  Future<void> cancel() async {
    cancelCount++;
  }

  @override
  Future<ReminderRuntimeStatus> status() async {
    statusCount++;
    return statusValue;
  }

  int notificationSettingsCount = 0;

  @override
  Future<bool> requestNotificationPermission() async {
    notificationRequests++;
    return statusValue.notificationPermission;
  }

  @override
  Future<void> openNotificationSettings() async {
    notificationSettingsCount++;
  }

  @override
  Future<bool> openExactAlarmSettings() async {
    exactAlarmSettingsCount++;
    return statusValue.exactAlarmAllowed;
  }

  @override
  Future<void> openBatterySettings() async {
    batterySettingsCount++;
  }

  @override
  Future<bool> sendTestReminder({
    required String style,
    int delaySeconds = 60,
  }) async {
    testRequests.add('$style|$delaySeconds');
    return true;
  }

  @override
  Future<bool> openAutostartSettings() async {
    autostartSettingsCount++;
    return autostartVendorPage;
  }

  @override
  Future<bool> previewReminder({
    required String style,
    required int leadMinutes,
    bool untilEnd = false,
  }) async {
    previewRequests.add('$style|$leadMinutes|$untilEnd');
    return true;
  }

  @override
  Future<void> stopFluid() async {
    stopFluidCount++;
  }

  final List<String> toasts = <String>[];

  @override
  Future<void> showToast(String message, {bool longDuration = false}) async {
    toasts.add(message);
  }
}
