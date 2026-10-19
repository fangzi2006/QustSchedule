/// 应用版本号：**唯一来源是 `pubspec.yaml` 的 `version:` 字段**。
///
/// 不硬编码：`pubspec.yaml` 被声明为 asset 一起打进包里，运行时读出来解析 `version:`。
/// 这样"界面显示的版本"和"构建配置的版本"永远一致——发版只改 pubspec 一处，
/// 不会出现"设置页还写着 1.1.0、装上去其实是 1.1.1"这种对不上的情况。
library;

import 'package:flutter/services.dart' show rootBundle;

String _version = '';
String _full = '';
bool _loaded = false;

/// 显示用的版本号，形如 `1.1.1`（不含 `+build` 号）。
///
/// 还没加载或读不到时为 `-`——版本号读不到不该让界面崩。
String get appVersion => _version.isEmpty ? '-' : _version;

/// 完整版本号，形如 `1.1.1+4`（含 build number，排查升级问题时有用）。
String get appVersionFull => _full.isEmpty ? appVersion : _full;

/// 从打包进去的 `pubspec.yaml` 读一次版本号（[main] 启动时调用）。
Future<void> loadAppVersion() async {
  if (_loaded) return;
  _loaded = true;
  try {
    final text = await rootBundle.loadString('pubspec.yaml');
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(text);
    final value = match?.group(1)?.trim() ?? '';
    if (value.isEmpty) return;
    _full = value;
    _version = value.split('+').first;
  } catch (_) {
    // 忽略：读不到就显示 `-`，不能因为版本号让 app 起不来。
  }
}
