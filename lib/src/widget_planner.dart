/// 桌面小组件的离线规划与快照序列化。
///
/// 纯函数——不读时钟、不读文件、不碰平台通道。沿用 `reminder_planner.dart` 的职责划分：
/// 周次 ⇄ 日期、调课覆盖、作息表按生效日切换、冲突分栏、同日考试混排全部在 Dart 算完，
/// Android 原生只消费标准化后的毫秒时间戳、星期/周次标签、样式配置与课表色板索引。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:zf_academic/zf_academic.dart';

import '../theme/course_palette.dart';
import 'course_text.dart';
import 'reschedule.dart';
import 'term_calendar.dart';
import 'timetable.dart';
import 'widget_style.dart';

const int widgetSnapshotVersion = 1;
const int widgetHorizonDays = 14;
const int widgetUpcomingExamWindowDays = 7;
const int widgetExamSnapshotMaxDays = 30;

/// 单条当日日程（普通课程或当天考试）。
class WidgetTimelineItem {
  const WidgetTimelineItem({
    required this.kind,
    required this.id,
    required this.title,
    required this.location,
    required this.teacher,
    required this.seatNumber,
    required this.examForm,
    required this.startPeriod,
    required this.endPeriod,
    required this.startLabel,
    required this.endLabel,
    required this.startMs,
    required this.endMs,
    required this.colorIndex,
    this.rescheduled = false,
  });

  /// `'course'` 或 `'exam'`。
  final String kind;
  final String id;
  final String title;
  final String location;
  final String teacher;
  final String seatNumber;
  final String examForm;
  final int startPeriod;
  final int endPeriod;
  final String startLabel;
  final String endLabel;
  final int startMs;
  final int endMs;
  final int colorIndex;
  final bool rescheduled;

  bool get isExam => kind == 'exam';

  Map<String, Object?> toJson() => <String, Object?>{
    'kind': kind,
    'id': id,
    'title': title,
    'location': location,
    'teacher': teacher,
    'seatNumber': seatNumber,
    'examForm': examForm,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'startLabel': startLabel,
    'endLabel': endLabel,
    'startMs': startMs,
    'endMs': endMs,
    'colorIndex': colorIndex,
    'rescheduled': rescheduled,
  };
}

/// 某一天的完整日程（含当日课程与当天考试）。
class WidgetDayPlan {
  const WidgetDayPlan({
    required this.dateIso,
    required this.week,
    required this.weekday,
    required this.items,
  });

  final String dateIso;
  final int week;
  final int weekday;
  final List<WidgetTimelineItem> items;

  Map<String, Object?> toJson() => <String, Object?>{
    'dateIso': dateIso,
    'week': week,
    'weekday': weekday,
    'items': <Object?>[for (final item in items) item.toJson()],
  };
}

/// 近期考试摘要（供今日无剩余课时优雅展示考试倒计时）。
class WidgetUpcomingExam {
  const WidgetUpcomingExam({
    required this.id,
    required this.courseName,
    required this.startMs,
    required this.endMs,
    required this.dateIso,
    required this.timeLabel,
    required this.week,
    required this.weekday,
    required this.location,
    required this.seatNumber,
    required this.examForm,
    required this.colorIndex,
  });

  final String id;
  final String courseName;
  final int startMs;
  final int endMs;
  final String dateIso;
  final String timeLabel;
  final int week;
  final int weekday;
  final String location;
  final String seatNumber;
  final String examForm;
  final int colorIndex;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'courseName': courseName,
    'startMs': startMs,
    'endMs': endMs,
    'dateIso': dateIso,
    'timeLabel': timeLabel,
    'week': week,
    'weekday': weekday,
    'location': location,
    'seatNumber': seatNumber,
    'examForm': examForm,
    'colorIndex': colorIndex,
  };
}

/// 周网格中的一块课程色块。
class WidgetWeekBlock {
  const WidgetWeekBlock({
    required this.id,
    required this.name,
    required this.location,
    required this.teacher,
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    required this.conflictIndex,
    required this.conflictTotal,
    required this.colorIndex,
    this.rescheduled = false,
  });

  final String id;
  final String name;
  final String location;
  final String teacher;
  final int day;
  final int startPeriod;
  final int endPeriod;
  final int conflictIndex;
  final int conflictTotal;
  final int colorIndex;
  final bool rescheduled;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'name': name,
    'location': location,
    'teacher': teacher,
    'day': day,
    'startPeriod': startPeriod,
    'endPeriod': endPeriod,
    'conflictIndex': conflictIndex,
    'conflictTotal': conflictTotal,
    'colorIndex': colorIndex,
    'rescheduled': rescheduled,
  };
}

