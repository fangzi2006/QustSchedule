/// 课表状态、周次翻页、学期校历校准与课表离线缓存控制器。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zf_academic/zf_academic.dart';

import '../reschedule.dart';
import '../schedule_cache.dart';
import '../term_calendar.dart';
import '../timetable.dart';
import 'preferences_controller.dart';

/// 周次通知源：在 [ValueNotifier] 基础上支持同值强制重发。
///
/// 手势翻页途中只改顶栏 `shownWeek`，停稳才回写 `model.week`。
/// 若动画还没停稳（`model.week` 仍等于原周）用户就点「今」或选周切回原周，
/// 目标值与 `_week` 相同；普通 [ValueNotifier] 会忽略同值赋值，这里显式广播。
class WeekNotifier extends ValueNotifier<int> {
  WeekNotifier(super._value);

  /// 强制广播当前周次。
  void notify() => notifyListeners();
}

/// 课表数据与周历状态控制器，继承 [ChangeNotifier] 以便课表顶栏/网格按需监听，
/// 并把高频变更的周次与刷新转圈隔离到独立轻量 [ValueNotifier] 上。
class ScheduleController extends ChangeNotifier {
  ScheduleController({
    required ScheduleCache? scheduleCache,
    required this._prefs,
  }) : _scheduleCache = scheduleCache ?? LateScheduleCache();

  ScheduleCache _scheduleCache;
  ScheduleCache get scheduleCache => _scheduleCache;

  final PreferencesController _prefs;

  /// 课表后台拉取状态独立监听源（仅驱动刷新按钮与课表气泡转圈，不重建课表网格）。
  final ValueNotifier<bool> refreshingNotifier = ValueNotifier<bool>(false);
  bool get refreshing => refreshingNotifier.value;

  /// 正在查看第几周（1-based）。
  int _week = 1;
  int get week => _week;

  /// 周次单独的通知源：翻页与点「今」不重绘课表网格。
  final WeekNotifier weekNotifier = WeekNotifier(1);

  int _maxWeek = 20;
  int get maxWeek => _maxWeek;

  DateTime? _termStart;
  DateTime? get termStart => _termStart;

  DateTime _lastSeenDay = dayOnly(DateTime.now());
  DateTime? _lastFetchedAt;

  Schedule? _schedule;
  Schedule? get schedule => _schedule;

  Terms? _terms;
  Terms? get terms => _terms;

  String _termId = '';
  String get termId => _termId;

  Future<Schedule>? scheduleLoad;
  bool _disposed = false;

  void rebindCache(ScheduleCache cache) {
    _scheduleCache = cache;
  }

  void markLastSeenToday() {
    _lastSeenDay = dayOnly(DateTime.now());
  }

  void setRefreshing(bool value) {
    if (_disposed) return;
    refreshingNotifier.value = value;
  }

  void setTerms(Terms terms, {bool notify = true}) {
    if (_disposed) return;
    _terms = terms;
    if (notify) notifyListeners();
  }

  void applyFetchedSchedule(
    Schedule schedule, {
    required String baseUrl,
    bool resetToTodayIfNeeded = true,
  }) {
    final previousTermId = _termId;
    _schedule = schedule;
    _termId = schedule.termId;
    if (resetToTodayIfNeeded) {
      applyCalendar(
        schedule,
        resetToToday:
            previousTermId.isEmpty || previousTermId != schedule.termId,
      );
    } else {
      applyCalendar(schedule, resetToToday: false);
    }
    unawaited(saveScheduleCache(schedule, baseUrl: baseUrl));
    _lastFetchedAt = DateTime.now();
    notifyListeners();
  }

  void applyCachedSchedule(CachedSchedule cached) {
    _schedule = cached.schedule;
    _termId = cached.schedule.termId;
    _lastFetchedAt = cached.fetchedAt;
    applyCalendar(cached.schedule);
    notifyListeners();
  }

  void applyCaptchaRecoveredSchedule(Schedule schedule) {
    _schedule = schedule;
    _termId = schedule.termId;
    notifyListeners();
  }

