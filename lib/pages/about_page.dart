/// 关于页面：应用图标、版本号、内联检查更新操作，以及更新日志、代理设置、调试信息、开源协议与项目主页入口。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_model.dart';
import '../src/app_version.dart';
import '../src/route_settled.dart';
import '../src/updater/update_models.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/page_skeleton.dart';
import '../widgets/tactile_button.dart';
import 'changelog_page.dart';
import 'debug_page.dart';
import 'update_dialog.dart';
import 'update_proxy_page.dart';

/// 项目主页（源码与发行版）：写入「项目主页与源码」，满足 GPL 的源码获取告知要求。
const String kProjectHomeUrl = 'https://github.com/fangzi2006/QustSchedule';

class AboutPage extends StatefulWidget {
  const AboutPage({super.key, required this.model});

  final AppModel model;

  @override
  State<AboutPage> createState() => _AboutPageState();
}

class _AboutPageState extends State<AboutPage> {
  bool _checkingUpdate = false;
  String? _updateStatusText;
  bool _lastCheckHadError = false;
  bool _cleanupScheduled = false;
  RouteSettledHandle? _cleanupRouteHandle;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_cleanupScheduled) return;
    _cleanupScheduled = true;
    // 旧安装包清理推迟到页面转场稳定之后，避免压入首帧并发磁盘遍历。
    _cleanupRouteHandle = scheduleAfterRouteSettled(
      context: context,
      isMounted: () => mounted,
      task: () => widget.model.cleanOldUpdateFiles(),
    );
  }

  @override
  void dispose() {
    _cleanupRouteHandle?.cancel();
    _cleanupRouteHandle = null;
    super.dispose();
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      _updateStatusText = null;
      _lastCheckHadError = false;
    });

    try {
      final result = await widget.model.checkForUpdates();

      if (!mounted) return;

      switch (result.status) {
        case UpdateStatus.hasUpdate:
          setState(() {
            _updateStatusText = '发现新版本 v${result.release?.version}';
          });
          await showUpdateDialog(
            context,
            controller: widget.model.updateFlow,
            updateResult: result,
            proxyPrefix: widget.model.selectedUpdateProxy,
            backupProxies: widget.model.allUpdateProxies,
          );
          break;
        case UpdateStatus.noUpdate:
          setState(() {
            _updateStatusText = '青科课表通已是最新版本 (v$appVersion)';
          });
          showAppSnackBar(
            context,
            message: '已是最新版本 (v$appVersion)',
            type: AppSnackBarType.success,
          );
          break;
        case UpdateStatus.rateLimited:
          setState(() {
            _lastCheckHadError = true;
            _updateStatusText = 'API 访问受限，请稍后再试';
          });
          showAppSnackBar(
            context,
            message: result.errorMessage ?? '检查更新过于频繁，请稍后再试',
            type: AppSnackBarType.error,
            action: SnackBarAction(
              label: '代理设置',
              onPressed: () {
                if (mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UpdateProxyPage(model: widget.model),
                    ),
                  );
                }
              },
            ),
          );
          break;
        case UpdateStatus.networkError:
          setState(() {
            _lastCheckHadError = true;
            _updateStatusText = '网络超时或节点不可用';
          });
          showAppSnackBar(
            context,
            message: result.errorMessage ?? '网络连接超时，可尝试切换加速节点',
            type: AppSnackBarType.error,
            action: SnackBarAction(
              label: '切换代理',
              onPressed: () {
                if (mounted) {
                  Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => UpdateProxyPage(model: widget.model),
                    ),
                  );
                }
              },
            ),
          );
          break;
        case UpdateStatus.unsupportedPlatform:
        case UpdateStatus.error:
          setState(() {
            _lastCheckHadError = true;
            _updateStatusText = result.errorMessage ?? '检查更新失败';
          });
          showAppSnackBar(
            context,
            message: result.errorMessage ?? '检查更新失败，请重试',
            type: AppSnackBarType.error,
          );
          break;
      }
    } finally {
      if (mounted) {
        setState(() => _checkingUpdate = false);
      }
    }
  }

  Future<void> _openProjectLink(BuildContext context) async {
    final opened = await widget.model.openExternalUrl(kProjectHomeUrl);
    if (!context.mounted || opened) return;
    showAppSnackBar(context, message: '无法打开链接', type: AppSnackBarType.error);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.model.prefsNotifier,
      builder: (context, _) {
        return Scaffold(
          appBar: TactileAppBar(
            leading: const TactileBackButton(),
            title: const Text('关于青科课表通'),
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // 顶部头部卡片：App 图标、标题、当前版本与内联「检查更新」按钮
              Card(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 24,
                  ),
                  child: Column(
                    children: [
                      // App 官方图标
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          boxShadow: [
                            BoxShadow(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.18,
                              ),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(18),
                          child: Image.asset(
                            'assets/logo.png',
                            width: 72,
                            height: 72,
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Text(
                        '青科课表通',
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'v$appVersionFull',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 内联「检查更新」按钮
                      TactileActionButton(
                        variant: TactileActionVariant.tonal,
                        onPressed: _checkingUpdate ? null : _checkUpdate,
                        icon: _checkingUpdate
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Icon(Icons.refresh_rounded, size: 18),
                        label: Text(_checkingUpdate ? '正在检查更新...' : '检查更新'),
                      ),
                      if (_updateStatusText != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _updateStatusText!,
                          style: TextStyle(
                            fontSize: 12,
                            color: _lastCheckHadError
                                ? theme.colorScheme.error
                                : theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // 其余选项保持原样，规整于卡片中
              Card(
                child: Column(
                  children: [
                    ListTile(
                      leading: const Icon(Icons.tune_rounded, size: 20),
                      title: const Text('更新代理设置'),
                      subtitle: Text(
                        '首选: ${displayProxyName(widget.model.selectedUpdateProxy)}',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => UpdateProxyPage(model: widget.model),
                        ),
                      ),
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.history_rounded, size: 20),
                      title: const Text('更新日志'),
                      subtitle: const Text('各版本详细说明与改进记录'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => ChangelogPage.open(context),
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.code_rounded, size: 20),
                      title: const Text('项目主页与源码'),
                      subtitle: const Text(kProjectHomeUrl),
                      trailing: const Icon(Icons.open_in_new_rounded, size: 18),
                      onTap: () => _openProjectLink(context),
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.description_outlined, size: 20),
                      title: const Text('开源许可'),
                      subtitle: const Text('第三方组件许可'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showLicensePage(
                        context: context,
                        applicationName: '青科课表通',
                        applicationVersion: appVersionFull,
                      ),
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.gavel_outlined, size: 20),
                      title: const Text('开源协议'),
                      subtitle: const Text('GNU GPL v3 · 协议全文'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const LicenseTextPage(),
                        ),
                      ),
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.bug_report_outlined, size: 20),
                      title: const Text('调试信息'),
                      subtitle: const Text('原始响应、解析结果、请求记录'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => DebugPage(model: widget.model),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 从 UTF-8 字节直接解码并分段重排 LICENSE 文本（顶层纯 Dart 函数，可直接在后台 Isolate 执行）。
List<String> reflowLicenseBytes(Uint8List bytes) {
  return LicenseTextPage.reflowParagraphs(utf8.decode(bytes));
}

/// 本应用开源协议全文（GPL v3）：从 asset 里的 LICENSE 并行后台解码重排，
/// 并在入场转场落稳后懒渲染展示，不阻塞 260ms 滑入动画。
class LicenseTextPage extends StatefulWidget {
  const LicenseTextPage({super.key});

  static final RegExp _blankLineSplitRegex = RegExp(r'\n[ \t]*\n');
  static final RegExp _lineBreakCollapseRegex = RegExp(r'\s*\n\s*');

  static List<String>? _cachedParagraphs;
  static Future<List<String>>? _inFlightLoad;

  @visibleForTesting
  static void resetCache() {
    _cachedParagraphs = null;
    _inFlightLoad = null;
  }

  /// 将 LICENSE 文本规范化并按段落拆分，仅在加载时执行一次。
  @visibleForTesting
  static List<String> reflowParagraphs(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final result = <String>[];
    for (final chunk in normalized.split(_blankLineSplitRegex)) {
      final cleaned = chunk.replaceAll(_lineBreakCollapseRegex, ' ').trim();
      if (cleaned.isNotEmpty) {
        result.add(cleaned);
      }
    }
    return result;
  }

  /// 读取并缓存分段后的开源协议文本（UTF-8 解码与段落重排卸载到后台 Isolate）。
  static Future<List<String>> loadParagraphs({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh) {
      final cached = _cachedParagraphs;
      if (cached != null) return cached;
      final inFlight = _inFlightLoad;
      if (inFlight != null) return inFlight;
    }

    late final Future<List<String>> future;
    future = _loadAndReflow().whenComplete(() {
      if (identical(_inFlightLoad, future)) {
        _inFlightLoad = null;
      }
    });
    _inFlightLoad = future;
    return future;
  }

  static Future<List<String>> _loadAndReflow() async {
    final data = await rootBundle.load('LICENSE');
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final paragraphs = await runInBackground<List<String>>(
      () => reflowLicenseBytes(bytes),
    );
    final unmodifiable = List<String>.unmodifiable(paragraphs);
    _cachedParagraphs = unmodifiable;
    return unmodifiable;
  }

  @override
  State<LicenseTextPage> createState() => _LicenseTextPageState();
}

class _LicenseTextPageState extends State<LicenseTextPage>
    with RouteSettledStateMixin<LicenseTextPage> {
  List<String>? _paragraphs;
  bool _failed = false;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final cached = LicenseTextPage._cachedParagraphs;
    if (cached != null) {
      _paragraphs = cached;
    } else {
      // 立即与入场转场动画并行发起后台加载与 Isolate 分段重排。
      _load();
    }
  }

  Future<void> _load({bool forceRefresh = false}) async {
    final generation = ++_loadGeneration;
    try {
      final paragraphs = await LicenseTextPage.loadParagraphs(
        forceRefresh: forceRefresh,
      );
      if (!mounted || generation != _loadGeneration) return;
      _paragraphs = paragraphs;
      _failed = false;
      if (isRouteSettled) {
        setState(() {});
      }
    } catch (_) {
      if (!mounted || generation != _loadGeneration) return;
      _failed = true;
      if (isRouteSettled) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: TactileAppBar(
        leading: const TactileBackButton(),
        title: const Text('开源协议'),
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (!isRouteSettled) {
      return const DocumentTransitionPlaceholder();
    }
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                '协议文件读取失败',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TactileActionButton(
                variant: TactileActionVariant.tonal,
                onPressed: () {
                  setState(() {
                    _failed = false;
                    _paragraphs = null;
                  });
                  _load(forceRefresh: true);
                },
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    final paragraphs = _paragraphs;
    if (paragraphs == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final textStyle = theme.textTheme.bodySmall?.copyWith(
      fontSize: 13,
      height: 1.6,
      color: theme.colorScheme.onSurface,
    );
    return SelectionArea(
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        itemCount: paragraphs.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(
            bottom: index == paragraphs.length - 1 ? 0 : 12,
          ),
          child: Text(
            paragraphs[index],
            textAlign: TextAlign.left,
            style: textStyle,
          ),
        ),
      ),
    );
  }
}
