/// 课程块：浅底深字的彩色格子。
///
/// 颜色按课程名稳定取（见 [CoursePalette]），同一门课每周同色。
///
/// 排版规则（**高度与字号固定，只调整"各占几行"**）：
///  - 格子高度 = 节数 × 行高，字号固定，不做任何缩放；
///  - 内容水平、垂直居中，超出边界自动换行；
///  - 装不下时按「课程名 → 教师 → 地点」砍，课名最先被压成省略号、地点最后砍；
///  - 地点只显示房间号（`高密校区 M1-239` → `M1-239`）。
///
/// **不变量：预算用的 TextStyle 必须是 `Text` 渲染时实际生效的那一份。**
/// `Text` 会先 merge `DefaultTextStyle`（由此继承 Material 的 `letterSpacing`），
/// 系统开"粗体文字"时再 merge bold；`TextPainter` 两步都不做。漏掉这一步，
/// 测量会比真实渲染少算一行——表现为"有空间却省略"，或把行数用满后溢出。
/// 因此样式里统一显式 `letterSpacing: 0`，并把 merge 后的结果同时交给两边。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:zf_academic/zf_academic.dart';

import '../src/course_text.dart';
import '../theme/course_palette.dart';

class CourseBlock extends StatelessWidget {
  const CourseBlock({
    super.key,
    required this.entry,
    required this.onTap,
    this.showTeacher = true,
    this.showLocation = true,
    this.textScale = 1,
    this.conflict = false,
  });

  final ScheduleEntry entry;
  final VoidCallback onTap;

  /// 是否显示教师 / 上课地点（设置页可关，关了以后空间全给课程名）。
  final bool showTeacher;
  final bool showLocation;

  /// 卡片文字缩放：只乘在这几行字上，时间列与别处不受影响。
  final double textScale;

  /// 该课当天与别的课时间冲突（重修 / 分班并排）。为 true 时在**右上角**画一个
  /// 小圆点——它放在 Stack 覆盖层里，不占文字流位置，**不影响下面的行数分配**。
  final bool conflict;

  /// 冲突小圆点的颜色（配一圈白边，保证在任何课程配色底上都看得清）。
  static const Color conflictBadgeColor = Color(0xFFE53935);

  /// 显式锁定 letterSpacing: 0，避免合并 Material 3 DefaultTextStyle (bodyMedium)
  /// 时继承默认的 0.25 字间距导致测量与渲染宽度不一致。
  static const TextStyle titleStyle = TextStyle(
    fontSize: 11,
    height: 1.25,
    fontWeight: FontWeight.w500,
    letterSpacing: 0,
  );

  // 教师 / 地点比课名再小一号：课名是主信息，教师地点是次信息。
  static const TextStyle detailStyle = TextStyle(
    fontSize: 9,
    height: 1.2,
    letterSpacing: 0,
  );

  /// 水平 / 垂直内边距保持一致：竖着也不白占边，能多给文字一行是一行。
  static const double _paddingX = 3;
  static const double _paddingY = 3;
  static const double _gap = 2;

