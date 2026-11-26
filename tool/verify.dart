/// 本地与 CI 共用的统一验证入口。
///
/// 用法（在 `qustschedule/` 目录下执行）：
///   dart run tool/verify.dart --quick       # 格式 + 静态分析 + Windows 编码检查 + 架构守卫
///   dart run tool/verify.dart --lint-only   # 仅静态门禁（CI Lint 阶段复用）
///   dart run tool/verify.dart --tests-only  # 仅协议包与主工程全量测试（CI Test 阶段复用）
///   dart run tool/verify.dart --full        # 默认：静态门禁 + 全量测试
///   dart run tool/verify.dart --android     # 额外执行 Android Manifest & Kotlin 编译检查
///   dart run tool/verify.dart --probe       # 额外分析外层 ../tools/probe（目录存在时）
library;

import 'dart:convert';
import 'dart:io';

Future<void> main(List<String> args) async {
  final options = _VerifyOptions.parse(args);
  if (options.showHelp) {
    _printUsage();
    return;
  }

  final root = _findProjectRoot();
  final totalWatch = Stopwatch()..start();

  if (options.runLint) {
    await _runCommand(
      label: 'Format check (main & tool)',
      executable: 'dart',
      arguments: <String>[
        'format',
        '--output=none',
        '--set-exit-if-changed',
        'lib',
        'test',
        'tool',
      ],
      workingDirectory: root,
    );
    await _runCommand(
      label: 'Format check (packages/zf_academic)',
      executable: 'dart',
      arguments: <String>[
        'format',
        '--output=none',
        '--set-exit-if-changed',
        'lib',
        'test',
        'example',
      ],
      workingDirectory:
          '$root${Platform.pathSeparator}packages'
          '${Platform.pathSeparator}zf_academic',
    );
    await _runCommand(
      label: 'Static analysis (main & tool)',
      executable: 'flutter',
      arguments: <String>['analyze', 'lib', 'test', 'tool'],
      workingDirectory: root,
    );
    await _runCommand(
      label: 'Static analysis (packages/zf_academic)',
      executable: 'dart',
      arguments: <String>['analyze', '--fatal-infos', 'lib', 'test'],
      workingDirectory:
          '$root${Platform.pathSeparator}packages'
          '${Platform.pathSeparator}zf_academic',
    );
    _checkWindowsEncoding(root);
  }

  if (options.runGuardOnly) {
    await _runCommand(
      label: 'Architecture guard test',
      executable: 'flutter',
      arguments: <String>[
        'test',
        '--timeout',
        '30s',
        'test/architecture_guard_test.dart',
      ],
      workingDirectory: root,
    );
  }

  if (options.runTests) {
    await _runCommand(
      label: 'Protocol tests (packages/zf_academic)',
      executable: 'dart',
      arguments: <String>['test', '-j', '2', '--timeout', '30s'],
      workingDirectory:
          '$root${Platform.pathSeparator}packages'
          '${Platform.pathSeparator}zf_academic',
    );

    final coreTests = _collectTestFiles(
      Directory('$root${Platform.pathSeparator}test'),
      root: root,
      excludeCustom: true,
    );
    if (coreTests.isEmpty) {
      stderr.writeln('ERROR: 未找到任何核心测试文件');
      exit(1);
    }
    await _runCommand(
      label:
          'Core tests (unit, state machine & widget: ${coreTests.length} files)',
      executable: 'flutter',
      arguments: <String>['test', '-j', '2', '--timeout', '30s', ...coreTests],
      workingDirectory: root,
    );

    final customDir = Directory(
      '$root${Platform.pathSeparator}test${Platform.pathSeparator}custom',
    );
    if (customDir.existsSync()) {
      final customTests = _collectTestFiles(
        customDir,
        root: root,
        excludeCustom: false,
      );
      if (customTests.isNotEmpty) {
        await _runCommand(
          label: 'Custom tests (${customTests.length} files)',
          executable: 'flutter',
          arguments: <String>[
            'test',
            '-j',
            '2',
            '--timeout',
            '30s',
            ...customTests,
          ],
          workingDirectory: root,
        );
      } else {
        stdout.writeln('==> Custom tests: test/custom/ 下没有测试项，跳过');
      }
    } else {
      stdout.writeln('==> Custom tests: test/custom/ 不存在，跳过');
    }
  }

  if (options.runAndroid) {
    final gradleWrapper = Platform.isWindows
        ? '$root${Platform.pathSeparator}android'
              '${Platform.pathSeparator}gradlew.bat'
        : '$root${Platform.pathSeparator}android'
              '${Platform.pathSeparator}gradlew';
    if (!File(gradleWrapper).existsSync()) {
      stderr.writeln(
        'ERROR: 未找到 $gradleWrapper，请先执行 flutter build apk --debug --config-only',
      );
      exit(1);
    }
    await _runCommand(
      label: 'Android Manifest & Kotlin compile',
      executable: gradleWrapper,
      arguments: <String>[
        '-p',
        'android',
        ':app:processDebugManifest',
        ':app:compileDebugKotlin',
      ],
      workingDirectory: root,
    );
  }

  if (options.runProbe) {
    final probeDir = Directory(
      '$root${Platform.pathSeparator}..${Platform.pathSeparator}tools'
      '${Platform.pathSeparator}probe',
    );
    if (probeDir.existsSync()) {
      await _runCommand(
        label: 'External probe analyze (../tools/probe)',
        executable: 'dart',
        arguments: <String>['analyze'],
        workingDirectory: probeDir.absolute.path,
      );
    } else {
      stdout.writeln('==> External probe: ../tools/probe 不存在，跳过');
    }
  }

  totalWatch.stop();
  final elapsedSeconds = (totalWatch.elapsedMilliseconds / 1000)
      .toStringAsFixed(1);
  stdout.writeln('\nAll requested checks passed in ${elapsedSeconds}s.');
}

