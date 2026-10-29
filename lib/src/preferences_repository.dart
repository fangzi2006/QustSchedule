/// 应用设置持久化。
///
/// 存这几类东西：
///  1. 每个学期的"第 1 周周一"（用户校准过才有）；
///  2. 作息时间表列表（多张、按生效日切换）+ 上次的快捷设置参数；
///  3. 课表节数（上午 / 下午 / 晚上各几节，全局设置，所有作息表共用）；
///  4. 课表格子里显不显示教师 / 上课地点；
///  5. 外观：格子高度与课程卡片文字缩放；
///  6. 静默更新开关与最小间隔、调课规则；
///  7. 课前提醒开关与提前量（schema 9）。
///
/// 为什么不复用 Cookie 快照文件：那个是会话资产（可清可重建），
/// 这里是用户资产（清 Cookie 不该丢），分开存。
///
/// 版本迁移（当前 schema 11）：读到旧版的单个 `sectionCount` 整数时按 4/4/其余
/// 拆成三段，避免升级后节数被重置；任何缺失字段一律回落到默认值。
library;

// 命名参数不允许以下划线开头，所以构造函数里只能显式赋值给私有字段。
// ignore_for_file: prefer_initializing_formals

import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'reminder_planner.dart';
import 'reschedule.dart';
import 'school.dart';
import 'timetable.dart';

const int preferencesSchema = 11;

/// 课表格子（一节那一行）的高度，逻辑像素。
///
/// 下限保证三行字（课名 / 教师 / 地点）还是放得下，上限是"再高就太浪费屏幕"。
const double minCellHeight = 50;
const double maxCellHeight = 120;
const double defaultCellHeight = 60;

/// 课程卡片里的文字缩放（只影响卡片，不影响时间列等其他文字）。
const double minCourseTextScale = 0.8;
const double maxCourseTextScale = 1.4;
const double defaultCourseTextScale = 1.0;

/// 把格子高度夹进合法区间。
double clampCellHeight(double value) {
  if (value.isNaN) return defaultCellHeight;
  return value.clamp(minCellHeight, maxCellHeight).toDouble();
}

/// 把文字缩放夹进合法区间。
double clampCourseTextScale(double value) {
  if (value.isNaN) return defaultCourseTextScale;
  return value.clamp(minCourseTextScale, maxCourseTextScale).toDouble();
}

/// 静默更新的最小间隔（分钟）范围与默认值。
const int minAutoRefreshIntervalMinutes = 60;
const int maxAutoRefreshIntervalMinutes = 1440;
const int defaultAutoRefreshIntervalMinutes = 180;

int clampAutoRefreshIntervalMinutes(int value) =>
    value.clamp(minAutoRefreshIntervalMinutes, maxAutoRefreshIntervalMinutes);

class Preferences {
  Preferences._({
    required Map<String, String> termStarts,
    required List<Timetable> timetables,
    QuickSetup? quickSetup,
    Map<PeriodGroup, int>? sectionCounts,
    List<String>? schools,
    String currentSchool = '',
    Map<String, String>? lastAccounts,
    bool showTeacher = true,
    bool showLocation = true,
    double cellHeight = defaultCellHeight,
    double courseTextScale = defaultCourseTextScale,
    bool autoRefresh = true,
    int autoRefreshIntervalMinutes = defaultAutoRefreshIntervalMinutes,
    List<RescheduleRule> reschedules = const <RescheduleRule>[],
    bool showScheduleRemarks = true,
    bool reminderEnabled = false,
    int reminderLeadMinutes = defaultReminderLeadMinutes,
    ReminderStyle reminderStyle = defaultReminderStyle,
    bool reminderFluidUntilEnd = defaultReminderFluidUntilEnd,
    File? file,
  }) : _termStarts = termStarts,
       _timetables = timetables,
       _quickSetup = quickSetup,
       _sectionCounts = clampCounts(sectionCounts ?? defaultSectionCounts),
       _schools = schools ?? <String>[...presetSchoolUrls],
       _lastAccounts = lastAccounts ?? <String, String>{},
       _currentSchool = currentSchool.isEmpty
           ? (schools == null || schools.isEmpty
                 ? defaultSchool.baseUrl
                 : schools.first)
           : currentSchool,
       _showTeacher = showTeacher,
       _showLocation = showLocation,
       _cellHeight = clampCellHeight(cellHeight),
       _courseTextScale = clampCourseTextScale(courseTextScale),
       _autoRefresh = autoRefresh,
       _autoRefreshIntervalMinutes = clampAutoRefreshIntervalMinutes(
         autoRefreshIntervalMinutes,
       ),
       _reschedules = reschedules,
       _showScheduleRemarks = showScheduleRemarks,
       _reminderEnabled = reminderEnabled,
       _reminderLeadMinutes = clampReminderLead(reminderLeadMinutes),
       _reminderStyle = reminderStyle,
       _reminderFluidUntilEnd = reminderFluidUntilEnd,
       _file = file;

