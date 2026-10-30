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
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => _DownloadProgressDialog(
      asset: asset,
      selectedProxy: selectedProxy,
      backupProxies: backupProxies,
      updateService: updateService,
    ),
  );
}

class _DownloadProgressDialog extends StatefulWidget {
  const _DownloadProgressDialog({
    required this.asset,
    required this.selectedProxy,
    this.backupProxies = const <String>[],
    this.updateService,
  });

  final ReleaseAsset asset;
  final String selectedProxy;
  final List<String> backupProxies;
  final UpdateService? updateService;

  @override
  State<_DownloadProgressDialog> createState() =>
      _DownloadProgressDialogState();
}

class _DownloadProgressDialogState extends State<_DownloadProgressDialog> {
  late final UpdateService _service;
  late final CancelToken _cancelToken;

  DownloadProgress? _currentProgress;
  String? _errorMessage;
  late String _currentProxy;
  bool _downloadStarted = false;

  @override
  void initState() {
    super.initState();
    _service = widget.updateService ?? UpdateService();
    _cancelToken = CancelToken();
    _currentProxy = widget.selectedProxy;
    // 仅在首次 initState 生命周期中触发下载，杜绝重建导致的多次并发下载冲突
    _startDownload();
  }

  @override
  void dispose() {
    _cancelToken.cancel();
    super.dispose();
  }

  Future<void> _startDownload() async {
    if (_downloadStarted) return;
    _downloadStarted = true;

    try {
      final file = await _service.downloadAssetWithFallback(
        asset: widget.asset,
        selectedProxy: widget.selectedProxy,
        backupProxies: widget.backupProxies,
        cancelToken: _cancelToken,
        onProxySwitched: (proxy) {
          if (!mounted) return;
          setState(() {
            _currentProxy = proxy;
          });
        },
        onProgress: (progress) {
          if (!mounted) return;
          setState(() {
            _currentProgress = progress;
          });
        },
      );

      if (!mounted) return;
      Navigator.of(context).pop();
      await _executeInstall(context, file);
    } catch (err) {
      if (_cancelToken.isCancelled) return;
      if (!mounted) return;
      setState(() {
        _errorMessage = '下载失败: $err';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progressVal = _currentProgress?.progress;
    final percent = _currentProgress?.percentage ?? 0;

    return AlertDialog(
      title: Text(_errorMessage != null ? '下载出错' : '正在下载更新'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.asset.name,
              style: TextStyle(
                fontSize: 12,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (_currentProxy.trim() != widget.selectedProxy.trim()) ...[
              const SizedBox(height: 4),
              Text(
                '已自动回退至: ${displayProxyName(_currentProxy)}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
              )
            else ...[
              LinearProgressIndicator(value: progressVal),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _currentProgress == null ? '连接中…' : '$percent%',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    _currentProgress == null
                        ? ''
                        : '${_currentProgress!.formattedReceived} / ${_currentProgress!.formattedTotal} (${_currentProgress!.formattedSpeed})',
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
            _cancelToken.cancel();
            Navigator.of(context).pop();
          },
          child: Text(_errorMessage != null ? '关闭' : '取消'),
        ),
        if (_errorMessage != null)
          FilledButton(
            onPressed: () {
              final finalUrl = UpdateService.buildProxiedUrl(
                widget.asset.downloadUrl,
                _currentProxy,
              );
              launchUrl(
                Uri.parse(finalUrl),
                mode: LaunchMode.externalApplication,
              );
              Navigator.of(context).pop();
            },
            child: const Text('改用浏览器下载'),
          ),
      ],
    );
  }
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
