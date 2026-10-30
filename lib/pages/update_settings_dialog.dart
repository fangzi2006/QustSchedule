// ignore_for_file: deprecated_member_use

/// 软件更新设置弹窗。
library;

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/preferences_repository.dart';

/// 辅助函数：根据代理地址展示简洁名称。
String displayProxyName(String proxyUrl) {
  final trimmed = proxyUrl.trim();
  if (trimmed.isEmpty) return '直连 (GitHub)';
  if (trimmed.contains('gh-proxy.com')) return 'gh-proxy.com (推荐)';
  if (trimmed.contains('ghproxy.net')) return 'ghproxy.net';
  if (trimmed.contains('gh.llkk.cc')) return 'gh.llkk.cc';
  return '自定义 ($trimmed)';
}

/// 弹出更新偏好设置面板。
Future<void> showUpdateSettingsDialog(
  BuildContext context, {
  required AppModel model,
}) async {
  await showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return _UpdateSettingsDialog(model: model);
    },
  );
}

class _UpdateSettingsDialog extends StatefulWidget {
  const _UpdateSettingsDialog({required this.model});

  final AppModel model;

  @override
  State<_UpdateSettingsDialog> createState() => _UpdateSettingsDialogState();
}

class _UpdateSettingsDialogState extends State<_UpdateSettingsDialog> {
  late bool _autoCheck;
  late String _selectedOption;
  late TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    _autoCheck = widget.model.autoCheckUpdate;
    final currentProxy = widget.model.updateProxyUrl;

    if (currentProxy.isEmpty) {
      _selectedOption = '';
    } else if (presetUpdateProxies.contains(currentProxy)) {
      _selectedOption = currentProxy;
    } else {
      _selectedOption = 'custom';
    }
    _customController = TextEditingController(text: currentProxy);
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    await widget.model.setAutoCheckUpdate(_autoCheck);

    String targetProxy = _selectedOption;
    if (_selectedOption == 'custom') {
      targetProxy = _customController.text.trim();
    }
    await widget.model.setUpdateProxyUrl(targetProxy);
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('软件更新设置'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('启动时自动检查更新'),
                subtitle: const Text('有新版本时在课表页弹窗提醒'),
                value: _autoCheck,
                onChanged: (val) {
                  setState(() {
                    _autoCheck = val;
                  });
                },
              ),
              const Divider(height: 24),
              const Text(
                'GitHub 加速代理',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const SizedBox(height: 4),
              Text(
                '国内网络访问 GitHub 易受阻，加速代理可提高更新检测与 APK 下载成功率。',
                style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 8),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('gh-proxy.com (推荐)'),
                subtitle: const Text('高可用公共反代，速度快且稳定'),
                value: 'https://gh-proxy.com',
                groupValue: _selectedOption,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedOption = val);
                },
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('ghproxy.net'),
                subtitle: const Text('备用加速镜像节点'),
                value: 'https://ghproxy.net',
                groupValue: _selectedOption,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedOption = val);
                },
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('gh.llkk.cc'),
                subtitle: const Text('备用加速镜像节点'),
                value: 'https://gh.llkk.cc',
                groupValue: _selectedOption,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedOption = val);
                },
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('直连 (GitHub 官方)'),
                subtitle: const Text('不使用任何代理，需网络环境能直接连通 GitHub'),
                value: '',
                groupValue: _selectedOption,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedOption = val);
                },
              ),
              RadioListTile<String>(
                contentPadding: EdgeInsets.zero,
                title: const Text('自定义加速前缀'),
                subtitle: const Text('使用自建 Cloudflare Worker 或反向代理'),
                value: 'custom',
                groupValue: _selectedOption,
                onChanged: (val) {
                  if (val != null) setState(() => _selectedOption = val);
                },
              ),
              if (_selectedOption == 'custom') ...[
                const SizedBox(height: 6),
                TextField(
                  controller: _customController,
                  decoration: const InputDecoration(
                    labelText: '自定义代理地址前缀',
                    hintText: '例如: https://my-proxy.com',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _save, child: const Text('保存')),
      ],
    );
  }
}
