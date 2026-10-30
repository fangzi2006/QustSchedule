/// 应用安装器（适配 Android 与 Windows）。
library;

import 'dart:io';

import 'package:flutter/services.dart';

class AppInstaller {
  AppInstaller._();

  static const _channel = MethodChannel('com.fangzi.qustschedule/updater');

  /// 检查 Android 是否已授予安装未知应用权限。Windows 返回 true。
  static Future<bool> canRequestPackageInstalls() async {
    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod<bool>(
          'canRequestPackageInstalls',
        );
        return result ?? true;
      } catch (_) {
        return true;
      }
    }
    return true;
  }

  /// 跳转至系统设置页授权安装权限（仅 Android）。
  static Future<void> openInstallSettings() async {
    if (Platform.isAndroid) {
      try {
        await _channel.invokeMethod<void>('openInstallSettings');
      } catch (_) {}
    }
  }

  /// 安装下载好的安装包。
  ///
  /// - Android：通过 FileProvider 授权并唤起系统安装器；
  /// - Windows：启动 Inno Setup 安装包程序，随后退出当前应用以便覆盖更新。
  static Future<void> install(File file) async {
    if (!file.existsSync()) {
      throw FileSystemException('安装文件不存在', file.path);
    }

    if (Platform.isAndroid) {
      await _channel.invokeMethod<void>('installApk', <String, dynamic>{
        'filePath': file.path,
      });
      return;
    }

    if (Platform.isWindows) {
      // 启动外部安装进程（脱离父进程），随后退出当前 App
      await Process.start(
        file.path,
        const <String>[],
        mode: ProcessStartMode.detached,
      );
      exit(0);
    }

    throw UnsupportedError('当前平台暂不支持应用内安装更新');
  }
}
