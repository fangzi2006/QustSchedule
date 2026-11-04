/// 系统日历（ICS）导出服务。
///
/// 依据 RFC 5545 规范将考试安排导出为标准 `.ics` 日历文件。
library;

import 'package:zf_academic/zf_academic.dart';

class CalendarExportService {
  /// 生成标准 RFC 5545 iCalendar 内容。
  static String buildIcs(List<ExamItem> exams) {
    final buffer = StringBuffer();
    buffer.write('BEGIN:VCALENDAR\r\n');
    buffer.write('VERSION:2.0\r\n');
    buffer.write('PRODID:-//fangzi//QUSTSchedule//CN\r\n');
    buffer.write('CALSCALE:GREGORIAN\r\n');
    buffer.write('METHOD:PUBLISH\r\n');

    final nowStr = _formatIcsDateTimeUtc(DateTime.now().toUtc());

    for (var i = 0; i < exams.length; i++) {
      final exam = exams[i];
      if (exam.startTime == null) continue;

      final start = _formatIcsDateTime(exam.startTime!);
      final end = exam.endTime != null
          ? _formatIcsDateTime(exam.endTime!)
          : _formatIcsDateTime(exam.startTime!.add(const Duration(hours: 2)));

      final summary = exam.examType.isNotEmpty
          ? '${exam.examType}：${exam.courseName}'
          : '考试：${exam.courseName}';

      final locParts = <String>[
        if (exam.campus.isNotEmpty) exam.campus,
        if (exam.classroom.isNotEmpty) exam.classroom,
        if (exam.seatNumber.isNotEmpty) '(座位号: ${exam.seatNumber})',
      ];
      final location = locParts.join(' ');

      final descParts = <String>[
        if (exam.examForm.isNotEmpty) '考试形式：${exam.examForm}',
        if (exam.examType.isNotEmpty) '考试批次：${exam.examType}',
        if (exam.seatNumber.isNotEmpty) '座位号：${exam.seatNumber}',
        '来源：青科课表通',
      ];
      final description = descParts.join('\n');

      final hash = exam.courseName.hashCode.abs();
      final uid =
          'exam_${hash}_${exam.startTime!.millisecondsSinceEpoch}_$i@qustschedule';

      buffer.write('BEGIN:VEVENT\r\n');
      buffer.write('UID:$uid\r\n');
      buffer.write('DTSTAMP:$nowStr\r\n');
      buffer.write('DTSTART:$start\r\n');
      buffer.write('DTEND:$end\r\n');
      buffer.write('SUMMARY:${_escapeText(summary)}\r\n');
      if (location.isNotEmpty) {
        buffer.write('LOCATION:${_escapeText(location)}\r\n');
      }
      buffer.write('DESCRIPTION:${_escapeText(description)}\r\n');
      buffer.write('STATUS:CONFIRMED\r\n');
      buffer.write('END:VEVENT\r\n');
    }

    buffer.write('END:VCALENDAR\r\n');
    return buffer.toString();
  }

  /// 依据 RFC 5545 第 3.3.11 节，对 TEXT 类型值中的保留字符进行转义。
  static String _escapeText(String text) {
    return text
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll('\r\n', r'\n')
        .replaceAll('\n', r'\n')
        .replaceAll('\r', r'\n');
  }

  static String _formatIcsDateTime(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    final min = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$y$m${d}T$h$min$s';
  }

  static String _formatIcsDateTimeUtc(DateTime dt) {
    return '${_formatIcsDateTime(dt)}Z';
  }
}
