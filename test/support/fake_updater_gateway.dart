/// 测试用更新安装器与外部链接假通道。
library;

import 'dart:io';

import 'package:qustschedule/src/updater/updater_gateway.dart';

class FakeUpdaterGateway implements UpdaterGateway {
  FakeUpdaterGateway({
    this.canInstall = true,
    this.canInstallError,
    this.installError,
    this.launchUrlResult = true,
  });

  bool canInstall;
  Object? canInstallError;
  Object? installError;
  bool launchUrlResult;

  int canInstallCheckCount = 0;
  int openInstallSettingsCount = 0;
  final List<File> installedFiles = <File>[];
  final List<Uri> launchedUrls = <Uri>[];

  @override
  Future<bool> canRequestPackageInstalls() async {
    canInstallCheckCount++;
    final error = canInstallError;
    if (error != null) throw error;
    return canInstall;
  }

  @override
  Future<void> openInstallSettings() async {
    openInstallSettingsCount++;
  }

  @override
  Future<void> install(File file) async {
    final error = installError;
    if (error != null) throw error;
    installedFiles.add(file);
  }

  @override
  Future<bool> launchExternalUrl(Uri uri) async {
    launchedUrls.add(uri);
    return launchUrlResult;
  }
}
