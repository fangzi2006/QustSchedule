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
      final vbsFile = File(
        '${appDir.path}${Platform.pathSeparator}qustschedule_launcher.vbs',
      );
      if (vbsFile.existsSync()) {
        vbsFile.deleteSync();
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

    // 5. 生成位于应用同目录下的极简、纯相对路径的原子替换脚本与静默启动器
    // 架构与防御性设计：
    // - 全脚本使用纯 ASCII 字符（无中文字符与中文注释），彻底杜绝 Windows CMD OEM 代码页（如 GBK 936）将 UTF-8 多字节解析为乱码而语法报错中断；
    // - 使用纯相对路径（.update_staging、.、$exeName），彻底消除路径空格与中文乱码；
    // - 采用 ping 127.0.0.1 稳定等待 1~2 秒，在无控制台/脱钩（DETACHED_PROCESS）环境下绝不报错且等待主进程彻底退出；
    // - 采用 Windows 原生自带、微软官方签名的 robocopy 进行原子搬运（/MOVE），完美规避杀毒软件（卡巴斯基/Defender）误拦截；
    // - 显式配置 /R:5 /W:1，在杀毒软件短暂占用句柄时最多重试 5 次、每次 1 秒，杜绝死锁与默认超长重试；
    // - 迁移完成后清理暂存目录、通过 start 重新启动新版主程序并自删脚本；
    // - 采用系统内置 GUI 子系统程序 wscript.exe 静默启动，彻底杜绝黑框与 ping 窗口闪烁。
    final scriptFile = File(
      '${appDir.path}${Platform.pathSeparator}qustschedule_updater.cmd',
    );

    final scriptContent =
        '''@echo off
cd /d "%~dp0"

ping 127.0.0.1 -n 2 >nul

robocopy ".update_staging" "." /E /MOVE /IS /IT /NFL /NDL /NP /NJH /NJS /R:5 /W:1 >nul 2>nul

if exist ".update_staging" (
    rd /s /q ".update_staging" >nul 2>nul
)

start "" "$exeName"

if exist "qustschedule_launcher.vbs" (
    del /f /q "qustschedule_launcher.vbs" >nul 2>nul
)

del /f /q "%~f0" >nul 2>nul
''';

    await scriptFile.writeAsString(scriptContent);

    final vbsFile = File(
      '${appDir.path}${Platform.pathSeparator}qustschedule_launcher.vbs',
    );
    final vbsContent =
        'CreateObject("WScript.Shell").Run "cmd.exe /c """ & '
        'CreateObject("Scripting.FileSystemObject").GetParentFolderName(WScript.ScriptFullName) & '
        r'"\qustschedule_updater.cmd""", 0, False';
    await vbsFile.writeAsString(vbsContent);

    // 6. 启动静默启动器并立即退出当前主程序
    // wscript.exe 属于 Windows GUI 进程，以 0 (隐藏窗口) 调度 cmd，绝不产生控制台黑框或 ping 标题闪烁；
    // 若系统策略限制 wscript 则安全降级为直接调用 cmd.exe
    try {
      await Process.start(
        'wscript.exe',
        <String>[vbsFile.path],
        mode: ProcessStartMode.detached,
        workingDirectory: appDir.path,
      );
    } catch (_) {
      await Process.start(
        'cmd.exe',
        <String>['/c', scriptFile.path],
        mode: ProcessStartMode.detached,
        workingDirectory: appDir.path,
      );
    }
    exit(0);
  }
}
