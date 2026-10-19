/// 版本号必须来自构建配置，不能是另一份硬编码。
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/app_version.dart';

/// 直接读项目根的 `pubspec.yaml`，取出构建真正用的版本号。
String pubspecVersion() {
  final text = File('pubspec.yaml').readAsStringSync();
  final match = RegExp(r'^version:\s*(\S+)', multiLine: true).firstMatch(text);
  return match?.group(1) ?? '';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('界面显示的版本号 = pubspec.yaml 里的 version', () async {
    final expected = pubspecVersion();
    expect(expected, isNotEmpty, reason: 'pubspec.yaml 里应该有 version 字段');

    await loadAppVersion();

    expect(appVersionFull, expected, reason: '完整版本号（含 build）必须与构建配置一致');
    expect(
      appVersion,
      expected.split('+').first,
      reason: '显示用的版本号是不带 +build 的那一段',
    );
    expect(appVersion, isNot('-'), reason: 'app 内应该能读到版本号');
  });
}
