import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'floating_dock.dart';
import 'tactile_button.dart';

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

/// 构建居中自适应纯白悬浮胶囊风格的 [SnackBar]。
///
/// 短文字自适应紧凑宽度居中展示，长句或带操作按钮时展开并自动换行；
/// 外层保留透明 [SnackBar] 壳以继承左右横滑关闭、防排队清理与安全区避让能力。
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

  // 底部间距：主页抬高避让 FloatingDock；无 Dock 子页抬升至 40dp 拇指舒适区避免贴底。
  final EdgeInsetsGeometry margin = aboveDock
      ? EdgeInsets.fromLTRB(16, 0, 16, FloatingDock.contentInset(context) + 4)
      : EdgeInsets.fromLTRB(
          16,
          0,
          16,
          40 + MediaQuery.paddingOf(context).bottom,
        );

  return SnackBar(
    behavior: SnackBarBehavior.floating,
    dismissDirection: DismissDirection.horizontal,
    margin: margin,
    padding: EdgeInsets.zero,
    backgroundColor: Colors.transparent,
    elevation: 0,
    shape: const RoundedRectangleBorder(side: BorderSide.none),
    duration: duration ?? const Duration(seconds: 2),
    content: _AppSnackBarPill(
      message: message,
      type: type,
      icon: effectiveIcon,
      iconColor: iconColor,
      action: action,
    ),
  );
}

class _AppSnackBarPill extends StatelessWidget {
  const _AppSnackBarPill({
    required this.message,
    required this.type,
    required this.icon,
    required this.iconColor,
    required this.action,
  });

  static const double _maxWidth = 420;
  static const double _iconSize = 18;
  static const double _iconGap = 8;

  final String message;
  final AppSnackBarType type;
  final IconData icon;
  final Color iconColor;
  final SnackBarAction? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final textDirection = Directionality.of(context);
    final textScaler = MediaQuery.textScalerOf(context);
    final boldText = MediaQuery.boldTextOf(context);

    final messageStyle = (theme.textTheme.bodyMedium ?? const TextStyle())
        .merge(DefaultTextStyle.of(context).style)
        .copyWith(
          color: scheme.onSurface,
          fontSize: 14,
          fontWeight: boldText ? FontWeight.w600 : FontWeight.w500,
          height: 1.35,
        );

    final actionLabelStyle = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: action?.textColor ?? scheme.primary,
    );

    final Color borderColor = type == AppSnackBarType.error
        ? scheme.error.withValues(alpha: 0.40)
        : scheme.outlineVariant.withValues(alpha: 0.85);

    return Center(
      heightFactor: 1,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxPillWidth = math.min(constraints.maxWidth, _maxWidth);
          final leftPad = 14.0;
          final rightPad = action == null ? 16.0 : 8.0;

          double reservedActionWidth = 0;
          if (action != null) {
            final actionPainter = TextPainter(
              text: TextSpan(text: action!.label, style: actionLabelStyle),
              maxLines: 1,
              textDirection: textDirection,
              textScaler: textScaler,
            )..layout();
            // 按钮左右内边距 + 与正文的间隔
            reservedActionWidth = actionPainter.width + 26;
          }

          final maxTextWidth = math.max(
            48.0,
            maxPillWidth -
                leftPad -
                rightPad -
                _iconSize -
                _iconGap -
                reservedActionWidth,
          );
          final messagePainter = TextPainter(
            text: TextSpan(text: message, style: messageStyle),
            maxLines: 1,
            textDirection: textDirection,
            textScaler: textScaler,
          )..layout(maxWidth: maxTextWidth);
          final radius = messagePainter.didExceedMaxLines ? 20.0 : 999.0;

          return ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxPillWidth),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: borderColor),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.10),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(leftPad, 10, rightPad, 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Icon(icon, size: _iconSize, color: iconColor),
                    const SizedBox(width: _iconGap),
                    Flexible(child: Text(message, style: messageStyle)),
                    if (action != null) ...<Widget>[
                      const SizedBox(width: 6),
                      TactileActionButton(
                        variant: TactileActionVariant.text,
                        minimumSize: Size.zero,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        foregroundColor: action!.textColor ?? scheme.primary,
                        onPressed: () {
                          ScaffoldMessenger.of(context).hideCurrentSnackBar();
                          action!.onPressed();
                        },
                        label: Text(action!.label, style: actionLabelStyle),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
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
