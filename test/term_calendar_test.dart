/// 周次换算测试：这些函数决定"第几周对应哪几天"，算错会让用户看到错误的课。
library;

import 'package:qustschedule/widgets/course_detail_sheet.dart'
    show compressWeeks;
import 'package:qustschedule/src/term_calendar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zf_academic/zf_academic_io.dart';

ScheduleEntry entryOf(List<int> weeks) => ScheduleEntry(
  id: 'e${weeks.join("-")}',
  name: '课${weeks.length}',
  day: 1,
  startPeriod: 1,
  endPeriod: 2,
  weeks: weeks,
);

void main() {
  group('mondayOf', () {
    test('周六归一到本周一', () {
      // 2026-10-17 是周六。
      expect(mondayOf(DateTime(2026, 10, 17)), DateTime(2026, 10, 12));
    });

    test('周一保持不变，且抹掉时分秒', () {
      expect(mondayOf(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
      expect(mondayOf(DateTime(2026, 10, 12, 23, 59)), DateTime(2026, 10, 12));
    });

    test('周日属于前一个周一（周一是周之始）', () {
      expect(mondayOf(DateTime(2026, 10, 18)), DateTime(2026, 10, 12));
    });
  });

  group('estimateTermStart', () {
    test('秋季学期 = 该年 9 月 1 日所在周的周一', () {
      final start = estimateTermStart(
        const Term(id: '2026-2027-1', name: '秋季', year: 2026, semester: 1),
      );
      expect(start.weekday, DateTime.monday);
      expect(start.month, 8);
      expect(start.day, 31, reason: '2026-09-01 是周二，所以周一是 8/31');
    });

    test('春季学期 = 次年 2 月 23 日所在周的周一', () {
      final start = estimateTermStart(
        const Term(id: '2026-2027-2', name: '春季', year: 2026, semester: 2),
      );
      expect(start.weekday, DateTime.monday);
      expect(start.year, 2027);
      expect(start.month, 2);
    });
  });

  group('weekOf / dateOf 互逆', () {
    final start = DateTime(2026, 8, 31); // 周一

    test('开学当天是第 1 周，本周日仍是第 1 周', () {
      expect(weekOf(start, DateTime(2026, 8, 31)), 1);
      expect(weekOf(start, DateTime(2026, 9, 6)), 1);
    });

    test('下周一进第 2 周', () {
      expect(weekOf(start, DateTime(2026, 9, 7)), 2);
    });

    test('早于开学日一律按第 1 周（不返回 0 或负数）', () {
      expect(weekOf(start, DateTime(2026, 8, 20)), 1);
    });

    test('dateOf 与 weekOf 互为逆运算', () {
      for (var week = 1; week <= 16; week++) {
        for (var day = 1; day <= 7; day++) {
          expect(weekOf(start, dateOf(start, week, day)), week);
        }
      }
    });

    test('第 1 周周一是 dateOf(start, 1, 1)', () {
      expect(dateOf(start, 1, 1), DateTime(2026, 8, 31));
      expect(dateOf(start, 2, 1), DateTime(2026, 9, 7));
      expect(dateOf(start, 2, 7), DateTime(2026, 9, 13));
    });
  });

  group('termStartFromWeek（用户校准）', () {
    test('"今天是第 5 周" → 反推第 1 周周一', () {
      // 2026-10-17（周六）所在周一是 10-12；第 5 周 → 往前 4 周 = 9-14。
      expect(
        termStartFromWeek(DateTime(2026, 10, 17), 5),
        DateTime(2026, 9, 14),
      );
    });

    test('校准后 weekOf 能还原出同一个周次', () {
      final start = termStartFromWeek(DateTime(2026, 10, 17), 7);
      expect(weekOf(start, DateTime(2026, 10, 17)), 7);
    });

    test('第 1 周时第 1 周周一就是本周一', () {
      expect(
        termStartFromWeek(DateTime(2026, 10, 17), 1),
        DateTime(2026, 10, 12),
      );
    });
  });

  group('周次过滤', () {
    test('有周次列表时只在该周出现', () {
      final entry = entryOf(<int>[1, 3, 5]);
      expect(occursInWeek(entry, 1), isTrue);
      expect(occursInWeek(entry, 2), isFalse);
      expect(occursInWeek(entry, 5), isTrue);
    });

    test('周次为空视为每周都有（解析不到周次时的容错）', () {
      final entry = entryOf(const <int>[]);
      expect(occursInWeek(entry, 1), isTrue);
      expect(occursInWeek(entry, 20), isTrue);
    });

    test('entriesOfWeek 保持原顺序并剔除其他周的课', () {
      final entries = <ScheduleEntry>[
        entryOf(<int>[1]),
        entryOf(<int>[2]),
        entryOf(<int>[1, 2]),
      ];
      final week1 = entriesOfWeek(entries, 1);
      expect(week1.length, 2);
      expect(week1.first.weeks, <int>[1]);
    });
  });

  group('展示文案', () {
    test('周范围 3/2 – 3/8', () {
      final start = DateTime(2026, 3, 2);
      expect(weekRangeLabel(start, 1), '3/2 – 3/8');
      expect(weekRangeLabel(start, 2), '3/9 – 3/15');
    });

    test('compressWeeks 压缩连续区间', () {
      expect(compressWeeks(<int>[1, 2, 3, 4, 6, 8]), '1-4, 6, 8 周');
      expect(compressWeeks(<int>[2]), '2 周');
      expect(compressWeeks(<int>[1, 3, 5]), '1, 3, 5 周');
      expect(compressWeeks(const <int>[]), '');
    });
  });
}