/// 整周课表网格数据（已应用调课与冲突分栏）。
class WidgetWeekPlan {
  const WidgetWeekPlan({
    required this.week,
    required this.startDateIso,
    required this.dayLabels,
    required this.maxSection,
    required this.sectionStarts,
    required this.sectionEnds,
    required this.blocks,
  });

  final int week;
  final String startDateIso;
  final List<String> dayLabels;
  final int maxSection;
  final List<String> sectionStarts;
  final List<String> sectionEnds;
  final List<WidgetWeekBlock> blocks;

  Map<String, Object?> toJson() => <String, Object?>{
    'week': week,
    'startDateIso': startDateIso,
    'dayLabels': dayLabels,
    'maxSection': maxSection,
    'sectionStarts': sectionStarts,
    'sectionEnds': sectionEnds,
    'blocks': <Object?>[for (final block in blocks) block.toJson()],
  };
}

/// 下发到 Android 原生端的完整桌面小组件快照。
class WidgetSnapshot {
  const WidgetSnapshot({
    required this.signedIn,
    required this.termId,
    required this.termStartIso,
    required this.maxWeek,
    required this.generatedAtMs,
    required this.fingerprint,
    required this.days,
    required this.upcomingExams,
    required this.weeks,
    required this.styles,
  });

  final bool signedIn;
  final String termId;
  final String termStartIso;
  final int maxWeek;
  final int generatedAtMs;
  final String fingerprint;
  final List<WidgetDayPlan> days;
  final List<WidgetUpcomingExam> upcomingExams;
  final List<WidgetWeekPlan> weeks;
  final DesktopWidgetConfigSet styles;

  /// 指纹之外的纯内容+样式结构，同时用于生成稳定摘要与序列化。
  Map<String, Object?> _canonicalBody() => <String, Object?>{
    'v': widgetSnapshotVersion,
    'signedIn': signedIn,
    'termId': termId,
    'termStartIso': termStartIso,
    'maxWeek': maxWeek,
    'days': <Object?>[for (final day in days) day.toJson()],
    'upcomingExams': <Object?>[for (final exam in upcomingExams) exam.toJson()],
    'weeks': <Object?>[for (final week in weeks) week.toJson()],
    'styles': styles.toJson(),
  };

  Map<String, Object?> toJson() => <String, Object?>{
    ..._canonicalBody(),
    'generatedAtMs': generatedAtMs,
    'fingerprint': fingerprint,
  };

  String toPayloadJson() => jsonEncode(toJson());
}

/// 构建未登录或无课表时的空态快照（保留用户自定义的样式配置）。
WidgetSnapshot buildSignedOutWidgetSnapshot(
  DesktopWidgetConfigSet styles, {
  required DateTime now,
}) {
  final fingerprint = _computeSnapshotFingerprint(
    signedIn: false,
    termId: '',
    termStartIso: '',
    maxWeek: 18,
    days: const <WidgetDayPlan>[],
    upcomingExams: const <WidgetUpcomingExam>[],
    weeks: const <WidgetWeekPlan>[],
    styles: styles,
  );
  return WidgetSnapshot(
    signedIn: false,
    termId: '',
    termStartIso: '',
    maxWeek: 18,
    generatedAtMs: now.millisecondsSinceEpoch,
    fingerprint: fingerprint,
    days: const <WidgetDayPlan>[],
    upcomingExams: const <WidgetUpcomingExam>[],
    weeks: const <WidgetWeekPlan>[],
    styles: styles,
  );
}

