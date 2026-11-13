/// 偏好设置、外观调节防抖、课前提醒偏好与自动更新配置控制器。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app_version.dart';
import '../preferences_repository.dart';
import '../reminder_planner.dart';
import '../reschedule.dart';
import '../school.dart';
import '../timetable.dart';
import '../updater/update_flow_controller.dart';
import '../updater/update_models.dart';
import '../updater/update_service.dart';
import 'hint_notice_controller.dart';

/// 管理用户设置持久化、外观滑块草稿防抖、存储故障温和提示以及更新代理配置。
class PreferencesController {
  PreferencesController({
    required Preferences? preferences,
    required this._updateFlow,
    required this._hints,
    required this._onStateChanged,
  }) : _preferences = preferences ?? Preferences.inMemory(),
       _preferencesLoaded = preferences != null {
    attachStorageMonitor();
  }

  Preferences _preferences;
  Preferences get raw => _preferences;

  final UpdateFlowController _updateFlow;
  UpdateFlowController get updateFlow => _updateFlow;

  final HintNoticeController _hints;
  final VoidCallback _onStateChanged;

  bool _preferencesLoaded;

  /// 偏好是否已经从磁盘读到（冷启动未读到前，提醒服务禁止用默认值清空闹钟）。
  bool get preferencesLoaded => _preferencesLoaded;

  /// 偏好设置独立通知源，仅供设置页/课表网格/提醒服务按需监听。
  final ValueNotifier<int> prefsNotifier = ValueNotifier<int>(0);

  bool _reportedWriteFailure = false;
  bool _disposed = false;

  double? _cellHeightDraft;
  double? _courseTextScaleDraft;
  Timer? _appearanceTimer;

  bool _hasCheckedAutoUpdate = false;
  Timer? _autoUpdateTimer;

  bool get hasCheckedAutoUpdate => _hasCheckedAutoUpdate;

  void notifyPrefs() {
    if (_disposed) return;
    prefsNotifier.value++;
  }

  void attachStorageMonitor() {
    _preferences.onWriteSuccess = () {
      _reportedWriteFailure = false;
    };
    _preferences.onWriteError = (_) {
      if (_disposed || _reportedWriteFailure) return;
      _reportedWriteFailure = true;
      _hints.emitStorageNotice('本地设置保存失败，请检查存储空间');
    };
  }

  void rebindOpened(Preferences loaded) {
    _preferences = loaded;
    attachStorageMonitor();
    if (_preferences.didResetFromCorruption) {
      _hints.emitStorageNotice('本地设置文件已损坏且无法恢复，已重置为默认设置');
    }
    _preferencesLoaded = true;
  }

  void markLoaded() {
    _preferencesLoaded = true;
  }

  Future<void> _commitPref(
    Future<void> Function() write, {
    bool syncProxy = false,
    bool notifyPrefsChanged = true,
  }) async {
    final flushing = write();
    if (syncProxy) syncUpdateProxy();
    _onStateChanged();
    if (notifyPrefsChanged) notifyPrefs();
    await flushing;
  }

  // ---------------------------------------------------------------------------
  // 作息时间表与节数
  // ---------------------------------------------------------------------------

  List<Timetable> get timetables => _preferences.timetables;

  Timetable? get activeTimetable => _preferences.activeTimetable();

  Map<PeriodGroup, int> get sectionCounts => _preferences.sectionCounts;

  int get sectionCount => _preferences.sectionCount;

  Future<void> setSectionCounts(Map<PeriodGroup, int> value) =>
      _commitPref(() => _preferences.setSectionCounts(value));

  List<SectionTime> get activeSections => reconcileSections(
    activeTimetable?.sections ?? const <SectionTime>[],
    sectionCounts,
  );

  Future<void> saveTimetables(List<Timetable> tables) =>
      _commitPref(() => _preferences.saveTimetables(tables));

  Future<void> upsertTimetable(Timetable table) async {
    final list = _preferences.timetables;
    final index = list.indexWhere((item) => item.id == table.id);
    if (index >= 0) {
      list[index] = table;
    } else {
      list.add(table);
    }
    await saveTimetables(list);
  }

  Future<void> deleteTimetable(String id) async {
    final rest = _preferences.timetables
        .where((item) => item.id != id)
        .toList();
    if (rest.isEmpty) return;
    await saveTimetables(rest);
  }

  QuickSetup? get quickSetup => _preferences.quickSetup;

  Future<void> saveQuickSetup(QuickSetup setup) => _commitPref(
    () => _preferences.setQuickSetup(setup),
    notifyPrefsChanged: false,
  );

  // ---------------------------------------------------------------------------
  // 课表显示开关与静默更新
  // ---------------------------------------------------------------------------

  bool get showTeacher => _preferences.showTeacher;
  bool get showLocation => _preferences.showLocation;
  bool get showScheduleRemarks => _preferences.showScheduleRemarks;
  bool get autoRefresh => _preferences.autoRefresh;
  int get autoRefreshIntervalMinutes => _preferences.autoRefreshIntervalMinutes;

