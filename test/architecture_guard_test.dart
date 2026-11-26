/// 架构边界、跨端契约、Windows 编码与文档地图的静态守卫测试（L1）。
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

class _DartDirective {
  const _DartDirective({
    required this.kind,
    required this.uri,
    required this.showSymbols,
    required this.raw,
  });

  final String kind;
  final String uri;
  final List<String> showSymbols;
  final String raw;
}

Directory resolveQustscheduleRoot() {
  bool isRoot(Directory dir) {
    final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    final mainDart = File(
      '${dir.path}${Platform.pathSeparator}lib${Platform.pathSeparator}main.dart',
    );
    return pubspec.existsSync() && mainDart.existsSync();
  }

  Directory cur = Directory.current.absolute;
  while (true) {
    if (isRoot(cur)) return cur;
    final nested = Directory(
      '${cur.path}${Platform.pathSeparator}qustschedule',
    );
    if (isRoot(nested)) return nested;
    final parent = cur.parent;
    if (parent.path == cur.path) break;
    cur = parent;
  }

  if (Platform.script.scheme == 'file') {
    Directory scriptDir = File.fromUri(Platform.script).parent.absolute;
    while (true) {
      if (isRoot(scriptDir)) return scriptDir;
      final nested = Directory(
        '${scriptDir.path}${Platform.pathSeparator}qustschedule',
      );
      if (isRoot(nested)) return nested;
      final parent = scriptDir.parent;
      if (parent.path == scriptDir.path) break;
      scriptDir = parent;
    }
  }

  throw StateError(
    'Unable to locate qustschedule root from ${Directory.current.path}',
  );
}

String _toPosixRelative(Directory root, FileSystemEntity entity) {
  final rootPath = root.absolute.path.replaceAll('\\', '/');
  final entityPath = entity.absolute.path.replaceAll('\\', '/');
  final prefix = rootPath.endsWith('/') ? rootPath : '$rootPath/';
  if (!entityPath.startsWith(prefix)) {
    throw StateError('$entityPath is not under $prefix');
  }
  return entityPath.substring(prefix.length);
}

List<File> _listFiles(
  Directory dir, {
  required String extension,
  bool Function(String relativePath)? exclude,
  Directory? root,
}) {
  if (!dir.existsSync()) return const <File>[];
  final base = root ?? dir;
  final result = <File>[];
  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final rel = _toPosixRelative(base, entity);
    if (!rel.endsWith(extension)) continue;
    if (exclude != null && exclude(rel)) continue;
    result.add(entity);
  }
  result.sort(
    (a, b) => _toPosixRelative(base, a).compareTo(_toPosixRelative(base, b)),
  );
  return result;
}

/// 扫描并剥离 Dart 注释；当 [stripStrings] 为 true 时同时清空字符串字面量内容。
String _scanDartSource(String source, {required bool stripStrings}) {
  final out = StringBuffer();
  final int len = source.length;
  int i = 0;

  void emitPreservingNewlines(int start, int end, {String replacement = ''}) {
    if (replacement.isNotEmpty) {
      out.write(replacement);
    }
    for (int k = start; k < end; k++) {
      out.write(source.codeUnitAt(k) == 10 ? '\n' : ' ');
    }
  }

  void copyRaw(int start, int end) {
    out.write(source.substring(start, end));
  }

  int skipBlockComment(int start) {
    int depth = 1;
    int pos = start + 2;
    while (pos < len && depth > 0) {
      if (pos + 1 < len &&
          source.codeUnitAt(pos) == 47 &&
          source.codeUnitAt(pos + 1) == 42) {
        depth++;
        pos += 2;
      } else if (pos + 1 < len &&
          source.codeUnitAt(pos) == 42 &&
          source.codeUnitAt(pos + 1) == 47) {
        depth--;
        pos += 2;
      } else {
        pos++;
      }
    }
    return pos;
  }

  late int Function(int start) scanString;

  int scanExpression(int start) {
    int depth = 1;
    int pos = start;
    while (pos < len && depth > 0) {
      final int ch = source.codeUnitAt(pos);
      if (ch == 47 && pos + 1 < len && source.codeUnitAt(pos + 1) == 47) {
        final int nl = source.indexOf('\n', pos + 2);
        final int end = nl == -1 ? len : nl;
        emitPreservingNewlines(pos, end);
        pos = end;
        continue;
      }
      if (ch == 47 && pos + 1 < len && source.codeUnitAt(pos + 1) == 42) {
        final int end = skipBlockComment(pos);
        emitPreservingNewlines(pos, end);
        pos = end;
        continue;
      }
      if (ch == 114 &&
          pos + 1 < len &&
          (source.codeUnitAt(pos + 1) == 39 ||
              source.codeUnitAt(pos + 1) == 34)) {
        pos = scanString(pos);
        continue;
      }
      if (ch == 39 || ch == 34) {
        pos = scanString(pos);
        continue;
      }
      if (ch == 123) {
        depth++;
      } else if (ch == 125) {
        depth--;
        if (depth == 0) {
          if (!stripStrings) out.write('}');
          return pos + 1;
        }
      }
      if (!stripStrings) out.writeCharCode(ch);
      pos++;
    }
    return pos;
  }

  scanString = (int start) {
    int pos = start;
    bool isRaw = false;
    if (source.codeUnitAt(pos) == 114) {
      isRaw = true;
      pos++;
    }
    final int quote = source.codeUnitAt(pos);
    final bool isTriple =
        pos + 2 < len &&
        source.codeUnitAt(pos + 1) == quote &&
        source.codeUnitAt(pos + 2) == quote;
    final int openLen = isTriple ? 3 : 1;
    pos += openLen;

    if (!stripStrings) {
      copyRaw(start, pos);
    } else {
      out.write(quote == 39 ? "''" : '""');
    }

    while (pos < len) {
      final int ch = source.codeUnitAt(pos);
      if (!isRaw && ch == 92) {
        final int next = pos + 2 <= len ? pos + 2 : len;
        if (!stripStrings) {
          copyRaw(pos, next);
        } else {
          emitPreservingNewlines(pos, next);
        }
        pos = next;
        continue;
      }
      if (!isRaw &&
          ch == 36 &&
          pos + 1 < len &&
          source.codeUnitAt(pos + 1) == 123) {
        if (!stripStrings) out.write(r'${');
        pos = scanExpression(pos + 2);
        continue;
      }
      if (isTriple) {
        if (pos + 2 < len &&
            source.codeUnitAt(pos) == quote &&
            source.codeUnitAt(pos + 1) == quote &&
            source.codeUnitAt(pos + 2) == quote) {
          if (!stripStrings) {
            copyRaw(pos, pos + 3);
          }
          return pos + 3;
        }
      } else if (ch == quote) {
        if (!stripStrings) {
          out.writeCharCode(ch);
        }
        return pos + 1;
      } else if (ch == 10) {
        out.write('\n');
        pos++;
        return pos;
      }
      if (!stripStrings) {
        out.writeCharCode(ch);
      } else if (ch == 10) {
        out.write('\n');
      }
      pos++;
    }
    return pos;
  };

  while (i < len) {
    final int ch = source.codeUnitAt(i);
    if (ch == 47 && i + 1 < len && source.codeUnitAt(i + 1) == 47) {
      final int nl = source.indexOf('\n', i + 2);
      final int end = nl == -1 ? len : nl;
      emitPreservingNewlines(i, end);
      i = end;
      continue;
    }
    if (ch == 47 && i + 1 < len && source.codeUnitAt(i + 1) == 42) {
      final int end = skipBlockComment(i);
      emitPreservingNewlines(i, end);
      i = end;
      continue;
    }
    if (ch == 114 &&
        i + 1 < len &&
        (source.codeUnitAt(i + 1) == 39 || source.codeUnitAt(i + 1) == 34)) {
      i = scanString(i);
      continue;
    }
    if (ch == 39 || ch == 34) {
      i = scanString(i);
      continue;
    }
    out.writeCharCode(ch);
    i++;
  }

  return out.toString();
}

