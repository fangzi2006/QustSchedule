/// 桌面小组件实时预览组件（与 Android 原生布局、语义色与解析规则 100% 同构）。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zf_academic/zf_academic.dart';

import '../src/reschedule.dart';
import '../src/term_calendar.dart';
import '../src/timetable.dart';
import '../src/widget_planner.dart';
import '../src/widget_style.dart';
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

/// 示例预览固定黄金参考时刻（10:40：同时具备已结束、进行中、待上调课与当天考试）。
DateTime samplePreviewClock([DateTime? reference]) {
  final base = reference ?? DateTime.now();
  return DateTime(base.year, base.month, base.day, 10, 40);
}

/// 构建用于预览页「示例课表」模式的黄金快照。
///
/// 无论今天是周一还是周日，均保证：
/// - 今日（第 2 周）包含已结束（1-2 节）、进行中（3-4 节）、待上调课（5-6 节）与当天考试；
/// - 调课来源日固定落在第 1 周周日（严格早于本周任意一天），确保调课规则在周一至周日均 100% 命中；
/// - 明日（含周日跨至第 3 周周一）均有课程，周网格排布饱满且含周末课便于检验周末列策略。
WidgetSnapshot buildSampleWidgetSnapshot({DateTime? reference}) {
  final clock = samplePreviewClock(reference);
  final today = DateTime(clock.year, clock.month, clock.day);
  final monday = today.subtract(
    Duration(days: today.weekday - DateTime.monday),
  );
  // 学期起点设为上周周一（今天落在第 2 周），使「第 1 周周日 → 今天」始终满足 fromDate <= toDate。
  final termStart = monday.subtract(const Duration(days: 7));
  final sourceDate = monday.subtract(const Duration(days: 1)); // 第 1 周周日
  final d = today.weekday;

  final entries = <ScheduleEntry>[
    // 今天：1-2 节（已结束 08:30-10:05）
    ScheduleEntry(
      id: 'sample_today_1',
      name: '传感器与检测技术',
      teacher: '张老师',
      location: '高密校区 M1-115',
      day: d,
      startPeriod: 1,
      endPeriod: 2,
      weeks: const <int>[2, 3],
    ),
    // 今天：3-4 节（进行中 10:25-12:00）
    ScheduleEntry(
      id: 'sample_today_2',
      name: '单片机原理及应用A',
      teacher: '王老师',
      location: '高密校区 M1-215',
      day: d,
      startPeriod: 3,
      endPeriod: 4,
      weeks: const <int>[2, 3],
    ),
    // 第 1 周周日：5-6 节（通过调课规则挪到今天 13:30-15:05，标记 rescheduled=true）
    const ScheduleEntry(
      id: 'sample_today_moved',
      name: '电力电子技术',
      teacher: '李老师',
      location: '高密校区 M1-237',
      day: 7,
      startPeriod: 5,
      endPeriod: 6,
      weeks: <int>[1],
    ),
  ];

  // 其余工作日与周末课程（第 2、3 周均排课，保证周一至周日的「明日」均有课程）。
  final extraBlueprints =
      <
        ({
          int day,
          String id,
          String name,
          String teacher,
          String loc,
          int s,
          int e,
        })
      >[
        (
          day: 1,
          id: 'sample_mon_1',
          name: '自动控制原理',
          teacher: '刘老师',
          loc: 'M1-204',
          s: 1,
          e: 2,
        ),
        (
          day: 1,
          id: 'sample_mon_2',
          name: '大学英语IV',
          teacher: '赵老师',
          loc: 'M2-108',
          s: 5,
          e: 6,
        ),
        (
          day: 2,
          id: 'sample_tue_1',
          name: '信号与系统',
          teacher: '陈老师',
          loc: 'M1-308',
          s: 3,
          e: 4,
        ),
        (
          day: 3,
          id: 'sample_wed_1',
          name: '数字信号处理',
          teacher: '周老师',
          loc: 'M1-210',
          s: 1,
          e: 2,
        ),
        (
          day: 4,
          id: 'sample_thu_1',
          name: '嵌入式系统设计',
          teacher: '孙老师',
          loc: 'M1-412',
          s: 3,
          e: 4,
        ),
        (
          day: 4,
          id: 'sample_thu_2',
          name: '工程电磁场',
          teacher: '吴老师',
          loc: 'M1-118',
          s: 7,
          e: 8,
        ),
        (
          day: 5,
          id: 'sample_fri_1',
          name: '电机与拖动基础',
          teacher: '郑老师',
          loc: 'M1-305',
          s: 1,
          e: 2,
        ),
        (
          day: 6,
          id: 'sample_sat_1',
          name: '科技创新实践',
          teacher: '林老师',
          loc: '实验楼 201',
          s: 3,
          e: 4,
        ),
        (
          day: 7,
          id: 'sample_sun_1',
          name: '创新创业导论',
          teacher: '高老师',
          loc: 'M2-302',
          s: 3,
          e: 4,
        ),
      ];

  for (final bp in extraBlueprints) {
    if (bp.day == d) continue;
    if (bp.day == 7 && d != 6) {
      // 非周六时不把周日塞满，保持周末由周六选修课体现即可。
      continue;
    }
    entries.add(
      ScheduleEntry(
        id: bp.id,
        name: bp.name,
        teacher: bp.teacher,
        location: bp.loc,
        day: bp.day,
        startPeriod: bp.s,
        endPeriod: bp.e,
        weeks: const <int>[2, 3],
      ),
    );
  }

  final reschedules = <RescheduleRule>[
    RescheduleRule(
      id: 'sample_rule_1',
      fromMonth: sourceDate.month,
      fromDay: sourceDate.day,
      toMonth: today.month,
      toDay: today.day,
    ),
  ];

  final futureExamDay = today.add(const Duration(days: 3));
  return buildWidgetSnapshot(
    termId: 'sample-term',
    entries: entries,
    reschedules: reschedules,
    termStart: termStart,
    timetables: <Timetable>[defaultTimetable()],
    sectionCounts: defaultSectionCounts,
    maxWeek: 18,
    styles: DesktopWidgetConfigSet.defaults(),
    now: clock,
    exams: <ExamItem>[
      ExamItem(
        courseName: '电力系统稳态分析',
        startTime: DateTime(today.year, today.month, today.day, 16, 0),
        endTime: DateTime(today.year, today.month, today.day, 17, 40),
        classroom: 'M1-117',
        seatNumber: '12',
        examForm: '闭卷',
      ),
      ExamItem(
        courseName: '自动控制原理',
        startTime: DateTime(
          futureExamDay.year,
          futureExamDay.month,
          futureExamDay.day,
          14,
          0,
        ),
        endTime: DateTime(
          futureExamDay.year,
          futureExamDay.month,
          futureExamDay.day,
          16,
          0,
        ),
        classroom: 'M1-302',
        seatNumber: '08',
        examForm: '闭卷',
      ),
    ],
  );
}

class DesktopWidgetPreview extends StatelessWidget {
  const DesktopWidgetPreview({
    super.key,
    required this.kind,
    required this.style,
    this.snapshot,
    this.useSampleData,
    this.todayNarrow = false,
    this.nextWide = false,
    this.now,
    this.systemBrightness = Brightness.light,
  });

  final DesktopWidgetKind kind;
  final DesktopWidgetStyle style;
  final WidgetSnapshot? snapshot;

  /// 为 `true` 时使用黄金示例数据与 10:40 黄金时钟；为 `false` 时忠实呈现 [snapshot]
  /// 真实状态（含空态/未登录/过期）；为 `null` 时在无快照时自动回退示例数据。
  final bool? useSampleData;
  final bool todayNarrow;
  final bool nextWide;
  final DateTime? now;
  final Brightness systemBrightness;

