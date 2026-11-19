/// 桌面小组件离线快照规划器测试。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/reschedule.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:qustschedule/src/widget_planner.dart';
import 'package:qustschedule/src/widget_style.dart';
import 'package:zf_academic/zf_academic_io.dart';

void main() {
  final termStart = DateTime(2026, 9, 7); // 第 1 周周一
  final now = DateTime(2026, 9, 7, 9, 0);

  test('当天课程与当天考试混排、调课标记与 7/30 天考试收集', () {
    final entries = <ScheduleEntry>[
      const ScheduleEntry(
        id: 'c1',
        name: '大学物理',
        teacher: '王老师',
        location: '崂山校区 弘毅楼 201',
        day: 1,
        startPeriod: 1,
        endPeriod: 2,
        weeks: <int>[1, 2],
      ),
      const ScheduleEntry(
        id: 'c2',
        name: '高等数学',
        teacher: '李老师',
        location: '明德楼 102',
        day: 2, // 周二 9/8 调到周三 9/9 的 3-4 节
        startPeriod: 3,
        endPeriod: 4,
        weeks: <int>[1],
      ),
    ];
    final reschedules = <RescheduleRule>[
      const RescheduleRule(
        id: 'r1',
        fromMonth: 9,
        fromDay: 8,
        toMonth: 9,
        toDay: 9,
      ),
    ];
    final exams = <ExamItem>[
      ExamItem(
        courseName: '离散数学期中',
        startTime: DateTime(2026, 9, 7, 9, 50), // 当天 9/7 考试
        endTime: DateTime(2026, 9, 7, 10, 5),
        classroom: '3教 301',
        seatNumber: '18',
        examForm: '闭卷',
      ),
      ExamItem(
        courseName: '信号与系统',
        startTime: DateTime(2026, 9, 12, 14, 0),
        endTime: DateTime(2026, 9, 12, 16, 0),
        classroom: 'M1-115',
        seatNumber: '06',
        examForm: '笔试',
      ),
    ];

    final snapshot = buildWidgetSnapshot(
      termId: '2026-2027-1',
      entries: entries,
      reschedules: reschedules,
      termStart: termStart,
      timetables: <Timetable>[defaultTimetable()],
      sectionCounts: defaultSectionCounts,
      maxWeek: 18,
      styles: DesktopWidgetConfigSet.defaults(),
      now: now,
      exams: exams,
    );

    expect(snapshot.signedIn, isTrue);
    expect(snapshot.days.length, widgetHorizonDays);

    // 第 1 天（9月7日 周一）：08:00 物理 -> 09:50 离散数学考试（高数已调去周三）
    final day0 = snapshot.days.first;
    expect(day0.dateIso, '2026-09-07');
    expect(day0.week, 1);
    expect(day0.items.length, 2);
    expect(day0.items[0].kind, 'course');
    expect(day0.items[0].title, '大学物理');
    expect(day0.items[0].location, '201');
    expect(day0.items[0].rescheduled, isFalse);

    expect(day0.items[1].kind, 'exam');
    expect(day0.items[1].title, '离散数学期中');
    expect(day0.items[1].seatNumber, '18');

    // 第 3 天（9月9日 周三）：调入的高数 3-4 节，标记 rescheduled = true
    final day2 = snapshot.days[2];
    expect(day2.dateIso, '2026-09-09');
    expect(day2.items.single.title, '高等数学');
    expect(day2.items.single.rescheduled, isTrue);

    // 近期未结束考试列表含周次与星期
    expect(snapshot.upcomingExams.length, 2);
    expect(snapshot.upcomingExams[1].courseName, '信号与系统');
    expect(snapshot.upcomingExams[1].week, 1);
    expect(snapshot.upcomingExams[1].weekday, DateTime.saturday);

    // 本周与下周网格均已预计算，且周三调入的高等数学标有 rescheduled = true
    expect(snapshot.weeks.length, 2);
    expect(snapshot.weeks.first.week, 1);
    expect(snapshot.weeks[1].week, 2);
    final movedBlock = snapshot.weeks.first.blocks.firstWhere(
      (b) => b.name == '高等数学',
    );
    expect(movedBlock.day, 3);
    expect(movedBlock.rescheduled, isTrue);
  });

  test('指纹仅随有效内容与样式改变，不因生成时刻变化', () {
    final a = buildWidgetSnapshot(
      termId: '2026-2027-1',
      entries: const <ScheduleEntry>[],
      reschedules: const <RescheduleRule>[],
      termStart: termStart,
      timetables: <Timetable>[defaultTimetable()],
      sectionCounts: defaultSectionCounts,
      maxWeek: 18,
      styles: DesktopWidgetConfigSet.defaults(),
      now: DateTime(2026, 9, 7, 8, 15),
    );
    final b = buildWidgetSnapshot(
      termId: '2026-2027-1',
      entries: const <ScheduleEntry>[],
      reschedules: const <RescheduleRule>[],
      termStart: termStart,
      timetables: <Timetable>[defaultTimetable()],
      sectionCounts: defaultSectionCounts,
      maxWeek: 18,
      styles: DesktopWidgetConfigSet.defaults(),
      now: DateTime(2026, 9, 7, 11, 30),
    );
    expect(a.fingerprint, b.fingerprint);

    final c = buildWidgetSnapshot(
      termId: '2026-2027-1',
      entries: const <ScheduleEntry>[],
      reschedules: const <RescheduleRule>[],
      termStart: termStart,
      timetables: <Timetable>[defaultTimetable()],
      sectionCounts: defaultSectionCounts,
      maxWeek: 18,
      styles: DesktopWidgetConfigSet.defaults().withStyle(
        DesktopWidgetKind.today,
        DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.today)
            .applyPreset(WidgetStylePreset.darkNight),
      ),
      now: DateTime(2026, 9, 7, 11, 30),
    );
    expect(c.fingerprint, isNot(a.fingerprint));
  });

  test('冲突分栏写入 WeekBlock.conflictIndex / conflictTotal 且未登录快照清空数据', () {
    final snapshot = buildWidgetSnapshot(
      termId: '2026-2027-1',
      entries: const <ScheduleEntry>[
        ScheduleEntry(
          id: 'a1',
          name: '课程A',
          day: 2,
          startPeriod: 1,
          endPeriod: 2,
          weeks: <int>[1],
        ),
        ScheduleEntry(
          id: 'b1',
          name: '课程B',
          day: 2,
          startPeriod: 1,
          endPeriod: 2,
          weeks: <int>[1],
        ),
      ],
      reschedules: const <RescheduleRule>[],
      termStart: termStart,
      timetables: <Timetable>[defaultTimetable()],
      sectionCounts: defaultSectionCounts,
      maxWeek: 18,
      styles: DesktopWidgetConfigSet.defaults(),
      now: now,
    );
    final weekBlocks = snapshot.weeks.first.blocks;
    expect(weekBlocks.length, 2);
    expect(weekBlocks.every((b) => b.conflictTotal == 2), isTrue);
    expect(weekBlocks.map((b) => b.conflictIndex).toSet(), <int>{0, 1});

    final signedOut = buildSignedOutWidgetSnapshot(
      DesktopWidgetConfigSet.defaults(),
      now: now,
    );
    expect(signedOut.signedIn, isFalse);
    expect(signedOut.days, isEmpty);
    expect(signedOut.weeks, isEmpty);
  });

  test('异常节次倒挂与考试名称空白防御', () {
    final snapshot = buildWidgetSnapshot(
      termId: '2026-2027-1',
      entries: const <ScheduleEntry>[
        ScheduleEntry(
          id: 'bad1',
          name: ' 异常节次课 ',
          day: 1,
          startPeriod: 3,
          endPeriod: 1,
          weeks: <int>[1],
        ),
      ],
      reschedules: const <RescheduleRule>[],
      termStart: termStart,
      timetables: <Timetable>[defaultTimetable()],
      sectionCounts: defaultSectionCounts,
      maxWeek: 18,
      styles: DesktopWidgetConfigSet.defaults(),
      now: now,
      exams: <ExamItem>[
        ExamItem(
          courseName: ' 线性代数 ',
          startTime: DateTime(2026, 9, 7, 14, 0),
          endTime: DateTime(2026, 9, 7, 16, 0),
          classroom: '2教 101',
        ),
      ],
    );

    final day0 = snapshot.days.first;
    final course = day0.items.firstWhere((e) => !e.isExam);
    expect(course.title, '异常节次课');
    expect(course.endPeriod, greaterThanOrEqualTo(course.startPeriod));
    expect(course.endMs, greaterThanOrEqualTo(course.startMs));

    final exam = day0.items.firstWhere((e) => e.isExam);
    expect(exam.title, '线性代数');
    expect(snapshot.upcomingExams.single.courseName, '线性代数');
  });
}
