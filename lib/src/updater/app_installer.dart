/// 应用安装器（适配 Android 与 Windows）。
library;

import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

class AppInstaller {
  AppInstaller._();

  static const _channel = MethodChannel('com.fangzi.qustschedule/updater');

  static const String portableCmdFileName = 'qustschedule_updater.cmd';
  static const String portableVbsFileName = 'qustschedule_launcher.vbs';
  static const String setupCmdFileName = 'qustschedule_setup_updater.cmd';
  static const String setupVbsFileName = 'qustschedule_setup_launcher.vbs';

  /// Windows 安装版全自动静默升级参数（配合 `setup.iss` 的 `/AUTOSTART=1` 自动重启）。
  static const List<String> windowsSetupSilentArgs = <String>[
    '/VERYSILENT',
    '/SUPPRESSMSGBOXES',
    '/NORESTART',
    '/CLOSEAPPLICATIONS',
    '/AUTOSTART=1',
  ];

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
  /// - Windows：
  ///   - `.zip` 便携版：解压到 `.update_staging` 后等待旧进程退出再搬运替换并重启；
  ///   - `.exe` 安装版：等待旧进程退出后以静默升级模式覆盖安装并自动重启。
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

  /// 清理遗留在应用目录或临时目录下的更新辅助脚本与暂存目录（若此前自删未完成）。
  static void cleanLegacyUpdaterScript({
    Directory? appDir,
    Directory? tempDir,
  }) {
    if (!Platform.isWindows && appDir == null && tempDir == null) return;
    final effectiveAppDir =
        appDir ??
        (Platform.isWindows ? File(Platform.resolvedExecutable).parent : null);
    if (effectiveAppDir != null) {
      _deleteIfExists(
        File(
          '${effectiveAppDir.path}${Platform.pathSeparator}$portableCmdFileName',
        ),
      );
      _deleteIfExists(
        File(
          '${effectiveAppDir.path}${Platform.pathSeparator}$portableVbsFileName',
        ),
      );
      _deleteDirIfExists(
        Directory(
          '${effectiveAppDir.path}${Platform.pathSeparator}.update_staging',
        ),
      );
    }
    if (tempDir != null) {
      _deleteIfExists(
        File('${tempDir.path}${Platform.pathSeparator}$setupCmdFileName'),
      );
      _deleteIfExists(
        File('${tempDir.path}${Platform.pathSeparator}$setupVbsFileName'),
      );
    }
  }

  static void _deleteIfExists(File file) {
    try {
      if (file.existsSync()) file.deleteSync();
    } catch (_) {}
  }

  static void _deleteDirIfExists(Directory dir) {
    try {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    } catch (_) {}
  }

  /// 构造等待指定 PID 彻底退出的纯 ASCII 批处理片段（最多轮询 20 秒，避免盲等 1 秒撞锁）。
  @visibleForTesting
  static String buildWindowsPidWaitBlock(
    int processId, {
    required String doneLabel,
  }) {
    return '''set /a "_tries=0"
:_wait_exit
tasklist /FI "PID eq $processId" /FO CSV /NH 2>nul | find ",""$processId""," >nul
if errorlevel 1 goto $doneLabel
set /a "_tries+=1"
if %_tries% geq 20 goto $doneLabel
ping 127.0.0.1 -n 2 >nul
goto _wait_exit''';
  }

  /// 生成通过 `wscript.exe` 隐藏窗口调度 `.cmd` 的纯 ASCII VBS 启动器内容。
  @visibleForTesting
  static String buildHiddenVbsLauncher(String cmdFileName) {
    return 'CreateObject("WScript.Shell").Run "cmd.exe /c """ & '
        'CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & '
        '"\\$cmdFileName""", 0, False';
  }

  /// 生成 Windows 安装版静默升级并自动重启的纯 ASCII 调度脚本。
  @visibleForTesting
  static String buildWindowsSetupLauncherScript({
    required String setupFileName,
    required int processId,
  }) {
    final silentArgs = windowsSetupSilentArgs.join(' ');
    final waitBlock = buildWindowsPidWaitBlock(
      processId,
      doneLabel: '_run_setup',
    );
    return '''@echo off
cd /d "%~dp0"

$waitBlock

:_run_setup
start "" "$setupFileName" $silentArgs

if exist "$setupVbsFileName" (
    del /f /q "$setupVbsFileName" >nul 2>nul
)

del /f /q "%~f0" >nul 2>nul
''';
  }

