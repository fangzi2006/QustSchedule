/// 学业页面：学期考试日程与成绩绩点概览。
///
/// 包含两大模块：
///  1. 近期考试安排：下一场考试倒计时 Hero 焦点卡片、考场座位号、考试列表（排序置顶沉底）；
///  2. 学期成绩与绩点：学期平均学分绩点 (GPA)、总修学分/已获学分统计、评教拦截提醒、课程成绩明细。
///
/// 采用独立状态订阅，滚动底部留足 [FloatingDock.contentInset] 避开悬浮胶囊。
library;

import 'package:flutter/material.dart';
import 'package:zf_academic/zf_academic.dart';

import '../src/academic_service.dart';
import '../src/app_model.dart';
import '../src/term_selector_helper.dart';
import '../theme/app_theme.dart';
import '../widgets/app_menu.dart';
import '../widgets/floating_dock.dart';
import '../widgets/status_popup.dart';
import '../widgets/tactile_button.dart';

class AcademicPage extends StatefulWidget {
  const AcademicPage({super.key, required this.model, this.isActive = true});

  final AppModel model;

  /// 当前标签页是否处于激活展示态；离屏预挂载时传入 `false`，延迟到真正切入再触发网络加载。
  final bool isActive;

  @override
  State<AcademicPage> createState() => _AcademicPageState();
}

class _AcademicPageState extends State<AcademicPage> {
  AppModel get model => widget.model;
  bool _loadCheckScheduled = false;

  // 考试排序与状态缓存：避免滚动或局部通知重建时重复排序、重复编译正则。
  List<ExamItem>? _cachedExamsSource;
  DateTime? _cachedSortedAt;
  DateTime? _cachedNextTransitionAt;
  _ExamPresentation? _cachedPresentation;

  @override
  void initState() {
    super.initState();
    if (widget.isActive) {
      _scheduleInitialLoadCheck();
    }
  }