  Future<void> setShowTeacher(bool value) async {
    if (_preferences.showTeacher == value) return;
    await _commitPref(() => _preferences.setShowTeacher(value));
  }

  Future<void> setShowLocation(bool value) async {
    if (_preferences.showLocation == value) return;
    await _commitPref(() => _preferences.setShowLocation(value));
  }

  Future<void> setShowScheduleRemarks(bool value) async {
    if (_preferences.showScheduleRemarks == value) return;
    await _commitPref(() => _preferences.setShowScheduleRemarks(value));
  }

  Future<void> setAutoRefresh(bool value) async {
    if (_preferences.autoRefresh == value) return;
    await _commitPref(() => _preferences.setAutoRefresh(value));
  }

  Future<void> setAutoRefreshIntervalMinutes(int value) async {
    final safe = clampAutoRefreshIntervalMinutes(value);
    if (_preferences.autoRefreshIntervalMinutes == safe) return;
    await _commitPref(() => _preferences.setAutoRefreshIntervalMinutes(safe));
  }

  // ---------------------------------------------------------------------------
  // 课前提醒偏好
  // ---------------------------------------------------------------------------

  bool get reminderEnabled => _preferences.reminderEnabled;
  int get reminderLeadMinutes => _preferences.reminderLeadMinutes;
  ReminderStyle get reminderStyle => _preferences.reminderStyle;
  bool get reminderFluidUntilEnd => _preferences.reminderFluidUntilEnd;

  Future<void> setReminderEnabled(bool value) async {
    if (_preferences.reminderEnabled == value) return;
    await _commitPref(() => _preferences.setReminderEnabled(value));
  }

  Future<void> setReminderLeadMinutes(int value) async {
    final safe = clampReminderLead(value);
    if (_preferences.reminderLeadMinutes == safe) return;
    await _commitPref(() => _preferences.setReminderLeadMinutes(safe));
  }

  Future<void> setReminderStyle(ReminderStyle value) async {
    if (_preferences.reminderStyle == value) return;
    await _commitPref(() => _preferences.setReminderStyle(value));
  }

  Future<void> setReminderFluidUntilEnd(bool value) async {
    if (_preferences.reminderFluidUntilEnd == value) return;
    await _commitPref(() => _preferences.setReminderFluidUntilEnd(value));
  }

  // ---------------------------------------------------------------------------
  // 调课规则
  // ---------------------------------------------------------------------------

  List<RescheduleRule> get reschedules => _preferences.reschedules;

  Future<RescheduleRule> addReschedule({
    required int fromMonth,
    required int fromDay,
    required int toMonth,
    required int toDay,
  }) async {
    final rule = RescheduleRule(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      fromMonth: fromMonth,
      fromDay: fromDay,
      toMonth: toMonth,
      toDay: toDay,
    );
    await _commitPref(
      () => _preferences.saveReschedules(<RescheduleRule>[
        ..._preferences.reschedules,
        rule,
      ]),
    );
    return rule;
  }

  Future<void> removeReschedule(String id) async {
    final rest = _preferences.reschedules
        .where((rule) => rule.id != id)
        .toList();
    if (rest.length == _preferences.reschedules.length) return;
    await _commitPref(() => _preferences.saveReschedules(rest));
  }

  Future<void> updateReschedule(
    String id, {
    required int fromMonth,
    required int fromDay,
    required int toMonth,
    required int toDay,
  }) async {
    final updated = <RescheduleRule>[];
    var changed = false;
    for (final rule in _preferences.reschedules) {
      if (rule.id == id) {
        updated.add(
          RescheduleRule(
            id: id,
            fromMonth: fromMonth,
            fromDay: fromDay,
            toMonth: toMonth,
            toDay: toDay,
          ),
        );
        changed = true;
      } else {
        updated.add(rule);
      }
    }
    if (!changed) return;
    await _commitPref(() => _preferences.saveReschedules(updated));
  }

  // ---------------------------------------------------------------------------
  // 外观草稿与防抖落盘
  // ---------------------------------------------------------------------------

  double get cellHeight => _cellHeightDraft ?? _preferences.cellHeight;
  double get courseTextScale =>
      _courseTextScaleDraft ?? _preferences.courseTextScale;

  void setCellHeight(double value) {
    final safe = clampCellHeight(value);
    if (safe == cellHeight) return;
    _cellHeightDraft = safe;
    _onStateChanged();
    notifyPrefs();
    _flushAppearanceSoon();
  }

  void setCourseTextScale(double value) {
    final safe = clampCourseTextScale(value);
    if (safe == courseTextScale) return;
    _courseTextScaleDraft = safe;
    _onStateChanged();
    notifyPrefs();
    _flushAppearanceSoon();
  }

  Future<void> flushAppearance() async {
    _appearanceTimer?.cancel();
    _appearanceTimer = null;
    if (_cellHeightDraft == null && _courseTextScaleDraft == null) return;
    if (_cellHeightDraft != null) {
      await _preferences.setCellHeight(_cellHeightDraft!);
    }
    if (_courseTextScaleDraft != null) {
      await _preferences.setCourseTextScale(_courseTextScaleDraft!);
    }
  }

