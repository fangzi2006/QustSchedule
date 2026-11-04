/// 考试与成绩解析。
///
/// 严格遵守纯 Dart（零 Flutter 依赖）。
/// 提供弹性时间解析器与数据清洗解析器。
library;

import 'types.dart';
import 'urls.dart' show zfCodeToSemester;
import 'util.dart';

/// 弹性考试时间解析器。
///
/// 正方返回的 `kssj` 字符串形式多样：
///  - `2025-01-08 08:30-10:30`
///  - `2025-01-08(08:30~10:30)`
///  - `2025-01-08 08:30~10:30`
///  - `2025年01月08日 08:30-10:30`
///  - `2025/01/08 08:30-10:30`
///  - `2025-01-08 08:30`
///  - `2025-01-08`
/// 通过正则提取年月日与起止时间，解析为本地时区 [DateTime]。
({DateTime? startTime, DateTime? endTime}) parseExamTime(String rawTime) {
  final text = rawTime.trim();
  if (text.isEmpty) return (startTime: null, endTime: null);

  // 匹配年月日：2025-01-08 / 2025/01/08 / 2025.01.08 / 2025年01月08日
  final dateMatch =
      RegExp(r'(\d{4})[年/\-.](\d{1,2})[月/\-.](\d{1,2})日?').firstMatch(text);
  if (dateMatch == null) return (startTime: null, endTime: null);

  try {
    final year = int.parse(dateMatch.group(1)!);
    final month = int.parse(dateMatch.group(2)!);
    final day = int.parse(dateMatch.group(3)!);

    // 匹配时间范围：08:30-10:30 / 08:30~10:30 / 08:30至10:30 / 08:30到10:30
    final timeRangeMatch = RegExp(
      r'(\d{1,2}):(\d{2})(?::\d{2})?\s*(?:[-~～—至到]+|~)\s*(\d{1,2}):(\d{2})(?::\d{2})?',
    ).firstMatch(text);

    if (timeRangeMatch != null) {
      final startH = int.parse(timeRangeMatch.group(1)!);
      final startM = int.parse(timeRangeMatch.group(2)!);
      final endH = int.parse(timeRangeMatch.group(3)!);
      final endM = int.parse(timeRangeMatch.group(4)!);

      return (
        startTime: DateTime(year, month, day, startH, startM),
        endTime: DateTime(year, month, day, endH, endM),
      );
    }

    // 单点时间：08:30
    final singleTimeMatch =
        RegExp(r'(\d{1,2}):(\d{2})(?::\d{2})?').firstMatch(text);
    if (singleTimeMatch != null) {
      final h = int.parse(singleTimeMatch.group(1)!);
      final m = int.parse(singleTimeMatch.group(2)!);
      return (
        startTime: DateTime(year, month, day, h, m),
        endTime: null,
      );
    }

    // 仅有日期
    return (
      startTime: DateTime(year, month, day),
      endTime: null,
    );
  } catch (_) {
    return (startTime: null, endTime: null);
  }
}

/// 新正方考试查询行 (`kwgl/kscx_cxXsksxxIndex.html`) → [ExamItem]。
List<ExamItem> jsonExams(List<Map<String, dynamic>> rows) {
  final result = <ExamItem>[];
  for (final row in rows) {
    final courseName = field(row, const ['kcmc', 'KCMC']);
    if (courseName.isEmpty) continue;

    final examType = field(row, const ['ksmc', 'KSMC']);
    final rawTime = field(row, const ['kssj', 'KSSJ']);
    final parsedTime = parseExamTime(rawTime);

    final campus = field(row, const ['cdxqmc', 'xqmc', 'CDXQMC', 'XQMC']);
    final classroom = field(row, const ['cdmc', 'CDMC', 'jxcdmc', 'cd', 'CD']);
    final seatNumber = field(row, const ['zwh', 'ZWH']);
    final examForm = field(row, const ['ksfs', 'ksxs', 'KSFS', 'KSXS']);
    final status = field(row, const ['kszt', 'bz', 'KSZT', 'BZ']);

    final item = ExamItem(
      courseName: courseName,
      examType: examType,
      startTime: parsedTime.startTime,
      endTime: parsedTime.endTime,
      campus: campus,
      classroom: classroom,
      seatNumber: seatNumber,
      examForm: examForm,
      rawTimeStr: rawTime,
      status: status,
    );
    if (!result.contains(item)) {
      result.add(item);
    }
  }
  return result;
}

/// 新正方成绩查询行 (`cjcx/cjcx_cxDgXscj.html`) → [GradeItem]。
List<GradeItem> jsonGrades(List<Map<String, dynamic>> rows) {
  final result = <GradeItem>[];
  for (final row in rows) {
    final courseName = field(row, const ['kcmc', 'KCMC']);
    if (courseName.isEmpty) continue;

    final courseCode = field(row, const ['kch', 'KCH']);
    final rawXf = field(row, const ['xf', 'XF']);
    final credit = double.tryParse(rawXf) ?? 0.0;

    final rawJd = field(row, const ['jd', 'JD']);
    final gradePoint = double.tryParse(rawJd);

    final rawScore = field(row, const ['cj', 'CJ']);
    final rawBfzcj = field(row, const ['bfzcj', 'BFZCJ']);
    final numericScore = double.tryParse(rawBfzcj);

    final courseNature = field(row, const ['kcxzmc', 'KCXZMC']);
    final courseCategory = field(row, const ['kclbmc', 'KCLBMC']);
    final examNature = field(row, const ['ksxz', 'KSXZ']);

    final xnm = field(row, const ['xnm', 'XNM']);
    final xqm = field(row, const ['xqm', 'XQM']);
    String? termId;
    if (xnm.isNotEmpty && RegExp(r'^\d{4}$').hasMatch(xnm)) {
      final year = int.parse(xnm);
      final sem = zfCodeToSemester[xqm] ?? int.tryParse(xqm);
      if (sem != null) {
        termId = '$year-${year + 1}-$sem';
      }
    }

    result.add(
      GradeItem(
        courseName: courseName,
        courseCode: courseCode,
        credit: credit,
        gradePoint: gradePoint,
        rawScore: rawScore,
        numericScore: numericScore,
        courseNature: courseNature,
        courseCategory: courseCategory,
        examNature: examNature,
        termId: termId,
      ),
    );
  }
  return result;
}
