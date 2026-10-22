/// 已登录后的外壳：两页（课表 / 设置）+ 底部悬浮 dock + 状态弹窗。
///
/// 切换用「水平平移」：
///  - 两页放在同一条**自建横向轨道**里（[Stack] + `Transform.translate`），
///    切换 = 整页横向滑过去，不是淡入淡出。没有用 [PageView]，因为它会回收
///    离屏页（切回来状态就丢了），而且位置没法被 dock 逐帧驱动；
///  - **位移完全跟着 dock 的指示块走**：页面自己没有动画，指示块滑到哪，
///    两页之间的分界就在哪（见 [FloatingDock.onPillProgress]）。按下、拖动、
///    松手三种情况都只有一处动，所以不会出现"阴影到位了页面还在路上"；
///  - **内容区不能用手势切换**：课表页内部有自己的翻页 [PageView]，
///    外壳若也接受横向拖动，两套手势会打架（滑一下既翻周又切页）。
///    所以外壳这一层**完全不注册手势**，两页之间只由底部 dock 触发；
///  - 两页始终保持挂载，切到设置再切回来时，课表的周次与滚动位置不会丢；
///  - 非当前页 `IgnorePointer` 断掉点击、`TickerMode` 停掉动画。
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

class _HomeShellState extends State<HomeShell> {
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

  /// 课表页的 widget 实例**只创建一次**。
  ///
  /// 之前每次 build 都 `SchedulePage(model: model)` 新建一个：model 没变，
  /// 但 widget 实例变了 → 整棵子树重建（实测 57ms/次，正是切页卡顿的主因）。
  /// 缓存实例后切页只动翻页器的位置，页面内容一个字节都不重建。
  late final Widget _schedulePage = SchedulePage(model: widget.model);

  /// 设置页：**第一次切过去时才建**，建好就一直留着。
  ///
  /// 懒建是为了冷启动首帧（设置页整棵建出来要占首帧构建的三分之一以上）。
  /// 但建好之后**不能再扔**——切回来时它得还在，展开状态与滚动位置才不丢。
  Widget? _settingsPage;

  /// 切到设置页 → 现在就把设置页建出来。
  ///
  /// 必须在开始滑动**之前**建完：否则滑到一半才建，那一帧会卡住。
  ///
  /// 触发点是 dock 的 `onPressStart`（手指按下），不是"首帧后空闲时"：
  /// 试过在首帧之后延一帧预建，实测那正好把 40~100ms 的构建砸在用户刚
  /// 看到课表、正要滑动的那一帧上 —— 换来的是启动卡顿，不值。
  /// 按下 dock 时用户已经决定要走了，这一帧的代价才是可以接受的。
  void _ensureSettingsPage() {
    if (_settingsPage != null) return;
    setState(() => _settingsPage = SettingsPage(model: widget.model));
  }

  final GlobalKey<_ShellPagerState> _pagerKey = GlobalKey<_ShellPagerState>();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top + kToolbarHeight;
    final Widget? settingsPage = _settingsPage;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _ShellPager(
              key: _pagerKey,
              index: _index,
              onIndexChanged: _onPageChanged,
              pages: <Widget>[
                _schedulePage,
                // 还没建时给个空位：横向轨道上留出它的位置，
                // 滑过去之前会先把它建好。
                settingsPage ?? const SizedBox.shrink(),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingDock(
              index: _index,
              items: _items,
              onPillProgress: _onPillProgress,
              // 按下 dock 就把设置页建好：等滑到一半再建，那一帧必卡。
              onPressStart: _ensureSettingsPage,
            ),
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

  /// 页面吸附到位、真的换页了（由翻页器在到位时通知）。
  void _onPageChanged(int index) {
    if (index == _index) return;
    setState(() => _index = index);
  }

  /// dock 指示块移动 → 页面跟着平移（位置完全由指示块决定）。
  void _onPillProgress(double progress) {
    _pagerKey.currentState?.followPill(progress);
  }

  void _openDebug() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => DebugPage(model: widget.model)),
    );
  }
}

