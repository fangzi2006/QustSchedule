/// 提醒的原生通道抽象。
///
/// 为什么不引 `flutter_local_notifications`：精确闹钟、开机恢复、权限回调
/// 都要原生完全可控，而且本机 pub.dev 不稳。这里只保留一层窄接口——
/// 页面/服务永远不直接碰 `MethodChannel`，测试换成假实现即可。
///
/// 通道方法（`qustschedule/reminder`）：
///  - `sync(payloadJson)`：重排全部提醒并返回结果；
///  - `cancel()`：取消全部（含流体云卡片）；
///  - `status()`：权限、账本、形态与流体云状态；
///  - `requestNotificationPermission()`：申请通知权限（Android 13+）；
///  - `openExactAlarmSettings()`：跳到精确闹钟授权页；
///  - `openBatterySettings()`：跳到应用详情（耗电管理）；
///  - `openAutostartSettings()`：跳到厂商自启动页，跳不动退应用详情；
///  - `testReminder({style, delaySeconds})`：延迟若干秒发一条示例提醒；
///  - `previewReminder({style, leadMinutes})`：不挂闹钟，立刻显示一条示例；
///  - `stopFluid()`：立刻收起流体云卡片。
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 原生侧某次排程的返回值。
class ReminderSyncResult {
  const ReminderSyncResult({
    this.scheduled = 0,
    this.nextTriggerMs,
    this.coverageEndMs,
    this.style = '',
    this.exactAlarmAllowed = false,
    this.error,
  });

  /// 通道不存在 / 原生报错：调用方保留旧 payload，下次再试，不弹错误。
  const ReminderSyncResult.failure(String message)
    : scheduled = 0,
      nextTriggerMs = null,
      coverageEndMs = null,
      style = '',
      exactAlarmAllowed = false,
      error = message;

  final int scheduled;
  final int? nextTriggerMs;
  final int? coverageEndMs;

  /// 实际生效的形态：`banner` 或 `fluid`。
  final String style;

  /// 这次是否用上了精确闹钟（false = 降级成 allow-while-idle）。
  final bool exactAlarmAllowed;

  /// 非空表示这次没排上（通道缺失、权限被拒、payload 非法……）。
  final String? error;

  bool get ok => error == null;

  factory ReminderSyncResult.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const ReminderSyncResult();
    return ReminderSyncResult(
      scheduled: _intOf(map['scheduled']) ?? 0,
      nextTriggerMs: _intOf(map['nextTriggerMs']),
      coverageEndMs: _intOf(map['coverageEndMs']),
      style: (map['style'] as String?) ?? '',
      exactAlarmAllowed: map['exactAlarmAllowed'] == true,
      error: map['error'] as String?,
    );
  }
}

/// 权限与排程现状（诊断卡片、设置页副标题都用它）。
class ReminderRuntimeStatus {
  const ReminderRuntimeStatus({
    this.available = true,
    this.notificationPermission = false,
    this.notificationsEnabled = false,
    this.exactAlarmAllowed = false,
    this.batteryOptimizationIgnored = false,
    this.autoStartVendorPage = false,
    this.scheduled = 0,
    this.nextTriggerMs,
    this.payloadAtMs,
    this.fingerprint = '',
    this.style = '',
    this.fluidCasting = false,
  });

  /// 通道是否可用（桌面端为 false，页面据此提示"仅 Android 支持"）。
  const ReminderRuntimeStatus.unavailable()
    : available = false,
      notificationPermission = false,
      notificationsEnabled = false,
      exactAlarmAllowed = false,
      batteryOptimizationIgnored = false,
      autoStartVendorPage = false,
      scheduled = 0,
      nextTriggerMs = null,
      payloadAtMs = null,
      fingerprint = '',
      style = '',
      fluidCasting = false;

  final bool available;
  final bool notificationPermission;
  final bool notificationsEnabled;
  final bool exactAlarmAllowed;
  final bool batteryOptimizationIgnored;

  /// 本机是否存在可跳转的厂商自启动管理页（ColorOS 12+ 起通常为 false）。
  final bool autoStartVendorPage;

  /// 已排的闹钟条数（原生账本大小）。
  final int scheduled;

