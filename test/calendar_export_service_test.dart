import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/calendar_export_service.dart';
import 'package:zf_academic/zf_academic.dart';

void main() {
  group('CalendarExportService', () {
    test(
      'buildIcs returns valid VCALENDAR envelope when exams list is empty',
      () {
        final ics = CalendarExportService.buildIcs(const []);
        expect(ics, contains('BEGIN:VCALENDAR'));
        expect(ics, contains('VERSION:2.0'));
        expect(ics, contains('PRODID:-//fangzi//QUSTSchedule//CN'));
        expect(ics, contains('END:VCALENDAR'));
        expect(ics, isNot(contains('BEGIN:VEVENT')));
      },
    );

    test('buildIcs skips exams without startTime', () {
      const exam = ExamItem(courseName: '待定考试', rawTimeStr: '待定');
      final ics = CalendarExportService.buildIcs([exam]);
      expect(ics, isNot(contains('BEGIN:VEVENT')));
    });

    test('buildIcs formats full VEVENT for valid exam', () {
      final start = DateTime(2026, 6, 20, 9, 0);
      final end = DateTime(2026, 6, 20, 11, 0);
      final exam = ExamItem(
        courseName: '高等数学A',
        examType: '期末考试',
        campus: '四方校区',
        classroom: '一教201',
        seatNumber: '25',
        examForm: '闭卷',
        startTime: start,
        endTime: end,
      );

      final ics = CalendarExportService.buildIcs([exam]);
      expect(ics, contains('BEGIN:VEVENT'));
      expect(ics, contains('SUMMARY:期末考试：高等数学A'));
      expect(ics, contains('LOCATION:四方校区 一教201 (座位号: 25)'));
      expect(ics, contains('DTSTART:20260620T090000'));
      expect(ics, contains('DTEND:20260620T110000'));
      expect(ics, contains('考试形式：闭卷'));
      expect(ics, contains('座位号：25'));
      expect(ics, contains('END:VEVENT'));
    });

    test('buildIcs defaults endTime to +2 hours if not provided', () {
      final start = DateTime(2026, 6, 20, 14, 0);
      final exam = ExamItem(courseName: '大学物理B', startTime: start);

      final ics = CalendarExportService.buildIcs([exam]);
      expect(ics, contains('DTSTART:20260620T140000'));
      expect(ics, contains('DTEND:20260620T160000'));
    });

    test(
      'buildIcs uses strict RFC 5545 CRLF line endings and escapes text',
      () {
        final start = DateTime(2026, 6, 20, 9, 0);
        final exam = ExamItem(
          courseName: '大学英语(1),分级班;A班',
          examType: '期末,考试',
          campus: '崂山,校区',
          classroom: '教学楼;301',
          examForm: '笔试\\闭卷',
          startTime: start,
        );

        final ics = CalendarExportService.buildIcs([exam]);

        // RFC 5545 requires CRLF \r\n line breaks
        expect(ics.contains('\r\n'), isTrue);
        expect(ics.contains('BEGIN:VCALENDAR\r\n'), isTrue);
        expect(ics.contains('END:VCALENDAR\r\n'), isTrue);

        // Verify escaping of commas and semicolons
        expect(ics, contains(r'大学英语(1)\,分级班\;A班'));
        expect(ics, contains(r'期末\,考试'));
        expect(ics, contains(r'崂山\,校区 教学楼\;301'));
        expect(ics, contains(r'笔试\\闭卷'));
      },
    );
  });
}
