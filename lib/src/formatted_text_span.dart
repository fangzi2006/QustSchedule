/// 轻量行内格式化文本工具（支持 `**加粗**` 与 `` `行内代码` `` 解析）。
library;

import 'package:flutter/material.dart';

final RegExp _inlineFormatPattern = RegExp(r'(\*\*.*?\*\*|`.*?`)');

/// 行内格式化片段类型（纯 Dart 枚举，可安全跨 Isolate 传递）。
enum FormattedSegmentKind { plain, bold, code }

/// 预解析的行内格式化片段（纯 Dart 不可变对象，可在后台 Isolate 提前拆分）。
class FormattedSegment {
  const FormattedSegment(this.text, this.kind);

  final String text;
  final FormattedSegmentKind kind;
}

/// 将包含 `**加粗**` 或 `` `代码` `` 的文本拆分为不可变 [FormattedSegment] 列表。
///
/// 纯 Dart 无 UI 依赖，可在后台 Isolate 预解析，避免在页面 `build()` 中重复跑正则。
List<FormattedSegment> parseFormattedSegments(String text) {
  if (text.isEmpty) {
    return const <FormattedSegment>[];
  }
  if (!text.contains('**') && !text.contains('`')) {
    return <FormattedSegment>[
      FormattedSegment(text, FormattedSegmentKind.plain),
    ];
  }

  final segments = <FormattedSegment>[];
  var lastIndex = 0;

  for (final match in _inlineFormatPattern.allMatches(text)) {
    if (match.start > lastIndex) {
      segments.add(
        FormattedSegment(
          text.substring(lastIndex, match.start),
          FormattedSegmentKind.plain,
        ),
      );
    }
    final matched = match.group(0)!;
    if (matched.startsWith('**') &&
        matched.endsWith('**') &&
        matched.length >= 4) {
      segments.add(
        FormattedSegment(
          matched.substring(2, matched.length - 2),
          FormattedSegmentKind.bold,
        ),
      );
    } else if (matched.startsWith('`') &&
        matched.endsWith('`') &&
        matched.length >= 2) {
      segments.add(
        FormattedSegment(
          matched.substring(1, matched.length - 1),
          FormattedSegmentKind.code,
        ),
      );
    }
    lastIndex = match.end;
  }

  if (lastIndex < text.length) {
    segments.add(
      FormattedSegment(text.substring(lastIndex), FormattedSegmentKind.plain),
    );
  }

  return List<FormattedSegment>.unmodifiable(segments);
}

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