/// 承载两页的横向轨道。
///
/// ## 为什么自己搭轨道，而不是用 [PageView]
///
/// 两点考虑：
///
///  1. **两页必须常驻**。[PageView] 会回收离屏页 —— 切到设置页再切回来，
///     设置页被重新构建，展开状态、滚动位置全丢（原来靠 `Opacity` 叠着才
///     没有这个问题）。自己搭轨道就没这毛病。
///  2. **位移要能被外部精确驱动**。页面是"跟着 dock 指示块走"的（见
///     [FloatingDock.onPillProgress]），这要求一个能直接写"当前在哪"的量，
///     而不是等手势自己结算、再补一段自己的动画。
///
/// ## 为什么平移比淡入淡出快
///
/// 之前是交叉淡入淡出：[Opacity] 在 0 < alpha < 1 时会让整页走一次
/// saveLayer（离屏缓冲再合成），框架源码里明确写着"expensive"——一屏内容的
/// 离屏缓冲在桌面端很贵，动画期间每帧都做一次。
///
/// 水平平移只用变换，不产生离屏缓冲：帧内只重绘"多出来的那一条"，
/// 两页各自的像素被缓存复用（每页一个 [RepaintBoundary]）。
///
/// ## 为什么内容区没有切换手势
///
/// 课表页内部有一个自己的 [PageView]（左右翻周）。若外壳这一层也接受
/// 横向拖动，两套手势会打架——内层翻周与外层换页同时响应，表现为
/// "滑一下既翻周又切页"。
///
/// 所以这一层**完全不注册手势**：两页之间的切换只由底部 dock 触发。
class _ShellPager extends StatefulWidget {
  const _ShellPager({
    super.key,
    required this.index,
    required this.onIndexChanged,
    required this.pages,
  });

  final int index;
  final ValueChanged<int> onIndexChanged;
  final List<Widget> pages;

  @override
  State<_ShellPager> createState() => _ShellPagerState();
}

class _ShellPagerState extends State<_ShellPager>
    with SingleTickerProviderStateMixin {
  /// 轨道上的当前位置：0 = 课表页正中，1 = 设置页正中。
  ///
  /// **唯一写入方是 [followPill]**（dock 指示块的位置）。这里不再自己跑动画：
  /// 两套动画必然差半拍 —— 指示块先到位、页面还在滑，看起来就是"阴影停了、
  /// 页面还在动"。
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: Duration.zero,
    value: widget.index.toDouble(),
  );

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
  }

  @override
  void dispose() {
    _controller.removeListener(_onTick);
    _controller.dispose();
    super.dispose();
  }

  /// 轨道当前位置（0 = 第一页正中，1 = 第二页正中）。
  double get _position => _controller.value;

  void _onTick() {
    // 位置只在**正好落在整页上**时才算换页。
    //
    // 指示块从"课表"滑到"设置"的过程中，位置会连续经过 0.3 / 0.5 / 0.7……
    // 这些都不是"换页了"，只是路过；一旦按 round() 判定，中途 0.5 就会把
    // 当前页切过去（按钮可点、动画停了），滑到一半被打断就会停在错的状态。
    final double offset = _position - _position.round();
    if (offset.abs() > 0.001) return;
    final int page = _position.round();
    if (page != widget.index) widget.onIndexChanged(page);
  }

  /// 把页面放到 dock 指示块所在的位置（0..1）。
  ///
  /// **页面没有自己的动画**：它只是跟着指示块走。指示块滑向手指、跟手拖动、
  /// 松手落位，三种情况都由 dock 的动画驱动，这里只负责把位置抄过来。
  ///
  /// 这样只有一处动，就不会出现"阴影已经到位、页面还在路上"（或者反过来）
  /// 的错位 —— 之前是两套动画（指示块 180ms / 页面 260ms），必然差半拍。
  ///
  /// [AnimationController.value] 会顺带停掉正在跑的动画，所以反复调用是安全的；
  /// 落点判定在 [_onTick] 里（位置正好压在整页上时才算换页）。
  void followPill(double progress) {
    if (!mounted) return;
    _controller.value = progress.clamp(
      0.0,
      (widget.pages.length - 1).toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        return Stack(
          children: <Widget>[
            for (var index = 0; index < widget.pages.length; index++)
              Positioned.fill(
                child: IgnorePointer(
                  ignoring: index != widget.index,
                  child: TickerMode(
                    enabled: index == widget.index,
                    child: AnimatedBuilder(
                      animation: _controller,
                      // 只重建变换：页面内容一个字节都不动。
                      //
                      // 缓存层必须**在 Transform 里面**：平移只改图层的位置，
                      // 边界内那棵子树可以直接复用已缓存的图层。反过来（边界在外）
                      // 每次平移都会把边界标脏，整页内容跟着重画一遍。
                      child: RepaintBoundary(child: widget.pages[index]),
                      builder: (context, child) => Transform.translate(
                        key: ValueKey<String>('shell-page-$index'),
                        offset: Offset((index - _position) * width, 0),
                        child: child,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
