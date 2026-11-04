/// 学期选择与学籍学年换算。
///
/// 包含三大核心能力：
///  1. 从学号提取入学年份（支持青科大 10 位学号前两位年份、4 位直接年份等；解析失败安全回退）；
///  2. 学期筛选：过滤早于入学年份的历史学期，且将未来学期限制在当前学年以内；
///  3. 学期文案映射：在籍学期转换为「大一/大二/大三/大四 上/下学期」，超出 4 年回退为学年学期名。
library;

import 'package:zf_academic/zf_academic.dart';

/// 从学号中解析入学年份。
///
/// 规则：
///  - 10 位学号如 `2407720102`：前 2 位为入学年份后两位 `24` → 2024；
///  - 4 位年份前缀如 `20240001`、`2026000001`：前 4 位即为入学年份 2024、2026；
///  - 解析失败或无法推断时返回 null，调用方走通用回退。
int? parseEnrollmentYear(String? studentId, {DateTime? now}) {
  if (studentId == null) return null;
  final trimmed = studentId.trim();
  if (trimmed.isEmpty) return null;

  final match = RegExp(r'\d{2,}').firstMatch(trimmed);
  if (match == null) return null;
  final digits = match.group(0)!;
  if (digits.length < 2) return null;
  if (digits.length == 3) return null;

  final currentYear = (now ?? DateTime.now()).year;
  final minYear = currentYear - 15; // 允许的最大往届年限（在校/近期毕业生）
  final maxYear = currentYear + 1; // 允许预招或近期新生

  bool isValidYear(int y) => y >= minYear && y <= maxYear;

  // 1. 若为 8 位学号且以 19 或 20 开头，固定为 4 位年份前缀 (如 20240001)
  if (digits.length == 8 &&
      (digits.startsWith('19') || digits.startsWith('20'))) {
    final y4 = int.tryParse(digits.substring(0, 4));
    if (y4 != null && isValidYear(y4)) {
      return y4;
    }
    return null;
  }

  // 2. 若长度正好为 4 位，直接按 4 位年份解析
  if (digits.length == 4) {
    final y4 = int.tryParse(digits);
    if (y4 != null && isValidYear(y4)) {
      return y4;
    }
    return null;
  }

  // 3. 若为 10 位学号（青科大标准本科 10 位学号 YY + CC + MM + NN + SS，前 2 位严格对应入学年份）：
  if (digits.length == 10) {
    final y2 = int.tryParse(digits.substring(0, 2));
    if (y2 != null) {
      final yFull = y2 >= 80 ? (1900 + y2) : (2000 + y2);
      if (isValidYear(yFull)) return yFull;
    }
  }

  // 4. 其它长度：先尝试前 4 位年份
  if (digits.length >= 4) {
    final y4 = int.tryParse(digits.substring(0, 4));
    if (y4 != null && isValidYear(y4)) {
      return y4;
    }
  }

  // 5. 尝试前 2 位年份 (如 24 -> 2024, 20 -> 2020)
  final y2 = int.tryParse(digits.substring(0, 2));
  if (y2 != null) {
    final yFull = y2 >= 80 ? (1900 + y2) : (2000 + y2);
    if (isValidYear(yFull)) {
      return yFull;
    }
  }

  return null;
}

/// 估算或获取当前的学年（如 2024 代表 2024-2025 学年）。
int estimateCurrentAcademicYear({
  DateTime? now,
  String? activeTermId,
  String? serverCurrentTermId,
}) {
  int? parseYear(String? id) {
    if (id == null || id.isEmpty) return null;
    return parseTerm(id)?.year;
  }

  final selectedYear = parseYear(activeTermId);
  final serverYear = parseYear(serverCurrentTermId);
  final calYear = calendarTerm(now).year ?? (now ?? DateTime.now()).year;

  var current = serverYear ?? calYear;
  if (selectedYear != null && selectedYear > current) {
    current = selectedYear;
  }
  return current;
}

