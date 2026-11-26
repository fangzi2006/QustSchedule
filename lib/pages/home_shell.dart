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
import '../src/reminder_service.dart';
import '../src/widget_service.dart';
import '../widgets/app_menu.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/floating_dock.dart';
import '../widgets/status_popup.dart';
import 'academic_page.dart';
import 'debug_page.dart';
import 'schedule_page.dart';
import 'settings_page.dart';
import 'update_dialog.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({
    super.key,
    required this.model,
    this.reminders,
    this.desktopWidgets,
  });

  final AppModel model;

  /// 课程提醒编排层（仅 Android 由 main 挂上来；测试里可以为 null）。
  final ReminderService? reminders;

  /// 桌面小组件编排层（仅 Android 由 main 挂上来；测试里可以为 null）。
  final DesktopWidgetService? desktopWidgets;

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
      icon: Icons.school_outlined,
      activeIcon: Icons.school_rounded,
      label: '学业',
    ),
    FloatingDockItem(
      icon: Icons.settings_outlined,
      activeIcon: Icons.settings_rounded,
      label: '设置',
    ),
  ];

  int _index = 0;
  final GlobalKey<FloatingDockState> _dockKey = GlobalKey<FloatingDockState>();

  late int _lastUpdateReadyEvent;
  late int _lastUpdateErrorEvent;

  @override
  void initState() {
    super.initState();
    final flow = widget.model.updateFlow;
    _lastUpdateReadyEvent = flow.backgroundReadyEvent;
    _lastUpdateErrorEvent = flow.backgroundErrorEvent;
    flow.addListener(_onUpdateFlowChanged);
  }

  @override
  void didUpdateWidget(covariant HomeShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.model.updateFlow != widget.model.updateFlow) {
      oldWidget.model.updateFlow.removeListener(_onUpdateFlowChanged);
      final flow = widget.model.updateFlow;
      _lastUpdateReadyEvent = flow.backgroundReadyEvent;
      _lastUpdateErrorEvent = flow.backgroundErrorEvent;
      flow.addListener(_onUpdateFlowChanged);
    }
  }

  @override
  void dispose() {
    widget.model.updateFlow.removeListener(_onUpdateFlowChanged);
    super.dispose();
  }

  void _onUpdateFlowChanged() {
    if (!mounted) return;
    final flow = widget.model.updateFlow;
    final isTopRoute = ModalRoute.of(context)?.isCurrent ?? true;

    if (flow.backgroundReadyEvent != _lastUpdateReadyEvent) {
      _lastUpdateReadyEvent = flow.backgroundReadyEvent;
      final version = flow.release?.version ?? '';
      showAppSnackBar(
        context,
        message: version.isNotEmpty ? '新版本 v$version 下载完成' : '新版本安装包下载完成',
        type: AppSnackBarType.success,
        aboveDock: isTopRoute,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: '立即安装',
          onPressed: () {
            if (!mounted) return;
            showUpdateDialog(context, controller: flow);
          },
        ),
      );
    }

    if (flow.backgroundErrorEvent != _lastUpdateErrorEvent) {
      _lastUpdateErrorEvent = flow.backgroundErrorEvent;
      showAppSnackBar(
        context,
        message: '更新下载失败，可点击查看重试',
        type: AppSnackBarType.error,
        aboveDock: isTopRoute,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: '查看',
          onPressed: () {
            if (!mounted) return;
            showUpdateDialog(context, controller: flow);
          },
        ),
      );
    }
  }

  /// 课表页的 widget 实例**只创建一次**。
  ///
  /// 之前每次 build 都 `SchedulePage(model: model)` 新建一个：model 没变，
  /// 但 widget 实例变了 → 整棵子树重建（实测 57ms/次，正是切页卡顿的主因）。
  /// 缓存实例后切页只动翻页器的位置，页面内容一个字节都不重建。
  late final Widget _schedulePage = SchedulePage(model: widget.model);

  /// 学业页与设置页：**第一次切过去时才建**，建好就一直留着。
  ///
  /// 懒建是为了冷启动首帧。但建好之后**不能再扔**——切回来时它们得还在，展开状态与滚动位置才不丢。
  Widget? _academicPage;
  Widget? _settingsPage;

  void _ensureAcademicPage() {
    if (_academicPage != null) return;
    setState(() => _academicPage = AcademicPage(model: widget.model));
  }

  void _ensureSettingsPage() {
    if (_settingsPage != null) return;
    setState(
      () => _settingsPage = SettingsPage(
        model: widget.model,
        reminders: widget.reminders,
        desktopWidgets: widget.desktopWidgets,
      ),
    );
  }

  void _ensurePageForIndex(int index) {
    if (index == 1) {
      _ensureAcademicPage();
    } else if (index == 2) {
      _ensureSettingsPage();
    }
  }

  final GlobalKey<_ShellPagerState> _pagerKey = GlobalKey<_ShellPagerState>();

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.paddingOf(context).top + kToolbarHeight;
    final Widget? academicPage = _academicPage;
    final Widget? settingsPage = _settingsPage;

    return Scaffold(
      // 主壳三个 Tab 均无页内输入框，输入法只在弹窗或二级页弹出；
      // 关闭键盘避让缩放，防止弹出输入法时把底部悬浮 FloatingDock 顶到键盘上方。
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _ShellPager(
              key: _pagerKey,
              index: _index,
              pages: <Widget>[
                _schedulePage,
                // 还没建时给个空位：横向轨道上留出它的位置，
                // 滑过去之前会先把它建好。
                academicPage ?? const SizedBox.shrink(),
                settingsPage ?? const SizedBox.shrink(),
              ],
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: FloatingDock(
              key: _dockKey,
              index: _index,
              items: _items,
              onPillProgress: _onPillProgress,
              // 按下或滑动到哪一页只懒建对应目标页，避免首触同帧双页并发构建。
              onTargetIndexHint: _ensurePageForIndex,
              // 确定目标页即刻解锁目标页、锁住离场页，无需苦等弹簧完全停稳。
              onIndexSelected: _onPageChanged,
              // 按住/拖动 Dock 预览期间暂锁页面内容区，松手即放行。
              onPointerActiveChanged: _onDockPointerActiveChanged,
            ),
          ),
          // 全局系统状态弹窗挂在外壳顶层：登录中 / 重新登录 / 连接中 / 报错都在这里出。
          // 悬浮于所有页面之上，切页时不跟随平移，始终置顶可见。
          //
          // 紧贴 AppBar 下方、靠右：通知要短小、别挡到左上的周次条。
          Positioned(
            top: topInset + 6,
            right: 10,
            child: ListenableBuilder(
              listenable: Listenable.merge(<Listenable>[
                widget.model.hints,
                widget.model.routeNotifier,
              ]),
              builder: (context, _) => StatusPopup(
                model: widget.model,
                scope: HintScope.global,
                onOpenDebug: _openDebug,
                onNavigateToAcademic: () => _switchToPage(1),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _switchToPage(int targetIndex) {
    if (targetIndex < 0 || targetIndex >= _items.length) return;
    if (_index == targetIndex) return;
    _ensurePageForIndex(targetIndex);
    final dockState = _dockKey.currentState;
    if (dockState != null && dockState.canAnimate) {
      dockState.animateToIndex(targetIndex);
    } else {
      _pagerKey.currentState?.setActiveIndex(targetIndex);
      setState(() => _index = targetIndex);
      _pagerKey.currentState?.jumpToPage(targetIndex);
    }
  }

  /// 目标页已由 Dock 提交（松手或编程切换），立即激活目标页与交互权。
  void _onPageChanged(int index) {
    if (index < 0 || index >= _items.length) return;
    _ensurePageForIndex(index);
    if (index == _index) return;
    // 同步通知轨道更新各页菜单活跃态，避免离场页在下一帧 build 前的空窗期内误展开菜单。
    _pagerKey.currentState?.setActiveIndex(index);
    setState(() => _index = index);
  }

  void _onDockPointerActiveChanged(bool active) {
    _pagerKey.currentState?.setInteractionBlocked(active);
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
  const _ShellPager({super.key, required this.index, required this.pages});

  final int index;
  final List<Widget> pages;

  @override
  State<_ShellPager> createState() => _ShellPagerState();
}

class _ShellPagerState extends State<_ShellPager> {
  /// 轨道上的当前位置：0 = 课表页正中，1 = 学业页正中，2 = 设置页正中。
  ///
  /// 视觉位置由 [followPill] 逐帧驱动，与目标页 [widget.index] 解耦：
  /// 确定目标页后 [widget.index] 立即切换（目标页即刻解锁可点可滚、离场页锁死），
  /// 轨道位置继续跟随 Dock 弹簧平滑滑行，绝不因为跨页路过中间页而误判落点或瞬移。
  late final ValueNotifier<double> _positionNotifier = ValueNotifier<double>(
    widget.index.toDouble(),
  );

  late int _activeIndex = widget.index;
  bool _interactionBlocked = false;
  late final List<ValueNotifier<bool>> _pageActiveNotifiers =
      <ValueNotifier<bool>>[
        for (var i = 0; i < widget.pages.length; i++)
          ValueNotifier<bool>(i == widget.index),
      ];

  @override
  void didUpdateWidget(covariant _ShellPager oldWidget) {
    super.didUpdateWidget(oldWidget);
    while (_pageActiveNotifiers.length < widget.pages.length) {
      _pageActiveNotifiers.add(ValueNotifier<bool>(false));
    }
    while (_pageActiveNotifiers.length > widget.pages.length) {
      _pageActiveNotifiers.removeLast().dispose();
    }
    _activeIndex = widget.index;
    _syncPageActiveNotifiers();
  }

  @override
  void dispose() {
    for (final notifier in _pageActiveNotifiers) {
      notifier.dispose();
    }
    _positionNotifier.dispose();
    super.dispose();
  }

  void _syncPageActiveNotifiers() {
    for (var i = 0; i < _pageActiveNotifiers.length; i++) {
      _pageActiveNotifiers[i].value = !_interactionBlocked && i == _activeIndex;
    }
  }

  /// 轨道当前位置（0 = 第一页正中，1 = 第二页正中，2 = 第三页正中）。
  double get _position => _positionNotifier.value;

  void setActiveIndex(int index) {
    if (!mounted || _activeIndex == index) return;
    _activeIndex = index;
    _syncPageActiveNotifiers();
  }

  void setInteractionBlocked(bool blocked) {
    if (!mounted || _interactionBlocked == blocked) return;
    _interactionBlocked = blocked;
    _syncPageActiveNotifiers();
    setState(() {});
  }

  /// 无动画兜底切页（仅在 Dock 尚未完成首帧测量时使用）。
  void jumpToPage(int index) {
    if (!mounted) return;
    final double maxPage = (widget.pages.length - 1).toDouble();
    _positionNotifier.value = index.toDouble().clamp(0.0, maxPage);
  }

  /// 把页面放到 dock 指示块所在的位置（0..1）。
  ///
  /// **页面没有自己的动画**：它只是跟着指示块走。指示块滑向手指、跟手拖动、
  /// 松手落位，三种情况都由 dock 的动画驱动，这里只负责把位置抄过来。
  void followPill(double progress) {
    if (!mounted) return;
    final double maxPage = (widget.pages.length - 1).toDouble();
    _positionNotifier.value = (progress * maxPage).clamp(0.0, maxPage);
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
                child: AnimatedBuilder(
                  animation: _positionNotifier,
                  // 页面内容与页面级菜单作用域均位于平移变换内部：
                  //  - 缓存层在 Transform 内部，翻页只改位移不重绘页面内容；
                  //  - AppMenuScope 位于页面 TickerMode 外部，离场页失活时菜单可一边
                  //    随原页划走一边跑完平滑收起动画，且翻页途中打开菜单也始终锚定
                  //    在目标页本地坐标系内、随页面一同滑入最终位置。
                  child: AppMenuScope(
                    activeListenable: _pageActiveNotifiers[index],
                    child: IgnorePointer(
                      ignoring: _interactionBlocked || index != widget.index,
                      child: TickerMode(
                        enabled: index == widget.index,
                        child: RepaintBoundary(child: widget.pages[index]),
                      ),
                    ),
                  ),
                  builder: (context, child) => Transform.translate(
                    key: ValueKey<String>('shell-page-$index'),
                    offset: Offset((index - _position) * width, 0),
                    child: child,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
