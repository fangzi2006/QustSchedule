/// 课程配色：同一门课永远同色，"浅底 + 深字"保证文字清晰。
///
/// 每对颜色取自同一色相的 50 级（底）与 800 级（字），对比度约 8–11:1，
/// 在浅色主题下足够看清，也不像纯黑那样生硬。
///
/// 课程数量超过色板长度时会**撞色**——这是哈希取模的必然结果，接受它：
/// 相邻色相差异足够大，同一屏里不容易认错。
library;

import 'package:flutter/material.dart';

/// 一组课程配色。
class CourseColor {
  /// 格子背景（浅）。
  final Color background;

  /// 文字与边框（深）。
  final Color foreground;

  const CourseColor(this.background, this.foreground);

  /// 边框用前景色降透明度，比纯色描边柔和。
  Color get border => foreground.withValues(alpha: 0.18);
}

class CoursePalette {
  const CoursePalette._();

  /// 10 组色相。改动颜色时保持"底浅字深"这一条，否则文字会糊。
  static const List<CourseColor> colors = <CourseColor>[
    CourseColor(Color(0xFFE6F1FB), Color(0xFF0C447C)), // 蓝
    CourseColor(Color(0xFFE1F5EE), Color(0xFF085041)), // 青
    CourseColor(Color(0xFFEAF3DE), Color(0xFF27500A)), // 绿
    CourseColor(Color(0xFFFAEEDA), Color(0xFF633806)), // 琥珀
    CourseColor(Color(0xFFFAECE7), Color(0xFF712B13)), // 珊瑚
    CourseColor(Color(0xFFFBEAF0), Color(0xFF72243E)), // 粉
    CourseColor(Color(0xFFEEEDFE), Color(0xFF3C3489)), // 紫
    CourseColor(Color(0xFFFCEBEB), Color(0xFF791F1F)), // 红
    CourseColor(Color(0xFFF1EFE8), Color(0xFF444441)), // 灰
  ];

  /// 按课程名稳定取色。
  ///
  /// 用乘加哈希而不是求和：求和会让"数学""学数"这类同字异序的课撞到一起。
  static CourseColor of(String courseName) {
    if (courseName.isEmpty) return colors.first;
    var hash = 2166136261;
    for (final unit in courseName.codeUnits) {
      hash = (hash ^ unit) * 16777619 & 0x7fffffff;
    }
    return colors[hash % colors.length];
  }
}
