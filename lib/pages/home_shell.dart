/// 已登录后的外壳：两页（课表 / 设置）+ 底部悬浮 dock + 状态弹窗。
///
/// 切换用「交叉淡入」：
///  - 两页始终保持挂载，切到设置再切回来时，课表的周次与滚动位置不会丢；
///  - 动画由**外壳自己的** AnimationController 驱动，不依赖页面内部的
///    `AnimatedOpacity`。之前的实现把淡入淡出交给隐式动画，页面又被
///    `TickerMode` 关掉，结果切回课表时动画可能停在原地——现在没有这个可能；
///  - **可中断**：每次切换都以"当前画面上真实的透明度"为新起点，中途反向切回时
///    不会从 0.15 重新淡入（那会在视觉上闪一下），而是从当前值连续过渡回去；
///  - 非当前页 `IgnorePointer` 断掉点击、`TickerMode` 停掉动画、
///    `opacity: 0` 跳过绘制（布局仍保留，避免 PageView 拿到 0 尺寸）。
library;

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../widgets/floating_dock.dart';
import '../widgets/status_popup.dart';
import 'debug_page.dart';
import 'schedule_page.dart';
import 'settings_page.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.model});

  final AppModel model;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell>
    with SingleTickerProviderStateMixin {
  static const List<FloatingDockItem> _items = <FloatingDockItem>[
    FloatingDockItem(
      icon: Icons.grid_view_outlined,
      activeIcon: Icons.grid_view_rounded,
      label: '课表',
    ),
    FloatingDockItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: '设置',
    ),
  ];

  int _index = 0;

  /// 本次过渡开始时每页的透明度快照。
  ///
  /// 中断时用它当起点：如果直接用 `forward(from: 0)`，正在淡入的那页会从当前值
  /// （比如 0.5）瞬间掉回 0.15 再重来，看起来就是闪一下。
  late Map<int, double> _from = <int, double>{0: 1, 1: 0};

  /// 切换进度：0 → 完全显示起点页，1 → 完全显示目标页。静止时为 1。
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
  );

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  /// 曲线处理后的进度。
  double get _progress =>
      Curves.easeOutCubic.transform(_fade.value.clamp(0.0, 1.0));

  /// 某一页在进度 [t] 时的透明度：从本次过渡的起点值线性走到目标值
  /// （当前页 1、其它页 0）。
  double _opacityOf(int index, double t) {
    final target = index == _index ? 1.0 : 0.0;
    final start = _from[index] ?? target;
    return start + (target - start) * t;
  }

  void _go(int index) {
    if (index == _index) return;
    // 先按"旧的目标"把当前真实透明度取出来当新起点，再改目标并重新计时。
    final t = _progress;
    final snapshot = <int, double>{
      for (var i = 0; i < _items.length; i++) i: _opacityOf(i, t),
    };
    setState(() {
      _from = snapshot;
      _index = index;
    });
    _fade.forward(from: 0);
  }

  void _openDebug() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DebugPage(model: widget.model)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final pages = <Widget>[
      SchedulePage(model: widget.model),
      SettingsPage(model: widget.model),
    ];
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          for (var index = 0; index < pages.length; index++)
            Positioned.fill(child: _page(index, pages[index])),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingDock(index: _index, items: _items, onChanged: _go),
          ),
          // 状态弹窗挂在两页之上：登录 / 取课表 / 重登 / 报错都在这里出。
          // 它在外壳里，不在页面的 ListenableBuilder 内，所以要自己订阅状态。
          //
          // 紧贴 AppBar 下方、靠右：通知要短小、别挡到左上的周次条。
          Positioned(
            top: topInset + 6,
            right: 10,
            child: ListenableBuilder(
              listenable: widget.model,
              builder: (context, _) =>
                  StatusPopup(model: widget.model, onOpenDebug: _openDebug),
            ),
          ),
        ],
      ),
    );
  }

  Widget _page(int index, Widget child) {
    final active = index == _index;

    return AnimatedBuilder(
      animation: _fade,
      builder: (context, _) {
        final t = _progress;

        return IgnorePointer(
          ignoring: !active,
          child: TickerMode(
            enabled: active,
            child: Opacity(
              // 带 key 是为了让测试能直接断言"这一页现在到底是不是可见的"：
              // 之前用隐式动画 + TickerMode，测试只能看到 widget 存在，
              // 看不到它其实停在透明状态。
              key: ValueKey<String>('page-opacity-$index'),
              opacity: _opacityOf(index, t).clamp(0.0, 1.0),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
