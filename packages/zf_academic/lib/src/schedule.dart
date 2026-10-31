/// 课表与学期解析。
///
/// 这些函数不是"随手写的正则"：周次格式（`1-4周(单)`、`第3-5周`、`1,3,5周`、`[1-16周]`）、
/// 节次格式（`1-2`、`3-4`、`[1-2节]`）都是按真实教务页面的多种写法收敛出来的。
library;

import 'errors.dart';
import 'html.dart' show allTags, hasClass, innerOf, stripTags;
import 'types.dart' show ScheduleDetail, ScheduleEntry, ScheduleRemark, Term;
import 'urls.dart' show parseTerm;
import 'util.dart' show field, firstOf, number, rowKey;

const List<String> _yearNames = ['xnm', 'xnd', 'ddlXN', 'xn'];
const List<String> _semesterNames = ['xqm', 'xqd', 'ddlXQ', 'xq'];
const Map<String, int> _semesterFromCode = <String, int>{
  '1': 1,
  '3': 1,
  '2': 2,
  '12': 2,
  '16': 3,
};

/// 学期下拉框里的编码值 → 第几学期。`xqm` 用编码表，其它字段只接受裸的 1/2/3。
int? _semesterPart(String name, String value) {
  if (name.split('\$').last == 'xqm') return _semesterFromCode[value];
  return RegExp(r'^[123]$').hasMatch(value) ? int.parse(value) : null;
}

List<Term> _uniqueById(List<Term> items) {
  final seen = <String, Term>{};
  for (final item in items) {
    seen[item.id] = item;
  }
  return seen.values.toList();
}

/// 收集页面里所有可选学期。先看能否直接从某个 option 文本解析，再回退到"学年 × 学期"组合。
List<Term> termsFromHtml(String html) {
  final combined = <Term>[];
  for (final node in allTags(html)) {
    if (node.tag != 'option' || node.attrs.containsKey('disabled')) continue;
    final parsed = parseTerm(node.attrs['value'] ?? '') ??
        parseTerm(stripTags(innerOf(html, node)));
    if (parsed != null) combined.add(parsed);
  }
  if (combined.isNotEmpty) return _uniqueById(combined);

  final years = <int>[];
  final parts = <int>[];
  for (final element in allTags(html)) {
    if (element.tag != 'select') continue;
    final name = (element.attrs['name'] ?? '').split('\$').last;
    if (!_yearNames.contains(name) && !_semesterNames.contains(name)) continue;
    final inner = innerOf(html, element);
    for (final option in allTags(inner)) {
      if (option.tag != 'option' || option.attrs.containsKey('disabled')) {
        continue;
      }
      final value = option.attrs['value'] ?? '';
      if (_yearNames.contains(name) && RegExp(r'^\d{4}').hasMatch(value)) {
        years.add(int.parse(value.substring(0, 4)));
      }
      if (_semesterNames.contains(name)) {
        final part = _semesterPart(name, value);
        if (part != null) parts.add(part);
      }
    }
  }
  final result = <Term>[];
  for (final year in years.toSet()) {
    for (final part in parts.toSet()) {
      final parsed = parseTerm('$year-${year + 1}-$part');
      if (parsed != null) result.add(parsed);
    }
  }
  return result;
}

/// 当前页面已经选中的学期。
Term? selectedTermFromHtml(String html) {
  for (final node in allTags(html)) {
    if (node.tag != 'option' || !node.attrs.containsKey('selected')) continue;
    final parsed = parseTerm(node.attrs['value'] ?? '') ??
        parseTerm(stripTags(innerOf(html, node)));
    if (parsed != null) return parsed;
  }
  var year = 0;
  int? semester;
  for (final element in allTags(html)) {
    if (element.tag != 'select' && element.tag != 'input') continue;
    final name = (element.attrs['name'] ?? '').split('\$').last;
    if (!_yearNames.contains(name) && !_semesterNames.contains(name)) continue;
    var value = element.attrs['value'];
    if (value == null && element.tag == 'select') {
      final inner = innerOf(html, element);
      final options =
          allTags(inner).where((node) => node.tag == 'option').toList();
      final chosen =
          firstOf(options.where((node) => node.attrs.containsKey('selected')));
      final first = options.isNotEmpty ? options.first : null;
      final target = chosen ?? first;
      value = target == null
          ? ''
          : (target.attrs['value'] ?? stripTags(innerOf(inner, target)));
    }
    if (_yearNames.contains(name)) {
      year = int.tryParse((value ?? '').substring(0, 4)) ?? 0;
    }
    if (_semesterNames.contains(name)) {
      semester = _semesterPart(name, value ?? '');
    }
  }
  if (year > 1900 && semester != null) {
    return parseTerm('$year-${year + 1}-$semester');
  }
  return null;
}

