/// 桌面小组件的编排服务：监听课表、学业考试与偏好变动，防抖计算快照并同步给原生。
///
/// 遵循与 [ReminderService] 同等级的稳定性纪律：
///  1. `model.preferencesLoaded == false` 前绝不下发，防止冷启动默认值覆盖用户自定义样式；
///  2. 300ms 防抖 + 单飞串行队列 + FNV-1a 指纹去重（滑动/切页零冗余通信）；
///  3. 退出登录时下发未登录空态快照（保留样式，清空课表与考试数据防隐私残留）。
library;

import 'dart:async';

import 'package:zf_academic/zf_academic.dart';

import 'app_model.dart';
import 'widget_gateway.dart';
import 'widget_planner.dart';
import 'widget_style.dart';

class DesktopWidgetService {
  DesktopWidgetService({
    required this.model,
    DesktopWidgetGateway? gateway,
    Duration debounce = const Duration(milliseconds: 300),
    DateTime Function()? now,
  }) : _gateway = gateway ?? const MethodChannelDesktopWidgetGateway(),
       // ignore: prefer_initializing_formals
       _debounce = debounce,
       _nowOverride = now {
    model.addListener(_onChanged);
    model.academicNotifier.addListener(_onChanged);
    model.prefsNotifier.addListener(_onChanged);
  }

  final AppModel model;
  final DesktopWidgetGateway _gateway;
  final Duration _debounce;
  final DateTime Function()? _nowOverride;

  DateTime _now() => (_nowOverride ?? DateTime.now)();

  Timer? _timer;
  bool _disposed = false;
  Future<bool>? _syncInFlight;
  bool _resyncQueued = false;
  bool _resyncForceQueued = false;
  int _syncEpoch = 0;

  String? _lastFingerprint;
  WidgetSnapshot? _lastSnapshot;

  WidgetSnapshot? get lastSnapshot => _lastSnapshot;

  void _onChanged() {
    if (_disposed) return;
    _timer?.cancel();
    _timer = Timer(_debounce, () => unawaited(syncNow()));
  }

  /// 立即同步一次桌面小组件快照。
  ///
  /// [force] 为 `true` 时忽略指纹去重（如回到前台、覆盖安装后兜底刷新）。
  Future<bool> syncNow({bool force = false}) {
    if (_disposed) return Future<bool>.value(false);
    _timer?.cancel();
    _timer = null;

    final active = _syncInFlight;
    if (active != null) {
      _resyncQueued = true;
      _resyncForceQueued = _resyncForceQueued || force;
      return active;
    }

    final future = _runSyncLoop(force);
    _syncInFlight = future;
    return future;
  }

  Future<bool> _runSyncLoop(bool initialForce) async {
    var force = initialForce;
    var ok = false;
    try {
      while (!_disposed) {
        _resyncQueued = false;
        _resyncForceQueued = false;
        ok = await _syncOnce(force: force);
        if (!_resyncQueued || _disposed) break;
        force = _resyncForceQueued;
      }
      return ok;
    } finally {
      _syncInFlight = null;
      _resyncQueued = false;
      _resyncForceQueued = false;
    }
  }

  Future<bool> _syncOnce({required bool force}) async {
    if (_disposed || !model.preferencesLoaded) return false;
    final epoch = _syncEpoch;
    final snapshot = buildSnapshot();
    if (snapshot == null) return false;

    if (!force && snapshot.fingerprint == _lastFingerprint) {
      return true;
    }

    final ok = await _gateway.syncSnapshot(snapshot.toPayloadJson());
    if (_disposed || epoch != _syncEpoch) return ok;
    _lastSnapshot = snapshot;
    if (ok) {
      _lastFingerprint = snapshot.fingerprint;
    }
    return ok;
  }

  /// 基于当前 [AppModel] 构造桌面小组件快照；`preferencesLoaded == false` 时返回 null。
  WidgetSnapshot? buildSnapshot() {
    if (!model.preferencesLoaded) return null;
    final now = _now();
    final schedule = model.schedule;
    final termStart = model.termStart;
    if (schedule == null || termStart == null) {
      return buildSignedOutWidgetSnapshot(model.widgetConfig, now: now);
    }

    // 严格遵守跨学期隔离契约：仅当内存考试实际归属当前课表学期时纳入小组件。
    final exams = model.loadedAcademicTerm == schedule.termId
        ? model.exams
        : const <ExamItem>[];

    return buildWidgetSnapshot(
      termId: schedule.termId,
      entries: schedule.entries,
      reschedules: model.reschedules,
      termStart: termStart,
      timetables: model.timetables,
      sectionCounts: model.sectionCounts,
      maxWeek: model.maxWeek,
      styles: model.widgetConfig,
      now: now,
      exams: exams,
    );
  }

  /// 强制清空原生快照并复位指纹记忆。
  Future<void> clearAll() async {
    _syncEpoch++;
    _resyncQueued = false;
    _resyncForceQueued = false;
    _timer?.cancel();
    _timer = null;
    _lastFingerprint = null;
    _lastSnapshot = null;
    await _gateway.clearSnapshot();
  }

  Future<bool> requestPinWidget(DesktopWidgetKind kind) =>
      _gateway.requestPinWidget(kind);

  Future<Map<DesktopWidgetKind, int>> getPinnedCounts() =>
      _gateway.getPinnedCounts();

  /// 若底层为原生 MethodChannel，确保已挂载桌面实例变更推送处理器。
  void ensureLivePinnedUpdates() {
    final gateway = _gateway;
    if (gateway is MethodChannelDesktopWidgetGateway) {
      gateway.ensurePushHandlerInstalled();
    }
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    model.removeListener(_onChanged);
    model.academicNotifier.removeListener(_onChanged);
    model.prefsNotifier.removeListener(_onChanged);
  }
}
