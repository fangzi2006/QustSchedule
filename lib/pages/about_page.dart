/// 关于页面：应用图标、版本号、内联检查更新操作，以及更新日志、代理设置、调试信息、开源协议与项目主页入口。
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../src/app_model.dart';
import '../src/app_version.dart';
import '../src/updater/update_models.dart';
import '../src/updater/update_service.dart';
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

  @override
  void initState() {
    super.initState();
    unawaited(UpdateService.cleanOldUpdateFiles(currentVersion: appVersion));
  }

  Future<void> _checkUpdate() async {
    if (_checkingUpdate) return;
    setState(() {
      _checkingUpdate = true;
      _updateStatusText = null;
      _lastCheckHadError = false;
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);

    try {
      final service = UpdateService();
      final result = await service.checkForUpdatesWithFallback(
        currentVersion: appVersion,
        selectedProxy: widget.model.selectedUpdateProxy,
        backupProxies: widget.model.allUpdateProxies,
      );

      if (!mounted) return;

      switch (result.status) {
        case UpdateStatus.hasUpdate:
          setState(() {
            _updateStatusText = '发现新版本 v${result.release?.version}';
          });
          await showUpdateDialog(
            context,
            updateResult: result,
            proxyPrefix: widget.model.selectedUpdateProxy,
            backupProxies: widget.model.allUpdateProxies,
          );
          break;
        case UpdateStatus.noUpdate:
          setState(() {
            _updateStatusText = '青科课表通已是最新版本 (v$appVersion)';
          });
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text('已是最新版本 (v$appVersion)'),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
          break;
        case UpdateStatus.rateLimited:
          setState(() {
            _lastCheckHadError = true;
            _updateStatusText = 'API 访问受限，请稍后再试';
          });
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? '检查更新过于频繁，请稍后再试'),
              behavior: SnackBarBehavior.floating,
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
            ),
          );
          break;
        case UpdateStatus.networkError:
          setState(() {
            _lastCheckHadError = true;
            _updateStatusText = '网络超时或节点不可用';
          });
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? '网络连接超时，可尝试切换加速节点'),
              behavior: SnackBarBehavior.floating,
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
            ),
          );
          break;
        case UpdateStatus.unsupportedPlatform:
        case UpdateStatus.error:
          setState(() {
            _lastCheckHadError = true;
            _updateStatusText = result.errorMessage ?? '检查更新失败';
          });
          scaffoldMessenger.showSnackBar(
            SnackBar(
              content: Text(result.errorMessage ?? '检查更新失败，请重试'),
              behavior: SnackBarBehavior.floating,
            ),
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
    final uri = Uri.parse(kProjectHomeUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!context.mounted || opened) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('无法打开链接')));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.model.prefsNotifier,
      builder: (context, _) {
        return Scaffold(
          appBar: AppBar(title: const Text('关于青科课表通')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              // 顶部头部卡片：App 图标、标题、当前版本与内联「检查更新」按钮 (FlClash 风格)
              Card(
                elevation: 0.8,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
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
                      FilledButton.tonalIcon(
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
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const ChangelogPage(),
                        ),
                      ),
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

/// 本应用开源协议全文（GPL v3）：从 asset 里的 LICENSE 读取展示。
class LicenseTextPage extends StatefulWidget {
  const LicenseTextPage({super.key});

  @override
  State<LicenseTextPage> createState() => _LicenseTextPageState();
}

class _LicenseTextPageState extends State<LicenseTextPage> {
  String? _text;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final text = await rootBundle.loadString('LICENSE');
      if (!mounted) return;
      setState(() => _text = text);
    } catch (_) {
      if (!mounted) return;
      setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('开源协议')),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (_failed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '协议文件读取失败',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ),
      );
    }
    if (_text == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
      child: SelectableText(
        _reflow(_text!),
        textAlign: TextAlign.left,
        style: theme.textTheme.bodySmall?.copyWith(
          fontSize: 13,
          height: 1.6,
          color: theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  String _reflow(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    return normalized
        .split(RegExp(r'\n[ \t]*\n'))
        .map((p) => p.replaceAll(RegExp(r'\s*\n\s*'), ' ').trim())
        .where((p) => p.isNotEmpty)
        .join('\n\n');
  }
}
