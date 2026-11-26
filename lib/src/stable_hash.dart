/// 纯 Dart 稳定哈希与课程色板索引计算（无 Flutter / `dart:ui` 依赖）。
library;

import 'dart:convert';

/// 课程色板标准颜色数量（与 [CoursePalette.colors] 及 Android 原生端一致）。
const int coursePaletteColorCount = 9;

/// FNV-1a 32 位哈希（基于 UTF-8 字节序，跨平台确定）。
int fnv1a32(String text) {
  var hash = 0x811C9DC5;
  for (final byte in utf8.encode(text)) {
    hash ^= byte;
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  return hash;
}

/// FNV-1a 32 位哈希的 8 位小写十六进制表示。
String fnv1a32Hex(String text) =>
    fnv1a32(text).toRadixString(16).padLeft(8, '0');

/// 按课程名计算稳定色板索引（与客户端色板及 Android 原生桌面小组件一致）。
///
/// 采用 UTF-16 `codeUnits` 乘加哈希（31 位正数截断），保持与既有色板映射完全一致。
int courseColorIndex(
  String courseName, {
  int colorCount = coursePaletteColorCount,
}) {
  if (courseName.isEmpty || colorCount <= 0) return 0;
  var hash = 2166136261;
  for (final unit in courseName.codeUnits) {
    hash = (hash ^ unit) * 16777619 & 0x7fffffff;
  }
  return hash % colorCount;
}
