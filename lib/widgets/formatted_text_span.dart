/// 轻量行内格式化文本的 Flutter [TextSpan] 拼装工具。
library;

import 'package:flutter/material.dart';

import '../src/formatted_text.dart';

/// 将预解析的 [FormattedSegment] 列表快速拼装为 [TextSpan]（零正则开销）。
TextSpan buildTextSpanFromSegments(
  List<FormattedSegment> segments, {
  TextStyle? baseStyle,
  TextStyle? boldStyle,
  TextStyle? codeStyle,
}) {
  if (segments.isEmpty) {
    return TextSpan(text: '', style: baseStyle);
  }
  if (segments.length == 1 &&
      segments.first.kind == FormattedSegmentKind.plain) {
    return TextSpan(text: segments.first.text, style: baseStyle);
  }

  final effectiveBold =
      boldStyle ?? const TextStyle(fontWeight: FontWeight.bold);
  final effectiveCode =
      codeStyle ??
      const TextStyle(fontFamily: 'monospace', fontWeight: FontWeight.w600);

  return TextSpan(
    style: baseStyle,
    children: <InlineSpan>[
      for (final segment in segments)
        switch (segment.kind) {
          FormattedSegmentKind.plain => TextSpan(text: segment.text),
          FormattedSegmentKind.bold => TextSpan(
            text: segment.text,
            style: effectiveBold,
          ),
          FormattedSegmentKind.code => TextSpan(
            text: segment.text,
            style: effectiveCode,
          ),
        },
    ],
  );
}

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
  return buildTextSpanFromSegments(
    parseFormattedSegments(text),
    baseStyle: baseStyle,
    boldStyle: boldStyle,
    codeStyle: codeStyle,
  );
}
