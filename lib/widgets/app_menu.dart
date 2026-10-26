/// 轻量锚定菜单：贴着按钮弹出，**没有外边距**，带纵向帷幕展开与菜单项错峰浮现动效。
///
/// 为什么不用 `PopupMenuButton`：
///  1. 它固定 300ms 展开，四项的菜单点完要等半秒才落定，观感很拖；
///  2. 它四周有 `menuPadding`（默认 8px），在圆角卡片里看起来就是"一圈白边"，
///     和 app 里其它卡片（圆角 14、无内边距）明显不是一套；
///  3. 这两点都没有主题开关可调。
///
/// 这里用一条 `PopupRoute` + `CustomSingleChildLayout` 自己摆位置：
/// 横向居中于按钮、纵向贴在按钮下方，放不下就翻到上方，并夹在屏幕安全边距内；
/// 展开/收起全程由单一路由 `animation` 驱动，中途点击菜单项或空白处可随时无跳变打断。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 一项菜单。
class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.trailing,
    this.enabled = true,
  }) : isDivider = false;

  /// 一条分隔线（点击不会有任何结果）。
  const AppMenuItem.divider()
    : value = null,
      label = '',
      icon = null,
      trailing = null,
      enabled = true,
      isDivider = true;

  final T? value;
  final String label;
  final IconData? icon;
  final Widget? trailing;
  final bool enabled;
  final bool isDivider;
}

/// 贴着 [context] 对应的控件弹出菜单；选中后回调 [onSelected]。
///
/// [context] 必须是"要被当成锚点"的那个控件（用 `Builder` 拿它的 context）。
Future<void> showAppMenu<T>({
  required BuildContext context,
  required List<AppMenuItem<T>> items,
  required ValueChanged<T> onSelected,
  double maxHeight = 380,
}) async {
  final box = context.findRenderObject();
  final overlay = Overlay.of(
    context,
    rootOverlay: true,
  ).context.findRenderObject();
  if (box is! RenderBox || overlay is! RenderBox || !box.hasSize) return;

  final anchor = box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  final picked = await Navigator.of(context, rootNavigator: true).push<T>(
    _AppMenuRoute<T>(anchor: anchor, items: items, maxHeight: maxHeight),
  );
  if (picked != null) onSelected(picked);
}

class _AppMenuRoute<T> extends PopupRoute<T> {
  _AppMenuRoute({
    required this.anchor,
    required this.items,
    required this.maxHeight,
  });

  final Rect anchor;
  final List<AppMenuItem<T>> items;
  final double maxHeight;

  // 不压暗背景：菜单很小，压暗反而像弹了个对话框。
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 100);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => CustomSingleChildLayout(
    delegate: _MenuLayout(anchor: anchor),
    child: _AppMenu<T>(
      items: items,
      maxHeight: maxHeight,
      anchor: anchor,
      animation: animation,
    ),
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final fade = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOut),
    );
    return FadeTransition(opacity: fade, child: child);
  }
}

/// 把菜单摆在锚点下方居中；下方放不下就翻到上方。
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout({required this.anchor});

  final Rect anchor;
  static const double margin = 8;
  static const double gap = 6;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = constraints.maxWidth.isFinite
        ? constraints.maxWidth - margin * 2
        : 260.0;
    final maxHeight = constraints.maxHeight.isFinite
        ? constraints.maxHeight - margin * 2
        : 380.0;
    return BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    var x = anchor.center.dx - childSize.width / 2;
    x = x.clamp(margin, size.width - childSize.width - margin);

    var y = anchor.bottom + gap;
    if (y + childSize.height > size.height - margin) {
      final above = anchor.top - childSize.height - gap;
      y = above >= margin ? above : size.height - childSize.height - margin;
    }
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(covariant _MenuLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

class _AppMenu<T> extends StatelessWidget {
  const _AppMenu({
    required this.items,
    required this.maxHeight,
    required this.anchor,
    required this.animation,
  });

  final List<AppMenuItem<T>> items;
  final double maxHeight;
  final Rect anchor;
  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerTheme;
    final screen = MediaQuery.sizeOf(context);
    final estHeight = (items.length * 40.0).clamp(40.0, maxHeight);
    final noRoomBelow = anchor.bottom + 6 + estHeight > screen.height - 8;
    final openUp = noRoomBelow && anchor.top >= estHeight + 14;

    const half = 70.0;
    final maxLeft = math.max(8.0, screen.width - 140.0 - 8.0);
    final left = (anchor.center.dx - half).clamp(8.0, maxLeft);
    final dxRatio = (anchor.center.dx - left) / half - 1.0;
    final alignX = dxRatio.clamp(-0.85, 0.85);
    final alignY = openUp ? 1.0 : -1.0;
    final align = openUp ? Alignment.bottomCenter : Alignment.topCenter;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value.clamp(0.0, 1.0);
        final curveT = Curves.easeOutCubic.transform(t);
        final scale = 0.92 + 0.08 * curveT;
        final heightFactor = 0.55 + 0.45 * curveT;

        return Transform.scale(
          alignment: Alignment(alignX, alignY),
          scale: scale,
          child: Material(
            color: Colors.white,
            surfaceTintColor: Colors.transparent,
            elevation: 4,
            shadowColor: Colors.black.withValues(alpha: 0.20),
            borderRadius: BorderRadius.circular(14),
            // 必须裁剪：既防止水波纹越出圆角，又在帷幕展开时裁出平滑圆角底边。
            clipBehavior: Clip.antiAlias,
            child: Align(
              alignment: align,
              heightFactor: heightFactor,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: maxHeight),
                child: SingleChildScrollView(
                  child: IntrinsicWidth(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        for (var i = 0; i < items.length; i++)
                          _buildStaggeredItem(divider, i, t, openUp),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// 单项错峰浮现：全部由当前帧 `t` 纯函数算出，任意时刻反转都能无跳变回退。
  Widget _buildStaggeredItem(
    DividerThemeData divider,
    int index,
    double t,
    bool openUp,
  ) {
    final item = items[index];
    final step = index < 6 ? index : 6;
    final start = step * 0.05;
    final end = start + 0.65;
    final raw = ((t - start) / (end - start)).clamp(0.0, 1.0);
    final itemT = Curves.easeOutCubic.transform(raw);
    final dy = (1.0 - itemT) * (openUp ? 6.0 : -6.0);

    final Widget child;
    if (item.isDivider) {
      child = Divider(
        height: 1,
        thickness: divider.thickness,
        color: divider.color,
      );
    } else {
      child = _MenuTile<T>(item: item);
    }

    final offset = Offset(0, dy);
    final shifted = Transform.translate(offset: offset, child: child);
    return Opacity(opacity: itemT, child: shifted);
  }
}

class _MenuTile<T> extends StatelessWidget {
  const _MenuTile({required this.item});

  final AppMenuItem<T> item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = item.enabled ? theme.colorScheme.onSurface : theme.hintColor;
    return InkWell(
      onTap: item.enabled ? () => Navigator.of(context).pop(item.value) : null,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            if (item.icon != null) ...<Widget>[
              Icon(
                item.icon,
                size: 18,
                color: item.enabled
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.hintColor,
              ),
              const SizedBox(width: 10),
            ],
            Text(item.label, style: TextStyle(fontSize: 14, color: color)),
            if (item.trailing != null) ...<Widget>[
              const SizedBox(width: 16),
              item.trailing!,
            ],
          ],
        ),
      ),
    );
  }
}
