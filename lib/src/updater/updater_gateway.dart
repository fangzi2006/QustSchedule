/// 更新安装器与外部链接的平台通道抽象。
///
/// 隔离 `AppInstaller` 的 `MethodChannel` 与 `url_launcher` 外部浏览器调用，
/// 使 `UpdateFlowController` 可在纯测试替身下确定性覆盖 Android/Windows 分支。
library;

import 'dart:io';

import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import 'app_installer.dart';

abstract class UpdaterGateway {
  const UpdaterGateway();

  /// 检查当前设备是否允许应用内安装更新包。
  Future<bool> canRequestPackageInstalls();

  /// 打开系统「允许安装未知应用」设置页（仅 Android）。
  Future<void> openInstallSettings();

  /// 触发平台安装或覆盖重启流程。
  Future<void> install(File file);

  /// 使用外部浏览器打开链接；成功唤起返回 `true`。
  Future<bool> launchExternalUrl(Uri uri);
}

class MethodChannelUpdaterGateway implements UpdaterGateway {
  const MethodChannelUpdaterGateway([
    this.channel = AppInstaller.defaultChannel,
  ]);

  final MethodChannel channel;

  @override
  Future<bool> canRequestPackageInstalls() =>
      AppInstaller.canRequestPackageInstalls(channel: channel);

  @override
  Future<void> openInstallSettings() =>
      AppInstaller.openInstallSettings(channel: channel);

  @override
  Future<void> install(File file) =>
      AppInstaller.install(file, channel: channel);

  @override
  Future<bool> launchExternalUrl(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}