  final Map<String, String> _termStarts;
  List<Timetable> _timetables;
  QuickSetup? _quickSetup;

  /// 课表显示多少节。**全局设置**（不属于某一张作息表）：
  /// 每张表只是"这些节分别几点上"，节数由这里统一决定。
  Map<PeriodGroup, int> _sectionCounts;

  /// 已添加的教务地址，以及当前使用的那一个。
  List<String> _schools;
  String _currentSchool;

  /// 每个学校上次登录用的账号（`baseUrl → 账号`）。
  ///
  /// 必须本地存：凭据是按「地址|账号」存进安全存储的，账号为空就取不到密码，
  /// Cookie 失效后也就无法自动重登。不能指望从 Cookie 里读身份——
  /// 免登冷启动时协议层拿不到用户名。
  Map<String, String> _lastAccounts;

  /// 课表格子里是否显示教师 / 上课地点。
  ///
  /// 格子小的时候三行文字挤不下，有人只想看"什么课、在哪上"，
  /// 所以做成开关而不是一律全显示。
  bool _showTeacher;
  bool _showLocation;

  /// 外观：课表格子高度与课程卡片文字缩放。
  double _cellHeight;
  double _courseTextScale;

  /// 静默更新：是否开启 + 最小间隔（分钟）。
  bool _autoRefresh;
  int _autoRefreshIntervalMinutes;

  /// 调课规则（只影响渲染，不改原始课表）。
  List<RescheduleRule> _reschedules;

  /// 是否在课表页下方显示"备注"（实践课程 / 其他课程）。
  bool _showScheduleRemarks;

  /// 课前提醒：总开关与提前量（分钟）。
  ///
  /// 默认关闭：通知权限、精确闹钟权限都要用户自己点，静默打开只会
  /// "开了也不响"。提前量是 1~60 分钟的任意整数（界面上是滑块）。
  bool _reminderEnabled;
  int _reminderLeadMinutes;

  /// 提醒形态：横幅 or 流体云（schema 10）。
  ReminderStyle _reminderStyle;

  /// 流体云是否显示到下课（schema 11，默认 false = 上课即收起）。
  bool _reminderFluidUntilEnd;

  final File? _file;

  /// 内存实例（测试用；不落盘）。可预置学期起始日、时间表与节数。
  factory Preferences.inMemory({
    Map<String, String>? termStarts,
    List<Timetable>? timetables,
    QuickSetup? quickSetup,
    Map<PeriodGroup, int>? sectionCounts,
    List<String>? schools,
    String currentSchool = '',
    Map<String, String>? lastAccounts,
    bool showTeacher = true,
    bool showLocation = true,
    double cellHeight = defaultCellHeight,
    double courseTextScale = defaultCourseTextScale,
    bool autoRefresh = true,
    int autoRefreshIntervalMinutes = defaultAutoRefreshIntervalMinutes,
    List<RescheduleRule> reschedules = const <RescheduleRule>[],
    bool showScheduleRemarks = true,
    bool reminderEnabled = false,
    int reminderLeadMinutes = defaultReminderLeadMinutes,
    ReminderStyle reminderStyle = defaultReminderStyle,
    bool reminderFluidUntilEnd = defaultReminderFluidUntilEnd,
  }) => Preferences._(
    termStarts: termStarts ?? <String, String>{},
    timetables: timetables ?? <Timetable>[defaultTimetable()],
    quickSetup: quickSetup,
    sectionCounts: sectionCounts,
    schools: schools,
    currentSchool: currentSchool,
    lastAccounts: lastAccounts,
    showTeacher: showTeacher,
    showLocation: showLocation,
    cellHeight: cellHeight,
    courseTextScale: courseTextScale,
    autoRefresh: autoRefresh,
    autoRefreshIntervalMinutes: autoRefreshIntervalMinutes,
    reschedules: reschedules,
    showScheduleRemarks: showScheduleRemarks,
    reminderEnabled: reminderEnabled,
    reminderLeadMinutes: reminderLeadMinutes,
    reminderStyle: reminderStyle,
    reminderFluidUntilEnd: reminderFluidUntilEnd,
    file: null,
  );

