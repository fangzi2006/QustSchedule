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
                    child: _ReleaseNotesView(
                      content: release.cleanBody,
                      version: release.version,
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
            onPressed: () async {
              if (Platform.isAndroid) {
                final canInstall =
                    await AppInstaller.canRequestPackageInstalls();
                if (!canInstall && dialogContext.mounted) {
                  final action = await showDialog<String>(
                    context: dialogContext,
                    builder: (ctx) => AlertDialog(
                      title: const Text('需要安装权限'),
                      content: const Text(
                        '青科课表通需要开启「允许安装未知应用」权限才能覆盖升级安装包。\n\n建议先前往系统设置开启权限，开启后返回即可直接更新。',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(ctx).pop('download'),
                          child: const Text('直接下载'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.of(ctx).pop('settings'),
                          child: const Text('去开启权限'),
                        ),
                      ],
                    ),
                  );

                  if (action == 'settings') {
                    await AppInstaller.openInstallSettings();
                    return;
                  } else if (action == null) {
                    return;
                  }
                }
              }

              if (!dialogContext.mounted) return;
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

enum _DownloadStage { downloading, readyToInstall, error }

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

class _DownloadProgressDialogState extends State<_DownloadProgressDialog>
    with WidgetsBindingObserver {
  late final UpdateService _service;
  late final CancelToken _cancelToken;

  DownloadProgress? _currentProgress;
  String? _errorMessage;
  late String _currentProxy;
  bool _downloadStarted = false;

  _DownloadStage _stage = _DownloadStage.downloading;
  File? _downloadedFile;
  bool _needsPermission = false;
  bool _isTriggeringInstall = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _service = widget.updateService ?? UpdateService();
    _cancelToken = CancelToken();
    _currentProxy = widget.selectedProxy;
    _startDownload();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _cancelToken.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed &&
        _stage == _DownloadStage.readyToInstall &&
        _downloadedFile != null) {
      _onAppResumedFromSettings();
    }
  }

  Future<void> _onAppResumedFromSettings() async {
    if (!Platform.isAndroid || _downloadedFile == null) return;
    final canInstall = await AppInstaller.canRequestPackageInstalls();
    if (!mounted) return;
    setState(() {
      _needsPermission = !canInstall;
    });

    if (canInstall) {
      // 用户从系统设置切回，且已授权，自动唤起安装！
      await _executeInstall(_downloadedFile!);
    }
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
      setState(() {
        _stage = _DownloadStage.readyToInstall;
        _downloadedFile = file;
      });

      // Android 端若已具备安装权限可自动唤起系统安装器；
      // Windows 端必须等待用户明确确认点击「立即重启更新」，切忌直接退出主程序导致弹窗闪退。
      if (Platform.isAndroid) {
        await _executeInstall(file);
      }
    } catch (err) {
      if (_cancelToken.isCancelled) return;
      if (!mounted) return;
      setState(() {
        _stage = _DownloadStage.error;
        _errorMessage = '下载失败: $err';
      });
    }
  }

  Future<void> _executeInstall(File file) async {
    if (_isTriggeringInstall) return;
    _isTriggeringInstall = true;

    try {
      if (Platform.isAndroid) {
        final canInstall = await AppInstaller.canRequestPackageInstalls();
        if (!canInstall) {
          if (!mounted) return;
          setState(() {
            _needsPermission = true;
          });
          final grant = await showDialog<bool>(
            context: context,
            builder: (ctx) => AlertDialog(
              title: const Text('安装权限未开启'),
              content: const Text(
                '安装包已下载完成！\n\n青科课表通需要「安装未知应用」权限才能覆盖升级安装包，请前往系统设置开启后返回。',
              ),
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
          return;
        }

        if (!mounted) return;
        setState(() {
          _needsPermission = false;
        });
      }

      await AppInstaller.install(file);
      if (mounted) {
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '唤起系统安装器失败: $e';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isTriggeringInstall = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_stage == _DownloadStage.readyToInstall) {
      return _buildReadyToInstallDialog(theme);
    }

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

  Widget _buildReadyToInstallDialog(ThemeData theme) {
    return AlertDialog(
      title: Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            color: Color(0xFF2E7D32),
            size: 24,
          ),
          const SizedBox(width: 8),
          const Text('下载完成'),
        ],
      ),
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
            const SizedBox(height: 12),
            if (_errorMessage != null) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.errorContainer.withValues(
                    alpha: 0.5,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (_needsPermission) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.4,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.warning_amber_rounded,
                      size: 18,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '青科课表通尚未开启「安装未知应用」权限。请开启权限后切回应用，将自动唤起安装。',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.colorScheme.onSurface,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              Text(
                Platform.isWindows
                    ? '新版本已下载就绪，点击下方按钮将自动应用更新并重新启动青科课表通。'
                    : '安装包已下载就绪，点击下方按钮即可覆盖安装。',
                style: TextStyle(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('稍后安装'),
        ),
        if (_needsPermission)
          FilledButton.icon(
            icon: const Icon(Icons.settings_outlined, size: 18),
            onPressed: () => AppInstaller.openInstallSettings(),
            label: const Text('去开启权限'),
          )
        else
          FilledButton.icon(
            icon: _isTriggeringInstall
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : Icon(
                    Platform.isWindows
                        ? Icons.restart_alt_rounded
                        : Icons.install_mobile_rounded,
                    size: 18,
                  ),
            onPressed: (_downloadedFile == null || _isTriggeringInstall)
                ? null
                : () => _executeInstall(_downloadedFile!),
            label: Text(
              _isTriggeringInstall
                  ? '正在准备更新…'
                  : (Platform.isWindows ? '立即重启更新' : '立即安装'),
            ),
          ),
      ],
    );
  }
}

/// 更新日志富文本渲染组件（支持分类徽章、无序列表与行内加粗强调）。
class _ReleaseNotesView extends StatelessWidget {
  const _ReleaseNotesView({required this.content, required this.version});

  final String content;
  final String version;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trimmed = content.trim();

    if (trimmed.isEmpty) {
      return SelectableText(
        '青科课表通 v$version 现已发布，包含性能优化与体验改进。',
        style: TextStyle(
          fontSize: 13,
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.45,
        ),
      );
    }

    final sections = _parseNotes(trimmed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < sections.length; i++) ...[
          if (i > 0) const SizedBox(height: 12),
          _buildSection(context, sections[i]),
        ],
      ],
    );
  }

  Widget _buildSection(BuildContext context, _NoteSection section) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title != null && section.title!.isNotEmpty) ...[
          _buildCategoryBadge(context, section.title!),
          const SizedBox(height: 6),
        ],
        for (final item in section.items) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (item.isBullet)
                  Padding(
                    padding: const EdgeInsets.only(top: 6, right: 8, left: 2),
                    child: Container(
                      width: 5,
                      height: 5,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary.withValues(alpha: 0.8),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                Expanded(
                  child: SelectableText.rich(
                    _buildFormattedSpan(context, item.text),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13,
                      height: 1.45,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCategoryBadge(BuildContext context, String title) {
    final theme = Theme.of(context);
    Color color;
    IconData icon;

    if (title.contains('新增')) {
      color = const Color(0xFF2E7D32);
      icon = Icons.add_circle_outline_rounded;
    } else if (title.contains('优化')) {
      color = const Color(0xFF1976D2);
      icon = Icons.auto_awesome_outlined;
    } else if (title.contains('修复')) {
      color = const Color(0xFFE65100);
      icon = Icons.build_circle_outlined;
    } else if (title.contains('碎碎念')) {
      color = const Color(0xFF7B1FA2);
      icon = Icons.chat_bubble_outline_rounded;
    } else {
      color = theme.colorScheme.primary;
      icon = Icons.label_outline_rounded;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  /// 将带 `**加粗**` 或 `` `代码` `` 的 Markdown 行解析为 TextSpan
  TextSpan _buildFormattedSpan(BuildContext context, String text) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*.*?\*\*|`.*?`)');
    int lastIndex = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > lastIndex) {
        spans.add(TextSpan(text: text.substring(lastIndex, match.start)));
      }
      final matched = match.group(0)!;
      if (matched.startsWith('**') && matched.endsWith('**')) {
        spans.add(
          TextSpan(
            text: matched.substring(2, matched.length - 2),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        );
      } else if (matched.startsWith('`') && matched.endsWith('`')) {
        spans.add(
          TextSpan(
            text: matched.substring(1, matched.length - 1),
            style: const TextStyle(
              fontFamily: 'monospace',
              fontWeight: FontWeight.w600,
            ),
          ),
        );
      }
      lastIndex = match.end;
    }

    if (lastIndex < text.length) {
      spans.add(TextSpan(text: text.substring(lastIndex)));
    }

    return TextSpan(children: spans);
  }

  List<_NoteSection> _parseNotes(String markdown) {
    final lines = markdown.split(RegExp(r'\r?\n'));
    final sections = <_NoteSection>[];

    String? currentTitle;
    final currentItems = <_NoteItem>[];

    void commitCurrentSection() {
      if (currentItems.isNotEmpty || currentTitle != null) {
        sections.add(
          _NoteSection(
            title: currentTitle,
            items: List.unmodifiable(currentItems),
          ),
        );
        currentItems.clear();
      }
      currentTitle = null;
    }

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;

      if (line.startsWith('#')) {
        commitCurrentSection();
        currentTitle = line.replaceFirst(RegExp(r'^#+\s*'), '').trim();
        continue;
      }

      if (line.startsWith('- ') ||
          line.startsWith('* ') ||
          line.startsWith('+ ')) {
        final text = line.substring(2).trim();
        if (text.isNotEmpty) {
          currentItems.add(_NoteItem(text: text, isBullet: true));
        }
      } else {
        currentItems.add(_NoteItem(text: line, isBullet: false));
      }
    }

    commitCurrentSection();
    return sections;
  }
}

class _NoteSection {
  const _NoteSection({required this.title, required this.items});

  final String? title;
  final List<_NoteItem> items;
}

class _NoteItem {
  const _NoteItem({required this.text, required this.isBullet});

  final String text;
  final bool isBullet;
}
