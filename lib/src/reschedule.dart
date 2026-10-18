/// 调课：按日期调——「把 X 月 X 日的课调到 Y 月 Y 日」。
///
/// 关键语义：**不修改保存的课表数据**，只在渲染时叠加——原始 `Schedule` 原封不动，
/// 只在"某周该显示哪些课"这一层做改写，缓存、调试页里的原始数据始终不变。
///
/// 合并与冲突（用户明确的规则）：
///  - 调到的那天若原本有课 → 与调过去的课**合并**显示；
///  - 合并时若**时间冲突**（同一天、节次区间相交）→ **优先显示调过去的课**，
///    原本占该时段的课被抑制（不显示），并记为该天的"冲突"，供表头黄底 + 点击查看。
library;

import 'package:zf_academic/zf_academic.dart';

import 'term_calendar.dart';

/// 一条调课规则：月 [fromMonth] 日 [fromDay] 的课，整体挪到月 [toMonth] 日 [toDay]。
class RescheduleRule {
  const RescheduleRule({
    required this.id,
    required this.fromMonth,
    required this.fromDay,
    required this.toMonth,
    required this.toDay,
  });

  final String id;
  final int fromMonth;
  final int fromDay;
  final int toMonth;
  final int toDay;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'fromMonth': fromMonth,
    'fromDay': fromDay,
    'toMonth': toMonth,
    'toDay': toDay,
  };

  static RescheduleRule? fromJson(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    final id = (raw['id'] as String?) ?? '';
    final fromMonth = (raw['fromMonth'] as num?)?.toInt();
    final fromDay = (raw['fromDay'] as num?)?.toInt();
    final toMonth = (raw['toMonth'] as num?)?.toInt();
    final toDay = (raw['toDay'] as num?)?.toInt();
    if (id.isEmpty ||
        fromMonth == null ||
        fromDay == null ||
        toMonth == null ||
        toDay == null) {
      return null;
    }
    return RescheduleRule(
      id: id,
      fromMonth: fromMonth,
      fromDay: fromDay,
      toMonth: toMonth,
      toDay: toDay,
    );
  }
}

/// 一条调课冲突：调课 [winner] 顶掉了原本在该时段上课的 [displaced]。
///
/// [displaced] 因冲突**不在网格里显示**，只在表头黄底点击后的详情里列出，
/// 让用户知道"这里本来有课，被调课盖掉了"。
class RescheduleConflict {
  const RescheduleConflict({required this.displaced, required this.winner});

  /// 被顶掉、本周不显示的原课。
  final ScheduleEntry displaced;

  /// 占了位置、优先显示的调课。
  final ScheduleEntry winner;
}

/// 某一周的调课渲染视图。
class RescheduleWeekView {
  const RescheduleWeekView({
    this.entries = const <ScheduleEntry>[],
    this.conflicts = const <int, List<RescheduleConflict>>{},
  });

  /// 本周实际要渲染的课（已合并调课、已按冲突抑制）。
  final List<ScheduleEntry> entries;

  /// 每天的冲突：`星期(1..7) → 被顶掉的原课列表`。表头据此画黄底。
  final Map<int, List<RescheduleConflict>> conflicts;

  /// 某一天是否有调课冲突（表头高亮用）。
  bool hasConflictOn(int day) {
    final list = conflicts[day];
    return list != null && list.isNotEmpty;
  }
}