String stripDartComments(String source) =>
    _scanDartSource(source, stripStrings: false);

String stripDartCommentsAndStrings(String source) =>
    _scanDartSource(source, stripStrings: true);

int _skipDartString(String source, int start) {
  final int len = source.length;
  int pos = start;
  bool isRaw = false;
  if (pos < len && source.codeUnitAt(pos) == 114) {
    isRaw = true;
    pos++;
  }
  final int quote = source.codeUnitAt(pos);
  final bool isTriple =
      pos + 2 < len &&
      source.codeUnitAt(pos + 1) == quote &&
      source.codeUnitAt(pos + 2) == quote;
  pos += isTriple ? 3 : 1;

  while (pos < len) {
    final int ch = source.codeUnitAt(pos);
    if (!isRaw && ch == 92) {
      pos += 2;
      continue;
    }
    if (isTriple) {
      if (pos + 2 < len &&
          source.codeUnitAt(pos) == quote &&
          source.codeUnitAt(pos + 1) == quote &&
          source.codeUnitAt(pos + 2) == quote) {
        return pos + 3;
      }
    } else if (ch == quote || ch == 10) {
      return pos + 1;
    }
    pos++;
  }
  return len;
}

bool _isIdentChar(int codeUnit) =>
    (codeUnit >= 48 && codeUnit <= 57) ||
    (codeUnit >= 65 && codeUnit <= 90) ||
    (codeUnit >= 97 && codeUnit <= 122) ||
    codeUnit == 95 ||
    codeUnit == 36;

String _unquoteDartString(String raw) {
  final String s = raw.startsWith('r') ? raw.substring(1) : raw;
  if ((s.startsWith("'''") && s.endsWith("'''")) ||
      (s.startsWith('"""') && s.endsWith('"""'))) {
    return s.length >= 6 ? s.substring(3, s.length - 3) : '';
  }
  if ((s.startsWith("'") && s.endsWith("'")) ||
      (s.startsWith('"') && s.endsWith('"'))) {
    return s.length >= 2 ? s.substring(1, s.length - 1) : '';
  }
  return s;
}

List<_DartDirective> _extractDartDirectives(String source) {
  final cleaned = stripDartComments(source);
  final int len = cleaned.length;
  final directives = <_DartDirective>[];
  int braceDepth = 0;
  int i = 0;

  while (i < len) {
    final int ch = cleaned.codeUnitAt(i);
    if (ch == 114 &&
        i + 1 < len &&
        (cleaned.codeUnitAt(i + 1) == 39 || cleaned.codeUnitAt(i + 1) == 34)) {
      i = _skipDartString(cleaned, i);
      continue;
    }
    if (ch == 39 || ch == 34) {
      i = _skipDartString(cleaned, i);
      continue;
    }
    if (ch == 123) {
      braceDepth++;
      i++;
      continue;
    }
    if (ch == 125) {
      if (braceDepth > 0) braceDepth--;
      i++;
      continue;
    }

    if (braceDepth == 0 &&
        (i == 0 || !_isIdentChar(cleaned.codeUnitAt(i - 1)))) {
      String? kind;
      if (cleaned.startsWith('import', i) &&
          (i + 6 >= len || !_isIdentChar(cleaned.codeUnitAt(i + 6)))) {
        kind = 'import';
      } else if (cleaned.startsWith('export', i) &&
          (i + 6 >= len || !_isIdentChar(cleaned.codeUnitAt(i + 6)))) {
        kind = 'export';
      }

      if (kind != null) {
        int pos = i + 6;
        while (pos < len && cleaned.codeUnitAt(pos) <= 32) {
          pos++;
        }
        if (pos < len &&
            (cleaned.codeUnitAt(pos) == 39 ||
                cleaned.codeUnitAt(pos) == 34 ||
                (cleaned.codeUnitAt(pos) == 114 &&
                    pos + 1 < len &&
                    (cleaned.codeUnitAt(pos + 1) == 39 ||
                        cleaned.codeUnitAt(pos + 1) == 34)))) {
          final int uriEnd = _skipDartString(cleaned, pos);
          final String uri = _unquoteDartString(cleaned.substring(pos, uriEnd));

          int stmtEnd = uriEnd;
          while (stmtEnd < len && cleaned.codeUnitAt(stmtEnd) != 59) {
            final int c = cleaned.codeUnitAt(stmtEnd);
            if (c == 39 ||
                c == 34 ||
                (c == 114 &&
                    stmtEnd + 1 < len &&
                    (cleaned.codeUnitAt(stmtEnd + 1) == 39 ||
                        cleaned.codeUnitAt(stmtEnd + 1) == 34))) {
              stmtEnd = _skipDartString(cleaned, stmtEnd);
            } else {
              stmtEnd++;
            }
          }

          final String tail = cleaned.substring(uriEnd, stmtEnd);
          final showMatch = RegExp(r'\bshow\s+([\s\S]*?)(?:\bhide\b|$)')
              .firstMatch(tail);
          final showSymbols = <String>[];
          if (showMatch != null) {
            for (final part in showMatch.group(1)!.split(',')) {
              final trimmed = part.trim();
              if (trimmed.isNotEmpty) {
                showSymbols.add(trimmed);
              }
            }
          }

          final int rawEnd = stmtEnd < len ? stmtEnd + 1 : stmtEnd;
          directives.add(
            _DartDirective(
              kind: kind,
              uri: uri,
              showSymbols: showSymbols,
              raw: cleaned.substring(i, rawEnd).trim(),
            ),
          );
          i = rawEnd;
          continue;
        }
      }
    }

    i++;
  }
  return directives;
}