/// 筛选学期列表。
///
/// 规则：
///  1. 不展示早于入学年份的历史学期；
///  2. 未来学期限制在当前学年学期以内（若当前为秋季第 1 学期，不展示同年的春季第 2 学期）；
///  3. 始终保留当前已选中的学期（即使特殊情况下不在计算区间内）；
///  4. 若原始列表为空且已知入学年份，根据在校区间推导有效学期列表。
List<Term> filterTerms({
  required List<Term> terms,
  String? studentId,
  int? enrollmentYear,
  int? currentAcademicYear,
  int? currentSemester,
  String? currentTermId,
  String? serverCurrentTermId,
  DateTime? now,
}) {
  final resolvedEnrollmentYear =
      enrollmentYear ?? parseEnrollmentYear(studentId, now: now);

  int maxYear;
  int maxSemester;

  final parsedServer =
      (serverCurrentTermId != null && serverCurrentTermId.isNotEmpty)
      ? parseTerm(serverCurrentTermId)
      : null;

  if (parsedServer != null && parsedServer.year != null) {
    maxYear = parsedServer.year!;
    maxSemester =
        resolveSemesterCode(parsedServer.semester, serverCurrentTermId!) ?? 1;
  } else if (currentAcademicYear != null &&
      currentSemester == null &&
      now == null) {
    // 仅显式指定了学年而未指定学期或日期时，允许该学年的所有学期 (1, 2)
    maxYear = currentAcademicYear;
    maxSemester = 3;
  } else {
    final cal = calendarTerm(now);
    maxYear = cal.year ?? (now ?? DateTime.now()).year;
    maxSemester = cal.semester ?? 1;
  }

  if (currentAcademicYear != null) {
    maxYear = currentAcademicYear;
  }
  if (currentSemester != null) {
    maxSemester = currentSemester;
  }

  // 如果原始列表为空但有入学年份，根据年份区间生成完整可选学期
  if (terms.isEmpty) {
    final list = <Term>[];
    if (resolvedEnrollmentYear != null) {
      for (var y = maxYear; y >= resolvedEnrollmentYear; y--) {
        if (y < maxYear || maxSemester >= 2) {
          list.add(
            Term(
              id: '$y-${y + 1}-2',
              name: '$y-${y + 1} 第2学期',
              year: y,
              semester: 2,
            ),
          );
        }
        list.add(
          Term(
            id: '$y-${y + 1}-1',
            name: '$y-${y + 1} 第1学期',
            year: y,
            semester: 1,
          ),
        );
      }
    }
    if (currentTermId != null &&
        currentTermId.isNotEmpty &&
        !list.any((t) => t.id == currentTermId)) {
      final parsed = parseTerm(currentTermId);
      list.add(parsed ?? Term(id: currentTermId, name: currentTermId));
    }
    list.sort((a, b) => b.id.compareTo(a.id));
    return list;
  }

  final result = <Term>[];
  final seenIds = <String>{};

  for (final term in terms) {
    if (!seenIds.add(term.id)) continue;

    // 当前选中学期无条件保留
    if (currentTermId != null &&
        currentTermId.isNotEmpty &&
        term.id == currentTermId) {
      result.add(term);
      continue;
    }

    final parsed = parseTerm(term.id);
    final termYear = term.year ?? parsed?.year;
    if (termYear != null) {
      // 1. 不显示早于入学年份的学期
      if (resolvedEnrollmentYear != null && termYear < resolvedEnrollmentYear) {
        continue;
      }
      // 2. 限制未来学期：学年大于 maxYear，或同一年但学期大于 maxSemester
      if (termYear > maxYear) {
        continue;
      }
      if (termYear == maxYear) {
        final rawSemester = term.semester ?? parsed?.semester;
        final termSemester = resolveSemesterCode(rawSemester, term.id);
        if (termSemester != null && termSemester > maxSemester) {
          continue;
        }
      }
    }

    result.add(term);
  }

  // 保证当前选中学期在列表中（如果原 terms 中不存在）
  if (currentTermId != null &&
      currentTermId.isNotEmpty &&
      !seenIds.contains(currentTermId)) {
    final parsed = parseTerm(currentTermId);
    result.add(parsed ?? Term(id: currentTermId, name: currentTermId));
  }

  // 按学期 id 降序排序（最新学期在最前）
  result.sort((a, b) => b.id.compareTo(a.id));
  return result;
}

