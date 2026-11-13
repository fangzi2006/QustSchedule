/// 应用状态协调器：串联认证会话、课表校历、学业缓存、用户设置与状态气泡五大专职控制器。
///
/// UI 与测试继续通过 [AppModel] 读取状态、发送意图；高频局部状态已隔离到各自的
/// [Listenable] 频道（[routeNotifier]、[hints]、[scheduleState]、[academic]、
/// [prefsNotifier]、[weekNotifier]、[refreshingNotifier]），防止微小的提示或
/// 刷新转圈触发外层外壳与课表网格白刷。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zf_academic/zf_academic.dart';

import 'academic_cache.dart';
import 'academic_service.dart';
import 'preferences_repository.dart';
import 'reminder_planner.dart';
import 'reschedule.dart';
import 'schedule_cache.dart';
import 'schedule_service.dart';
import 'school.dart';
import 'session_repository.dart';
import 'state/academic_controller.dart';
import 'state/auth_session_controller.dart';
import 'state/hint_notice_controller.dart';
import 'state/preferences_controller.dart';
import 'state/schedule_controller.dart';
import 'timetable.dart';
import 'updater/update_flow_controller.dart';
import 'updater/update_models.dart';
import 'updater/update_service.dart';

export 'state/academic_controller.dart';
export 'state/auth_session_controller.dart';
export 'state/hint_notice_controller.dart' show HintNoticeController, HintScope;
export 'state/preferences_controller.dart';
export 'state/schedule_controller.dart' show ScheduleController, WeekNotifier;

enum AppStatus {
  /// 启动中：读快照、试探会话。
  booting,

  /// 需要登录（没有可用会话，或自动重登失败）。
  needLogin,

  /// 手动登录中。
  signingIn,

  /// 等待用户输入验证码。
  needCaptcha,

  /// 正在取课表。
  loading,

  /// 课表就绪。
  ready,

  /// 失败（带文案）。
  failed,
}

class AppModel extends ChangeNotifier {
  AppModel({
    ScheduleService? service,
    SessionRepository? repository,
    CredentialStore? credentials,
    Preferences? preferences,
    ScheduleCache? scheduleCache,
    ExamCache? examCache,
    GradesCache? gradesCache,
    AcademicService? academicService,
    UpdateFlowController? updateFlow,
    String? schoolBaseUrl,
  }) : _repositoryReady = repository != null,
       _preferencesReady = preferences != null,
       _cacheReady = scheduleCache != null,
       _examCacheReady = examCache != null,
       _gradesCacheReady = gradesCache != null,
       _academicServiceReady = academicService != null,
       hints = HintNoticeController() {
    prefs = PreferencesController(
      preferences: preferences,
      updateFlow: updateFlow ?? UpdateFlowController(),
      hints: hints,
      onStateChanged: _notifyStateChanged,
    );
    session = AuthSessionController(
      prefs: prefs,
      onStateChanged: _notifyStateChanged,
      onRouteChanged: _notifyRouteChanged,
      service: service,
      repository: repository,
      credentials: credentials,
      schoolBaseUrl: schoolBaseUrl,
    );
    scheduleState = ScheduleController(
      scheduleCache: scheduleCache,
      prefs: prefs,
    );
    academic = AcademicController(
      service: session.service,
      examCache: examCache ?? LateExamCache(),
      gradesCache: gradesCache ?? LateGradesCache(),
      hints: hints,
      fallbackTermIdReader: () => scheduleState.termId,
      termsReader: () => scheduleState.terms,
      termsSetter: (terms) => scheduleState.setTerms(terms, notify: false),
      isNeedLoginReader: () => _status == AppStatus.needLogin,
      suppressStageHintsSetter: (suppress) => _suppressStageHints = suppress,
      academicService: academicService,
    );
    session.service.captchaHandler = _handleCaptcha;
    session.service.onStage = _onServiceStage;
  }

  final bool _repositoryReady;
  final bool _preferencesReady;
  final bool _cacheReady;
  final bool _examCacheReady;
  final bool _gradesCacheReady;
  final bool _academicServiceReady;

