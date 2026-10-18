/// 作息时间表：把"第几节"映射到真实时间。
///
/// 教务只给"第 1 节""第 3-4 节"，不给几点上课。所以这张表是用户自己的资产：
///  - 可以有**多张**（夏季作息 / 冬季作息）；
///  - 每张有**生效起始日**，当天用「已生效里最新的一张」；
///  - 每节有起止时间（分钟数），课表左侧时间轴直接读它。
///
/// **节数是全局设置**（上午 / 下午 / 晚上各几节），不属于某一张表：
/// 每张表只负责"这些节分别几点上"。这样换作息表不会把课表行数换掉。
///
/// 另提供"快捷设置"：给每节时长、小课间、三段开始时间（可选大课间），
/// 一次算出整张表——避免手工填 10 行时间。
library;

/// 一天里的三个时段。分段是为了"上午/下午/晚上分别设开始时间与大课间"。
enum PeriodGroup {
  morning('上午'),
  afternoon('下午'),
  evening('晚上');

  const PeriodGroup(this.label);

  final String label;
}

/// 一节课的时间。`startMinutes` / `endMinutes` 是从 00:00 起的分钟数，
/// 存分钟而不是 `TimeOfDay`，是为了方便做加法和序列化。
class SectionTime {
  final int period;

  /// 第几节，1-based。
  final int startMinutes;
  final int endMinutes;
  final PeriodGroup group;

  const SectionTime({
    required this.period,
    required this.startMinutes,
    required this.endMinutes,
    required this.group,
  });

  int get durationMinutes => endMinutes - startMinutes;

  SectionTime copyWith({
    int? period,
    int? startMinutes,
    int? endMinutes,
    PeriodGroup? group,
  }) => SectionTime(
    period: period ?? this.period,
    startMinutes: startMinutes ?? this.startMinutes,
    endMinutes: endMinutes ?? this.endMinutes,
    group: group ?? this.group,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'period': period,
    'start': startMinutes,
    'end': endMinutes,
    'group': group.name,
  };

  static SectionTime fromJson(Map<String, dynamic> json) => SectionTime(
    period: (json['period'] as num?)?.toInt() ?? 1,
    startMinutes: (json['start'] as num?)?.toInt() ?? 0,
    endMinutes: (json['end'] as num?)?.toInt() ?? 0,
    group: _groupOf(json['group'] as String?),
  );

  static PeriodGroup _groupOf(String? name) {
    for (final group in PeriodGroup.values) {
      if (group.name == name) return group;
    }
    return PeriodGroup.morning;
  }
}

/// 大课间：某个时段的第 N 节之后休息更久（替代小课间，不是叠加）。
class BigBreak {
  final int afterInGroup;
  final int minutes;

  const BigBreak({required this.afterInGroup, required this.minutes});

  Map<String, Object?> toJson() => <String, Object?>{
    'after': afterInGroup,
    'minutes': minutes,
  };

  static BigBreak fromJson(Map<String, dynamic> json) => BigBreak(
    afterInGroup: (json['after'] as num?)?.toInt() ?? 2,
    minutes: (json['minutes'] as num?)?.toInt() ?? 20,
  );
}

class Timetable {
  final String id;

  /// 可重命名，例如"夏季作息"。
  final String name;

  /// 从哪天开始使用（当天 00:00）。多张表按这个日期排序取最新生效的。
  final DateTime effectiveFrom;

  /// 全部节次，按 period 递增排列。
  final List<SectionTime> sections;

  const Timetable({
    required this.id,
    required this.name,
    required this.effectiveFrom,
    required this.sections,
  });

  int get sectionCount => sections.length;

  /// 某个时段的节数。
  int countOf(PeriodGroup group) =>
      sections.where((section) => section.group == group).length;

  SectionTime? sectionOf(int period) {
    for (final section in sections) {
      if (section.period == period) return section;
    }
    return null;
  }

  Timetable copyWith({
    String? name,
    DateTime? effectiveFrom,
    List<SectionTime>? sections,
  }) => Timetable(
    id: id,
    name: name ?? this.name,
    effectiveFrom: effectiveFrom ?? this.effectiveFrom,
    sections: sections ?? this.sections,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'effectiveFrom': effectiveFrom.toIso8601String(),
    'sections': sections.map((section) => section.toJson()).toList(),
  };

