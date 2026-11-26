/// 纯 Dart 行内格式化文本分词工具（支持 `**加粗**` 与 `` `行内代码` `` 解析）。
library;

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