  @override
  Widget build(BuildContext context) {
    final showSample = useSampleData ?? (snapshot == null);
    final effectiveNow = showSample
        ? (now ?? samplePreviewClock())
        : (now ?? DateTime.now());
    final WidgetSnapshot? data = showSample
        ? (snapshot ?? buildSampleWidgetSnapshot(reference: effectiveNow))
        : snapshot;
    final colors = _PreviewColors.resolve(
      style: style,
      systemBrightness: systemBrightness,
    );

    final Widget card = switch (kind) {
      DesktopWidgetKind.today => _TodayPreviewCard(
        style: style,
        snapshot: data,
        now: effectiveNow,
        colors: colors,
        narrow: todayNarrow,
      ),
      DesktopWidgetKind.week => _WeekPreviewCard(
        style: style,
        snapshot: data,
        now: effectiveNow,
        colors: colors,
      ),
      DesktopWidgetKind.next => _NextPreviewCard(
        style: style,
        snapshot: data,
        now: effectiveNow,
        colors: colors,
        wide: nextWide,
      ),
    };

    // 与 Android 侧 COMPLEX_UNIT_DIP / density 保持一致，彻底免疫系统超大字体二次放大。
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: card,
    );
  }
}

enum _PreviewPillTone { accent, ongoing, tomorrow, exam, reschedule, neutral }

enum _PreviewNextStatusKind {
  ongoing,
  today,
  tomorrow,
  examOngoing,
  examUpcoming,
  empty,
  signedOut,
  stale,
}

class _PreviewColors {
  const _PreviewColors({
    required this.isDark,
    required this.surface,
    required this.border,
    required this.primaryText,
    required this.secondaryText,
    required this.tertiaryText,
    required this.accent,
    required this.accentBg,
    required this.ongoingFg,
    required this.ongoingBg,
    required this.ongoingRowBg,
    required this.tomorrowFg,
    required this.tomorrowBg,
    required this.examFg,
    required this.examBg,
    required this.examCardBg,
    required this.examRowBg,
    required this.rescheduleFg,
    required this.rescheduleBg,
    required this.rescheduleDot,
    required this.neutralFg,
    required this.neutralBg,
    required this.neutralBar,
    required this.gridLine,
    required this.todayColumnHighlight,
  });

  final bool isDark;
  final Color surface;
  final Color border;
  final Color primaryText;
  final Color secondaryText;
  final Color tertiaryText;
  final Color accent;
  final Color accentBg;
  final Color ongoingFg;
  final Color ongoingBg;
  final Color ongoingRowBg;
  final Color tomorrowFg;
  final Color tomorrowBg;
  final Color examFg;
  final Color examBg;
  final Color examCardBg;
  final Color examRowBg;
  final Color rescheduleFg;
  final Color rescheduleBg;
  final Color rescheduleDot;
  final Color neutralFg;
  final Color neutralBg;
  final Color neutralBar;
  final Color gridLine;
  final Color todayColumnHighlight;

  CourseColor chipColor(int index) => isDark
      ? CoursePalette.darkOfIndex(index)
      : CoursePalette.lightOfIndex(index);

  Color pillFg(_PreviewPillTone tone) => switch (tone) {
    _PreviewPillTone.accent => accent,
    _PreviewPillTone.ongoing => ongoingFg,
    _PreviewPillTone.tomorrow => tomorrowFg,
    _PreviewPillTone.exam => examFg,
    _PreviewPillTone.reschedule => rescheduleFg,
    _PreviewPillTone.neutral => neutralFg,
  };

  Color pillBg(_PreviewPillTone tone) => switch (tone) {
    _PreviewPillTone.accent => accentBg,
    _PreviewPillTone.ongoing => ongoingBg,
    _PreviewPillTone.tomorrow => tomorrowBg,
    _PreviewPillTone.exam => examBg,
    _PreviewPillTone.reschedule => rescheduleBg,
    _PreviewPillTone.neutral => neutralBg,
  };

  factory _PreviewColors.resolve({
    required DesktopWidgetStyle style,
    required Brightness systemBrightness,
  }) {
    final isDark = switch (style.themeMode) {
      WidgetThemeMode.light => false,
      WidgetThemeMode.dark => true,
      WidgetThemeMode.system ||
      WidgetThemeMode.dynamic => systemBrightness == Brightness.dark,
    };

    // 与 Android WidgetThemeResolver 保持像素级一致。
    final Color baseBg;
    final Color accent;
    if (style.themeMode == WidgetThemeMode.dynamic) {
      baseBg = isDark ? const Color(0xFF1C2330) : const Color(0xFFF3F6FC);
      accent = isDark ? const Color(0xFFAEC6FF) : const Color(0xFF3B66A8);
    } else {
      baseBg = isDark ? const Color(0xFF1C1F26) : Colors.white;
      accent = isDark ? const Color(0xFF9AB4FF) : const Color(0xFF3F5AA6);
    }

    final opacity = style.backgroundOpacity.clamp(0.0, 1.0);
    final surface = baseBg.withValues(alpha: opacity);

    // 边框随不透明度平滑淡出，消除 0% → 5% 跳变。
    final Color border;
    if (opacity <= 0.01) {
      border = Colors.transparent;
    } else {
      final maxBorderAlpha = (isDark ? 34.0 : 20.0) / 255.0;
      border = (isDark ? Colors.white : Colors.black).withValues(
        alpha: maxBorderAlpha * opacity,
      );
    }

    // 低不透明度仅靠纯色提对比保证可读性，严禁文字阴影。
    final lowOpacityFactor = ((0.35 - opacity) / 0.35).clamp(0.0, 1.0);
    final primaryText = isDark
        ? Color.lerp(const Color(0xFFF3F5F8), Colors.white, lowOpacityFactor)!
        : Color.lerp(
            const Color(0xFF1A1D24),
            const Color(0xFF101218),
            lowOpacityFactor,
          )!;
    final secondaryText = isDark
        ? Color.lerp(
            const Color(0xFFB4BCC8),
            const Color(0xFFDDE3EC),
            lowOpacityFactor,
          )!
        : Color.lerp(
            const Color(0xFF5F6775),
            const Color(0xFF3A4150),
            lowOpacityFactor,
          )!;
    final tertiaryText = isDark
        ? Color.lerp(
            const Color(0xFF8A93A2),
            const Color(0xFFC2CBD8),
            lowOpacityFactor,
          )!
        : Color.lerp(
            const Color(0xFF868E9C),
            const Color(0xFF505868),
            lowOpacityFactor,
          )!;

    double lerpAlpha(int a, int b) => (a + (b - a) * lowOpacityFactor) / 255.0;

    final accentBg = accent.withValues(
      alpha: lerpAlpha(isDark ? 0x36 : 0x22, isDark ? 0x58 : 0x3A),
    );
    final ongoingFg = isDark
        ? const Color(0xFF6EE7B7)
        : const Color(0xFF0F766E);
    final ongoingBg = isDark
        ? const Color(0xFF16382C)
        : const Color(0xFFE0F5EE);
    final ongoingRowBg = ongoingFg.withValues(
      alpha: lerpAlpha(isDark ? 0x22 : 0x16, isDark ? 0x36 : 0x28),
    );
    final tomorrowFg = isDark
        ? const Color(0xFFC4B8FF)
        : const Color(0xFF5B4BC4);
    final tomorrowBg = isDark
        ? const Color(0xFF2B2448)
        : const Color(0xFFEFEBFD);
    final examFg = isDark ? const Color(0xFFFFC175) : const Color(0xFFE65100);
    final examBg = isDark ? const Color(0xFF3E2914) : const Color(0xFFFFF3E0);
    final examCardBg = examBg.withValues(alpha: lerpAlpha(0xFF, 0xE6));
    final examRowBg = examFg.withValues(
      alpha: lerpAlpha(isDark ? 0x24 : 0x18, isDark ? 0x38 : 0x2A),
    );
    final rescheduleFg = isDark
        ? const Color(0xFF7DD3FC)
        : const Color(0xFF0369A1);
    final rescheduleBg = isDark
        ? const Color(0xFF172E42)
        : const Color(0xFFE0F2FE);
    final rescheduleDot = isDark
        ? const Color(0xFF5EEAD4)
        : const Color(0xFF0D9488);
    final neutralFg = isDark
        ? const Color(0xFFB8C0CC)
        : const Color(0xFF5A6270);
    final neutralBg = isDark
        ? const Color(0xFF2C313C)
        : const Color(0xFFECEFF4);
    final neutralBar = isDark
        ? const Color(0xFF64748B)
        : const Color(0xFF94A3B8);
    final gridLine = secondaryText.withValues(
      alpha: lerpAlpha(isDark ? 0x24 : 0x20, isDark ? 0x36 : 0x2C),
    );
    final todayColumnHighlight = accent.withValues(
      alpha: (isDark ? 0x10 : 0x0D) / 255.0,
    );

    return _PreviewColors(
      isDark: isDark,
      surface: surface,
      border: border,
      primaryText: primaryText,
      secondaryText: secondaryText,
      tertiaryText: tertiaryText,
      accent: accent,
      accentBg: accentBg,
      ongoingFg: ongoingFg,
      ongoingBg: ongoingBg,
      ongoingRowBg: ongoingRowBg,
      tomorrowFg: tomorrowFg,
      tomorrowBg: tomorrowBg,
      examFg: examFg,
      examBg: examBg,
      examCardBg: examCardBg,
      examRowBg: examRowBg,
      rescheduleFg: rescheduleFg,
      rescheduleBg: rescheduleBg,
      rescheduleDot: rescheduleDot,
      neutralFg: neutralFg,
      neutralBg: neutralBg,
      neutralBar: neutralBar,
      gridLine: gridLine,
      todayColumnHighlight: todayColumnHighlight,
    );
  }
}

