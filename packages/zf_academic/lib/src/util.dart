/// 小工具：取值与 id 生成，逐条对齐原项目的同名函数。
library;

import 'dart:async';

/// 休眠（限速与重试退避用）。
Future<void> delay(int milliseconds) =>
    Future<void>.delayed(Duration(milliseconds: milliseconds));

String str(Object? value) => value == null ? '' : value.toString().trim();

/// 取可迭代对象的第一个元素，空则 null（dart:core 没有 firstOrNull）。
T? firstOf<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}

/// 按候选字段名依次取第一个非空值（原项目 `field()`）。
String field(Map<String, dynamic> row, List<String> names) {
  for (final name in names) {
    final value = str(row[name]);
    if (value.isNotEmpty && value != 'null') return value;
  }
  return '';
}

/// 按候选字段名取第一个纯数字值（原项目 `number()`）。
int? number(Map<String, dynamic> row, List<String> names) {
  for (final name in names) {
    final value = str(row[name]);
    if (RegExp(r'^\d+$').hasMatch(value)) return int.parse(value);
  }
  return null;
}

/// 稳定、有界、且不把请求参数泄露到界面上的行标识。
/// FNV-1a 32 位：同样的输入永远得到同样的 id（跨版本稳定）。
String rowKey(List<String> values) {
  var hash = 2166136261;
  for (final unit in values.join('\u0000').codeUnits) {
    hash = ((hash ^ unit) * 16777619) & 0xFFFFFFFF;
  }
  final joined = values.where((value) => value.isNotEmpty).join('|');
  final bounded = joined.length > 96 ? joined.substring(0, 96) : joined;
  return '${hash.toRadixString(16)}:$bounded';
}

bool isBlank(Object? value) => str(value).isEmpty;
