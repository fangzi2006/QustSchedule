/// 课程详情：把一条记录的全部字段摊开（含原始周次与 details）。
///
/// 从 `pages/schedule_page.dart` 抽出来的：调试页也要用同样的字段说明，
/// 两处各写一份迟早会不一致。
library;

import 'package:flutter/material.dart';
import 'package:zf_academic/zf_academic.dart';

import '../theme/course_palette.dart';

/// 周日 → 周六的短标签（1-based 索引用）。
const List<String> kDayLabels = <String>['一', '二', '三', '四', '五', '六', '日'];

/// `[1,2,3,4,6,8]` → `1-4, 6, 8 周`。
String compressWeeks(List<int> weeks) {
  if (weeks.isEmpty) return '';
  final sorted = weeks.toList()..sort();
  final parts = <String>[];
  var start = sorted.first;
  var previous = sorted.first;
  for (final week in sorted.skip(1)) {
    if (week == previous + 1) {
      previous = week;
      continue;
    }
    parts.add(start == previous ? '$start' : '$start-$previous');
    start = week;
    previous = week;
  }
  parts.add(start == previous ? '$start' : '$start-$previous');
  return '${parts.join(', ')} 周';
}

void showEntryDetails(BuildContext context, ScheduleEntry entry, int week) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (context) => _CourseDetailSheet(entry: entry, week: week),
  );
}

class _CourseDetailSheet extends StatelessWidget {
  const _CourseDetailSheet({required this.entry, required this.week});

  final ScheduleEntry entry;
  final int week;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = CoursePalette.of(entry.name);
    final rows = <(String, String)>[
      (
        '时间',
        '周${kDayLabels[entry.day - 1]} 第 ${entry.startPeriod}-${entry.endPeriod} 节',
      ),
      ('周次', entry.weeks.isEmpty ? '每周（未解析到周次）' : compressWeeks(entry.weeks)),
      if (entry.weeks.isNotEmpty)
        ('本周', entry.weeks.contains(week) ? '上（第 $week 周）' : '不上'),
      if (entry.teacher != null) ('教师', entry.teacher!),
      if (entry.location != null) ('地点', entry.location!),
      for (final detail in entry.details ?? const <ScheduleDetail>[])
        (detail.label, detail.value),
      ('课程 ID', entry.id),
    ];

    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: color.background,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.border),
                ),
                child: Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        entry.name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          color: color.foreground,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Text(
                      '第 ${entry.startPeriod}-${entry.endPeriod} 节',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: color.foreground,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              for (final (label, value) in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      SizedBox(
                        width: 68,
                        child: Text(
                          label,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                      ),
                      Expanded(
                        child: SelectableText(
                          value,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