/// 根据当前课表、调课、作息、考试与小组件样式构建完整离线快照。
///
/// 调用方须保证仅在考试数据实际归属当前学期时传入 [exams]，避免跨学期错配。
WidgetSnapshot buildWidgetSnapshot({
  required String termId,
  required List<ScheduleEntry> entries,
  required List<RescheduleRule> reschedules,
  required DateTime termStart,
  required List<Timetable> timetables,
  required Map<PeriodGroup, int> sectionCounts,
  required int maxWeek,
  required DesktopWidgetConfigSet styles,
  required DateTime now,
  List<ExamItem> exams = const <ExamItem>[],
  int horizonDays = widgetHorizonDays,
  int examMaxDays = widgetExamSnapshotMaxDays,
}) {
  final safeMaxWeek = maxWeek < 1 ? 1 : maxWeek;
  final daysCount = horizonDays < 1 ? 1 : horizonDays;
  final mondayStart = mondayOf(termStart);
  final termStartIso = formatIsoDate(mondayStart);
  final today = dayOnly(now);

  final weekViews = <int, RescheduleWeekView>{};
  final rawWeekEntries = <int, List<ScheduleEntry>>{};
  final sectionCache = <String, List<SectionTime>>{};
  final dayPlans = <WidgetDayPlan>[];

  RescheduleWeekView viewForWeek(int week) =>
      weekViews[week] ??= rescheduleWeekView(
        entries,
        reschedules,
        termStart,
        week,
        maxWeek: safeMaxWeek,
      );

  List<ScheduleEntry> rawForWeek(int week) =>
      rawWeekEntries[week] ??= entriesOfWeek(entries, week);

  List<SectionTime> sectionsForDate(DateTime date) {
    final table = activeTimetableAt(timetables, date);
    if (table == null) {
      return reconcileSections(const <SectionTime>[], sectionCounts);
    }
    return sectionCache[table.id] ??= reconcileSections(
      table.sections,
      sectionCounts,
    );
  }

  for (var offset = 0; offset < daysCount; offset++) {
    final date = DateTime(today.year, today.month, today.day + offset);
    final inTerm = !date.isBefore(mondayStart);
    final week = inTerm ? weekOf(termStart, date) : 0;
    final items = <WidgetTimelineItem>[];

    if (inTerm && week >= 1 && week <= safeMaxWeek) {
      final view = viewForWeek(week);
      final rawEntries = rawForWeek(week);
      final sections = sectionsForDate(date);
      for (final entry in view.entries) {
        if (entry.day != date.weekday) continue;
        if (!occursInWeek(entry, week)) continue;
        final startMinutes = _minutesOf(sections, entry.startPeriod);
        if (startMinutes == null) continue;
        final rawEndMinutes = _endMinutesOf(sections, entry.endPeriod);
        final endMinutes =
            rawEndMinutes == null || rawEndMinutes < startMinutes
            ? startMinutes
            : rawEndMinutes;
        final startAt = _at(date, startMinutes);
        final endAt = _at(date, endMinutes);
        final isMoved = !_hasOriginalMatch(rawEntries, entry);
        final normalizedName = entry.name.trim();
        items.add(
          WidgetTimelineItem(
            kind: 'course',
            id: _stableCourseId(entry.id, date, entry.startPeriod),
            title: normalizedName,
            location: roomOnly(entry.location ?? ''),
            teacher: (entry.teacher ?? '').trim(),
            seatNumber: '',
            examForm: '',
            startPeriod: entry.startPeriod,
            endPeriod: entry.endPeriod < entry.startPeriod
                ? entry.startPeriod
                : entry.endPeriod,
            startLabel: _formatMinutes(startMinutes),
            endLabel: _formatMinutes(endMinutes),
            startMs: startAt.millisecondsSinceEpoch,
            endMs: endAt.millisecondsSinceEpoch,
            colorIndex: CoursePalette.indexOf(normalizedName),
            rescheduled: isMoved,
          ),
        );
      }
    }

    // 混排当天的考试条目。
    for (final exam in exams) {
      final start = exam.startTime;
      if (start == null) continue;
      if (!_isSameDay(start, date)) continue;
      final end = _resolveExamEnd(start, exam.endTime);
      final courseName = exam.courseName.trim();
      items.add(
        WidgetTimelineItem(
          kind: 'exam',
          id: _stableExamId(exam),
          title: courseName,
          location: _examLocationOf(exam),
          teacher: '',
          seatNumber: exam.seatNumber.trim(),
          examForm: exam.examForm.trim(),
          startPeriod: 0,
          endPeriod: 0,
          startLabel: _formatHm(start),
          endLabel: _formatHm(end),
          startMs: start.millisecondsSinceEpoch,
          endMs: end.millisecondsSinceEpoch,
          colorIndex: CoursePalette.indexOf(courseName),
        ),
      );
    }

    items.sort((a, b) {
      final byStart = a.startMs.compareTo(b.startMs);
      if (byStart != 0) return byStart;
      final byPeriod = a.startPeriod.compareTo(b.startPeriod);
      if (byPeriod != 0) return byPeriod;
      return a.id.compareTo(b.id);
    });

    dayPlans.add(
      WidgetDayPlan(
        dateIso: formatIsoDate(date),
        week: week,
        weekday: date.weekday,
        items: List<WidgetTimelineItem>.unmodifiable(items),
      ),
    );
  }

  // 收集未来 examMaxDays 天内的未结束考试，供「无剩余课时展示近期考试倒计时」。
  final upcomingExams = <WidgetUpcomingExam>[];
  final nowMs = now.millisecondsSinceEpoch;
  for (final exam in exams) {
    final start = exam.startTime;
    if (start == null) continue;
    final end = _resolveExamEnd(start, exam.endTime);
    if (end.millisecondsSinceEpoch <= nowMs) continue;
    final examDay = dayOnly(start);
    final diffDays = DateTime.utc(
      examDay.year,
      examDay.month,
      examDay.day,
    ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;
    if (diffDays > examMaxDays) continue;

    final inTerm = !examDay.isBefore(mondayStart);
    final week = inTerm ? weekOf(termStart, examDay) : 0;
    final courseName = exam.courseName.trim();
    upcomingExams.add(
      WidgetUpcomingExam(
        id: _stableExamId(exam),
        courseName: courseName,
        startMs: start.millisecondsSinceEpoch,
        endMs: end.millisecondsSinceEpoch,
        dateIso: formatIsoDate(examDay),
        timeLabel: '${_formatHm(start)}-${_formatHm(end)}',
        week: week > safeMaxWeek ? 0 : week,
        weekday: examDay.weekday,
        location: _examLocationOf(exam),
        seatNumber: exam.seatNumber.trim(),
        examForm: exam.examForm.trim(),
        colorIndex: CoursePalette.indexOf(courseName),
      ),
    );
  }
  upcomingExams.sort((a, b) {
    final byStart = a.startMs.compareTo(b.startMs);
    return byStart != 0 ? byStart : a.courseName.compareTo(b.courseName);
  });

  // 预计算未来 horizonDays 覆盖到的全部学期内周次（周一生成含今下 2 周；周二~周日跨入第 3 周时
  // 一并预计算，确保周课表与今日/下一节共享完整 14 天离线窗口，不在第 8 天提前过期）。
  final currentWeek = today.isBefore(mondayStart)
      ? 1
      : weekOf(termStart, today).clamp(1, safeMaxWeek);
  final horizonEnd = DateTime(
    today.year,
    today.month,
    today.day + daysCount - 1,
  );
  final horizonEndWeek = horizonEnd.isBefore(mondayStart)
      ? 1
      : weekOf(termStart, horizonEnd).clamp(1, safeMaxWeek);
  final targetEndWeek = math.min(
    safeMaxWeek,
    math.max(currentWeek + 1, horizonEndWeek),
  );
  final weekTargets = <int>[
    for (var w = currentWeek; w <= targetEndWeek; w++) w,
  ];
  final weeks = <WidgetWeekPlan>[];
  for (final w in weekTargets) {
    final monday = dateOf(termStart, w, 1);
    final view = viewForWeek(w);
    final rawEntries = rawForWeek(w);
    final sections = sectionsForDate(monday);
    final conflicts = conflictLayout(view.entries);

    var maxEntryPeriod = sections.length;
    for (final entry in view.entries) {
      if (entry.endPeriod > maxEntryPeriod) {
        maxEntryPeriod = entry.endPeriod;
      }
    }
    final maxSection = math.max(sections.length, maxEntryPeriod);

    final blocks = <WidgetWeekBlock>[];
    for (final entry in view.entries) {
      final layout = conflicts[entry.id] ?? (index: 0, total: 1);
      blocks.add(
        WidgetWeekBlock(
          id: entry.id,
          name: entry.name,
          location: roomOnly(entry.location ?? ''),
          teacher: entry.teacher ?? '',
          day: entry.day,
          startPeriod: entry.startPeriod,
          endPeriod: entry.endPeriod,
          conflictIndex: layout.index,
          conflictTotal: layout.total,
          colorIndex: CoursePalette.indexOf(entry.name),
          rescheduled: !_hasOriginalMatch(rawEntries, entry),
        ),
      );
    }
    blocks.sort((a, b) {
      final byDay = a.day.compareTo(b.day);
      if (byDay != 0) return byDay;
      final byPeriod = a.startPeriod.compareTo(b.startPeriod);
      if (byPeriod != 0) return byPeriod;
      return a.id.compareTo(b.id);
    });

    weeks.add(
      WidgetWeekPlan(
        week: w,
        startDateIso: formatIsoDate(monday),
        dayLabels: <String>[
          for (var d = 1; d <= 7; d++)
            () {
              final dt = dateOf(termStart, w, d);
              return '${dt.month}/${dt.day}';
            }(),
        ],
        maxSection: maxSection,
        sectionStarts: <String>[
          for (var p = 1; p <= maxSection; p++)
            () {
              final m = _minutesOf(sections, p);
              return m == null ? '' : _formatMinutes(m);
            }(),
        ],
        sectionEnds: <String>[
          for (var p = 1; p <= maxSection; p++)
            () {
              final m = _endMinutesOf(sections, p);
              return m == null ? '' : _formatMinutes(m);
            }(),
        ],
        blocks: List<WidgetWeekBlock>.unmodifiable(blocks),
      ),
    );
  }

  final fingerprint = _computeSnapshotFingerprint(
    signedIn: true,
    termId: termId,
    termStartIso: termStartIso,
    maxWeek: safeMaxWeek,
    days: dayPlans,
    upcomingExams: upcomingExams,
    weeks: weeks,
    styles: styles,
  );

  return WidgetSnapshot(
    signedIn: true,
    termId: termId,
    termStartIso: termStartIso,
    maxWeek: safeMaxWeek,
    generatedAtMs: nowMs,
    fingerprint: fingerprint,
    days: List<WidgetDayPlan>.unmodifiable(dayPlans),
    upcomingExams: List<WidgetUpcomingExam>.unmodifiable(upcomingExams),
    weeks: List<WidgetWeekPlan>.unmodifiable(weeks),
    styles: styles,
  );
}

String _computeSnapshotFingerprint({
  required bool signedIn,
  required String termId,
  required String termStartIso,
  required int maxWeek,
  required List<WidgetDayPlan> days,
  required List<WidgetUpcomingExam> upcomingExams,
  required List<WidgetWeekPlan> weeks,
  required DesktopWidgetConfigSet styles,
}) {
  final canonical = jsonEncode(<String, Object?>{
    'v': widgetSnapshotVersion,
    'signedIn': signedIn,
    'termId': termId,
    'termStartIso': termStartIso,
    'maxWeek': maxWeek,
    'days': <Object?>[for (final day in days) day.toJson()],
    'upcomingExams': <Object?>[for (final exam in upcomingExams) exam.toJson()],
    'weeks': <Object?>[for (final week in weeks) week.toJson()],
    'styles': styles.toJson(),
  });
  return _fnv1a(canonical).toRadixString(16).padLeft(8, '0');
}

bool _hasOriginalMatch(
  List<ScheduleEntry> rawEntries,
  ScheduleEntry candidate,
) {
  for (final original in rawEntries) {
    if (original.id == candidate.id &&
        original.day == candidate.day &&
        original.startPeriod == candidate.startPeriod &&
        original.endPeriod == candidate.endPeriod) {
      return true;
    }
  }
  return false;
}

DateTime _resolveExamEnd(DateTime start, DateTime? endTime) {
  if (endTime == null) return start.add(const Duration(hours: 2));
  return endTime.isBefore(start) ? start : endTime;
}

String _examLocationOf(ExamItem exam) {
  final classroom = exam.classroom.trim();
  final campus = exam.campus.trim();
  if (classroom.isNotEmpty) return classroom;
  return campus;
}

String _stableCourseId(String entryId, DateTime date, int startPeriod) {
  final stamp = formatIsoDate(date);
  return 'c_${_fnv1a('$entryId|$stamp|$startPeriod').toRadixString(16).padLeft(8, '0')}';
}

String _stableExamId(ExamItem exam) {
  final startMs = exam.startTime?.millisecondsSinceEpoch ?? 0;
  return 'x_${_fnv1a('${exam.courseName}|$startMs|${exam.classroom}').toRadixString(16).padLeft(8, '0')}';
}

bool _isSameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

int? _minutesOf(List<SectionTime> sections, int period) {
  for (final section in sections) {
    if (section.period == period) return section.startMinutes;
  }
  return null;
}

int? _endMinutesOf(List<SectionTime> sections, int period) {
  for (final section in sections) {
    if (section.period == period) return section.endMinutes;
  }
  return null;
}

DateTime _at(DateTime date, int minutes) =>
    DateTime(date.year, date.month, date.day, minutes ~/ 60, minutes % 60);

String _formatMinutes(int minutes) {
  final h = (minutes ~/ 60).toString().padLeft(2, '0');
  final m = (minutes % 60).toString().padLeft(2, '0');
  return '$h:$m';
}

String _formatHm(DateTime dt) {
  final h = dt.hour.toString().padLeft(2, '0');
  final m = dt.minute.toString().padLeft(2, '0');
  return '$h:$m';
}

int _fnv1a(String text) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}
