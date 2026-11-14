/// 软件更新对话框与后台下载流转界面。
library;

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/formatted_text_span.dart';
import '../src/updater/update_flow_controller.dart';
import '../src/updater/update_models.dart';
import '../src/updater/update_service.dart';
import '../theme/app_theme.dart';
import '../widgets/changelog_category_badge.dart';
import '../widgets/tactile_button.dart';

/// 弹出统一的应用更新流程弹窗（同一弹窗内流转：版本说明 → 下载进度 → 准备安装）。
///
/// 全程禁止点击弹窗外空白处关闭：
/// - 预览阶段按返回键或右上角关闭仅收起弹窗（顶栏图标常驻保留）；
/// - 下载阶段按返回键、右上角关闭或点击「后台下载」会收起弹窗并继续在后台下载；
/// - 只有点击「取消下载」才会中止下载任务。
Future<void> showUpdateDialog(
  BuildContext context, {
  UpdateFlowController? controller,
  UpdateCheckResult? updateResult,
  String proxyPrefix = '',
  List<String> backupProxies = const <String>[],
  UpdateService? updateService,
}) async {
  final ownsController = controller == null;
  final effectiveController =
      controller ?? UpdateFlowController(updateService: updateService);

  if (updateResult != null) {
    effectiveController.setAvailableUpdate(
      result: updateResult,
      selectedProxy: proxyPrefix,
      backupProxies: backupProxies,
    );
  }

  final result = effectiveController.updateResult;
  final release = effectiveController.release;
  if (result == null || release == null) {
    if (ownsController) effectiveController.dispose();
    return;
  }

  if (effectiveController.isDialogOpen) {
    if (ownsController) effectiveController.dispose();
    return;
  }

  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateFlowDialog(
        controller: effectiveController,
        cancelOnDispose: ownsController,
      ),
    );
  } finally {
    if (ownsController) {
      effectiveController.dispose();
    }
  }
}

/// 弹出下载进度弹窗并执行自动安装（兼容直接从下载阶段启动的调用方式）。
Future<void> showDownloadProgressDialog(
  BuildContext context, {
  required ReleaseAsset asset,
  required String selectedProxy,
  List<String> backupProxies = const <String>[],
  UpdateService? updateService,
}) async {
  final controller = UpdateFlowController(updateService: updateService);
  controller.prepareDirectDownload(
    asset: asset,
    selectedProxy: selectedProxy,
    backupProxies: backupProxies,
  );
  unawaited(controller.startDownload());
  try {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _UpdateFlowDialog(controller: controller, cancelOnDispose: true),
    );
  } finally {
    controller.dispose();
  }
}

class _UpdateFlowDialog extends StatefulWidget {
  const _UpdateFlowDialog({
    required this.controller,
    required this.cancelOnDispose,
  });

  final UpdateFlowController controller;
  final bool cancelOnDispose;

  @override
  State<_UpdateFlowDialog> createState() => _UpdateFlowDialogState();
}