const List<String> _gradeNames = <String>['大一', '大二', '大三', '大四', '大五'];

/// 解析学期数字（支持标准 1/2/3 及教务 xqm 编码 3/12/16）。
int? resolveSemesterCode(int? rawSemester, String termId, [String? xqm]) {
  if (xqm != null && xqm.isNotEmpty) {
    if (xqm == '1' || xqm == '3') return 1;
    if (xqm == '2' || xqm == '12') return 2;
    if (xqm == '16') return 3;
    final parsed = int.tryParse(xqm);
    if (parsed != null && parsed >= 1 && parsed <= 3) return parsed;
  }
  if (rawSemester != null && (rawSemester >= 1 && rawSemester <= 3)) {
    return rawSemester;
  }
  final parts = termId.split('-');
  if (parts.isNotEmpty) {
    final last = parts.last;
    if (last == '12' || last == '2') return 2;
    if (last == '16') return 3;
    if (last == '1') return 1;
    if (last == '3') return 3;
  }
  return rawSemester;
}

/// 学期主标题映射。
///
/// 映射规则：
///  - Year 0: "大一 上学期" (xqm '1'/'3'), "大一 下学期" (xqm '2'/'12')
///  - Year 1: "大二 上学期", "大二 下学期"
///  - Year 2: "大三 上学期", "大三 下学期"
///  - Year 3: "大四 上学期", "大四 下学期"
///  - Beyond Year 3 或无入学年份：回退至学年学期名称（如 "2028-2029 第1学期"）。
String formatTermPrimaryLabel({
  required Term term,
  String? studentId,
  int? enrollmentYear,
  String? xqm,
  DateTime? now,
}) {
  final resolvedEnrollmentYear =
      enrollmentYear ?? parseEnrollmentYear(studentId, now: now);

  final termYear = term.year ?? parseTerm(term.id)?.year;
  final rawSemester = term.semester ?? parseTerm(term.id)?.semester;
  final semester = resolveSemesterCode(rawSemester, term.id, xqm);

  String defaultLabel() {
    if (termYear != null && semester != null) {
      return '$termYear-${termYear + 1} 第$semester学期';
    }
    if (term.name.isNotEmpty) return term.name;
    return term.id;
  }

  if (resolvedEnrollmentYear == null || termYear == null || semester == null) {
    return defaultLabel();
  }

  final offset = termYear - resolvedEnrollmentYear;
  if (offset < 0 || offset >= _gradeNames.length) {
    return defaultLabel();
  }

  final grade = _gradeNames[offset];
  final String semesterStr;
  if (semester == 1) {
    semesterStr = '上学期';
  } else if (semester == 2) {
    semesterStr = '下学期';
  } else {
    semesterStr = '第$semester学期';
  }

  return '$grade $semesterStr';
}

/// 根据 termId 获取学期主标题。
String formatTermPrimaryLabelById({
  required String termId,
  String? termName,
  String? studentId,
  int? enrollmentYear,
  String? xqm,
  DateTime? now,
}) {
  final parsed = parseTerm(termId);
  final term = parsed ?? Term(id: termId, name: termName ?? termId);
  return formatTermPrimaryLabel(
    term: term,
    studentId: studentId,
    enrollmentYear: enrollmentYear,
    xqm: xqm,
    now: now,
  );
}