/// `1-2`、`3,4`、`5-6节` → 连续节次区间。非法或越界的分片直接忽略。
///
/// 比 TS 版更宽容：先剥掉首尾的非数字装饰（`[1-2节]`、`5-6节` 这类真实页面写法），
/// 再做区间解析——TS 版的正则遇到 `节` 后缀会直接跳过该行。
List<(int, int)> periods(String value) {
  final numbers = <int>{};
  for (final piece in value.replaceAll('—', '-').split(RegExp(r'[,，、]'))) {
    final cleaned = piece.replaceAll(RegExp(r'^[^\d]+|[^\d]+$'), '');
    final match = RegExp(r'^\s*(\d+)(?:\s*-\s*(\d+))?\s*$').firstMatch(cleaned);
    if (match == null) continue;
    final start = int.parse(match.group(1)!);
    final end = int.parse(match.group(2) ?? match.group(1)!);
    if (start < 1 || end < start || end > 30) continue;
    for (var n = start; n <= end; n++) {
      numbers.add(n);
    }
  }
  final spans = <(int, int)>[];
  for (final n in (numbers.toList()..sort())) {
    if (spans.isNotEmpty && spans.last.$2 + 1 == n) {
      spans[spans.length - 1] = (spans.last.$1, n);
    } else {
      spans.add((n, n));
    }
  }
  return spans;
}

/// `1-4周(单)`、`第3-5周`、`1,3,5周`、`[1-16周]` → 周次数组。上限 25 周，超出视为页面结构变化。
List<int> weeks(String value) {
  if (value.trim().isEmpty) return const <int>[];
  final normalized = value
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll(RegExp(r'—|－'), '-')
      .replaceAll('第', '')
      .replaceAll('(周)', '周')
      .replaceAll(RegExp(r'[\[\]]'), '');
  final result = <int>{};
  final pattern = RegExp(
    r'(\d+(?:\s*-\s*\d+)?(?:\s*[,，、]\s*\d+(?:\s*-\s*\d+)?)*)\s*(?:\(([单双])(?:周)?\))?\s*周?(?:\(([单双])(?:周)?\))?',
  );
  for (final match in pattern.allMatches(normalized)) {
    for (final range in (match.group(1) ?? '').split(RegExp(r'[,，、]'))) {
      final pair = range.split('-').map(int.parse).toList();
      final start = pair[0];
      final end = pair.length > 1 ? pair[1] : start;
      final mode = match.group(2) ?? match.group(3);
      if (start < 1 || end < start || end > 25) {
        changed('学校课表周次超出当前支持的 1–25 周');
      }
      for (var week = start; week <= end; week++) {
        if (mode == null || week % 2 == (mode == '单' ? 1 : 0)) {
          result.add(week);
        }
      }
    }
  }
  if (result.isEmpty) changed('学校课表缺少可识别的周次');
  return result.toList()..sort();
}

List<ScheduleDetail> _scheduleDetails(Map<String, dynamic> row) {
  const definitions = <(String, String, List<String>)>[
    ('courseCode', '课程号', ['kch', 'KCH', 'courseCode']),
    ('credits', '学分', ['xf', 'XF', 'credits']),
    ('sectionName', '教学班', ['jxbmc', 'JXBMC', 'sectionName']),
    ('className', '上课班级', ['bjmc', 'BJMC', 'className']),
    ('lessonSequence', '课序号', ['kxh', 'KXH', 'lessonSequence']),
    ('teachingContent', '授课内容', ['sknr', 'SKNR', 'teachingContent']),
    ('notes', '备注', ['bz', 'BZ', 'notes']),
  ];
  final result = <ScheduleDetail>[];
  for (final (id, label, keys) in definitions) {
    final value = field(row, keys);
    if (value.isNotEmpty) {
      result.add(ScheduleDetail(id: id, label: label, value: value));
    }
  }
  return result;
}

