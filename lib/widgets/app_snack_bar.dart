import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'floating_dock.dart';

/// 统一 SnackBar 语义类型。
enum AppSnackBarType {
  /// 普通信息提示。
  info,

  /// 操作成功。
  success,

  /// 操作异常或失败。
  error,

  /// 剪贴板复制提示。
  copy,
}

/// 构建符合应用 Material 3 现代轻量悬浮胶囊规范的 [SnackBar]。
SnackBar buildAppSnackBar(
  BuildContext context, {
  required String message,
  AppSnackBarType type = AppSnackBarType.info,
  IconData? icon,
  SnackBarAction? action,
  Duration? duration,
  bool aboveDock = false,
}) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;

  // 语义前缀图标与色调
  final IconData effectiveIcon =
      icon ??
      switch (type) {
        AppSnackBarType.success => Icons.check_circle_rounded,
        AppSnackBarType.error => Icons.error_outline_rounded,
        AppSnackBarType.copy => Icons.copy_rounded,
        AppSnackBarType.info => Icons.info_outline_rounded,
      };

  final colors = AppColors.of(context);
  final Color iconColor = switch (type) {
    AppSnackBarType.success => colors.success,
    AppSnackBarType.error => scheme.error,
    AppSnackBarType.copy || AppSnackBarType.info => scheme.primary,
  };

  // 底部间距：含底栏 Dock 的页面向上抬高避让；普通子页留出系统底部安全区
  final EdgeInsetsGeometry margin = aboveDock
      ? EdgeInsets.fromLTRB(16, 0, 16, FloatingDock.contentInset(context) + 4)
      : EdgeInsets.fromLTRB(
          16,
          0,
          16,
          14 + MediaQuery.paddingOf(context).bottom,
        );

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    dismissDirection: DismissDirection.horizontal,
    margin: margin,
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    backgroundColor: scheme.surface,
    elevation: 3,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(
        color: scheme.outlineVariant.withValues(alpha: 0.6),
        width: 1,
      ),
    ),
    duration: duration ?? const Duration(seconds: 2),
    content: Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Icon(effectiveIcon, size: 20, color: iconColor),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface,
              fontSize: 14,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    ),
    action: action,
  );
}

/// 弹出全局统一样式的轻量悬浮胶囊提示。
///
/// 自动清理前一个提示（防排队阻塞），并支持语义图标、操作按钮与 Dock 避让。
void showAppSnackBar(
  BuildContext context, {
  required String message,
  AppSnackBarType type = AppSnackBarType.info,
  IconData? icon,
  SnackBarAction? action,
  Duration? duration,
  bool aboveDock = false,
}) {
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    buildAppSnackBar(
      context,
      message: message,
      type: type,
      icon: icon,
      action: action,
      duration: duration,
      aboveDock: aboveDock,
    ),
  );
}
