/// 提醒的编排层：什么时候重算、什么时候下发、什么时候取消。
///
/// 三条纪律：
///  1. **偏好没读到之前不动手**——冷启动时 `reminderEnabled` 还是默认的
///     `false`，此时同步会把用户真正开着的提醒当成"关掉了"而清空闹钟；
///  2. **指纹没变就不重排**——否则每次回到前台都要跟原生来回一趟；
///  3. **原生失败不清数据**——保留旧 payload（旧闹钟还能响），下次再试。
library;

import 'dart:async';

import 'app_model.dart';
import 'reminder_gateway.dart';
import 'reminder_planner.dart';

class ReminderService {
  ReminderService({
    required this.model,
    ReminderGateway? gateway,
    Duration debounce = const Duration(milliseconds: 300),
    DateTime Function()? now,
  }) : _gateway = gateway ?? const MethodChannelReminderGateway(),
       // 命名参数不能以下划线开头，只能显式赋值（不是能写成 this._debounce）。
       // ignore: prefer_initializing_formals
       _debounce = debounce,
       _now = now ?? DateTime.now {
    model.addListener(_onModelChanged);
  }

  final AppModel model;
  final ReminderGateway _gateway;
  final Duration _debounce;
  final DateTime Function() _now;

  Timer? _timer;
  bool _disposed = false;

  /// 已经"取消过"一次：课表没了 / 开关关着时不必每次通知都再调一次原生。
  bool _cancelled = false;

  String? _lastFingerprint;
  ReminderPlan? _lastPlan;
  ReminderSyncResult? _lastResult;
  ReminderRuntimeStatus? _lastStatus;

  /// 最近一次规划结果（诊断页展示覆盖范围）。
  ReminderPlan? get lastPlan => _lastPlan;

  /// 最近一次下发结果。
  ReminderSyncResult? get lastResult => _lastResult;

  /// 最近一次查到的原生状态（页面打开时刷新）。
  ReminderRuntimeStatus? get lastStatus => _lastStatus;

  /// 模型变了：防抖后排一次。
  ///
  /// 课表刷新、改作息、改调课、改开关都会走到这里；300ms 足够把
  /// "连续调整提前量"合并成一次下发（与参考实现一致）。
  void _onModelChanged() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(syncNow()));
  }

  /// 立即同步一次。
  ///
  /// [force] 为 true 时忽略指纹（回到前台、覆盖安装后恢复用）——系统可能在
  /// App 不在时清掉闹钟（force-stop、清后台），指纹相同也必须重排一遍。
  ///
  /// 返回 null 表示这次什么都没做（偏好未加载 / 没开提醒 / 没有课表）。
  Future<ReminderSyncResult?> syncNow({bool force = false}) async {
    if (_disposed) return null;
    _timer?.cancel();
    _timer = null;
    // 冷启动保护：偏好还没读到，默认的 false 不代表用户关掉了提醒。
    if (!model.preferencesLoaded) return null;

    final plan = buildPlan();
    if (plan == null) {
      await _cancelIfNeeded();
      return null;
    }

    if (!force && plan.fingerprint == _lastFingerprint) {
      return _lastResult;
    }

    final result = await _gateway.sync(plan.toPayloadJson());
    if (_disposed) return result;
    _cancelled = false;
    _lastResult = result;
    _lastPlan = plan;
    // 只有真的排上了才记住指纹：失败了下次还得重试。
    if (result.ok) _lastFingerprint = plan.fingerprint;
    return result;
  }

  /// 按当前课表与设置规划一次；条件不足时返回 null（表示应当取消）。
  ///
  /// 抽成公开方法是为了让单测能只验规划、不碰平台通道。
  ReminderPlan? buildPlan() {
    if (!model.preferencesLoaded) return null;
    if (!model.reminderEnabled) return null;
    final schedule = model.schedule;
    final termStart = model.termStart;
    if (schedule == null || termStart == null) return null;
    return planCourseReminders(
      entries: schedule.entries,
      reschedules: model.reschedules,
      termStart: termStart,
      timetables: model.timetables,
      sectionCounts: model.sectionCounts,
      now: _now(),
      leadMinutes: model.reminderLeadMinutes,
      maxWeek: model.maxWeek,
      style: model.reminderStyle,
      fluidUntilEnd: model.reminderFluidUntilEnd,
    );
  }

  Future<void> _cancelIfNeeded() async {
    if (_cancelled) return;
    _cancelled = true;
    _lastFingerprint = null;
    _lastPlan = null;
    _lastResult = null;
    await _gateway.cancel();
  }

  /// 强制取消（退出登录、换账号时用）：无论指纹如何都清一遍。
  Future<void> cancelAll() async {
    _timer?.cancel();
    _timer = null;
    _cancelled = true;
    _lastFingerprint = null;
    _lastPlan = null;
    _lastResult = null;
    await _gateway.cancel();
  }

  /// 查一次原生状态（诊断/权限卡片打开时调用，不进 build 热路径）。
  Future<ReminderRuntimeStatus> refreshStatus() async {
    final status = await _gateway.status();
    if (_disposed) return status;
    _lastStatus = status;
    return status;
  }

  /// 申请通知权限，返回授权结果。
  Future<bool> requestNotificationPermission() async {
    final granted = await _gateway.requestNotificationPermission();
    await refreshStatus();
    return granted;
  }

  /// 跳到精确闹钟授权页，返回"当前是否已授权"。
  Future<bool> openExactAlarmSettings() async {
    final allowed = await _gateway.openExactAlarmSettings();
    await refreshStatus();
    return allowed;
  }

  /// 跳到电池优化设置页（没有返回值，用户自己决定）。
  Future<void> openBatterySettings() async {
    await _gateway.openBatterySettings();
    await refreshStatus();
  }

  /// 打开自启动设置；返回是否真的落到厂商自启动页（false = 应用详情）。
  Future<bool> openAutostartSettings() async {
    final vendor = await _gateway.openAutostartSettings();
    await refreshStatus();
    return vendor;
  }

  /// 延迟发一条测试提醒，验证"闹钟 → 通知"这条链路本身是通的。
  ///
  /// 形态取用户当前设置：开了流体云就测卡片，否则测横幅。
  Future<bool> sendTestReminder({int delaySeconds = 60}) async {
    return _gateway.sendTestReminder(
      style: model.reminderStyle.wireName,
      delaySeconds: delaySeconds,
    );
  }

  /// 立刻显示一条示例提醒，不挂闹钟（诊断页预览形态用）。
  Future<bool> previewReminder() {
    return _gateway.previewReminder(
      style: model.reminderStyle.wireName,
      leadMinutes: model.reminderLeadMinutes,
      untilEnd: model.reminderFluidUntilEnd,
    );
  }

  /// 立刻收起流体云卡片（用户手动停止，或切回横幅后兜底）。
  Future<void> stopFluid() async {
    await _gateway.stopFluid();
    await refreshStatus();
  }

  /// 显示系统级 Toast 提示。
  Future<void> showToast(String message, {bool longDuration = false}) =>
      _gateway.showToast(message, longDuration: longDuration);

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    model.removeListener(_onModelChanged);
  }
}
