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
    test('按提前量（1/10/30 分钟）计算提醒时刻、endMs 及房间号裁剪', () {
      final defResult = plan(
        entries: <ScheduleEntry>[entryOf(location: '高密校区 M1-239')],
        horizonDays: 1,
      );
      expect(defResult.events.length, 1);
      final defEvent = defResult.events.single;
      final start = DateTime.fromMillisecondsSinceEpoch(defEvent.startMs);
      final remind = DateTime.fromMillisecondsSinceEpoch(defEvent.remindAtMs);
      final end = DateTime.fromMillisecondsSinceEpoch(defEvent.endMs);
      expect(start.hour, 8);
      expect(start.minute, 0);
      expect(remind.hour, 7);
      expect(remind.minute, 50);
      // 第 2 节 08:50–09:35（45 分钟一节、课间 5 分钟）
      expect(end.hour, 9);
      expect(end.minute, 35);
      expect(defEvent.startMs - defEvent.remindAtMs, 10 * 60 * 1000);
      expect(defEvent.week, 1);
      expect(defEvent.teacher, '张三');
      expect(defEvent.location, 'M1-239');

      for (final lead in [1, 30]) {
        final r = plan(
          entries: <ScheduleEntry>[entryOf()],
          horizonDays: 1,
          lead: lead,
        );
        expect(r.leadMinutes, lead);
        expect(
          r.events.single.startMs - r.events.single.remindAtMs,
          lead * 60 * 1000,
        );
      }
    });

    test('提前量收敛到 1~60 分钟，中间值原样保留', () {
      expect(clampReminderLead(-5), reminderMinLeadMinutes);
      expect(clampReminderLead(0), reminderMinLeadMinutes);
      expect(clampReminderLead(1), 1);
      expect(clampReminderLead(7), 7);
      expect(clampReminderLead(43), 43);
      expect(clampReminderLead(60), reminderMaxLeadMinutes);
      expect(clampReminderLead(999), reminderMaxLeadMinutes);
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

    test('按课程当天匹配生效作息表（6 月夏季 14:00 / 10 月秋冬 13:30）', () {
      final juneResult = planCourseReminders(
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
      final juneStart = DateTime.fromMillisecondsSinceEpoch(
        juneResult.events.single.startMs,
      );
      expect(juneStart.hour, 14);
      expect(juneStart.minute, 0);

      final octResult = planCourseReminders(
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
      final octStart = DateTime.fromMillisecondsSinceEpoch(
        octResult.events.single.startMs,
      );
      expect(octStart.hour, 13);
      expect(octStart.minute, 30);
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
    test('单周课命中、weeks 为空默认每周、超出 maxWeek 的日子不排', () {
      // 14 天窗口从周一起算只覆盖第 1–2 周，放长到 15 天够到第 3 周
      final singleWeek = plan(
        entries: <ScheduleEntry>[
          entryOf(weeks: <int>[3]),
        ],
        horizonDays: 15,
      );
      expect(singleWeek.events.length, 1);
      final start = DateTime.fromMillisecondsSinceEpoch(
        singleWeek.events.single.startMs,
      );
      expect(start, DateTime(2026, 9, 21, 8));
      expect(singleWeek.events.single.week, 3);

      // weeks 为空视为每周都上
      final everyWeek = plan(entries: <ScheduleEntry>[entryOf()]);
      expect(everyWeek.events.length, 2);
      expect(everyWeek.events.first.week, 1);
      expect(everyWeek.events.last.week, 2);

      // 超出 maxWeek 的日子不排
      final cappedWeek = plan(entries: <ScheduleEntry>[entryOf()], maxWeek: 1);
      expect(cappedWeek.events.length, 1);
    });

    test('调课把周一的课挪到周二，且周二被顶掉的原课不再提醒', () {
      const rule = RescheduleRule(
        id: 'r1',
        fromMonth: 9,
        fromDay: 7,
        toMonth: 9,
        toDay: 8,
      );
      final moved = plan(
        entries: <ScheduleEntry>[entryOf()],
        reschedules: const <RescheduleRule>[rule],
        horizonDays: 2,
      );
      expect(moved.events.length, 1);
      expect(
        DateTime.fromMillisecondsSinceEpoch(moved.events.single.startMs),
        DateTime(2026, 9, 8, 8),
      );

      final overridden = plan(
        entries: <ScheduleEntry>[
          entryOf(id: 'a', day: 1, start: 1, end: 2, weeks: <int>[1]),
          entryOf(id: 'b', day: 2, start: 1, end: 2, weeks: <int>[1]),
        ],
        reschedules: const <RescheduleRule>[rule],
        horizonDays: 2,
      );
      expect(overridden.events.length, 1);
      expect(overridden.events.single.entryId, 'a');
      expect(
        DateTime.fromMillisecondsSinceEpoch(overridden.events.single.startMs),
        DateTime(2026, 9, 8, 8),
      );
    });
  });

  group('过期与截断', () {
    test('已经响过或提前量把提醒时刻推到过去时均不补发', () {
      final pastCourse = plan(
        entries: <ScheduleEntry>[entryOf()],
        horizonDays: 1,
        now: DateTime(2026, 9, 7, 9),
      );
      expect(pastCourse.events, isEmpty);

      // 08:00 上课、提前 30 分钟 = 07:30；now 已经是 07:40
      final pastLead = plan(
        entries: <ScheduleEntry>[entryOf()],
        horizonDays: 1,
        lead: 30,
        now: DateTime(2026, 9, 7, 7, 40),
      );
      expect(pastLead.events, isEmpty);
    });

    test('按 remindAtMs 升序排列，超过 maxEvents 时截断并保留最早事件', () {
      final ordered = plan(
        entries: <ScheduleEntry>[
          entryOf(id: 'b', start: 3, end: 4),
          entryOf(id: 'a', start: 1, end: 2),
        ],
        horizonDays: 1,
      );
      expect(ordered.events.map((e) => e.entryId).toList(), <String>['a', 'b']);

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

    test('改提前量 / 改形态 / 改课表均会使指纹变化', () {
      final base = plan(entries: <ScheduleEntry>[entryOf()], lead: 10);
      expect(
        base.fingerprint,
        isNot(plan(entries: <ScheduleEntry>[entryOf()], lead: 20).fingerprint),
      );

      final fluid = plan(
        entries: <ScheduleEntry>[entryOf()],
        style: ReminderStyle.fluid,
      );
      expect(base.style, ReminderStyle.banner);
      expect(fluid.style, ReminderStyle.fluid);
      expect(base.fingerprint, isNot(fluid.fingerprint));

      final withExtraCourse = plan(
        entries: <ScheduleEntry>[
          entryOf(),
          entryOf(id: 'c9', day: 3),
        ],
      );
      expect(base.fingerprint, isNot(withExtraCourse.fingerprint));
    });

    test('payload 结构：版本、提前量、事件字段齐全，无事件时为空数组', () {
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

      final emptyResult = plan(entries: const <ScheduleEntry>[]);
      final emptyDecoded =
          jsonDecode(emptyResult.toPayloadJson()) as Map<String, dynamic>;
      expect(emptyDecoded['events'], isEmpty);
      expect(emptyResult.nextTriggerMs, isNull);
    });
  });

  group('事件 id', () {
    test('同课同日同起始节 id 一致；换天 / 换节次 / 换课程 id 不同', () {
      final base = reminderEventId(
        entryId: 'c1',
        date: DateTime(2026, 9, 7),
        startPeriod: 1,
      );
      final same = reminderEventId(
        entryId: 'c1',
        date: DateTime(2026, 9, 7),
        startPeriod: 1,
      );
      expect(base, same);
      expect(base.startsWith('e_'), isTrue);
      expect(base.length, 10);

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
