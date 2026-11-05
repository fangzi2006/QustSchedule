/// 轻量行内格式化文本工具（支持 `**加粗**` 与 `` `行内代码` `` 解析）。
library;

import 'package:flutter/material.dart';

/// 将包含 `**加粗**` 或 `` `代码` `` 的轻量 Markdown 行内文本解析为 [TextSpan]。
///
/// 采用零外部依赖正则扫描，内存开销极小且无渲染卡顿风险。
/// 所有的行内片段均自动继承 [baseStyle] 所设定的字号、行高与颜色。
TextSpan buildFormattedTextSpan(
  BuildContext context,
  String text, {
  TextStyle? baseStyle,
  TextStyle? boldStyle,
  TextStyle? codeStyle,
}) {
  if (text.isEmpty) {
    return TextSpan(text: '', style: baseStyle);
  }

  // 快速路径：若不含任何标记字符，直接返回纯文本 TextSpan，免去正则匹配开销
  if (!text.contains('**') && !text.contains('`')) {
    return TextSpan(text: text, style: baseStyle);
  }

  final effectiveBold =
      boldStyle ?? const TextStyle(fontWeight: FontWeight.bold);
  final effectiveCode =
      codeStyle ??
      const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600);

  final spans = <InlineSpan>[];
  final pattern = RegExp(r'(\*\*.*?\*\*|`.*?`)');
  int lastIndex = 0;

  for (final match in pattern.allMatches(text)) {
    if (match.start > lastIndex) {
      spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
    }
    final matched = match.group(0)!;
    if (matched.startsWith('**') &&
        matched.endsWith('**') &&
        matched.length >= 4) {
      spans.add(
        TextSpan(
          text: matched.substring(2, matched.length - 2),
          style: effectiveBold,
        ),
      );
    } else if (matched.startsWith('`') &&
        matched.endsWith('`') &&
        matched.length >= 2) {
      spans.add(
        TextSpan(
          text: matched.substring(1, matched.length - 1),
          style: effectiveCode,
        ),
      );
    }
    lastIndex = match.end;
  }

  if (lastIndex < text.length) {
    spans.add(TextSpan(text: text.substring(lastIndex)));
  }

  return TextSpan(style: baseStyle, children: spans);
}
