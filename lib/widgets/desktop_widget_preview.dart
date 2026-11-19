/// 桌面小组件实时预览组件（与 Android 原生风格与显示规则保持同构）。
library;

import 'package:flutter/material.dart';
import 'package:zf_academic/zf_academic.dart';

import '../src/reschedule.dart';
import '../src/timetable.dart';
import '../src/widget_planner.dart';
import '../src/widget_style.dart';
import '../theme/app_theme.dart';
import '../theme/course_palette.dart';

/// 预览壁纸样式，供用户在配置页模拟真实桌面底图，检验不同透明度与配色效果。
enum PreviewWallpaper {
  softLight('浅色简约', Color(0xFFEBF0F7), Color(0xFFD6E2F0), Brightness.light),
  colorfulGradient(
    '彩绘渐变',
    Color(0xFF4C6EF5),
    Color(0xFFE64980),
    Brightness.dark,
  ),
  darkNight('深色桌面', Color(0xFF151922), Color(0xFF252D3D), Brightness.dark);

  const PreviewWallpaper(
    this.label,
    this.startColor,
    this.endColor,
    this.brightness,
  );

  final String label;
  final Color startColor;
  final Color endColor;
  final Brightness brightness;
}

class DesktopWidgetPreview extends StatelessWidget {
  const DesktopWidgetPreview({
    super.key,
    required this.kind,
    required this.style,
    this.snapshot,
    this.nextWide = false,
    this.now,
    this.systemBrightness = Brightness.light,
  });

  final DesktopWidgetKind kind;
  final DesktopWidgetStyle style;
  final WidgetSnapshot? snapshot;
  final bool nextWide;
  final DateTime? now;
  final Brightness systemBrightness;

  @override
  Widget build(BuildContext context) {
    final effectiveNow = now ?? DateTime.now();
    final data = _effectiveSnapshot(snapshot, style, effectiveNow);
    final colors = _PreviewColors.resolve(
      context,
      style: style,
      systemBrightness: systemBrightness,
    );

    switch (kind) {
      case DesktopWidgetKind.today:
        return _TodayPreviewCard(
          style: style,
          snapshot: data,
          now: effectiveNow,
          colors: colors,
        );
      case DesktopWidgetKind.week:
        return _WeekPreviewCard(
          style: style,
          snapshot: data,
          now: effectiveNow,
          colors: colors,
        );
      case DesktopWidgetKind.next:
        return _NextPreviewCard(
          style: style,
          snapshot: data,
          now: effectiveNow,
          colors: colors,
          wide: nextWide,
        );
    }
  }
}

class _PreviewColors {
  const _PreviewColors({
    required this.isDark,
    required this.surface,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
    required this.accent,
    required this.examBg,
    required this.examFg,
    required this.textShadows,
  });

  final bool isDark;
  final Color surface;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final Color accent;
  final Color examBg;
  final Color examFg;
  final List<Shadow>? textShadows;

  CourseColor chipColor(int index) => isDark
      ? CoursePalette.darkOfIndex(index)
      : CoursePalette.lightOfIndex(index);

