/// 课前提醒的规划层：把课表 / 调课 / 作息 / 周次换算成绝对毫秒事件。
///
/// 纯函数——不读时钟、不读文件、不碰平台通道。所有「什么时候该提醒」的
/// 判断都在这里，原生侧只负责按绝对时间挂闹钟。
///
/// 为什么留在 Dart：周次 ⇄ 日期、单双周、调课叠加、作息表按生效日切换，
/// 这些逻辑本来就只在 Flutter 侧存在；Kotlin 再实现一遍必然跟着漂移
/// （而且 minSdk 24 没有 `java.time`，日期计算只会更麻烦）。
library;

import 'dart:convert';

import 'package:zf_academic/zf_academic.dart';

import 'course_text.dart';
import 'reschedule.dart';
import 'term_calendar.dart';
import 'timetable.dart';

/// payload 版本号。原生侧只认已知版本，未知版本直接拒绝而不是猜。
const int reminderPayloadVersion = 1;

/// 一次规划覆盖多少天。
///
/// 14 天够覆盖「两周不打开 App」的极端情况，又不至于把闹钟表塞满。
/// 没有每日滚动定时器：过期后下次打开 App 会重新规划。
const int reminderHorizonDays = 14;

/// 单次规划最多下发多少条事件。
///
/// AOSP 每个 uid 的闹钟上限约 500 条，120 条留足余量；
/// 正常课表 14 天也就 40~70 条。
const int reminderMaxEvents = 120;

/// 预设档位（分钟）。滑块负责连续取值，这几个按钮只是快捷跳转，
/// 但保留它们是因为「5/10/15/20/30」覆盖了绝大多数人的习惯值。
const List<int> reminderLeadOptions = <int>[5, 10, 15, 20, 30];

/// 提前量下界：1 分钟（0 等于不提前，没有意义）。
const int reminderMinLeadMinutes = 1;

/// 提前量上界：60 分钟。再大就会跨到上一节课里去，反而误导。
const int reminderMaxLeadMinutes = 60;

/// 默认提前量：10 分钟。
const int defaultReminderLeadMinutes = 10;

/// 把任意整数收敛到 [reminderMinLeadMinutes]~[reminderMaxLeadMinutes]。
///
/// 不做「不在预设里就回落默认」：滑块可以取 1~60 之间任何整数，
/// 回落会把用户刚拖出来的 17 分钟悄悄改成 10 分钟。
int clampReminderLead(int value) =>
    value.clamp(reminderMinLeadMinutes, reminderMaxLeadMinutes);

/// 提醒形态：普通横幅，或上课前的常驻"流体云"卡片。
///
/// 形态进 payload 也进指纹：切换形态必须触发一次重排，否则原生的旧闹钟
/// 还按旧形态发通知。
enum ReminderStyle {
  /// 一条普通通知，点开回 App。
  banner('banner'),

  /// 前台服务维持的常驻进度卡片（ColorOS 流体云 / HyperOS 焦点通知等）。
  fluid('fluid');

  const ReminderStyle(this.wireName);

  /// 写进 payload 的字符串，原生只认这两个值。
  final String wireName;

  static ReminderStyle parse(String? raw) =>
      raw == fluid.wireName ? fluid : banner;
}

/// 默认形态：横幅。开启流体云要额外消费一个前台服务，必须由用户显式选择。
const ReminderStyle defaultReminderStyle = ReminderStyle.banner;

/// 流体云卡片是否"显示到下课"。
///
/// 默认 false：上课铃一响卡片就撤（停止条件 = 上课时刻），符合"提醒"的直觉；
/// 想把它当上课进度条用再手动打开（停止条件 = 下课时刻）。
///
/// 该值进 payload **也进指纹**：改它必须触发一次重排，否则原生仍按旧语义
/// 挂那条"到点收起"的闹钟。
const bool defaultReminderFluidUntilEnd = false;

/// 一条待提醒的课程实例（某一天、某个节次）。
///
/// 字段全部是原生能直接消费的原始类型：毫秒时间戳 + 展示用文本。
/// [id] 跨进程稳定（同一门课、同一天、同一起始节 ⇒ 同一个 id），
/// 原生用它做 PendingIntent 的 requestCode 与通知 id。
class CourseReminderEvent {
  const CourseReminderEvent({
    required this.id,
    required this.entryId,
    required this.name,
    required this.teacher,
    required this.location,
    required this.startMs,
    required this.endMs,
    required this.remindAtMs,
    required this.startPeriod,
    required this.endPeriod,
    required this.week,
  });

  final String id;
  final String entryId;
  final String name;

  /// 没有教师 / 地点时是空串（原生按空串省略，不做 null 判断）。
  final String teacher;
  final String location;

  final int startMs;
  final int endMs;

  /// 通知该响的时刻 = [startMs] − 提前量。
  final int remindAtMs;

  final int startPeriod;
  final int endPeriod;
  final int week;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'entryId': entryId,
    'name': name,
    'teacher': teacher,
    'location': location,
    'startMs': startMs,
    'endMs': endMs,
    'remindAtMs': remindAtMs,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'week': week,
  };

  @override
  String toString() =>
      'CourseReminderEvent($id, $name, start=$startMs, remind=$remindAtMs)';
}