  static Future<Preferences> open({String fileName = 'app_prefs.json'}) async {
    final directory = await getApplicationSupportDirectory();
    final file = File('${directory.path}/$fileName');
    final text = file.existsSync() ? await file.readAsString() : '';
    final prefs = decode(text, file: file);
    return prefs;
  }

  /// 从 JSON 文本恢复设置（[open] 的核心逻辑）。
  ///
  /// 单独抽出来是为了能测迁移：schema 1 只有 `termStarts`，
  /// 读到没有 `timetables` 的旧文件时必须自动补一张默认表，
  /// 否则用户升级后课表没有作息可读。
  /// 把出厂预设线路补进地址簿：已有的跳过，缺的按顺序追加在后面。
  ///
  /// 只用于**从旧 schema 升级**这一次；之后用户删掉的线路不会被反复补回来。
  static List<String> withPresetSchools(List<String> current) {
    final merged = <String>[...current];
    for (final String url in presetSchoolUrls) {
      if (!merged.any((String item) => sameSchool(item, url))) {
        merged.add(url);
      }
    }
    return merged;
  }

  static Preferences decode(String text, {File? file}) {
    var termStarts = <String, String>{};
    var timetables = <Timetable>[];
    QuickSetup? quickSetup;
    var sectionCounts = <PeriodGroup, int>{...defaultSectionCounts};
    var schools = <String>[...presetSchoolUrls];
    var currentSchool = defaultSchool.baseUrl;
    var lastAccounts = <String, String>{};
    var showTeacher = true;
    var showLocation = true;
    var cellHeight = defaultCellHeight;
    var courseTextScale = defaultCourseTextScale;
    var autoRefresh = true;
    var autoRefreshIntervalMinutes = defaultAutoRefreshIntervalMinutes;
    var reschedules = <RescheduleRule>[];
    var showScheduleRemarks = true;
    var reminderEnabled = false;
    var reminderLeadMinutes = defaultReminderLeadMinutes;
    var reminderStyle = defaultReminderStyle;
    var reminderFluidUntilEnd = defaultReminderFluidUntilEnd;

    if (text.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(text);
        if (decoded is Map<String, dynamic>) {
          final rawStarts = decoded['termStarts'];
          if (rawStarts is Map<String, dynamic>) {
            termStarts = rawStarts.map(
              (key, value) => MapEntry(key, value.toString()),
            );
          }
          final rawTables = decoded['timetables'];
          if (rawTables is List<dynamic>) {
            timetables = rawTables
                .whereType<Map<String, dynamic>>()
                .map(Timetable.fromJson)
                .where((table) => table.sections.isNotEmpty)
                .toList();
          }
          final rawQuick = decoded['quickSetup'];
          if (rawQuick is Map<String, dynamic>) {
            quickSetup = QuickSetup.fromJson(rawQuick);
          }
          // 新格式：三段节数。旧格式只有总数，按 4/4/其余 迁移。
          final rawCounts = decoded['sectionCounts'];
          if (rawCounts is Map<String, dynamic>) {
            final parsed = <PeriodGroup, int>{};
            for (final group in PeriodGroup.values) {
              final value = (rawCounts[group.name] as num?)?.toInt();
              if (value != null) parsed[group] = value;
            }
            if (parsed.isNotEmpty) sectionCounts = clampCounts(parsed);
          } else {
            final legacy = (decoded['sectionCount'] as num?)?.toInt();
            if (legacy != null) {
              sectionCounts = clampCounts(splitCounts(legacy));
            }
          }
          final rawSchools = decoded['schools'];
          if (rawSchools is List<dynamic>) {
            final parsed = rawSchools
                .whereType<String>()
                .map((item) => item.trim())
                .where((item) => item.isNotEmpty)
                .toList();
            if (parsed.isNotEmpty) schools = parsed;
          }
          // schema 8：地址簿出厂带 6 条青科大线路。老文件里只有当初那一条
          // （或用户自己加的几条），这里把缺的补上；用户删过的线路在 schema 8
          // 之后不会再被补回来（迁移只跑一次）。
          final int rawSchema = (decoded['schema'] as num?)?.toInt() ?? 1;
          if (rawSchema < 8) schools = withPresetSchools(schools);

          final rawCurrent = (decoded['currentSchool'] as String?)?.trim();
          if (rawCurrent != null && rawCurrent.isNotEmpty) {
            currentSchool = rawCurrent;
          }
          // schema 7：每个学校上次登录的账号（用于拼凭据的 key）。
          final rawAccounts = decoded['lastAccounts'];
          if (rawAccounts is Map<String, dynamic>) {
            lastAccounts = <String, String>{
              for (final entry in rawAccounts.entries)
                if (entry.value is String && (entry.value as String).isNotEmpty)
                  entry.key: entry.value as String,
            };
          }
          // 缺字段 = 旧版本存的设置，按"都显示"处理。
          final rawTeacher = decoded['showTeacher'];
          if (rawTeacher is bool) showTeacher = rawTeacher;
          final rawLocation = decoded['showLocation'];
          if (rawLocation is bool) showLocation = rawLocation;
          final rawCell = (decoded['cellHeight'] as num?)?.toDouble();
          if (rawCell != null) cellHeight = clampCellHeight(rawCell);
          final rawScale = (decoded['courseTextScale'] as num?)?.toDouble();
          if (rawScale != null) {
            courseTextScale = clampCourseTextScale(rawScale);
          }
          // schema 5：静默更新开关 / 间隔 / 调课规则。
          final rawAutoRefresh = decoded['autoRefresh'];
          if (rawAutoRefresh is bool) autoRefresh = rawAutoRefresh;
          final rawInterval = (decoded['autoRefreshIntervalMinutes'] as num?)
              ?.toInt();
          if (rawInterval != null) {
            autoRefreshIntervalMinutes = clampAutoRefreshIntervalMinutes(
              rawInterval,
            );
          }
          final rawReschedules = decoded['reschedules'];
          if (rawReschedules is List<dynamic>) {
            reschedules = rawReschedules
                .map(RescheduleRule.fromJson)
                .whereType<RescheduleRule>()
                .toList();
          }
          // schema 6：是否显示课表备注。缺字段 = 旧版本，按"显示"处理。
          final rawRemarks = decoded['showScheduleRemarks'];
          if (rawRemarks is bool) showScheduleRemarks = rawRemarks;
          // schema 9：课前提醒。缺字段 = 旧版本，按"关闭 + 默认提前量"。
          final rawReminder = decoded['reminderEnabled'];
          if (rawReminder is bool) reminderEnabled = rawReminder;
          final rawLead = (decoded['reminderLeadMinutes'] as num?)?.toInt();
          if (rawLead != null) reminderLeadMinutes = clampReminderLead(rawLead);
          // schema 10：提醒形态。缺字段 / 脏值一律按横幅。
          reminderStyle = ReminderStyle.parse(
            decoded['reminderStyle'] as String?,
          );
          // schema 11：流体云是否显示到下课。缺字段 = 默认（上课即收起）。
          final rawUntilEnd = decoded['reminderFluidUntilEnd'];
          if (rawUntilEnd is bool) reminderFluidUntilEnd = rawUntilEnd;
        }
      } catch (_) {
        // 文件损坏按空设置处理：不值得因为一份设置让 app 起不来。
        termStarts = <String, String>{};
        timetables = <Timetable>[];
        quickSetup = null;
        sectionCounts = <PeriodGroup, int>{...defaultSectionCounts};
        showTeacher = true;
        showLocation = true;
        cellHeight = defaultCellHeight;
        courseTextScale = defaultCourseTextScale;
        autoRefresh = true;
        autoRefreshIntervalMinutes = defaultAutoRefreshIntervalMinutes;
        reschedules = <RescheduleRule>[];
        showScheduleRemarks = true;
        reminderEnabled = false;
        reminderLeadMinutes = defaultReminderLeadMinutes;
        reminderStyle = defaultReminderStyle;
        reminderFluidUntilEnd = defaultReminderFluidUntilEnd;
      }
    }