/// 某一周实际要渲染的课 + 冲突信息：把"日期 → 日期"的调课套到每个**实例**上，
/// 再取落在 [week] 这一周的（含从别的周调进来的）。
///
/// 月日没有年份，用 [termStart] 把它落到当前学期窗口里（早于学期开始就取次年），
/// 跨年边界（12 月 → 次年 1 月）也自然处理。
///
/// ⚠ 这里按"实例"而非"课程 id"生成：同一门课跨多周时每周都是一个独立实例，
/// 早年用 `id` 去重导致"调到目标周的课被同 id 的原周实例顶掉"——目标日不显示。
RescheduleWeekView rescheduleWeekView(
  List<ScheduleEntry> entries,
  List<RescheduleRule> rules,
  DateTime termStart,
  int week, {
  required int maxWeek,
}) {
  if (rules.isEmpty) {
    return RescheduleWeekView(entries: entriesOfWeek(entries, week));
  }

  final resolved = <_ResolvedRule>[
    for (final rule in rules) _resolve(rule, termStart),
  ];

  // 1) 生成本周的实例：每条 entry × 每个周次，命中规则就改到目标 (week, day)。
  final movedIn = <ScheduleEntry>[]; // 从别处调入本周的课
  final staying = <ScheduleEntry>[]; // 本周原本就上、且没被调走的课
  for (final entry in entries) {
    final weeks = entry.weeks.isEmpty
        ? <int>[for (var w = 1; w <= maxWeek; w++) w]
        : entry.weeks;
    for (final w in weeks) {
      final rule = _firstRuleFor(resolved, w, entry.day);
      if (rule != null) {
        // 这条实例被调走：只有目标周正好是本周才落入渲染。
        if (rule.toWeek == week) {
          movedIn.add(_movedToDay(entry, rule.toDay, week));
        }
      } else if (w == week) {
        staying.add(entry);
      }
    }
  }

  // 2) 合并 + 冲突抑制：调课优先，顶掉同一时段原本的课。
  final conflicts = <int, List<RescheduleConflict>>{};
  final suppressed = <ScheduleEntry>[];
  for (final moved in movedIn) {
    for (final original in staying) {
      if (suppressed.contains(original)) continue;
      if (original.day == moved.day && _overlaps(original, moved)) {
        suppressed.add(original);
        (conflicts[moved.day] ??= <RescheduleConflict>[]).add(
          RescheduleConflict(displaced: original, winner: moved),
        );
      }
    }
  }

  final rendered = <ScheduleEntry>[...movedIn];
  for (final original in staying) {
    if (!suppressed.contains(original)) rendered.add(original);
  }

  // 3) 兜底去重：极端配置下同一门课被多条规则调到同一时段（同 id 同天且重叠），
  //    只保留先到的一条，避免布局键冲突导致两块互相盖住。
  final deduped = <ScheduleEntry>[];
  for (final entry in rendered) {
    final clash = deduped.any(
      (other) =>
          other.id == entry.id &&
          other.day == entry.day &&
          _overlaps(other, entry),
    );
    if (!clash) deduped.add(entry);
  }

  return RescheduleWeekView(entries: deduped, conflicts: conflicts);
}

class _ResolvedRule {
  const _ResolvedRule(this.fromWeek, this.fromDay, this.toWeek, this.toDay);
  final int fromWeek;
  final int fromDay;
  final int toWeek;
  final int toDay;
}

_ResolvedRule _resolve(RescheduleRule rule, DateTime termStart) {
  final fromDate = _dateInTerm(rule.fromMonth, rule.fromDay, termStart);
  final toDate = _dateInTerm(rule.toMonth, rule.toDay, fromDate);
  return _ResolvedRule(
    weekOf(termStart, fromDate),
    fromDate.weekday,
    weekOf(termStart, toDate),
    toDate.weekday,
  );
}

/// 第一条命中的规则（同一来源日期配了多条时取先创建的，行为确定）。
_ResolvedRule? _firstRuleFor(List<_ResolvedRule> rules, int week, int day) {
  for (final rule in rules) {
    if (rule.fromWeek == week && rule.fromDay == day) return rule;
  }
  return null;
}

/// 两条课的节次区间是否相交（同一天才谈得上冲突）。
bool _overlaps(ScheduleEntry a, ScheduleEntry b) =>
    !(a.endPeriod < b.startPeriod || a.startPeriod > b.endPeriod);

DateTime _dateInTerm(int month, int day, DateTime anchor) {
  var date = DateTime(anchor.year, month, day);
  if (date.isBefore(dayOnly(anchor))) {
    date = DateTime(anchor.year + 1, month, day);
  }
  return date;
}

/// 把一条课渲染到目标星期 [day]、目标周 [week]。
///
/// `weeks` 设成 `[week]`：这是"本周这一条被调过来的实例"，详情里据此显示
/// "本周：上"，而不是拿原始周次去判断导致显示成"不上"。`id` 保持原样——
/// 它还是同一门课的记录，详情页不该出现伪造 id。
ScheduleEntry _movedToDay(ScheduleEntry entry, int day, int week) =>
    ScheduleEntry(
      id: entry.id,
      name: entry.name,
      details: entry.details,
      teacher: entry.teacher,
      location: entry.location,
      day: day,
      startPeriod: entry.startPeriod,
      endPeriod: entry.endPeriod,
      weeks: <int>[week],
    );