class _VerifyOptions {
  const _VerifyOptions({
    required this.showHelp,
    required this.runLint,
    required this.runGuardOnly,
    required this.runTests,
    required this.runAndroid,
    required this.runProbe,
  });

  final bool showHelp;
  final bool runLint;
  final bool runGuardOnly;
  final bool runTests;
  final bool runAndroid;
  final bool runProbe;

  static _VerifyOptions parse(List<String> args) {
    var showHelp = false;
    var quick = false;
    var lintOnly = false;
    var testsOnly = false;
    var full = false;
    var android = false;
    var probe = false;

    for (final arg in args) {
      switch (arg) {
        case '--help':
        case '-h':
          showHelp = true;
        case '--quick':
          quick = true;
        case '--lint-only':
          lintOnly = true;
        case '--tests-only':
          testsOnly = true;
        case '--full':
          full = true;
        case '--android':
          android = true;
        case '--probe':
          probe = true;
        default:
          stderr.writeln('Unknown option: $arg');
          _printUsage();
          exit(2);
      }
    }

    final modeCount =
        (quick ? 1 : 0) +
        (lintOnly ? 1 : 0) +
        (testsOnly ? 1 : 0) +
        (full ? 1 : 0);
    if (modeCount > 1) {
      stderr.writeln(
        'ERROR: --quick / --lint-only / --tests-only / --full 互斥，请仅指定一个。',
      );
      exit(2);
    }

    final hasExplicitMode = modeCount == 1;
    final defaultFull = !hasExplicitMode && !android && !probe;

    return _VerifyOptions(
      showHelp: showHelp,
      runLint: defaultFull || full || quick || lintOnly,
      runGuardOnly: quick,
      runTests: defaultFull || full || testsOnly,
      runAndroid: android,
      runProbe: probe,
    );
  }
}

void _printUsage() {
  stdout.writeln('''
青科课表通统一验证脚本 (tool/verify.dart)

用法:
  dart run tool/verify.dart [模式] [附加项]

模式（互斥，默认 --full）:
  --quick       L0 静态门禁 + Windows 编码检查 + test/architecture_guard_test.dart
  --lint-only   仅 L0 静态门禁 + Windows 编码检查（CI Lint 阶段复用）
  --tests-only  仅协议包与主工程全量测试（CI Test 阶段复用）
  --full        L0 静态门禁 + Windows 编码检查 + 全量测试

附加项（可与任意模式组合，也可单独使用）:
  --android     运行 Android Gradle :app:processDebugManifest :app:compileDebugKotlin
  --probe       若 ../tools/probe 存在则运行 dart analyze
  -h, --help    显示本帮助
''');
}

