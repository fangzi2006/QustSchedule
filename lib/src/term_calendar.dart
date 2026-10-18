/// 周次与日期的换算：把"第 N 周"和真实日历对上。
///
/// 教务只给"周次数字"（`1-4周(单)` → [1,3]），学期起始日不在课表数据里。
/// 所以需要两层：
///  1. [estimateTermStart]：按学期估算第 1 周周一（秋季 9 月初、春季 2 月底）；
///  2. 用户在界面上校准一次（"现在其实是第 3 周"）→ [termStartFromWeek] 反推并持久化。
///
/// 一旦 termStart 确定，[weekOf] 就能把任意日期换算成周次，[dateOf] 反过来。
library;

import 'package:zf_academic/zf_academic.dart';

/// 把日期归一到当天 00:00（本地时区），避免时分秒干扰差值计算。
DateTime dayOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

/// 该日期所在周的周一（周一为一周之始，与国际标准一致）。
DateTime mondayOf(DateTime value) {
  final day = dayOnly(value);
  return day.subtract(Duration(days: day.weekday - DateTime.monday));
}

/// 估算学期第 1 周的周一。
///
/// - 秋季学期（semester == 1）：取该年 9 月 1 日所在周的周一；
/// - 春季学期（semester == 2）：取次年 2 月 23 日所在周的周一。
///
/// 青科大实际开学日期会前后浮动一两周，界面上提供"校准"让用户一次对准。
DateTime estimateTermStart(Term term, {DateTime? now}) {
  final today = now ?? DateTime.now();
  final year = term.year ?? today.year;
  final semester = term.semester ?? 1;
  if (semester == 2) {
    return mondayOf(DateTime(year + 1, 2, 23));
  }
  if (semester == 3) {
    // 小学期/夏季学期：多数学校 7 月初开始。
    return mondayOf(DateTime(year + 1, 7, 1));
  }
  return mondayOf(DateTime(year, 9, 1));
}

/// 某天是第几周（1-based）。早于开学日时返回 1（而不是 0 或负数）。
int weekOf(DateTime termStart, DateTime date) {
  final start = mondayOf(termStart);
  final diff = dayOnly(date).difference(start).inDays;
  if (diff < 0) return 1;
  return diff ~/ 7 + 1;
}

/// 第 [week] 周、星期 [day]（1=周一 … 7=周日）对应的日期。
DateTime dateOf(DateTime termStart, int week, int day) {
  final start = mondayOf(termStart);
  return start.add(Duration(days: (week - 1) * 7 + (day - 1)));
}

/// 用户校准："今天是第 [week] 周" → 反推第 1 周周一。
DateTime termStartFromWeek(DateTime today, int week) {
  final thisMonday = mondayOf(today);
  final safeWeek = week < 1 ? 1 : week;
  return thisMonday.subtract(Duration(days: (safeWeek - 1) * 7));
}

/// 这一周的日期范围文案：`3/2 – 3/8`。
String weekRangeLabel(DateTime termStart, int week) {
  final monday = dateOf(termStart, week, 1);
  final sunday = dateOf(termStart, week, 7);
  String fmt(DateTime d) => '${d.month}/${d.day}';
  return '${fmt(monday)} – ${fmt(sunday)}';
}

/// 该课是否在这一周上。[weeks] 为空时视为每周都上（解析不到周次时的容错）。
bool occursInWeek(ScheduleEntry entry, int week) =>
    entry.weeks.isEmpty || entry.weeks.contains(week);

/// 只看这一周要上的课（保持原始顺序）。
List<ScheduleEntry> entriesOfWeek(List<ScheduleEntry> entries, int week) =>
    entries.where((entry) => occursInWeek(entry, week)).toList();

/// 同一天里重叠的课程（重修 / 分班冲突）→ 并列列位。
///
/// 返回值：`课程 id → (index, total)`。`total > 1` 表示这一格要拆成多列并排，
/// 否则两条课会完全重叠、互相盖住。
///
/// 只按"节次区间是否相交"判断重叠，不看课程是否相同：同一门课被教务拆成
/// `1-2` 与 `3-4` 两段时区间不相交，各自占一格，符合预期。
Map<String, ({int index, int total})> conflictLayout(
  List<ScheduleEntry> entries,
) {
  final result = <String, ({int index, int total})>{};
  final byDay = <int, List<ScheduleEntry>>{};
  for (final entry in entries) {
    (byDay[entry.day] ??= <ScheduleEntry>[]).add(entry);
  }
  for (final dayEntries in byDay.values) {
    for (final entry in dayEntries) {
      final overlapping =
          dayEntries
              .where(
                (other) =>
                    !(other.endPeriod < entry.startPeriod ||
                        other.startPeriod > entry.endPeriod),
              )
              .toList()
            ..sort((a, b) => a.id.compareTo(b.id));
      final index = overlapping.indexWhere((other) => other.id == entry.id);
      result[entry.id] = (
        index: index < 0 ? 0 : index,
        total: overlapping.length,
      );
    }
  }
  return result;
}
