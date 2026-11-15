/// 周次换算测试：这些函数决定"第几周对应哪几天"，算错会让用户看到错误的课。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/term_calendar.dart';
import 'package:qustschedule/widgets/course_detail_sheet.dart'
    show compressWeeks;
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
    test('周一不变、周六/周日归到本周一并抹除时分秒', () {
      expect(mondayOf(DateTime(2026, 10, 12)), DateTime(2026, 10, 12));
      expect(mondayOf(DateTime(2026, 10, 12, 23, 59)), DateTime(2026, 10, 12));
      expect(mondayOf(DateTime(2026, 10, 17)), DateTime(2026, 10, 12));
      expect(mondayOf(DateTime(2026, 10, 18)), DateTime(2026, 10, 12));
    });
  });

  group('estimateTermStart', () {
    test('春秋两季分别定位到 9 月 1 日与次年 2 月 23 日所在周的周一', () {
      final autumn = estimateTermStart(
        const Term(id: '2026-2027-1', name: '秋季', year: 2026, semester: 1),
      );
      expect(autumn.weekday, DateTime.monday);
      expect(autumn.month, 8);
      expect(autumn.day, 31, reason: '2026-09-01 是周二，所以周一是 8/31');

      final spring = estimateTermStart(
        const Term(id: '2026-2027-2', name: '春季', year: 2026, semester: 2),
      );
      expect(spring.weekday, DateTime.monday);
      expect(spring.year, 2027);
      expect(spring.month, 2);
    });
  });

  group('weekOf / dateOf 互逆', () {
    final start = DateTime(2026, 8, 31); // 周一

    test('边界日期、起止日期与逐日换算', () {
      expect(weekOf(start, DateTime(2026, 8, 20)), 1); // 早于开学日兜底第 1 周
      expect(weekOf(start, DateTime(2026, 8, 31)), 1);
      expect(weekOf(start, DateTime(2026, 9, 6)), 1);
      expect(weekOf(start, DateTime(2026, 9, 7)), 2);

      expect(dateOf(start, 1, 1), DateTime(2026, 8, 31));
      expect(dateOf(start, 2, 1), DateTime(2026, 9, 7));
      expect(dateOf(start, 2, 7), DateTime(2026, 9, 13));
    });

    test('dateOf 与 weekOf 在 1..16 周内互为逆运算', () {
      for (var week = 1; week <= 16; week++) {
        for (var day = 1; day <= 7; day++) {
          expect(weekOf(start, dateOf(start, week, day)), week);
        }
      }
    });
  });

  group('termStartFromWeek（用户校准）', () {
    test('按当前日期和周次反推第 1 周周一并与 weekOf 互逆', () {
      expect(
        termStartFromWeek(DateTime(2026, 10, 17), 1),
        DateTime(2026, 10, 12),
      );
      expect(
        termStartFromWeek(DateTime(2026, 10, 17), 5),
        DateTime(2026, 9, 14),
      );
      final start = termStartFromWeek(DateTime(2026, 10, 17), 7);
      expect(weekOf(start, DateTime(2026, 10, 17)), 7);
    });
  });

  group('周次过滤与展示文案', () {
    test('occursInWeek 与 entriesOfWeek（含空周次容错）', () {
      final spaced = entryOf(<int>[1, 3, 5]);
      expect(occursInWeek(spaced, 1), isTrue);
      expect(occursInWeek(spaced, 2), isFalse);
      expect(occursInWeek(spaced, 5), isTrue);

      final emptyWeeks = entryOf(const <int>[]);
      expect(occursInWeek(emptyWeeks, 1), isTrue);
      expect(occursInWeek(emptyWeeks, 20), isTrue);

      final week1 = entriesOfWeek(<ScheduleEntry>[
        entryOf(<int>[1]),
        entryOf(<int>[2]),
        entryOf(<int>[1, 2]),
      ], 1);
      expect(week1.length, 2);
      expect(week1.first.weeks, <int>[1]);
    });

    test('weekRangeLabel 与 compressWeeks', () {
      final start = DateTime(2026, 3, 2);
      expect(weekRangeLabel(start, 1), '3/2 – 3/8');
      expect(weekRangeLabel(start, 2), '3/9 – 3/15');

      expect(compressWeeks(<int>[1, 2, 3, 4, 6, 8]), '1-4, 6, 8 周');
      expect(compressWeeks(<int>[2]), '2 周');
      expect(compressWeeks(<int>[1, 3, 5]), '1, 3, 5 周');
      expect(compressWeeks(const <int>[]), '');
    });
  });
}