  /// 全局与页面级提示气泡控制器。
  final HintNoticeController hints;

  /// 用户偏好与外观防抖控制器。
  late final PreferencesController prefs;

  /// 登录会话与线路控制器。
  late final AuthSessionController session;

  /// 课表与周历控制器。
  late final ScheduleController scheduleState;

  /// 学业考试成绩控制器。
  late final AcademicController academic;

  /// 顶层页面路由监听源：仅在页面切换条件、登录提示或错误码变化时通知。
  final ChangeNotifier routeNotifier = ChangeNotifier();

  bool _suppressStageHints = false;
  bool _disposed = false;

  AppStatus _status = AppStatus.booting;
  AppStatus get status => _status;

  String _message = '';
  String get message => _message;

  String _errorCode = '';
  String get errorCode => _errorCode;

  void _notifyStateChanged() {
    if (_disposed) return;
    notifyListeners();
  }

  void _notifyRouteChanged() {
    if (_disposed) return;
    routeNotifier.notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 转发到专职控制器（保持外部 API 完全兼容）
  // ---------------------------------------------------------------------------

  ScheduleService get service => session.service;
  AcademicService get academicService => academic.academicService;
  UpdateFlowController get updateFlow => prefs.updateFlow;

  String get academicTermId => academic.academicTermId;
  List<ExamItem> get exams => academic.exams;
  List<GradeItem> get grades => academic.grades;
  GradeStats get gradeStats => academic.gradeStats;
  bool get isNotEvaluated => academic.isNotEvaluated;
  bool get academicLoading => academic.academicLoading;
  String? get academicError => academic.academicError;
  ChangeNotifier get academicNotifier => academic;

  int get storageNoticeEvent => hints.storageNoticeEvent;
  String? get storageNoticeMessage => hints.storageNoticeMessage;

  Schedule? get schedule => scheduleState.schedule;
  Terms? get terms => scheduleState.terms;
  String get termId => scheduleState.termId;
  String get studentName => session.studentName;
  String get studentId => session.studentId;
  CaptchaState? get captcha => session.captcha;

  String get username => session.username;
  set username(String value) => session.username = value;

  String get schoolBaseUrl => session.schoolBaseUrl;

  int get week => scheduleState.week;
  WeekNotifier get weekNotifier => scheduleState.weekNotifier;
  ValueNotifier<int> get prefsNotifier => prefs.prefsNotifier;
  ValueNotifier<bool> get refreshingNotifier =>
      scheduleState.refreshingNotifier;

  int get maxWeek => scheduleState.maxWeek;
  DateTime? get termStart => scheduleState.termStart;
  String get weekRange => scheduleState.weekRange;
  List<ScheduleEntry> get weekEntries => scheduleState.weekEntries;

  RescheduleWeekView rescheduleViewFor(int week) =>
      scheduleState.rescheduleViewFor(week);

  List<ScheduleEntry> entriesForWeek(int week) =>
      scheduleState.entriesForWeek(week);

  int get currentWeekOfToday => scheduleState.currentWeekOfToday;

  bool get signedIn =>
      session.service.sessionInfo?.authenticated == true ||
      scheduleState.schedule != null ||
      session.service.hasCookies;

  // 作息时间表与节数
  List<Timetable> get timetables => prefs.timetables;
  Timetable? get activeTimetable => prefs.activeTimetable;
  Map<PeriodGroup, int> get sectionCounts => prefs.sectionCounts;
  int get sectionCount => prefs.sectionCount;
  Future<void> setSectionCounts(Map<PeriodGroup, int> value) =>
      prefs.setSectionCounts(value);
  List<SectionTime> get activeSections => prefs.activeSections;
  int get timetableSectionCount => sectionCount;
  int get gridSectionCount => scheduleState.gridSectionCount;
  bool get hasSectionsBeyondTimetable =>
      scheduleState.hasSectionsBeyondTimetable;
  String timeLabelOf(int period) => scheduleState.timeLabelOf(period);
  String startLabelOf(int period) => scheduleState.startLabelOf(period);
  String endLabelOf(int period) => scheduleState.endLabelOf(period);
  Future<void> saveTimetables(List<Timetable> tables) =>
      prefs.saveTimetables(tables);
  Future<void> upsertTimetable(Timetable table) => prefs.upsertTimetable(table);
  Future<void> deleteTimetable(String id) => prefs.deleteTimetable(id);
  QuickSetup? get quickSetup => prefs.quickSetup;
  Future<void> saveQuickSetup(QuickSetup setup) => prefs.saveQuickSetup(setup);

  // 课表显示与静默更新设置
  bool get showTeacher => prefs.showTeacher;
  bool get showLocation => prefs.showLocation;
  Future<void> setShowTeacher(bool value) => prefs.setShowTeacher(value);
  Future<void> setShowLocation(bool value) => prefs.setShowLocation(value);
  List<ScheduleRemark> get scheduleRemarks => scheduleState.scheduleRemarks;
  bool get showScheduleRemarks => prefs.showScheduleRemarks;
  bool get showScheduleRemarksSection =>
      showScheduleRemarks && scheduleRemarks.isNotEmpty;
  Future<void> setShowScheduleRemarks(bool value) =>
      prefs.setShowScheduleRemarks(value);
  bool get autoRefresh => prefs.autoRefresh;
  int get autoRefreshIntervalMinutes => prefs.autoRefreshIntervalMinutes;
  Future<void> setAutoRefresh(bool value) => prefs.setAutoRefresh(value);
  Future<void> setAutoRefreshIntervalMinutes(int value) =>
      prefs.setAutoRefreshIntervalMinutes(value);

  // 课前提醒偏好
  bool get preferencesLoaded => prefs.preferencesLoaded;
  bool get reminderEnabled => prefs.reminderEnabled;
  int get reminderLeadMinutes => prefs.reminderLeadMinutes;
  ReminderStyle get reminderStyle => prefs.reminderStyle;
  Future<void> setReminderEnabled(bool value) =>
      prefs.setReminderEnabled(value);
  Future<void> setReminderLeadMinutes(int value) =>
      prefs.setReminderLeadMinutes(value);
  Future<void> setReminderStyle(ReminderStyle value) =>
      prefs.setReminderStyle(value);
  bool get reminderFluidUntilEnd => prefs.reminderFluidUntilEnd;
  Future<void> setReminderFluidUntilEnd(bool value) =>
      prefs.setReminderFluidUntilEnd(value);

  // 软件更新设置
  String get selectedUpdateProxy => prefs.selectedUpdateProxy;
  Future<void> setSelectedUpdateProxy(String value) =>
      prefs.setSelectedUpdateProxy(value);
  String get updateProxyUrl => prefs.updateProxyUrl;
  Future<void> setUpdateProxyUrl(String value) =>
      prefs.setUpdateProxyUrl(value);
  List<String> get customUpdateProxies => prefs.customUpdateProxies;
  List<String> get allUpdateProxies => prefs.allUpdateProxies;
  Future<void> addCustomUpdateProxy(String url) =>
      prefs.addCustomUpdateProxy(url);
  Future<void> removeCustomUpdateProxy(String url) =>
      prefs.removeCustomUpdateProxy(url);
  bool get autoCheckUpdate => prefs.autoCheckUpdate;
  @visibleForTesting
  bool get hasCheckedAutoUpdate => prefs.hasCheckedAutoUpdate;
  void cancelAutoUpdate() => prefs.cancelAutoUpdate();
  void checkAutoUpdate({
    required void Function(UpdateCheckResult result) onHasUpdate,
    UpdateService? updateService,
    Duration initialDelay = const Duration(seconds: 1),
  }) => prefs.checkAutoUpdate(
    onHasUpdate: onHasUpdate,
    updateService: updateService,
    initialDelay: initialDelay,
  );
  Future<void> setAutoCheckUpdate(bool value) =>
      prefs.setAutoCheckUpdate(value);

  // 调课与外观
  List<RescheduleRule> get reschedules => prefs.reschedules;
  Future<RescheduleRule> addReschedule({
    required int fromMonth,
    required int fromDay,
    required int toMonth,
    required int toDay,
  }) => prefs.addReschedule(
    fromMonth: fromMonth,
    fromDay: fromDay,
    toMonth: toMonth,
    toDay: toDay,
  );
  Future<void> removeReschedule(String id) => prefs.removeReschedule(id);
  Future<void> updateReschedule(
    String id, {
    required int fromMonth,
    required int fromDay,
    required int toMonth,
    required int toDay,
  }) => prefs.updateReschedule(
    id,
    fromMonth: fromMonth,
    fromDay: fromDay,
    toMonth: toMonth,
    toDay: toDay,
  );
  double get cellHeight => prefs.cellHeight;
  double get courseTextScale => prefs.courseTextScale;
  void setCellHeight(double value) => prefs.setCellHeight(value);
  void setCourseTextScale(double value) => prefs.setCourseTextScale(value);
  Future<void> flushAppearance() => prefs.flushAppearance();

  // 提示状态
  bool get refreshing => scheduleState.refreshing;
  String get scheduleHint => hints.scheduleHint;
  bool get scheduleHintIsError => hints.scheduleHintIsError;
  String get academicHint => hints.academicHint;
  bool get academicHintIsError => hints.academicHintIsError;
  String get globalHint => hints.globalHint;
  bool get globalHintIsError => hints.globalHintIsError;
  bool get isGlobalPopupActive => hints.isGlobalPopupActive(
    isStatusBusyOrFailed:
        _status == AppStatus.failed ||
        _status == AppStatus.signingIn ||
        _status == AppStatus.loading ||
        _status == AppStatus.booting,
  );
  String get hint => hints.hint;
  bool get hintIsError => hints.hintIsError;
  HintScope get hintScope => hints.hintScope;
  bool get isAcademicUpdateHint => hints.isAcademicUpdateHint;

  // ---------------------------------------------------------------------------
  // 启动编排
  // ---------------------------------------------------------------------------

  Future<void> boot() async {
    _setStatus(AppStatus.booting);
    try {
      final sessionFuture = _repositoryReady
          ? null
          : FileSessionRepository.open();
      final preferencesFuture = _preferencesReady ? null : Preferences.open();
      final cacheFuture = _cacheReady ? null : FileScheduleCache.open();
      final examCacheFuture = _examCacheReady ? null : FileExamCache.open();
      final gradesCacheFuture = _gradesCacheReady
          ? null
          : FileGradesCache.open();

      if (sessionFuture != null) session.rebindRepository(await sessionFuture);
      if (preferencesFuture != null) {
        prefs.rebindOpened(await preferencesFuture);
      } else {
        prefs.markLoaded();
      }
      scheduleState.markLastSeenToday();
      if (cacheFuture != null) scheduleState.rebindCache(await cacheFuture);
      final loadedExamCache = examCacheFuture == null
          ? null
          : await examCacheFuture;
      final loadedGradesCache = gradesCacheFuture == null
          ? null
          : await gradesCacheFuture;
      if (!_academicServiceReady ||
          loadedExamCache != null ||
          loadedGradesCache != null) {
        academic.rebindCaches(
          examCache: loadedExamCache,
          gradesCache: loadedGradesCache,
          academicService: _academicServiceReady
              ? academic.academicService
              : null,
        );
      }

      session.restoreSavedSchoolIfNeeded();
      session.restoreAccount();

      final snapshotFuture = session.service.bootstrap();
      final cachedFuture = scheduleState.scheduleCache.load();
      final snapshot = await snapshotFuture;
      final cached = await cachedFuture;

      if (cached != null && sameSchool(cached.baseUrl, schoolBaseUrl)) {
        _restoreCachedSchedule(cached);
        if (snapshot != null && (studentName.isEmpty || studentId.isEmpty)) {
          unawaited(session.syncIdentityQuietly());
        }
        if (snapshot != null &&
            prefs.autoRefresh &&
            scheduleState.shouldSilentRefresh(cached.fetchedAt)) {
          unawaited(syncSilently());
        }
        return;
      }

      if (snapshot == null) {
        final saved = await session.service.credentials.get(
          session.accountKey(),
        );
        if (saved != null) session.username = saved.username;
        final hasSaved = await session.service.credentials.has(
          session.accountKey(),
        );
        if (!hasSaved) {
          _setStatus(AppStatus.needLogin);
          return;
        }
      }
      await _loadSchedule();
    } catch (error) {
      _fail(error);
    }
  }

  void _restoreCachedSchedule(CachedSchedule cached) {
    scheduleState.applyCachedSchedule(cached);
    _setStatus(AppStatus.ready);
    unawaited(academic.restoreCachedData(cached.schedule.termId));
  }

  // ---------------------------------------------------------------------------
  // 学业、周次与课表刷新编排
  // ---------------------------------------------------------------------------

  void setAcademicTerm(String termId) => academic.setAcademicTerm(termId);

  Future<void> loadAcademicData({
    String? termId,
    bool forceRefresh = false,
    bool showHint = false,
  }) => academic.loadAcademicData(
    termId: termId,
    forceRefresh: forceRefresh,
    showHint: showHint,
  );

  Future<void> refreshAcademicData({bool showHint = true}) =>
      academic.refreshAcademicData(showHint: showHint);

  void goToWeek(int week) => scheduleState.goToWeek(week);
  void nextWeek() => scheduleState.nextWeek();
  void previousWeek() => scheduleState.previousWeek();
  void goToThisWeek() => scheduleState.goToThisWeek();

  Future<void> calibrateCurrentWeek(int week) async {
    await scheduleState.calibrateCurrentWeek(week);
    _notifyStateChanged();
  }

  Future<void> resetCalendar() async {
    await scheduleState.resetCalendar();
    _notifyStateChanged();
  }

  Future<void> syncSilently() =>
      _loadSchedule(background: true, triggerAcademic: true);

  Future<void> refresh() =>
      _loadSchedule(background: true, triggerAcademic: false);

  Future<void> _loadSchedule({
    String? termId,
    bool background = false,
    bool triggerAcademic = false,
  }) async {
    final hasData = scheduleState.schedule != null;
    final silent = background || hasData;

    scheduleState.setRefreshing(true);
    if (silent) {
      hints.showHint('更新中…', scope: HintScope.schedule);
    } else {
      _setStatus(AppStatus.loading);
      hints.showHint('获取中…', scope: HintScope.schedule);
    }

    final loadFuture = session.service.getSchedule(termId: termId);
    scheduleState.scheduleLoad = loadFuture;
    try {
      final fetched = await loadFuture;
      if (_disposed) return;
      scheduleState.applyFetchedSchedule(
        fetched,
        baseUrl: schoolBaseUrl,
        resetToTodayIfNeeded:
            !hasData || scheduleState.termId != fetched.termId,
      );
      scheduleState.setRefreshing(false);
      _setStatus(AppStatus.ready);
      hints.clearGlobalHint();
      if (silent) {
        hints.showHint(
          '已更新',
          clearAfter: const Duration(milliseconds: 1500),
          scope: HintScope.schedule,
        );
      } else {
        hints.clearHint();
      }
      unawaited(_loadTermsQuietly());
      unawaited(session.syncIdentityQuietly());
      if (triggerAcademic && fetched.termId.isNotEmpty) {
        unawaited(academic.syncQuietly(fetched.termId));
      }
    } on AcademicError catch (error) {
      if (_disposed) return;
      scheduleState.setRefreshing(false);
      if (silent) {
        hints.showHint(
          '更新失败：${HintNoticeController.humanizeError(error)}',
          error: true,
          clearAfter: const Duration(seconds: 3),
          scope: HintScope.schedule,
        );
      } else {
        _fail(error);
      }
    } catch (error) {
      if (_disposed) return;
      scheduleState.setRefreshing(false);
      if (silent) {
        hints.showHint(
          '更新失败：$error',
          error: true,
          clearAfter: const Duration(seconds: 3),
          scope: HintScope.schedule,
        );
      } else {
        _fail(error);
      }
    }
  }

  Future<void> _loadTermsQuietly() async {
    try {
      final fetched = await session.service.fetchTerms();
      if (_disposed) return;
      scheduleState.setTerms(fetched);
      _notifyStateChanged();
    } catch (_) {}
  }

  // ---------------------------------------------------------------------------
  // 回到前台生命周期
  // ---------------------------------------------------------------------------

  Future<void> onAppShown() async {
    if (_disposed) return;
    if (scheduleState.syncCalendarDay()) {
      _notifyStateChanged();
      academic.notifyDayChanged();
    }
    if (scheduleState.shouldRefreshWhenShown) {
      await syncSilently();
    }
  }

  @visibleForTesting
  static bool shouldRefreshOnShow({
    required bool autoRefresh,
    required bool refreshing,
    required bool hasSchedule,
    required DateTime? lastFetchedAt,
    required int intervalMinutes,
    DateTime? now,
  }) => ScheduleController.shouldRefreshOnShow(
    autoRefresh: autoRefresh,
    refreshing: refreshing,
    hasSchedule: hasSchedule,
    lastFetchedAt: lastFetchedAt,
    intervalMinutes: intervalMinutes,
    now: now,
  );

  @visibleForTesting
  void seedLifecycleForTest({DateTime? lastSeenDay, DateTime? lastFetchedAt}) =>
      scheduleState.seedLifecycleForTest(
        lastSeenDay: lastSeenDay,
        lastFetchedAt: lastFetchedAt,
      );

  // ---------------------------------------------------------------------------
  // 登录、验证码、切线路、退出
  // ---------------------------------------------------------------------------

  Future<void> signIn(String username, String password) async {
    session.username = username;
    _setStatus(AppStatus.signingIn);
    hints.showHint('登录中…');
    try {
      final state = await session.service.signIn(
        username,
        password,
        remember: true,
      );
      if (_disposed) return;
      await _afterAuth(state);
    } on AcademicError catch (error) {
      _fail(error);
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> submitCaptcha(String code) async {
    if (session.captcha == null) return;
    if (session.hasPendingReloginCaptcha) {
      session.completePendingCaptcha(code);
      _setStatus(AppStatus.signingIn);
      final pending = scheduleState.scheduleLoad;
      if (pending != null) {
        try {
          final fetched = await pending;
          if (_disposed) return;
          scheduleState.applyCaptchaRecoveredSchedule(fetched);
          session.setCaptcha(null);
          _setStatus(AppStatus.ready);
          unawaited(_loadTermsQuietly());
          unawaited(session.syncIdentityQuietly());
        } on AcademicError catch (error) {
          _fail(error);
        } catch (error) {
          _fail(error);
        }
      }
      return;
    }

    _setStatus(AppStatus.signingIn);
    try {
      final state = await session.service.submitCaptcha(code);
      if (_disposed) return;
      await _afterAuth(state);
    } on AcademicError catch (error) {
      _fail(error);
    } catch (error) {
      _fail(error);
    }
  }

  Future<void> _afterAuth(AuthState state) async {
    switch (state) {
      case AuthenticatedState():
        session.setCaptcha(null);
        if (state.studentName.isNotEmpty) {
          session.setIdentity(studentName: state.studentName);
        }
        if (state.studentId.isNotEmpty) {
          session.setIdentity(studentId: state.studentId);
        }
        await prefs.raw.setCurrentSchool(schoolBaseUrl);
        await session.rememberIdentity(
          studentId: studentId.isNotEmpty ? studentId : username,
          studentName: studentName,
        );
        await _loadSchedule();
      case CaptchaState():
        session.setCaptcha(state);
        _setStatus(AppStatus.needCaptcha, message: '请输入验证码');
      case WebLoginState():
        _setStatus(
          AppStatus.failed,
          message: '教务系统要求先完成网页统一认证，暂不支持自动登录',
          code: ErrorCode.webLoginRequired.wire,
        );
    }
  }

  Future<void> refreshCaptcha() async {
    try {
      await session.refreshCaptcha();
    } on AcademicError catch (error) {
      _fail(error);
    }
  }

  void cancelCaptcha() {
    session.cancelCaptcha(
      onCanceled: () => _setStatus(AppStatus.needLogin, message: '已取消登录'),
    );
  }

  Future<void> changeSchool(String baseUrl, {bool relogin = true}) async {
    if (sameSchool(schoolBaseUrl, baseUrl)) return;

    final String account = username;

    if (!relogin) {
      session.switchSchoolTarget(baseUrl);
      scheduleState.clearForSchoolReset();
      unawaited(prefs.raw.setCurrentSchool(baseUrl));
      session.resetIdentityFields();
      session.restoreAccount();
      prefs.notifyPrefs();
      _setStatus(AppStatus.needLogin);
      return;
    }

    final Credentials? saved = account.isEmpty
        ? null
        : await session.service.credentials.get(session.accountKey());
    if (saved == null || saved.password.isEmpty || saved.username.isEmpty) {
      hints.showHint('切换失败：本机没有找到已保存的密码。请在「设置 → 账号」重新登录一次再切换', error: true);
      return;
    }

    final String previousBase = schoolBaseUrl;
    _setStatus(AppStatus.loading, message: '正在切换到「${schoolLabel(baseUrl)}」…');
    session.switchSchoolTarget(baseUrl);
    session.username = account;
    prefs.notifyPrefs();
    unawaited(prefs.raw.setCurrentSchool(baseUrl));
    unawaited(scheduleState.scheduleCache.clear());

    try {
      final AuthState state = await session.service.signIn(
        account,
        saved.password,
        remember: true,
      );
      if (_disposed) return;
      await _afterAuth(state);
    } on AcademicError catch (error) {
      if (_disposed) return;
      session.rollbackSchool(previousBase);
      _setStatus(
        AppStatus.failed,
        message: '切换失败：${HintNoticeController.humanizeError(error)}（仍停留在原线路）',
        code: error.code.wire,
      );
    } catch (error) {
      if (_disposed) return;
      session.rollbackSchool(previousBase);
      _fail(error);
    }
  }

  List<String> get schools => prefs.schoolsWithCurrent(schoolBaseUrl);
  Future<void> addSchool(String url) => prefs.addSchool(url);
  Future<void> removeSchool(String url) => prefs.removeSchool(url);

  @visibleForTesting
  Future<void>? get academicSyncForTest => academic.academicSyncForTest;

  @visibleForTesting
  Future<void>? get identitySyncForTest => session.identitySyncForTest;

  Future<void> changePassword(String newPassword) async {
    final account = session.service.sessionInfo?.username ?? username;
    if (account.isEmpty) {
      throw AcademicError(ErrorCode.validationFailed, '还不知道账号，请先退出后重新登录一次');
    }
    final state = await session.service.signIn(
      account,
      newPassword,
      remember: true,
    );
    if (state is CaptchaState) {
      throw AcademicError(
        ErrorCode.captchaRequired,
        '这所学校登录需要验证码，请退出登录后用验证码登录',
      );
    }
    if (state is! AuthenticatedState) {
      throw AcademicError(ErrorCode.sessionExpired, '新密码没有通过验证');
    }
    session.username = account;
    if (state.studentName.isNotEmpty) {
      session.setIdentity(studentName: state.studentName);
    }
    if (state.studentId.isNotEmpty) {
      session.setIdentity(studentId: state.studentId);
    }
    unawaited(
      session.rememberIdentity(
        studentId: studentId.isNotEmpty ? studentId : account,
        studentName: studentName,
      ),
    );
    _notifyStateChanged();
    prefs.notifyPrefs();
    await _loadSchedule(background: true);
  }

  void retryAfterSessionLoss() {
    session.setCaptcha(null);
    _setStatus(AppStatus.needLogin, message: '会话已过期，请重新登录');
  }

  Future<void> signOut() async {
    await session.signOutReset();
    if (_disposed) return;
    scheduleState.resetOnSignOut();
    academic.resetOnSignOut();
    prefs.notifyPrefs();
    _setStatus(AppStatus.needLogin, message: '已退出登录');
  }

  // ---------------------------------------------------------------------------
  // 调试与测试辅助
  // ---------------------------------------------------------------------------

  List<RequestLog> get requestLog => session.requestLog;
  String? get rawScheduleBody => session.rawScheduleBody;
  List<Map<String, dynamic>> get rawScheduleRows => session.rawScheduleRows;
  String? get rawTermsBody => session.rawTermsBody;
  List<String> get cookieNames => session.cookieNames;
  int get weekEntryCount => weekEntries.length;

  @visibleForTesting
  void hydrateForTest({
    required Schedule schedule,
    Terms? terms,
    String studentName = '测试学生',
    String studentId = '20240001',
    int? week,
    DateTime? termStart,
    List<ExamItem>? exams,
    List<GradeItem>? grades,
    bool isNotEvaluated = false,
  }) {
    final currentScheduleTermId = scheduleState.termId;
    session.hydrateForTest(
      termId: schedule.termId,
      currentScheduleTermId: currentScheduleTermId,
      studentName: studentName,
      studentId: studentId,
    );
    academic.hydrateForTest(
      termId: schedule.termId,
      exams: exams,
      grades: grades,
      isNotEvaluated: isNotEvaluated,
    );
    scheduleState.hydrateForTest(
      schedule: schedule,
      terms: terms,
      week: week,
      termStart: termStart,
    );
    _status = AppStatus.ready;
    _notifyRouteChanged();
    _notifyStateChanged();
  }

  @visibleForTesting
  void setHintForTest(
    String message, {
    bool error = false,
    HintScope scope = HintScope.global,
  }) => hints.showHint(message, error: error, scope: scope);

  @visibleForTesting
  Future<void> loadScheduleForTest() async {
    await _loadSchedule();
    await session.identitySyncForTest;
  }

  @visibleForTesting
  void setStatusForTest(
    AppStatus status, {
    String message = '',
    String code = '',
  }) => _setStatus(status, message: message, code: code);

  @visibleForTesting
  void showAcademicUpdateHintForTest(String message) =>
      hints.showAcademicUpdateHint(message);

  Future<void> clearAcademicDataForDebug() async {
    await academic.clearDataForDebug();
    _notifyStateChanged();
  }

  // ---------------------------------------------------------------------------
  // 内部回调与状态路由
  // ---------------------------------------------------------------------------

  Future<String?> _handleCaptcha(CaptchaState state) => session.handleCaptcha(
    state,
    onNeedCaptcha: () =>
        _setStatus(AppStatus.needCaptcha, message: '自动重登需要验证码'),
  );

  void _onServiceStage(String stage) {
    if (_disposed || _suppressStageHints) return;
    if (stage == ScheduleService.stageRelogin) {
      scheduleState.setRefreshing(true);
      hints.showHint('正在重新登录…', scope: HintScope.global);
    } else if (stage == ScheduleService.stageFetchingSchedule) {
      scheduleState.setRefreshing(true);
      hints.clearGlobalHint();
      final hasData = scheduleState.schedule != null;
      hints.showHint(hasData ? '更新中…' : '获取中…', scope: HintScope.schedule);
    }
  }

  void clearScheduleHint() => hints.clearScheduleHint();
  void clearAcademicHint() => hints.clearAcademicHint();
  void clearGlobalHint() => hints.clearGlobalHint();
  void clearHint([HintScope? scope]) => hints.clearHint(scope);

  void _setStatus(AppStatus status, {String message = '', String code = ''}) {
    _status = status;
    _message = message;
    _errorCode = code;
    _notifyRouteChanged();
    _notifyStateChanged();
  }

  void _fail(Object error) {
    if (_disposed) return;
    final academic = asAcademicError(error);
    scheduleState.setRefreshing(false);
    hints.clearHint();
    _setStatus(
      AppStatus.failed,
      message: HintNoticeController.humanizeError(academic),
      code: academic.code.wire,
    );
  }

  void dismissError() {
    if (_disposed || _status != AppStatus.failed) return;
    if (scheduleState.schedule != null) {
      _setStatus(AppStatus.ready);
    } else {
      _setStatus(AppStatus.needLogin);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    hints.dispose();
    academic.dispose();
    scheduleState.dispose();
    prefs.dispose();
    session.dispose();
    updateFlow.dispose();
    routeNotifier.dispose();
    super.dispose();
  }
}
