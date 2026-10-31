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
      final isZip = file.path.toLowerCase().endsWith('.zip');
      if (isZip) {
        await _installWindowsPortable(file);
      } else {
        await _installWindowsSetup(file);
      }
      return;
    }

    throw UnsupportedError('当前平台暂不支持应用内安装更新');
  }

  /// 清理遗留在应用目录下的更新辅助脚本（若此前自删未完成）。
  static void cleanLegacyUpdaterScript() {
    if (!Platform.isWindows) return;
    try {
      final exeFile = File(Platform.resolvedExecutable);
      final scriptFile = File(
        '${exeFile.parent.path}${Platform.pathSeparator}qustschedule_updater.cmd',
      );
      if (scriptFile.existsSync()) {
        scriptFile.deleteSync();
      }
    } catch (_) {}
  }

  static Future<void> _installWindowsSetup(File file) async {
    // 启动外部安装进程（脱离父进程），随后退出当前 App
    await Process.start(
      file.path,
      const <String>[],
      mode: ProcessStartMode.detached,
    );
    exit(0);
  }

  static Future<void> _installWindowsPortable(File zipFile) async {
    final exeFile = File(Platform.resolvedExecutable);
    final appDir = exeFile.parent;

    // 1. 检查当前便携版所在目录是否具备写入权限
    final testFile = File(
      '${appDir.path}${Platform.pathSeparator}.write_test_${DateTime.now().millisecondsSinceEpoch}.tmp',
    );
    try {
      testFile.writeAsStringSync('test');
      testFile.deleteSync();
    } catch (_) {
      throw FileSystemException(
        '当前便携版目录受系统保护，无写入权限（例如位于 Program Files 目录）。无法自动热更新，请手动解压更新包',
        appDir.path,
      );
    }

    // 2. 生成位于应用同目录下的透明更新脚本
    // 规避杀毒软件（卡巴斯基/Defender 等）拦截的针对性设计：
    // - 不在 %TEMP% 跨目录操作，脚本直接置于当前应用目录内，属于应用本地合法自维护组件；
    // - 赋予清晰的控制台窗口标题与阶段提示，拒绝隐藏窗口与无提示静默执行；
    // - 不使用敏感的 taskkill 强杀进程，由主进程主动 exit(0) 释放文件句柄；
    // - 解压调用 Windows 10/11 系统自带、微软官方签名的原生 tar.exe，绝不携带未知解压程序；
    // - 覆盖完毕后重新拉起主程序，并自删临时脚本与下载包。
    final scriptFile = File(
      '${appDir.path}${Platform.pathSeparator}qustschedule_updater.cmd',
    );
    final scriptContent = '''
@echo off
chcp 65001 >nul
title 青科课表通 - 正在完成更新
echo ====================================================
echo 正在完成青科课表通更新，请稍候...
echo ====================================================

timeout /t 2 /nobreak >nul

echo 正在解压新版本文件...
tar.exe -xf "%~1" -C "%~2"
if errorlevel 1 (
    echo.
    echo [错误] 解压新版本失败，请检查文件是否被其他软件占用。
    echo 压缩包位于: %~1
    pause
    exit /b 1
)

del /f /q "%~1" >nul 2>nul
echo 更新成功！正在重新启动青科课表通...

start "" "%~3"
del /f /q "%~f0" >nul 2>nul
''';

    await scriptFile.writeAsString(scriptContent);

    // 3. 启动更新脚本并退出当前主程序
    await Process.start('cmd.exe', <String>[
      '/c',
      scriptFile.path,
      zipFile.path,
      appDir.path,
      exeFile.path,
    ], mode: ProcessStartMode.detached);
    exit(0);
  }
}