class _UpdateFlowDialogState extends State<_UpdateFlowDialog>
    with WidgetsBindingObserver {
  late int _lastCloseEvent;
  bool _hasPopped = false;

  UpdateFlowController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller.attachDialog();
    _lastCloseEvent = _controller.requestCloseEvent;
    _controller.addListener(_onControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.detachDialog();
    WidgetsBinding.instance.removeObserver(this);
    if (widget.cancelOnDispose &&
        _controller.stage == UpdateFlowStage.downloading) {
      _controller.cancelDownload();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_controller.refreshInstallPermissionAndAutoInstall());
    }
  }

  void _onControllerChanged() {
    if (!mounted) return;
    if (_controller.requestCloseEvent != _lastCloseEvent) {
      _lastCloseEvent = _controller.requestCloseEvent;
      _popSelf();
      return;
    }
    setState(() {});
  }

  void _popSelf() {
    if (_hasPopped || !mounted) return;
    _hasPopped = true;
    Navigator.of(context).pop();
  }

  Future<void> _launchExternalUrl(String rawUrl) async {
    if (rawUrl.isEmpty) return;
    final uri = Uri.parse(rawUrl);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _onTapUpdateNow() async {
    if (Platform.isAndroid) {
      final canInstall = await _controller.canInstallPackages();
      if (!canInstall && mounted) {
        final action = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('需要安装权限'),
            content: const Text(
              '青科课表通需要开启「允许安装未知应用」权限才能覆盖升级安装包。\n\n建议先前往系统设置开启权限，开启后返回即可直接更新。',
            ),
            actions: [
              TactileActionButton(
                variant: TactileActionVariant.text,
                onPressed: () => Navigator.of(ctx).pop('download'),
                label: const Text('直接下载'),
              ),
              TactileActionButton(
                variant: TactileActionVariant.filled,
                onPressed: () => Navigator.of(ctx).pop('settings'),
                label: const Text('去开启权限'),
              ),
            ],
          ),
        );

        if (action == 'settings') {
          await _controller.openInstallSettings();
          return;
        } else if (action == null) {
          return;
        }
      }
    }

    if (!mounted) return;
    unawaited(_controller.startDownload());
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return switch (_controller.stage) {
      UpdateFlowStage.idle ||
      UpdateFlowStage.available => _buildAvailableDialog(theme),
      UpdateFlowStage.downloading => _buildDownloadingDialog(theme),
      UpdateFlowStage.readyToInstall => _buildReadyToInstallDialog(theme),
      UpdateFlowStage.error => _buildErrorDialog(theme),
    };
  }

  Widget _buildAvailableDialog(ThemeData theme) {
    final result = _controller.updateResult;
    final release = _controller.release;
    if (result == null || release == null) {
      return const SizedBox.shrink();
    }

    final asset = _controller.targetAsset;
    if (asset == null) {
      // 发现新版本但未匹配到当前架构安装包时给出友好提示
      return AlertDialog(
        titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
        title: _DialogTitleBar(
          title: '发现新版本 v${release.version}',
          closeTooltip: '稍后再说',
          onClose: _popSelf,
        ),
        content: Text(
          '检测到新版本，但当前平台与架构 (${result.currentArchName.isNotEmpty ? result.currentArchName : '当前环境'}) 暂未匹配到直接升级安装包。\n\n您可以前往 GitHub Releases 页面查看与下载。',
        ),
        actions: [
          _DialogActionsBar(
            left: TactileActionButton(
              variant: TactileActionVariant.text,
              onPressed: _popSelf,
              label: const Text('知道了'),
            ),
            right: TactileActionButton(
              variant: TactileActionVariant.filled,
              onPressed: () {
                _popSelf();
                unawaited(_launchExternalUrl(release.htmlUrl));
              },
              label: const Text('前往 Release 页面'),
            ),
          ),
        ],
      );
    }

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      title: _DialogTitleBar(
        leading: Icon(
          Icons.system_update_rounded,
          color: theme.colorScheme.primary,
        ),
        title: '发现新版本 v${release.version}',
        closeTooltip: '稍后再说',
        onClose: _popSelf,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${release.formattedDate.isNotEmpty ? '发布于 ${release.formattedDate} · ' : ''}${asset.formattedSize} · ${result.currentArchName}',
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
        _DialogActionsBar(
          left: TactileActionButton(
            variant: TactileActionVariant.outlined,
            onPressed: () =>
                unawaited(_launchExternalUrl(_controller.proxiedDownloadUrl)),
            label: const Text('浏览器下载'),
          ),
          right: TactileActionButton(
            variant: TactileActionVariant.filled,
            onPressed: _onTapUpdateNow,
            label: const Text('立即更新'),
          ),
        ),
      ],
    );
  }

  Widget _buildDownloadingDialog(ThemeData theme) {
    final progress = _controller.progress;
    final progressVal = progress?.progress;
    final percent = progress?.percentage ?? 0;
    final asset = _controller.targetAsset;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      title: _DialogTitleBar(
        leading: Icon(
          Icons.downloading_rounded,
          color: theme.colorScheme.primary,
        ),
        title: '正在下载更新',
        closeTooltip: '后台下载',
        onClose: _popSelf,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (asset != null)
              Text(
                asset.name,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            if (_controller.currentProxy.trim() !=
                _controller.selectedProxy.trim()) ...[
              const SizedBox(height: 4),
              Text(
                '已自动回退至: ${displayProxyName(_controller.currentProxy)}',
                style: TextStyle(
                  fontSize: 11,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
            const SizedBox(height: 14),
            LinearProgressIndicator(value: progressVal),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  progress == null ? '连接中…' : '$percent%',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Flexible(
                  child: Text(
                    progress == null
                        ? ''
                        : '${progress.formattedReceived} / ${progress.formattedTotal} (${progress.formattedSpeed})',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        _DialogActionsBar(
          left: TactileActionButton(
            variant: TactileActionVariant.text,
            onPressed: () {
              final canReturnToAvailable = _controller.hasAvailableFallback;
              _controller.cancelDownload();
              if (!canReturnToAvailable) {
                _popSelf();
              }
            },
            label: const Text('取消下载'),
          ),
          right: TactileActionButton(
            variant: TactileActionVariant.tonal,
            onPressed: _popSelf,
            label: const Text('后台下载'),
          ),
        ),
      ],
    );
  }

  Widget _buildErrorDialog(ThemeData theme) {
    final asset = _controller.targetAsset;
    final errorMessage = _controller.errorMessage ?? '下载失败，请稍后重试';

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      title: _DialogTitleBar(
        leading: Icon(
          Icons.error_outline_rounded,
          color: theme.colorScheme.error,
        ),
        title: '下载出错',
        closeTooltip: '关闭',
        onClose: _popSelf,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (asset != null) ...[
              Text(
                asset.name,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
            ],
            Text(
              errorMessage,
              style: TextStyle(color: theme.colorScheme.error, fontSize: 13),
            ),
          ],
        ),
      ),
      actions: [
        _DialogActionsBar(
          left: TactileActionButton(
            variant: TactileActionVariant.outlined,
            onPressed: () {
              final url = _controller.fallbackDownloadUrl;
              _popSelf();
              unawaited(_launchExternalUrl(url));
            },
            label: const Text('浏览器下载'),
          ),
          right: TactileActionButton(
            variant: TactileActionVariant.filled,
            onPressed: () => unawaited(_controller.startDownload()),
            label: const Text('重试下载'),
          ),
        ),
      ],
    );
  }

  Widget _buildReadyToInstallDialog(ThemeData theme) {
    final asset = _controller.targetAsset;
    final errorMessage = _controller.errorMessage;
    final needsPermission = _controller.needsPermission;
    final isTriggeringInstall = _controller.isTriggeringInstall;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(24, 16, 12, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      actionsPadding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      title: _DialogTitleBar(
        leading: Icon(
          Icons.check_circle_rounded,
          color: AppColors.of(context).success,
          size: 24,
        ),
        title: '下载完成',
        closeTooltip: '稍后安装',
        onClose: _popSelf,
      ),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (asset != null) ...[
              Text(
                asset.name,
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),
            ],
            if (errorMessage != null) ...[
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
                  errorMessage,
                  style: TextStyle(
                    color: theme.colorScheme.onErrorContainer,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
            ],
            if (needsPermission) ...[
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
        _DialogActionsBar(
          left: TactileActionButton(
            variant: TactileActionVariant.text,
            onPressed: _popSelf,
            label: const Text('稍后安装'),
          ),
          right: needsPermission
              ? TactileActionButton(
                  variant: TactileActionVariant.filled,
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  onPressed: () => unawaited(_controller.openInstallSettings()),
                  label: const Text('去开启权限'),
                )
              : TactileActionButton(
                  variant: TactileActionVariant.filled,
                  icon: isTriggeringInstall
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.colorScheme.onPrimary,
                          ),
                        )
                      : Icon(
                          Platform.isWindows
                              ? Icons.restart_alt_rounded
                              : Icons.install_mobile_rounded,
                          size: 18,
                        ),
                  onPressed:
                      (_controller.downloadedFile == null ||
                          isTriggeringInstall)
                      ? null
                      : () => unawaited(_controller.executeInstall()),
                  label: Text(
                    isTriggeringInstall
                        ? '正在准备更新…'
                        : (Platform.isWindows ? '立即重启更新' : '立即安装'),
                  ),
                ),
        ),
      ],
    );
  }
}

/// 统一弹窗标题栏（图标 + 标题 + 右上角关闭按钮）。
class _DialogTitleBar extends StatelessWidget {
  const _DialogTitleBar({
    this.leading,
    required this.title,
    required this.closeTooltip,
    required this.onClose,
  });

  final Widget? leading;
  final String title;
  final String closeTooltip;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        if (leading != null) ...[leading!, const SizedBox(width: 10)],
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
        ),
        TactileIconButton(
          icon: const Icon(Icons.close_rounded),
          size: 32,
          iconSize: 18,
          color: theme.colorScheme.onSurfaceVariant,
          surfaceStyle: TactileSurfaceStyle.tinted,
          tooltip: closeTooltip,
          onPressed: onClose,
        ),
      ],
    );
  }
}

/// 统一弹窗底部双按钮容器：宽够时左右分列，极窄屏/大字号自动换行防溢出。
class _DialogActionsBar extends StatelessWidget {
  const _DialogActionsBar({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: SizedBox(
        width: double.maxFinite,
        child: Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 12,
          runSpacing: 8,
          children: [left, right],
        ),
      ),
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
      return Text(
        '青科课表通 v$version 现已发布，包含性能优化与体验改进。',
        style: TextStyle(
          fontSize: 13,
          color: theme.colorScheme.onSurfaceVariant,
          height: 1.45,
        ),
      );
    }

    final sections = _parseNotes(trimmed);

    return SelectionArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (int i = 0; i < sections.length; i++) ...[
            if (i > 0) const SizedBox(height: 12),
            _buildSection(context, sections[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildSection(BuildContext context, _NoteSection section) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (section.title != null && section.title!.isNotEmpty) ...[
          ChangelogCategoryBadge(title: section.title!),
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
                  child: Text.rich(
                    buildFormattedTextSpan(
                      context,
                      item.text,
                      baseStyle: theme.textTheme.bodyMedium?.copyWith(
                        fontSize: 13,
                        height: 1.45,
                      ),
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