double _cornerClearance(DesktopWidgetStyle style) =>
    style.backgroundOpacity <= 0.01 ? 0.0 : style.cornerRadius * 0.30;

class _WidgetShellFrame extends StatelessWidget {
  const _WidgetShellFrame({
    required this.style,
    required this.colors,
    required this.width,
    required this.height,
    required this.padding,
    required this.child,
  });

  final DesktopWidgetStyle style;
  final _PreviewColors colors;
  final double width;
  final double height;
  final EdgeInsets padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final hasVisibleCard = style.backgroundOpacity > 0.01;
    final effectiveRadius = hasVisibleCard
        ? math.min(style.cornerRadius, math.min(width, height) * 0.5)
        : 0.0;
    final innerRadius = hasVisibleCard
        ? (effectiveRadius - 1).clamp(0.0, 28.0)
        : 0.0;

    final Widget padded = Padding(padding: padding, child: child);
    return Container(
      width: width,
      height: height,
      decoration: hasVisibleCard
          ? BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(effectiveRadius),
              border: Border.all(color: colors.border, width: 1),
            )
          : null,
      child: hasVisibleCard
          ? ClipRRect(
              borderRadius: BorderRadius.circular(innerRadius),
              child: padded,
            )
          : padded,
    );
  }
}

class _PreviewPill extends StatelessWidget {
  const _PreviewPill({
    required this.label,
    required this.tone,
    required this.colors,
    required this.fontSize,
    this.padding = const EdgeInsets.symmetric(horizontal: 5.5, vertical: 1.5),
    this.dimmed = false,
  });

  final String label;
  final _PreviewPillTone tone;
  final _PreviewColors colors;
  final double fontSize;
  final EdgeInsets padding;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final rawFg = colors.pillFg(tone);
    final rawBg = colors.pillBg(tone);
    final fg = dimmed ? rawFg.withValues(alpha: 0.45) : rawFg;
    final bg = dimmed ? rawBg.withValues(alpha: rawBg.a * 0.45) : rawBg;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
          height: 1.15,
          color: fg,
        ),
      ),
    );
  }
}

class _TodayPreviewCard extends StatelessWidget {
  const _TodayPreviewCard({
    required this.style,
    required this.snapshot,
    required this.now,
    required this.colors,
    required this.narrow,
  });

  final DesktopWidgetStyle style;
  final WidgetSnapshot? snapshot;
  final DateTime now;
  final _PreviewColors colors;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final compact = style.density == WidgetDensity.compact;
    final scale = style.fontScale;
    final resolved = _resolveTodayForPreview(snapshot, style, now);
    final hasVisibleCard = style.backgroundOpacity > 0.01;
    final clearance = _cornerClearance(style);
    final sideClearance = hasVisibleCard ? style.cornerRadius * 0.16 : 0.0;
    final baseH = narrow ? (compact ? 4.0 : 4.8) : (compact ? 5.0 : 6.0);
    final baseV = narrow ? (compact ? 5.5 : 7.5) : (compact ? 7.0 : 10.0);
    final padH = math.max(baseH, sideClearance);
    final padTop = math.max(baseV, clearance);
    final weekAlignedHeaderStart =
        math.max(compact ? 6.0 : 9.0, clearance) + (hasVisibleCard ? 2.5 : 0.0);
    final headerCornerInset = math.max(0.0, weekAlignedHeaderStart - padH);

