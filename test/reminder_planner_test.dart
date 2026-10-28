/// 课前提醒规划层测试：只测纯函数，不碰平台通道。
///
/// 这里错了的后果很具体：提醒会响在错误的时刻（提前量算错、作息表选错、
/// 调课没跟上），或者干脆不响（事件被当成"已过期"丢掉）。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/reminder_planner.dart';
import 'package:qustschedule/src/reschedule.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:zf_academic/zf_academic.dart';

/// 4 / 4 / 2 = 10 节。
Map<PeriodGroup, int> countsOf() => <PeriodGroup, int>{
  PeriodGroup.morning: 4,
  PeriodGroup.afternoon: 4,
  PeriodGroup.evening: 2,
};

ScheduleEntry entryOf({
  String id = 'c1',
  String name = '高等数学',
  int day = 1,
  int start = 1,
  int end = 2,
  List<int> weeks = const <int>[],
  String? teacher = '张三',
  String? location = '3教201',
}) => ScheduleEntry(
  id: id,
  name: name,
  teacher: teacher,
  location: location,
  day: day,
  startPeriod: start,
  endPeriod: end,
  weeks: weeks,
);

/// 一张作息表：上午 08:00、下午可指定、晚上 19:00，每节 45 分钟。
Timetable tableOf({
  String id = 't1',
  String name = '秋冬作息',
  int month = 10,
  int day = 1,
  int afternoonStart = 14 * 60,
}) => Timetable(
  id: id,
  name: name,
  effectiveFrom: DateTime(2026, month, day),
  sections: buildSections(
    QuickSetup(
      starts: <PeriodGroup, int>{
        PeriodGroup.morning: 8 * 60,
        PeriodGroup.afternoon: afternoonStart,
        PeriodGroup.evening: 19 * 60,
      },
    ),
    countsOf(),
  ),
);

/// 2026-09-07 是周一（第 1 周）。
final DateTime termStart = DateTime(2026, 9, 7);

ReminderPlan plan({
  required List<ScheduleEntry> entries,
  List<RescheduleRule> reschedules = const <RescheduleRule>[],
  List<Timetable>? timetables,
  DateTime? now,
  int lead = 10,
  int maxWeek = 20,
  int horizonDays = 14,
  int maxEvents = reminderMaxEvents,
  ReminderStyle style = ReminderStyle.banner,
  bool fluidUntilEnd = false,
}) => planCourseReminders(
  entries: entries,
  reschedules: reschedules,
  termStart: termStart,
  timetables: timetables ?? <Timetable>[tableOf()],
  sectionCounts: countsOf(),
  now: now ?? DateTime(2026, 9, 7),
  leadMinutes: lead,
  maxWeek: maxWeek,
  horizonDays: horizonDays,
  maxEvents: maxEvents,
  style: style,
  fluidUntilEnd: fluidUntilEnd,
);

