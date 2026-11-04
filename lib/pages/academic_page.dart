/// 学业页面：学期考试日程与成绩绩点概览。
///
/// 包含两大模块：
///  1. 近期考试安排：下一场考试倒计时 Hero 焦点卡片、考场座位号、考试列表（排序置顶沉底）；
///  2. 学期成绩与绩点：平均学分绩点 (GPA)、总修学分/已获学分统计、评教拦截提醒、课程成绩明细。
///
/// 采用独立状态订阅，滚动底部留足 [FloatingDock.contentInset] 避开悬浮胶囊。
library;

import 'package:flutter/material.dart';
import 'package:zf_academic/zf_academic.dart';

import '../src/academic_service.dart';
import '../src/app_model.dart';
import '../src/term_selector_helper.dart';
import '../widgets/app_menu.dart';
import '../widgets/floating_dock.dart';

class AcademicPage extends StatefulWidget {
  const AcademicPage({super.key, required this.model});

  final AppModel model;

  @override
  State<AcademicPage> createState() => _AcademicPageState();
}

class _AcademicPageState extends State<AcademicPage> {
  AppModel get model => widget.model;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (model.exams.isEmpty &&
          model.grades.isEmpty &&
          !model.academicLoading &&
          !model.isNotEvaluated) {
        model.loadAcademicData();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model.academicNotifier,
      builder: (context, _) {
        final currentTermId = model.academicTermId;
        final terms = model.terms?.items ?? const <Term>[];

        return Scaffold(
          appBar: AppBar(
            title: const Text('学业概览'),
            actions: <Widget>[
              _TermSelectorButton(
                currentTermId: currentTermId,
                terms: terms,
                studentId: model.studentId,
                serverCurrentTermId: model.terms?.currentId,
                onSelected: (termId) => model.setAcademicTerm(termId),
              ),
              IconButton(
                icon: model.academicLoading
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: '刷新学业数据',
                onPressed: model.academicLoading
                    ? null
                    : () => model.refreshAcademicData(),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              8,
              16,
              FloatingDock.contentInset(context),
            ),
            children: <Widget>[
              if (model.academicError != null) ...<Widget>[
                _ErrorBanner(
                  message: model.academicError!,
                  onRetry: () => model.refreshAcademicData(),
                ),
                const SizedBox(height: 12),
              ],
              _SectionHeader(
                title: '考试安排',
                subtitle: model.exams.isNotEmpty
                    ? '共 ${model.exams.length} 门考试'
                    : null,
              ),
              const SizedBox(height: 8),
              _ExamSection(
                exams: model.exams,
                loading: model.academicLoading && model.exams.isEmpty,
              ),
              const SizedBox(height: 20),
              _SectionHeader(
                title: '成绩与绩点',
                subtitle: model.grades.isNotEmpty
                    ? '共 ${model.grades.length} 门成绩'
                    : null,
              ),
              const SizedBox(height: 8),
              if (model.isNotEvaluated) ...<Widget>[
                const _EvaluationWarningBanner(),
                const SizedBox(height: 12),
              ],
              _GradeSection(
                grades: model.grades,
                stats: model.gradeStats,
                isNotEvaluated: model.isNotEvaluated,
                loading: model.academicLoading && model.grades.isEmpty,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.subtitle});

  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Row(
      children: <Widget>[
        Text(
          title,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: scheme.onSurface,
          ),
        ),
        if (subtitle != null) ...<Widget>[
          const SizedBox(width: 8),
          Text(
            subtitle!,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline),
          ),
        ],
      ],
    );
  }
}

class _TermSelectorButton extends StatelessWidget {
  const _TermSelectorButton({
    required this.currentTermId,
    required this.terms,
    required this.studentId,
    this.serverCurrentTermId,
    required this.onSelected,
  });

  final String currentTermId;
  final List<Term> terms;
  final String studentId;
  final String? serverCurrentTermId;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final enrollmentYear = parseEnrollmentYear(studentId);
    final displayLabel = _displayLabelOf(currentTermId, enrollmentYear);

    return Builder(
      builder: (anchorContext) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () => _openMenu(anchorContext, enrollmentYear),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                displayLabel,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.arrow_drop_down_rounded, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openMenu(
    BuildContext anchorContext,
    int? enrollmentYear,
  ) async {
    final theme = Theme.of(anchorContext);
    final scheme = theme.colorScheme;

    final filtered = filterTerms(
      terms: terms,
      studentId: studentId,
      enrollmentYear: enrollmentYear,
      currentTermId: currentTermId,
      serverCurrentTermId: serverCurrentTermId,
    );

    if (filtered.isEmpty) {
      await showAppMenu<String>(
        context: anchorContext,
        items: const <AppMenuItem<String>>[
          AppMenuItem<String>(value: '', label: '暂无可选项', enabled: false),
        ],
        onSelected: (_) {},
      );
      return;
    }

    final menuItems = <AppMenuItem<String>>[
      for (final term in filtered)
        AppMenuItem<String>(
          value: term.id,
          label: formatTermPrimaryLabel(
            term: term,
            enrollmentYear: enrollmentYear,
          ),
          selected: term.id == currentTermId,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                term.id,
                style: TextStyle(
                  fontSize: 12,
                  color: term.id == currentTermId
                      ? scheme.primary
                      : theme.hintColor,
                  fontWeight: term.id == currentTermId
                      ? FontWeight.w600
                      : FontWeight.normal,
                ),
              ),
              const SizedBox(width: 8),
              if (term.id == currentTermId)
                Icon(Icons.check_rounded, size: 16, color: scheme.primary)
              else
                const SizedBox(width: 16),
            ],
          ),
        ),
    ];

    await showAppMenu<String>(
      context: anchorContext,
      maxHeight: 260,
      items: menuItems,
      onSelected: onSelected,
    );
  }