  /// 下一条该响的时刻（毫秒）。
  final int? nextTriggerMs;

  /// 原生保存的 payload 生成时刻。
  final int? payloadAtMs;

  final String fingerprint;

  /// 原生记住的形态：`banner` / `fluid`。
  final String style;

  /// 流体云卡片当前是否正在显示。
  final bool fluidCasting;

  /// 通知权限真的到位了吗（Android 13+ 要运行时授权，12- 只看渠道开关）。
  bool get canNotify => notificationPermission && notificationsEnabled;

  /// 电池优化白名单是否已开（没开只影响可靠性，不阻塞）。
  bool get batteryOptOut => batteryOptimizationIgnored;

  factory ReminderRuntimeStatus.fromMap(Map<Object?, Object?>? map) {
    if (map == null) return const ReminderRuntimeStatus.unavailable();
    return ReminderRuntimeStatus(
      notificationPermission: map['notificationPermission'] == true,
      notificationsEnabled: map['notificationsEnabled'] == true,
      exactAlarmAllowed: map['exactAlarmAllowed'] == true,
      batteryOptimizationIgnored: map['batteryOptimizationIgnored'] == true,
      autoStartVendorPage: map['autoStartVendorPage'] == true,
      scheduled: _intOf(map['scheduled']) ?? 0,
      nextTriggerMs: _intOf(map['nextTriggerMs']),
      payloadAtMs: _intOf(map['payloadAtMs']),
      fingerprint: (map['fingerprint'] as String?) ?? '',
      style: (map['style'] as String?) ?? '',
      fluidCasting: map['fluidCasting'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ReminderRuntimeStatus &&
          runtimeType == other.runtimeType &&
          available == other.available &&
          notificationPermission == other.notificationPermission &&
          notificationsEnabled == other.notificationsEnabled &&
          exactAlarmAllowed == other.exactAlarmAllowed &&
          batteryOptimizationIgnored == other.batteryOptimizationIgnored &&
          autoStartVendorPage == other.autoStartVendorPage &&
          scheduled == other.scheduled &&
          nextTriggerMs == other.nextTriggerMs &&
          payloadAtMs == other.payloadAtMs &&
          fingerprint == other.fingerprint &&
          style == other.style &&
          fluidCasting == other.fluidCasting;

  @override
  int get hashCode => Object.hash(
    available,
    notificationPermission,
    notificationsEnabled,
    exactAlarmAllowed,
    batteryOptimizationIgnored,
    autoStartVendorPage,
    scheduled,
    nextTriggerMs,
    payloadAtMs,
    fingerprint,
    style,
    fluidCasting,
  );
}

/// 提醒原生能力的窄接口（生产实现 + 测试假实现都走它）。
abstract class ReminderGateway {
  Future<ReminderSyncResult> sync(String payloadJson);

  Future<void> cancel();

  Future<ReminderRuntimeStatus> status();

  Future<bool> requestNotificationPermission();

  /// 打开应用通知管理页（供用户手动开启横幅与锁屏总开关）。
  Future<void> openNotificationSettings();

  /// 跳到精确闹钟授权页，返回"当前是否已授权"。
  Future<bool> openExactAlarmSettings();

  Future<void> openBatterySettings();

  /// 打开自启动设置，返回是否真的落到厂商自启动页（false = 退到应用详情）。
  ///
  /// 自启动没有公共 API 也不能申请：只能尽力跳厂商页，跳不动就跳应用详情。
  Future<bool> openAutostartSettings();

  /// 延迟发一条示例提醒（走真实闹钟链路），返回是否排上。
  Future<bool> sendTestReminder({required String style, int delaySeconds = 60});

  /// 立刻显示一条示例提醒（**不挂闹钟**），返回是否成功。
  ///
  /// 与 [sendTestReminder] 的区别：这里只验证「文案与形态长什么样」，
  /// 用来预览横幅/流体云，链路是否通畅要看 [sendTestReminder]。
  Future<bool> previewReminder({
    required String style,
    required int leadMinutes,
    bool untilEnd = false,
  });

  /// 立刻收起流体云卡片（用户手动停止或在页面里关掉形态时用）。
  Future<void> stopFluid();

  /// 显示系统级 Toast 提示（跨进程覆盖在系统设置等页面上方）。
  Future<void> showToast(String message, {bool longDuration = false});
}

/// 真实实现：`MethodChannel` + 原生 `ReminderBridge`。
///
/// 所有异常都在这里吞掉并转成"失败结果"——桌面端没有这条通道，
/// 缺插件不该让设置页弹红条，更不该把已排的提醒清掉。
class MethodChannelReminderGateway implements ReminderGateway {
  const MethodChannelReminderGateway();

  static const MethodChannel channel = MethodChannel('qustschedule/reminder');

  @override
  Future<ReminderSyncResult> sync(String payloadJson) async {
    try {
      final raw = await channel.invokeMethod<Map<Object?, Object?>>(
        'sync',
        payloadJson,
      );
      return ReminderSyncResult.fromMap(raw);
    } on MissingPluginException {
      return const ReminderSyncResult.failure('通道不可用');
    } on PlatformException catch (error) {
      return ReminderSyncResult.failure(error.message ?? error.code);
    }
  }

  @override
  Future<void> cancel() async {
    try {
      await channel.invokeMethod<void>('cancel');
    } on MissingPluginException {
      // 桌面端：无事可做。
    } on PlatformException catch (error) {
      debugPrint('提醒取消失败：${error.code}');
    }
  }

  @override
  Future<ReminderRuntimeStatus> status() async {
    try {
      final raw = await channel.invokeMethod<Map<Object?, Object?>>('status');
      return ReminderRuntimeStatus.fromMap(raw);
    } on MissingPluginException {
      return const ReminderRuntimeStatus.unavailable();
    } on PlatformException {
      return const ReminderRuntimeStatus.unavailable();
    }
  }

  @override
  Future<bool> requestNotificationPermission() async {
    try {
      return await channel.invokeMethod<bool>(
            'requestNotificationPermission',
          ) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openNotificationSettings() async {
    try {
      await channel.invokeMethod<void>('openNotificationSettings');
    } on MissingPluginException {
      // 桌面端无通知设置，忽略。
    } on PlatformException {
      // 系统限制或跳转失败，忽略。
    }
  }

  @override
  Future<bool> openExactAlarmSettings() async {
    try {
      return await channel.invokeMethod<bool>('openExactAlarmSettings') ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> openBatterySettings() async {
    try {
      await channel.invokeMethod<void>('openBatterySettings');
    } on MissingPluginException {
      // 桌面端：无事可做。
    } on PlatformException catch (error) {
      debugPrint('打开电池设置失败：${error.code}');
    }
  }

  @override
  Future<bool> openAutostartSettings() async {
    try {
      return await channel.invokeMethod<bool>('openAutostartSettings') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> sendTestReminder({
    required String style,
    int delaySeconds = 60,
  }) async {
    try {
      final epoch = await channel.invokeMethod<int>('testReminder', {
        'style': style,
        'delaySeconds': delaySeconds,
      });
      return epoch != null && epoch > 0;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<bool> previewReminder({
    required String style,
    required int leadMinutes,
    bool untilEnd = false,
  }) async {
    try {
      return await channel.invokeMethod<bool>('previewReminder', {
            'style': style,
            'leadMinutes': leadMinutes,
            'untilEnd': untilEnd,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> stopFluid() async {
    try {
      await channel.invokeMethod<void>('stopFluid');
    } on MissingPluginException {
      // 桌面端：无事可做。
    } on PlatformException catch (error) {
      debugPrint('停止流体云失败：${error.code}');
    }
  }

  @override
  Future<void> showToast(String message, {bool longDuration = false}) async {
    try {
      await channel.invokeMethod<void>('toast', <String, Object?>{
        'message': message,
        'long': longDuration,
      });
    } on MissingPluginException {
      // 桌面端：无事可做。
    } on PlatformException catch (error) {
      debugPrint('显示 Toast 失败：${error.code}');
    }
  }
}

int? _intOf(Object? raw) {
  if (raw is int) return raw;
  if (raw is num) return raw.toInt();
  return null;
}
