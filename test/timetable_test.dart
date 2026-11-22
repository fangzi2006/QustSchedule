/// 作息时间表的数据与算法测试。
///
/// 这里错了的后果很具体：课表时间轴会显示错误的上下课时间，
/// 或者"设了 10 节却只显示 8 行"把课藏掉。
library;

import 'dart:convert';
import 'dart:io';

import 'package:qustschedule/src/course_text.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/reminder_planner.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:flutter_test/flutter_test.dart';

/// 构造一份可控的快捷设置（**不含节数**：节数是全局设置）。
QuickSetup setup({
  int lesson = 45,
  int shortBreak = 10,
  Map<PeriodGroup, int>? starts,
  Map<PeriodGroup, BigBreak>? bigBreaks,
}) => QuickSetup(
  lessonMinutes: lesson,
  shortBreakMinutes: shortBreak,
  starts:
      starts ??
      const <PeriodGroup, int>{
        PeriodGroup.morning: 8 * 60,
        PeriodGroup.afternoon: 14 * 60,
        PeriodGroup.evening: 19 * 60,
      },
  bigBreaks: bigBreaks ?? const <PeriodGroup, BigBreak>{},
);

/// 4 / 4 / 2 = 10 节。
Map<PeriodGroup, int> countsOf({
  int morning = 4,
  int afternoon = 4,
  int evening = 2,
}) => <PeriodGroup, int>{
  PeriodGroup.morning: morning,
  PeriodGroup.afternoon: afternoon,
  PeriodGroup.evening: evening,
};

