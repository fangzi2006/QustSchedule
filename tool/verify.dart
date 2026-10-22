/// L0 基础门禁：格式校验 → 静态分析（语法 / 类型 / 编译期检查）→ 测试编译与执行。
///
/// 这些检查不属于「业务测试」，它们回答的是"这份代码还能不能编译、格式是否
/// 一致"，判定标准是**工具退出码**，而不是任何断言。单独抽出来是为了：
///   - 提交前先跑 L0（几秒到十几秒），别等 L1~L3 跑完才发现格式错了；
///   - CI / 本地 / 编辑器用同一套口径，避免"我这能过"。
///
/// 用法：
/// ```bash
/// dart run tool/verify.dart          # 全量：格式 + 分析 + 测试
/// dart run tool/verify.dart --static # 只跑 L0：格式 + 分析（不跑测试）
/// ```
///
/// 退出码：0 = 全过；1 = 有任一步失败（并打印失败的是哪一步）。
library;

import 'dart:convert';
import 'dart:io';

/// 需要跑格式与分析的目录。
const List<String> _targets = <String>['lib', 'test', 'tool'];

/// 独立组件包（有自己的 pubspec，格式/分析/测试都得在它自己的目录下跑）。
const String _packageDir = 'packages/zf_academic';

Future<void> main(List<String> args) async {
  final bool staticOnly = args.contains('--static');
  final _Runner runner = _Runner();

  await runner.step('L0-1 格式校验', <String>[
    'dart',
    'format',
    '--output=none',
    '--set-exit-if-changed',
    ..._targets,
  ]);

  await runner.step('L0-2 静态分析（语法 / 类型 / 未使用符号）', <String>[
    'flutter',
    'analyze',
    // info 不算门禁失败（warning / error 仍然致命）：风格建议不该拦住合并。
    '--no-fatal-infos',
    ..._targets,
  ]);

  await runner.step('L0-1p 格式校验（组件包 zf_academic）', <String>[
    'dart',
    'format',
    '--output=none',
    '--set-exit-if-changed',
    'lib',
    'test',
  ], workingDirectory: _packageDir);

  await runner.step('L0-2p 静态分析（组件包 zf_academic）', <String>[
    'flutter',
    'analyze',
    '--no-fatal-infos',
    'lib',
    'test',
  ], workingDirectory: _packageDir);

  if (!staticOnly) {
    await runner.step('L0-3 编译并执行全部测试（L1+L2+L3）', <String>['flutter', 'test']);

    // 组件包有自己的测试套件：不跑就等于"改了它也没人验"。
    await runner.step('L0-4 组件包测试（zf_academic）', <String>[
      'flutter',
      'test',
    ], workingDirectory: _packageDir);
  }

  if (runner.failed.isNotEmpty) {
    stderr.writeln('');
    stderr.writeln('失败步骤：${runner.failed.join('、')}');
    exit(1);
  }
  stdout.writeln('');
  stdout.writeln('全部通过${staticOnly ? '（仅 L0）' : ''}。');
}

class _Runner {
  final List<String> failed = <String>[];

  Future<void> step(
    String label,
    List<String> command, {
    String? workingDirectory,
  }) async {
    stdout.writeln('\n=== $label');
    stdout.writeln(
      '    ${workingDirectory == null ? '' : '($workingDirectory) '}'
      '${command.join(' ')}',
    );

    final Stopwatch watch = Stopwatch()..start();
    final ProcessResult result = await Process.run(
      _executable(command.first),
      command.skip(1).toList(),
      workingDirectory: workingDirectory,
      environment: _environment(),
      includeParentEnvironment: false,
      runInShell: false,
      // 子进程输出是 UTF-8；不显式指定，Windows 控制台会按本地代码页解码成乱码。
      stdoutEncoding: utf8,
      stderrEncoding: utf8,
    );
    watch.stop();

    final String out = '${result.stdout}${result.stderr}';
    if (out.trim().isNotEmpty) stdout.write(out);
    stdout.writeln(
      '    → 退出码 ${result.exitCode}（${watch.elapsed.inMilliseconds}ms）',
    );

    if (result.exitCode != 0) failed.add(label);
  }

  /// Windows 上 `dart` / `flutter` 是 `.bat`，必须经 cmd 启动。
  String _executable(String name) => Platform.isWindows ? '$name.bat' : name;

  /// 去掉指向本机的代理变量。
  ///
  /// 本机沙箱会把 `HTTP_PROXY` 指到 `127.0.0.1`，`flutter_tester` 起 websocket
  /// 时会走代理并握手失败（`Invalid WebSocket upgrade request`）。只清掉
  /// **指向本机**的那几个，外网代理（公司网络必需）保持不动。
  Map<String, String> _environment() {
    final Map<String, String> env = Map<String, String>.from(
      Platform.environment,
    );
    const List<String> proxyKeys = <String>[
      'HTTP_PROXY',
      'HTTPS_PROXY',
      'http_proxy',
      'https_proxy',
    ];
    for (final String key in proxyKeys) {
      final String? value = env[key];
      if (value == null) continue;
      final String lower = value.toLowerCase();
      if (lower.contains('127.0.0.1') || lower.contains('localhost')) {
        env.remove(key);
      }
    }
    return env;
  }
}
