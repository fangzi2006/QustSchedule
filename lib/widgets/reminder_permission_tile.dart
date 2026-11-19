import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../src/reminder_service.dart';
import '../theme/app_theme.dart';
import 'app_snack_bar.dart';
import 'tactile_button.dart';

/// 权限状态列表项：统一展示图标、权限名称、状态着色副标题与右侧操作按钮。
class ReminderPermissionTile extends StatelessWidget {
  const ReminderPermissionTile({
    super.key,
    required this.icon,
    required this.title,
    required this.value,
    required this.ok,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool? ok;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppColors.of(context);
    final color = switch (ok) {
      true => colors.success,
      false => theme.colorScheme.error,
      null => colors.warning,
    };
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title),
      subtitle: Text(value, style: TextStyle(color: color)),
      trailing: TactileActionButton(
        variant: TactileActionVariant.text,
        onPressed: onAction,
        label: Text(actionLabel),
      ),
    );
  }
}

/// 跨应用跳转到系统设置页时的悬浮指路提示，避免切出后页内胶囊被挡住。
void showReminderGuideToast(
  BuildContext context,
  ReminderService service,
  String message, {
  bool aboveDock = false,
}) {
  if (defaultTargetPlatform == TargetPlatform.android) {
    unawaited(service.showToast(message, longDuration: true));
  } else {
    if (!context.mounted) return;
    showAppSnackBar(
      context,
      message: message,
      aboveDock: aboveDock,
      duration: const Duration(seconds: 3),
    );
  }
}
