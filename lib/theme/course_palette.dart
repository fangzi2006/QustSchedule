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

  /// 深色模式配套色板（与 [colors] 一一对应，低饱和深底 + 浅色高对比文字）。
  static const List<CourseColor> darkColors = <CourseColor>[
    CourseColor(Color(0xFF15293E), Color(0xFF9ECAFF)), // 蓝
    CourseColor(Color(0xFF122C26), Color(0xFF8BE2CC)), // 青
    CourseColor(Color(0xFF1B2E17), Color(0xFFA9DF9A)), // 绿
    CourseColor(Color(0xFF332613), Color(0xFFF3C87D)), // 琥珀
    CourseColor(Color(0xFF352019), Color(0xFFF5B7A3)), // 珊瑚
    CourseColor(Color(0xFF361D29), Color(0xFFF6B2CE)), // 粉
    CourseColor(Color(0xFF25203E), Color(0xFFC5BFFF)), // 紫
    CourseColor(Color(0xFF381C1E), Color(0xFFF6B0B0)), // 红
    CourseColor(Color(0xFF272624), Color(0xFFD0CEC6)), // 灰
  ];

  /// 按课程名计算稳定色板索引（与客户端 / 原生桌面小组件共享）。
  ///
  /// 用乘加哈希而不是求和：求和会让"数学""学数"这类同字异序的课撞到一起。
  static int indexOf(String courseName) {
    if (courseName.isEmpty) return 0;
    var hash = 2166136261;
    for (final unit in courseName.codeUnits) {
      hash = (hash ^ unit) * 16777619 & 0x7fffffff;
    }
    return hash % colors.length;
  }

  /// 按课程名稳定取色（浅色主题）。
  static CourseColor of(String courseName) => colors[indexOf(courseName)];

  static CourseColor lightOfIndex(int index) =>
      colors[((index % colors.length) + colors.length) % colors.length];

  static CourseColor darkOfIndex(int index) =>
      darkColors[((index % darkColors.length) + darkColors.length) %
          darkColors.length];
}