  /// 生成 Windows 便携版替换更新并重启的纯 ASCII 调度脚本。
  @visibleForTesting
  static String buildWindowsPortableScript({
    required String exeName,
    required int processId,
  }) {
    final waitBlock = buildWindowsPidWaitBlock(
      processId,
      doneLabel: '_do_replace',
    );
    // - 全脚本纯 ASCII，避免 CMD OEM 代码页解析 UTF-8 中文出错；
    // - 通过 PID 轮询确认旧进程释放全部锁与单实例互斥量后再搬运；
    // - 只有 robocopy 退出码 < 8（成功）才清理 .update_staging，保留失败排查线索。
    return '''@echo off
cd /d "%~dp0"

$waitBlock

:_do_replace
robocopy ".update_staging" "." /E /IS /IT /NFL /NDL /NP /NJH /NJS /R:5 /W:1 >nul 2>nul
if not errorlevel 8 (
    if exist ".update_staging" (
        rd /s /q ".update_staging" >nul 2>nul
    )
)

start "" "$exeName"

if exist "$portableVbsFileName" (
    del /f /q "$portableVbsFileName" >nul 2>nul
)

del /f /q "%~f0" >nul 2>nul
''';
  }

  static Future<void> _launchDetachedScript({
    required Directory workDir,
    required String cmdFileName,
    required String vbsFileName,
    required String cmdContent,
  }) async {
    final scriptFile = File(
      '${workDir.path}${Platform.pathSeparator}$cmdFileName',
    );
    await scriptFile.writeAsString(cmdContent);

    final vbsFile = File(
      '${workDir.path}${Platform.pathSeparator}$vbsFileName',
    );
    await vbsFile.writeAsString(buildHiddenVbsLauncher(cmdFileName));

    try {
      await Process.start(
        'wscript.exe',
        <String>[vbsFile.path],
        mode: ProcessStartMode.detached,
        workingDirectory: workDir.path,
      );
    } catch (_) {
      await Process.start(
        'cmd.exe',
        <String>['/c', scriptFile.path],
        mode: ProcessStartMode.detached,
        workingDirectory: workDir.path,
      );
    }
  }

  static Future<void> _installWindowsSetup(File file) async {
    final setupDir = file.parent;
    final setupFileName = file.uri.pathSegments.last;
    final scriptContent = buildWindowsSetupLauncherScript(
      setupFileName: setupFileName,
      processId: pid,
    );
    await _launchDetachedScript(
      workDir: setupDir,
      cmdFileName: setupCmdFileName,
      vbsFileName: setupVbsFileName,
      cmdContent: scriptContent,
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
    _deleteDirIfExists(stagingDir);
    stagingDir.createSync(recursive: true);

    // 3. 在 Dart 主进程仍在运行时，将 zip 解压至隔离的 .update_staging 目录
    final extractResult = await Process.run('tar.exe', <String>[
      '-xf',
      zipFile.path,
      '-C',
      stagingDir.path,
    ]);

    if (extractResult.exitCode != 0) {
      _deleteDirIfExists(stagingDir);
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
      _deleteDirIfExists(stagingDir);
      throw FileSystemException('更新包解压完整性校验未通过，缺少主执行文件', stagedExe.path);
    }

    // 不在此处提前删除 zipFile：等待新版本成功启动后由 cleanOldUpdateFiles 自动清理，
    // 防止后续文件搬运意外失败时用户必须重新下载。

    // 5. 启动静默 PID 等待 + robocopy 搬运重启脚本并退出当前进程
    final scriptContent = buildWindowsPortableScript(
      exeName: exeName,
      processId: pid,
    );
    await _launchDetachedScript(
      workDir: appDir,
      cmdFileName: portableCmdFileName,
      vbsFileName: portableVbsFileName,
      cmdContent: scriptContent,
    );
    exit(0);
  }
}