  @override
  void didUpdateWidget(covariant AcademicPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.isActive && widget.isActive) {
      _scheduleInitialLoadCheck();
    }
  }

  void _scheduleInitialLoadCheck() {
    if (_loadCheckScheduled) return;
    _loadCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadCheckScheduled = false;
      if (!mounted || !widget.isActive) return;
      if (model.exams.isEmpty &&
          model.grades.isEmpty &&
          !model.academicLoading &&
          !model.isNotEvaluated) {
        model.loadAcademicData();
      }
    });
  }

  _ExamPresentation _getExamPresentation(List<ExamItem> exams) {
    final now = DateTime.now();
    final cached = _cachedPresentation;
    final cachedAt = _cachedSortedAt;
    if (cached != null &&
        cachedAt != null &&
        identical(_cachedExamsSource, exams) &&
        cachedAt.year == now.year &&
        cachedAt.month == now.month &&
        cachedAt.day == now.day &&
        now.difference(cachedAt).abs() < const Duration(seconds: 30) &&
        (_cachedNextTransitionAt == null ||
            now.isBefore(_cachedNextTransitionAt!))) {
      return cached;
    }

    final sortedExams = sortAcademicExams(exams, now: now);
    ExamItem? nextUpcoming;
    DateTime? earliestTransition;

    void considerTransition(ExamItem item) {
      final end = item.effectiveEndTime;
      if (end != null && !end.isBefore(now)) {
        if (earliestTransition == null || end.isBefore(earliestTransition!)) {
          earliestTransition = end;
        }
      }
      final start = item.startTime;
      if (start != null && start.isAfter(now)) {
        if (earliestTransition == null || start.isBefore(earliestTransition!)) {
          earliestTransition = start;
        }
      }
    }

    for (final e in sortedExams) {
      considerTransition(e);
      if (nextUpcoming == null && !isExamPast(e, now) && e.startTime != null) {
        nextUpcoming = e;
      }
    }

    final remaining = nextUpcoming != null
        ? sortedExams.where((e) => e != nextUpcoming).toList(growable: false)
        : sortedExams;
    final remainingPast = <bool>[for (final e in remaining) isExamPast(e, now)];

    final next = _ExamPresentation(
      now: now,
      nextUpcoming: nextUpcoming,
      remainingExams: remaining,
      remainingPastFlags: remainingPast,
    );
    _cachedExamsSource = exams;
    _cachedSortedAt = now;
    _cachedNextTransitionAt = earliestTransition;
    _cachedPresentation = next;
    return next;
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model.academicNotifier,
      builder: (context, _) {
        final currentTermId = model.academicTermId;
        final terms = model.terms?.items ?? const <Term>[];

        return Scaffold(
          appBar: TactileAppBar(
            title: const Text('学业概览'),
            actions: <Widget>[
              _TermSelectorButton(
                currentTermId: currentTermId,
                terms: terms,
                studentId: model.studentId,
                serverCurrentTermId: model.terms?.currentId,
                onSelected: (termId) => model.setAcademicTerm(termId),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 6, right: 10),
                child: TactileIconButton(
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
              ),
            ],
          ),
          body: Stack(
            children: <Widget>[
              Positioned.fill(
                child: CustomScrollView(
                  slivers: <Widget>[
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(
                        16,
                        8,
                        16,
                        FloatingDock.contentInset(context),
                      ),
                      sliver: SliverMainAxisGroup(
                        slivers: <Widget>[
                          if (model.academicError != null) ...<Widget>[
                            SliverToBoxAdapter(
                              child: _ErrorBanner(
                                message: model.academicError!,
                                onRetry: () => model.refreshAcademicData(),
                              ),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 12),
                            ),
                          ],
                          SliverToBoxAdapter(
                            child: _SectionHeader(
                              title: '考试安排',
                              subtitle: model.exams.isNotEmpty
                                  ? '共 ${model.exams.length} 门考试'
                                  : null,
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                          ..._buildExamSectionSlivers(
                            context,
                            exams: model.exams,
                            loading:
                                model.academicLoading && model.exams.isEmpty,
                            presentation:
                                (model.academicLoading &&
                                        model.exams.isEmpty) ||
                                    model.exams.isEmpty
                                ? null
                                : _getExamPresentation(model.exams),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 20)),
                          SliverToBoxAdapter(
                            child: _SectionHeader(
                              title: '成绩与绩点',
                              subtitle: model.grades.isNotEmpty
                                  ? '共 ${model.grades.length} 门成绩'
                                  : null,
                            ),
                          ),
                          const SliverToBoxAdapter(child: SizedBox(height: 8)),
                          if (model.isNotEvaluated) ...<Widget>[
                            const SliverToBoxAdapter(
                              child: _EvaluationWarningBanner(),
                            ),
                            const SliverToBoxAdapter(
                              child: SizedBox(height: 12),
                            ),
                          ],
                          ..._buildGradeSectionSlivers(
                            context,
                            grades: model.grades,
                            stats: model.gradeStats,
                            isNotEvaluated: model.isNotEvaluated,
                            loading:
                                model.academicLoading && model.grades.isEmpty,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // 学业专属提示气泡：附着于学业页，随横向平移手势一同滑入/滑出。
              Positioned(
                top: 6,
                right: 10,
                child: ListenableBuilder(
                  listenable: Listenable.merge(<Listenable>[
                    model.hints,
                    model.routeNotifier,
                    model.academicNotifier,
                  ]),
                  builder: (context, _) =>
                      StatusPopup(model: model, scope: HintScope.academic),
                ),
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

    return TactileSurfaceButton(
      minSize: const Size(0, 36),
      borderRadius: BorderRadius.circular(18),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      onMenuOpen: (anchorContext, dragPointer) =>
          _openMenu(anchorContext, enrollmentYear, dragPointer: dragPointer),
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
    );
  }

  Future<void> _openMenu(
    BuildContext anchorContext,
    int? enrollmentYear, {
    int? dragPointer,
  }) async {
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
        anchorRadius: 18,
        dragPointer: dragPointer,
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
      anchorRadius: 18,
      dragPointer: dragPointer,
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
/// 判定规则：委托给 [ExamItem.effectiveEndTime] 计算有效结束时刻。
bool isExamPast(ExamItem exam, DateTime now) {
  final end = exam.effectiveEndTime;
  if (end != null) {
    return end.isBefore(now);
  }
  return false;
}

final RegExp _examTimeOfDayRegex = RegExp(r'\d{1,2}:\d{2}');

class _ExamPresentation {
  const _ExamPresentation({
    required this.now,
    required this.nextUpcoming,
    required this.remainingExams,
    required this.remainingPastFlags,
  });

  final DateTime now;
  final ExamItem? nextUpcoming;
  final List<ExamItem> remainingExams;
  final List<bool> remainingPastFlags;
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

      final hasTimeA = _examTimeOfDayRegex.hasMatch(a.rawTimeStr);
      final hasTimeB = _examTimeOfDayRegex.hasMatch(b.rawTimeStr);
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

List<Widget> _buildExamSectionSlivers(
  BuildContext context, {
  required List<ExamItem> exams,
  required bool loading,
  required _ExamPresentation? presentation,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  if (loading) {
    return <Widget>[
      SliverToBoxAdapter(
        child: Card(
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
        ),
      ),
    ];
  }

  if (exams.isEmpty || presentation == null) {
    return <Widget>[
      SliverToBoxAdapter(
        child: Card(
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
        ),
      ),
    ];
  }

  final nextUpcoming = presentation.nextUpcoming;
  final remainingExams = presentation.remainingExams;
  final remainingPastFlags = presentation.remainingPastFlags;
  final cardColor =
      CardTheme.of(context).color ??
      (theme.useMaterial3 ? scheme.surfaceContainerLow : theme.cardColor);
  final borderSide = BorderSide(
    color: scheme.outlineVariant.withValues(alpha: 0.5),
  );

  return <Widget>[
    if (nextUpcoming != null) ...<Widget>[
      SliverToBoxAdapter(
        child: NextExamHeroCard(exam: nextUpcoming, now: presentation.now),
      ),
      if (remainingExams.isNotEmpty)
        const SliverToBoxAdapter(child: SizedBox(height: 12)),
    ],
    if (remainingExams.isNotEmpty)
      SliverMainAxisGroup(
        key: const Key('academic-exam-list-card'),
        slivers: <Widget>[
          SliverList.builder(
            itemCount: remainingExams.length,
            itemBuilder: (context, i) => _LazyCardSegment(
              isFirst: i == 0,
              isLast: i == remainingExams.length - 1,
              color: cardColor,
              side: borderSide,
              showTopDivider: i > 0,
              child: _ExamListTile(
                exam: remainingExams[i],
                isPast: remainingPastFlags[i],
              ),
            ),
          ),
        ],
      ),
  ];
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
    final colors = AppColors.of(context);

    final start = exam.startTime;
    String countdownLabel;
    Color badgeColor = scheme.primary;
    Color badgeTextColor = scheme.onPrimary;

    if (start != null) {
      final hasSpecificTime = _examTimeOfDayRegex.hasMatch(exam.rawTimeStr);
      final effectiveEnd =
          exam.effectiveEndTime ??
          DateTime(start.year, start.month, start.day, 23, 59, 59);

      final startDate = DateTime(start.year, start.month, start.day);
      final nowDate = DateTime(now.year, now.month, now.day);
      final dayDiff = startDate.difference(nowDate).inDays;

      if (hasSpecificTime && now.isAfter(start) && now.isBefore(effectiveEnd)) {
        countdownLabel = '正在进行';
        badgeColor = colors.examOngoingBg;
        badgeTextColor = colors.onExamAccentBadge;
      } else if (dayDiff == 0) {
        countdownLabel = '今天考试';
        badgeColor = colors.examUrgentBg;
        badgeTextColor = colors.onExamAccentBadge;
      } else if (dayDiff == 1) {
        countdownLabel = '明天考试';
        badgeColor = colors.examTomorrowBg;
        badgeTextColor = colors.onExamAccentBadge;
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
        borderRadius: BorderRadius.circular(20),
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
                    borderRadius: BorderRadius.circular(AppRadius.micro),
                  ),
                  child: Text(
                    countdownLabel,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: badgeTextColor,
                      fontWeight: FontWeight.bold,
                    ),
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
  const _ExamListTile({required this.exam, required this.isPast});

  final ExamItem exam;
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
              color: isPast
                  ? scheme.outlineVariant
                  : scheme.outline.withValues(alpha: 0.5),
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

List<Widget> _buildGradeSectionSlivers(
  BuildContext context, {
  required List<GradeItem> grades,
  required GradeStats stats,
  required bool isNotEvaluated,
  required bool loading,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  if (loading) {
    return <Widget>[
      SliverToBoxAdapter(
        child: Card(
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
        ),
      ),
    ];
  }

  if (grades.isEmpty) {
    if (isNotEvaluated) return const <Widget>[];
    return <Widget>[
      SliverToBoxAdapter(
        child: Card(
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
        ),
      ),
    ];
  }

  final cardColor =
      CardTheme.of(context).color ??
      (theme.useMaterial3 ? scheme.surfaceContainerLow : theme.cardColor);
  final borderSide = BorderSide(
    color: scheme.outlineVariant.withValues(alpha: 0.5),
  );

  return <Widget>[
    SliverToBoxAdapter(child: _GpaStatsCard(stats: stats)),
    const SliverToBoxAdapter(child: SizedBox(height: 12)),
    SliverList.builder(
      itemCount: grades.length,
      itemBuilder: (context, i) => _LazyCardSegment(
        isFirst: i == 0,
        isLast: i == grades.length - 1,
        color: cardColor,
        side: borderSide,
        showTopDivider: i > 0,
        child: _GradeListTile(grade: grades[i]),
      ),
    ),
  ];
}

/// 懒加载分组卡片中的单条分段容器：在 [SliverList] 内复用整卡的圆角描边与内部分割线外观。
class _LazyCardSegment extends StatelessWidget {
  const _LazyCardSegment({
    required this.isFirst,
    required this.isLast,
    required this.color,
    required this.side,
    required this.showTopDivider,
    required this.child,
  });

  final bool isFirst;
  final bool isLast;
  final Color color;
  final BorderSide side;
  final bool showTopDivider;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color,
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: _CardSegmentShape(
        isFirst: isFirst,
        isLast: isLast,
        radius: 20,
        side: side,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (showTopDivider) const Divider(height: 0, indent: 16),
          child,
        ],
      ),
    );
  }
}

class _CardSegmentShape extends OutlinedBorder {
  const _CardSegmentShape({
    required this.isFirst,
    required this.isLast,
    required this.radius,
    super.side,
  });

  final bool isFirst;
  final bool isLast;
  final double radius;

  @override
  OutlinedBorder copyWith({BorderSide? side}) => _CardSegmentShape(
    isFirst: isFirst,
    isLast: isLast,
    radius: radius,
    side: side ?? this.side,
  );

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    final r = Radius.circular(radius);
    if (isFirst && isLast) {
      return Path()..addRRect(RRect.fromRectAndRadius(rect, r));
    }
    if (isFirst) {
      return Path()
        ..addRRect(RRect.fromRectAndCorners(rect, topLeft: r, topRight: r));
    }
    if (isLast) {
      return Path()..addRRect(
        RRect.fromRectAndCorners(rect, bottomLeft: r, bottomRight: r),
      );
    }
    return Path()..addRect(rect);
  }

  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    final w = side.style == BorderStyle.none ? 0.0 : side.width;
    final innerRect = Rect.fromLTRB(
      rect.left + w,
      rect.top + (isFirst ? w : 0),
      rect.right - w,
      rect.bottom - (isLast ? w : 0),
    );
    final innerR = (radius - w) > 0 ? radius - w : 0.0;
    final r = Radius.circular(innerR);
    if (isFirst && isLast) {
      return Path()..addRRect(RRect.fromRectAndRadius(innerRect, r));
    }
    if (isFirst) {
      return Path()..addRRect(
        RRect.fromRectAndCorners(innerRect, topLeft: r, topRight: r),
      );
    }
    if (isLast) {
      return Path()..addRRect(
        RRect.fromRectAndCorners(innerRect, bottomLeft: r, bottomRight: r),
      );
    }
    return Path()..addRect(innerRect);
  }

  @override
  void paint(Canvas canvas, Rect rect, {TextDirection? textDirection}) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    final paint = side.toPaint();
    final half = side.width / 2;
    final left = rect.left + half;
    final top = rect.top + half;
    final right = rect.right - half;
    final bottom = rect.bottom - half;
    final rVal = (radius - half) > 0 ? radius - half : 0.0;
    final r = Radius.circular(rVal);

    if (isFirst && isLast) {
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          left,
          top,
          right,
          bottom,
          topLeft: r,
          topRight: r,
          bottomLeft: r,
          bottomRight: r,
        ),
        paint,
      );
      return;
    }

    if (isFirst) {
      final path = Path()
        ..moveTo(left, rect.bottom)
        ..lineTo(left, top + rVal)
        ..arcToPoint(Offset(left + rVal, top), radius: r, clockwise: true)
        ..lineTo(right - rVal, top)
        ..arcToPoint(Offset(right, top + rVal), radius: r, clockwise: true)
        ..lineTo(right, rect.bottom);
      canvas.drawPath(path, paint);
      return;
    }

    if (isLast) {
      final path = Path()
        ..moveTo(left, rect.top)
        ..lineTo(left, bottom - rVal)
        ..arcToPoint(Offset(left + rVal, bottom), radius: r, clockwise: false)
        ..lineTo(right - rVal, bottom)
        ..arcToPoint(Offset(right, bottom - rVal), radius: r, clockwise: false)
        ..lineTo(right, rect.top);
      canvas.drawPath(path, paint);
      return;
    }

    canvas.drawLine(Offset(left, rect.top), Offset(left, rect.bottom), paint);
    canvas.drawLine(Offset(right, rect.top), Offset(right, rect.bottom), paint);
  }

  @override
  ShapeBorder scale(double t) => _CardSegmentShape(
    isFirst: isFirst,
    isLast: isLast,
    radius: radius * t,
    side: side.scale(t),
  );
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
        borderRadius: BorderRadius.circular(20),
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
                    '学期平均学分绩点 (GPA)',
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
    final colors = AppColors.of(context);

    final scoreColor = _scoreColor(grade.rawScore, scheme, colors);

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
                    if (grade.gradePoint != null) '绩点 ${grade.gradePoint}',
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
              borderRadius: BorderRadius.circular(AppRadius.small),
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

  Color _scoreColor(String score, ColorScheme scheme, AppColors colors) {
    final num = double.tryParse(score);
    if (num != null) {
      if (num >= 90) return colors.scoreExcellent;
      if (num >= 60) return scheme.primary;
      return scheme.error;
    }
    final trimmed = score.trim();
    if (trimmed == '优秀') return colors.scoreExcellent;
    if (GradeStats.passingScoreLabels.contains(trimmed)) {
      return scheme.primary;
    }
    if (const ['不及格', '不合格', '不通过', 'F', 'f'].contains(trimmed)) {
      return scheme.error;
    }
    return scheme.onSurface;
  }
}

class _EvaluationWarningBanner extends StatelessWidget {
  const _EvaluationWarningBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);

    return Card(
      elevation: 0,
      color: colors.warningBannerBg,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: colors.warningBannerBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14.0),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(
              Icons.warning_amber_rounded,
              color: colors.onWarningBanner,
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
                      color: colors.onWarningBanner,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '教务系统提示：本学期教学质量评价未完成，请前往青科教务系统网页端完成学生评教后再查询。',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colors.onWarningBanner,
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
        borderRadius: BorderRadius.circular(AppRadius.medium),
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
          TactileActionButton(
            variant: TactileActionVariant.text,
            onPressed: onRetry,
            visualDensity: VisualDensity.compact,
            foregroundColor: scheme.error,
            label: const Text('重试'),
          ),
        ],
      ),
    );
  }
}