/// 一次规划的产物：[events] 已排序、已去重、已截断。
class ReminderPlan {
  const ReminderPlan({
    required this.events,
    required this.leadMinutes,
    required this.style,
    required this.fluidUntilEnd,
    required this.generatedAtMs,
    required this.fingerprint,
    required this.coverageEndMs,
    required this.skipped,
    required this.truncated,
  });

  const ReminderPlan.empty()
    : events = const <CourseReminderEvent>[],
      leadMinutes = defaultReminderLeadMinutes,
      style = defaultReminderStyle,
      fluidUntilEnd = defaultReminderFluidUntilEnd,
      generatedAtMs = 0,
      fingerprint = '',
      coverageEndMs = null,
      skipped = 0,
      truncated = false;

  /// 按 `remindAtMs` 升序（同刻按 id 升序，保证结果确定）。
  final List<CourseReminderEvent> events;

  final int leadMinutes;

  /// 提醒形态（横幅 / 流体云）。
  final ReminderStyle style;

  /// 流体云是否显示到下课（false = 上课即收起）。
  final bool fluidUntilEnd;

  /// 规划时刻。**不参与指纹**，否则每次重算都会"看起来变了"。
  final int generatedAtMs;

  /// 课表 + 提前量的稳定摘要：输入不变 → 指纹不变。
  final String fingerprint;

  /// 最后一条事件的上课时刻；没有事件时为 null（诊断页展示"覆盖截止"）。
  final int? coverageEndMs;

  /// 因为作息表里找不到节次而跳过的条目数（数据不完整时提示用）。
  final int skipped;

  /// 是否因为超过 [reminderMaxEvents] 被截断。
  final bool truncated;

  bool get isEmpty => events.isEmpty;

  /// 下一条该响的时刻（毫秒）；已过期的不算。
  int? get nextTriggerMs => events.isEmpty ? null : events.first.remindAtMs;

  /// 下发给原生的 JSON（版本化，未知字段由原生忽略）。
  String toPayloadJson() => jsonEncode(<String, Object?>{
    'v': reminderPayloadVersion,
    'generatedAtMs': generatedAtMs,
    'leadMinutes': leadMinutes,
    'style': style.wireName,
    'fluidUntilEnd': fluidUntilEnd,
    'fingerprint': fingerprint,
    'events': <Object?>[for (final event in events) event.toJson()],
  });
}