/// 新正方 `kbList` 行 → ScheduleEntry。
/// 一门课横跨多段连续节次时会拆成多条，`id` 由课程标识 + 星期 + 节次 + 周次哈希而来，
/// 因此同一份课表重复解析得到的 id 稳定，可以直接做去重和增量更新。
List<ScheduleEntry> jsonSchedule(List<Map<String, dynamic>> rows) {
  final result = <ScheduleEntry>[];
  for (final row in rows) {
    final name = field(row, const ['kcmc', 'KCMC']);
    if (name.isEmpty) continue;
    final day = number(row, const ['xqj', 'XQJ']);
    final spans = periods(field(row, const ['jcs', 'JCS', 'jcor', 'JCOR']));
    if (day == null || day < 1 || day > 7 || spans.isEmpty) {
      // 容错：跳过缺少星期或节次的无规律课程项（如网课、实践阶段），避免整份课表解析崩溃。
      continue;
    }
    final details = _scheduleDetails(row);
    final teacher = field(row, const ['xm', 'XM', 'jsxm']);
    final campus = field(row, const ['xqmc', 'cdxqmc']);
    final room = field(row, const ['cdmc', 'CDMC', 'jxcdmc']);
    final location = [campus, room].where((part) => part.isNotEmpty).join(' ');
    final rawWeeks = field(row, const ['zcd', 'ZCD', 'weeks']);
    List<int> weekList;
    try {
      weekList = rawWeeks.isEmpty ? const <int>[] : weeks(rawWeeks);
    } catch (_) {
      weekList = const <int>[];
    }
    final courseKey = field(row, const [
      'schedule_source_id',
      'kcb_id',
      'kb_id',
      'jxb_id',
      'jx0404id',
      'kch_id',
    ]);
    for (final (startPeriod, endPeriod) in spans) {
      result.add(ScheduleEntry(
        id: rowKey([
          courseKey,
          name,
          '$day',
          '$startPeriod',
          '$endPeriod',
          rawWeeks,
        ]),
        name: name,
        details: details.isEmpty ? null : details,
        teacher: teacher.isEmpty ? null : teacher,
        location: location.isEmpty ? null : location,
        day: day,
        startPeriod: startPeriod,
        endPeriod: endPeriod,
        weeks: weekList,
      ));
    }
  }
  final unique = <String, ScheduleEntry>{};
  for (final entry in result) {
    unique[entry.id] = entry;
  }
  return unique.values.toList();
}

/// 课表响应里的 `sjkList`（备注：实践课程 / 其他课程）→ [ScheduleRemark]。
///
/// `sfsjk = 1` 是实践课程、`sfsjk = 0` 是其他课程；`sjkcgs` 是网页显示字段。
/// 行里可能还带课程名 / 教师 / 周次 / 地点，一并取出供 UI 展示。
List<ScheduleRemark> jsonScheduleRemarks(List<Map<String, dynamic>> rows) {
  final result = <ScheduleRemark>[];
  for (final row in rows) {
    final content = field(row, const ['sjkcgs', 'SJKCGS']);
    final courseName = field(row, const ['kcmc', 'KCMC']);
    // 内容和课名都空 → 空行，跳过。
    if (content.isEmpty && courseName.isEmpty) continue;
    final teacher = field(row, const ['xm', 'XM', 'jsxm']);
    final weeks = field(row, const ['zcd', 'ZCD', 'weeks']);
    final campus = field(row, const ['xqmc', 'cdxqmc']);
    final room = field(row, const ['cdmc', 'CDMC', 'jxcdmc']);
    final location = [campus, room].where((part) => part.isNotEmpty).join(' ');
    result.add(
      ScheduleRemark(
        practical: (number(row, const ['sfsjk', 'SFSJK']) ?? 0) == 1,
        content: content,
        courseName: courseName.isEmpty ? null : courseName,
        teacher: teacher.isEmpty ? null : teacher,
        weeks: weeks.isEmpty ? null : weeks,
        location: location.isEmpty ? null : location,
      ),
    );
  }
  return result;
}

int maxWeeksOf(List<ScheduleEntry> entries) {
  var max = 25;
  for (final entry in entries) {
    for (final week in entry.weeks) {
      if (week > max) max = week;
    }
  }
  return max;
}

/// 判断页面里是否存在课表控件的痕迹，用于把"没权限"和"格式变了"区分开。
bool looksLikeTimetable(String html) {
  return allTags(html).any((element) => const [
        'courselists-item',
        'kbcontent',
        'kbcontent1'
      ].any((token) => hasClass(element.attrs, token)));
}