void main() {
  group('buildSections：快捷设置 → 时间表', () {
    test('三段各自按起始时间逐节累加，大课间替代小课间', () {
      final sections = buildSections(setup(), countsOf());
      expect(sections.length, 10);

      expect(sections[0].period, 1);
      expect(formatClock(sections[0].startMinutes), '08:00');
      expect(formatClock(sections[0].endMinutes), '08:45');

      expect(formatClock(sections[1].startMinutes), '08:55');
      expect(formatClock(sections[1].endMinutes), '09:40');

      expect(formatClock(sections[2].startMinutes), '09:50');

      // 下午、晚上从各自的开始时间重新起算，不受上午影响
      final afternoon = sections.firstWhere(
        (s) => s.group == PeriodGroup.afternoon,
      );
      final evening = sections.firstWhere(
        (s) => s.group == PeriodGroup.evening,
      );
      expect(formatClock(afternoon.startMinutes), '14:00');
      expect(formatClock(evening.startMinutes), '19:00');
      expect(formatClock(evening.endMinutes), '19:45');

      // 大课间替代小课间，不是叠加：第 2 节 08:55-09:40，大课间 20 分钟 → 第 3 节 10:00 开始
      final withBigBreak = buildSections(
        setup(
          bigBreaks: const <PeriodGroup, BigBreak>{
            PeriodGroup.morning: BigBreak(afterInGroup: 2, minutes: 20),
          },
        ),
        countsOf(),
      );
      expect(formatClock(withBigBreak[1].endMinutes), '09:40');
      expect(formatClock(withBigBreak[2].startMinutes), '10:00');
    });

    test('某段节数为 0 时跳过该段，每节时长越界报错', () {
      final sections = buildSections(
        setup(),
        countsOf(morning: 2, afternoon: 0, evening: 2),
      );
      expect(sections.length, 4);
      expect(sections[2].group, PeriodGroup.evening);
      expect(sections[2].period, 3);

      expect(
        () => buildSections(setup(lesson: 5), countsOf()),
        throwsArgumentError,
      );
      expect(
        () => buildSections(setup(lesson: 200), countsOf()),
        throwsArgumentError,
      );
    });
  });

  group('生效表选择', () {
    Timetable table(String id, String date, {int count = 8}) => Timetable(
      id: id,
      name: id,
      effectiveFrom: DateTime.parse(date),
      sections: buildSections(
        setup(),
        countsOf(morning: count, afternoon: 0, evening: 0),
      ),
    );

    test('取已生效最新表、按生效日切换、跨年回绕、全在未来、空列表与排序', () {
      final tables = <Timetable>[
        table('winter', '2026-11-01'),
        table('summer', '2026-05-01'),
        table('base', '2020-01-01'),
      ];
      expect(
        activeTimetableAt(tables, DateTime(2026, 10, 17))!.id,
        'summer',
        reason: '冬季作息 11/1 才生效',
      );
      expect(activeTimetableAt(tables, DateTime(2026, 11, 1))!.id, 'winter');
      expect(activeTimetableAt(tables, DateTime(2026, 10, 31))!.id, 'summer');
      expect(
        activeTimetableAt([
          table('future', '2030-01-01'),
        ], DateTime(2026, 10, 17))!.id,
        'future',
      );
      expect(
        activeTimetableAt(const <Timetable>[], DateTime(2026, 10, 17)),
        isNull,
      );

      final sorted = sortedTimetables(<Timetable>[
        table('a', '2020-01-01'),
        table('b', '2026-11-01'),
        table('c', '2024-06-01'),
      ]);
      expect(sorted.map((t) => t.id).toList(), <String>['b', 'c', 'a']);

      // 按月日循环切换（跨年回绕）
      final cycle = <Timetable>[
        table('spring', '2026-05-01'),
        table('autumn', '2026-10-01'),
      ];
      expect(activeTimetableAt(cycle, DateTime(2026, 10, 18))!.id, 'autumn');
      expect(activeTimetableAt(cycle, DateTime(2026, 6, 1))!.id, 'spring');
      expect(activeTimetableAt(cycle, DateTime(2026, 1, 5))!.id, 'autumn');
    });
  });

  group('序列化', () {
    test('Timetable 与 QuickSetup 往返一致，旧版 counts 字段被忽略', () {
      final original = Timetable(
        id: 't1',
        name: '冬季作息',
        effectiveFrom: DateTime(2026, 11, 1),
        sections: buildSections(
          setup(
            bigBreaks: const <PeriodGroup, BigBreak>{
              PeriodGroup.morning: BigBreak(afterInGroup: 2, minutes: 20),
            },
          ),
          countsOf(),
        ),
      );

      final restored = Timetable.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );

      expect(restored.id, 't1');
      expect(restored.name, '冬季作息');
      expect(restored.effectiveFrom, DateTime(2026, 11, 1));
      expect(restored.sectionCount, original.sectionCount);
      expect(
        restored.sections[2].startMinutes,
        original.sections[2].startMinutes,
      );
      expect(restored.sections[2].group, PeriodGroup.morning);

      final originalSetup = setup(
        bigBreaks: const <PeriodGroup, BigBreak>{
          PeriodGroup.afternoon: BigBreak(afterInGroup: 3, minutes: 30),
        },
      );
      final restoredSetup = QuickSetup.fromJson(
        jsonDecode(jsonEncode(originalSetup.toJson())) as Map<String, dynamic>,
      );
      expect(restoredSetup.lessonMinutes, 45);
      expect(restoredSetup.starts[PeriodGroup.afternoon], 14 * 60);
      expect(restoredSetup.bigBreaks[PeriodGroup.afternoon]!.afterInGroup, 3);
      expect(restoredSetup.bigBreaks[PeriodGroup.afternoon]!.minutes, 30);

      final legacySetup = QuickSetup.fromJson(<String, dynamic>{
        'lessonMinutes': 50,
        'counts': <String, int>{'morning': 6, 'afternoon': 6, 'evening': 4},
      });
      expect(legacySetup.lessonMinutes, 50);
      expect(legacySetup.starts[PeriodGroup.morning], 8 * 60);
    });
  });

  group('Preferences 迁移与持久化', () {
    test('内置作息、空/损坏文件兜底及 schema 1/5 作息表迁移', () {
      // 内置两套作息：默认 + 夏季（下午 14:00 起），以及空/损坏文件兜底
      final def = Preferences.decode('');
      expect(
        def.timetables.map((t) => t.id),
        containsAll(<String>['default', 'default-summer']),
      );
      final summer = def.timetables.firstWhere((t) => t.id == 'default-summer');
      final afternoonStart = summer.sections
          .firstWhere(
            (s) => s.period == defaultSectionCounts[PeriodGroup.morning]! + 1,
          )
          .startMinutes;
      expect(formatClock(afternoonStart), '14:00');
      expect(Preferences.decode('not json').timetables, hasLength(2));
      expect(
        Preferences.decode('{"timetables": "oops"}').timetables,
        hasLength(2),
      );

      // schema 1 保留 termStarts 并补两套作息
      final s1 = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 1,
          'termStarts': <String, String>{
            '2026-2027-1': '2026-08-31T00:00:00.000',
          },
        }),
      );
      expect(s1.termStartOf('2026-2027-1'), DateTime(2026, 8, 31));
      expect(s1.timetables, hasLength(2));
      expect(s1.timetables.every((t) => t.sections.isNotEmpty), isTrue);

      // 老用户未改默认表：补插夏季表；改名后不碰
      final untouched = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 5,
          'timetables': <Object?>[defaultTimetable().toJson()],
        }),
      );
      expect(untouched.timetables, hasLength(2));

      final renamed = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 5,
          'timetables': <Object?>[
            defaultTimetable().toJson()..['name'] = '我的作息',
          ],
        }),
      );
      expect(renamed.timetables, hasLength(1));
      expect(renamed.timetables.single.name, '我的作息');
    });

    test('出厂默认线路及 schema 7 补齐、schema 8 删除保留', () {
      final fresh = Preferences.inMemory();
      expect(fresh.schools, <String>['https://jwglxt.qust.edu.cn/jwglxt']);
      expect(fresh.currentSchool, 'https://jwglxt.qust.edu.cn/jwglxt');

      final s7 = Preferences.decode(
        '{"schema":7,"schools":["https://custom.example.edu.cn/jwglxt"]}',
      );
      expect(s7.schools, <String>[
        'https://custom.example.edu.cn/jwglxt',
        'https://jwglxt.qust.edu.cn/jwglxt',
      ]);

      final s8 = Preferences.decode(
        '{"schema":8,"schools":["https://custom.example.edu.cn/jwglxt"]}',
      );
      expect(s8.schools, <String>['https://custom.example.edu.cn/jwglxt']);
    });

    test('schema 4/5/6：静默更新、调课规则与课表备注开关读回及旧版默认值', () {
      final s4 = Preferences.decode(jsonEncode(<String, Object?>{'schema': 4}));
      expect(s4.autoRefresh, isTrue);
      expect(s4.autoRefreshIntervalMinutes, defaultAutoRefreshIntervalMinutes);
      expect(s4.reschedules, isEmpty);
      expect(s4.showScheduleRemarks, isTrue);

      final s5 = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 5,
          'autoRefresh': false,
          'autoRefreshIntervalMinutes': 60,
          'reschedules': <Object?>[
            <String, Object?>{
              'id': 'r1',
              'fromMonth': 10,
              'fromDay': 20,
              'toMonth': 10,
              'toDay': 25,
            },
          ],
        }),
      );
      expect(s5.autoRefresh, isFalse);
      expect(s5.autoRefreshIntervalMinutes, 60);
      expect(s5.reschedules.single.fromMonth, 10);
      expect(s5.reschedules.single.toDay, 25);
      expect(s5.showScheduleRemarks, isTrue);

      final s6 = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 6,
          'showScheduleRemarks': false,
        }),
      );
      expect(s6.showScheduleRemarks, isFalse);
    });

    test('保存多张表后能按生效日选出生效的那张，且不允许清空时间表', () async {
      final prefs = Preferences.inMemory();
      await prefs.saveTimetables(<Timetable>[
        Timetable(
          id: 'winter',
          name: '冬季',
          effectiveFrom: DateTime(2026, 11, 1),
          sections: buildSections(setup(), countsOf()),
        ),
        Timetable(
          id: 'summer',
          name: '夏季',
          effectiveFrom: DateTime(2026, 5, 1),
          sections: buildSections(setup(), countsOf()),
        ),
      ]);

      expect(prefs.timetables, hasLength(2));
      expect(
        prefs.activeTimetable(today: DateTime(2026, 10, 17))!.id,
        'summer',
      );
      expect(prefs.activeTimetable(today: DateTime(2026, 12, 1))!.id, 'winter');

      expect(
        () => prefs.saveTimetables(const <Timetable>[]),
        throwsArgumentError,
      );
    });
  });

  group('时间格式化、房间号文本与全局节数', () {
    test('formatClock / parseClock / snapToFiveMinutes', () {
      expect(formatClock(0), '00:00');
      expect(formatClock(8 * 60), '08:00');
      expect(formatClock(8 * 60 + 5), '08:05');
      expect(formatClock(23 * 60 + 59), '23:59');

      expect(parseClock('08:05'), 485);
      expect(parseClock('8:05'), 485);
      expect(parseClock(' 14:00 '), 840);
      expect(parseClock('25:00'), isNull);
      expect(parseClock('abc'), isNull);

      expect(snapToFiveMinutes(483), 485);
      expect(snapToFiveMinutes(482), 480);
      expect(snapToFiveMinutes(-10), 0);
    });

    test('roomOnly 裁剪多段、校区前缀、空白与空串', () {
      expect(roomOnly('高密校区 M1-239'), 'M1-239');
      expect(roomOnly('青岛科技大学 崂山校区 明德楼 201'), '201');
      expect(roomOnly('崂山校区3教201'), '3教201');
      expect(roomOnly(' 3教201 '), '3教201');
      expect(roomOnly(''), '');
      expect(roomOnly('   '), '');
    });

    test('clampCounts 与旧配置 splitCounts', () {
      final capped = clampCounts(
        countsOf(morning: 10, afternoon: 10, evening: 6),
      );
      expect(countsSum(capped), maxSections);
      expect(capped[PeriodGroup.morning], 10);

      final negative = clampCounts(
        countsOf(morning: -3, afternoon: 1, evening: 0),
      );
      expect(negative[PeriodGroup.morning], 0);
      expect(countsSum(negative), 1);

      final safe = clampCounts(countsOf(morning: 0, afternoon: 0, evening: 0));
      expect(countsSum(safe), defaultSectionCount);
      expect(safe[PeriodGroup.morning], 4);

      expect(splitCounts(10)[PeriodGroup.morning], 4);
      expect(splitCounts(10)[PeriodGroup.afternoon], 4);
      expect(splitCounts(10)[PeriodGroup.evening], 2);
      expect(splitCounts(6)[PeriodGroup.evening], 0);
      expect(splitCounts(2)[PeriodGroup.afternoon], 0);
    });
  });

  group('reconcileSections：逐段对齐', () {
    test('某段变少独立裁剪、变多沿用末节时长后补、从 0 变有课按默认起算', () {
      final base = buildSections(setup(), countsOf());

      // 1. 某段变少只裁这一段，不影响别的段
      final shrunk = reconcileSections(base, countsOf(morning: 2, evening: 2));
      expect(shrunk.length, 8);
      expect(shrunk[0].group, PeriodGroup.morning);
      expect(shrunk[2].group, PeriodGroup.afternoon);
      expect(shrunk[6].group, PeriodGroup.evening);
      expect(shrunk[6].period, 7);
      expect(formatClock(shrunk[6].startMinutes), '19:00');

      // 2. 某段变多：按该段最后一节的时长 + 默认课间往后补
      final grown = reconcileSections(base, countsOf(morning: 6));
      expect(grown.length, 12);
      expect(formatClock(grown[4].startMinutes), '11:35');
      expect(grown[4].durationMinutes, 45, reason: '沿用最后一节的时长');
      expect(grown[4].group, PeriodGroup.morning);
      expect(grown[6].group, PeriodGroup.afternoon, reason: '下午整体后移两节');

      // 3. 某段从 0 变成有课：从默认开始时间起算
      final withoutAfternoon = buildSections(
        setup(),
        countsOf(morning: 4, afternoon: 0, evening: 0),
      );
      final addedAfternoon = reconcileSections(
        withoutAfternoon,
        countsOf(morning: 4, afternoon: 2, evening: 0),
      );
      expect(addedAfternoon.length, 6);
      expect(addedAfternoon[4].group, PeriodGroup.afternoon);
      expect(formatClock(addedAfternoon[4].startMinutes), '14:00');
    });

    test('空表按三段生成、节数夹在 1..20 且已对齐时保留手工修改', () {
      final fromEmpty = reconcileSections(const <SectionTime>[], countsOf());
      expect(fromEmpty.length, 10);
      expect(fromEmpty.first.group, PeriodGroup.morning);
      expect(fromEmpty.last.group, PeriodGroup.evening);

      expect(
        reconcileSections(
          const <SectionTime>[],
          countsOf(morning: 0, afternoon: 0, evening: 0),
        ).length,
        defaultSectionCount,
      );
      expect(
        reconcileSections(
          const <SectionTime>[],
          countsOf(morning: 12, afternoon: 12, evening: 12),
        ).length,
        maxSections,
      );

      final base = buildSections(setup(), countsOf());
      final edited = <SectionTime>[
        base[0].copyWith(startMinutes: 8 * 60 + 10, endMinutes: 8 * 60 + 55),
        ...base.sublist(1),
      ];
      final preserved = reconcileSections(edited, countsOf());
      expect(preserved[0].startMinutes, 8 * 60 + 10);
    });
  });

  group('生效日期（只选月日，按年循环）', () {
    test('effectiveDateFor 一律落在当年，daysInMonth 处理大小月与闰年', () {
      final pastInYear = effectiveDateFor(
        month: 2,
        day: 23,
        now: DateTime(2026, 12, 20),
      );
      expect(pastInYear, DateTime(2026, 2, 23));

      expect(
        effectiveDateFor(month: 11, day: 1, now: DateTime(2026, 10, 17)).year,
        2026,
      );
      expect(
        effectiveDateFor(month: 10, day: 17, now: DateTime(2026, 10, 17)).year,
        2026,
      );

      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 12), 31);
    });
  });

  group('Preferences 全局节数', () {
    test('默认值、旧字段迁移、三段解码范围校验与写入夹取', () async {
      final def = Preferences.decode('');
      expect(def.sectionCount, 10);
      expect(def.sectionCounts[PeriodGroup.morning], 4);
      expect(def.sectionCounts[PeriodGroup.evening], 2);
      expect(
        Preferences.decode(jsonEncode(<String, Object?>{'schema': 1}))
            .sectionCount,
        10,
      );

      final migrated = Preferences.decode(
        jsonEncode(<String, Object?>{'schema': 2, 'sectionCount': 12}),
      );
      expect(migrated.sectionCount, 12);
      expect(migrated.sectionCounts[PeriodGroup.morning], 4);
      expect(migrated.sectionCounts[PeriodGroup.evening], 4);

      final decoded = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 2,
          'sectionCounts': <String, int>{
            'morning': 5,
            'afternoon': 3,
            'evening': 0,
          },
        }),
      );
      expect(decoded.sectionCount, 8);
      expect(decoded.sectionCounts[PeriodGroup.morning], 5);

      final prefs = Preferences.inMemory();
      await prefs.setSectionCounts(
        countsOf(morning: 5, afternoon: 5, evening: 2),
      );
      expect(prefs.sectionCount, 12);
      await prefs.setSectionCounts(
        countsOf(morning: 30, afternoon: 30, evening: 30),
      );
      expect(prefs.sectionCount, maxSections);
      await prefs.setSectionCounts(
        countsOf(morning: 0, afternoon: 0, evening: 0),
      );
      expect(prefs.sectionCount, defaultSectionCount, reason: '全 0 退回默认');
    });
  });

  group('Preferences 格子显示与外观设置', () {
    test('格子显示开关默认值、旧文件兼容与落盘读写', () async {
      expect(Preferences.decode('').showTeacher, isTrue);
      expect(Preferences.decode('').showLocation, isTrue);
      final legacy = Preferences.decode(
        jsonEncode(<String, Object?>{'schema': 2}),
      );
      expect(legacy.showTeacher, isTrue, reason: '升级不该把教师藏起来');
      expect(legacy.showLocation, isTrue);

      final dir = await Directory.systemTemp.createTemp('kb_prefs_show');
      final file = File('${dir.path}/app_prefs.json');
      final prefs = Preferences.decode('', file: file);
      await prefs.setShowTeacher(false);
      await prefs.setShowLocation(false);

      final raw = await file.readAsString();
      final again = Preferences.decode(raw);
      expect(again.showTeacher, isFalse);
      expect(again.showLocation, isFalse);
      expect(
        (jsonDecode(raw) as Map<String, dynamic>)['schema'],
        preferencesSchema,
      );
      await dir.delete(recursive: true);
    });

    test('外观默认值、边界夹取、NaN 退回与落盘读写', () async {
      final def = Preferences.decode('');
      expect(def.cellHeight, defaultCellHeight);
      expect(def.courseTextScale, defaultCourseTextScale);
      expect(
        Preferences.decode(jsonEncode(<String, Object?>{'schema': 3}))
            .cellHeight,
        defaultCellHeight,
      );

      final mem = Preferences.inMemory();
      await mem.setCellHeight(999);
      expect(mem.cellHeight, maxCellHeight);
      await mem.setCellHeight(1);
      expect(mem.cellHeight, minCellHeight);
      await mem.setCourseTextScale(9);
      expect(mem.courseTextScale, maxCourseTextScale);
      await mem.setCourseTextScale(double.nan);
      expect(mem.courseTextScale, defaultCourseTextScale);

      final dir = await Directory.systemTemp.createTemp('kb_prefs_look');
      final file = File('${dir.path}/app_prefs.json');
      final prefs = Preferences.decode('', file: file);
      await prefs.setCellHeight(88);
      await prefs.setCourseTextScale(1.15);

      final again = Preferences.decode(await file.readAsString());
      expect(again.cellHeight, 88);
      expect(again.courseTextScale, closeTo(1.15, 1e-9));
      await dir.delete(recursive: true);
    });
  });

  test('上次登录的账号与学生姓名按学校分别记，兼容旧版与尾斜杠（schema 7 / 13）', () async {
    final prefs = Preferences.inMemory();
    await prefs.setAccountOf('https://a.edu.cn/jwglxt', '111');
    await prefs.setAccountOf('https://b.edu.cn/jwglxt', '222');
    expect(prefs.accountOf('https://a.edu.cn/jwglxt'), '111');
    expect(prefs.accountOf('https://b.edu.cn/jwglxt'), '222');

    await prefs.clearAccountOf('https://a.edu.cn/jwglxt');
    expect(prefs.accountOf('https://a.edu.cn/jwglxt'), isEmpty);
    expect(prefs.accountOf('https://b.edu.cn/jwglxt'), '222', reason: '别清错学校');

    await prefs.setIdentityOf(
      'https://a.edu.cn/jwglxt',
      studentId: '111',
      studentName: '张三',
    );
    await prefs.setIdentityOf(
      'https://b.edu.cn/jwglxt',
      studentId: '222',
      studentName: '李四',
    );
    expect(prefs.accountOf('https://a.edu.cn/jwglxt'), '111');
    expect(prefs.studentNameOf('https://a.edu.cn/jwglxt'), '张三');
    expect(prefs.accountOf('https://b.edu.cn/jwglxt'), '222');
    expect(prefs.studentNameOf('https://b.edu.cn/jwglxt'), '李四');

    await prefs.clearIdentityOf('https://a.edu.cn/jwglxt');
    expect(prefs.accountOf('https://a.edu.cn/jwglxt'), isEmpty);
    expect(prefs.studentNameOf('https://a.edu.cn/jwglxt'), isEmpty);
    expect(prefs.accountOf('https://b.edu.cn/jwglxt'), '222', reason: '别清错学校');
    expect(prefs.studentNameOf('https://b.edu.cn/jwglxt'), '李四');

    // 旧文件（schema 6 / 7）缺字段时为空，不崩溃
    final legacyS6 = Preferences.decode('{"schema":6,"termStarts":{}}');
    expect(legacyS6.accountOf('https://a.edu.cn/jwglxt'), isEmpty);

    final legacyS7 = Preferences.decode(
      '{"schema":7,"lastAccounts":{"https://a.edu.cn/jwglxt/":"111"}}',
    );
    expect(legacyS7.accountOf('https://a.edu.cn/jwglxt'), '111');
    expect(legacyS7.studentNameOf('https://a.edu.cn/jwglxt'), isEmpty);

    // 新格式能读回账号与姓名，且地址比较忽略尾斜杠差异
    final restored = Preferences.decode(
      '{"schema":13,"lastAccounts":{"https://a.edu.cn/jwglxt/":"333"},"lastStudentNames":{"https://a.edu.cn/jwglxt/":"王五"}}',
    );
    expect(restored.accountOf('https://a.edu.cn/jwglxt'), '333');
    expect(restored.studentNameOf('https://a.edu.cn/jwglxt'), '王五');
  });

  group('课前提醒设置（schema 11）', () {
    test('默认值、旧文件缺字段与未知形态回落横幅', () {
      final prefs = Preferences.inMemory();
      expect(prefs.reminderEnabled, isFalse);
      expect(prefs.reminderLeadMinutes, defaultReminderLeadMinutes);
      expect(prefs.reminderStyle, ReminderStyle.banner);
      expect(defaultReminderLeadMinutes, 10);
      expect(reminderLeadOptions, <int>[5, 10, 15, 20, 30]);

      final legacy = Preferences.decode(
        '{"schema":8,"termStarts":{},"autoRefresh":false}',
      );
      expect(legacy.reminderEnabled, isFalse);
      expect(legacy.reminderLeadMinutes, 10);
      expect(legacy.reminderStyle, ReminderStyle.banner);

      final unknown = Preferences.decode(
        '{"schema":10,"reminderStyle":"capsule"}',
      );
      expect(unknown.reminderStyle, ReminderStyle.banner);
    });

    test('提前量收敛与持久化、文件解码校验', () async {
      final mem = Preferences.inMemory();
      await mem.setReminderLeadMinutes(7);
      expect(mem.reminderLeadMinutes, 7);
      await mem.setReminderLeadMinutes(30);
      expect(mem.reminderLeadMinutes, 30);
      await mem.setReminderLeadMinutes(0);
      expect(mem.reminderLeadMinutes, reminderMinLeadMinutes);
      await mem.setReminderLeadMinutes(999);
      expect(mem.reminderLeadMinutes, reminderMaxLeadMinutes);

      final kept = Preferences.decode(
        '{"schema":10,"reminderEnabled":true,"reminderLeadMinutes":7}',
      );
      expect(kept.reminderEnabled, isTrue);
      expect(kept.reminderLeadMinutes, 7);

      final clamped = Preferences.decode(
        '{"schema":10,"reminderLeadMinutes":999}',
      );
      expect(clamped.reminderLeadMinutes, reminderMaxLeadMinutes);

      final dir = await Directory.systemTemp.createTemp('kb_prefs_remind');
      final file = File('${dir.path}/app_prefs.json');
      final prefs = Preferences.decode('', file: file);
      await prefs.setReminderEnabled(true);
      await prefs.setReminderLeadMinutes(20);
      await prefs.setReminderStyle(ReminderStyle.fluid);

      final text = await file.readAsString();
      expect(text, contains('"schema":$preferencesSchema'));
      final again = Preferences.decode(text);
      expect(again.reminderEnabled, isTrue);
      expect(again.reminderLeadMinutes, 20);
      expect(again.reminderStyle, ReminderStyle.fluid);
      await dir.delete(recursive: true);
    });
  });
}