/// 规划 [now] 起 [horizonDays] 天内的课前提醒。
///
/// 参数全部显式传入（不给默认时钟），这样单测能钉死任意日期。
///
/// 规则：
///  1. 逐日推进，用 [weekOf] 得到周次，超出 `1..maxWeek` 的日子直接跳过；
///  2. 每周只算一次调课视图（[rescheduleWeekView]），天然含"调进来的课"
///     与"被顶掉不显示的课"；
///  3. 用 [activeTimetableAt] 按**事件当天**选作息表，再按全局节数对齐；
///  4. `remindAtMs <= now` 的事件不补发——打开 App 时突然弹一堆旧提醒
///     比漏一条更糟；
///  5. 按 `remindAtMs` 排序、按 id 去重、最多 [reminderMaxEvents] 条。
ReminderPlan planCourseReminders({
  required List<ScheduleEntry> entries,
  required List<RescheduleRule> reschedules,
  required DateTime termStart,
  required List<Timetable> timetables,
  required Map<PeriodGroup, int> sectionCounts,
  required DateTime now,
  required int leadMinutes,
  required int maxWeek,
  ReminderStyle style = defaultReminderStyle,
  bool fluidUntilEnd = defaultReminderFluidUntilEnd,
  int horizonDays = reminderHorizonDays,
  int maxEvents = reminderMaxEvents,
}) {
  final lead = clampReminderLead(leadMinutes);
  final leadMs = lead * 60 * 1000;
  final safeMaxWeek = maxWeek < 1 ? 1 : maxWeek;
  final days = horizonDays < 1 ? 1 : horizonDays;

  final weekEntries = <int, List<ScheduleEntry>>{};
  final sectionCache = <String, List<SectionTime>>{};
  final events = <CourseReminderEvent>[];
  var skipped = 0;

  final start = dayOnly(now);
  for (var offset = 0; offset < days; offset++) {
    final date = DateTime(start.year, start.month, start.day + offset);
    final week = weekOf(termStart, date);
    if (week < 1 || week > safeMaxWeek) continue;

    final active = weekEntries[week] ??= rescheduleWeekView(
      entries,
      reschedules,
      termStart,
      week,
      maxWeek: safeMaxWeek,
    ).entries;

    final table = activeTimetableAt(timetables, date);
    if (table == null) continue;
    final sections = sectionCache[table.id] ??= reconcileSections(
      table.sections,
      sectionCounts,
    );

    for (final entry in active) {
      if (entry.day != date.weekday) continue;
      // 调课视图已经按周过滤过，这里再判一次是为了 entries 为空 weeks 的
      // 容错路径（空 weeks = 每周都上）也保持同一套语义。
      if (!occursInWeek(entry, week)) continue;

      final startMinutes = _minutesOf(sections, entry.startPeriod);
      if (startMinutes == null) {
        skipped++;
        continue;
      }
      // 结束时刻要取「末节的**下课**时间」，不是末节的开始时间。
      // 取不到就退化成零时长，绝不让 endMs < startMs。
      final endMinutes =
          _endMinutesOf(sections, entry.endPeriod) ?? startMinutes;

      final startMs = _at(date, startMinutes).millisecondsSinceEpoch;
      final endMs = _at(date, endMinutes).millisecondsSinceEpoch;
      final remindAtMs = startMs - leadMs;
      // 已经过点的、以及"提前量把时间推到过去"的，都不补发。
      if (remindAtMs <= now.millisecondsSinceEpoch) continue;

      events.add(
        CourseReminderEvent(
          id: reminderEventId(
            entryId: entry.id,
            date: date,
            startPeriod: entry.startPeriod,
          ),
          entryId: entry.id,
          name: entry.name,
          teacher: entry.teacher ?? '',
          // 与课表格子共用同一套文本派生：通知里也只放房间号。
          location: roomOnly(entry.location ?? ''),
          startMs: startMs,
          endMs: endMs,
          remindAtMs: remindAtMs,
          startPeriod: entry.startPeriod,
          endPeriod: entry.endPeriod,
          week: week,
        ),
      );
    }
  }

  events.sort((a, b) {
    final byTime = a.remindAtMs.compareTo(b.remindAtMs);
    return byTime != 0 ? byTime : a.id.compareTo(b.id);
  });

  final unique = <CourseReminderEvent>[];
  final seen = <String>{};
  for (final event in events) {
    if (seen.add(event.id)) unique.add(event);
  }

  final truncated = unique.length > maxEvents;
  final kept = truncated ? unique.sublist(0, maxEvents) : unique;
  final coverage = kept.isEmpty
      ? null
      : kept.map((event) => event.startMs).reduce((a, b) => a > b ? a : b);

  return ReminderPlan(
    events: List<CourseReminderEvent>.unmodifiable(kept),
    leadMinutes: lead,
    style: style,
    fluidUntilEnd: fluidUntilEnd,
    generatedAtMs: now.millisecondsSinceEpoch,
    fingerprint: reminderFingerprint(
      leadMinutes: lead,
      style: style,
      fluidUntilEnd: fluidUntilEnd,
      events: kept,
    ),
    coverageEndMs: coverage,
    skipped: skipped,
    truncated: truncated,
  );
}

/// 事件 id：`entryId + 日期 + 起始节` 的稳定哈希。
///
/// 不含提前量：改提前量只改 `remindAtMs`，同一个事件不该换 id——
/// 否则旧闹钟取消后可能因为 id 变化而残留。
String reminderEventId({
  required String entryId,
  required DateTime date,
  required int startPeriod,
}) {
  final day = <String>[
    date.year.toString().padLeft(4, '0'),
    date.month.toString().padLeft(2, '0'),
    date.day.toString().padLeft(2, '0'),
  ].join();
  final seed = '$entryId|$day|$startPeriod';
  return 'e_${_hex32(_fnv1a(seed))}';
}

/// 课表 + 提前量的稳定指纹（FNV-1a 32 位，8 位十六进制）。
///
/// 刻意不含 `generatedAtMs`：同样的课表与设置必须得到同样的指纹，
/// 否则每次启动都会"发现不同"并重新排一遍闹钟。
String reminderFingerprint({
  required int leadMinutes,
  required List<CourseReminderEvent> events,
  ReminderStyle style = defaultReminderStyle,
  bool fluidUntilEnd = defaultReminderFluidUntilEnd,
}) {
  final sorted = events.toList()..sort((a, b) => a.id.compareTo(b.id));
  final buffer = StringBuffer(
    'v$reminderPayloadVersion|lead$leadMinutes|style${style.wireName}'
    '|untilEnd$fluidUntilEnd',
  );
  for (final event in sorted) {
    buffer
      ..write('|')
      ..write(event.id)
      ..write(':')
      ..write(event.startMs)
      ..write(':')
      ..write(event.remindAtMs);
  }
  return _hex32(_fnv1a(buffer.toString()));
}

int? _minutesOf(List<SectionTime> sections, int period) {
  for (final section in sections) {
    if (section.period == period) return section.startMinutes;
  }
  return null;
}

int? _endMinutesOf(List<SectionTime> sections, int period) {
  for (final section in sections) {
    if (section.period == period) return section.endMinutes;
  }
  return null;
}

/// 当天 [minutes] 分钟对应的本地时刻。
DateTime _at(DateTime date, int minutes) =>
    DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);

/// FNV-1a 32 位。用 UTF-8 字节而不是 code unit，结果与平台无关。
int _fnv1a(String text) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

String _hex32(int value) => value.toRadixString(16).padLeft(8, '0');