  void clearForSchoolReset() {
    _schedule = null;
    _terms = null;
    _termId = '';
    unawaited(_scheduleCache.clear());
    notifyListeners();
  }

  void resetOnSignOut() {
    _schedule = null;
    _terms = null;
    _termId = '';
    notifyListeners();
    unawaited(_scheduleCache.clear());
  }

  void hydrateForTest({
    required Schedule schedule,
    Terms? terms,
    int? week,
    DateTime? termStart,
  }) {
    _schedule = schedule;
    _terms = terms;
    _termId = schedule.termId;
    applyCalendar(schedule);
    if (termStart != null) _termStart = termStart;
    if (week != null) _setWeek(week);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 周次与课表网格计算
  // ---------------------------------------------------------------------------

  String get weekRange =>
      _termStart == null ? '' : weekRangeLabel(_termStart!, _week);

  List<ScheduleEntry> get weekEntries => entriesForWeek(_week);

  List<ScheduleRemark> get scheduleRemarks =>
      _schedule?.remarks ?? const <ScheduleRemark>[];

  RescheduleWeekView rescheduleViewFor(int week) {
    final schedule = _schedule;
    final termStart = _termStart;
    if (schedule == null || termStart == null) {
      return const RescheduleWeekView();
    }
    return rescheduleWeekView(
      schedule.entries,
      _prefs.reschedules,
      termStart,
      week,
      maxWeek: _maxWeek,
    );
  }

  List<ScheduleEntry> entriesForWeek(int week) =>
      rescheduleViewFor(week).entries;

  int get currentWeekOfToday =>
      _termStart == null ? 1 : weekOf(_termStart!, DateTime.now());

  int get _dataMaxPeriod {
    var max = 0;
    for (final entry in _schedule?.entries ?? const <ScheduleEntry>[]) {
      if (entry.endPeriod > max) max = entry.endPeriod;
    }
    return max;
  }

  int get gridSectionCount {
    final dataMax = _dataMaxPeriod;
    return dataMax > _prefs.sectionCount ? dataMax : _prefs.sectionCount;
  }

  bool get hasSectionsBeyondTimetable => _dataMaxPeriod > _prefs.sectionCount;

  SectionTime? _sectionOf(int period) {
    for (final section in _prefs.activeSections) {
      if (section.period == period) return section;
    }
    return null;
  }

  String timeLabelOf(int period) {
    final section = _sectionOf(period);
    if (section == null) return '';
    return '${formatClock(section.startMinutes)}–${formatClock(section.endMinutes)}';
  }

  String startLabelOf(int period) {
    final section = _sectionOf(period);
    return section == null ? '' : formatClock(section.startMinutes);
  }

  String endLabelOf(int period) {
    final section = _sectionOf(period);
    return section == null ? '' : formatClock(section.endMinutes);
  }

  int _clampWeek(int value) =>
      value < 1 ? 1 : (value > _maxWeek ? _maxWeek : value);

  void _setWeek(int week) {
    final int next = _clampWeek(week);
    if (next == _week) return;
    _week = next;
    weekNotifier.value = next;
  }

  void goToWeek(int week) {
    final int next = _clampWeek(week);
    if (next == _week) {
      weekNotifier.notify();
      return;
    }
    _week = next;
    weekNotifier.value = next;
  }

  void nextWeek() => goToWeek(_week + 1);
  void previousWeek() => goToWeek(_week - 1);
  void goToThisWeek() => goToWeek(currentWeekOfToday);

  void applyCalendar(Schedule schedule, {bool resetToToday = true}) {
    final DateTime? previousStart = _termStart;
    var maxWeek = 0;
    for (final entry in schedule.entries) {
      for (final week in entry.weeks) {
        if (week > maxWeek) maxWeek = week;
      }
    }
    _maxWeek = maxWeek > 0 ? maxWeek : 20;

    final saved = _prefs.raw.termStartOf(schedule.termId);
    if (saved != null) {
      _termStart = saved;
    } else {
      final term = _termById(schedule.termId);
      _termStart = estimateTermStart(term ?? _fallbackTerm(schedule.termId));
    }

    if (resetToToday) {
      _setWeek(weekOf(_termStart!, DateTime.now()));
    } else {
      _setWeek(_week);
    }
    if (_termStart != previousStart) _prefs.notifyPrefs();
  }

  Term? _termById(String termId) {
    final terms = _terms;
    if (terms == null) return null;
    for (final term in terms.items) {
      if (term.id == termId) return term;
    }
    return null;
  }

  Term _fallbackTerm(String termId) {
    final match = RegExp(r'^(\d{4})-').firstMatch(termId);
    final year = match == null
        ? DateTime.now().year
        : int.parse(match.group(1)!);
    final semester = termId.endsWith('-2') ? 2 : 1;
    return Term(id: termId, name: termId, year: year, semester: semester);
  }

  Future<void> calibrateCurrentWeek(int week) async {
    final safe = week < 1 ? 1 : week;
    final start = termStartFromWeek(DateTime.now(), safe);
    _termStart = start;
    _maxWeek = safe > _maxWeek ? safe : _maxWeek;
    _setWeek(safe);
    final termId = _termId;
    if (termId.isNotEmpty) {
      await _prefs.raw.setTermStart(termId, start);
    }
    notifyListeners();
    _prefs.notifyPrefs();
  }

  Future<void> resetCalendar() async {
    final termId = _termId;
    if (termId.isEmpty) return;
    final term = _termById(termId) ?? _fallbackTerm(termId);
    _termStart = estimateTermStart(term);
    _setWeek(weekOf(_termStart!, DateTime.now()));
    await _prefs.raw.setTermStart(termId, _termStart!);
    notifyListeners();
    _prefs.notifyPrefs();
  }

  // ---------------------------------------------------------------------------
  // 缓存与生命周期刷新判定
  // ---------------------------------------------------------------------------

  bool shouldSilentRefresh(DateTime fetchedAt) =>
      DateTime.now().difference(fetchedAt) >=
      Duration(minutes: _prefs.autoRefreshIntervalMinutes);

  Future<void> saveScheduleCache(
    Schedule schedule, {
    required String baseUrl,
  }) => _scheduleCache.save(
    CachedSchedule(
      baseUrl: baseUrl,
      schedule: schedule,
      fetchedAt: DateTime.now(),
    ),
  );

  bool syncCalendarDay() {
    final today = dayOnly(DateTime.now());
    if (today == _lastSeenDay) return false;

    final start = _termStart;
    if (start != null) {
      final weekWhenLeft = weekOf(start, _lastSeenDay);
      if (_week == weekWhenLeft) _setWeek(weekOf(start, today));
    }
    _lastSeenDay = today;
    notifyListeners();
    return true;
  }

  bool get shouldRefreshWhenShown => shouldRefreshOnShow(
    autoRefresh: _prefs.autoRefresh,
    refreshing: refreshing,
    hasSchedule: _schedule != null,
    lastFetchedAt: _lastFetchedAt,
    intervalMinutes: _prefs.autoRefreshIntervalMinutes,
  );

  static bool shouldRefreshOnShow({
    required bool autoRefresh,
    required bool refreshing,
    required bool hasSchedule,
    required DateTime? lastFetchedAt,
    required int intervalMinutes,
    DateTime? now,
  }) {
    if (!autoRefresh || refreshing || !hasSchedule) return false;
    final last = lastFetchedAt;
    if (last == null) return true;
    return (now ?? DateTime.now()).difference(last) >=
        Duration(minutes: intervalMinutes);
  }

  void seedLifecycleForTest({DateTime? lastSeenDay, DateTime? lastFetchedAt}) {
    if (lastSeenDay != null) _lastSeenDay = dayOnly(lastSeenDay);
    _lastFetchedAt = lastFetchedAt;
  }

  @override
  void dispose() {
    _disposed = true;
    weekNotifier.dispose();
    refreshingNotifier.dispose();
    super.dispose();
  }
}