  void _flushAppearanceSoon() {
    _appearanceTimer?.cancel();
    _appearanceTimer = Timer(const Duration(milliseconds: 300), () {
      _appearanceTimer = null;
      unawaited(flushAppearance());
    });
  }

  // ---------------------------------------------------------------------------
  // 更新设置与自动检查
  // ---------------------------------------------------------------------------

  String get selectedUpdateProxy => _preferences.selectedUpdateProxy;
  String get updateProxyUrl => _preferences.updateProxyUrl;
  List<String> get customUpdateProxies => _preferences.customUpdateProxies;
  List<String> get allUpdateProxies => _preferences.allUpdateProxies;
  bool get autoCheckUpdate => _preferences.autoCheckUpdate;

  void syncUpdateProxy() {
    _updateFlow.updateProxySelection(
      selectedProxy: selectedUpdateProxy,
      backupProxies: allUpdateProxies,
    );
  }

  Future<void> setSelectedUpdateProxy(String value) async {
    if (_preferences.selectedUpdateProxy == value.trim()) return;
    await _commitPref(
      () => _preferences.setSelectedUpdateProxy(value),
      syncProxy: true,
    );
  }

  Future<void> setUpdateProxyUrl(String value) async {
    if (_preferences.updateProxyUrl == value.trim()) return;
    await _commitPref(
      () => _preferences.setUpdateProxyUrl(value),
      syncProxy: true,
    );
  }

  Future<void> addCustomUpdateProxy(String url) => _commitPref(
    () => _preferences.addCustomUpdateProxy(url),
    syncProxy: true,
  );

  Future<void> removeCustomUpdateProxy(String url) => _commitPref(
    () => _preferences.removeCustomUpdateProxy(url),
    syncProxy: true,
  );

  Future<void> setAutoCheckUpdate(bool value) async {
    if (_preferences.autoCheckUpdate == value) return;
    await _commitPref(() => _preferences.setAutoCheckUpdate(value));
  }

  void cancelAutoUpdate() {
    _autoUpdateTimer?.cancel();
    _autoUpdateTimer = null;
  }

  void checkAutoUpdate({
    required void Function(UpdateCheckResult result) onHasUpdate,
    UpdateService? updateService,
    Duration initialDelay = const Duration(seconds: 1),
  }) {
    if (_hasCheckedAutoUpdate || !autoCheckUpdate || _disposed) return;

    var retryCount = 0;
    late void Function(Duration delay) scheduleCheck;

    Future<void> executeCheck() async {
      if (_hasCheckedAutoUpdate || !autoCheckUpdate || _disposed) return;
      UpdateService? ownedService;
      try {
        final service = updateService ?? (ownedService = UpdateService());
        final result = await service.checkForUpdatesWithFallback(
          currentVersion: appVersion,
          selectedProxy: selectedUpdateProxy,
          backupProxies: allUpdateProxies,
        );
        if (_hasCheckedAutoUpdate || !autoCheckUpdate || _disposed) return;

        if (result.status == UpdateStatus.hasUpdate) {
          _hasCheckedAutoUpdate = true;
          if (result.release != null) {
            _updateFlow.setAvailableUpdate(
              result: result,
              selectedProxy: selectedUpdateProxy,
              backupProxies: allUpdateProxies,
            );
            onHasUpdate(result);
          }
        } else if (result.status == UpdateStatus.noUpdate) {
          _hasCheckedAutoUpdate = true;
        } else if (result.status == UpdateStatus.networkError) {
          if (retryCount < 2) {
            retryCount++;
            scheduleCheck(const Duration(seconds: 2));
          } else {
            _hasCheckedAutoUpdate = true;
          }
        } else {
          _hasCheckedAutoUpdate = true;
        }
      } catch (_) {
        if (_hasCheckedAutoUpdate || !autoCheckUpdate || _disposed) return;
        if (retryCount < 2) {
          retryCount++;
          scheduleCheck(const Duration(seconds: 2));
        } else {
          _hasCheckedAutoUpdate = true;
        }
      } finally {
        ownedService?.dispose();
      }
    }

    scheduleCheck = (Duration delay) {
      _autoUpdateTimer?.cancel();
      if (delay == Duration.zero) {
        unawaited(executeCheck());
      } else {
        _autoUpdateTimer = Timer(delay, executeCheck);
      }
    };

    scheduleCheck(initialDelay);
  }

  // ---------------------------------------------------------------------------
  // 教务地址簿转发
  // ---------------------------------------------------------------------------

  List<String> schoolsWithCurrent(String currentBaseUrl) {
    final saved = _preferences.schools;
    if (saved.any((item) => sameSchool(item, currentBaseUrl))) return saved;
    return <String>[currentBaseUrl, ...saved];
  }

  Future<void> addSchool(String url) =>
      _commitPref(() => _preferences.addSchool(url));

  Future<void> removeSchool(String url) =>
      _commitPref(() => _preferences.removeSchool(url));

  void dispose() {
    _disposed = true;
    cancelAutoUpdate();
    _appearanceTimer?.cancel();
    unawaited(flushAppearance());
    prefsNotifier.dispose();
  }
}