  static Timetable fromJson(Map<String, dynamic> json) {
    final rawSections =
        (json['sections'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(SectionTime.fromJson)
            .toList()
          ..sort((a, b) => a.period.compareTo(b.period));
    return Timetable(
      id: json['id'] as String? ?? 't0',
      name: json['name'] as String? ?? '作息表',
      effectiveFrom:
          DateTime.tryParse(json['effectiveFrom'] as String? ?? '') ??
          DateTime(2020),
      sections: rawSections,
    );
  }
}

/// 课表节数的默认分段：上午 4 / 下午 4 / 晚上 2，共 10 节。
///
/// 只是估算值——各校区作息不同，用户应改成自己班级的实际节数。
const Map<PeriodGroup, int> defaultSectionCounts = <PeriodGroup, int>{
  PeriodGroup.morning: 4,
  PeriodGroup.afternoon: 4,
  PeriodGroup.evening: 2,
};

/// 未配置时的兜底总节数。
const int defaultSectionCount = 10;

/// 三段节数相加。
int countsSum(Map<PeriodGroup, int> counts) {
  var total = 0;
  for (final value in counts.values) {
    if (value > 0) total += value;
  }
  return total;
}

/// 夹到合法范围：每段 0..[maxSections]，总数不超过 [maxSections]。
///
/// 全为 0 时退回默认分段——课表没有节次就没法画。
Map<PeriodGroup, int> clampCounts(Map<PeriodGroup, int> counts) {
  final result = <PeriodGroup, int>{};
  var remaining = maxSections;
  for (final group in PeriodGroup.values) {
    final raw = counts[group] ?? 0;
    final value = raw < 0 ? 0 : (raw > remaining ? remaining : raw);
    result[group] = value;
    remaining -= value;
  }
  if (countsSum(result) < 1) {
    return Map<PeriodGroup, int>.from(defaultSectionCounts);
  }
  return result;
}

/// 快捷设置的输入（**不含节数**：节数是全局设置，见 [defaultSectionCounts]）。
class QuickSetup {
  /// 每节课时长（分钟）。
  final int lessonMinutes;

  /// 小课间时长（分钟）。
  final int shortBreakMinutes;

  /// 每个时段的开始时间（分钟）。
  final Map<PeriodGroup, int> starts;

  /// 大课间：键是时段，值是该时段内的规则。关闭时为空。
  final Map<PeriodGroup, BigBreak> bigBreaks;

  const QuickSetup({
    this.lessonMinutes = 45,
    this.shortBreakMinutes = 5,
    this.starts = const <PeriodGroup, int>{
      PeriodGroup.morning: 8 * 60,
      PeriodGroup.afternoon: 14 * 60,
      PeriodGroup.evening: 18 * 60,
    },
    this.bigBreaks = const <PeriodGroup, BigBreak>{},
  });

  QuickSetup copyWith({
    int? lessonMinutes,
    int? shortBreakMinutes,
    Map<PeriodGroup, int>? starts,
    Map<PeriodGroup, BigBreak>? bigBreaks,
  }) => QuickSetup(
    lessonMinutes: lessonMinutes ?? this.lessonMinutes,
    shortBreakMinutes: shortBreakMinutes ?? this.shortBreakMinutes,
    starts: starts ?? this.starts,
    bigBreaks: bigBreaks ?? this.bigBreaks,
  );

  Map<String, Object?> toJson() => <String, Object?>{
    'lessonMinutes': lessonMinutes,
    'shortBreakMinutes': shortBreakMinutes,
    'starts': <String, int>{
      for (final entry in starts.entries) entry.key.name: entry.value,
    },
    'bigBreaks': <String, Object?>{
      for (final entry in bigBreaks.entries)
        entry.key.name: entry.value.toJson(),
    },
  };

  /// 反序列化：缺字段就用默认值，保证旧配置不会让面板打不开。
  ///
  /// 旧版本在快捷设置里存过 `counts`，这里刻意忽略——节数已移到全局设置。
  static QuickSetup fromJson(Map<String, dynamic> json) {
    const fallback = QuickSetup();
    final starts = <PeriodGroup, int>{...fallback.starts};
    final bigBreaks = <PeriodGroup, BigBreak>{};

    final rawStarts = json['starts'];
    if (rawStarts is Map<String, dynamic>) {
      for (final entry in rawStarts.entries) {
        final group = _groupOf(entry.key);
        final value = (entry.value as num?)?.toInt();
        if (group != null && value != null) starts[group] = value;
      }
    }
    final rawBig = json['bigBreaks'];
    if (rawBig is Map<String, dynamic>) {
      for (final entry in rawBig.entries) {
        final group = _groupOf(entry.key);
        final value = entry.value;
        if (group != null && value is Map<String, dynamic>) {
          bigBreaks[group] = BigBreak.fromJson(value);
        }
      }
    }
    return QuickSetup(
      lessonMinutes:
          (json['lessonMinutes'] as num?)?.toInt() ?? fallback.lessonMinutes,
      shortBreakMinutes:
          (json['shortBreakMinutes'] as num?)?.toInt() ??
          fallback.shortBreakMinutes,
      starts: starts,
      bigBreaks: bigBreaks,
    );
  }

  static PeriodGroup? _groupOf(String name) {
    for (final group in PeriodGroup.values) {
      if (group.name == name) return group;
    }
    return null;
  }
}

/// 单节课时长的合法区间（太短没意义，太长说明填错了）。
const int minLessonMinutes = 20;
const int maxLessonMinutes = 180;
const int maxShortBreakMinutes = 60;
const int maxBigBreakMinutes = 120;

/// 张数上限：够用又不至于把界面撑爆。
const int maxTimetables = 20;
const int maxSections = 20;

/// 快捷设置 → 完整时间表。
///
/// 规则：
///  - 每段从各自的开始时间起步，逐节累加"时长 + 小课间"；
///  - 大课间**替代**该次小课间（不是叠加），所以"上午第 2 节后休息 20 分钟"
///    意味着第 2 节下课 20 分钟后才开始第 3 节；
///  - 节数来自 [counts]（全局设置），上限 [maxSections]。
List<SectionTime> buildSections(
  QuickSetup setup,
  Map<PeriodGroup, int> counts,
) {
  if (setup.lessonMinutes < minLessonMinutes ||
      setup.lessonMinutes > maxLessonMinutes) {
    throw ArgumentError('每节课时长应在 $minLessonMinutes–$maxLessonMinutes 分钟之间');
  }
  if (setup.shortBreakMinutes < 0 ||
      setup.shortBreakMinutes > maxShortBreakMinutes) {
    throw ArgumentError('小课间应在 0–$maxShortBreakMinutes 分钟之间');
  }
  final safe = clampCounts(counts);
  if (countsSum(safe) < 1) {
    throw ArgumentError('至少要有一节课');
  }

  final sections = <SectionTime>[];
  var period = 1;
  for (final group in PeriodGroup.values) {
    final count = safe[group] ?? 0;
    if (count <= 0) continue;
    var cursor = setup.starts[group] ?? 8 * 60;
    final big = setup.bigBreaks[group];
    for (var index = 1; index <= count; index++) {
      final start = cursor;
      final end = start + setup.lessonMinutes;
      sections.add(
        SectionTime(
          period: period,
          startMinutes: start,
          endMinutes: end,
          group: group,
        ),
      );
      period++;
      final isBigBreak = big != null && big.afterInGroup == index;
      cursor = end + (isBigBreak ? big.minutes : setup.shortBreakMinutes);
    }
  }
  return sections;
}

/// 当前该用哪张表：`effectiveFrom <= 今天` 里最新的一张。
///
/// 全都在未来时取最早那张（否则用户新建表后课表就没作息可读了）；
/// 空列表返回 null。
/// 作息表按「月日」循环切换：每年到日子就换成对应那张，不需要手动切。
///
/// 生效日只存月日（年份仅用于内部排序，不参与"哪张在用"的判断）：
///  - 今天是 10 月 18 日，表里有 5 月 1 日与 10 月 1 日 → 取 10 月 1 日那张；
///  - 今天是 1 月 5 日，比所有表都早 → 回绕取月日最大的那张（去年的循环还在用）。
Timetable? activeTimetableAt(List<Timetable> tables, DateTime today) {
  if (tables.isEmpty) return null;
  int key(Timetable table) =>
      table.effectiveFrom.month * 100 + table.effectiveFrom.day;
  final todayKey = today.month * 100 + today.day;
  final sorted = tables.toList()..sort((a, b) => key(a) - key(b));
  final effective = sorted.where((table) => key(table) <= todayKey).toList();
  if (effective.isNotEmpty) return effective.last;
  return sorted.last;
}

/// 按生效月日倒序（列表页展示顺序）。
List<Timetable> sortedTimetables(List<Timetable> tables) {
  int key(Timetable table) =>
      table.effectiveFrom.month * 100 + table.effectiveFrom.day;
  final copy = tables.toList()..sort((a, b) => key(b) - key(a));
  return copy;
}

/// 默认作息：按 [defaultSectionCounts] 生成，供首次启动与"恢复默认"使用。
///
/// 数值只是常见作息的近似，用户应按自己班级改一次。
Timetable defaultTimetable({DateTime? effectiveFrom}) {
  final setup =
      const QuickSetup(
        bigBreaks: <PeriodGroup, BigBreak>{
          PeriodGroup.morning: BigBreak(afterInGroup: 2, minutes: 20),
          PeriodGroup.afternoon: BigBreak(afterInGroup: 2, minutes: 20),
        },
      ).copyWith(
        starts: const <PeriodGroup, int>{
          PeriodGroup.morning: 8 * 60 + 30,
          PeriodGroup.afternoon: 13 * 60 + 30,
          PeriodGroup.evening: 18 * 60,
        },
      );
  return Timetable(
    id: 'default',
    name: '秋冬作息',
    effectiveFrom: effectiveFrom ?? effectiveDateFor(month: 10, day: 1),
    sections: buildSections(setup, defaultSectionCounts),
  );
}

/// 第二套内置预设：夏季作息——下午提前半小时上课。
///
/// 生效月日 5 月 1 日，与秋冬作息（10 月 1 日）按年循环自动切换；
/// 具体时间与生效日都可以在设置里改。
Timetable defaultSummerTimetable({DateTime? effectiveFrom}) {
  final setup =
      const QuickSetup(
        bigBreaks: <PeriodGroup, BigBreak>{
          PeriodGroup.morning: BigBreak(afterInGroup: 2, minutes: 20),
          PeriodGroup.afternoon: BigBreak(afterInGroup: 2, minutes: 20),
        },
      ).copyWith(
        starts: const <PeriodGroup, int>{
          PeriodGroup.morning: 8 * 60 + 30,
          PeriodGroup.afternoon: 14 * 60,
          PeriodGroup.evening: 18 * 60 + 30,
        },
      );
  return Timetable(
    id: 'default-summer',
    name: '春夏作息',
    effectiveFrom: effectiveFrom ?? effectiveDateFor(month: 5, day: 1),
    sections: buildSections(setup, defaultSectionCounts),
  );
}

/// 内置的两套预设（设置 → 作息时间表 里可改时间 / 生效日 / 删增）。
List<Timetable> defaultTimetables() => <Timetable>[
  defaultTimetable(),
  defaultSummerTimetable(),
];

/// 分钟数 → `HH:mm`（时间轴与编辑页共用）。
String formatClock(int minutes) {
  final safe = minutes < 0 ? 0 : (minutes > 24 * 60 ? 24 * 60 : minutes);
  final hour = safe ~/ 60;
  final minute = safe % 60;
  return '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
}

/// `HH:mm` / `H:mm` → 分钟数。解析失败返回 null。
int? parseClock(String text) {
  final match = RegExp(r'^\s*(\d{1,2}):(\d{2})\s*$').firstMatch(text);
  if (match == null) return null;
  final hour = int.parse(match.group(1)!);
  final minute = int.parse(match.group(2)!);
  if (hour > 23 || minute > 59) return null;
  return hour * 60 + minute;
}

/// 把分钟数对齐到 5 分钟（时间轮的可选间隔）。
int snapToFiveMinutes(int minutes) {
  final snapped = ((minutes / 5).round()) * 5;
  return snapped.clamp(0, 24 * 60 - 5);
}

/// 把总节数拆成三段：上午最多 4 节、下午最多 4 节，其余归晚上。
///
/// 只用于旧配置迁移（旧版本只存了一个总数）。
Map<PeriodGroup, int> splitCounts(int total) {
  var remaining = total < 0 ? 0 : total;
  final morning = remaining >= 4 ? 4 : remaining;
  remaining -= morning;
  final afternoon = remaining >= 4 ? 4 : remaining;
  remaining -= afternoon;
  return <PeriodGroup, int>{
    PeriodGroup.morning: morning,
    PeriodGroup.afternoon: afternoon,
    PeriodGroup.evening: remaining,
  };
}

/// 把节次对齐到目标节数（**逐段**对齐，并重算每节的段归属）。
///
/// - 某段多了：从该段尾部裁掉（保留用户改过的前几节）；
/// - 某段少了：按"该段最后一节的时长 + 默认小课间"往后补；
/// - 该段原本没有节次：从 [QuickSetup.starts] 里的默认开始时间起算。
///
/// 之所以逐段处理而不是简单裁尾：把"上午 4 节"改成"上午 2 节"时，
/// 简单裁尾会砍掉晚上的课——那是错的。
List<SectionTime> reconcileSections(
  List<SectionTime> sections,
  Map<PeriodGroup, int> counts,
) {
  final safe = clampCounts(counts);
  const fallback = QuickSetup();
  final result = <SectionTime>[];
  var period = 1;

  for (final group in PeriodGroup.values) {
    final target = safe[group] ?? 0;
    if (target <= 0) continue;
    final existing =
        sections.where((section) => section.group == group).toList()
          ..sort((a, b) => a.period.compareTo(b.period));

    // 该段原本没有节次时用默认开始时间（下午 14:00 之类），
    // 而不是"上一段结束 + 1 小时"——后者会随上午节数漂移，不可预期。
    var cursor = existing.isNotEmpty
        ? existing.last.endMinutes
        : fallback.starts[group]!;
    var duration = existing.isNotEmpty
        ? existing.last.durationMinutes
        : fallback.lessonMinutes;

    for (var index = 0; index < target; index++) {
      if (index < existing.length) {
        final source = existing[index];
        result.add(
          SectionTime(
            period: period,
            startMinutes: source.startMinutes,
            endMinutes: source.endMinutes,
            group: group,
          ),
        );
        cursor = source.endMinutes;
        duration = source.durationMinutes;
      } else {
        // 该段第一节（原来没有任何节次）直接用开始时间，不需要再让出课间。
        final step = existing.isEmpty && index == 0
            ? 0
            : fallback.shortBreakMinutes;
        final start = cursor + step;
        result.add(
          SectionTime(
            period: period,
            startMinutes: start,
            endMinutes: start + duration,
            group: group,
          ),
        );
        cursor = start + duration;
      }
      period++;
    }
  }

  if (result.isEmpty) return buildSections(fallback, safe);
  return result;
}

/// `3 月 2 日`。生效日期只让用户选月日，年份由 [effectiveDateFor] 决定。
String formatMonthDay(int month, int day) => '$month 月 $day 日';

/// 生效日期的展示统一用这个：**只到月日，不带年份**——
/// 作息按月日每年循环，年份是内部排序用的细节，展示出来只会让人困惑。
String formatMonthDayDate(DateTime value) =>
    formatMonthDay(value.month, value.day);

/// 由月日算内部用的生效日期：固定落在**今年**（年份不参与"哪张在用"的
/// 判断，[activeTimetableAt] 只比月日）。曾經"早于今天就落到明年"的规则
/// 会让 10 月 1 日的秋冬作息推到明年、导致当年 10 月反而不生效，已废弃。
DateTime effectiveDateFor({
  required int month,
  required int day,
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  return DateTime(today.year, month, day);
}

/// 某年某月的天数（用于月日轮的第二列）。
int daysInMonth(int year, int month) {
  if (month == 12) return 31;
  return DateTime(year, month + 1, 0).day;
}