  factory _PreviewColors.resolve(
    BuildContext context, {
    required DesktopWidgetStyle style,
    required Brightness systemBrightness,
  }) {
    final isDark = switch (style.themeMode) {
      WidgetThemeMode.light => false,
      WidgetThemeMode.dark => true,
      WidgetThemeMode.system ||
      WidgetThemeMode.dynamic => systemBrightness == Brightness.dark,
    };

    final Color baseBg;
    final Color accent;
    if (style.themeMode == WidgetThemeMode.dynamic) {
      baseBg = isDark ? const Color(0xFF1C2330) : const Color(0xFFF3F6FC);
      accent = isDark ? const Color(0xFFAEC6FF) : const Color(0xFF3B66A8);
    } else {
      baseBg = isDark ? const Color(0xFF1C1F26) : Colors.white;
      accent = isDark
          ? const Color(0xFF9AB4FF)
          : Theme.of(context).colorScheme.primary;
    }

    final opacity = style.backgroundOpacity.clamp(0.0, 1.0);
    final surface = baseBg.withValues(alpha: opacity);
    final border = opacity <= 0.02
        ? Colors.transparent
        : (isDark
              ? Colors.white.withValues(alpha: 0.12)
              : Colors.black.withValues(alpha: 0.07));
    final primaryText = isDark
        ? const Color(0xFFF3F5F8)
        : const Color(0xFF1A1D24);
    final secondaryText = isDark
        ? const Color(0xFFB8C0CC)
        : const Color(0xFF646C7A);
    final appColors = AppColors.of(context);
    final examBg = isDark ? const Color(0xFF3E2914) : appColors.warningChipBg;
    final examFg = isDark ? const Color(0xFFFFC175) : appColors.warningStrong;
    final shadows = opacity < 0.25
        ? <Shadow>[
            Shadow(
              color: (isDark ? Colors.black : Colors.white).withValues(
                alpha: 0.55,
              ),
              blurRadius: 4,
              offset: const Offset(0, 1),
            ),
          ]
        : null;

    return _PreviewColors(
      isDark: isDark,
      surface: surface,
      border: border,
      primaryText: primaryText,
      secondaryText: secondaryText,
      accent: accent,
      examBg: examBg,
      examFg: examFg,
      textShadows: shadows,
    );
  }
}

class _WidgetShellFrame extends StatelessWidget {
  const _WidgetShellFrame({
    required this.style,
    required this.colors,
    required this.width,
    this.height,
    required this.child,
  });

  final DesktopWidgetStyle style;
  final _PreviewColors colors;
  final double width;
  final double? height;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final compact = style.density == WidgetDensity.compact;
    final pad = compact ? 10.0 : 14.0;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: width,
      height: height,
      padding: EdgeInsets.all(pad),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(style.cornerRadius),
        border: Border.all(color: colors.border, width: 1),
        boxShadow: style.backgroundOpacity > 0.2
            ? <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: colors.isDark ? 0.28 : 0.08,
                  ),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: child,
    );
  }
}

class _TodayPreviewCard extends StatelessWidget {
  const _TodayPreviewCard({
    required this.style,
    required this.snapshot,
    required this.now,
    required this.colors,
  });

  final DesktopWidgetStyle style;
  final WidgetSnapshot snapshot;
  final DateTime now;
  final _PreviewColors colors;

  @override
  Widget build(BuildContext context) {
    final compact = style.density == WidgetDensity.compact;
    final scale = style.fontScale;
    final resolved = _resolveTodayForPreview(snapshot, style, now);

    return _WidgetShellFrame(
      style: style,
      colors: colors,
      width: 304,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (style.showHeader) ...<Widget>[
            Row(
              children: <Widget>[
                Text(
                  resolved.headerTitle,
                  style: TextStyle(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                    shadows: colors.textShadows,
                  ),
                ),
                const Spacer(),
                Text(
                  resolved.headerRight,
                  style: TextStyle(
                    fontSize: 11 * scale,
                    color: colors.secondaryText,
                    shadows: colors.textShadows,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 6 : 8),
          ],
          if (resolved.examBanner != null)
            _ExamCountdownRow(
              exam: resolved.examBanner!,
              style: style,
              colors: colors,
              now: now,
            )
          else if (resolved.items.isEmpty)
            Padding(
              padding: EdgeInsets.symmetric(vertical: compact ? 14 : 20),
              child: Center(
                child: Text(
                  '今明两日无课，好好休息',
                  style: TextStyle(
                    fontSize: 12.5 * scale,
                    color: colors.secondaryText,
                    shadows: colors.textShadows,
                  ),
                ),
              ),
            )
          else
            for (
              var i = 0;
              i < resolved.items.length && i < 3;
              i++
            ) ...<Widget>[
              if (i > 0) SizedBox(height: compact ? 5 : 7),
              _TodayPreviewItemTile(
                item: resolved.items[i],
                style: style,
                colors: colors,
                nowMs: now.millisecondsSinceEpoch,
              ),
            ],
        ],
      ),
    );
  }
}

class _TodayPreviewItemTile extends StatelessWidget {
  const _TodayPreviewItemTile({
    required this.item,
    required this.style,
    required this.colors,
    required this.nowMs,
  });

