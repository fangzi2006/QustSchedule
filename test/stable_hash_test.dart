/// 纯 Dart 哈希与文本分词工具测试（含 CoursePalette 索引一致性校验）。
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/formatted_text.dart';
import 'package:qustschedule/src/reminder_planner.dart';
import 'package:qustschedule/src/stable_hash.dart';
import 'package:qustschedule/src/term_calendar.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:qustschedule/src/widget_planner.dart';
import 'package:qustschedule/src/widget_style.dart';
import 'package:qustschedule/theme/course_palette.dart';

void main() {
  group('stable_hash 纯 Dart 工具', () {
    test('courseColorIndex 与 CoursePalette.indexOf 在空串/ASCII/中文上完全一致', () {
      const samples = <String>[
        '',
        '高等数学',
        '数据结构与算法',
        '大学英语(1)',
        'Linear Algebra',
        '软件工程实践Ⅱ',
        '电力电子技术',
        '数学',
        '学数',
      ];
      expect(coursePaletteColorCount, CoursePalette.colors.length);
      for (final name in samples) {
        expect(
          courseColorIndex(name),
          CoursePalette.indexOf(name),
          reason: '课程名「$name」的色板索引应与 CoursePalette.indexOf 一致',
        );
      }
      expect(courseColorIndex('高等数学', colorCount: 0), 0);
      expect(courseColorIndex('高等数学', colorCount: -3), 0);
    });

    test('fnv1a32 / fnv1a32Hex 与提醒、小组件指纹输出保持确定性一致', () {
      expect(fnv1a32Hex(''), '811c9dc5');
      expect(fnv1a32Hex('hello'), '4f9f2cab');

      final eventId = reminderEventId(
        entryId: 'e1',
        date: DateTime(2026, 9, 7),
        startPeriod: 1,
      );
      expect(eventId, 'e_${fnv1a32Hex('e1|20260907|1')}');

      final snap = buildSignedOutWidgetSnapshot(
        DesktopWidgetConfigSet(),
        now: DateTime(2026, 9, 7, 8),
      );
      expect(snap.fingerprint.length, 8);
      expect(RegExp(r'^[0-9a-f]{8}$').hasMatch(snap.fingerprint), isTrue);
    });

    test('timetable 节次查询与 term_calendar dateAtMinutes 纯函数边界行为正确', () {
      final sections = <SectionTime>[
        SectionTime(
          period: 1,
          startMinutes: 8 * 60,
          endMinutes: 8 * 60 + 50,
          group: PeriodGroup.morning,
        ),
        SectionTime(
          period: 2,
          startMinutes: 9 * 60,
          endMinutes: 9 * 60 + 50,
          group: PeriodGroup.morning,
        ),
      ];
      expect(sectionOfPeriod(sections, 1)?.period, 1);
      expect(sectionOfPeriod(sections, 9), isNull);
      expect(sectionStartMinutes(sections, 2), 9 * 60);
      expect(sectionEndMinutes(sections, 2), 9 * 60 + 50);
      expect(sectionStartMinutes(sections, 99), isNull);
      expect(sectionEndMinutes(sections, 99), isNull);

      final dt = dateAtMinutes(DateTime(2026, 9, 7, 23, 59), 14 * 60 + 35);
      expect(dt, DateTime(2026, 9, 7, 14, 35));
    });
  });

  group('formatted_text 纯 Dart 分词', () {
    test('无 WidgetTester 环境下可正确解析空串、纯文本、加粗、代码与未闭合标记', () {
      expect(parseFormattedSegments(''), isEmpty);

      final plain = parseFormattedSegments('普通文本');
      expect(plain.length, 1);
      expect(plain.single.text, '普通文本');
      expect(plain.single.kind, FormattedSegmentKind.plain);

      final mixed = parseFormattedSegments('修复 **登录** 与 `Cookie` 问题');
      expect(
        mixed.map((s) => (s.text, s.kind)).toList(),
        <(String, FormattedSegmentKind)>[
          ('修复 ', FormattedSegmentKind.plain),
          ('登录', FormattedSegmentKind.bold),
          (' 与 ', FormattedSegmentKind.plain),
          ('Cookie', FormattedSegmentKind.code),
          (' 问题', FormattedSegmentKind.plain),
        ],
      );

      final unclosed = parseFormattedSegments('保留 **未闭合 与 `未闭合');
      expect(unclosed.single.kind, FormattedSegmentKind.plain);
      expect(unclosed.single.text, '保留 **未闭合 与 `未闭合');
    });
  });
}
