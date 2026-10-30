/// 软件更新对话框与下载进度管理。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/updater/app_installer.dart';
import '../src/updater/update_models.dart';
import '../src/updater/update_service.dart';

/// 弹出发现新版本提示框。
Future<void> showUpdateDialog(
  BuildContext context, {
  required UpdateCheckResult updateResult,
  required String proxyPrefix,
  List<String> backupProxies = const <String>[],
  VoidCallback? onIgnore,
}) async {
  final release = updateResult.release;
  final asset = updateResult.targetAsset;
  if (release == null) return;

  if (asset == null) {
    // 发现新版本但未匹配到当前架构安装包时给出友好提示
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('发现新版本 v${release.version}'),
        content: Text(
          '检测到新版本，但当前平台与架构 (${updateResult.currentArchName.isNotEmpty ? updateResult.currentArchName : '当前环境'}) 暂未匹配到直接升级安装包。\n\n您可以前往 GitHub Releases 页面查看与下载。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('知道了'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              if (release.htmlUrl.isNotEmpty) {
                launchUrl(
                  Uri.parse(release.htmlUrl),
                  mode: LaunchMode.externalApplication,
                );
              }
            },
            child: const Text('前往 Release 页面'),
          ),
        ],
      ),
    );
    return;
  }

  final finalDownloadUrl = UpdateService.buildProxiedUrl(
    asset.downloadUrl,
    proxyPrefix,
  );

  await showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) {
      final theme = Theme.of(dialogContext);
      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
        actionsPadding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        title: Row(
          children: [
            Icon(Icons.system_update_rounded, color: theme.colorScheme.primary),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                '发现新版本 v${release.version}',
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        content: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${release.formattedDate.isNotEmpty ? '发布于 ${release.formattedDate} · ' : ''}${asset.formattedSize} · ${updateResult.currentArchName}',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest.withValues(
                      alpha: 0.5,
                    ),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
                    ),
                  ),
                  child: SingleChildScrollView(
                    child: SelectableText(
                      release.body.trim().isEmpty
                          ? '暂无详细更新说明。'
                          : release.body.trim(),
                      style: const TextStyle(fontSize: 13, height: 1.45),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          if (onIgnore != null)
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                onIgnore();
              },
              child: const Text('忽略此版'),
            ),
          OutlinedButton(
            onPressed: () async {
              final uri = Uri.parse(finalDownloadUrl);
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri, mode: LaunchMode.externalApplication);
              }
            },
            child: const Text('浏览器下载'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              showDownloadProgressDialog(
                context,
                asset: asset,
                selectedProxy: proxyPrefix,
                backupProxies: backupProxies,
              );
            },
            child: const Text('立即更新'),
          ),
        ],
      );
    },
  );
}

/// 弹出下载进度弹窗并执行自动安装。
Future<void> showDownloadProgressDialog(
  BuildContext context, {
  required ReleaseAsset asset,
  required String selectedProxy,
  List<String> backupProxies = const <String>[],
  UpdateService? updateService,
}) async {
  final service = updateService ?? UpdateService();
  final cancelToken = CancelToken();

  String? errorMessage;
  String? currentProxy = selectedProxy;
  bool isCompleted = false;

  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      DownloadProgress? currentProgress;

      return StatefulBuilder(
        builder: (context, setState) {
          // 仅在首次构建时启动下载
          void startDownloadOnce() {
            service
                .downloadAssetWithFallback(
                  asset: asset,
                  selectedProxy: selectedProxy,
                  backupProxies: backupProxies,
                  cancelToken: cancelToken,
                  onProxySwitched: (proxy) {
                    if (dialogContext.mounted) {
                      setState(() {
                        currentProxy = proxy;
                      });
                    }
                  },
                  onProgress: (progress) {
                    if (dialogContext.mounted) {
                      setState(() {
                        currentProgress = progress;
                      });
                    }
                  },
                )
                .then((file) async {
                  isCompleted = true;
                  if (dialogContext.mounted) {
                    Navigator.of(dialogContext).pop();
                    await _executeInstall(context, file);
                  }
                })
                .catchError((Object err) {
                  if (cancelToken.isCancelled) return;
                  if (dialogContext.mounted) {
                    setState(() {
                      errorMessage = '下载失败: $err';
                    });
                  }
                });
          }

          if (currentProgress == null && errorMessage == null && !isCompleted) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              startDownloadOnce();
            });
          }

          final theme = Theme.of(context);
          final progressVal = currentProgress?.progress ?? 0.0;
          final percent = currentProgress?.percentage ?? 0;

          return AlertDialog(
            title: Text(errorMessage != null ? '下载出错' : '正在下载更新'),
            content: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    asset.name,
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (currentProxy != null &&
                      currentProxy!.trim() != selectedProxy.trim()) ...[
                    const SizedBox(height: 4),
                    Text(
                      '已自动回退至: ${displayProxyName(currentProxy!)}',
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  if (errorMessage != null)
                    Text(
                      errorMessage!,
                      style: TextStyle(
                        color: theme.colorScheme.error,
                        fontSize: 13,
                      ),
                    )
                  else ...[
                    LinearProgressIndicator(
                      value: currentProgress == null ? null : progressVal,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          currentProgress == null ? '准备中…' : '$percent%',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          currentProgress == null
                              ? ''
                              : '${currentProgress!.formattedReceived} / ${currentProgress!.formattedTotal} (${currentProgress!.formattedSpeed})',
                          style: TextStyle(
                            fontSize: 12,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () {
                  cancelToken.cancel();
                  Navigator.of(dialogContext).pop();
                },
                child: Text(errorMessage != null ? '关闭' : '取消'),
              ),
              if (errorMessage != null)
                FilledButton(
                  onPressed: () {
                    final finalUrl = UpdateService.buildProxiedUrl(
                      asset.downloadUrl,
                      currentProxy ?? selectedProxy,
                    );
                    launchUrl(
                      Uri.parse(finalUrl),
                      mode: LaunchMode.externalApplication,
                    );
                    Navigator.of(dialogContext).pop();
                  },
                  child: const Text('改用浏览器下载'),
                ),
            ],
          );
        },
      );
    },
  );
}

/// 执行安装并引导异常提示。
Future<void> _executeInstall(BuildContext context, File file) async {
  try {
    if (Platform.isAndroid) {
      final canInstall = await AppInstaller.canRequestPackageInstalls();
      if (!canInstall && context.mounted) {
        final grant = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('安装权限未开启'),
            content: const Text('青科课表通需要「安装未知应用」权限才能覆盖升级安装包，是否前往系统设置开启？'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: const Text('去设置'),
              ),
            ],
          ),
        );
        if (grant == true) {
          await AppInstaller.openInstallSettings();
        }
      }
    }

    await AppInstaller.install(file);
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('唤起安装失败 ($e)，安装包已保存在: ${file.path}'),
          action: SnackBarAction(label: '确定', onPressed: () {}),
        ),
      );
    }
  }
}