  final WidgetTimelineItem item;
  final DesktopWidgetStyle style;
  final _PreviewColors colors;
  final int nowMs;

  @override
  Widget build(BuildContext context) {
    final compact = style.density == WidgetDensity.compact;
    final scale = style.fontScale;
    final finished = item.endMs <= nowMs;
    final ongoing = item.startMs <= nowMs && item.endMs > nowMs;
    final dimmed =
        finished && style.finishedCourseMode == FinishedCourseMode.dim;
    final chip = colors.chipColor(item.colorIndex);

    final metaParts = <String>[
      if (style.showTime) '${item.startLabel}-${item.endLabel}',
      if (style.showLocation && item.location.isNotEmpty) item.location,
      if (item.isExam && item.seatNumber.isNotEmpty) '${item.seatNumber}座',
      if (!item.isExam && style.showTeacher && item.teacher.isNotEmpty)
        item.teacher,
    ];

    return Opacity(
      opacity: dimmed ? 0.45 : 1.0,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          Container(
            width: 3.5,
            height: compact ? 26 : 30,
            decoration: BoxDecoration(
              color: item.isExam ? colors.examFg : chip.foreground,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (item.isExam) ...<Widget>[
                      Container(
                        margin: const EdgeInsets.only(right: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: colors.examBg,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '考试',
                          style: TextStyle(
                            fontSize: 9.5 * scale,
                            fontWeight: FontWeight.w700,
                            color: colors.examFg,
                          ),
                        ),
                      ),
                    ] else if (ongoing) ...<Widget>[
                      Container(
                        margin: const EdgeInsets.only(right: 5),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 5,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: chip.background,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '进行中',
                          style: TextStyle(
                            fontSize: 9.5 * scale,
                            fontWeight: FontWeight.w700,
                            color: chip.foreground,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13 * scale,
                          fontWeight: FontWeight.w600,
                          color: colors.primaryText,
                          shadows: colors.textShadows,
                        ),
                      ),
                    ),
                  ],
                ),
                if (metaParts.isNotEmpty)
                  Text(
                    metaParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 10.5 * scale,
                      color: colors.secondaryText,
                      shadows: colors.textShadows,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ExamCountdownRow extends StatelessWidget {
  const _ExamCountdownRow({
    required this.exam,
    required this.style,
    required this.colors,
    required this.now,
  });

  final WidgetUpcomingExam exam;
  final DesktopWidgetStyle style;
  final _PreviewColors colors;
  final DateTime now;

  @override
  Widget build(BuildContext context) {
    final scale = style.fontScale;
    final days = _calendarDayDiff(
      now,
      DateTime.fromMillisecondsSinceEpoch(exam.startMs),
    );
    final countdown = days <= 0 ? '今天考试' : '还有 $days 天';
    final weekPart = exam.week > 0
        ? ' · 第${exam.week}周 ${_weekdayName(exam.weekday)}'
        : '';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.examBg.withValues(
          alpha: style.backgroundOpacity < 0.25 ? 0.85 : 1,
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '近期考试 · $countdown$weekPart',
            style: TextStyle(
              fontSize: 10.5 * scale,
              fontWeight: FontWeight.w700,
              color: colors.examFg,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            exam.courseName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13.5 * scale,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            <String>[
              if (style.showTime)
                '${exam.dateIso.substring(5)} ${exam.timeLabel}',
              if (style.showLocation && exam.location.isNotEmpty) exam.location,
              if (exam.seatNumber.isNotEmpty) '${exam.seatNumber}座',
            ].join(' · '),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10.5 * scale,
              color: colors.secondaryText,
            ),
          ),
        ],
      ),
    );
  }
}

class _WeekPreviewCard extends StatelessWidget {
  const _WeekPreviewCard({
    required this.style,
    required this.snapshot,
    required this.now,
    required this.colors,
  });