  @override
  Widget build(BuildContext context) {
    final color = CoursePalette.of(entry.name);
    final scale = textScale.clamp(0.6, 2.0);

    // 关键：提前与 DefaultTextStyle 及系统粗体设置合并，确保传给 TextPainter 的样式
    // 与 Text 内部实际生成的 effectiveTextStyle 100% 一致（包括 fontFamily 等）。
    final baseTextStyle = DefaultTextStyle.of(context).style;
    final boldText = MediaQuery.boldTextOf(context);

    var effectiveTitleStyle = baseTextStyle.merge(
      CourseBlock.titleStyle.copyWith(
        fontSize: CourseBlock.titleStyle.fontSize! * scale,
        color: color.foreground,
      ),
    );
    var effectiveDetailStyle = baseTextStyle.merge(
      CourseBlock.detailStyle.copyWith(
        fontSize: CourseBlock.detailStyle.fontSize! * scale,
        color: color.foreground.withValues(alpha: 0.72),
      ),
    );
    if (boldText) {
      const boldOverride = TextStyle(fontWeight: FontWeight.bold);
      effectiveTitleStyle = effectiveTitleStyle.merge(boldOverride);
      effectiveDetailStyle = effectiveDetailStyle.merge(boldOverride);
    }

    final location = showLocation && entry.location != null
        ? roomOnly(entry.location!)
        : '';
    final scaler = MediaQuery.textScalerOf(context);
    final textDirection = Directionality.of(context);
    final locale = Localizations.maybeLocaleOf(context);

    return Material(
      color: color.background,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: _paddingX,
                  vertical: _paddingY,
                ),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: color.border),
                ),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final plan = _BlockPlan.solve(
                      title: entry.name,
                      teacher: showTeacher ? entry.teacher : null,
                      location: location,
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      scaler: scaler,
                      textDirection: textDirection,
                      locale: locale,
                      titleStyle: effectiveTitleStyle,
                      detailStyle: effectiveDetailStyle,
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
                                  entry.name,
                                  maxLines: plan.titleLines,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: effectiveTitleStyle,
                                ),
                              if (plan.teacherLines > 0) ...<Widget>[
                                const SizedBox(height: _gap),
                                Text(
                                  entry.teacher!,
                                  maxLines: plan.teacherLines,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: effectiveDetailStyle,
                                ),
                              ],
                              if (plan.locationLines > 0) ...<Widget>[
                                const SizedBox(height: _gap),
                                Text(
                                  location,
                                  maxLines: plan.locationLines,
                                  textAlign: TextAlign.center,
                                  overflow: TextOverflow.ellipsis,
                                  style: effectiveDetailStyle,
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
            if (conflict)
              Positioned(
                top: 1,
                left: 1,
                child: Container(
                  key: const ValueKey<String>('course-conflict-badge'),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: CourseBlock.conflictBadgeColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 每个字段各占几行。
///
/// 格子高度与字号都固定，能调的只有行数，依次做四步：
///  1. 按格宽量出各字段完整显示需要几行；
///  2. 装不下时按「课名 → 教师 → 地点」砍（课名最先被压成省略号，地点最后）；
///  3. 砍完若还有富余，按「地点 → 教师 → 课名」回填；
///  4. 最后把剩余高度还能容纳的行数补给课名，避免"下面有空间却显示省略号"。
///
/// 高度一律用与渲染同参的 `TextPainter` 实测，不用 `fontSize × height` 推算
/// （引擎会给每行 ascent/descent 取整，公式会算小）。
class _BlockPlan {
  const _BlockPlan({
    this.titleLines = 0,
    this.teacherLines = 0,
    this.locationLines = 0,
  });

  final int titleLines;
  final int teacherLines;
  final int locationLines;

  /// 仅用于消除 IEEE 754 双精度浮点加法的尾数误差（如 30.000000000000004 > 30.0）。
  static const double _epsilon = 1e-4;

  factory _BlockPlan.solve({
    required String title,
    required String? teacher,
    required String location,
    required double width,
    required double height,
    required TextScaler scaler,
    required TextDirection textDirection,
    required Locale? locale,
    required TextStyle titleStyle,
    required TextStyle detailStyle,
  }) {
    if (width <= 0 || height <= 0) {
      return const _BlockPlan();
    }

    final titleText = title.trim();
    final teacherText = teacher?.trim() ?? '';
    final locationText = location.trim();

    final titleMeasure = titleText.isEmpty
        ? (lines: 0, lineHeight: 0.0)
        : _measure(titleText, titleStyle, width, scaler, textDirection, locale);
    final teacherMeasure = teacherText.isEmpty
        ? (lines: 0, lineHeight: 0.0)
        : _measure(
            teacherText,
            detailStyle,
            width,
            scaler,
            textDirection,
            locale,
          );
    final locationMeasure = locationText.isEmpty
        ? (lines: 0, lineHeight: 0.0)
        : _measure(
            locationText,
            detailStyle,
            width,
            scaler,
            textDirection,
            locale,
          );

    var titleLines = titleMeasure.lines;
    var teacherLines = teacherMeasure.lines;
    var locationLines = locationMeasure.lines;

    final heightCache = <String, double>{};
    double fieldHeight(String text, TextStyle style, int maxLines) {
      if (text.isEmpty || maxLines <= 0) return 0;
      final key = '$text\x00${style.fontSize}\x00$maxLines';
      return heightCache.putIfAbsent(
        key,
        () => _fieldHeight(
          text,
          style,
          width,
          scaler,
          textDirection,
          locale,
          maxLines,
        ),
      );
    }

    double usedHeight() {
      final fields = <int>[
        titleLines,
        teacherLines,
        locationLines,
      ].where((int lines) => lines > 0).length;
      final gaps = fields > 1 ? fields - 1 : 0;
      return fieldHeight(titleText, titleStyle, titleLines) +
          fieldHeight(teacherText, detailStyle, teacherLines) +
          fieldHeight(locationText, detailStyle, locationLines) +
          gaps * CourseBlock._gap;
    }

    bool fits() => usedHeight() <= height + _epsilon;

    final titleNeeded = titleLines;
    final teacherNeeded = teacherLines;
    final locationNeeded = locationLines;

    // 1) 砍：装不下时按「课程名（保底 1 行）→ 教师（整条让位）→ 地点 → 课程名清零」砍。
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

    // 2) 回填：按「地点 → 教师 → 课名」往回加行。
    var changed = true;
    while (changed) {
      changed = false;
      if (locationLines < locationNeeded) {
        locationLines++;
        if (fits()) {
          changed = true;
          continue;
        }
        locationLines--;
      }
      if (teacherLines < teacherNeeded) {
        final saved = teacherLines;
        teacherLines = teacherNeeded;
        if (fits()) {
          changed = true;
          continue;
        }
        teacherLines = saved;
      }
      if (titleLines < titleNeeded) {
        titleLines++;
        if (fits()) {
          changed = true;
          continue;
        }
        titleLines--;
      }
    }

    // 3) 释放富余纵向空间：如果课名已完整显示（titleLines == titleNeeded）且卡片纵向
    //    还有剩余空间，把剩余高度能容纳的额外行数也赋予 titleLines（作为 maxLines 上限）。
    //    因为 Column 是 MainAxisSize.min，放宽 maxLines 不会改变正常 1 行的渲染高度与居中，
    //    但能彻底兜底任何亚像素临界宽度下的换行需求，防止有空间却出省略号。
    if (titleLines > 0 &&
        titleLines >= titleNeeded &&
        titleMeasure.lineHeight > 0) {
      final remaining = height - usedHeight();
      if (remaining > titleMeasure.lineHeight) {
        final extraLines = (remaining / titleMeasure.lineHeight).floor();
        titleLines += extraLines;
      }
    }

    return _BlockPlan(
      titleLines: titleLines,
      teacherLines: teacherLines,
      locationLines: locationLines,
    );
  }

  static double _fieldHeight(
    String text,
    TextStyle style,
    double width,
    TextScaler scaler,
    TextDirection textDirection,
    Locale? locale,
    int maxLines,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: textDirection,
      textScaler: scaler,
      locale: locale,
      maxLines: maxLines,
      ellipsis: '…',
    )..layout(maxWidth: width);
    final h = painter.height;
    painter.dispose();
    return h;
  }

  static ({int lines, double lineHeight}) _measure(
    String text,
    TextStyle style,
    double width,
    TextScaler scaler,
    TextDirection textDirection,
    Locale? locale,
  ) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: TextAlign.center,
      textDirection: textDirection,
      textScaler: scaler,
      locale: locale,
    )..layout(maxWidth: width);
    final lines = math.max(1, painter.computeLineMetrics().length);
    final lineHeight = painter.height / lines;
    painter.dispose();
    return (lines: lines, lineHeight: lineHeight);
  }
}