    return Preferences._(
      termStarts: termStarts,
      timetables: _withBuiltinSummerTable(timetables),
      quickSetup: quickSetup,
      sectionCounts: sectionCounts,
      schools: schools,
      currentSchool: currentSchool,
      lastAccounts: lastAccounts,
      showTeacher: showTeacher,
      showLocation: showLocation,
      cellHeight: cellHeight,
      courseTextScale: courseTextScale,
      autoRefresh: autoRefresh,
      autoRefreshIntervalMinutes: autoRefreshIntervalMinutes,
      reschedules: reschedules,
      showScheduleRemarks: showScheduleRemarks,
      reminderEnabled: reminderEnabled,
      reminderLeadMinutes: reminderLeadMinutes,
      reminderStyle: reminderStyle,
      reminderFluidUntilEnd: reminderFluidUntilEnd,
      file: file,
    );
  }

  // ---------------------------------------------------------------------------
  // 学期起始日（周次校准）
  // ---------------------------------------------------------------------------

  /// 第 1 周周一的日期；没校准过返回 null。
  DateTime? termStartOf(String termId) {
    final raw = _termStarts[termId];
    if (raw == null) return null;
    return DateTime.tryParse(raw);
  }

  Future<void> setTermStart(String termId, DateTime value) async {
    _termStarts[termId] = DateTime(
      value.year,
      value.month,
      value.day,
    ).toIso8601String();
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 全局节数（上午 / 下午 / 晚上）
  // ---------------------------------------------------------------------------

  Map<PeriodGroup, int> get sectionCounts =>
      Map<PeriodGroup, int>.from(_sectionCounts);

  /// 总节数 = 三段之和。
  int get sectionCount => countsSum(_sectionCounts);

  Future<void> setSectionCounts(Map<PeriodGroup, int> value) async {
    final safe = clampCounts(value);
    if (countsSum(safe) == sectionCount &&
        PeriodGroup.values.every((g) => safe[g] == _sectionCounts[g])) {
      return;
    }
    _sectionCounts = safe;
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 教务地址簿
  // ---------------------------------------------------------------------------

  /// 已添加的教务地址（按添加顺序）。
  List<String> get schools => List<String>.unmodifiable(_schools);

  /// 当前使用的地址。
  String get currentSchool => _currentSchool;

  Future<void> addSchool(String url) async {
    final text = url.trim();
    if (text.isEmpty) return;
    if (_schools.any((item) => sameSchool(item, text))) return;
    _schools = <String>[..._schools, text];
    await _flush();
  }

  Future<void> removeSchool(String url) async {
    final rest = _schools.where((item) => !sameSchool(item, url)).toList();
    if (rest.isEmpty || rest.length == _schools.length) return;
    _schools = rest;
    if (sameSchool(_currentSchool, url)) _currentSchool = rest.first;
    await _flush();
  }

  Future<void> setCurrentSchool(String url) async {
    final text = url.trim();
    if (text.isEmpty) return;
    if (!_schools.any((item) => sameSchool(item, text))) {
      _schools = <String>[..._schools, text];
    }
    if (sameSchool(_currentSchool, text)) return;
    _currentSchool = text;
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 上次登录的账号（每个学校各记一个）
  // ---------------------------------------------------------------------------

  /// 某个学校上次登录用的账号；没登录过返回空串。
  ///
  /// 冷启动要靠它拼凭据的 key（`地址|账号`），否则取不到保存的密码，
  /// Cookie 失效后就无法自动重登。
  String accountOf(String url) {
    for (final entry in _lastAccounts.entries) {
      if (sameSchool(entry.key, url)) return entry.value;
    }
    return '';
  }

  Future<void> setAccountOf(String url, String account) async {
    final text = url.trim();
    final name = account.trim();
    if (text.isEmpty || name.isEmpty) return;
    if (accountOf(text) == name) return;
    _lastAccounts = _accountsExcept(text)..[text] = name;
    await _flush();
  }

  /// 退出登录时清掉本校的账号记录（凭据本身也一并删除）。
  Future<void> clearAccountOf(String url) async {
    final text = url.trim();
    if (text.isEmpty || accountOf(text).isEmpty) return;
    _lastAccounts = _accountsExcept(text);
    await _flush();
  }

  /// 复制一份"去掉某个学校"的账号表（Map 没有 where，用循环重建）。
  Map<String, String> _accountsExcept(String url) {
    final next = <String, String>{};
    for (final entry in _lastAccounts.entries) {
      if (!sameSchool(entry.key, url)) next[entry.key] = entry.value;
    }
    return next;
  }

  // ---------------------------------------------------------------------------
  // 课表格子显示哪些信息
  // ---------------------------------------------------------------------------

  /// 课格里是否显示教师名。
  bool get showTeacher => _showTeacher;

  /// 课格里是否显示上课地点。
  bool get showLocation => _showLocation;

  Future<void> setShowTeacher(bool value) async {
    if (_showTeacher == value) return;
    _showTeacher = value;
    await _flush();
  }

  Future<void> setShowLocation(bool value) async {
    if (_showLocation == value) return;
    _showLocation = value;
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 外观
  // ---------------------------------------------------------------------------

  /// 课表格子高度（逻辑像素）。
  double get cellHeight => _cellHeight;

  /// 课程卡片文字缩放。
  double get courseTextScale => _courseTextScale;

  Future<void> setCellHeight(double value) async {
    final safe = clampCellHeight(value);
    if (safe == _cellHeight) return;
    _cellHeight = safe;
    await _flush();
  }

  Future<void> setCourseTextScale(double value) async {
    final safe = clampCourseTextScale(value);
    if (safe == _courseTextScale) return;
    _courseTextScale = safe;
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 静默更新 + 调课
  // ---------------------------------------------------------------------------

  /// 是否开启冷启动的静默更新。
  bool get autoRefresh => _autoRefresh;

  /// 静默更新的最小间隔（分钟）。
  int get autoRefreshIntervalMinutes => _autoRefreshIntervalMinutes;

  /// 调课规则（只影响渲染）。
  List<RescheduleRule> get reschedules =>
      List<RescheduleRule>.unmodifiable(_reschedules);

  Future<void> setAutoRefresh(bool value) async {
    if (_autoRefresh == value) return;
    _autoRefresh = value;
    await _flush();
  }

  Future<void> setAutoRefreshIntervalMinutes(int value) async {
    final safe = clampAutoRefreshIntervalMinutes(value);
    if (safe == _autoRefreshIntervalMinutes) return;
    _autoRefreshIntervalMinutes = safe;
    await _flush();
  }

  Future<void> saveReschedules(List<RescheduleRule> rules) async {
    _reschedules = List<RescheduleRule>.from(rules);
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 课表备注（实践课程 / 其他课程）
  // ---------------------------------------------------------------------------

  /// 是否在课表页下方显示"备注"（实践课程 / 其他课程）。
  bool get showScheduleRemarks => _showScheduleRemarks;

  Future<void> setShowScheduleRemarks(bool value) async {
    if (_showScheduleRemarks == value) return;
    _showScheduleRemarks = value;
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 课前提醒
  // ---------------------------------------------------------------------------

  /// 是否开启课前提醒（默认关闭）。
  bool get reminderEnabled => _reminderEnabled;

  /// 提前多少分钟（1~60 的任意整数）。
  int get reminderLeadMinutes => _reminderLeadMinutes;

  Future<void> setReminderEnabled(bool value) async {
    if (_reminderEnabled == value) return;
    _reminderEnabled = value;
    await _flush();
  }

  Future<void> setReminderLeadMinutes(int value) async {
    final safe = clampReminderLead(value);
    if (safe == _reminderLeadMinutes) return;
    _reminderLeadMinutes = safe;
    await _flush();
  }

  /// 提醒形态（横幅 / 流体云）。
  ReminderStyle get reminderStyle => _reminderStyle;

  Future<void> setReminderStyle(ReminderStyle value) async {
    if (_reminderStyle == value) return;
    _reminderStyle = value;
    await _flush();
  }

  /// 流体云卡片是否显示到下课（false = 上课即收起）。
  bool get reminderFluidUntilEnd => _reminderFluidUntilEnd;

  Future<void> setReminderFluidUntilEnd(bool value) async {
    if (_reminderFluidUntilEnd == value) return;
    _reminderFluidUntilEnd = value;
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 内置作息表补齐
  // ---------------------------------------------------------------------------

  /// 老用户的设置里只有一张内置默认表时，自动补上第二套预设，
  /// 让升级后也能看到两套作息；只要用户动过（改名/加表），就不碰。
  static List<Timetable> _withBuiltinSummerTable(List<Timetable> tables) {
    if (tables.isEmpty) return defaultTimetables();
    final hasSummer = tables.any((table) => table.id == 'default-summer');
    final onlyBuiltinDefault =
        tables.length == 1 &&
        tables.single.id == 'default' &&
        tables.single.name == defaultTimetable().name;
    if (!hasSummer && onlyBuiltinDefault) {
      return <Timetable>[...tables, defaultSummerTimetable()];
    }
    return tables;
  }

  // ---------------------------------------------------------------------------
  // 作息时间表
  // ---------------------------------------------------------------------------

  /// 全部时间表（按生效日倒序，列表页直接用）。
  List<Timetable> get timetables => sortedTimetables(_timetables);

  /// 今天该用哪张表。
  Timetable? activeTimetable({DateTime? today}) =>
      activeTimetableAt(_timetables, today ?? DateTime.now());

  /// 整体覆盖保存（增删改都走这里，写完立刻落盘）。
  Future<void> saveTimetables(List<Timetable> tables) async {
    if (tables.isEmpty) {
      throw ArgumentError('至少要保留一张作息时间表');
    }
    _timetables = tables.take(maxTimetables).toList();
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 快捷设置（记住上次填的参数，下次打开面板不用重填）
  // ---------------------------------------------------------------------------

  QuickSetup? get quickSetup => _quickSetup;

  Future<void> setQuickSetup(QuickSetup setup) async {
    _quickSetup = setup;
    await _flush();
  }

  // ---------------------------------------------------------------------------
  // 落盘
  // ---------------------------------------------------------------------------

  Future<void> _flush() async {
    final file = _file;
    if (file == null) return;
    await file.parent.create(recursive: true);
    await file.writeAsString(
      jsonEncode(<String, Object?>{
        'schema': preferencesSchema,
        'termStarts': _termStarts,
        'sectionCounts': <String, int>{
          for (final entry in _sectionCounts.entries)
            entry.key.name: entry.value,
        },
        'schools': _schools,
        'currentSchool': _currentSchool,
        'lastAccounts': _lastAccounts,
        'showTeacher': _showTeacher,
        'showLocation': _showLocation,
        'cellHeight': _cellHeight,
        'courseTextScale': _courseTextScale,
        'autoRefresh': _autoRefresh,
        'autoRefreshIntervalMinutes': _autoRefreshIntervalMinutes,
        'reschedules': _reschedules.map((rule) => rule.toJson()).toList(),
        'showScheduleRemarks': _showScheduleRemarks,
        'reminderEnabled': _reminderEnabled,
        'reminderLeadMinutes': _reminderLeadMinutes,
        'reminderStyle': _reminderStyle.wireName,
        'reminderFluidUntilEnd': _reminderFluidUntilEnd,
        'timetables': _timetables.map((table) => table.toJson()).toList(),
        if (_quickSetup != null) 'quickSetup': _quickSetup!.toJson(),
      }),
    );
  }
}