  final DesktopWidgetStyle style;
  final WidgetSnapshot snapshot;
  final DateTime now;
  final _PreviewColors colors;

  @override
  Widget build(BuildContext context) {
    final compact = style.density == WidgetDensity.compact;
    final scale = style.fontScale;
    final weekPlan = snapshot.weeks.first;
    final hasWeekendClass = weekPlan.blocks.any((b) => b.day >= 6);
    final showWeekend = switch (style.weekendMode) {
      WeekendColumnMode.show => true,
      WeekendColumnMode.hide => false,
      WeekendColumnMode.auto => hasWeekendClass || now.weekday >= 6,
    };
    final dayCount = showWeekend ? 7 : 5;
    final maxSection = weekPlan.maxSection.clamp(8, 12);

    return _WidgetShellFrame(
      style: style,
      colors: colors,
      width: 304,
      height: 286,
      child: Column(
        children: <Widget>[
          if (style.showHeader) ...<Widget>[
            Row(
              children: <Widget>[
                Text(
                  '第 ${weekPlan.week} 周',
                  style: TextStyle(
                    fontSize: 12 * scale,
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                    shadows: colors.textShadows,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '本周课表',
                  style: TextStyle(
                    fontSize: 11 * scale,
                    color: colors.secondaryText,
                    shadows: colors.textShadows,
                  ),
                ),
              ],
            ),
            SizedBox(height: compact ? 4 : 6),
          ],
          Row(
            children: <Widget>[
              if (style.showTime) const SizedBox(width: 22),
              for (var d = 1; d <= dayCount; d++)
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1.5,
                      ),
                      decoration: d == now.weekday
                          ? BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.16),
                              borderRadius: BorderRadius.circular(5),
                            )
                          : null,
                      child: Text(
                        _shortWeekday(d),
                        style: TextStyle(
                          fontSize: 9.5 * scale,
                          fontWeight: d == now.weekday
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: d == now.weekday
                              ? colors.accent
                              : colors.secondaryText,
                          shadows: colors.textShadows,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final axisWidth = style.showTime ? 22.0 : 0.0;
                final colWidth = (constraints.maxWidth - axisWidth) / dayCount;
                final rowHeight = constraints.maxHeight / maxSection;
                return Stack(
                  children: <Widget>[
                    for (var p = 1; p <= maxSection; p++)
                      Positioned(
                        left: axisWidth,
                        right: 0,
                        top: (p - 1) * rowHeight,
                        child: Container(
                          height: 0.5,
                          color: colors.secondaryText.withValues(alpha: 0.14),
                        ),
                      ),
                    if (style.showTime)
                      for (var p = 1; p <= maxSection; p += 2)
                        Positioned(
                          left: 0,
                          width: axisWidth - 2,
                          top: (p - 1) * rowHeight + 1,
                          child: Text(
                            '$p',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 8.5 * scale,
                              color: colors.secondaryText,
                              shadows: colors.textShadows,
                            ),
                          ),
                        ),
                    for (final block in weekPlan.blocks)
                      if (block.day <= dayCount &&
                          block.startPeriod <= maxSection)
                        Positioned(
                          left:
                              axisWidth +
                              (block.day - 1) * colWidth +
                              (block.conflictIndex *
                                  (colWidth / block.conflictTotal)) +
                              1.2,
                          width: (colWidth / block.conflictTotal) - 2.4,
                          top: (block.startPeriod - 1) * rowHeight + 1.2,
                          height:
                              ((block.endPeriod.clamp(
                                        block.startPeriod,
                                        maxSection,
                                      ) -
                                      block.startPeriod +
                                      1) *
                                  rowHeight) -
                              2.4,
                          child: Container(
                            padding: EdgeInsets.all(compact ? 2 : 3),
                            decoration: BoxDecoration(
                              color: colors
                                  .chipColor(block.colorIndex)
                                  .background,
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: Text(
                              style.showLocation && block.location.isNotEmpty
                                  ? '${block.name}\n${block.location}'
                                  : block.name,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 8 * scale,
                                height: 1.15,
                                fontWeight: FontWeight.w600,
                                color: colors
                                    .chipColor(block.colorIndex)
                                    .foreground,
                              ),
                            ),
                          ),
                        ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NextPreviewCard extends StatelessWidget {
  const _NextPreviewCard({
    required this.style,
    required this.snapshot,
    required this.now,
    required this.colors,
    required this.wide,
  });

  final DesktopWidgetStyle style;
  final WidgetSnapshot snapshot;
  final DateTime now;
  final _PreviewColors colors;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scale = style.fontScale;
    final compact = style.density == WidgetDensity.compact;
    final nextInfo = _resolveNextForPreview(snapshot, style, now);

    return _WidgetShellFrame(
      style: style,
      colors: colors,
      width: wide ? 304 : 176,
      child: wide
          ? Row(
              children: <Widget>[
                Container(
                  width: 4,
                  height: compact ? 34 : 40,
                  decoration: BoxDecoration(
                    color: nextInfo.isExam ? colors.examFg : colors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          _StatusChip(
                            label: nextInfo.badge,
                            isExam: nextInfo.isExam,
                            colors: colors,
                            scale: scale,
                          ),
                          if (style.showTime &&
                              nextInfo.timeText.isNotEmpty) ...<Widget>[
                            const SizedBox(width: 6),
                            Text(
                              nextInfo.timeText,
                              style: TextStyle(
                                fontSize: 10.5 * scale,
                                color: colors.secondaryText,
                                shadows: colors.textShadows,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        nextInfo.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13.5 * scale,
                          fontWeight: FontWeight.w700,
                          color: colors.primaryText,
                          shadows: colors.textShadows,
                        ),
                      ),
                      if (nextInfo.subtitle.isNotEmpty)
                        Text(
                          nextInfo.subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10.5 * scale,
                            color: colors.secondaryText,
                            shadows: colors.textShadows,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (style.showHeader) ...<Widget>[
                  _StatusChip(
                    label: nextInfo.badge,
                    isExam: nextInfo.isExam,
                    colors: colors,
                    scale: scale,
                  ),
                  SizedBox(height: compact ? 6 : 8),
                ],
                Text(
                  nextInfo.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14 * scale,
                    fontWeight: FontWeight.w700,
                    height: 1.2,
                    color: colors.primaryText,
                    shadows: colors.textShadows,
                  ),
                ),
                SizedBox(height: compact ? 4 : 6),
                if (style.showTime && nextInfo.timeText.isNotEmpty)
                  Text(
                    nextInfo.timeText,
                    style: TextStyle(
                      fontSize: 11 * scale,
                      color: colors.accent,
                      fontWeight: FontWeight.w600,
                      shadows: colors.textShadows,
                    ),
                  ),
                if (nextInfo.subtitle.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    nextInfo.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11 * scale,
                      color: colors.secondaryText,
                      shadows: colors.textShadows,
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    required this.label,
    required this.isExam,
    required this.colors,
    required this.scale,
  });

  final String label;
  final bool isExam;
  final _PreviewColors colors;
  final double scale;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isExam ? colors.examBg : colors.accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9.5 * scale,
          fontWeight: FontWeight.w700,
          color: isExam ? colors.examFg : colors.accent,
        ),
      ),
    );
  }
}

WidgetSnapshot _effectiveSnapshot(
  WidgetSnapshot? raw,
  DesktopWidgetStyle style,
  DateTime now,
) {
  if (raw != null &&
      raw.signedIn &&
      raw.days.isNotEmpty &&
      raw.weeks.isNotEmpty &&
      (raw.days.first.items.isNotEmpty || raw.weeks.first.blocks.isNotEmpty)) {
    return raw;
  }
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(
    Duration(days: today.weekday - DateTime.monday),
  );
  final d = today.weekday;
  final nextD = (d % 7) + 1;
  return buildWidgetSnapshot(
    termId: 'sample-term',
    entries: <ScheduleEntry>[
      ScheduleEntry(
        id: 'sample1',
        name: '传感器与检测技术',
        teacher: '张老师',
        location: '高密校区 M1-115',
        day: d,
        startPeriod: 1,
        endPeriod: 2,
        weeks: const <int>[1],
      ),
      ScheduleEntry(
        id: 'sample2',
        name: '电力电子技术',
        teacher: '李老师',
        location: '高密校区 M1-237',
        day: d,
        startPeriod: 5,
        endPeriod: 6,
        weeks: const <int>[1],
      ),
      ScheduleEntry(
        id: 'sample3',
        name: '单片机原理及应用A',
        teacher: '王老师',
        location: '高密校区 M1-215',
        day: nextD,
        startPeriod: 3,
        endPeriod: 4,
        weeks: const <int>[1],
      ),
    ],
    reschedules: const <RescheduleRule>[],
    termStart: monday,
    timetables: <Timetable>[defaultTimetable()],
    sectionCounts: defaultSectionCounts,
    maxWeek: 18,
    styles: DesktopWidgetConfigSet.defaults(),
    now: DateTime(now.year, now.month, now.day, 9, 0),
    exams: <ExamItem>[
      ExamItem(
        courseName: '电力系统稳态分析',
        startTime: DateTime(now.year, now.month, now.day, 14, 30),
        endTime: DateTime(now.year, now.month, now.day, 16, 10),
        classroom: 'M1-117',
        seatNumber: '12',
        examForm: '闭卷',
      ),
    ],
  );
}

({
  String headerTitle,
  String headerRight,
  List<WidgetTimelineItem> items,
  WidgetUpcomingExam? examBanner,
})
_resolveTodayForPreview(
  WidgetSnapshot snapshot,
  DesktopWidgetStyle style,
  DateTime now,
) {
  final day0 = snapshot.days.first;
  final nowMs = now.millisecondsSinceEpoch;
  bool allow(WidgetTimelineItem item) => style.showExams || !item.isExam;

  final todayItems = day0.items.where(allow).where((item) {
    if (style.finishedCourseMode == FinishedCourseMode.hide) {
      return item.endMs > nowMs;
    }
    return true;
  }).toList();

  final hasRemainingToday = day0.items.where(allow).any((i) => i.endMs > nowMs);
  if (todayItems.isNotEmpty && hasRemainingToday) {
    return (
      headerTitle: '今日课表',
      headerRight:
          '第${day0.week > 0 ? day0.week : 1}周 ${_weekdayName(day0.weekday)}',
      items: todayItems,
      examBanner: null,
    );
  }

  if (snapshot.days.length > 1) {
    final day1 = snapshot.days[1];
    final tomorrowItems = day1.items.where(allow).toList();
    if (tomorrowItems.isNotEmpty) {
      return (
        headerTitle: '明日预告',
        headerRight:
            '第${day1.week > 0 ? day1.week : 1}周 ${_weekdayName(day1.weekday)}',
        items: tomorrowItems,
        examBanner: null,
      );
    }
  }

  if (style.showExams && snapshot.upcomingExams.isNotEmpty) {
    final nextExam = snapshot.upcomingExams.first;
    final days = _calendarDayDiff(
      now,
      DateTime.fromMillisecondsSinceEpoch(nextExam.startMs),
    );
    if (days <= widgetUpcomingExamWindowDays) {
      return (
        headerTitle: '近期考试',
        headerRight: '${snapshot.upcomingExams.length}场待考',
        items: const <WidgetTimelineItem>[],
        examBanner: nextExam,
      );
    }
  }

  return (
    headerTitle: '今日课表',
    headerRight: _weekdayName(day0.weekday),
    items: todayItems,
    examBanner: null,
  );
}

({String badge, String title, String timeText, String subtitle, bool isExam})
_resolveNextForPreview(
  WidgetSnapshot snapshot,
  DesktopWidgetStyle style,
  DateTime now,
) {
  final nowMs = now.millisecondsSinceEpoch;
  bool allow(WidgetTimelineItem item) => style.showExams || !item.isExam;

  final todayItems = snapshot.days.first.items.where(allow).toList();
  for (final item in todayItems) {
    if (item.startMs <= nowMs && item.endMs > nowMs) {
      return (
        badge: item.isExam ? '正在考试' : '正在上课',
        title: item.title,
        timeText: '${item.startLabel}-${item.endLabel}',
        subtitle: _itemSubtitle(item, style),
        isExam: item.isExam,
      );
    }
  }
  for (final item in todayItems) {
    if (item.startMs > nowMs) {
      return (
        badge: item.isExam ? '下一场考试' : '今日下一节',
        title: item.title,
        timeText: '${item.startLabel}-${item.endLabel}',
        subtitle: _itemSubtitle(item, style),
        isExam: item.isExam,
      );
    }
  }
  if (snapshot.days.length > 1) {
    final tomorrowItems = snapshot.days[1].items.where(allow).toList();
    if (tomorrowItems.isNotEmpty) {
      final item = tomorrowItems.first;
      return (
        badge: item.isExam ? '明日考试' : '明日第一节',
        title: item.title,
        timeText: '${item.startLabel}-${item.endLabel}',
        subtitle: _itemSubtitle(item, style),
        isExam: item.isExam,
      );
    }
  }
  if (style.showExams && snapshot.upcomingExams.isNotEmpty) {
    final exam = snapshot.upcomingExams.first;
    final days = _calendarDayDiff(
      now,
      DateTime.fromMillisecondsSinceEpoch(exam.startMs),
    );
    if (days <= widgetUpcomingExamWindowDays) {
      return (
        badge: days <= 0 ? '今天考试' : '考试倒计时 $days 天',
        title: exam.courseName,
        timeText: exam.timeLabel,
        subtitle: <String>[
          if (style.showLocation && exam.location.isNotEmpty) exam.location,
          if (exam.seatNumber.isNotEmpty) '${exam.seatNumber}座',
        ].join(' · '),
        isExam: true,
      );
    }
  }
  return (
    badge: '日程空闲',
    title: '近期暂无课程',
    timeText: '',
    subtitle: '好好休息',
    isExam: false,
  );
}

String _itemSubtitle(WidgetTimelineItem item, DesktopWidgetStyle style) {
  return <String>[
    if (style.showLocation && item.location.isNotEmpty) item.location,
    if (item.isExam && item.seatNumber.isNotEmpty) '${item.seatNumber}座',
    if (!item.isExam && style.showTeacher && item.teacher.isNotEmpty)
      item.teacher,
  ].join(' · ');
}

int _calendarDayDiff(DateTime from, DateTime to) {
  final a = DateTime.utc(from.year, from.month, from.day);
  final b = DateTime.utc(to.year, to.month, to.day);
  return b.difference(a).inDays;
}

String _weekdayName(int weekday) => const <String>[
  '',
  '周一',
  '周二',
  '周三',
  '周四',
  '周五',
  '周六',
  '周日',
][weekday.clamp(1, 7)];

String _shortWeekday(int weekday) =>
    const <String>['', '一', '二', '三', '四', '五', '六', '日'][weekday.clamp(1, 7)];
