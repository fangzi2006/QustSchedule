/// 桌面小组件的编排服务：监听课表、学业考试与偏好变动，防抖计算快照并同步给原生。
///
/// 遵循与 [ReminderService] 同等级的稳定性纪律：
///  1. `model.preferencesLoaded == false` 前绝不下发，防止冷启动默认值覆盖用户自定义样式；
///  2. 300ms 防抖 + 单飞串行队列 + FNV-1a 指纹去重（滑动/切页零冗余通信）；
///  3. 退出登录时下发未登录空态快照（保留样式，清空课表与考试数据防隐私残留）。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:zf_academic/zf_academic.dart';

import 'app_model.dart';
import 'reschedule.dart';
import 'timetable.dart';
import 'widget_gateway.dart';
import 'widget_planner.dart';
import 'widget_style.dart';

/// 纯 Dart 可跨 Isolate 传递的小组件快照计算入参。
class WidgetSnapshotInput {
  const WidgetSnapshotInput.signedOut({required this.styles, required this.now})
    : signedIn = false,
      termId = '',
      entries = const <ScheduleEntry>[],
      reschedules = const <RescheduleRule>[],
      termStart = null,
      timetables = const <Timetable>[],
      sectionCounts = const <PeriodGroup, int>{},
      maxWeek = 0,
      exams = const <ExamItem>[];

  const WidgetSnapshotInput.signedIn({
    required this.termId,
    required this.entries,
    required this.reschedules,
    required this.termStart,
    required this.timetables,
    required this.sectionCounts,
    required this.maxWeek,
    required this.styles,
    required this.now,
    required this.exams,
  }) : signedIn = true;

  final bool signedIn;
  final String termId;
  final List<ScheduleEntry> entries;
  final List<RescheduleRule> reschedules;
  final DateTime? termStart;
  final List<Timetable> timetables;
  final Map<PeriodGroup, int> sectionCounts;
  final int maxWeek;
  final DesktopWidgetConfigSet styles;
  final DateTime now;
  final List<ExamItem> exams;

  /// 纯函数执行快照计算（无 UI/I/O 依赖，可直接在后台 Isolate 调用）。
  WidgetSnapshot compute() {
    if (!signedIn || termStart == null) {
      return buildSignedOutWidgetSnapshot(styles, now: now);
    }
    return buildWidgetSnapshot(
      termId: termId,
      entries: entries,
      reschedules: reschedules,
      termStart: termStart!,
      timetables: timetables,
      sectionCounts: sectionCounts,
      maxWeek: maxWeek,
      styles: styles,
      now: now,
      exams: exams,
    );
  }
}

class DesktopWidgetService {
  DesktopWidgetService({
    required this.model,
    DesktopWidgetGateway? gateway,
    Duration debounce = const Duration(milliseconds: 300),
    DateTime Function()? now,
  }) : _ownsGateway = gateway == null,
       _gateway = gateway ?? MethodChannelDesktopWidgetGateway(),
       // ignore: prefer_initializing_formals
       _debounce = debounce,
       _nowOverride = now {
    model.addListener(_onChanged);
    model.academicNotifier.addListener(_onChanged);
    model.prefsNotifier.addListener(_onChanged);
  }

  final AppModel model;
  final bool _ownsGateway;
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
  String? _lastPayloadJson;
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

    final sameFingerprint = snapshot.fingerprint == _lastFingerprint;
    if (!force && sameFingerprint) {
      return true;
    }

    // force=true 且指纹未变时直接复用上次已编码的 JSON 字符串，
    // 既省去 UI 线程 ~50KB 二次 jsonEncode，又使原生 WidgetStore 命中 O(1) 原文缓存跳过解析与写盘。
    final payloadJson = (sameFingerprint && _lastPayloadJson != null)
        ? _lastPayloadJson!
        : snapshot.toPayloadJson();
    final ok = await _gateway.syncSnapshot(payloadJson);
    if (_disposed || epoch != _syncEpoch) return ok;
    _lastSnapshot = snapshot;
    if (ok) {
      _lastFingerprint = snapshot.fingerprint;
      _lastPayloadJson = payloadJson;
    }
    return ok;
  }

  /// 采集当前不可变快照计算入参（UI 线程 O(1)），供页面在后台 Isolate 并行计算快照；
  /// `preferencesLoaded == false` 时返回 null。
  WidgetSnapshotInput? captureSnapshotInput() {
    if (!model.preferencesLoaded) return null;
    final now = _now();
    final schedule = model.schedule;
    final termStart = model.termStart;
    if (schedule == null || termStart == null) {
      return WidgetSnapshotInput.signedOut(
        styles: model.widgetConfig,
        now: now,
      );
    }

    // 严格遵守跨学期隔离契约：仅当内存考试实际归属当前课表学期时纳入小组件。
    final exams = model.loadedAcademicTerm == schedule.termId
        ? List<ExamItem>.unmodifiable(model.exams)
        : const <ExamItem>[];

    return WidgetSnapshotInput.signedIn(
      termId: schedule.termId,
      entries: List<ScheduleEntry>.unmodifiable(schedule.entries),
      reschedules: List<RescheduleRule>.unmodifiable(model.reschedules),
      termStart: termStart,
      timetables: List<Timetable>.unmodifiable(model.timetables),
      sectionCounts: Map<PeriodGroup, int>.unmodifiable(model.sectionCounts),
      maxWeek: model.maxWeek,
      styles: model.widgetConfig,
      now: now,
      exams: exams,
    );
  }

  /// 基于当前 [AppModel] 构造桌面小组件快照；`preferencesLoaded == false` 时返回 null。
  WidgetSnapshot? buildSnapshot() => captureSnapshotInput()?.compute();

  /// 强制清空原生快照并复位指纹记忆。
  Future<void> clearAll() async {
    _syncEpoch++;
    _resyncQueued = false;
    _resyncForceQueued = false;
    _timer?.cancel();
    _timer = null;
    _lastFingerprint = null;
    _lastPayloadJson = null;
    _lastSnapshot = null;
    final active = _syncInFlight;
    if (active != null) {
      try {
        await active;
      } catch (_) {}
    }
    await _gateway.clearSnapshot();
  }

  Future<bool> requestPinWidget(DesktopWidgetKind kind) =>
      _gateway.requestPinWidget(kind);

  Future<Map<DesktopWidgetKind, int>> getPinnedCounts() =>
      _gateway.getPinnedCounts();

  /// 原生广播/Pin 成功回调实时推送的最新桌面实例数量。
  ValueListenable<Map<DesktopWidgetKind, int>?> get livePinnedCounts =>
      _gateway.livePinnedCounts;

  /// 确保已挂载桌面实例变更推送处理器。
  Future<void> ensureLivePinnedUpdates() =>
      _disposed ? Future<void>.value() : _gateway.ensureLivePinnedUpdates();

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _timer = null;
    model.removeListener(_onChanged);
    model.academicNotifier.removeListener(_onChanged);
    model.prefsNotifier.removeListener(_onChanged);
    if (_ownsGateway) {
      final gateway = _gateway;
      if (gateway is MethodChannelDesktopWidgetGateway) {
        gateway.dispose();
      }
    }
  }
}
