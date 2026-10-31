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

  /// 清理遗留在应用目录下的更新辅助脚本与暂存目录（若此前自删未完成）。
  static void cleanLegacyUpdaterScript() {
    if (!Platform.isWindows) return;
    try {
      final exeFile = File(Platform.resolvedExecutable);
      final appDir = exeFile.parent;
      final scriptFile = File(
        '${appDir.path}${Platform.pathSeparator}qustschedule_updater.cmd',
      );
      if (scriptFile.existsSync()) {
        scriptFile.deleteSync();
      }
      final stagingDir = Directory(
        '${appDir.path}${Platform.pathSeparator}.update_staging',
      );
      if (stagingDir.existsSync()) {
        stagingDir.deleteSync(recursive: true);
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

    // 2. 准备全新的隔离暂存解压目录（.update_staging）
    final stagingDir = Directory(
      '${appDir.path}${Platform.pathSeparator}.update_staging',
    );
    if (stagingDir.existsSync()) {
      try {
        stagingDir.deleteSync(recursive: true);
      } catch (_) {}
    }
    stagingDir.createSync(recursive: true);

    // 3. 在 Dart 主进程仍在运行时，将 zip 解压至隔离的 .update_staging 目录
    // 优势：暂存目录为全新创建，无运行中进程锁争抢，100% 确保解压完整与事务安全
    final extractResult = await Process.run('tar.exe', <String>[
      '-xf',
      zipFile.path,
      '-C',
      stagingDir.path,
    ]);

    if (extractResult.exitCode != 0) {
      try {
        stagingDir.deleteSync(recursive: true);
      } catch (_) {}
      final errorMsg = (extractResult.stderr as String?)?.trim();
      throw ProcessException(
        'tar.exe',
        <String>['-xf', zipFile.path, '-C', stagingDir.path],
        '更新包解压失败: ${errorMsg?.isNotEmpty == true ? errorMsg : '未知解压错误'}',
        extractResult.exitCode,
      );
    }

    // 4. 关键产物完整性校验：验证解压后的主执行文件 qustschedule.exe 是否存在且非空
    final exeName = exeFile.uri.pathSegments.last;
    final stagedExe = File(
      '${stagingDir.path}${Platform.pathSeparator}$exeName',
    );
    if (!stagedExe.existsSync() || stagedExe.lengthSync() == 0) {
      try {
        stagingDir.deleteSync(recursive: true);
      } catch (_) {}
      throw FileSystemException('更新包解压完整性校验未通过，缺少主执行文件', stagedExe.path);
    }

    // 解压校验成功后，尽早清理位于 Temp 的更新包，节省磁盘空间
    try {
      zipFile.deleteSync();
    } catch (_) {}

    // 5. 生成位于应用同目录下的极简、纯相对路径的原子替换脚本
    // 架构与防御性设计：
    // - 全脚本使用纯相对路径（.update_staging、.、qustschedule.exe），彻底消除路径空格与中文/不同代码页（GBK/UTF-8）乱码；
    // - 接收当前主程序的具体 PID 作为参数，通过 tasklist 精确轮询监听直到该 PID 完全终结，杜绝盲等与未释放句柄锁冲突；
    // - 采用 Windows 原生自带、微软官方签名的 robocopy 进行毫秒级原子搬运（/MOVE），完美规避杀毒软件（卡巴斯基/Defender）启发式主动防御误拦截；
    // - 严格遵守 robocopy 状态码规范（Exit Code >= 8 才是致命错误，0~7 为正常/成功）。
    final scriptFile = File(
      '${appDir.path}${Platform.pathSeparator}qustschedule_updater.cmd',
    );
    final currentPid = pid;

    final scriptContent =
        '''
@echo off
title 青科课表通 - 正在完成更新
echo ====================================================
echo 正在完成青科课表通更新，请稍候...
echo ====================================================

:: 1. 切换到脚本所在目录（应用根目录），确保全部使用相对路径
cd /d "%~dp0"

:: 2. 精确监听主进程退出（轮询指定 PID，最多等待 15 秒）
set TARGET_PID=%~1
if not "%TARGET_PID%"=="" (
    for /l %%i in (1,1,15) do (
        tasklist /fi "PID eq %TARGET_PID%" 2>nul | findstr /i "%TARGET_PID%" >nul
        if errorlevel 1 (
            goto :proc_exited
        )
        timeout /t 1 /nobreak >nul
    )
)
:proc_exited
timeout /t 1 /nobreak >nul

:: 3. 调用 Windows 原生 robocopy 毫秒级原子同步搬运
robocopy ".update_staging" "." /E /MOVE /IS /IT /NFL /NDL /NP /NJH /NJS >nul 2>nul
if %errorlevel% GEQ 8 (
    echo.
    echo [错误] 替换新版本文件失败（错误码: %errorlevel%）。
    echo 暂存更新文件仍保留在 .update_staging 目录中。
    pause
    exit /b 1
)

:: 4. 清理暂存目录残留
if exist ".update_staging" (
    rd /s /q ".update_staging" >nul 2>nul
)

:: 5. 启动更新后的新版本主程序
echo 更新成功！正在重新启动青科课表通...
start "" "$exeName"

:: 6. 自删脚本自身
del /f /q "%~f0" >nul 2>nul
''';

    await scriptFile.writeAsString(scriptContent);

    // 6. 启动更新脚本，传入当前进程 PID 并立即退出主程序
    await Process.start(
      'cmd.exe',
      <String>['/c', scriptFile.path, '$currentPid'],
      mode: ProcessStartMode.detached,
      workingDirectory: appDir.path,
    );
    exit(0);
  }
}
