/// 软件更新代理管理页面：支持增删自定义加速代理、测速检测、可用性诊断与自动回退设置。
library;

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/preferences_repository.dart';
import '../src/updater/update_models.dart';
import '../src/updater/update_service.dart';

class UpdateProxyPage extends StatefulWidget {
  const UpdateProxyPage({super.key, required this.model});

  final AppModel model;

  @override
  State<UpdateProxyPage> createState() => _UpdateProxyPageState();
}

class _UpdateProxyPageState extends State<UpdateProxyPage> {
  final _service = UpdateService();
  final _testResults = <String, ProxyTestResult>{};
  final _testingUrls = <String>{};

  @override
  void initState() {
    super.initState();
  }

  Future<void> _testProxy(String url) async {
    if (_testingUrls.contains(url)) return;
    setState(() => _testingUrls.add(url));
    try {
      final result = await _service.testProxy(url);
      if (!mounted) return;
      setState(() {
        _testResults[url] = result;
      });
    } finally {
      if (mounted) {
        setState(() => _testingUrls.remove(url));
      }
    }
  }

  Future<void> _testAll() async {
    final proxies = <String>[
      ...presetUpdateProxies,
      ...widget.model.customUpdateProxies,
      '',
    ];

    await Future.wait(proxies.map(_testProxy));
  }

  Future<void> _addProxy(BuildContext context) async {
    final result = await showDialog<String>(
      context: context,
      builder: (dialogCtx) =>
          _AddProxyDialog(existingProxies: widget.model.allUpdateProxies),
    );

    if (result != null && result.isNotEmpty) {
      await widget.model.addCustomUpdateProxy(result);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已添加代理: $result'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      // 添加后立即进行一次测速
      _testProxy(result);
    }
  }

