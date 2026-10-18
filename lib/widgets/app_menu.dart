/// 轻量锚定菜单：贴着按钮弹出，**没有外边距**，展开只有 120ms。
///
/// 为什么不用 `PopupMenuButton`：
///  1. 它固定 300ms 展开，而且是"逐个 item 依次长出"的尺寸动画，四项的菜单
///     点完要等半秒才落定，观感很拖；
///  2. 它四周有 `menuPadding`（默认 8px），在圆角卡片里看起来就是"一圈白边"，
///     和 app 里其它卡片（圆角 14、无内边距）明显不是一套；
///  3. 这两点都没有主题开关可调。
///
/// 这里用一条 `PopupRoute` + `CustomSingleChildLayout` 自己摆位置：
/// 横向居中于按钮、纵向贴在按钮下方，放不下就翻到上方，并夹在屏幕安全边距内。
library;

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
    _AppMenuRoute<T>(
      anchor: anchor,
      menu: _AppMenu<T>(items: items, maxHeight: maxHeight),
    ),
  );
  if (picked != null) onSelected(picked);
}

class _AppMenuRoute<T> extends PopupRoute<T> {
  _AppMenuRoute({required this.anchor, required this.menu});

  final Rect anchor;
  final Widget menu;

  // 不压暗背景：菜单很小，压暗反而像弹了个对话框。
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => '关闭菜单';

  @override
  Duration get transitionDuration => const Duration(milliseconds: 120);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) => CustomSingleChildLayout(
    delegate: _MenuLayout(anchor: anchor),
    child: menu,
  );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => FadeTransition(
    opacity: CurvedAnimation(parent: animation, curve: Curves.easeOut),
    child: child,
  );
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
  const _AppMenu({required this.items, required this.maxHeight});

  final List<AppMenuItem<T>> items;
  final double maxHeight;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerTheme;
    return Material(
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shadowColor: Colors.black.withValues(alpha: 0.20),
      borderRadius: BorderRadius.circular(14),
      // 必须裁剪：没有内边距，水波纹会跑到圆角外面去。
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: IntrinsicWidth(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                for (final item in items)
                  if (item.isDivider)
                    Divider(
                      height: 1,
                      thickness: divider.thickness,
                      color: divider.color,
                    )
                  else
                    _MenuTile<T>(item: item),
              ],
            ),
          ),
        ),
      ),
    );
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
