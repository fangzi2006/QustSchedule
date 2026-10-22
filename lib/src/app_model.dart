/// 应用状态机：UI 只跟这里读状态、发意图，不直接碰教务客户端。
///
/// 与模块错误码一一对应（不允许"其他错误弹个 toast"这种黑洞）：
///  - SESSION_EXPIRED    → 引导重新登录（自动重登失败或没有保存密码时）；
///  - CAPTCHA_REQUIRED   → 验证码页；
///  - WEB_LOGIN_REQUIRED → 明确提示"该学校需要网页统一认证，暂不支持"；
///  - INVALID_CREDENTIALS→ 账号或密码不正确；
///  - NETWORK_RETRYABLE  → 网络问题，可重试；
///  - PAGE_CHANGED       → 页面结构变化，建议反馈；
///  - UNSUPPORTED        → 账号没有课表权限。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zf_academic/zf_academic.dart';

import 'schedule_service.dart';
import 'school.dart';
import 'session_repository.dart';
import 'credentials_repository.dart';
import 'preferences_repository.dart';
import 'reschedule.dart';
import 'schedule_cache.dart';
import 'term_calendar.dart';
import 'timetable.dart';

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
    String? schoolBaseUrl,
  }) : _schoolBaseUrl = schoolBaseUrl ?? defaultSchool.baseUrl,
       // 构造时显式给了地址（测试注入）就别被设置里的"上次用的学校"覆盖。
       _schoolFixed = schoolBaseUrl != null,
       service =
           service ??
           ScheduleService(
             credentials: credentials ?? SecureCredentialStore(),
             // path_provider 的目录要异步取；boot() 注入真实实现。
             cookieStorage: repository ?? LateSessionRepository(),
           ),
       _repositoryReady = repository != null,
       _preferences = preferences ?? Preferences.inMemory(),
       _preferencesReady = preferences != null,
       _scheduleCache = scheduleCache ?? LateScheduleCache(),
       _cacheReady = scheduleCache != null {
    // 自动回登遇到验证码时由状态机挂起、UI 输入（见 _handleCaptcha）。
    this.service.captchaHandler = _handleCaptcha;
    // 编排层进入"重新登录"阶段时，把右上角提示语换掉（仍不遮挡课表）。
    this.service.onStage = _onServiceStage;
  }

  final ScheduleService service;
  final bool _repositoryReady;

  /// 用户设置。构造时先给内存实现，`boot()` 时替换为落盘实现。
  Preferences _preferences;
  final bool _preferencesReady;

  /// 课表本地缓存（课表 + 抓取时间）。同样在 `boot()` 时替换为落盘实现。
  ScheduleCache _scheduleCache;
  final bool _cacheReady;

  AppStatus _status = AppStatus.booting;
  AppStatus get status => _status;

  String _message = '';
  String get message => _message;

  String _errorCode = '';
  String get errorCode => _errorCode;

  /// 上次"看见"的日期（只到天）。回到前台时拿它比对，发现跨天就重建一次界面。
  ///
  /// 课表页的表头日期与"今天"高亮都是 build 时按 `DateTime.now()` 现算的，
  /// 所以一次 `notifyListeners` 就够——但没人通知的话，App 在后台过夜后
  /// 回到前台会一直显示昨天的日期。
  DateTime _lastSeenDay = dayOnly(DateTime.now());

  /// 上次成功抓到课表的时刻。`null` = 本次进程还没成功抓过、也不知道缓存时间。
  DateTime? _lastFetchedAt;

  Schedule? _schedule;
  Schedule? get schedule => _schedule;

  Terms? _terms;
  Terms? get terms => _terms;

  String _termId = '';
  String get termId => _termId;

  String _studentName = '';
  String get studentName => _studentName;

  String _studentId = '';
  String get studentId => _studentId;

  CaptchaState? _captcha;
  CaptchaState? get captcha => _captcha;

  String _username = '';
  String get username => _username;
  set username(String value) {
    _username = value;
    notifyListeners();
  }

  String _schoolBaseUrl;
  final bool _schoolFixed;
  String get schoolBaseUrl => _schoolBaseUrl;

  // ---------------------------------------------------------------------------
  // 周次（周视图的核心状态）
  // ---------------------------------------------------------------------------

  /// 正在查看第几周（1-based）。
  int _week = 1;
  int get week => _week;

  /// 周次单独的通知源。
  ///
  /// 周次是"看哪一页"，不是课表内容：改它不该把整张课表重建一次（实测一次
  /// 整页重建 60ms+，而翻页落稳、点箭头、选周都会改周次）。所以它走自己的
  /// notifier —— 只有顶栏、右下角按钮和翻页逻辑监听它，课表网格不监听。
  final ValueNotifier<int> weekNotifier = ValueNotifier<int>(1);

  /// 设置当前周次。
  ///
  /// **不**发 `notifyListeners()`：内容没变，整页重建是白花的钱。
  /// 需要重建界面（例如校准改了开学日）的地方自己另外通知。
  void _setWeek(int week) {
    final int next = _clampWeek(week);
    if (next == _week) return;
    _week = next;
    weekNotifier.value = next;
  }

  /// 偏好设置（显示教师/地点、静默更新、外观…）单独的通知源。
  ///
  /// 设置页只关心这些。原先它听的是整个 model，于是**任何**通知都会让它整页
  /// 重建一次（实测 21~26ms）：后台刷新一次课表，用户在设置页里就白重建一遍。
  ///
  /// 走自己的 notifier 后，设置页只在偏好真的变了时重建。
  final ValueNotifier<int> prefsNotifier = ValueNotifier<int>(0);

  /// 偏好变了：通知设置页（以及任何只关心偏好的界面）。
  ///
  /// 计数递增即可——监听方只需要知道"变了"，不需要知道变成了什么。
  void _notifyPrefs() {
    prefsNotifier.value++;
  }

  /// 本学期实际有课的最大周次（课表里出现过的最晚周）。
  int _maxWeek = 20;
  int get maxWeek => _maxWeek;

  /// 第 1 周的周一。null 表示还没定位（未加载课表）。
  DateTime? _termStart;
  DateTime? get termStart => _termStart;

  /// 以周一为一周之始的日期文案，给周次条用。
  String get weekRange =>
      _termStart == null ? '' : weekRangeLabel(_termStart!, _week);

  /// 这一周要上的课（已按周次过滤，并叠加调课规则）。
  List<ScheduleEntry> get weekEntries => entriesForWeek(_week);

  /// 某一周的调课渲染视图：要显示的课 + 每天的调课冲突（被顶掉、未显示的原课）。
  ///
  /// 调课只在这里叠加，`_schedule.entries` 始终是教务返回的原样。
  RescheduleWeekView rescheduleViewFor(int week) {
    final schedule = _schedule;
    final termStart = _termStart;
    if (schedule == null || termStart == null) {
      return const RescheduleWeekView();
    }
    return rescheduleWeekView(
      schedule.entries,
      _preferences.reschedules,
      termStart,
      week,
      maxWeek: _maxWeek,
    );
  }

  /// 某一周实际渲染的课（= 调课视图的 entries）。
  List<ScheduleEntry> entriesForWeek(int week) =>
      rescheduleViewFor(week).entries;

  /// 今天按当前校准落在第几周（用于"回到本周"）。
  int get currentWeekOfToday =>
      _termStart == null ? 1 : weekOf(_termStart!, DateTime.now());

  /// 是否已有可用会话（设置页据此区分"已登录 / 未登录"）。
  ///
  /// 不能用 `studentName.isEmpty` 判断：Cookie 免登时客户端并不知道"我是谁"，
  /// 课表能取但姓名是空的——那正是"能看课表却显示未登录"的原因。
  bool get signedIn =>
      service.sessionInfo?.authenticated == true ||
      _schedule != null ||
      service.hasCookies;

  // ---------------------------------------------------------------------------
  // 作息时间表（课表左侧时间轴与网格行数的来源）
  // ---------------------------------------------------------------------------

  /// 全部时间表（按生效日倒序）。
  List<Timetable> get timetables => _preferences.timetables;

  /// 今天生效的时间表。null 表示还没配置（理论上不会：迁移时会补默认表）。
  Timetable? get activeTimetable => _preferences.activeTimetable();

  /// 课表节数（**全局设置**，所有作息表共用）：上午 / 下午 / 晚上各几节。
  Map<PeriodGroup, int> get sectionCounts => _preferences.sectionCounts;

  /// 总节数 = 三段之和。
  int get sectionCount => _preferences.sectionCount;

  /// 改全局节数。每张表读取时会按段自动对齐，课表行数跟着变。
  Future<void> setSectionCounts(Map<PeriodGroup, int> value) async {
    await _preferences.setSectionCounts(value);
    notifyListeners();
    _notifyPrefs();
  }

  /// 当前生效表对齐到全局节数后的节次（时间轴读它，保证行数一致）。
  List<SectionTime> get activeSections => reconcileSections(
    activeTimetable?.sections ?? const <SectionTime>[],
    sectionCounts,
  );

  /// 时间表配了多少节（等于全局节数，保留给外部读）。
  int get timetableSectionCount => sectionCount;

  /// 数据里出现过的最大节次。
  int get _dataMaxPeriod {
    var max = 0;
    for (final entry in _schedule?.entries ?? const <ScheduleEntry>[]) {
      if (entry.endPeriod > max) max = entry.endPeriod;
    }
    return max;
  }

  /// 课表网格行数 = max(时间表节数, 数据最大节次)。
  ///
  /// 取大值是为了**不丢课**：如果教务出现第 11 节而时间表只配了 10 节，
  /// 严格按时间表渲染会把那节课直接藏掉。宁可多一行并标注。
  int get gridSectionCount {
    final dataMax = _dataMaxPeriod;
    return dataMax > sectionCount ? dataMax : sectionCount;
  }

  /// 数据里有课超出时间表节数（UI 据此给"未在时间表中"的提示）。
  bool get hasSectionsBeyondTimetable => _dataMaxPeriod > sectionCount;

  /// 某节的起止时间文案，例如 `08:00–08:45`。没有这一节时返回空串。
  String timeLabelOf(int period) {
    final section = _sectionOf(period);
    if (section == null) return '';
    return '${formatClock(section.startMinutes)}–${formatClock(section.endMinutes)}';
  }

  /// 某节的开始时间文案（时间轴主标签）。
  String startLabelOf(int period) {
    final section = _sectionOf(period);
    return section == null ? '' : formatClock(section.startMinutes);
  }

  /// 某节的结束时间文案（时间轴第三行）。没有这一节时返回空串。
  String endLabelOf(int period) {
    final section = _sectionOf(period);
    return section == null ? '' : formatClock(section.endMinutes);
  }

  SectionTime? _sectionOf(int period) {
    for (final section in activeSections) {
      if (section.period == period) return section;
    }
    return null;
  }

  /// 保存整份时间表集合（增删改统一走这里）。
  Future<void> saveTimetables(List<Timetable> tables) async {
    await _preferences.saveTimetables(tables);
    notifyListeners();
    _notifyPrefs();
  }

  /// 新增或按 id 覆盖一张表。
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

  /// 删除一张表。最后一张不允许删（否则课表没有作息可读）。
  Future<void> deleteTimetable(String id) async {
    final rest = _preferences.timetables
        .where((item) => item.id != id)
        .toList();
    if (rest.isEmpty) return;
    await saveTimetables(rest);
  }

  /// 上次填的快捷设置（面板回填用）。
  QuickSetup? get quickSetup => _preferences.quickSetup;

  Future<void> saveQuickSetup(QuickSetup setup) async {
    await _preferences.setQuickSetup(setup);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 课表格子显示哪些信息
  // ---------------------------------------------------------------------------

  /// 课格里是否显示教师名。
  bool get showTeacher => _preferences.showTeacher;

  /// 课格里是否显示上课地点。
  bool get showLocation => _preferences.showLocation;

  Future<void> setShowTeacher(bool value) async {
    await _preferences.setShowTeacher(value);
    notifyListeners();
    _notifyPrefs();
  }

  Future<void> setShowLocation(bool value) async {
    await _preferences.setShowLocation(value);
    notifyListeners();
    _notifyPrefs();
  }

  /// 当前课表的"备注"（实践课程 / 其他课程，来自 `sjkList`）。没有则为空。
  List<ScheduleRemark> get scheduleRemarks =>
      _schedule?.remarks ?? const <ScheduleRemark>[];

  /// 是否在课表页下方显示备注。
  bool get showScheduleRemarks => _preferences.showScheduleRemarks;

  /// 是否真的显示备注区：有备注 **且** 开关打开。空备注时区不占地方。
  bool get showScheduleRemarksSection =>
      showScheduleRemarks && scheduleRemarks.isNotEmpty;

  Future<void> setShowScheduleRemarks(bool value) async {
    await _preferences.setShowScheduleRemarks(value);
    notifyListeners();
    _notifyPrefs();
  }

  // ---------------------------------------------------------------------------
  // 静默更新（开关 + 最小间隔）
  // ---------------------------------------------------------------------------

  /// 是否开启冷启动的静默更新。
  bool get autoRefresh => _preferences.autoRefresh;

  /// 静默更新的最小间隔（分钟）。
  int get autoRefreshIntervalMinutes => _preferences.autoRefreshIntervalMinutes;

  Future<void> setAutoRefresh(bool value) async {
    await _preferences.setAutoRefresh(value);
    notifyListeners();
    _notifyPrefs();
  }

  Future<void> setAutoRefreshIntervalMinutes(int value) async {
    await _preferences.setAutoRefreshIntervalMinutes(value);
    notifyListeners();
    _notifyPrefs();
  }

  // ---------------------------------------------------------------------------
  // 调课（只影响渲染，不改原始课表）
  // ---------------------------------------------------------------------------

  /// 全部调课规则。
  List<RescheduleRule> get reschedules => _preferences.reschedules;

  /// 新增一条调课规则：把 [fromMonth] 月 [fromDay] 日的课整体调到 [toMonth] 月 [toDay] 日。
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
    await _preferences.saveReschedules(<RescheduleRule>[
      ..._preferences.reschedules,
      rule,
    ]);
    notifyListeners();
    return rule;
  }

  /// 删除一条调课规则（按 id）。
  Future<void> removeReschedule(String id) async {
    final rest = _preferences.reschedules
        .where((rule) => rule.id != id)
        .toList();
    if (rest.length == _preferences.reschedules.length) return;
    await _preferences.saveReschedules(rest);
    notifyListeners();
  }

  /// 修改一条调课规则的起止日期（保留原 id，渲染与冲突判定不变）。
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
    await _preferences.saveReschedules(updated);
    notifyListeners();
  }

  // ---------------------------------------------------------------------------
  // 外观（格子高度 / 课程卡片文字缩放）
  // ---------------------------------------------------------------------------

  /// 拖动滑块时先只改内存里的值，界面立刻跟着变；落盘延后到 [flushAppearance]。
  ///
  /// 直接每次 `onChanged` 都写文件的话，一次拖动会写几十遍 JSON。
  double? _cellHeightDraft;
  double? _courseTextScaleDraft;
  Timer? _appearanceTimer;

  /// 课表格子高度（逻辑像素）。
  double get cellHeight => _cellHeightDraft ?? _preferences.cellHeight;

  /// 课程卡片文字缩放（只影响卡片里的字，不影响时间列等其他文字）。
  double get courseTextScale =>
      _courseTextScaleDraft ?? _preferences.courseTextScale;

  void setCellHeight(double value) {
    final safe = clampCellHeight(value);
    if (safe == cellHeight) return;
    _cellHeightDraft = safe;
    notifyListeners();
    _notifyPrefs();
    _flushAppearanceSoon();
  }

  void setCourseTextScale(double value) {
    final safe = clampCourseTextScale(value);
    if (safe == courseTextScale) return;
    _courseTextScaleDraft = safe;
    notifyListeners();
    _notifyPrefs();
    _flushAppearanceSoon();
  }

  /// 立刻把外观设置写盘（关掉面板、离开页面时调）。
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

  /// 验证码挂起：手动登录与自动回登共用。
  Completer<String?> _captchaCompleter = Completer<String?>();

  /// 进行中的取课表任务（自动回登挂起时由它承接后续）。
  Future<Schedule>? _scheduleLoad;

  /// 后台刷新中（课表仍显示旧数据，右上角给提示，不遮挡页面）。
  bool _refreshing = false;
  bool get refreshing => _refreshing;

  /// 右上角提示语。空字符串表示不显示。
  String _hint = '';
  String get hint => _hint;

  bool _hintIsError = false;
  bool get hintIsError => _hintIsError;

  Timer? _hintTimer;

  bool _disposed = false;

  // -------------------------------------------------------------------------
  // 启动
  // -------------------------------------------------------------------------

  /// 启动流程：注入 Cookie 目录 → 先读本地缓存的课表（有就直接展示，不等网络）
  /// → 再按最小更新间隔决定要不要后台静默刷新。
  ///
  /// 没有缓存时退回旧路径：有快照直接取课表（免密）；没有快照但有保存的凭据
  /// 也能自动登录，否则引导手动登录。
  Future<void> boot() async {
    _setStatus(AppStatus.booting);
    try {
      // 三个本地存储互不依赖，但各自都要一次 path_provider 平台往返：
      // 先把三个 Future 都发出去再逐个 await，冷启动省掉两次串行往返。
      final sessionFuture = _repositoryReady
          ? null
          : FileSessionRepository.open();
      final preferencesFuture = _preferencesReady ? null : Preferences.open();
      final cacheFuture = _cacheReady ? null : FileScheduleCache.open();
      if (sessionFuture != null) _rebindRepository(await sessionFuture);
      if (preferencesFuture != null) _preferences = await preferencesFuture;
      // 冷启动也算"刚看见过今天"：回到前台时拿它比对，跨天才重建。
      _lastSeenDay = dayOnly(DateTime.now());
      if (cacheFuture != null) _scheduleCache = await cacheFuture;
      // 上次用的学校优先。以前不存这个，用户改了地址重启就退回默认学校。
      if (!_schoolFixed) {
        final savedSchool = _preferences.currentSchool;
        if (savedSchool.isNotEmpty) _schoolBaseUrl = savedSchool;
      }
      service.switchSchool(_schoolBaseUrl);
      // 账号必须本地恢复：凭据按「地址|账号」存，账号为空就取不到密码，
      // Cookie 失效后也就没法自动重登。
      _restoreAccount();

      // Cookie 快照与课表缓存也是两份独立文件：一起读，别串行。
      final snapshotFuture = service.bootstrap();
      final cachedFuture = _scheduleCache.load();
      final snapshot = await snapshotFuture;
      final cached = await cachedFuture;

      if (cached != null && sameSchool(cached.baseUrl, _schoolBaseUrl)) {
        // 先拿缓存把课表立起来：打开就能看，不卡网络。
        _restoreCachedSchedule(cached);
        // 有 Cookie 可用、且用户开了静默更新、且距上次抓取过了最小间隔，
        // 才后台静默刷一次；否则先让用户看缓存，手动刷新再说。
        if (snapshot != null &&
            _preferences.autoRefresh &&
            _shouldSilentRefresh(cached.fetchedAt)) {
          unawaited(_loadSchedule(background: true));
        }
        return;
      }

      if (snapshot == null) {
        final saved = await service.credentials.get(_accountKey());
        if (saved != null) username = saved.username;
        final hasSaved = await service.credentials.has(_accountKey());
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

  // -------------------------------------------------------------------------
  // 取课表
  // -------------------------------------------------------------------------

  /// 把缓存里的课表直接变成"就绪"状态（冷启动免等待）。
  ///
  /// 只回填课表与周次，不补身份、不发任何网络请求——这正是"打开就看到课表"
  /// 的全部成本。身份（姓名/学号）留给之后的静默刷新或手动刷新去补。
  void _restoreCachedSchedule(CachedSchedule cached) {
    _schedule = cached.schedule;
    _termId = cached.schedule.termId;
    // 记住缓存是什么时候抓的：回到前台时用它判断"够不够旧、要不要静默刷"。
    _lastFetchedAt = cached.fetchedAt;
    _applyCalendar(cached.schedule);
    _setStatus(AppStatus.ready);
  }

  /// 距上次成功抓课表是否已经超过用户设置的最小间隔。
  bool _shouldSilentRefresh(DateTime fetchedAt) =>
      DateTime.now().difference(fetchedAt) >=
      Duration(minutes: _preferences.autoRefreshIntervalMinutes);

  /// 把课表写进本地缓存（带当前学校与抓取时间）。
  Future<void> _saveScheduleCache(Schedule schedule) => _scheduleCache.save(
    CachedSchedule(
      baseUrl: _schoolBaseUrl,
      schedule: schedule,
      fetchedAt: DateTime.now(),
    ),
  );

  /// 取课表。
  ///
  /// 无论有没有数据，进度都只走「状态弹窗」：不把页面切成整屏 loading。
  /// [background] 为 true（或已经有数据）时课表继续显示旧内容。
  Future<void> _loadSchedule({String? termId, bool background = false}) async {
    final hasData = _schedule != null;
    final silent = background || hasData;

    _refreshing = true;
    if (silent) {
      _showHint('更新中…');
    } else {
      _setStatus(AppStatus.loading);
      _showHint('获取中…');
    }

    _scheduleLoad = service.getSchedule(termId: termId);
    try {
      final schedule = await _scheduleLoad!;
      if (_disposed) return;
      _schedule = schedule;
      _termId = schedule.termId;
      await _readIdentity();
      _applyCalendar(schedule);
      // 抓到就落缓存：下次冷启动直接展示，不再干等网络。
      unawaited(_saveScheduleCache(schedule));
      // 记下抓取时刻：回到前台的"够不够旧"判断用它，别再用缓存的旧时间。
      _lastFetchedAt = DateTime.now();
      _refreshing = false;
      _setStatus(AppStatus.ready);
      if (silent) {
        _showHint('已更新', clearAfter: const Duration(milliseconds: 1500));
      } else {
        clearHint();
      }
      _loadTermsQuietly();
    } on AcademicError catch (error) {
      _refreshing = false;
      if (silent) {
        _showHint(
          '更新失败：${_humanize(error)}',
          error: true,
          clearAfter: const Duration(seconds: 3),
        );
      } else {
        _fail(error);
      }
    } catch (error) {
      _refreshing = false;
      if (silent) {
        _showHint(
          '更新失败：$error',
          error: true,
          clearAfter: const Duration(seconds: 3),
        );
      } else {
        _fail(error);
      }
    }
  }

  /// 学期列表失败不阻塞课表展示（它只用于调试页与学期名反解）。
  Future<void> _loadTermsQuietly() async {
    try {
      final terms = await service.fetchTerms();
      if (_disposed) return;
      _terms = terms;
      notifyListeners();
    } catch (_) {
      // 忽略：课表已可用。
    }
  }

  /// 课表就绪后定位"第几周"：
  /// 用户校准过就用校准值；否则按学期估算（秋季 9 月初 / 春季 2 月底）。
  void _applyCalendar(Schedule schedule) {
    final DateTime? previousStart = _termStart;
    var maxWeek = 0;
    for (final entry in schedule.entries) {
      for (final week in entry.weeks) {
        if (week > maxWeek) maxWeek = week;
      }
    }
    _maxWeek = maxWeek > 0 ? maxWeek : 20;

    final saved = _preferences.termStartOf(schedule.termId);
    if (saved != null) {
      _termStart = saved;
      _setWeek(weekOf(saved, DateTime.now()));
    } else {
      final term = _termById(schedule.termId);
      _termStart = estimateTermStart(term ?? _fallbackTerm(schedule.termId));
      _setWeek(weekOf(_termStart!, DateTime.now()));
    }
    // 只有起始日**真的变了**才通知。
    //
    // 这里每次加载课表都会走到（含后台刷新），无条件通知等于"刷新一次课表，
    // 设置页就白重建一次"—— 那正是这次要消掉的开销之一。
    if (_termStart != previousStart) _notifyPrefs();
  }

  Term? _termById(String termId) {
    final terms = _terms;
    if (terms == null) return null;
    for (final term in terms.items) {
      if (term.id == termId) return term;
    }
    return null;
  }

  /// 学期列表还没回来时的兜底：从 `2026-2027-1` 反解学年与学期。
  Term _fallbackTerm(String termId) {
    final match = RegExp(r'^(\d{4})-').firstMatch(termId);
    final year = match == null
        ? DateTime.now().year
        : int.parse(match.group(1)!);
    final semester = termId.endsWith('-2') ? 2 : 1;
    return Term(id: termId, name: termId, year: year, semester: semester);
  }

  int _clampWeek(int value) =>
      value < 1 ? 1 : (value > _maxWeek ? _maxWeek : value);

  /// 切到指定周（越界自动收敛）。
  void goToWeek(int week) {
    // 只发周次通知：整页重建对"换一页"是白干的（见 weekNotifier 的说明）。
    _setWeek(week);
  }

  void nextWeek() => goToWeek(_week + 1);

  void previousWeek() => goToWeek(_week - 1);

  /// 回到"今天所在的周"（按当前校准）。
  void goToThisWeek() => goToWeek(currentWeekOfToday);

  /// 用户校准："现在其实是第 [week] 周" → 反推开学日并持久化。
  ///
  /// 这是唯一能让周视图与真实校历对齐的操作：教务不提供开学日期。
  Future<void> calibrateCurrentWeek(int week) async {
    final safe = week < 1 ? 1 : week;
    final start = termStartFromWeek(DateTime.now(), safe);
    _termStart = start;
    _maxWeek = safe > _maxWeek ? safe : _maxWeek;
    _setWeek(safe);
    final termId = _termId;
    if (termId.isNotEmpty) {
      await _preferences.setTermStart(termId, start);
    }
    notifyListeners();
    _notifyPrefs();
  }

  /// 清理当前学期的周次校准（回到估算值）。
  Future<void> resetCalendar() async {
    final termId = _termId;
    if (termId.isEmpty) return;
    final term = _termById(termId) ?? _fallbackTerm(termId);
    _termStart = estimateTermStart(term);
    _setWeek(weekOf(_termStart!, DateTime.now()));
    await _preferences.setTermStart(termId, _termStart!);
    notifyListeners();
    _notifyPrefs();
  }

  Future<void> refresh() => _loadSchedule(termId: _termId, background: true);

  // -------------------------------------------------------------------------
  // 回到前台
  // -------------------------------------------------------------------------

  /// App 重新回到前台时调用（由 `AppLifecycleListener.onShow` 驱动）。
  ///
  /// 两件事，顺序固定：
  ///  1. 校正"今天"——跨天后重建一次，表头日期与"今天"高亮立刻落到新的一天；
  ///     用户原本停在当前周时，周次也跟着走。
  ///  2. 按最小更新间隔决定要不要静默刷一次课表——与冷启动同一套语义，
  ///     频繁切前后台最多每 N 分钟刷一次。
  Future<void> onAppShown() async {
    if (_disposed) return;
    _syncCalendarDay();
    await _refreshIfDue();
  }

  /// 日期变了就重建一次界面；返回是否真的跨天了。
  ///
  /// 只在 App 回到前台时调用，不做定时器：课表页本来就不需要在后台自己动。
  bool _syncCalendarDay() {
    final today = dayOnly(DateTime.now());
    if (today == _lastSeenDay) return false;

    // 周次跟随：只在用户原本就停在"上次看见那天所在的周"时才跟。
    // 他手翻到第 2 周看课，过了几天再回来，不该被强行拽到当前周。
    final start = _termStart;
    if (start != null) {
      final weekWhenLeft = weekOf(start, _lastSeenDay);
      if (_week == weekWhenLeft) _setWeek(weekOf(start, today));
    }
    _lastSeenDay = today;
    notifyListeners();
    return true;
  }

  /// 距上次成功抓取是否已过最小间隔 → 静默刷一次。
  Future<void> _refreshIfDue() async {
    final allowed = shouldRefreshOnShow(
      autoRefresh: _preferences.autoRefresh,
      refreshing: _refreshing,
      hasSchedule: _schedule != null,
      lastFetchedAt: _lastFetchedAt,
      intervalMinutes: _preferences.autoRefreshIntervalMinutes,
    );
    if (!allowed) return;
    await refresh();
  }

  /// 「回到前台要不要静默刷新」的判定，抽成纯函数以便单测。
  ///
  /// 与冷启动的 `_shouldSilentRefresh` 语义一致：同一个最小间隔、同一组开关。
  @visibleForTesting
  static bool shouldRefreshOnShow({
    required bool autoRefresh,
    required bool refreshing,
    required bool hasSchedule,
    required DateTime? lastFetchedAt,
    required int intervalMinutes,
    DateTime? now,
  }) {
    // 用户关掉了静默更新 / 正在刷 / 还没有课表（交给 boot 与登录流程）
    if (!autoRefresh || refreshing || !hasSchedule) return false;
    final last = lastFetchedAt;
    // 不知道上次是什么时候抓的（例如本次进程刚起、缓存里没有时间）：放行一次，
    // 宁可多刷一次也不要让用户看到的是一份不知道多旧的课表。
    if (last == null) return true;
    return (now ?? DateTime.now()).difference(last) >=
        Duration(minutes: intervalMinutes);
  }

  /// 仅测试用：注入"上次看见的日期"与"上次抓取时刻"，让生命周期逻辑可断言。
  @visibleForTesting
  void seedLifecycleForTest({DateTime? lastSeenDay, DateTime? lastFetchedAt}) {
    if (lastSeenDay != null) _lastSeenDay = dayOnly(lastSeenDay);
    _lastFetchedAt = lastFetchedAt;
  }

  // -------------------------------------------------------------------------
  // 登录
  // -------------------------------------------------------------------------

  Future<void> signIn(String username, String password) async {
    this.username = username;
    _setStatus(AppStatus.signingIn);
    _showHint('登录中…');
    try {
      final state = await service.signIn(username, password, remember: true);
      if (_disposed) return;
      await _afterAuth(state);
    } on AcademicError catch (error) {
      _fail(error);
    } catch (error) {
      _fail(error);
    }
  }

  /// 提交验证码。两条来路：
  ///  - 手动登录：service 还持有登录挑战，直接提交；
  ///  - 自动回登：编排层正挂起等这个码，交给它继续（避免二次消费挑战）。
  Future<void> submitCaptcha(String code) async {
    if (_captcha == null) return;
    if (!_captchaCompleter.isCompleted) {
      _captchaCompleter.complete(code);
      _setStatus(AppStatus.signingIn);
      final pending = _scheduleLoad;
      if (pending != null) {
        try {
          final schedule = await pending;
          if (_disposed) return;
          _schedule = schedule;
          _termId = schedule.termId;
          await _readIdentity();
          _captcha = null;
          _setStatus(AppStatus.ready);
          _loadTermsQuietly();
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
      final state = await service.submitCaptcha(code);
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
        _captcha = null;
        // 登录成功才把地址收进地址簿：只记"能用的"地址，避免手滑打错也留着。
        await _preferences.setCurrentSchool(_schoolBaseUrl);
        // 同时记住账号：下次冷启动要用它算凭据的 key。
        await _rememberAccount(_username);
        await _loadSchedule();
      case CaptchaState():
        _captcha = state;
        _setStatus(AppStatus.needCaptcha, message: '请输入验证码');
      case WebLoginState():
        _setStatus(
          AppStatus.failed,
          message: '该学校要求先完成网页统一认证，暂不支持自动登录',
          code: ErrorCode.webLoginRequired.wire,
        );
    }
  }

  Future<void> refreshCaptcha() async {
    try {
      final state = await service.refreshCaptcha();
      _captcha = state;
      notifyListeners();
    } on AcademicError catch (error) {
      _fail(error);
    }
  }

  /// 验证码页"取消"：解除编排层的挂起，回退到登录页。
  void cancelCaptcha() {
    if (!_captchaCompleter.isCompleted) _captchaCompleter.complete(null);
    _captcha = null;
    _captchaCompleter = Completer<String?>();
    _setStatus(AppStatus.needLogin, message: '已取消登录');
  }

  /// 换教务地址。
  ///
  /// [relogin] = true（设置页 → 教务地址里切换）：**沿用当前账号**在新线路直接
  /// 登录，全程留在课表页 —— 不经过 `needLogin` / `signingIn` 这两个会被根路由
  /// 判成"该显示登录页"的状态（那正是"闪一下登录页再自动登录"的来源）。
  ///
  /// [relogin] = false（登录页里改了地址）：只切地址，随后由调用方用表单里
  /// 那套账号密码登录 —— 那种场景不该替用户决定用哪套凭据。
  ///
  /// 失败一律**只提示、不跳页**：切线路是用户主动发起的，出问题时把话说明白、
  /// 留在原地让他决定（重试 / 换线路 / 去设置里重登），而不是把人丢到登录页。
  Future<void> changeSchool(String baseUrl, {bool relogin = true}) async {
    if (sameSchool(_schoolBaseUrl, baseUrl)) return;

    final String account = username;

    // ---- 登录页路径：只切地址 ----
    if (!relogin) {
      _schoolBaseUrl = baseUrl;
      service.switchSchool(baseUrl);
      _schedule = null;
      _terms = null;
      _termId = '';
      unawaited(_preferences.setCurrentSchool(baseUrl));
      unawaited(_scheduleCache.clear());
      _username = '';
      _studentId = '';
      _studentName = '';
      // 先恢复目标学校的账号，再通知：通知在 `_restoreAccount` 之前发的话，
      // 设置页会在"账号已清空、还没读回"的中间态上渲染一次。
      _restoreAccount();
      _notifyPrefs();
      _setStatus(AppStatus.needLogin);
      return;
    }

    // ---- 设置页路径 ----
    // 凭据的 key 是「地址|账号」，换完地址就取不到了：先读出来。
    // 读不到就**什么都不动**（地址、会话、课表保持原样），只把问题说清楚。
    final Credentials? saved = account.isEmpty
        ? null
        : await service.credentials.get(_accountKey());
    if (saved == null || saved.password.isEmpty || saved.username.isEmpty) {
      _showHint('切换失败：本机没有找到已保存的密码。请在「设置 → 账号」重新登录一次再切换', error: true);
      return;
    }

    final String previousBase = _schoolBaseUrl;
    // 先切状态再切地址：`loading` 仍然映射到课表页，用户看到的是原地加载。
    _setStatus(AppStatus.loading, message: '正在切换到「${schoolLabel(baseUrl)}」…');
    _schoolBaseUrl = baseUrl;
    service.switchSchool(baseUrl);
    _username = account;
    _notifyPrefs();
    // 换的地址记住：下次启动直接用它（否则每次都退回默认学校）。
    unawaited(_preferences.setCurrentSchool(baseUrl));
    // 旧线路的课表缓存作废（内容是旧主机抓的）。
    unawaited(_scheduleCache.clear());
    // **刻意不清 `_schedule`**：清空后根路由会判定"没课表"，直接回登录页。
    // 旧课表先留在屏幕上，新数据到了整体替换；失败也只是它继续留着。

    try {
      final AuthState state = await service.signIn(
        account,
        saved.password,
        remember: true,
      );
      if (_disposed) return;
      await _afterAuth(state);
    } on AcademicError catch (error) {
      if (_disposed) return;
      // 登录失败：**回滚到原线路**，别把用户留在一台连不上的教务上。
      // 只提示、不跳页 —— 由他决定重试还是换一条。
      _rollbackSchool(previousBase);
      _setStatus(
        AppStatus.failed,
        message: '切换失败：${_humanize(error)}（仍停留在原线路）',
        code: error.code.wire,
      );
    } catch (error) {
      if (_disposed) return;
      _rollbackSchool(previousBase);
      _fail(error);
    }
  }

  /// 换线路失败后回到原地址：地址、服务端配置、持久化的"当前学校"一起回退。
  void _rollbackSchool(String baseUrl) {
    if (sameSchool(_schoolBaseUrl, baseUrl)) return;
    _schoolBaseUrl = baseUrl;
    service.switchSchool(baseUrl);
    unawaited(_preferences.setCurrentSchool(baseUrl));
    _notifyPrefs();
  }

  // -------------------------------------------------------------------------
  // 教务地址簿
  // -------------------------------------------------------------------------

  /// 已添加的教务地址。
  ///
  /// 一定包含当前地址：地址簿是"登录成功才收录"的，但用户可能还停在
  /// 一个刚手改、尚未成功的地址上——列表里不显示它，界面就会没有"使用中"那一项。
  List<String> get schools {
    final saved = _preferences.schools;
    if (saved.any((item) => sameSchool(item, _schoolBaseUrl))) return saved;
    return <String>[_schoolBaseUrl, ...saved];
  }

  Future<void> addSchool(String url) async {
    await _preferences.addSchool(url);
    notifyListeners();
    _notifyPrefs();
  }

  Future<void> removeSchool(String url) async {
    await _preferences.removeSchool(url);
    notifyListeners();
    _notifyPrefs();
  }

  /// 冷启动恢复"上次在这个学校登录的账号"（不联网）。
  ///
  /// 作用有两个：
  ///  1. 调试页 / 设置页立刻能显示学号，不必等网络把身份读回来；
  ///  2. 凭据按「地址|账号」存，账号算不出来就取不到密码——Cookie 失效后
  ///     会变成"明明存了密码却无法自动重登"。
  void _restoreAccount() {
    if (_username.isNotEmpty) return;
    final saved = _preferences.accountOf(_schoolBaseUrl);
    if (saved.isEmpty) return;
    _username = saved;
    service.accountHint = saved;
    if (_studentId.isEmpty) _studentId = saved;
  }

  /// 记住"这台设备上次登录的账号"（按学校区分），供下次冷启动使用。
  Future<void> _rememberAccount(String account) async {
    final text = account.trim();
    if (text.isEmpty) return;
    _username = text;
    service.accountHint = text;
    if (_studentId.isEmpty) _studentId = text;
    await _preferences.setAccountOf(_schoolBaseUrl, text);
    if (_disposed) return;
    notifyListeners();
    _notifyPrefs();
  }

  /// 读一次身份（姓名 / 学号）。
  ///
  /// 课表接口不返回"我是谁"：Cookie 免登冷启动时 `sessionInfo` 的姓名是空的，
  /// 于是出现了"能看课表但设置页显示未登录"。这里补一次 `checkSession`。
  Future<void> _readIdentity() async {
    var info = service.sessionInfo;
    if (info == null || info.studentName.isEmpty || info.studentId.isEmpty) {
      await service.ensureIdentity();
      info = service.sessionInfo;
    }
    if (info != null) {
      if (info.studentName.isNotEmpty) _studentName = info.studentName;
      if (info.studentId.isNotEmpty) _studentId = info.studentId;
    }
    // 还是读不到：至少用工号/学号顶上，别让界面显示"未登录"。
    if (_studentName.isEmpty && _studentId.isEmpty && username.isNotEmpty) {
      _studentId = username;
    }
    // 老安装升级上来的情况：以前没存账号，这次联网读到了学号，顺手补记，
    // 下次 Cookie 失效就能直接自动重登。
    if (_username.isEmpty && _studentId.isNotEmpty) {
      unawaited(_rememberAccount(_studentId));
    }
  }

  /// 修改密码：用新密码重新登录验证一次，成功后保存并刷新课表。
  ///
  /// 教务没有开放改密端点，所以这里的语义是**更新本机保存的密码**：
  /// 用户在教务网页改过密码后，用它把自动重登用的凭据换新。
  Future<void> changePassword(String newPassword) async {
    final account = service.sessionInfo?.username ?? _username;
    if (account.isEmpty) {
      throw AcademicError(ErrorCode.validationFailed, '还不知道账号，请先退出后重新登录一次');
    }
    final state = await service.signIn(account, newPassword, remember: true);
    if (state is CaptchaState) {
      throw AcademicError(
        ErrorCode.captchaRequired,
        '这所学校登录需要验证码，请退出登录后用验证码登录',
      );
    }
    if (state is! AuthenticatedState) {
      throw AcademicError(ErrorCode.sessionExpired, '新密码没有通过验证');
    }
    _username = account;
    // 学校偶尔不返回姓名，别把已经读到的名字擦成空串。
    if (state.studentName.isNotEmpty) _studentName = state.studentName;
    if (state.studentId.isNotEmpty) _studentId = state.studentId;
    notifyListeners();
    _notifyPrefs();
    await _loadSchedule(background: true);
  }

  /// 会话失效且自动重登失败：回到登录页（保留已填账号）。
  void retryAfterSessionLoss() {
    _captcha = null;
    _setStatus(AppStatus.needLogin, message: '会话已过期，请重新登录');
  }

  /// 仅测试用：直接注入一份已就绪的课表状态，避免 widget 测试去碰网络与平台通道。
  @visibleForTesting
  void hydrateForTest({
    required Schedule schedule,
    Terms? terms,
    String studentName = '房子洋',
    String studentId = '2407720102',
    int? week,
    DateTime? termStart,
  }) {
    final bool identityChanged =
        _termId != schedule.termId ||
        _studentName != studentName ||
        _studentId != studentId;
    _schedule = schedule;
    _terms = terms;
    _termId = schedule.termId;
    _studentName = studentName;
    _studentId = studentId;
    if (identityChanged) _notifyPrefs();
    _applyCalendar(schedule);
    if (termStart != null) _termStart = termStart;
    if (week != null) _setWeek(week);
    _status = AppStatus.ready;
    notifyListeners();
  }

  /// 仅测试用：直接设置右上角提示（验证浮层不遮挡课表）。
  @visibleForTesting
  void setHintForTest(String message, {bool error = false}) {
    _showHint(message, error: error);
  }

  /// 仅测试用：按"首次加载"路径取一次课表（不经过 boot 的目录/凭据初始化）。
  @visibleForTesting
  Future<void> loadScheduleForTest() => _loadSchedule();

  /// 仅测试用：把状态设为指定值（覆盖 loading / failed 的界面断言）。
  @visibleForTesting
  void setStatusForTest(
    AppStatus status, {
    String message = '',
    String code = '',
  }) {
    _setStatus(status, message: message, code: code);
  }

  /// 退出登录。只有一个入口，且**必定清掉保存的账号密码**——
  /// 这个 app 的密码只为自动重登存在，用户点退出就是要它别再自动登。
  Future<void> signOut() async {
    await service.signOut(forgetCredentials: true);
    if (_disposed) return;
    await _preferences.clearAccountOf(_schoolBaseUrl);
    _username = '';
    _studentId = '';
    _studentName = '';
    _schedule = null;
    _terms = null;
    _termId = '';
    _captcha = null;
    _notifyPrefs();
    // 退出登录连缓存课表一起清：那是"这个账号"的数据，不该留下给下一个人看。
    unawaited(_scheduleCache.clear());
    _setStatus(AppStatus.needLogin, message: '已退出登录');
  }

  // -------------------------------------------------------------------------
  // 调试信息（DebugPage 消费）
  // -------------------------------------------------------------------------

  /// 最近请求记录（方法/URL/状态码，不含 Cookie 值与请求体）。
  List<RequestLog> get requestLog => service.requestLog;

  /// 最近一次课表查询的原始响应文本。
  String? get rawScheduleBody => service.lastScheduleRawBody;

  /// 最近一次课表解析用的 kbList 原始行。
  List<Map<String, dynamic>> get rawScheduleRows => service.lastScheduleRows;

  /// 最近一次学期列表查询的原始页面。
  String? get rawTermsBody => service.lastTermsRawBody;

  /// Cookie 的**名字**列表（绝不输出值）。调试页用来确认"会话在不在"。
  List<String> get cookieNames {
    final header = service.cookieHeaderForDebug;
    if (header.isEmpty) return const <String>[];
    return header
        .split(';')
        .map((part) => part.split('=').first.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  /// 当前查看周的课程数（调试页显示）。
  int get weekEntryCount => weekEntries.length;

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  String _accountKey({String? username}) =>
      '$_schoolBaseUrl|${username ?? this.username}';

  /// 自动回登遇到验证码：挂起等用户输入。返回码或 null（取消）。
  Future<String?> _handleCaptcha(CaptchaState state) async {
    _captcha = state;
    _captchaCompleter = Completer<String?>();
    _setStatus(AppStatus.needCaptcha, message: '自动重登需要验证码');
    return _captchaCompleter.future;
  }

  void _rebindRepository(SessionRepository repository) {
    // service 内部持有 repository 引用；换绑定让后续 save 落到新目录。
    service.rebindCookieStorage(repository);
  }

  /// 编排层进入"重新登录"时更新提示语——用户能看到"在重登"，但课表不会被遮住。
  void _onServiceStage(String stage) {
    if (stage == ScheduleService.stageRelogin) {
      _refreshing = true;
      _showHint('正在重新登录…');
    }
  }

  void _showHint(String message, {bool error = false, Duration? clearAfter}) {
    _hint = message;
    _hintIsError = error;
    _hintTimer?.cancel();
    if (clearAfter != null) {
      _hintTimer = Timer(clearAfter, () {
        if (_disposed) return;
        _hint = '';
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// 手动关掉右上角提示（用户点一下）。
  void clearHint() {
    _hintTimer?.cancel();
    if (_hint.isEmpty) return;
    _hint = '';
    notifyListeners();
  }

  void _setStatus(AppStatus status, {String message = '', String code = ''}) {
    _status = status;
    _message = message;
    _errorCode = code;
    notifyListeners();
  }

  void _fail(Object error) {
    final academic = asAcademicError(error);
    _refreshing = false;
    _hint = '';
    _hintTimer?.cancel();
    _setStatus(
      AppStatus.failed,
      message: _humanize(academic),
      code: academic.code.wire,
    );
  }

  /// 关掉错误弹窗：有旧课表就退回"看起来正常"的状态，没有就回登录页。
  ///
  /// 错误现在走弹窗（不占整页），所以必须给用户一个干净出口，
  /// 否则弹窗会一直挂在那里。
  void dismissError() {
    if (_status != AppStatus.failed) return;
    if (_schedule != null) {
      _setStatus(AppStatus.ready);
    } else {
      _setStatus(AppStatus.needLogin);
    }
  }

  /// 错误码 → 用户能懂的话。新增错误码时必须在这里补分支。
  String _humanize(AcademicError error) {
    switch (error.code) {
      case ErrorCode.invalidCredentials:
        return '账号或密码不正确。注意有的学校用学号、有的用身份证号或教务账号。';
      case ErrorCode.sessionExpired:
        return '会话已过期。自动重登失败（可能是密码已变更或触发学校登录限制），请手动登录。';
      case ErrorCode.captchaRequired:
        return '需要验证码。请在验证码页输入后重试。';
      case ErrorCode.webLoginRequired:
        return '该学校要求先完成网页统一认证，暂不支持自动登录。';
      case ErrorCode.networkRetryable:
        return '网络不稳定或教务系统暂时无响应，请稍后重试。';
      case ErrorCode.pageChanged:
        return '教务页面结构与预期不一致（学校可能升级了系统），请反馈这个错误。';
      case ErrorCode.unsupported:
        return '该账号没有课表查询权限。';
      case ErrorCode.untrustedUrl:
        return '教务系统把请求跳转到了未声明的地址，已中止以保护账号安全。'
            '如果学校换了入口，请到「教务地址」里更新后再试。';
      case ErrorCode.cancelled:
        return '操作已取消。';
      case ErrorCode.validationFailed:
        return '输入不合法：${error.message}';
      case ErrorCode.staleContext:
        return '登录会话已过期，请重新登录。';
      case ErrorCode.resultUnknown:
        return '教务系统未明确返回结果，请刷新查看最新状态。';
      case ErrorCode.notOpen:
      case ErrorCode.noCapacity:
      case ErrorCode.conflict:
      case ErrorCode.alreadySelected:
      case ErrorCode.creditLimit:
      case ErrorCode.timeout:
      case ErrorCode.resourceLimit:
      case ErrorCode.success:
        return error.message;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    weekNotifier.dispose();
    prefsNotifier.dispose();
    _hintTimer?.cancel();
    _appearanceTimer?.cancel();
    // 面板没点"完成"就被关掉（比如返回手势）时，别把刚拖好的值丢掉。
    unawaited(flushAppearance());
    service.dispose();
    super.dispose();
  }
}