void main() {
  group('提前量换算', () {
    test('第 1-2 节 08:00 上课，提前 10 分钟 → 07:50', () {
      final result = plan(entries: <ScheduleEntry>[entryOf()], horizonDays: 1);

      expect(result.events.length, 1);
      final event = result.events.single;
      expect(DateTime.fromMillisecondsSinceEpoch(event.startMs).hour, 8);
      expect(DateTime.fromMillisecondsSinceEpoch(event.startMs).minute, 0);
      expect(DateTime.fromMillisecondsSinceEpoch(event.remindAtMs).hour, 7);
      expect(DateTime.fromMillisecondsSinceEpoch(event.remindAtMs).minute, 50);
      expect(event.startMs - event.remindAtMs, 10 * 60 * 1000);
      expect(event.week, 1);
      expect(event.teacher, '张三');
      expect(event.location, '3教201');
    });

    test('提前量 30 分钟也按 30 分钟算', () {
      final result = plan(
        entries: <ScheduleEntry>[entryOf()],
        horizonDays: 1,
        lead: 30,
      );
      final event = result.events.single;
      expect(event.startMs - event.remindAtMs, 30 * 60 * 1000);
      expect(result.leadMinutes, 30);
    });

    test('提前量收敛到 1~60 分钟，中间值原样保留', () {
      expect(clampReminderLead(-5), reminderMinLeadMinutes);
      expect(clampReminderLead(0), reminderMinLeadMinutes);
      expect(clampReminderLead(1), 1);
      // 滑块可以取任意整数，不能悄悄改回默认档位。
      expect(clampReminderLead(7), 7);
      expect(clampReminderLead(43), 43);
      expect(clampReminderLead(60), reminderMaxLeadMinutes);
      expect(clampReminderLead(999), reminderMaxLeadMinutes);
    });

    test('通知里的地点与课表格子一致（只留房间号）', () {
      final result = plan(
        entries: <ScheduleEntry>[entryOf(location: '高密校区 M1-239')],
        horizonDays: 1,
      );
      expect(result.events.single.location, 'M1-239');
    });

    test('提前量 1 分钟（滑块下界）也算得对', () {
      final result = plan(
        entries: <ScheduleEntry>[entryOf()],
        horizonDays: 1,
        lead: 1,
      );
      final event = result.events.single;
      expect(event.startMs - event.remindAtMs, 60 * 1000);
      expect(result.leadMinutes, 1);
    });

    test('节次结束时刻按 endPeriod 算', () {
      final result = plan(
        entries: <ScheduleEntry>[entryOf(start: 1, end: 2)],
        horizonDays: 1,
      );
      final event = result.events.single;
      // 第 2 节 08:50–09:35（QuickSetup 默认 45 分钟一节、课间 5 分钟）。
      final end = DateTime.fromMillisecondsSinceEpoch(event.endMs);
      expect(end.hour, 9);
      expect(end.minute, 35);
    });
  });

  group('作息表按事件当天选', () {
    final summer = tableOf(
      id: 'summer',
      name: '春夏作息',
      month: 5,
      day: 1,
      afternoonStart: 14 * 60,
    );
    final winter = tableOf(
      id: 'winter',
      name: '秋冬作息',
      month: 10,
      day: 1,
      afternoonStart: 13 * 60 + 30,
    );

    test('6 月的课用 5 月 1 日生效的夏季作息（14:00）', () {
      final result = planCourseReminders(
        entries: <ScheduleEntry>[entryOf(start: 5, end: 6)],
        reschedules: const <RescheduleRule>[],
        termStart: DateTime(2026, 5, 4),
        timetables: <Timetable>[summer, winter],
        sectionCounts: countsOf(),
        now: DateTime(2026, 6, 1),
        leadMinutes: 10,
        maxWeek: 20,
        horizonDays: 1,
      );
      final start = DateTime.fromMillisecondsSinceEpoch(
        result.events.single.startMs,
      );
      expect(start.hour, 14);
      expect(start.minute, 0);
    });

    test('10 月的课用 10 月 1 日生效的秋冬作息（13:30）', () {
      final result = planCourseReminders(
        entries: <ScheduleEntry>[entryOf(start: 5, end: 6)],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[summer, winter],
        sectionCounts: countsOf(),
        now: DateTime(2026, 10, 5),
        leadMinutes: 10,
        maxWeek: 20,
        horizonDays: 1,
      );
      final start = DateTime.fromMillisecondsSinceEpoch(
        result.events.single.startMs,
      );
      expect(start.hour, 13);
      expect(start.minute, 30);
    });

    test('课表节次超出作息表 → 跳过并计数，不抛异常', () {
      // 课表里的课在第 15 节，而全局节数只有 10 节（作息表无论如何也对不齐）。
      final result = plan(
        entries: <ScheduleEntry>[entryOf(start: 15, end: 16)],
        horizonDays: 1,
      );
      expect(result.events, isEmpty);
      expect(result.skipped, 1);
      expect(result.coverageEndMs, isNull);
    });
  });

  group('周次与调课', () {
    test('单周课只在命中周出现', () {
      // 14 天窗口从周一起算只覆盖第 1–2 周，这里放长到 15 天才够到第 3 周。
      final result = plan(
        entries: <ScheduleEntry>[
          entryOf(weeks: <int>[3]),
        ],
        horizonDays: 15,
      );
      expect(result.events.length, 1);
      final start = DateTime.fromMillisecondsSinceEpoch(
        result.events.single.startMs,
      );
      expect(start, DateTime(2026, 9, 21, 8));
      expect(result.events.single.week, 3);
    });

    test('weeks 为空视为每周都上', () {
      final result = plan(entries: <ScheduleEntry>[entryOf()]);
      expect(result.events.length, 2);
      expect(result.events.first.week, 1);
      expect(result.events.last.week, 2);
    });

    test('超出 maxWeek 的日子不排', () {
      final result = plan(entries: <ScheduleEntry>[entryOf()], maxWeek: 1);
      expect(result.events.length, 1);
    });

    test('调课把周一的课挪到周二', () {
      final result = plan(
        entries: <ScheduleEntry>[entryOf()],
        reschedules: <RescheduleRule>[
          const RescheduleRule(
            id: 'r1',
            fromMonth: 9,
            fromDay: 7,
            toMonth: 9,
            toDay: 8,
          ),
        ],
        horizonDays: 2,
      );

      expect(result.events.length, 1);
      final start = DateTime.fromMillisecondsSinceEpoch(
        result.events.single.startMs,
      );
      expect(start, DateTime(2026, 9, 8, 8));
    });

    test('调课顶掉的原课不再提醒', () {
      final result = plan(
        entries: <ScheduleEntry>[
          entryOf(id: 'a', day: 1, start: 1, end: 2, weeks: <int>[1]),
          entryOf(id: 'b', day: 2, start: 1, end: 2, weeks: <int>[1]),
        ],
        reschedules: <RescheduleRule>[
          const RescheduleRule(
            id: 'r1',
            fromMonth: 9,
            fromDay: 7,
            toMonth: 9,
            toDay: 8,
          ),
        ],
        horizonDays: 2,
      );

      // 周二原本的课被调进来的课顶掉，只留一条。
      expect(result.events.length, 1);
      expect(result.events.single.entryId, 'a');
      final start = DateTime.fromMillisecondsSinceEpoch(
        result.events.single.startMs,
      );
      expect(start, DateTime(2026, 9, 8, 8));
    });
  });

  group('过期与截断', () {
    test('已经响过的事件不补发', () {
      final result = plan(
        entries: <ScheduleEntry>[entryOf()],
        horizonDays: 1,
        now: DateTime(2026, 9, 7, 9),
      );
      expect(result.events, isEmpty);
    });

    test('提前量把时刻推到过去时同样不补发', () {
      // 08:00 上课、提前 30 分钟 = 07:30；now 已经是 07:40。
      final result = plan(
        entries: <ScheduleEntry>[entryOf()],
        horizonDays: 1,
        lead: 30,
        now: DateTime(2026, 9, 7, 7, 40),
      );
      expect(result.events, isEmpty);
    });

    test('超过 maxEvents 截断，保留最早的那几条', () {
      final entries = <ScheduleEntry>[
        for (var day = 1; day <= 7; day++)
          entryOf(id: 'c$day', day: day, start: 1, end: 2),
      ];
      final result = plan(entries: entries, maxEvents: 5);

      expect(result.events.length, 5);
      expect(result.truncated, isTrue);
      final times = result.events.map((e) => e.remindAtMs).toList();
      final sorted = times.toList()..sort();
      expect(times, sorted);
      expect(
        result.coverageEndMs,
        result.events.map((e) => e.startMs).reduce((a, b) => a > b ? a : b),
      );
    });

    test('按 remindAtMs 升序，同一时刻按 id 稳定排序', () {
      final result = plan(
        entries: <ScheduleEntry>[
          entryOf(id: 'b', start: 3, end: 4),
          entryOf(id: 'a', start: 1, end: 2),
        ],
        horizonDays: 1,
      );
      expect(result.events.map((e) => e.entryId).toList(), <String>['a', 'b']);
    });
  });

  group('跨月 / 跨年', () {
    test('窗口跨年时日期照常推进', () {
      final result = planCourseReminders(
        entries: <ScheduleEntry>[entryOf(day: 5)],
        reschedules: const <RescheduleRule>[],
        termStart: DateTime(2026, 12, 21),
        timetables: <Timetable>[tableOf()],
        sectionCounts: countsOf(),
        now: DateTime(2026, 12, 21),
        leadMinutes: 10,
        maxWeek: 20,
        horizonDays: 14,
      );

      final days = result.events
          .map((e) => DateTime.fromMillisecondsSinceEpoch(e.startMs))
          .toList();
      expect(days, <DateTime>[
        DateTime(2026, 12, 25, 8),
        DateTime(2027, 1, 1, 8),
      ]);
    });
  });

  group('指纹与 payload', () {
    test('同样的课表与设置 → 同样的指纹（不含规划时刻）', () {
      final first = plan(
        entries: <ScheduleEntry>[entryOf()],
        now: DateTime(2026, 9, 7, 6),
      );
      final second = plan(
        entries: <ScheduleEntry>[entryOf()],
        now: DateTime(2026, 9, 7, 6, 30),
      );
      expect(first.generatedAtMs, isNot(second.generatedAtMs));
      expect(first.fingerprint, second.fingerprint);
    });

    test('改提前量 → 指纹变化', () {
      final ten = plan(entries: <ScheduleEntry>[entryOf()], lead: 10);
      final twenty = plan(entries: <ScheduleEntry>[entryOf()], lead: 20);
      expect(ten.fingerprint, isNot(twenty.fingerprint));
    });

    test('改形态 → 指纹变化（否则旧闹钟不改形态）', () {
      final banner = plan(entries: <ScheduleEntry>[entryOf()]);
      final fluid = plan(
        entries: <ScheduleEntry>[entryOf()],
        style: ReminderStyle.fluid,
      );
      expect(banner.style, ReminderStyle.banner);
      expect(fluid.style, ReminderStyle.fluid);
      expect(banner.fingerprint, isNot(fluid.fingerprint));
    });

    test('改课表 → 指纹变化', () {
      final one = plan(entries: <ScheduleEntry>[entryOf()]);
      final two = plan(
        entries: <ScheduleEntry>[
          entryOf(),
          entryOf(id: 'c9', day: 3),
        ],
      );
      expect(one.fingerprint, isNot(two.fingerprint));
    });

    test('payload 结构：版本、提前量、事件字段齐全', () {
      final result = plan(entries: <ScheduleEntry>[entryOf()], horizonDays: 1);
      final decoded =
          jsonDecode(result.toPayloadJson()) as Map<String, dynamic>;
      expect(decoded['v'], reminderPayloadVersion);
      expect(decoded['leadMinutes'], 10);
      expect(decoded['style'], 'banner');
      // 默认不显示到下课：上课时刻即收起。
      expect(decoded['fluidUntilEnd'], isFalse);
      expect(decoded['generatedAtMs'], result.generatedAtMs);
      expect(decoded['fingerprint'], result.fingerprint);

      final events = decoded['events'] as List<dynamic>;
      expect(events.length, 1);
      final event = events.single as Map<String, dynamic>;
      expect(event['name'], '高等数学');
      expect(event['teacher'], '张三');
      expect(event['location'], '3教201');
      expect(event['startPeriod'], 1);
      expect(event['endPeriod'], 2);
      expect(event['week'], 1);
      expect(event['remindAtMs'], isA<int>());
      expect((event['remindAtMs'] as int) < (event['startMs'] as int), isTrue);
    });

    test('没有事件时 payload 里是空数组', () {
      final result = plan(entries: const <ScheduleEntry>[]);
      final decoded =
          jsonDecode(result.toPayloadJson()) as Map<String, dynamic>;
      expect(decoded['events'], isEmpty);
      expect(result.nextTriggerMs, isNull);
    });
  });

  group('事件 id', () {
    test('同一门课同一天同一起始节 → 同一个 id', () {
      final a = reminderEventId(
        entryId: 'c1',
        date: DateTime(2026, 9, 7),
        startPeriod: 1,
      );
      final b = reminderEventId(
        entryId: 'c1',
        date: DateTime(2026, 9, 7),
        startPeriod: 1,
      );
      expect(a, b);
      expect(a.startsWith('e_'), isTrue);
      expect(a.length, 10);
    });

    test('换一天 / 换节次 / 换课程 → id 不同', () {
      final base = reminderEventId(
        entryId: 'c1',
        date: DateTime(2026, 9, 7),
        startPeriod: 1,
      );
      expect(
        reminderEventId(
          entryId: 'c1',
          date: DateTime(2026, 9, 8),
          startPeriod: 1,
        ),
        isNot(base),
      );
      expect(
        reminderEventId(
          entryId: 'c1',
          date: DateTime(2026, 9, 7),
          startPeriod: 3,
        ),
        isNot(base),
      );
      expect(
        reminderEventId(
          entryId: 'c2',
          date: DateTime(2026, 9, 7),
          startPeriod: 1,
        ),
        isNot(base),
      );
    });
  });
}