  String _displayLabelOf(String termId, int? enrollmentYear) {
    if (termId.isEmpty) return '选择学期';
    for (final t in terms) {
      if (t.id == termId) {
        return formatTermPrimaryLabel(term: t, enrollmentYear: enrollmentYear);
      }
    }
    return formatTermPrimaryLabelById(
      termId: termId,
      studentId: studentId,
      enrollmentYear: enrollmentYear,
    );
  }
}

/// 判断考试是否已结束。
///
/// 判定规则：
///  1. 若存在 endTime，则以 endTime 是否早于 now 为准；
///  2. 若存在 startTime：
///     - 若 rawTimeStr 包含具体时刻（如 08:30），按常规考程 2 小时估算有效结束时刻，未满 2 小时前不判定为已结束；
///     - 若仅公布考试日期而无具体时刻（如仅 2026-11-04），在该自然日（23:59:59）结束前不判定为已结束；
///  3. 未公布时间（两者皆空）的考试不判定为已结束。
bool isExamPast(ExamItem exam, DateTime now) {
  if (exam.endTime != null) {
    return exam.endTime!.isBefore(now);
  }
  if (exam.startTime != null) {
    final hasSpecificTime = RegExp(r'\d{1,2}:\d{2}').hasMatch(exam.rawTimeStr);
    if (hasSpecificTime) {
      return exam.startTime!.add(const Duration(hours: 2)).isBefore(now);
    }
    final endOfDay = DateTime(
      exam.startTime!.year,
      exam.startTime!.month,
      exam.startTime!.day,
      23,
      59,
      59,
      999,
    );
    return endOfDay.isBefore(now);
  }
  return false;
}

/// 考试安排列表排序规则：
///  1. 进行中/未来的考试排在最前，按日期与时刻升序排列（确保下一门要考的永远在最顶端）；
///  2. 时间未公布的考试紧随其后；
///  3. 已结束的考试自动下沉到底部（内部同样按时间升序排序）。
List<ExamItem> sortAcademicExams(List<ExamItem> exams, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final list = List<ExamItem>.of(exams);

  int tierOf(ExamItem e) {
    if (isExamPast(e, current)) return 2; // 已结束：挪到底部
    if (e.startTime != null) return 0; // 进行中/未来：置顶
    return 1; // 未定具体时间：居中
  }

  list.sort((a, b) {
    final tierA = tierOf(a);
    final tierB = tierOf(b);
    if (tierA != tierB) {
      return tierA.compareTo(tierB);
    }
    // Tier 0 (进行中/未来)：按日期升序，同日有具体时间的排在仅有日期前，再按时间升序
    if (tierA == 0) {
      final dateA = DateTime(
        a.startTime!.year,
        a.startTime!.month,
        a.startTime!.day,
      );
      final dateB = DateTime(
        b.startTime!.year,
        b.startTime!.month,
        b.startTime!.day,
      );
      final dateCmp = dateA.compareTo(dateB);
      if (dateCmp != 0) return dateCmp;

      final hasTimeA = RegExp(r'\d{1,2}:\d{2}').hasMatch(a.rawTimeStr);
      final hasTimeB = RegExp(r'\d{1,2}:\d{2}').hasMatch(b.rawTimeStr);
      if (hasTimeA != hasTimeB) {
        return hasTimeA ? -1 : 1;
      }

      final cmp = a.startTime!.compareTo(b.startTime!);
      if (cmp != 0) return cmp;
      if (a.endTime != null && b.endTime != null) {
        final endCmp = a.endTime!.compareTo(b.endTime!);
        if (endCmp != 0) return endCmp;
      }
      return a.courseName.compareTo(b.courseName);
    }
    // Tier 1 (未定时间)：按课程名
    if (tierA == 1) {
      return a.courseName.compareTo(b.courseName);
    }
    // Tier 2 (已结束)：按 startTime 升序排在底部
    if (a.startTime != null && b.startTime != null) {
      final cmp = a.startTime!.compareTo(b.startTime!);
      if (cmp != 0) return cmp;
    } else if (a.startTime != null) {
      return -1;
    } else if (b.startTime != null) {
      return 1;
    }
    if (a.endTime != null && b.endTime != null) {
      final endCmp = a.endTime!.compareTo(b.endTime!);
      if (endCmp != 0) return endCmp;
    }
    return a.courseName.compareTo(b.courseName);
  });

  return list;
}