String _findProjectRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 6; i++) {
    final pubspec = File('${dir.path}${Platform.pathSeparator}pubspec.yaml');
    final guard = File(
      '${dir.path}${Platform.pathSeparator}test'
      '${Platform.pathSeparator}architecture_guard_test.dart',
    );
    if (pubspec.existsSync() && guard.existsSync()) {
      return dir.path;
    }
    final nested = Directory(
      '${dir.path}${Platform.pathSeparator}qustschedule',
    );
    if (File('${nested.path}${Platform.pathSeparator}pubspec.yaml')
            .existsSync() &&
        File(
          '${nested.path}${Platform.pathSeparator}test'
          '${Platform.pathSeparator}architecture_guard_test.dart',
        ).existsSync()) {
      return nested.path;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  stderr.writeln('ERROR: 未能定位 qustschedule 项目根目录。');
  exit(1);
}

Future<void> _runCommand({
  required String label,
  required String executable,
  required List<String> arguments,
  required String workingDirectory,
}) async {
  stdout.writeln('\n==> $label');
  stdout.writeln('    \$ $executable ${arguments.join(' ')}');
  final watch = Stopwatch()..start();
  final process = await Process.start(
    executable,
    arguments,
    workingDirectory: workingDirectory,
    mode: ProcessStartMode.inheritStdio,
    runInShell: Platform.isWindows,
  );
  final code = await process.exitCode;
  watch.stop();
  if (code != 0) {
    stderr.writeln(
      '\nFAILED: $label (exit code $code after '
      '${(watch.elapsedMilliseconds / 1000).toStringAsFixed(1)}s)',
    );
    exit(code);
  }
}

List<String> _collectTestFiles(
  Directory dir, {
  required String root,
  required bool excludeCustom,
}) {
  final files = <String>[];
  if (!dir.existsSync()) return files;
  final rootNormalized = _toPosix(root);
  final prefix = rootNormalized.endsWith('/')
      ? rootNormalized
      : '$rootNormalized/';

  for (final entity in dir.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final posix = _toPosix(entity.absolute.path);
    if (!posix.endsWith('_test.dart')) continue;
    final rel = posix.startsWith(prefix)
        ? posix.substring(prefix.length)
        : posix;
    if (excludeCustom && rel.startsWith('test/custom/')) continue;
    files.add(rel);
  }
  files.sort();
  return files;
}

String _toPosix(String path) => path.replaceAll('\\', '/');

void _checkWindowsEncoding(String root) {
  stdout.writeln('\n==> Windows encoding & C4819 guard');
  final errors = <String>[];

  final runnerDir = Directory(
    '$root${Platform.pathSeparator}windows${Platform.pathSeparator}runner',
  );
  if (runnerDir.existsSync()) {
    final cppFiles =
        runnerDir
            .listSync(recursive: true, followLinks: false)
            .whereType<File>()
            .where((f) {
              final lower = f.path.toLowerCase();
              return lower.endsWith('.cpp') || lower.endsWith('.h');
            })
            .toList()
          ..sort((a, b) => a.path.compareTo(b.path));
    for (final file in cppFiles) {
      final bytes = file.readAsBytesSync();
      for (var i = 0; i < bytes.length; i++) {
        if (bytes[i] > 0x7f) {
          var line = 1;
          for (var j = 0; j < i; j++) {
            if (bytes[j] == 0x0a) line++;
          }
          final rel = _relativePosix(root, file.path);
          final hex = bytes[i].toRadixString(16).padLeft(2, '0');
          errors.add('$rel:$line: non-ASCII byte 0x$hex (C4819 risk)');
          break;
        }
      }
    }
  }

  final issFile = File(
    '$root${Platform.pathSeparator}windows'
    '${Platform.pathSeparator}packaging${Platform.pathSeparator}setup.iss',
  );
  if (!issFile.existsSync()) {
    errors.add('windows/packaging/setup.iss: file not found');
  } else {
    final bytes = issFile.readAsBytesSync();
    final hasUtf8Bom =
        bytes.length >= 3 &&
        bytes[0] == 0xef &&
        bytes[1] == 0xbb &&
        bytes[2] == 0xbf;
    if (!hasUtf8Bom) {
      errors.add('windows/packaging/setup.iss: missing UTF-8 BOM (EF BB BF)');
    } else {
      try {
        utf8.decode(bytes.sublist(3));
      } on FormatException catch (e) {
        errors.add('windows/packaging/setup.iss: invalid UTF-8: $e');
      }
    }
  }

  final rcFile = File(
    '$root${Platform.pathSeparator}windows'
    '${Platform.pathSeparator}runner${Platform.pathSeparator}Runner.rc',
  );
  if (!rcFile.existsSync()) {
    errors.add('windows/runner/Runner.rc: file not found');
  } else {
    final bytes = rcFile.readAsBytesSync();
    final hasBom =
        (bytes.length >= 2 &&
            ((bytes[0] == 0xff && bytes[1] == 0xfe) ||
                (bytes[0] == 0xfe && bytes[1] == 0xff))) ||
        (bytes.length >= 3 &&
            bytes[0] == 0xef &&
            bytes[1] == 0xbb &&
            bytes[2] == 0xbf);
    if (hasBom) {
      errors.add(
        'windows/runner/Runner.rc: unexpected BOM '
        '(expected UTF-8 without BOM + #pragma code_page(65001))',
      );
    } else {
      try {
        final text = utf8.decode(bytes);
        if (!text.contains('#pragma code_page(65001)')) {
          errors.add(
            'windows/runner/Runner.rc: missing #pragma code_page(65001)',
          );
        }
      } on FormatException catch (e) {
        errors.add('windows/runner/Runner.rc: invalid UTF-8: $e');
      }
    }
  }

  if (errors.isNotEmpty) {
    for (final error in errors) {
      stderr.writeln('ERROR: $error');
    }
    exit(1);
  }
  stdout.writeln('    Windows encoding checks passed!');
}

String _relativePosix(String root, String fullPath) {
  final rootPosix = _toPosix(root);
  final pathPosix = _toPosix(fullPath);
  final prefix = rootPosix.endsWith('/') ? rootPosix : '$rootPosix/';
  return pathPosix.startsWith(prefix)
      ? pathPosix.substring(prefix.length)
      : pathPosix;
}