    // 2×2 窄卡保持 1:1 正方形（176×176），4×2 宽卡同高横拉（336×176），贴近主流桌面栅格比例；
    // 底部内边距归零，内容直抵 1dp 外描边内缘，彻底去除下方白边。
    return _WidgetShellFrame(
      style: style,
      colors: colors,
      width: narrow ? 176 : 336,
      height: 176,
      padding: EdgeInsets.fromLTRB(padH, padTop, padH, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (style.showHeader) ...<Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: headerCornerInset),
              child: Row(
                children: <Widget>[
                  if (resolved.badgeText.isNotEmpty) ...<Widget>[
                    _PreviewPill(
                      label: resolved.badgeText,
                      tone: resolved.badgeTone,
                      colors: colors,
                      fontSize: (narrow ? 8.5 : 9.2) * scale,
                    ),
                    const SizedBox(width: 5),
                  ],
                  Expanded(
                    child: Text(
                      resolved.headerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: (narrow ? 10.5 : 11.5) * scale,
                        fontWeight: FontWeight.w700,
                        color: resolved.isTomorrow
                            ? colors.primaryText
                            : colors.accent,
                      ),
                    ),
                  ),
                  if (resolved.headerRight.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 6),
                    Text(
                      resolved.headerRight,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: (narrow ? 9.2 : 10.0) * scale,
                        color: colors.secondaryText,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: compact ? 3.5 : 5.5),
          ] else if (resolved.isTomorrow &&
              resolved.compactCue.isNotEmpty) ...<Widget>[
            Padding(
              padding: EdgeInsets.symmetric(horizontal: headerCornerInset),
              child: _PreviewPill(
                label: resolved.compactCue,
                tone: _PreviewPillTone.tomorrow,
                colors: colors,
                fontSize: (narrow ? 8.2 : 8.8) * scale,
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
              ),
            ),
            const SizedBox(height: 3),
          ],
          Expanded(
            child: resolved.items.isNotEmpty
                ? ListView.separated(
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: resolved.items.length,
                    separatorBuilder: (_, _) =>
                        SizedBox(height: compact ? 1.5 : 2.5),
                    itemBuilder: (context, i) => _TodayPreviewItemTile(
                      item: resolved.items[i],
                      style: style,
                      colors: colors,
                      nowMs: now.millisecondsSinceEpoch,
                      narrow: narrow,
                    ),
                  )
                : resolved.examBanner != null
                ? Center(
                    child: _ExamCountdownRow(
                      exam: resolved.examBanner!,
                      style: style,
                      colors: colors,
                      now: now,
                      narrow: narrow,
                    ),
                  )
                : Center(
                    child: Text(
                      resolved.emptyMessage,
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: (narrow ? 10.5 : 11.8) * scale,
                        color: colors.secondaryText,
                      ),
                    ),
                  ),
          ),
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
    required this.narrow,
  });

  final WidgetTimelineItem item;
  final DesktopWidgetStyle style;
  final _PreviewColors colors;
  final int nowMs;
  final bool narrow;

  @override
  Widget build(BuildContext context) {
    final compact = style.density == WidgetDensity.compact;
    final scale = style.fontScale;
    final finished = item.endMs <= nowMs;
    final ongoing = item.startMs <= nowMs && item.endMs > nowMs;
    final dimmed =
        finished && style.finishedCourseMode == FinishedCourseMode.dim;
    final chip = colors.chipColor(item.colorIndex);

    final rowHPad = narrow ? 1.5 : 2.0;
    final rowVPad = narrow ? (compact ? 1.5 : 2.5) : (compact ? 2.0 : 3.0);
    final barLeftGap = narrow ? 3.5 : 4.0;
    final barRightGap = narrow ? 4.0 : 4.5;

    final Color? rowBg = ongoing
        ? (item.isExam ? colors.examRowBg : colors.ongoingRowBg)
        : null;

    final startColor = dimmed
        ? colors.primaryText.withValues(alpha: 0.43)
        : ongoing && item.isExam
        ? colors.examFg
        : ongoing
        ? colors.ongoingFg
        : colors.primaryText;
    final endColor = dimmed
        ? colors.tertiaryText.withValues(alpha: 0.39)
        : colors.tertiaryText;
    final barColor = (item.isExam ? colors.examFg : chip.foreground).withValues(
      alpha: dimmed ? 0.41 : 1.0,
    );
    final titleColor = dimmed
        ? colors.primaryText.withValues(alpha: 0.47)
        : colors.primaryText;
    final metaColor = dimmed
        ? colors.secondaryText.withValues(alpha: 0.43)
        : colors.secondaryText;

    final metaParts = <String>[
      if (style.showLocation && item.location.isNotEmpty) item.location,
      if (item.isExam && style.showLocation && item.seatNumber.isNotEmpty)
        '${item.seatNumber}座',
      if (!item.isExam && style.showTeacher && item.teacher.isNotEmpty)
        item.teacher,
    ];
    final tagSize = (narrow ? 7.5 : 8.5) * scale;

    String? tagLabel;
    _PreviewPillTone? tagTone;
    var tagDimmed = false;
    if (item.isExam && ongoing) {
      tagLabel = '正在考试';
      tagTone = _PreviewPillTone.exam;
    } else if (item.isExam) {
      tagLabel = '考试';
      tagTone = _PreviewPillTone.exam;
      tagDimmed = dimmed;
    } else if (ongoing) {
      tagLabel = '进行中';
      tagTone = _PreviewPillTone.ongoing;
    } else if (item.rescheduled) {
      tagLabel = '调课';
      tagTone = _PreviewPillTone.reschedule;
      tagDimmed = dimmed;
    }

    final hasTwoLines =
        (style.showTime &&
            item.startLabel.isNotEmpty &&
            item.endLabel.isNotEmpty) ||
        metaParts.isNotEmpty;
    final barHeight =
        (hasTwoLines ? (narrow ? 22.0 : 24.0) : (narrow ? 12.5 : 14.0)) * scale;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: rowHPad, vertical: rowVPad),
      decoration: rowBg != null
          ? BoxDecoration(color: rowBg, borderRadius: BorderRadius.circular(10))
          : null,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          if (style.showTime) ...<Widget>[
            SizedBox(
              width: (narrow ? 34.0 : 37.0) * scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  if (item.startLabel.isNotEmpty) ...<Widget>[
                    Text(
                      item.startLabel,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: (narrow ? 9.6 : 10.5) * scale,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                        height: 1.15,
                        color: startColor,
                      ),
                    ),
                    if (item.endLabel.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 1),
                      Text(
                        item.endLabel,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: (narrow ? 8.4 : 9.0) * scale,
                          fontFamily: 'monospace',
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                          height: 1.15,
                          color: endColor,
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
            SizedBox(width: barLeftGap),
          ],
          Container(
            width: 3.0,
            height: barHeight,
            decoration: BoxDecoration(
              color: barColor,
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
          SizedBox(width: barRightGap),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    if (tagLabel != null && tagTone != null) ...<Widget>[
                      _PreviewPill(
                        label: tagLabel,
                        tone: tagTone,
                        colors: colors,
                        fontSize: tagSize,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        dimmed: tagDimmed,
                      ),
                      const SizedBox(width: 4),
                    ],
                    Expanded(
                      child: Text(
                        item.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: (narrow ? 10.8 : 12.0) * scale,
                          fontWeight: FontWeight.w700,
                          height: 1.2,
                          color: titleColor,
                        ),
                      ),
                    ),
                  ],
                ),
                if (metaParts.isNotEmpty) ...<Widget>[
                  const SizedBox(height: 2),
                  Text(
                    metaParts.join(' · '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: (narrow ? 9.0 : 10.0) * scale,
                      height: 1.15,
                      color: metaColor,
                    ),
                  ),
                ],
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
    required this.narrow,
  });

  final WidgetUpcomingExam exam;
  final DesktopWidgetStyle style;
  final _PreviewColors colors;
  final DateTime now;
  final bool narrow;

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
    final prefix = style.showHeader ? '' : '近期考试 · ';
    final datePart = _shortMonthDay(exam.dateIso);
    final timePart = '$datePart ${exam.timeLabel}'.trim();
    final metaParts = <String>[
      if (style.showTime && timePart.isNotEmpty) timePart,
      if (style.showLocation && exam.location.isNotEmpty) exam.location,
      if (style.showLocation && exam.seatNumber.isNotEmpty)
        '${exam.seatNumber}座',
    ];
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(narrow ? 8 : 10),
      decoration: BoxDecoration(
        color: colors.examCardBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '$prefix$countdown$weekPart',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: (narrow ? 9.2 : 10.0) * scale,
              fontWeight: FontWeight.w700,
              color: colors.examFg,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            exam.courseName,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: (narrow ? 11.5 : 13.0) * scale,
              fontWeight: FontWeight.w700,
              color: colors.primaryText,
            ),
          ),
          if (metaParts.isNotEmpty) ...<Widget>[
            const SizedBox(height: 3),
            Text(
              metaParts.join(' · '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: (narrow ? 9.2 : 10.2) * scale,
                color: colors.secondaryText,
              ),
            ),
          ],
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
  final WidgetSnapshot? snapshot;
  final DateTime now;
  final _PreviewColors colors;

  @override
  Widget build(BuildContext context) {
    final compact = style.density == WidgetDensity.compact;
    final scale = style.fontScale;
    final hasVisibleCard = style.backgroundOpacity > 0.01;
    final clearance = _cornerClearance(style);
    final padX = math.max(compact ? 6.0 : 9.0, clearance);
    final padTop = math.max(compact ? 5.5 : 8.5, clearance);
    final padBottom = hasVisibleCard ? math.max(4.0, clearance * 0.55) : 0.0;
    final resolved = _resolveWeekForPreview(snapshot, style, now);

    if (!resolved.signedIn ||
        resolved.isStale ||
        resolved.isTermEnded ||
        resolved.weekPlan == null) {
      final titleText = !resolved.signedIn
          ? '轻触打开青科课表通登录'
          : resolved.isStale
          ? '课表数据已过期'
          : resolved.isTermEnded
          ? '本学期课程已结束'
          : '当前周暂无课表';
      final subText = resolved.isStale
          ? '轻触打开青科课表通自动刷新'
          : resolved.isTermEnded
          ? '切换新学期课表后自动展示'
          : '课表同步后自动展示整周网格';
      return _WidgetShellFrame(
        style: style,
        colors: colors,
        width: 316,
        height: 316,
        padding: EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                titleText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12 * scale,
                  fontWeight: FontWeight.w700,
                  color: colors.primaryText,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subText,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 10.5 * scale,
                  color: colors.secondaryText,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final weekPlan = resolved.weekPlan!;
    final dayCount = resolved.showWeekend ? 7 : 5;
    final maxSection = weekPlan.maxSection.clamp(6, 14);
    // 节次轴宽度随字号动态适配，120% 字号下两位数节次（10-12）绝不裁切。
    final axisWidth = style.showTime
        ? math.max(compact ? 16.0 : 19.0, 14.5 * scale + 5.5)
        : 0.0;
    final headerLeftPad = hasVisibleCard ? 2.5 : 0.0;

    // 4×4 整周网格保持 1:1 正方形（316×316），可见卡片底部保留圆角安全内边距以对齐原生端。
    return _WidgetShellFrame(
      style: style,
      colors: colors,
      width: 316,
      height: 316,
      padding: EdgeInsets.fromLTRB(padX, padTop, padX, padBottom),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (style.showHeader) ...<Widget>[
            Padding(
              padding: EdgeInsets.only(left: headerLeftPad),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  Text(
                    '第 ${weekPlan.week} 周',
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 11 * scale,
                      fontWeight: FontWeight.w700,
                      color: colors.accent,
                    ),
                  ),
                  if (resolved.dateRange.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        resolved.dateRange,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.2 * scale,
                          color: colors.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(height: compact ? 2.5 : 4.5),
          ],
          Row(
            children: <Widget>[
              if (style.showTime) SizedBox(width: axisWidth),
              for (var d = 1; d <= dayCount; d++)
                Expanded(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 4,
                        vertical: 1.5,
                      ),
                      decoration:
                          resolved.isCurrentWeek && d == resolved.todayWeekday
                          ? BoxDecoration(
                              color: colors.accentBg,
                              borderRadius: BorderRadius.circular(4.5),
                            )
                          : null,
                      child: Text(
                        _shortWeekday(d),
                        style: TextStyle(
                          fontSize: 8.8 * scale,
                          fontWeight:
                              resolved.isCurrentWeek &&
                                  d == resolved.todayWeekday
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color:
                              resolved.isCurrentWeek &&
                                  d == resolved.todayWeekday
                              ? colors.accent
                              : colors.secondaryText,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 2.5),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final colWidth = (constraints.maxWidth - axisWidth) / dayCount;
                final rowHeight = constraints.maxHeight / maxSection;
                return Stack(
                  children: <Widget>[
                    if (resolved.isCurrentWeek &&
                        resolved.todayWeekday >= 1 &&
                        resolved.todayWeekday <= dayCount)
                      Positioned(
                        left:
                            axisWidth +
                            (resolved.todayWeekday - 1) * colWidth +
                            0.5,
                        width: math.max(0.0, colWidth - 1.0),
                        top: 0,
                        bottom: 0,
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: colors.todayColumnHighlight,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                    for (var p = 1; p <= maxSection; p++)
                      Positioned(
                        left: axisWidth,
                        right: 0,
                        top: (p - 1) * rowHeight,
                        child: Container(height: 0.5, color: colors.gridLine),
                      ),
                    if (style.showTime)
                      for (var p = 1; p <= maxSection; p++)
                        Positioned(
                          left: 0,
                          width: axisWidth - 1,
                          top: (p - 1) * rowHeight,
                          height: rowHeight,
                          child: Center(
                            child: Text(
                              '$p',
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              style: TextStyle(
                                fontSize: 8.0 * scale,
                                color: colors.secondaryText,
                              ),
                            ),
                          ),
                        ),
                    if (!weekPlan.blocks.any(
                      (b) =>
                          b.day >= 1 &&
                          b.day <= dayCount &&
                          b.startPeriod >= 1 &&
                          b.startPeriod <= maxSection,
                    ))
                      Positioned(
                        left: axisWidth,
                        right: 0,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: Text(
                            weekPlan.blocks.isEmpty
                                ? '本周无课，好好休息'
                                : '工作日无课，周末有安排',
                            style: TextStyle(
                              fontSize: 11.5 * scale,
                              color: colors.secondaryText,
                            ),
                          ),
                        ),
                      )
                    else
                      for (final block in weekPlan.blocks)
                        if (block.day <= dayCount &&
                            block.startPeriod <= maxSection)
                          Positioned(
                            left:
                                axisWidth +
                                (block.day - 1) * colWidth +
                                (block.conflictIndex *
                                    (colWidth / block.conflictTotal)) +
                                (compact ? 0.9 : 1.2),
                            width:
                                (colWidth / block.conflictTotal) -
                                (compact ? 1.8 : 2.4),
                            top:
                                (block.startPeriod - 1) * rowHeight +
                                (compact ? 0.9 : 1.2),
                            height:
                                ((block.endPeriod.clamp(
                                          block.startPeriod,
                                          maxSection,
                                        ) -
                                        block.startPeriod +
                                        1) *
                                    rowHeight) -
                                (compact ? 1.8 : 2.4),
                            child: _WeekPreviewBlockTile(
                              block: block,
                              style: style,
                              chip: colors.chipColor(block.colorIndex),
                              compact: compact,
                              rescheduleDotColor: colors.rescheduleDot,
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

class _WeekPreviewBlockTile extends StatelessWidget {
  const _WeekPreviewBlockTile({
    required this.block,
    required this.style,
    required this.chip,
    required this.compact,
    required this.rescheduleDotColor,
  });

  final WidgetWeekBlock block;
  final DesktopWidgetStyle style;
  final CourseColor chip;
  final bool compact;
  final Color rescheduleDotColor;

  @override
  Widget build(BuildContext context) {
    final scale = style.fontScale;
    final baseStyle = DefaultTextStyle.of(context).style;
    final titleStyle = baseStyle.merge(
      TextStyle(
        fontSize: (compact ? 8.0 : 8.8) * scale,
        height: 1.12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0,
        color: chip.foreground,
      ),
    );
    final teacherStyle = baseStyle.merge(
      TextStyle(
        fontSize: (compact ? 6.8 : 7.4) * scale,
        height: 1.10,
        letterSpacing: 0,
        color: chip.foreground.withValues(alpha: 0.74),
      ),
    );
    final locationStyle = baseStyle.merge(
      TextStyle(
        fontSize: (compact ? 6.8 : 7.4) * scale,
        height: 1.10,
        letterSpacing: 0,
        color: chip.foreground.withValues(alpha: 0.78),
      ),
    );

    final titleText = block.name.trim();
    final teacherText = style.showTeacher ? block.teacher.trim() : '';
    final locationText = style.showLocation ? block.location.trim() : '';
    final pad = compact ? 1.6 : 2.2;
    final fieldGap = compact ? 0.8 : 1.2;

    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: Container(
            padding: EdgeInsets.all(pad),
            decoration: BoxDecoration(
              color: chip.background,
              borderRadius: BorderRadius.circular(5.5),
              border: Border.all(
                color: chip.foreground.withValues(alpha: 0.18),
                width: 0.7,
              ),
            ),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final plan = _solvePreviewBlockPlan(
                  titleText: titleText,
                  teacherText: teacherText,
                  locationText: locationText,
                  width: constraints.maxWidth,
                  height: constraints.maxHeight,
                  fieldGap: fieldGap,
                  titleStyle: titleStyle,
                  detailStyle: locationStyle,
                  textDirection: Directionality.of(context),
                  scaler: TextScaler.noScaling,
                );
                return ClipRect(
                  child: Center(
                    child: SizedBox(
                      width: constraints.maxWidth,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: <Widget>[
                          if (plan.titleLines > 0)
                            Text(
                              titleText,
                              maxLines: plan.titleLines,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: titleStyle,
                            ),
                          if (plan.teacherLines > 0) ...<Widget>[
                            SizedBox(height: fieldGap),
                            Text(
                              teacherText,
                              maxLines: plan.teacherLines,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: teacherStyle,
                            ),
                          ],
                          if (plan.locationLines > 0) ...<Widget>[
                            SizedBox(height: fieldGap),
                            Text(
                              locationText,
                              maxLines: plan.locationLines,
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              style: locationStyle,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        if (block.rescheduled)
          Positioned(
            top: 2,
            right: 2,
            child: Container(
              width: 4.2,
              height: 4.2,
              decoration: BoxDecoration(
                color: rescheduleDotColor,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }
}

({int titleLines, int teacherLines, int locationLines}) _solvePreviewBlockPlan({
  required String titleText,
  required String teacherText,
  required String locationText,
  required double width,
  required double height,
  required double fieldGap,
  required TextStyle titleStyle,
  required TextStyle detailStyle,
  required TextDirection textDirection,
  required TextScaler scaler,
}) {
  if (width <= 0 || height <= 0) {
    return (titleLines: 0, teacherLines: 0, locationLines: 0);
  }

  ({int lines, double lineH}) measureAll(String text, TextStyle style) {
    if (text.isEmpty) return (lines: 0, lineH: 0);
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: textDirection,
      textScaler: scaler,
    )..layout(maxWidth: width);
    final lines = math.max(1, p.computeLineMetrics().length);
    final lineH = p.height / lines;
    p.dispose();
    return (lines: lines, lineH: lineH);
  }

  double fieldH(String text, TextStyle style, int maxLines) {
    if (text.isEmpty || maxLines <= 0) return 0;
    final p = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: textDirection,
      textScaler: scaler,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    final h = p.height;
    p.dispose();
    return h;
  }

  final titleM = measureAll(titleText, titleStyle);
  final teacherM = measureAll(teacherText, detailStyle);
  final locationM = measureAll(locationText, detailStyle);

  var titleLines = titleM.lines;
  var teacherLines = teacherM.lines;
  var locationLines = locationM.lines;

  double used() {
    final fields = <int>[
      titleLines,
      teacherLines,
      locationLines,
    ].where((n) => n > 0).length;
    final gaps = fields > 1 ? fields - 1 : 0;
    return fieldH(titleText, titleStyle, titleLines) +
        fieldH(teacherText, detailStyle, teacherLines) +
        fieldH(locationText, detailStyle, locationLines) +
        gaps * fieldGap;
  }

  bool fits() => used() <= height + 1e-4;

  while (!fits()) {
    if (titleLines > 1) {
      titleLines--;
    } else if (teacherLines > 0) {
      teacherLines = 0;
    } else if (locationLines > 1) {
      locationLines--;
    } else if (locationLines > 0) {
      locationLines = 0;
    } else if (titleLines > 0) {
      titleLines = 0;
    } else {
      break;
    }
  }

  var changed = true;
  while (changed) {
    changed = false;
    if (locationLines < locationM.lines) {
      locationLines++;
      if (fits()) {
        changed = true;
        continue;
      }
      locationLines--;
    }
    if (teacherLines < teacherM.lines) {
      final saved = teacherLines;
      teacherLines = teacherM.lines;
      if (fits()) {
        changed = true;
        continue;
      }
      teacherLines = saved;
    }
    if (titleLines < titleM.lines) {
      titleLines++;
      if (fits()) {
        changed = true;
        continue;
      }
      titleLines--;
    }
  }

  if (titleLines > 0 &&
      titleLines >= titleM.lines &&
      titleLines < 12 &&
      titleM.lineH > 0) {
    final rem = height - used();
    if (rem > titleM.lineH) {
      titleLines = math.min(12, titleLines + (rem / titleM.lineH).floor());
    }
  }

  return (
    titleLines: titleLines,
    teacherLines: teacherLines,
    locationLines: locationLines,
  );
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
  final WidgetSnapshot? snapshot;
  final DateTime now;
  final _PreviewColors colors;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    final scale = style.fontScale;
    final nextInfo = _resolveNextForPreview(snapshot, style, now);
    final clearance = _cornerClearance(style);

    final pillTone = switch (nextInfo.statusKind) {
      _PreviewNextStatusKind.ongoing => _PreviewPillTone.ongoing,
      _PreviewNextStatusKind.today => _PreviewPillTone.accent,
      _PreviewNextStatusKind.tomorrow => _PreviewPillTone.tomorrow,
      _PreviewNextStatusKind.examOngoing ||
      _PreviewNextStatusKind.examUpcoming => _PreviewPillTone.exam,
      _PreviewNextStatusKind.empty ||
      _PreviewNextStatusKind.signedOut ||
      _PreviewNextStatusKind.stale => _PreviewPillTone.neutral,
    };
    final barColor = !nextInfo.hasCourseAccent
        ? colors.neutralBar
        : nextInfo.isExam
        ? colors.examFg
        : colors.chipColor(nextInfo.colorIndex).foreground;
    final timeColor = switch (nextInfo.statusKind) {
      _PreviewNextStatusKind.ongoing => colors.ongoingFg,
      _PreviewNextStatusKind.examOngoing ||
      _PreviewNextStatusKind.examUpcoming => colors.examFg,
      _PreviewNextStatusKind.tomorrow => colors.tomorrowFg,
      _ => colors.accent,
    };

    if (wide) {
      final stripCornerH = style.backgroundOpacity <= 0.01
          ? 0.0
          : style.cornerRadius * 0.45;
      final padH = math.max(12.0, stripCornerH);
      final stripTime = !style.showTime
          ? ''
          : (nextInfo.dateHint.isNotEmpty && nextInfo.timeText.isNotEmpty)
          ? '${nextInfo.dateHint.split(' ').first} ${nextInfo.timeText.split('-').first}'
          : nextInfo.timeText;

      return _WidgetShellFrame(
        style: style,
        colors: colors,
        width: 336,
        height: 76,
        padding: EdgeInsets.symmetric(horizontal: padH, vertical: 6),
        child: Center(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              Expanded(
                child: IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Container(
                        width: 3.5,
                        margin: const EdgeInsets.symmetric(vertical: 2),
                        decoration: BoxDecoration(
                          color: barColor,
                          borderRadius: BorderRadius.circular(1.75),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              nextInfo.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13.0 * scale,
                                fontWeight: FontWeight.w700,
                                height: 1.2,
                                color: colors.primaryText,
                              ),
                            ),
                            if (nextInfo.subtitle.isNotEmpty) ...<Widget>[
                              const SizedBox(height: 2),
                              Text(
                                nextInfo.subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10.5 * scale,
                                  height: 1.15,
                                  color: colors.secondaryText,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  _PreviewPill(
                    label: nextInfo.badge,
                    tone: pillTone,
                    colors: colors,
                    fontSize: 9.0 * scale,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 1.5,
                    ),
                  ),
                  if (stripTime.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 3),
                    Text(
                      stripTime,
                      maxLines: 1,
                      style: TextStyle(
                        fontSize: 11.0 * scale,
                        fontWeight: FontWeight.w700,
                        fontFamily: 'monospace',
                        fontFeatures: const <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                        height: 1.15,
                        color: timeColor,
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      );
    }

    final padH = math.max(12.0, clearance + 2.0);
    final padV = math.max(11.0, clearance + 1.0);
    // 2×2 卡片保持 1:1 正方形（176×176），与桌面真实栅格比例一致。
    return _WidgetShellFrame(
      style: style,
      colors: colors,
      width: 176,
      height: 176,
      padding: EdgeInsets.symmetric(horizontal: padH, vertical: padV),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _PreviewPill(
                label: nextInfo.badge,
                tone: pillTone,
                colors: colors,
                fontSize: 9.5 * scale,
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              ),
              if (nextInfo.dateHint.isNotEmpty) ...<Widget>[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    nextInfo.dateHint,
                    maxLines: 1,
                    textAlign: TextAlign.right,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 9.5 * scale,
                      color: colors.secondaryText,
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Container(
                  width: 3.5,
                  margin: const EdgeInsets.symmetric(vertical: 1.5),
                  decoration: BoxDecoration(
                    color: barColor,
                    borderRadius: BorderRadius.circular(1.75),
                  ),
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    nextInfo.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13.8 * scale,
                      fontWeight: FontWeight.w700,
                      height: 1.15,
                      color: colors.primaryText,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (style.showTime && nextInfo.timeText.isNotEmpty) ...<Widget>[
            const SizedBox(height: 5),
            Text(
              nextInfo.timeText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11.8 * scale,
                fontWeight: FontWeight.w700,
                fontFamily: 'monospace',
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                color: timeColor,
              ),
            ),
          ],
          if (nextInfo.subtitle.isNotEmpty) ...<Widget>[
            const SizedBox(height: 2.5),
            Text(
              nextInfo.subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10.5 * scale,
                color: colors.secondaryText,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

({
  bool signedIn,
  bool isStale,
  bool isTomorrow,
  String badgeText,
  _PreviewPillTone badgeTone,
  String headerTitle,
  String headerRight,
  String compactCue,
  List<WidgetTimelineItem> items,
  WidgetUpcomingExam? examBanner,
  String emptyMessage,
})
_resolveTodayForPreview(
  WidgetSnapshot? snapshot,
  DesktopWidgetStyle style,
  DateTime now,
) {
  if (snapshot == null || !snapshot.signedIn) {
    return (
      signedIn: false,
      isStale: false,
      isTomorrow: false,
      badgeText: '',
      badgeTone: _PreviewPillTone.neutral,
      headerTitle: '今日课表',
      headerRight: '未登录',
      compactCue: '',
      items: const <WidgetTimelineItem>[],
      examBanner: null,
      emptyMessage: '打开青科课表通登录后自动同步课表',
    );
  }

  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final todayIso = formatIsoDate(today);
  final tomorrowIso = formatIsoDate(tomorrow);
  final todayPlan = _findDayPlan(snapshot.days, todayIso);
  final tomorrowPlan = _findDayPlan(snapshot.days, tomorrowIso);

  if (snapshot.days.isNotEmpty && todayPlan == null && tomorrowPlan == null) {
    return (
      signedIn: true,
      isStale: true,
      isTomorrow: false,
      badgeText: '需刷新',
      badgeTone: _PreviewPillTone.neutral,
      headerTitle: '今日课表',
      headerRight: '',
      compactCue: '',
      items: const <WidgetTimelineItem>[],
      examBanner: null,
      emptyMessage: '课表数据已过期，轻触打开应用刷新',
    );
  }

  final nowMs = now.millisecondsSinceEpoch;
  bool allow(WidgetTimelineItem item) => style.showExams || !item.isExam;

  final todayAll = (todayPlan?.items ?? const <WidgetTimelineItem>[])
      .where(allow)
      .toList();
  final remainingToday = todayAll.where((i) => i.endMs > nowMs).toList();
  final visibleToday = style.finishedCourseMode == FinishedCourseMode.hide
      ? remainingToday
      : todayAll;
  final todayWeekLabel = _weekAndWeekday(
    todayPlan?.week ?? 0,
    todayPlan?.weekday ?? today.weekday,
  );

  if (remainingToday.isNotEmpty) {
    final unit = remainingToday.every((i) => i.isExam) ? '场' : '节';
    return (
      signedIn: true,
      isStale: false,
      isTomorrow: false,
      badgeText: '',
      badgeTone: _PreviewPillTone.accent,
      headerTitle: todayWeekLabel,
      headerRight: '剩${remainingToday.length}$unit',
      compactCue: '',
      items: visibleToday,
      examBanner: null,
      emptyMessage: '',
    );
  }

  if (!style.autoSwitchTomorrow) {
    if (todayAll.isNotEmpty) {
      return (
        signedIn: true,
        isStale: false,
        isTomorrow: false,
        badgeText: '',
        badgeTone: _PreviewPillTone.accent,
        headerTitle: todayWeekLabel,
        headerRight: '已结束',
        compactCue: '',
        items: visibleToday,
        examBanner: null,
        emptyMessage: '今日课程已全部结束',
      );
    }
    if (style.showExams) {
      final nearest = _findNearestExam(snapshot.upcomingExams, now, nowMs);
      if (nearest != null) {
        final count = snapshot.upcomingExams
            .where((e) => e.endMs > nowMs)
            .length;
        return (
          signedIn: true,
          isStale: false,
          isTomorrow: false,
          badgeText: '近期考试',
          badgeTone: _PreviewPillTone.exam,
          headerTitle: '',
          headerRight: '$count场待考',
          compactCue: '',
          items: const <WidgetTimelineItem>[],
          examBanner: nearest,
          emptyMessage: '',
        );
      }
    }
    return (
      signedIn: true,
      isStale: false,
      isTomorrow: false,
      badgeText: '',
      badgeTone: _PreviewPillTone.accent,
      headerTitle: todayWeekLabel,
      headerRight: '无课',
      compactCue: '',
      items: const <WidgetTimelineItem>[],
      examBanner: null,
      emptyMessage: '今日无课，好好休息',
    );
  }

  final tomorrowItems = (tomorrowPlan?.items ?? const <WidgetTimelineItem>[])
      .where(allow)
      .toList();
  if (tomorrowItems.isNotEmpty) {
    final tomorrowWd = tomorrowPlan?.weekday ?? tomorrow.weekday;
    final unit = tomorrowItems.every((i) => i.isExam) ? '场' : '节';
    return (
      signedIn: true,
      isStale: false,
      isTomorrow: true,
      badgeText: '明日',
      badgeTone: _PreviewPillTone.tomorrow,
      headerTitle: _weekAndWeekday(tomorrowPlan?.week ?? 0, tomorrowWd),
      headerRight: '共${tomorrowItems.length}$unit',
      compactCue: '明日 · ${_weekdayName(tomorrowWd)}',
      items: tomorrowItems,
      examBanner: null,
      emptyMessage: '',
    );
  }

  if (style.showExams) {
    final nearest = _findNearestExam(snapshot.upcomingExams, now, nowMs);
    if (nearest != null) {
      final count = snapshot.upcomingExams.where((e) => e.endMs > nowMs).length;
      return (
        signedIn: true,
        isStale: false,
        isTomorrow: false,
        badgeText: '近期考试',
        badgeTone: _PreviewPillTone.exam,
        headerTitle: '',
        headerRight: '$count场待考',
        compactCue: '',
        items: const <WidgetTimelineItem>[],
        examBanner: nearest,
        emptyMessage: '',
      );
    }
  }

  return (
    signedIn: true,
    isStale: false,
    isTomorrow: false,
    badgeText: '',
    badgeTone: _PreviewPillTone.accent,
    headerTitle: todayWeekLabel,
    headerRight: todayAll.isNotEmpty ? '已结束' : '无课',
    compactCue: '',
    items: visibleToday,
    examBanner: null,
    emptyMessage: todayAll.isNotEmpty ? '今日课程已全部结束，明日无课' : '今明两日无课，好好休息',
  );
}

({
  bool signedIn,
  _PreviewNextStatusKind statusKind,
  String badge,
  String title,
  String timeText,
  String dateHint,
  String subtitle,
  int colorIndex,
  bool isExam,
  bool hasCourseAccent,
})
_resolveNextForPreview(
  WidgetSnapshot? snapshot,
  DesktopWidgetStyle style,
  DateTime now,
) {
  if (snapshot == null || !snapshot.signedIn) {
    return (
      signedIn: false,
      statusKind: _PreviewNextStatusKind.signedOut,
      badge: '青科课表通',
      title: '轻触登录同步课表',
      timeText: '',
      dateHint: '',
      subtitle: '登录后自动显示下一节课',
      colorIndex: -1,
      isExam: false,
      hasCourseAccent: false,
    );
  }

  final today = DateTime(now.year, now.month, now.day);
  final tomorrow = DateTime(now.year, now.month, now.day + 1);
  final todayPlan = _findDayPlan(snapshot.days, formatIsoDate(today));
  final tomorrowPlan = _findDayPlan(snapshot.days, formatIsoDate(tomorrow));

  if (snapshot.days.isNotEmpty && todayPlan == null && tomorrowPlan == null) {
    return (
      signedIn: true,
      statusKind: _PreviewNextStatusKind.stale,
      badge: '需刷新',
      title: '课表数据已过期',
      timeText: '',
      dateHint: '',
      subtitle: '轻触打开青科课表通刷新',
      colorIndex: -1,
      isExam: false,
      hasCourseAccent: false,
    );
  }

  final nowMs = now.millisecondsSinceEpoch;
  bool allow(WidgetTimelineItem item) => style.showExams || !item.isExam;
  final todayItems = (todayPlan?.items ?? const <WidgetTimelineItem>[])
      .where(allow)
      .toList();

  for (final item in todayItems) {
    if (item.startMs <= nowMs && item.endMs > nowMs) {
      return (
        signedIn: true,
        statusKind: item.isExam
            ? _PreviewNextStatusKind.examOngoing
            : _PreviewNextStatusKind.ongoing,
        badge: item.isExam ? '正在考试' : '正在上课',
        title: item.title,
        timeText: _formatTimeRange(item.startLabel, item.endLabel),
        dateHint: '',
        subtitle: _itemSubtitle(item, style),
        colorIndex: item.colorIndex,
        isExam: item.isExam,
        hasCourseAccent: true,
      );
    }
  }
  for (final item in todayItems) {
    if (item.startMs > nowMs) {
      return (
        signedIn: true,
        statusKind: item.isExam
            ? _PreviewNextStatusKind.examUpcoming
            : _PreviewNextStatusKind.today,
        badge: item.isExam ? '下一场考试' : '今日下一节',
        title: item.title,
        timeText: _formatTimeRange(item.startLabel, item.endLabel),
        dateHint: '',
        subtitle: _itemSubtitle(item, style),
        colorIndex: item.colorIndex,
        isExam: item.isExam,
        hasCourseAccent: true,
      );
    }
  }

  final tomorrowItems = (tomorrowPlan?.items ?? const <WidgetTimelineItem>[])
      .where(allow)
      .toList();
  if (tomorrowItems.isNotEmpty) {
    final item = tomorrowItems.first;
    return (
      signedIn: true,
      statusKind: item.isExam
          ? _PreviewNextStatusKind.examUpcoming
          : _PreviewNextStatusKind.tomorrow,
      badge: item.isExam ? '明日考试' : '明日第一节',
      title: item.title,
      timeText: _formatTimeRange(item.startLabel, item.endLabel),
      dateHint: '',
      subtitle: _itemSubtitle(item, style),
      colorIndex: item.colorIndex,
      isExam: item.isExam,
      hasCourseAccent: true,
    );
  }

  if (style.showExams) {
    final exam = _findNearestExam(snapshot.upcomingExams, now, nowMs);
    if (exam != null) {
      final days = _calendarDayDiff(
        now,
        DateTime.fromMillisecondsSinceEpoch(exam.startMs),
      );
      final datePart = _shortMonthDay(exam.dateIso);
      final hint = <String>[
        if (datePart.isNotEmpty) datePart,
        _weekdayName(exam.weekday),
      ].where((s) => s.isNotEmpty).join(' ');
      return (
        signedIn: true,
        statusKind: _PreviewNextStatusKind.examUpcoming,
        badge: days <= 0 ? '今天考试' : '考试倒计时 $days天',
        title: exam.courseName,
        timeText: exam.timeLabel,
        dateHint: hint,
        subtitle: <String>[
          if (style.showLocation && exam.location.isNotEmpty) exam.location,
          if (style.showLocation && exam.seatNumber.isNotEmpty)
            '${exam.seatNumber}座',
        ].join(' · '),
        colorIndex: exam.colorIndex,
        isExam: true,
        hasCourseAccent: true,
      );
    }
  }

  return (
    signedIn: true,
    statusKind: _PreviewNextStatusKind.empty,
    badge: '日程空闲',
    title: '近期暂无课程',
    timeText: '',
    dateHint: '',
    subtitle: '今明两日无课，好好休息',
    colorIndex: -1,
    isExam: false,
    hasCourseAccent: false,
  );
}

({
  bool signedIn,
  bool isStale,
  bool isTermEnded,
  WidgetWeekPlan? weekPlan,
  bool isCurrentWeek,
  int todayWeekday,
  bool showWeekend,
  String dateRange,
})
_resolveWeekForPreview(
  WidgetSnapshot? snapshot,
  DesktopWidgetStyle style,
  DateTime now,
) {
  final today = DateTime(now.year, now.month, now.day);
  final todayWeekday = today.weekday;
  if (snapshot == null || !snapshot.signedIn || snapshot.weeks.isEmpty) {
    return (
      signedIn: snapshot?.signedIn ?? false,
      isStale: false,
      isTermEnded: false,
      weekPlan: null,
      isCurrentWeek: false,
      todayWeekday: todayWeekday,
      showWeekend: style.weekendMode == WeekendColumnMode.show,
      dateRange: '',
    );
  }
  final todayIso = formatIsoDate(today);
  final todayPlan = _findDayPlan(snapshot.days, todayIso);
  final mondayIso = formatIsoDate(mondayOf(today));
  WidgetWeekPlan? matched;
  for (final w in snapshot.weeks) {
    if (w.startDateIso == mondayIso) {
      matched = w;
      break;
    }
  }
  final lastStart = snapshot.weeks.last.startDateIso;
  if (matched == null &&
      lastStart.isNotEmpty &&
      mondayIso.compareTo(lastStart) > 0) {
    final isFreshPostTerm =
        todayPlan != null && todayPlan.week > snapshot.maxWeek;
    return (
      signedIn: true,
      isStale: !isFreshPostTerm,
      isTermEnded: isFreshPostTerm,
      weekPlan: null,
      isCurrentWeek: false,
      todayWeekday: todayWeekday,
      showWeekend: style.weekendMode == WeekendColumnMode.show,
      dateRange: '',
    );
  }
  final weekPlan = matched ?? snapshot.weeks.first;
  final isCurrentWeek = weekPlan.startDateIso == mondayIso;
  final hasWeekendClass = weekPlan.blocks.any((b) => b.day >= 6);
  final showWeekend = switch (style.weekendMode) {
    WeekendColumnMode.show => true,
    WeekendColumnMode.hide => false,
    WeekendColumnMode.auto => hasWeekendClass,
  };
  final String dateRange;
  if (weekPlan.dayLabels.length >= 2) {
    final first = weekPlan.dayLabels.first.trim();
    final last = weekPlan.dayLabels.last.trim();
    dateRange = first.isNotEmpty && last.isNotEmpty ? '$first–$last' : '';
  } else {
    dateRange = '';
  }
  return (
    signedIn: true,
    isStale: false,
    isTermEnded: false,
    weekPlan: weekPlan,
    isCurrentWeek: isCurrentWeek,
    todayWeekday: todayWeekday,
    showWeekend: showWeekend,
    dateRange: dateRange,
  );
}

WidgetDayPlan? _findDayPlan(List<WidgetDayPlan> days, String dateIso) {
  for (final day in days) {
    if (day.dateIso == dateIso) return day;
  }
  return null;
}

WidgetUpcomingExam? _findNearestExam(
  List<WidgetUpcomingExam> exams,
  DateTime now,
  int nowMs,
) {
  for (final exam in exams) {
    if (exam.startMs <= 0 || exam.endMs <= nowMs) continue;
    final days = _calendarDayDiff(
      now,
      DateTime.fromMillisecondsSinceEpoch(exam.startMs),
    );
    if (days <= widgetUpcomingExamWindowDays) return exam;
  }
  return null;
}

String _formatTimeRange(String startLabel, String endLabel) {
  final s = startLabel.trim();
  final e = endLabel.trim();
  if (s.isEmpty) return '';
  return e.isEmpty ? s : '$s-$e';
}

String _itemSubtitle(WidgetTimelineItem item, DesktopWidgetStyle style) {
  return <String>[
    if (style.showLocation && item.location.isNotEmpty) item.location,
    if (item.isExam && style.showLocation && item.seatNumber.isNotEmpty)
      '${item.seatNumber}座',
    if (!item.isExam && style.showTeacher && item.teacher.isNotEmpty)
      item.teacher,
  ].join(' · ');
}

String _weekAndWeekday(int week, int weekday) {
  final wd = _weekdayName(weekday);
  return week > 0 ? '第$week周 $wd' : wd;
}

String _shortMonthDay(String isoDate) {
  final parts = isoDate.split('-');
  if (parts.length != 3) return isoDate;
  final m = int.tryParse(parts[1]);
  final d = int.tryParse(parts[2]);
  if (m == null || d == null) return isoDate;
  return '$m/$d';
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