class _ExamSection extends StatelessWidget {
  const _ExamSection({required this.exams, required this.loading});

  final List<ExamItem> exams;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (loading) {
      return Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: const Padding(
          padding: EdgeInsets.all(28.0),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (exams.isEmpty) {
      return Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(
                  Icons.event_available_outlined,
                  size: 40,
                  color: scheme.outline,
                ),
                const SizedBox(height: 8),
                Text(
                  '暂无考试安排数据',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final current = DateTime.now();
    final sortedExams = sortAcademicExams(exams, now: current);

    ExamItem? nextUpcoming;
    for (final e in sortedExams) {
      if (!isExamPast(e, current) && e.startTime != null) {
        nextUpcoming = e;
        break;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (nextUpcoming != null) ...<Widget>[
          NextExamHeroCard(exam: nextUpcoming, now: current),
          const SizedBox(height: 12),
        ],
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: sortedExams.length,
            separatorBuilder: (_, _) => const Divider(height: 0, indent: 16),
            itemBuilder: (context, index) {
              final exam = sortedExams[index];
              return _ExamListTile(
                exam: exam,
                isNext: exam == nextUpcoming,
                isPast: isExamPast(exam, current),
              );
            },
          ),
        ),
      ],
    );
  }
}

@visibleForTesting
class NextExamHeroCard extends StatelessWidget {
  const NextExamHeroCard({super.key, required this.exam, required this.now});

  final ExamItem exam;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final start = exam.startTime;
    String countdownLabel;
    Color badgeColor = scheme.primary;

    if (start != null) {
      final hasSpecificTime = RegExp(r'\d{1,2}:\d{2}')
          .hasMatch(exam.rawTimeStr);
      final effectiveEnd =
          exam.endTime ??
          (hasSpecificTime
              ? start.add(const Duration(hours: 2))
              : DateTime(start.year, start.month, start.day, 23, 59, 59));

      final startDate = DateTime(start.year, start.month, start.day);
      final nowDate = DateTime(now.year, now.month, now.day);
      final dayDiff = startDate.difference(nowDate).inDays;

      if (hasSpecificTime && now.isAfter(start) && now.isBefore(effectiveEnd)) {
        countdownLabel = '正在进行';
        badgeColor = Colors.orange;
      } else if (dayDiff == 0) {
        countdownLabel = '今天考试';
        badgeColor = Colors.redAccent;
      } else if (dayDiff == 1) {
        countdownLabel = '明天考试';
        badgeColor = Colors.orangeAccent;
      } else if (dayDiff > 1) {
        countdownLabel = '离下一场还剩 $dayDiff 天';
      } else {
        countdownLabel = '考试预告';
      }
    } else {
      countdownLabel = '考试预告';
    }