String _resolveLibImport(String importerRelPath, String uri) {
  if (uri.startsWith('package:qustschedule/')) {
    return 'lib/${uri.substring('package:qustschedule/'.length)}';
  }
  if (uri.contains(':')) {
    return uri;
  }
  final importerDir = Uri.file(importerRelPath).resolve('.');
  final resolved = importerDir.resolve(uri);
  return resolved.path.replaceAll('\\', '/');
}

String _fileNameOf(String posixPath) {
  final idx = posixPath.lastIndexOf('/');
  return idx == -1 ? posixPath : posixPath.substring(idx + 1);
}

List<({int bg, int fg})> _parseDartCoursePalette(String source, String field) {
  final blockMatch = RegExp(
    'static\\s+const\\s+List<CourseColor>\\s+$field\\s*=\\s*<CourseColor>\\s*\\[([\\s\\S]*?)\\];',
  ).firstMatch(source);
  expect(
    blockMatch,
    isNotNull,
    reason: 'Missing CoursePalette.$field definition',
  );
  final entries = <({int bg, int fg})>[];
  final itemPattern = RegExp(
    r'CourseColor\(\s*Color\((0x[0-9A-Fa-f]+)\)\s*,\s*Color\((0x[0-9A-Fa-f]+)\)\s*\)',
  );
  for (final m in itemPattern.allMatches(blockMatch!.group(1)!)) {
    entries.add((
      bg: int.parse(m.group(1)!.substring(2), radix: 16),
      fg: int.parse(m.group(2)!.substring(2), radix: 16),
    ));
  }
  return entries;
}

List<({int bg, int fg})> _parseKotlinCoursePalette(
  String source,
  String field,
) {
  final blockMatch = RegExp(
    'private\\s+val\\s+$field\\s*=\\s*listOf\\(([\\s\\S]*?)\\n\\s*\\)',
  ).firstMatch(source);
  expect(
    blockMatch,
    isNotNull,
    reason: 'Missing WidgetThemeResolver.$field definition',
  );
  final entries = <({int bg, int fg})>[];
  final itemPattern = RegExp(
    r'CourseChipColor\(\s*(0x[0-9A-Fa-f]+)\.toInt\(\)\s*,\s*(0x[0-9A-Fa-f]+)\.toInt\(\)\s*\)',
  );
  for (final m in itemPattern.allMatches(blockMatch!.group(1)!)) {
    entries.add((
      bg: int.parse(m.group(1)!.substring(2), radix: 16),
      fg: int.parse(m.group(2)!.substring(2), radix: 16),
    ));
  }
  return entries;
}