  Future<void> _removeProxy(BuildContext context, String url) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除代理'),
        content: Text('确定要删除加速代理「$url」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      if (widget.model.selectedUpdateProxy == url) {
        await widget.model.setSelectedUpdateProxy(defaultUpdateProxyUrl);
      }
      await widget.model.removeCustomUpdateProxy(url);
      setState(() {
        _testResults.remove(url);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: widget.model.prefsNotifier,
      builder: (context, _) {
        final selectedProxy = widget.model.selectedUpdateProxy;
        final proxies = <String>[
          ...presetUpdateProxies,
          ...widget.model.customUpdateProxies,
          '',
        ];

        return Scaffold(
          appBar: AppBar(
            title: const Text('更新代理设置'),
            actions: [
              IconButton(
                icon: const Icon(Icons.speed_rounded),
                tooltip: '测速全部节点',
                onPressed: _testAll,
              ),
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: '添加代理',
                onPressed: () => _addProxy(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            children: [
              Text(
                '青科课表通从 GitHub 获取版本与更新包。配置加速代理可避免境内网络卡顿或握手超时。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 12),
              _buildSectionTitle('首选加速节点'),
              for (final proxy in proxies) ...[
                _buildProxyCard(context, proxy, selectedProxy),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => _addProxy(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新增自定义代理'),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('通用更新选项'),
              Card(
                child: SwitchListTile(
                  secondary: const Icon(Icons.autorenew_rounded, size: 20),
                  title: const Text('启动时自动检查更新'),
                  subtitle: const Text('打开课表页时静默检测新版本并弹窗'),
                  value: widget.model.autoCheckUpdate,
                  onChanged: widget.model.setAutoCheckUpdate,
                ),
              ),
              const SizedBox(height: 20),
              _buildSectionTitle('多层自动回退机制'),
              Card(
                color: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.35,
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        Icons.shield_outlined,
                        size: 22,
                        color: theme.colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '无需担心所选代理失效：\n'
                          '• 若首选节点超时或网络异常，系统会自动轮询备用代理并最终回退至官方直连；\n'
                          '• 绝大多数代理仅加速静态文件，检查版本时若节点不支持 API，系统会自动直连官方 api.github.com，绝不阻断更新。',
                          style: theme.textTheme.bodySmall?.copyWith(
                            height: 1.5,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionTitle(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 8),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).hintColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  Widget _buildProxyCard(
    BuildContext context,
    String proxy,
    String selectedProxy,
  ) {
    final theme = Theme.of(context);
    final isSelected = proxy.trim() == selectedProxy.trim();
    final isTesting = _testingUrls.contains(proxy);
    final testResult = _testResults[proxy];
    final isCustom = proxy.isNotEmpty && !presetUpdateProxies.contains(proxy);

    return Card(
      elevation: isSelected ? 1.5 : 0.5,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
              ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => widget.model.setSelectedUpdateProxy(proxy),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isSelected
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    size: 20,
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.hintColor,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          displayProxyName(proxy),
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: isSelected
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: isSelected
                                ? theme.colorScheme.primary
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        if (proxy.isNotEmpty &&
                            displayProxyName(proxy) != proxy) ...[
                          const SizedBox(height: 2),
                          Text(
                            proxy,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 11,
                              color: theme.hintColor,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  // 操作区：测速 / 删除
                  if (isTesting)
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  else
                    IconButton(
                      icon: const Icon(Icons.network_ping_rounded, size: 20),
                      tooltip: '测速',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _testProxy(proxy),
                    ),
                  if (isCustom)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      tooltip: '删除',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _removeProxy(context, proxy),
                    ),
                ],
              ),
              // 测速状态展示 (延时与 API 支持标签)
              if (testResult != null) ...[
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.only(left: 30),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      _buildLatencyChip(context, testResult),
                      _buildApiSupportChip(context, testResult),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLatencyChip(BuildContext context, ProxyTestResult result) {
    Color bg;
    Color fg;

    if (!result.isUsable) {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
    } else if (result.latencyMs < 600) {
      bg = const Color(0xFFE8F5E9);
      fg = const Color(0xFF2E7D32);
    } else if (result.latencyMs < 1500) {
      bg = const Color(0xFFFFF3E0);
      fg = const Color(0xFFE65100);
    } else {
      bg = const Color(0xFFFFEBEE);
      fg = const Color(0xFFC62828);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        result.isUsable ? '${result.latencyMs} ms' : '不可用 / 超时',
        style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: fg),
      ),
    );
  }

  Widget _buildApiSupportChip(BuildContext context, ProxyTestResult result) {
    final theme = Theme.of(context);
    if (!result.isUsable) return const SizedBox.shrink();

    final supportsApi = result.supportsApi;
    final text = supportsApi ? '支持 API' : '仅下载加速 (API 自动回退)';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: supportsApi
            ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          color: supportsApi
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _AddProxyDialog extends StatefulWidget {
  const _AddProxyDialog({required this.existingProxies});

  final List<String> existingProxies;

  @override
  State<_AddProxyDialog> createState() => _AddProxyDialogState();
}

class _AddProxyDialogState extends State<_AddProxyDialog> {
  late final TextEditingController _controller;
  String? _errorText;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  String? _validateAndClean(String raw) {
    if (raw.isEmpty) return null;
    String clean = raw.trim();
    if (!clean.startsWith('http://') && !clean.startsWith('https://')) {
      clean = 'https://$clean';
    }
    while (clean.endsWith('/')) {
      clean = clean.substring(0, clean.length - 1);
    }
    try {
      final uri = Uri.parse(clean);
      if (uri.host.isEmpty) return null;
      return clean;
    } catch (_) {
      return null;
    }
  }

  void _submit() {
    final cleaned = _validateAndClean(_controller.text.trim());
    if (cleaned == null) {
      setState(() {
        _errorText = '请输入合法的 http/https 代理地址';
      });
      return;
    }
    if (widget.existingProxies.contains(cleaned) || cleaned.isEmpty) {
      setState(() {
        _errorText = '该代理地址已存在';
      });
      return;
    }
    Navigator.of(context).pop(cleaned);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增加速代理'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '支持输入常见 GitHub 文件加速代理前缀，例如：\nhttps://ghproxy.net',
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '代理地址',
              hintText: 'https://...',
              errorText: _errorText,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
    );
  }
}