    return Card(
      elevation: 0,
      color: scheme.primaryContainer.withValues(alpha: 0.4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: scheme.primary.withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: badgeColor,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    countdownLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (exam.examType.isNotEmpty)
                  Text(
                    exam.examType,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                const Spacer(),
                if (exam.seatNumber.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surface,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Text(
                      '座位号：${exam.seatNumber}',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: scheme.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              exam.courseName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: <Widget>[
                Icon(
                  Icons.access_time_rounded,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    exam.rawTimeStr.isNotEmpty ? exam.rawTimeStr : '时间未公布',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Row(
              children: <Widget>[
                Icon(
                  Icons.location_on_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      if (exam.campus.isNotEmpty) exam.campus,
                      if (exam.classroom.isNotEmpty) exam.classroom,
                    ].join(' '),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
                if (exam.examForm.isNotEmpty)
                  Text(
                    exam.examForm,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExamListTile extends StatelessWidget {
  const _ExamListTile({
    required this.exam,
    required this.isNext,
    required this.isPast,
  });

  final ExamItem exam;
  final bool isNext;
  final bool isPast;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final primaryText = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: isPast ? scheme.outline : scheme.onSurface,
    );

    final secondaryText = theme.textTheme.bodySmall?.copyWith(
      color: isPast ? scheme.outline.withValues(alpha: 0.7) : scheme.outline,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            margin: const EdgeInsets.only(top: 2),
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isNext
                  ? scheme.primary
                  : (isPast
                        ? scheme.outlineVariant
                        : scheme.outline.withValues(alpha: 0.5)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(child: Text(exam.courseName, style: primaryText)),
                    if (isPast)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
                          ),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text('已结束', style: secondaryText),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  exam.rawTimeStr.isNotEmpty ? exam.rawTimeStr : '时间未公布',
                  style: secondaryText,
                ),
                const SizedBox(height: 2),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        [
                          if (exam.campus.isNotEmpty) exam.campus,
                          if (exam.classroom.isNotEmpty) exam.classroom,
                          if (exam.seatNumber.isNotEmpty)
                            '座位: ${exam.seatNumber}',
                        ].join(' · '),
                        style: secondaryText,
                      ),
                    ),
                    if (exam.examForm.isNotEmpty)
                      Text(exam.examForm, style: secondaryText),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GradeSection extends StatelessWidget {
  const _GradeSection({
    required this.grades,
    required this.stats,
    required this.isNotEvaluated,
    required this.loading,
  });

  final List<GradeItem> grades;
  final GradeStats stats;
  final bool isNotEvaluated;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    if (loading) {
      return Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.4),
        child: const Padding(
          padding: EdgeInsets.all(28.0),
          child: Center(
            child: SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        ),
      );
    }

    if (grades.isEmpty) {
      if (isNotEvaluated) return const SizedBox.shrink();
      return Card(
        elevation: 0,
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Icon(Icons.school_outlined, size: 40, color: scheme.outline),
                const SizedBox(height: 8),
                Text(
                  '暂无成绩数据',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _GpaStatsCard(stats: stats),
        const SizedBox(height: 12),
        Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: grades.length,
            separatorBuilder: (_, _) => const Divider(height: 0, indent: 16),
            itemBuilder: (context, index) {
              final grade = grades[index];
              return _GradeListTile(grade: grade);
            },
          ),
        ),
      ],
    );
  }
}

class _GpaStatsCard extends StatelessWidget {
  const _GpaStatsCard({required this.stats});

  final GradeStats stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: scheme.secondaryContainer.withValues(alpha: 0.35),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.secondary.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: <Widget>[
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '平均学分绩点 (GPA)',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    stats.averageGpa.toStringAsFixed(2),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              height: 40,
              width: 1,
              color: scheme.outlineVariant.withValues(alpha: 0.5),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(left: 14.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '已获 / 总学分',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stats.passedCredits.toStringAsFixed(1)} / ${stats.totalCredits.toStringAsFixed(1)}',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              flex: 2,
              child: Padding(
                padding: const EdgeInsets.only(left: 8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      '修读门数',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${stats.totalCourses} 门',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradeListTile extends StatelessWidget {
  const _GradeListTile({required this.grade});

  final GradeItem grade;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    final scoreColor = _scoreColor(grade.rawScore, scheme);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  grade.courseName,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  [
                    if (grade.courseNature.isNotEmpty) grade.courseNature,
                    '${grade.credit} 学分',
                    '绩点 ${grade.gradePoint}',
                    if (grade.examNature.isNotEmpty &&
                        grade.examNature != '正常考试')
                      grade.examNature,
                  ].join(' · '),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: scoreColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              grade.rawScore,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: scoreColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color _scoreColor(String score, ColorScheme scheme) {
    final num = double.tryParse(score);
    if (num != null) {
      if (num >= 90) return Colors.teal;
      if (num >= 60) return scheme.primary;
      return scheme.error;
    }
    if (score == '优秀') return Colors.teal;
    if (score == '良好' || score == '中等' || score == '及格') return scheme.primary;
    if (score == '不及格' || score == '不合格') return scheme.error;
    return scheme.onSurface;
  }
}

class _EvaluationWarningBanner extends StatelessWidget {
  const _EvaluationWarningBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: Colors.amber.withValues(alpha: 0.15),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: Colors.amber.shade700.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber.shade800,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    '评教尚未完成',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.amber.shade900,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '教务系统提示：本学期教学质量评价未完成，暂不开放成绩查询。请前往青科教务系统网页端完成学生评教后再查询。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: Colors.amber.shade900,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.errorContainer.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.info_outline_rounded, color: scheme.error, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onErrorContainer,
              ),
            ),
          ),
          TextButton(
            onPressed: onRetry,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              foregroundColor: scheme.error,
            ),
            child: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