void main() {
  final Directory root = resolveQustscheduleRoot();
  String readRel(String relPath) => File(
    '${root.path}${Platform.pathSeparator}${relPath.replaceAll('/', Platform.pathSeparator)}',
  ).readAsStringSync();

  group('0. Guard parser self-check', () {
    test('ignores comments, nested block comments & multiline strings', () {
      const sample = '''
// import 'package:flutter/material.dart';
/*
  import 'dart:ui';
  /* export 'src/http_client.dart'; */
*/
import 'dart:async';
import '../pages/home_shell.dart'
    show
        HomeShell;

const fakeCode = \'\'\'
import 'dart:io';
export 'src/respond.dart';
final x = MethodChannel('fake');
\'\'\';

const rawFake = r"import 'package:flutter/widgets.dart'; UpdateService();";
''';
      final directives = _extractDartDirectives(sample);
      expect(directives.length, equals(2));
      expect(directives[0].kind, equals('import'));
      expect(directives[0].uri, equals('dart:async'));
      expect(directives[1].uri, equals('../pages/home_shell.dart'));
      expect(directives[1].showSymbols, equals(<String>['HomeShell']));

      final stripped = stripDartCommentsAndStrings(sample);
      expect(stripped.contains('MethodChannel'), isFalse);
      expect(stripped.contains('UpdateService'), isFalse);
    });
  });

  group('1. zf_academic isolation & barrel encapsulation', () {
    test('packages/zf_academic/lib has no Flutter/app/unexpected dart:io', () {
      final zfLibDir = Directory('${root.path}/packages/zf_academic/lib');
      final dartFiles = _listFiles(
        zfLibDir,
        extension: '.dart',
        root: zfLibDir,
      );
      expect(dartFiles, isNotEmpty);

      const allowedIoFiles = <String>{
        'src/cookie_storage.dart',
        'src/dart_io_transport.dart',
        'zf_academic_io.dart',
      };

      final violations = <String>[];
      for (final file in dartFiles) {
        final rel = _toPosixRelative(zfLibDir, file);
        final directives = _extractDartDirectives(file.readAsStringSync());
        for (final d in directives) {
          if (d.uri.startsWith('package:flutter/') ||
              d.uri == 'dart:ui' ||
              d.uri.startsWith('package:qustschedule/')) {
            violations.add('$rel imports forbidden ${d.uri}');
          }
          if ((d.uri == 'dart:io' || d.uri == 'dart:isolate') &&
              !allowedIoFiles.contains(rel)) {
            violations.add('$rel imports ${d.uri} outside IO boundary');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
      'zf_academic.dart exports only allowed 8 barrels & public symbols',
      () {
        final barrelSource = readRel(
          'packages/zf_academic/lib/zf_academic.dart',
        );
        final directives = _extractDartDirectives(barrelSource);
        final exports = directives
            .where((d) => d.kind == 'export')
            .toList(growable: false);

        const allowedBarrels = <String>{
          'src/cookies.dart',
          'src/credential_store.dart',
          'src/crypto.dart',
          'src/errors.dart',
          'src/schedule.dart',
          'src/types.dart',
          'src/urls.dart',
          'src/zhengfang_client.dart',
        };

        const forbiddenSymbols = <String>{
          'Page',
          'AcademicSystemId',
          'allTags',
          'innerOf',
          'stripTags',
          'hasClass',
          'isLoginPage',
          'loginForm',
          'detectCaptcha',
          'identity',
          'selectOptions',
          'encodeForm',
          'listRows',
          'inspectResponse',
          'requireQueryPage',
          'str',
          'number',
          'field',
          'firstOf',
          'rowKey',
          'bytesToHex',
          'rsaEncryptPkcs1',
          'AcademicHttpClient',
          'parseSetCookie',
        };

        expect(exports.map((e) => e.uri).toSet(), equals(allowedBarrels));
        for (final e in exports) {
          expect(
            e.showSymbols,
            isNotEmpty,
            reason: 'Export ${e.uri} must use explicit show list',
          );
          for (final sym in e.showSymbols) {
            expect(
              forbiddenSymbols.contains(sym),
              isFalse,
              reason: 'zf_academic.dart must not export internal symbol $sym',
            );
          }
        }
      },
    );
  });

  group('2. Import DAG & pure-Dart planner boundaries', () {
    test('lib/src/** and pure-Dart planner boundaries hold', () {
      final srcDir = Directory('${root.path}/lib/src');
      final srcFiles = _listFiles(srcDir, extension: '.dart', root: root);
      expect(srcFiles, isNotEmpty);

      const pureDartSrcFiles = <String>{
        'lib/src/course_text.dart',
        'lib/src/formatted_text.dart',
        'lib/src/reminder_planner.dart',
        'lib/src/reschedule.dart',
        'lib/src/school.dart',
        'lib/src/stable_hash.dart',
        'lib/src/term_calendar.dart',
        'lib/src/term_selector_helper.dart',
        'lib/src/timetable.dart',
        'lib/src/updater/update_models.dart',
        'lib/src/updater/version_comparator.dart',
        'lib/src/widget_planner.dart',
        'lib/src/widget_style.dart',
      };

      const forbiddenInPureDart = <String>{
        'app_model.dart',
        'route_settled.dart',
        'app_version.dart',
        'safe_json_file.dart',
      };

      final violations = <String>[];
      for (final file in srcFiles) {
        final rel = _toPosixRelative(root, file);
        final directives = _extractDartDirectives(file.readAsStringSync());
        for (final d in directives) {
          if (d.kind != 'import') continue;
          final resolved = _resolveLibImport(rel, d.uri);
          if (resolved.startsWith('lib/theme/') ||
              resolved.startsWith('lib/widgets/') ||
              resolved.startsWith('lib/pages/') ||
              resolved == 'dart:ui' ||
              resolved == 'package:flutter/material.dart' ||
              resolved == 'package:flutter/cupertino.dart') {
            violations.add('$rel imports forbidden $resolved');
          }

          if (pureDartSrcFiles.contains(rel) ||
              rel == 'lib/src/academic_service.dart') {
            if (resolved.startsWith('package:flutter/') ||
                resolved == 'dart:ui') {
              violations.add('$rel must not import $resolved');
            }
          }

          if (pureDartSrcFiles.contains(rel)) {
            final baseName = _fileNameOf(resolved);
            if (resolved == 'dart:io' ||
                resolved == 'dart:isolate' ||
                resolved == 'package:zf_academic/zf_academic_io.dart' ||
                resolved.startsWith('lib/src/state/') ||
                forbiddenInPureDart.contains(baseName) ||
                baseName.endsWith('_service.dart') ||
                baseName.endsWith('_cache.dart') ||
                baseName.endsWith('_repository.dart') ||
                baseName.endsWith('_gateway.dart')) {
              violations.add(
                '$rel (pure-Dart) must not import $resolved ($baseName)',
              );
            }
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('lib/theme/** stays decoupled from widgets/pages/services/IO', () {
      final themeFiles = _listFiles(
        Directory('${root.path}/lib/theme'),
        extension: '.dart',
        root: root,
      );
      expect(themeFiles, isNotEmpty);

      final violations = <String>[];
      for (final file in themeFiles) {
        final rel = _toPosixRelative(root, file);
        for (final d in _extractDartDirectives(file.readAsStringSync())) {
          if (d.kind != 'import') continue;
          final resolved = _resolveLibImport(rel, d.uri);
          final baseName = _fileNameOf(resolved);
          if (resolved.startsWith('lib/widgets/') ||
              resolved.startsWith('lib/pages/') ||
              resolved == 'dart:io' ||
              baseName.endsWith('_service.dart') ||
              baseName.endsWith('_repository.dart') ||
              baseName.endsWith('_cache.dart')) {
            violations.add('$rel imports forbidden $resolved');
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('lib/widgets/** stays decoupled from pages/repos/services/IO', () {
      final widgetFiles = _listFiles(
        Directory('${root.path}/lib/widgets'),
        extension: '.dart',
        root: root,
      );
      expect(widgetFiles, isNotEmpty);

      const exactForbidden = <String>{
        'update_service.dart',
        'update_flow_controller.dart',
        'app_installer.dart',
        'updater_gateway.dart',
        'schedule_service.dart',
        'academic_service.dart',
      };

      final violations = <String>[];
      for (final file in widgetFiles) {
        final rel = _toPosixRelative(root, file);
        final raw = file.readAsStringSync();
        for (final d in _extractDartDirectives(raw)) {
          if (d.kind != 'import') continue;
          final resolved = _resolveLibImport(rel, d.uri);
          final baseName = _fileNameOf(resolved);
          if (resolved.startsWith('lib/pages/') ||
              resolved == 'dart:io' ||
              resolved == 'package:zf_academic/zf_academic_io.dart' ||
              baseName.endsWith('_repository.dart') ||
              baseName.endsWith('_cache.dart') ||
              baseName.endsWith('_gateway.dart') ||
              exactForbidden.contains(baseName)) {
            violations.add('$rel imports forbidden $resolved');
          }
        }
        final stripped = stripDartCommentsAndStrings(raw);
        if (RegExp(r'\bMethodChannel\b').hasMatch(stripped)) {
          violations.add('$rel references MethodChannel');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('lib/pages/** boundaries, acyclic sibling DAG & leaf isolation', () {
      final pageFiles = _listFiles(
        Directory('${root.path}/lib/pages'),
        extension: '.dart',
        root: root,
      );
      expect(pageFiles, isNotEmpty);

      const forbiddenReposAndServices = <String>{
        'credentials_repository.dart',
        'session_repository.dart',
        'schedule_service.dart',
        'update_service.dart',
        'app_installer.dart',
        'updater_gateway.dart',
      };
      const tabPages = <String>{
        'lib/pages/schedule_page.dart',
        'lib/pages/academic_page.dart',
        'lib/pages/settings_page.dart',
      };
      const leafPages = <String>{
        'lib/pages/academic_page.dart',
        'lib/pages/appearance_sheet.dart',
        'lib/pages/captcha_page.dart',
        'lib/pages/changelog_page.dart',
        'lib/pages/debug_page.dart',
        'lib/pages/login_page.dart',
        'lib/pages/reminder_page.dart',
        'lib/pages/reschedule_page.dart',
        'lib/pages/school_address_page.dart',
        'lib/pages/timetable_edit_page.dart',
        'lib/pages/update_dialog.dart',
        'lib/pages/update_proxy_page.dart',
        'lib/pages/widget_settings_page.dart',
      };

      final graph = <String, List<String>>{};
      final violations = <String>[];

      for (final file in pageFiles) {
        final rel = _toPosixRelative(root, file);
        final raw = file.readAsStringSync();
        final edges = <String>[];
        graph[rel] = edges;

        for (final d in _extractDartDirectives(raw)) {
          if (d.kind != 'import') continue;
          final resolved = _resolveLibImport(rel, d.uri);
          final baseName = _fileNameOf(resolved);
          if (resolved == 'dart:io' ||
              resolved == 'package:zf_academic/zf_academic_io.dart' ||
              baseName.endsWith('_cache.dart') ||
              forbiddenReposAndServices.contains(baseName)) {
            violations.add('$rel imports forbidden $resolved');
          }
          if (resolved.startsWith('lib/pages/')) {
            edges.add(resolved);
            if (resolved == 'lib/pages/home_shell.dart' &&
                rel != 'lib/pages/home_shell.dart') {
              violations.add('$rel must not import home_shell.dart');
            }
            if (tabPages.contains(rel) && tabPages.contains(resolved)) {
              violations.add(
                'Tab page $rel must not import tab page $resolved',
              );
            }
            if (leafPages.contains(rel)) {
              violations.add(
                'Leaf page $rel must not import sibling page $resolved',
              );
            }
          }
        }

        final stripped = stripDartCommentsAndStrings(raw);
        if (RegExp(r'\bMethodChannel\b').hasMatch(stripped)) {
          violations.add('$rel references MethodChannel');
        }
      }

      // DFS cycle check on sibling pages/ graph
      final state = <String, int>{}; // 0/null=unvisited, 1=visiting, 2=done
      void dfs(String node, List<String> stack) {
        state[node] = 1;
        stack.add(node);
        for (final next in graph[node] ?? const <String>[]) {
          final nextState = state[next] ?? 0;
          if (nextState == 1) {
            violations.add('Cycle in pages/: ${stack.join(' -> ')} -> $next');
          } else if (nextState == 0) {
            dfs(next, stack);
          }
        }
        stack.removeLast();
        state[node] = 2;
      }

      for (final node in graph.keys) {
        if ((state[node] ?? 0) == 0) {
          dfs(node, <String>[]);
        }
      }

      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test(
      'MethodChannel containment & no direct service instantiation in UI',
      () {
        const allowedMethodChannelFiles = <String>{
          'lib/src/reminder_gateway.dart',
          'lib/src/widget_gateway.dart',
          'lib/src/updater/app_installer.dart',
          'lib/src/updater/updater_gateway.dart',
        };

        final libFiles = _listFiles(
          Directory('${root.path}/lib'),
          extension: '.dart',
          root: root,
        );
        final forbiddenUiInstantiation = RegExp(
          r'\b(?:MethodChannel|UpdateService|ScheduleService|AcademicService|ReminderService|DesktopWidgetService|MethodChannelReminderGateway|MethodChannelDesktopWidgetGateway|MethodChannelUpdaterGateway)\s*\(|\bMethodChannelDesktopWidgetGateway\.livePinnedCounts\b',
        );

        final violations = <String>[];
        for (final file in libFiles) {
          final rel = _toPosixRelative(root, file);
          final stripped = stripDartCommentsAndStrings(file.readAsStringSync());
          if (RegExp(r'\bMethodChannel\b').hasMatch(stripped) &&
              !allowedMethodChannelFiles.contains(rel)) {
            violations.add('$rel touches MethodChannel outside gateway layer');
          }
          if (rel.startsWith('lib/pages/') || rel.startsWith('lib/widgets/')) {
            final m = forbiddenUiInstantiation.firstMatch(stripped);
            if (m != null) {
              violations.add(
                '$rel directly instantiates/accesses ${m.group(0)}',
              );
            }
          }
        }
        expect(violations, isEmpty, reason: violations.join('\n'));
      },
    );
  });

  group('3. Shared test doubles consolidation', () {
    test('no implements *Gateway outside test/support/', () {
      final testFiles = _listFiles(
        Directory('${root.path}/test'),
        extension: '.dart',
        exclude: (rel) =>
            rel.startsWith('test/support/') || rel.startsWith('test/custom/'),
        root: root,
      );
      expect(testFiles, isNotEmpty);

      final pattern = RegExp(
        r'\bimplements\s+(?:[A-Za-z_]\w*\s*,\s*)*(DesktopWidgetGateway|ReminderGateway|UpdaterGateway)\b',
      );
      final violations = <String>[];
      for (final file in testFiles) {
        final rel = _toPosixRelative(root, file);
        final stripped = stripDartCommentsAndStrings(file.readAsStringSync());
        final match = pattern.firstMatch(stripped);
        if (match != null) {
          violations.add(
            '$rel directly implements ${match.group(1)} (extend Fake*Gateway in test/support/)',
          );
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('4. Cross-platform Kotlin contract parity', () {
    test('CoursePalette matches WidgetThemeResolver.kt (9 pairs)', () {
      final stableHash = readRel('lib/src/stable_hash.dart');
      final countMatch = RegExp(
        r'const\s+int\s+coursePaletteColorCount\s*=\s*(\d+)\s*;',
      ).firstMatch(stableHash);
      expect(countMatch, isNotNull);
      final expectedCount = int.parse(countMatch!.group(1)!);
      expect(expectedCount, equals(9));

      final dartSource = readRel('lib/theme/course_palette.dart');
      final ktSource = readRel(
        'android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetThemeResolver.kt',
      );

      final dartLight = _parseDartCoursePalette(dartSource, 'colors');
      final dartDark = _parseDartCoursePalette(dartSource, 'darkColors');
      final ktLight = _parseKotlinCoursePalette(
        ktSource,
        'LIGHT_COURSE_COLORS',
      );
      final ktDark = _parseKotlinCoursePalette(ktSource, 'DARK_COURSE_COLORS');

      expect(dartLight.length, equals(expectedCount));
      expect(dartDark.length, equals(expectedCount));
      expect(ktLight, equals(dartLight));
      expect(ktDark, equals(dartDark));
    });

    test('DesktopWidgetStyle kinds, themes, presets & bounds match Kotlin', () {
      final dartStyle = readRel('lib/src/widget_style.dart');
      final widgetStoreKt = readRel(
        'android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetStore.kt',
      );
      final themeResolverKt = readRel(
        'android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetThemeResolver.kt',
      );

      for (final kind in const <String>['today', 'week', 'next']) {
        expect(dartStyle, contains("'$kind'"));
        expect(widgetStoreKt, contains('"$kind"'));
      }
      for (final mode in const <String>['light', 'dark', 'system', 'dynamic']) {
        expect(dartStyle, contains("'$mode'"));
        expect(themeResolverKt, contains('"$mode"'));
      }
      for (final preset in const <String>[
        'minimal_white',
        'frosted_glass',
        'dark_night',
        'pure_transparent',
        'material_you',
      ]) {
        expect(dartStyle, contains("'$preset'"));
      }

      expect(dartStyle, contains('const double widgetMinOpacity = 0.0;'));
      expect(dartStyle, contains('const double widgetMaxOpacity = 1.0;'));
      expect(dartStyle, contains('const double widgetMinCornerRadius = 8.0;'));
      expect(dartStyle, contains('const double widgetMaxCornerRadius = 28.0;'));
      expect(dartStyle, contains('const double widgetMinFontScale = 0.75;'));
      expect(dartStyle, contains('const double widgetMaxFontScale = 1.20;'));

      expect(
        widgetStoreKt,
        contains(
          'optFiniteFloat("backgroundOpacity", base.backgroundOpacity, 0f, 1f)',
        ),
      );
      expect(
        widgetStoreKt,
        contains('optFiniteFloat("cornerRadius", base.cornerRadius, 8f, 28f)'),
      );
      expect(
        widgetStoreKt,
        contains('optFiniteFloat("fontScale", base.fontScale, 0.75f, 1.20f)'),
      );
      expect(widgetStoreKt, contains('val preset: String = "minimal_white"'));
      expect(widgetStoreKt, contains('val themeMode: String = "light"'));
      expect(widgetStoreKt, contains('val density: String = "comfortable"'));
      expect(widgetStoreKt, contains('val finishedCourseMode: String = "dim"'));
      expect(widgetStoreKt, contains('val weekendMode: String = "auto"'));
    });

    test('MethodChannels & methods match Dart gateways and Kotlin bridges', () {
      final reminderDart = readRel('lib/src/reminder_gateway.dart');
      final reminderBridgeKt = readRel(
        'android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderBridge.kt',
      );
      final reminderSchedulerKt = readRel(
        'android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderScheduler.kt',
      );

      expect(reminderDart, contains("MethodChannel('qustschedule/reminder')"));
      expect(
        reminderBridgeKt,
        contains('const val CHANNEL = "qustschedule/reminder"'),
      );
      const reminderMethods = <String>[
        'sync',
        'cancel',
        'status',
        'requestNotificationPermission',
        'openNotificationSettings',
        'openExactAlarmSettings',
        'openBatterySettings',
        'openAutostartSettings',
        'testReminder',
        'previewReminder',
        'stopFluid',
        'toast',
      ];
      for (final m in reminderMethods) {
        expect(reminderDart, contains("'$m'"));
        expect(reminderBridgeKt, contains('"$m" ->'));
      }
      expect(reminderDart, contains("map['dirty']"));
      expect(reminderSchedulerKt, contains('"dirty" to store.isDirty()'));
      expect(
        reminderSchedulerKt,
        contains('private const val MIN_EVENT_REQUEST_CODE = 10_000'),
      );
      expect(reminderSchedulerKt, contains('0x3fffffff'));
      expect(reminderSchedulerKt, contains('0x40000000'));

      final widgetDart = readRel('lib/src/widget_gateway.dart');
      final widgetBridgeKt = readRel(
        'android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetBridge.kt',
      );
      expect(widgetDart, contains("MethodChannel('qustschedule/widget')"));
      expect(
        widgetBridgeKt,
        contains('private const val CHANNEL = "qustschedule/widget"'),
      );
      for (final m in const <String>[
        'syncSnapshot',
        'clearSnapshot',
        'requestPinWidget',
        'getPinnedCounts',
      ]) {
        expect(widgetDart, contains("'$m'"));
        expect(widgetBridgeKt, contains('"$m" ->'));
      }
      expect(widgetDart, contains("'onPinnedCountsChanged'"));
      expect(
        widgetBridgeKt,
        contains('invokeMethod("onPinnedCountsChanged", counts)'),
      );

      final updaterDart = readRel('lib/src/updater/app_installer.dart');
      final updaterBridgeKt = readRel(
        'android/app/src/main/kotlin/com/fangzi/qustschedule/updater/AppUpdaterBridge.kt',
      );
      expect(updaterDart, contains("'com.fangzi.qustschedule/updater'"));
      expect(
        updaterBridgeKt,
        contains('const val CHANNEL_NAME = "com.fangzi.qustschedule/updater"'),
      );
      for (final m in const <String>[
        'canRequestPackageInstalls',
        'openInstallSettings',
        'installApk',
      ]) {
        expect(updaterDart, contains("'$m'"));
        expect(updaterBridgeKt, contains('"$m" ->'));
      }
    });
  });

  group('5. Windows encoding & C4819 contract', () {
    test('windows/runner/**/*.{cpp,h} are pure ASCII', () {
      final runnerDir = Directory('${root.path}/windows/runner');
      final files = <File>[
        ..._listFiles(runnerDir, extension: '.cpp', root: root),
        ..._listFiles(runnerDir, extension: '.h', root: root),
      ];
      expect(files, isNotEmpty);

      final violations = <String>[];
      for (final file in files) {
        final rel = _toPosixRelative(root, file);
        final bytes = file.readAsBytesSync();
        int line = 1;
        for (int i = 0; i < bytes.length; i++) {
          final b = bytes[i];
          if (b == 10) line++;
          if (b > 0x7F) {
            violations.add(
              '$rel:$line: non-ASCII byte 0x${b.toRadixString(16)}',
            );
            break;
          }
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });

    test('setup.iss has UTF-8 BOM and decodes as UTF-8', () {
      final iss = File('${root.path}/windows/packaging/setup.iss');
      expect(iss.existsSync(), isTrue);
      final bytes = iss.readAsBytesSync();
      expect(
        bytes.length >= 3 &&
            bytes[0] == 0xEF &&
            bytes[1] == 0xBB &&
            bytes[2] == 0xBF,
        isTrue,
        reason: 'windows/packaging/setup.iss must start with UTF-8 BOM',
      );
      expect(
        () => utf8.decode(bytes.sublist(3), allowMalformed: false),
        returnsNormally,
      );
    });

    test('Runner.rc has no BOM, decodes UTF-8, and sets code_page(65001)', () {
      final rc = File('${root.path}/windows/runner/Runner.rc');
      expect(rc.existsSync(), isTrue);
      final bytes = rc.readAsBytesSync();
      final bool hasUtf8Bom =
          bytes.length >= 3 &&
          bytes[0] == 0xEF &&
          bytes[1] == 0xBB &&
          bytes[2] == 0xBF;
      final bool hasUtf16LeBom =
          bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE;
      final bool hasUtf16BeBom =
          bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF;

      expect(
        hasUtf8Bom || hasUtf16LeBom || hasUtf16BeBom,
        isFalse,
        reason: 'windows/runner/Runner.rc must not contain a BOM',
      );
      final text = utf8.decode(bytes, allowMalformed: false);
      expect(text, contains('#pragma code_page(65001)'));
    });
  });

  group('6. Bidirectional docs/dev/FILE_MAP.md sync', () {
    test('every Dart & Kotlin source/test file is indexed in FILE_MAP.md', () {
      final fileMap = readRel('docs/dev/FILE_MAP.md');

      final expectedPaths = <String>[
        ..._listFiles(
          Directory('${root.path}/lib'),
          extension: '.dart',
          root: root,
        ).map((f) => _toPosixRelative(root, f)),
        ..._listFiles(
          Directory('${root.path}/test'),
          extension: '.dart',
          exclude: (rel) => rel.startsWith('test/custom/'),
          root: root,
        ).map((f) => _toPosixRelative(root, f)),
        ..._listFiles(
          Directory('${root.path}/tool'),
          extension: '.dart',
          root: root,
        ).map((f) => _toPosixRelative(root, f)),
        ..._listFiles(
          Directory('${root.path}/packages/zf_academic/lib'),
          extension: '.dart',
          root: root,
        ).map((f) => _toPosixRelative(root, f)),
        ..._listFiles(
          Directory('${root.path}/android/app/src/main/kotlin'),
          extension: '.kt',
          root: root,
        ).map((f) => _toPosixRelative(root, f)),
      ];

      final missing = <String>[];
      for (final rel in expectedPaths) {
        if (!fileMap.contains(rel)) {
          missing.add(rel);
        }
      }
      expect(
        missing,
        isEmpty,
        reason:
            'Files missing from docs/dev/FILE_MAP.md:\n${missing.join('\n')}',
      );
    });

    test('every Markdown link & backticked repo path in FILE_MAP.md exists', () {
      final fileMapFile = File('${root.path}/docs/dev/FILE_MAP.md');
      final fileMap = fileMapFile.readAsStringSync();
      final docDir = fileMapFile.parent;

      final linkPattern = RegExp(r'\]\(([^)#\s]+)(?:#[^)]*)?\)');
      final missingLinks = <String>[];
      for (final match in linkPattern.allMatches(fileMap)) {
        final target = match.group(1)!;
        if (target.startsWith('http://') || target.startsWith('https://')) {
          continue;
        }
        final resolved = docDir.uri.resolve(target).toFilePath();
        if (!File(resolved).existsSync() && !Directory(resolved).existsSync()) {
          missingLinks.add(target);
        }
      }
      expect(
        missingLinks,
        isEmpty,
        reason:
            'Broken Markdown links in FILE_MAP.md:\n${missingLinks.join('\n')}',
      );

      final backtickPathPattern = RegExp(
        r'`((?:lib|test|tool|packages|android|windows|docs|\.github)/[^`\s]+)`',
      );
      final missingPaths = <String>[];
      for (final match in backtickPathPattern.allMatches(fileMap)) {
        final rel = match.group(1)!;
        if (rel.contains('*') || rel.contains('{') || rel.contains('...')) {
          continue;
        }
        final fsPath =
            '${root.path}${Platform.pathSeparator}${rel.replaceAll('/', Platform.pathSeparator)}';
        final exists = rel.endsWith('/')
            ? Directory(fsPath).existsSync()
            : (File(fsPath).existsSync() || Directory(fsPath).existsSync());
        if (!exists) {
          missingPaths.add(rel);
        }
      }
      expect(
        missingPaths,
        isEmpty,
        reason:
            'Broken backticked paths in FILE_MAP.md:\n${missingPaths.join('\n')}',
      );
    });
  });

  group('7. AppModel facade freeze, line endings & SDK/AGP upgrade audit', () {
    test('AppModel thin controller forwarders stay frozen (<= 134)', () {
      const kMaxAppModelForwarders = 134;
      final appModelCode = _scanDartSource(
        readRel('lib/src/app_model.dart'),
        stripStrings: true,
      );
      final forwarderPattern = RegExp(
        r'=>\s*(?:prefs|session|scheduleState|academic|hints|updateFlow)\.[A-Za-z_]',
      );
      final count = forwarderPattern.allMatches(appModelCode).length;
      expect(
        count,
        lessThanOrEqualTo(kMaxAppModelForwarders),
        reason:
            'AppModel thin controller forwarders grew to $count '
            '(frozen ceiling: $kMaxAppModelForwarders). '
            'Consume model.prefs/session/scheduleState/academic/hints/updateFlow '
            'directly instead of adding new 1:1 pass-throughs on AppModel.',
      );
    });

    test(
      'zf_academic example/secure_storage_flutter.dart stays on v11 API',
      () {
        final example = _scanDartSource(
          readRel('packages/zf_academic/example/secure_storage_flutter.dart'),
          stripStrings: false,
        );
        expect(
          example,
          isNot(contains('encryptedSharedPreferences:')),
          reason:
              'example/secure_storage_flutter.dart must not regress to '
              'removed flutter_secure_storage v9 encryptedSharedPreferences.',
        );
        for (final token in const <String>[
          'FlutterSecureStorage',
          'IOSOptions',
          'KeychainAccessibility.first_unlock',
          'implements CredentialStore',
          'credentialStoreKey(',
          'Future<Credentials?> get(',
          'Future<void> save(',
          'Future<void> remove(',
          'Future<bool> has(',
          'Future<void> clearAll(',
        ]) {
          expect(
            example,
            contains(token),
            reason:
                'example/secure_storage_flutter.dart missing v11 contract '
                'token: $token',
          );
        }
      },
    );

    test('CI FLUTTER_VERSION and android/gradle.properties flags match AGENTS.md', () {
      final workflow = readRel('.github/workflows/build-release.yml');
      final verMatch = RegExp(r"FLUTTER_VERSION:\s*'([^']+)'")
          .firstMatch(workflow);
      expect(
        verMatch,
        isNotNull,
        reason: 'FLUTTER_VERSION missing in build-release.yml',
      );
      final flutterVersion = verMatch!.group(1)!;

      final agents = readRel('AGENTS.md');
      expect(
        agents,
        contains(flutterVersion),
        reason:
            'CI FLUTTER_VERSION ($flutterVersion) changed: re-audit '
            'android/gradle.properties compat flags & '
            'packages/zf_academic/example/secure_storage_flutter.dart, '
            'then sync AGENTS.md.',
      );

      final gradleProps = readRel('android/gradle.properties');
      for (final flag in const <String>[
        'android.newDsl=false',
        'android.builtInKotlin=false',
      ]) {
        if (gradleProps.contains(flag)) {
          expect(
            agents,
            contains(flag),
            reason:
                'android/gradle.properties keeps $flag; document it in AGENTS.md.',
          );
        }
      }
    });

    test('.gitattributes enforces cross-platform LF/CRLF rules', () {
      final attrs = readRel('.gitattributes');
      for (final rule in const <String>[
        '*.dart text eol=lf',
        '*.kt text eol=lf',
        '*.yml text eol=lf',
        '*.cpp text eol=crlf',
        '*.rc text eol=crlf',
        '*.iss text eol=crlf',
      ]) {
        expect(
          attrs,
          contains(rule),
          reason: '.gitattributes missing required line-ending rule: $rule',
        );
      }
    });
  });
}
