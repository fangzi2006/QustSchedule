/// 教务地址簿：一个学校一条，可新增、切换、删除。
///
/// 切换地址会丢掉当前会话（Cookie 跟主机绑定），所以切完直接回登录页。
/// 地址只在"登录成功"时才被收进这里，手滑打错的地址不会留在列表里。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/school.dart';

class SchoolAddressPage extends StatelessWidget {
  const SchoolAddressPage({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    // 只听**偏好**的通知源（见 [AppModel.prefsNotifier]）：课表刷新那些
    // 与本页无关的 model 通知，不该让整页重建一次。
    return ListenableBuilder(
      listenable: model.prefsNotifier,
      builder: (context, _) {
        final theme = Theme.of(context);
        final addresses = model.schools;
        return Scaffold(
          appBar: AppBar(
            title: const Text('教务地址'),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: '新增地址',
                onPressed: () => _add(context),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              Text(
                '只支持新正方教务系统；地址写到 /jwglxt 为止，不要带登录页文件名。\n'
                '6 条线路账号通用；切换后会用当前账号重新登录（会话与主机绑定）。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 12),
              for (final address in addresses) ...<Widget>[
                Card(
                  child: ListTile(
                    leading: Icon(
                      sameSchool(address, model.schoolBaseUrl)
                          ? Icons.radio_button_checked_rounded
                          : Icons.radio_button_unchecked_rounded,
                      size: 20,
                      color: sameSchool(address, model.schoolBaseUrl)
                          ? theme.colorScheme.primary
                          : theme.hintColor,
                    ),
                    title: Text(
                      address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: sameSchool(address, model.schoolBaseUrl)
                        ? Text(
                            '使用中',
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.primary,
                            ),
                          )
                        : null,
                    trailing: sameSchool(address, model.schoolBaseUrl)
                        ? null
                        : IconButton(
                            icon: const Icon(
                              Icons.delete_outline_rounded,
                              size: 20,
                            ),
                            tooltip: '删除',
                            onPressed: () => _remove(context, address),
                          ),
                    onTap: () => _switchTo(context, address),
                  ),
                ),
                const SizedBox(height: 8),
              ],
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: () => _add(context),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新增教务地址'),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _switchTo(BuildContext context, String address) async {
    if (sameSchool(address, model.schoolBaseUrl)) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('切换到这台教务？'),
        content: Text(
          '切换后会直接用当前账号在这台教务登录，不需要重新输入密码：\n\n'
          '$address',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('切换'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;
    // 先把压在 HomeShell 上的页面全部收掉，否则主界面切成登录页时
    // 这些路由还盖在上面，用户会看到"点了切换没反应"。
    Navigator.of(context).popUntil((route) => route.isFirst);
    // 不等它：换地址 + 自动登录要联网，界面由外壳的加载态负责。
    unawaited(model.changeSchool(address));
  }

  Future<void> _add(BuildContext context) async {
    final entered = await showDialog<String>(
      context: context,
      builder: (context) => const _AddressDialog(),
    );
    if (entered == null) return;
    await model.addSchool(entered);
  }

  Future<void> _remove(BuildContext context, String address) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除这个地址？'),
        content: Text(address),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) await model.removeSchool(address);
  }
}

/// 新增地址：一个输入框 + 已知学校的快捷填法。
class _AddressDialog extends StatefulWidget {
  const _AddressDialog();

  @override
  State<_AddressDialog> createState() => _AddressDialogState();
}

class _AddressDialogState extends State<_AddressDialog> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) {
      setState(() => _error = '请填写教务地址');
      return;
    }
    if (!RegExp(r'^(https?://)?[\w.-]+\.\w+').hasMatch(text)) {
      setState(() => _error = '看起来不是有效的地址');
      return;
    }
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('新增教务地址'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          TextField(
            controller: _controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: '教务系统地址',
              hintText: 'https://jw.example.edu.cn/jwglxt',
              errorText: _error,
              helperText: '写到 /jwglxt 为止，不要带 login_slogin.html',
              helperMaxLines: 2,
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final school in knownSchools)
                ActionChip(
                  label: Text(school.name),
                  onPressed: () => setState(() {
                    _controller.text = school.baseUrl;
                    _error = null;
                  }),
                ),
            ],
          ),
        ],
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('添加')),
      ],
    );
  }
}
