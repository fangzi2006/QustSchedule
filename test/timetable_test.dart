/// 作息时间表的数据与算法测试。
///
/// 这里错了的后果很具体：课表时间轴会显示错误的上下课时间，
/// 或者"设了 10 节却只显示 8 行"把课藏掉。
library;

import 'dart:convert';
import 'dart:io';

import 'package:qustschedule/src/preferences_repository.dart';
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
    test('上午 4 节：每节 45 分钟、课间 10 分钟，逐节累加', () {
      final sections = buildSections(setup(), countsOf());
      expect(sections.length, 10);

      expect(sections[0].period, 1);
      expect(formatClock(sections[0].startMinutes), '08:00');
      expect(formatClock(sections[0].endMinutes), '08:45');

      expect(formatClock(sections[1].startMinutes), '08:55');
      expect(formatClock(sections[1].endMinutes), '09:40');

      expect(formatClock(sections[2].startMinutes), '09:50');
    });

    test('大课间替代小课间，不是叠加', () {
      final sections = buildSections(
        setup(
          bigBreaks: const <PeriodGroup, BigBreak>{
            PeriodGroup.morning: BigBreak(afterInGroup: 2, minutes: 20),
          },
        ),
        countsOf(),
      );

      // 第 2 节 08:55-09:40，大课间 20 分钟 → 第 3 节 10:00 开始。
      expect(formatClock(sections[1].endMinutes), '09:40');
      expect(formatClock(sections[2].startMinutes), '10:00');
    });

    test('下午从自己的开始时间重新起算，不受上午影响', () {
      final sections = buildSections(setup(), countsOf());
      final afternoon = sections.firstWhere(
        (s) => s.group == PeriodGroup.afternoon,
      );
      final evening = sections.firstWhere(
        (s) => s.group == PeriodGroup.evening,
      );
      expect(formatClock(afternoon.startMinutes), '14:00');
      expect(formatClock(evening.startMinutes), '19:00');
      expect(formatClock(evening.endMinutes), '19:45');
    });

    test('某段节数为 0 时跳过该段，不产生空档', () {
      final sections = buildSections(
        setup(),
        countsOf(morning: 2, afternoon: 0, evening: 2),
      );
      expect(sections.length, 4);
      expect(sections[2].group, PeriodGroup.evening);
      expect(sections[2].period, 3);
    });

    test('每节时长越界报错', () {
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

    test('取「已生效里最新」的一张', () {
      final tables = <Timetable>[
        table('winter', '2026-11-01'),
        table('summer', '2026-05-01'),
        table('base', '2020-01-01'),
      ];
      final active = activeTimetableAt(tables, DateTime(2026, 10, 17));
      expect(active!.id, 'summer', reason: '冬季作息 11/1 才生效');
    });

    test('到了生效日当天就切换', () {
      final tables = <Timetable>[
        table('winter', '2026-11-01'),
        table('summer', '2026-05-01'),
      ];
      expect(activeTimetableAt(tables, DateTime(2026, 11, 1))!.id, 'winter');
      expect(activeTimetableAt(tables, DateTime(2026, 10, 31))!.id, 'summer');
    });

    test('全都在未来时取最早那张（不能没有作息）', () {
      final tables = <Timetable>[table('future', '2030-01-01')];
      expect(activeTimetableAt(tables, DateTime(2026, 10, 17))!.id, 'future');
    });

    test('空列表返回 null', () {
      expect(
        activeTimetableAt(const <Timetable>[], DateTime(2026, 10, 17)),
        isNull,
      );
    });

    test('sortedTimetables 按生效月日倒序', () {
      final sorted = sortedTimetables(<Timetable>[
        table('a', '2020-01-01'),
        table('b', '2026-11-01'),
        table('c', '2024-06-01'),
      ]);
      expect(sorted.map((t) => t.id).toList(), <String>['b', 'c', 'a']);
    });

    test('activeTimetableAt 按月日循环切换（跨年回绕）', () {
      final tables = <Timetable>[
        table('spring', '2026-05-01'),
        table('autumn', '2026-10-01'),
      ];
      // 10 月 18 日：秋冬（10/1）是月日 ≤ 今天里最大的 → 生效。
      expect(activeTimetableAt(tables, DateTime(2026, 10, 18))!.id, 'autumn');
      // 6 月 1 日：春夏生效。
      expect(activeTimetableAt(tables, DateTime(2026, 6, 1))!.id, 'spring');
      // 1 月 5 日：比所有表都早 → 回绕取月日最大的（秋冬仍在用）。
      expect(activeTimetableAt(tables, DateTime(2026, 1, 5))!.id, 'autumn');
    });
  });

  group('序列化', () {
    test('Timetable 往返后内容一致', () {
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
    });

    test('QuickSetup 往返后内容一致', () {
      final original = setup(
        bigBreaks: const <PeriodGroup, BigBreak>{
          PeriodGroup.afternoon: BigBreak(afterInGroup: 3, minutes: 30),
        },
      );
      final restored = QuickSetup.fromJson(
        jsonDecode(jsonEncode(original.toJson())) as Map<String, dynamic>,
      );
      expect(restored.lessonMinutes, 45);
      expect(restored.starts[PeriodGroup.afternoon], 14 * 60);
      expect(restored.bigBreaks[PeriodGroup.afternoon]!.afterInGroup, 3);
      expect(restored.bigBreaks[PeriodGroup.afternoon]!.minutes, 30);
    });

    test('旧版 QuickSetup 里的 counts 被忽略（节数已挪到全局设置）', () {
      final restored = QuickSetup.fromJson(<String, dynamic>{
        'lessonMinutes': 50,
        'counts': <String, int>{'morning': 6, 'afternoon': 6, 'evening': 4},
      });
      expect(restored.lessonMinutes, 50);
      expect(restored.starts[PeriodGroup.morning], 8 * 60);
    });
  });

  group('Preferences 迁移与持久化', () {
    test('schema 1 的旧文件：保留 termStarts 并补一张默认表', () {
      final prefs = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 1,
          'termStarts': <String, String>{
            '2026-2027-1': '2026-08-31T00:00:00.000',
          },
        }),
      );

      expect(prefs.termStartOf('2026-2027-1'), DateTime(2026, 8, 31));
      expect(prefs.timetables, hasLength(2), reason: '升级后要有两套内置作息');
      expect(prefs.timetables.every((t) => t.sections.isNotEmpty), isTrue);
    });

    test('空文件 / 损坏文件都按默认设置处理，不抛异常', () {
      expect(Preferences.decode('').timetables, hasLength(2));
      expect(Preferences.decode('not json').timetables, hasLength(2));
      expect(
        Preferences.decode('{"timetables": "oops"}').timetables,
        hasLength(2),
      );
    });

    test('内置两套作息：默认 + 夏季（夏季下午 14:00 起）', () {
      final prefs = Preferences.decode('');
      expect(
        prefs.timetables.map((t) => t.id),
        containsAll(<String>['default', 'default-summer']),
      );
      final summer = prefs.timetables.firstWhere(
        (t) => t.id == 'default-summer',
      );
      final afternoonStart = summer.sections
          .firstWhere(
            (s) => s.period == defaultSectionCounts[PeriodGroup.morning]! + 1,
          )
          .startMinutes;
      expect(formatClock(afternoonStart), '14:00');
    });

    test('老用户只有一张未动过的默认表：补插夏季表；动过就不碰', () {
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

    test('schema 5：静默更新开关/间隔/调课规则能正确读回', () {
      final prefs = Preferences.decode(
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

      expect(prefs.autoRefresh, isFalse);
      expect(prefs.autoRefreshIntervalMinutes, 60);
      expect(prefs.reschedules, hasLength(1));
      expect(prefs.reschedules.single.fromMonth, 10);
      expect(prefs.reschedules.single.toDay, 25);
    });

    test('schema 6：是否显示课表备注能正确读回；缺字段默认显示', () {
      final off = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 6,
          'showScheduleRemarks': false,
        }),
      );
      expect(off.showScheduleRemarks, isFalse);

      final legacy = Preferences.decode(
        jsonEncode(<String, Object?>{'schema': 5}),
      );
      expect(legacy.showScheduleRemarks, isTrue, reason: '旧文件缺字段默认显示');
    });

    test('旧文件缺 schema 5 字段：静默更新默认开、间隔 30、无调课', () {
      final prefs = Preferences.decode(
        jsonEncode(<String, Object?>{'schema': 4}),
      );

      expect(prefs.autoRefresh, isTrue);
      expect(prefs.autoRefreshIntervalMinutes, 30);
      expect(prefs.reschedules, isEmpty);
    });

    test('保存多张表后能按生效日选出生效的那张', () async {
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
    });

    test('不允许把时间表清空', () async {
      final prefs = Preferences.inMemory();
      expect(
        () => prefs.saveTimetables(const <Timetable>[]),
        throwsArgumentError,
      );
    });
  });

  group('时间格式化', () {
    test('formatClock 补零', () {
      expect(formatClock(0), '00:00');
      expect(formatClock(8 * 60), '08:00');
      expect(formatClock(8 * 60 + 5), '08:05');
      expect(formatClock(23 * 60 + 59), '23:59');
    });

    test('parseClock 解析容错', () {
      expect(parseClock('08:05'), 485);
      expect(parseClock('8:05'), 485);
      expect(parseClock(' 14:00 '), 840);
      expect(parseClock('25:00'), isNull);
      expect(parseClock('abc'), isNull);
    });

    test('snapToFiveMinutes 对齐到 5 分钟', () {
      expect(snapToFiveMinutes(483), 485);
      expect(snapToFiveMinutes(482), 480);
      expect(snapToFiveMinutes(-10), 0);
    });
  });

  group('全局节数（三段）', () {
    test('clampCounts：每段非负、总数不超过 20', () {
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
    });

    test('全 0 退回默认分段，而不是画一张空表', () {
      final safe = clampCounts(countsOf(morning: 0, afternoon: 0, evening: 0));
      expect(countsSum(safe), defaultSectionCount);
      expect(safe[PeriodGroup.morning], 4);
    });

    test('splitCounts 只用于旧配置迁移', () {
      expect(splitCounts(10)[PeriodGroup.morning], 4);
      expect(splitCounts(10)[PeriodGroup.afternoon], 4);
      expect(splitCounts(10)[PeriodGroup.evening], 2);
      expect(splitCounts(6)[PeriodGroup.evening], 0);
      expect(splitCounts(2)[PeriodGroup.afternoon], 0);
    });
  });

  group('reconcileSections：逐段对齐', () {
    test('某段变少只裁这一段，不影响别的段', () {
      final base = buildSections(setup(), countsOf());
      final result = reconcileSections(base, countsOf(morning: 2, evening: 2));

      expect(result.length, 8);
      expect(result[0].group, PeriodGroup.morning);
      expect(result[2].group, PeriodGroup.afternoon);
      expect(result[6].group, PeriodGroup.evening);
      // 晚上的课必须还在，且节次重排为 7–8。
      expect(result[6].period, 7);
      expect(formatClock(result[6].startMinutes), '19:00');
    });

    test('某段变多：按该段最后一节的时长 + 默认课间往后补', () {
      final base = buildSections(setup(), countsOf());
      final result = reconcileSections(base, countsOf(morning: 6));

      expect(result.length, 12);
      // 第 4 节 10:45–11:30 → 补出来的第 5 节按默认课间（5 分钟）11:35 开始。
      expect(formatClock(result[4].startMinutes), '11:35');
      expect(result[4].durationMinutes, 45, reason: '沿用最后一节的时长');
      expect(result[4].group, PeriodGroup.morning);
      expect(result[6].group, PeriodGroup.afternoon, reason: '下午整体后移两节');
    });

    test('某段从 0 变成有课：从默认开始时间起算', () {
      final base = buildSections(
        setup(),
        countsOf(morning: 4, afternoon: 0, evening: 0),
      );
      final result = reconcileSections(
        base,
        countsOf(morning: 4, afternoon: 2, evening: 0),
      );

      expect(result.length, 6);
      expect(result[4].group, PeriodGroup.afternoon);
      expect(formatClock(result[4].startMinutes), '14:00');
    });

    test('空表按三段生成', () {
      final result = reconcileSections(const <SectionTime>[], countsOf());
      expect(result.length, 10);
      expect(result.first.group, PeriodGroup.morning);
      expect(result.last.group, PeriodGroup.evening);
    });

    test('节数被夹在 1..20', () {
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
    });

    test('已经对齐时原样返回（保留手工改过的时间）', () {
      final base = buildSections(setup(), countsOf());
      final edited = <SectionTime>[
        base[0].copyWith(startMinutes: 8 * 60 + 10, endMinutes: 8 * 60 + 55),
        ...base.sublist(1),
      ];
      final result = reconcileSections(edited, countsOf());
      expect(result[0].startMinutes, 8 * 60 + 10);
    });
  });

  group('生效日期（只选月日，按年循环）', () {
    test('一律落在当年（年份不参与切换判断）', () {
      final date = effectiveDateFor(
        month: 2,
        day: 23,
        now: DateTime(2026, 12, 20),
      );
      expect(date.year, 2026);
      expect(date.month, 2);
      expect(date.day, 23);
    });

    test('未来的月日留在今年', () {
      final date = effectiveDateFor(
        month: 11,
        day: 1,
        now: DateTime(2026, 10, 17),
      );
      expect(date.year, 2026);
    });

    test('同一天算今年（不跳到明年）', () {
      expect(
        effectiveDateFor(month: 10, day: 17, now: DateTime(2026, 10, 17)).year,
        2026,
      );
    });

    test('daysInMonth 处理大小月与闰年', () {
      expect(daysInMonth(2026, 1), 31);
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 4), 30);
      expect(daysInMonth(2026, 12), 31);
    });
  });

  group('Preferences 全局节数', () {
    test('默认 4/4/2；旧文件缺字段时也是 10 节', () {
      final prefs = Preferences.decode('');
      expect(prefs.sectionCount, 10);
      expect(prefs.sectionCounts[PeriodGroup.morning], 4);
      expect(prefs.sectionCounts[PeriodGroup.evening], 2);
      expect(
        Preferences.decode(jsonEncode(<String, Object?>{'schema': 1}))
            .sectionCount,
        10,
      );
    });

    test('旧的单个 sectionCount 迁移成三段', () {
      final prefs = Preferences.decode(
        jsonEncode(<String, Object?>{'schema': 2, 'sectionCount': 12}),
      );
      expect(prefs.sectionCount, 12);
      expect(prefs.sectionCounts[PeriodGroup.morning], 4);
      expect(prefs.sectionCounts[PeriodGroup.evening], 4);
    });

    test('新格式直接读三段，并夹在合法范围', () {
      final prefs = Preferences.decode(
        jsonEncode(<String, Object?>{
          'schema': 2,
          'sectionCounts': <String, int>{
            'morning': 5,
            'afternoon': 3,
            'evening': 0,
          },
        }),
      );
      expect(prefs.sectionCount, 8);
      expect(prefs.sectionCounts[PeriodGroup.morning], 5);
    });

    test('写入时夹取，且三段之和等于 sectionCount', () async {
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

  group('Preferences 格子显示开关', () {
    test('默认都显示；旧文件没有这两个字段也按显示处理', () {
      expect(Preferences.decode('').showTeacher, isTrue);
      expect(Preferences.decode('').showLocation, isTrue);
      final legacy = Preferences.decode(
        jsonEncode(<String, Object?>{'schema': 2}),
      );
      expect(legacy.showTeacher, isTrue, reason: '升级不该把教师藏起来');
      expect(legacy.showLocation, isTrue);
    });

    test('关掉后落盘，重新读回来还是关着', () async {
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
  });

  group('Preferences 外观', () {
    test('默认值：格子 72、字号 100%；旧文件缺字段也是这个值', () {
      final prefs = Preferences.decode('');
      expect(prefs.cellHeight, defaultCellHeight);
      expect(prefs.courseTextScale, defaultCourseTextScale);
      expect(
        Preferences.decode(jsonEncode(<String, Object?>{'schema': 3}))
            .cellHeight,
        defaultCellHeight,
      );
    });

    test('越界的值按上下限夹住，NaN 退回默认', () async {
      final prefs = Preferences.inMemory();
      await prefs.setCellHeight(999);
      expect(prefs.cellHeight, maxCellHeight);
      await prefs.setCellHeight(1);
      expect(prefs.cellHeight, minCellHeight);
      await prefs.setCourseTextScale(9);
      expect(prefs.courseTextScale, maxCourseTextScale);
      await prefs.setCourseTextScale(double.nan);
      expect(prefs.courseTextScale, defaultCourseTextScale);
    });

    test('落盘后重新读回来一致', () async {
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
}
