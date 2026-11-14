/// 轻量非阻塞锚定菜单：支持按钮到菜单的无缝容器形变衔接、按住下拉直选、
/// 短菜单指尖滑选与越界橡皮筋回弹，以及外部触控穿透即时关闭。
///
/// 为什么放弃传统的 `PopupRoute`：
///  1. `PopupRoute` 的 `ModalBarrier` 会吃掉第一次外部点击，导致打开菜单后无法
///     直接拖动底部 Dock 栏或滑动课表；
///  2. 改用非阻塞 [OverlayEntry] + 全局指针路由 + [LocalHistoryEntry]（系统返回键），
///     菜单外任意位置手指一落下就会同步启动收起动画，同时原触控/拖动不丢帧直达底层组件；
///  3. 配合 [TactileSurfaceButton]，支持按钮框线形变展开为菜单卡片，也支持“按住按钮
///     下拉不松手”一指连贯滑入菜单预览、松手即选中。
library;

import 'dart:async' show Completer, unawaited;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart'
    show SpringDescription, SpringSimulation, Tolerance;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart' show HapticFeedback;

/// 一项菜单。
class AppMenuItem<T> {
  const AppMenuItem({
    required this.value,
    required this.label,
    this.icon,
    this.trailing,
    this.enabled = true,
    this.selected = false,
  }) : isDivider = false;

  /// 一条分隔线（点击不会有任何结果，手指滑过时会无缝吸附到上方或下方最近可用项）。
  const AppMenuItem.divider()
    : value = null,
      label = '',
      icon = null,
      trailing = null,
      enabled = true,
      selected = false,
      isDivider = true;

  final T? value;
  final String label;
  final IconData? icon;
  final Widget? trailing;
  final bool enabled;
  final bool isDivider;
  final bool selected;
}

/// 全局当前激活的菜单会话：同一时刻最多只存在一个锚定菜单，避免叠层打架。
_ActiveMenuSession? _activeSession;

/// 记录当前正在形变展开/收起的菜单触发器及进度（0..1），让原按钮原地渐隐融入变形。
final ValueNotifier<(RenderObject?, double)> activeAppMenuMorph =
    ValueNotifier<(RenderObject?, double)>((null, 0.0));

/// 长按/下拉交接打开菜单那一刻的全局指针坐标，供 [showAppMenu] 测量后直接定位初始胶囊。
(int, Offset)? activeTactileDragStart;

/// 记录被同一触发按钮按下关闭时的 RenderObject，避免随后的 `onTap` 立即二次打开。
RenderObject? _suppressedTriggerObject;
int? _suppressedPointer;

/// 贴着 [context] 对应的控件展开菜单；选中后回调 [onSelected]。
///
/// [anchorRadius] 用于按钮 → 菜单容器形变衔接的起始圆角半径；
/// [dragPointer] 不为 null 时，菜单会直接接管该手指实现“按住按钮不放下滑直选”。
Future<void> showAppMenu<T>({
  required BuildContext context,
  required List<AppMenuItem<T>> items,
  required ValueChanged<T> onSelected,
  double maxHeight = 380,
  double anchorRadius = 18,
  int? dragPointer,
}) async {
  final box = context.findRenderObject();
  final overlayState = Overlay.of(context, rootOverlay: true);
  final overlayBox = overlayState.context.findRenderObject();
  if (box is! RenderBox || overlayBox is! RenderBox || !box.hasSize) return;

  // 若是同一个触发按钮刚在 PointerDown 被判定收起，本次点击不再重开（实现点一下开、再点一下关）。
  if (dragPointer == null && identical(_suppressedTriggerObject, box)) {
    _suppressedTriggerObject = null;
    _suppressedPointer = null;
    return;
  }
  _suppressedTriggerObject = null;
  _suppressedPointer = null;

  // 若同一按钮对应的菜单正打开着（例如键盘/无障碍直接触发），直接收起。
  final existing = _activeSession;
  if (existing != null &&
      !existing.closing &&
      identical(existing.triggerRenderObject, box)) {
    existing.dismiss();
    return;
  }
  existing?.dismiss();

  final anchor =
      box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  final overlaySize = overlayBox.size;
  final modalRoute = ModalRoute.of(context);

  final completer = Completer<T?>();
  late final _ActiveMenuSession session;
  late final OverlayEntry entry;

  final menuKey = GlobalKey<_AppMenuState<T>>();

  entry = OverlayEntry(
    builder: (_) => _AppMenu<T>(
      key: menuKey,
      session: session,
      items: items,
      maxHeight: maxHeight,
      anchor: anchor,
      anchorRadius: anchorRadius,
      overlaySize: overlaySize,
      dragPointer: dragPointer,
      overlayVsync: overlayState,
      onDismissed: (T? picked) {
        if (!completer.isCompleted) {
          completer.complete(picked);
        }
      },
      onEntryDisposeReady: () {
        session.cleanupEntry();
      },
    ),
  );

  session = _ActiveMenuSession(
    triggerRenderObject: box,
    triggerGlobalRect:
        box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size,
    entry: entry,
    modalRoute: modalRoute,
    onRequestClose: ([Object? result]) {
      menuKey.currentState?.closeWithResult(result as T?);
    },
  );

  _activeSession = session;
  session.attach();
  overlayState.insert(entry);

  final picked = await completer.future;
  if (picked != null) {
    onSelected(picked);
  }
}

class _ActiveMenuSession {
  _ActiveMenuSession({
    required this.triggerRenderObject,
    required this.triggerGlobalRect,
    required this.entry,
    required this.modalRoute,
    required this.onRequestClose,
  });

  final RenderObject triggerRenderObject;
  final Rect triggerGlobalRect;
  final OverlayEntry entry;
  final ModalRoute<dynamic>? modalRoute;
  final void Function([Object? result]) onRequestClose;

  bool closing = false;
  bool cleaned = false;
  LocalHistoryEntry? _historyEntry;
  bool _removingHistory = false;
  _AppMenuState<dynamic>? state;

  void attach() {
    if (modalRoute != null && modalRoute!.isActive) {
      // impliesAppBarDismissal: false —— 只让系统返回键能收起菜单，
      // 不要让 AppBar 因此自动冒出一个左上角返回按钮。
      final localHistory = LocalHistoryEntry(
        impliesAppBarDismissal: false,
        onRemove: () {
          if (_removingHistory || closing) return;
          dismiss();
        },
      );
      _historyEntry = localHistory;
      modalRoute!.addLocalHistoryEntry(localHistory);
    }
  }

  void dismiss([Object? result]) {
    if (closing) return;
    closing = true;
    _removeHistoryEntry();
    onRequestClose(result);
  }

  void _removeHistoryEntry() {
    final history = _historyEntry;
    _historyEntry = null;
    if (history == null) return;
    _removingHistory = true;
    try {
      history.remove();
    } finally {
      _removingHistory = false;
    }
  }

  void cleanupEntry() {
    if (cleaned) return;
    cleaned = true;
    _removeHistoryEntry();
    if (identical(_activeSession, this)) {
      _activeSession = null;
    }
    if (identical(activeAppMenuMorph.value.$1, triggerRenderObject)) {
      activeAppMenuMorph.value = (null, 0.0);
    }
    if (entry.mounted) {
      entry.remove();
    }
  }
}

class _AppMenu<T> extends StatefulWidget {
  const _AppMenu({
    super.key,
    required this.session,
    required this.items,
    required this.maxHeight,
    required this.anchor,
    required this.anchorRadius,
    required this.overlaySize,
    required this.dragPointer,
    required this.overlayVsync,
    required this.onDismissed,
    required this.onEntryDisposeReady,
  });

  final _ActiveMenuSession session;
  final List<AppMenuItem<T>> items;
  final double maxHeight;
  final Rect anchor;
  final double anchorRadius;
  final Size overlaySize;
  final int? dragPointer;
  final TickerProvider overlayVsync;
  final ValueChanged<T?> onDismissed;
  final VoidCallback onEntryDisposeReady;

  @override
  State<_AppMenu<T>> createState() => _AppMenuState<T>();
}

class _AppMenuState<T> extends State<_AppMenu<T>>
    with TickerProviderStateMixin {
  /// 高亮胶囊在菜单项间切换的果冻弹簧：高刚度快响应并保留利落回弹（ζ≈0.68）。
  static const SpringDescription _pillSpring = SpringDescription(
    mass: 1.0,
    stiffness: 1150.0,
    damping: 46.0,
  );

  /// 胶囊出现/隐去及纵向拉伸形变弹簧（ζ≈0.68）。
  static const SpringDescription _presenceSpring = SpringDescription(
    mass: 1.0,
    stiffness: 960.0,
    damping: 42.0,
  );

  /// 容器宽度弹簧：敏捷舒展并带利落微弹（ζ≈0.65）。
  static const SpringDescription _widthSpring = SpringDescription(
    mass: 1.0,
    stiffness: 860.0,
    damping: 38.0,
  );

  /// 容器高度弹簧：略缓于宽度并保留利落微弹（ζ≈0.65）。
  static const SpringDescription _heightSpring = SpringDescription(
    mass: 1.0,
    stiffness: 760.0,
    damping: 36.0,
  );

  static const Tolerance _morphTolerance = Tolerance(
    distance: 1e-3,
    velocity: 1e-2,
  );

  /// 滑出菜单外松手后的整卡橡皮筋回弹弹簧。
  static const SpringDescription _rubberSpring = SpringDescription(
    mass: 1.0,
    stiffness: 880.0,
    damping: 50.0,
  );

  final GlobalKey _restBoxKey = GlobalKey();
  final GlobalKey _menuStackKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = <GlobalKey>[];

  late final AnimationController _openAnim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 200),
    reverseDuration: const Duration(milliseconds: 145),
  );
  late final AnimationController _widthMorph = AnimationController.unbounded(
    vsync: this,
    value: 0.0,
  );
  late final AnimationController _heightMorph = AnimationController.unbounded(
    vsync: this,
    value: 0.0,
  );
  late final AnimationController _pillSlide = AnimationController.unbounded(
    vsync: this,
    value: 1.0,
  );
  late final AnimationController _pillPresence = AnimationController.unbounded(
    vsync: this,
    value: 0.0,
  );
  late final AnimationController _pillStretch = AnimationController.unbounded(
    vsync: this,
    value: 0.0,
  );
  late final AnimationController _pressLift = AnimationController.unbounded(
    vsync: this,
    value: 0.0,
  );
  late final AnimationController _rubberAnim = AnimationController.unbounded(
    vsync: this,
    value: 1.0,
  );

  List<Rect> _itemRects = const <Rect>[];
  Size _menuSize = Size.zero;
  Rect? _targetRect;
  bool _openUp = false;
  bool _alignRight = false;
  bool _isScrollable = false;

  void _syncAnchorMorph() {
    if (!mounted) return;
    activeAppMenuMorph.value = (
      widget.session.triggerRenderObject,
      _openAnim.value.clamp(0.0, 1.0),
    );
  }

  int? _activePointer;
  int? _handoffPointer;
  Offset? _handoffPosition;
  bool _suppressInitialHoverHaptic = false;
  int? _hoveredIndex;
  int? _pressedScrollableIndex;
  bool _committed = false;
  double _pressLiftTarget = 0.0;

  Rect _pillFrom = Rect.zero;
  Rect _pillTo = Rect.zero;
  Offset _rubberFrom = Offset.zero;
  Offset _rubberTarget = Offset.zero;
  final ValueNotifier<Offset> _rubberOffset = ValueNotifier<Offset>(
    Offset.zero,
  );

  bool _globalRouterAttached = false;

  @override
  void initState() {
    super.initState();
    widget.session.state = this;
    _syncKeys();
    _rubberAnim.addListener(_syncRubberOffset);
    _openAnim.addListener(_syncAnchorMorph);
    _attachGlobalPointerRouter();

    if (widget.dragPointer != null) {
      _handoffPointer = widget.dragPointer;
      _activePointer = widget.dragPointer;
      if (activeTactileDragStart?.$1 == widget.dragPointer) {
        _handoffPosition = activeTactileDragStart!.$2;
        activeTactileDragStart = null;
      } else {
        _handoffPosition = widget.anchor.center;
      }
      _suppressInitialHoverHaptic = true;
      // 长按触发瞬间统一下发唯一一次轻触震动，避免后续初次落入菜单项再重复震动。
      _hapticTick();
      _setPressLift(1.0);
    }

    _openAnim.forward();
    unawaited(
      _widthMorph.animateWith(
        SpringSimulation(
          _widthSpring,
          0.0,
          1.0,
          0.0,
          tolerance: _morphTolerance,
        ),
      ),
    );
    unawaited(
      _heightMorph.animateWith(
        SpringSimulation(
          _heightSpring,
          0.0,
          1.0,
          0.0,
          tolerance: _morphTolerance,
        ),
      ),
    );
  }

  void _attachGlobalPointerRouter() {
    if (_globalRouterAttached) return;
    _globalRouterAttached = true;
    GestureBinding.instance.pointerRouter.addGlobalRoute(_handleGlobalPointer);
  }

  void _detachGlobalPointerRouter() {
    if (!_globalRouterAttached) return;
    _globalRouterAttached = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handleGlobalPointer,
    );
  }

  void _handleGlobalPointer(PointerEvent event) {
    if (!mounted) return;

    // 若用户直接触发触发按钮后的释放完成，延迟清理防二次重开标记。
    if (_suppressedPointer == event.pointer &&
        (event is PointerUpEvent || event is PointerCancelEvent)) {
      final releasedPointer = event.pointer;
      Future<void>.microtask(() {
        if (_suppressedPointer == releasedPointer) {
          _suppressedTriggerObject = null;
          _suppressedPointer = null;
        }
      });
    }

    // 处理从触发按钮"按住不放下滑进入菜单"的接管手指。
    if (_handoffPointer != null && event.pointer == _handoffPointer) {
      if (event is PointerMoveEvent) {
        _handoffPosition = event.position;
        _measure();
        _onPointerMove(event);
      } else if (event is PointerUpEvent) {
        _handoffPointer = null;
        _handoffPosition = null;
        _measure();
        _onPointerUp(event);
      } else if (event is PointerCancelEvent) {
        _handoffPointer = null;
        _handoffPosition = null;
        _onPointerCancel(event);
      }
      return;
    }

    // 外部触控即时穿透关闭：当菜单空闲打开时，任何落在菜单外的新按下都同步触发关菜单，
    // 但不拦截该事件，让底层的 Dock / 课表 / 其它按钮在同一手势内立刻响应！
    if (event is PointerDownEvent && !widget.session.closing && !_committed) {
      if (_activePointer != null) return;
      final currentMenuRect = _currentVisualMenuRect;
      if (currentMenuRect.contains(event.position)) {
        return;
      }
      if (widget.session.triggerGlobalRect.contains(event.position)) {
        _suppressedTriggerObject = widget.session.triggerRenderObject;
        _suppressedPointer = event.pointer;
      }
      widget.session.dismiss();
    }
  }

  Rect _morphedCardRect(Rect target) {
    final wx = _widthMorph.value.clamp(0.0, 1.15);
    final hy = _heightMorph.value.clamp(0.0, 1.15);
    return Rect.fromLTRB(
      lerpDouble(widget.anchor.left, target.left, wx) ?? target.left,
      lerpDouble(widget.anchor.top, target.top, hy) ?? target.top,
      lerpDouble(widget.anchor.right, target.right, wx) ?? target.right,
      lerpDouble(widget.anchor.bottom, target.bottom, hy) ?? target.bottom,
    );
  }

  Rect get _currentVisualMenuRect {
    final target = _targetRect;
    if (target == null) return widget.anchor;
    return _morphedCardRect(target).shift(_rubberOffset.value);
  }

  void _syncRubberOffset() {
    _rubberOffset.value =
        Offset.lerp(_rubberFrom, _rubberTarget, _rubberAnim.value) ??
        _rubberTarget;
  }

  @override
  void didUpdateWidget(_AppMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _syncKeys();
      _itemRects = const <Rect>[];
      _targetRect = null;
    }
  }

  @override
  void dispose() {
    _detachGlobalPointerRouter();
    _openAnim.removeListener(_syncAnchorMorph);
    final triggerRo = widget.session.triggerRenderObject;
    if (identical(activeAppMenuMorph.value.$1, triggerRo)) {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        Future<void>.microtask(() {
          if (identical(activeAppMenuMorph.value.$1, triggerRo)) {
            activeAppMenuMorph.value = (null, 0.0);
          }
        });
      } else {
        activeAppMenuMorph.value = (null, 0.0);
      }
    }
    if (identical(_activeSession?.state, this)) {
      _activeSession?.state = null;
      _activeSession = null;
    }
    _rubberAnim.removeListener(_syncRubberOffset);
    _rubberOffset.dispose();
    _scrollController.dispose();
    _openAnim.dispose();
    _widthMorph.dispose();
    _heightMorph.dispose();
    _pillSlide.dispose();
    _pillPresence.dispose();
    _pillStretch.dispose();
    _pressLift.dispose();
    _rubberAnim.dispose();
    super.dispose();
  }

  void _syncKeys() {
    _itemKeys
      ..clear()
      ..addAll(<GlobalKey>[
        for (var i = 0; i < widget.items.length; i++)
          GlobalKey(debugLabel: 'menu-item-$i'),
      ]);
  }

  Rect _computeTargetRect(Size menuSize) {
    const margin = 8.0;
    final screen = widget.overlaySize;
    final maxX = math.max(margin, screen.width - menuSize.width - margin);
    final alignRight = widget.anchor.center.dx > screen.width * 0.5;
    _alignRight = alignRight;
    final x =
        (alignRight ? widget.anchor.right - menuSize.width : widget.anchor.left)
            .clamp(margin, maxX);

    // 原位覆合生长：卡片与触发按钮角点对齐并原地长出，而非孤立悬在下方。
    var y = widget.anchor.top;
    var openUp = false;
    if (y + menuSize.height > screen.height - margin) {
      final above = widget.anchor.bottom - menuSize.height;
      if (above >= margin) {
        y = above;
        openUp = true;
      } else {
        y = math.max(margin, screen.height - menuSize.height - margin);
      }
    }
    _openUp = openUp;
    return Offset(x, y) & menuSize;
  }

  void _measure() {
    if (!mounted) return;
    final stackBox = _menuStackKey.currentContext?.findRenderObject();
    if (stackBox is! RenderBox || !stackBox.hasSize) return;
    final rects = <Rect>[];
    for (final key in _itemKeys) {
      final itemRender = key.currentContext?.findRenderObject();
      if (itemRender is! RenderBox || !itemRender.hasSize) return;
      rects.add(
        itemRender.localToGlobal(Offset.zero, ancestor: stackBox) &
            itemRender.size,
      );
    }
    final scrollable =
        _scrollController.hasClients &&
        _scrollController.position.maxScrollExtent > 1.0;

    final clampedSize = Size(
      stackBox.size.width.clamp(0.0, widget.overlaySize.width - 16.0),
      stackBox.size.height.clamp(0.0, widget.maxHeight),
    );
    final computedTarget = _computeTargetRect(clampedSize);
    final targetChanged =
        _targetRect == null ||
        (_targetRect!.left - computedTarget.left).abs() > 0.5 ||
        (_targetRect!.top - computedTarget.top).abs() > 0.5 ||
        (_targetRect!.width - computedTarget.width).abs() > 0.5 ||
        (_targetRect!.height - computedTarget.height).abs() > 0.5;

    final sizeChanged =
        (clampedSize.width - _menuSize.width).abs() > 0.5 ||
        (clampedSize.height - _menuSize.height).abs() > 0.5;
    if (!sizeChanged &&
        !targetChanged &&
        scrollable == _isScrollable &&
        _sameRects(rects, _itemRects)) {
      return;
    }
    final needRebuildForLayout = _targetRect == null || targetChanged;
    _menuSize = clampedSize;
    _targetRect = computedTarget;
    _itemRects = rects;
    _isScrollable = scrollable;
    final hovered = _hoveredIndex;
    if (hovered != null && hovered >= 0 && hovered < _itemRects.length) {
      final updatedTarget = _itemRects[hovered];
      if (_pillTo != updatedTarget) {
        _pillTo = updatedTarget;
        if (!_pillSlide.isAnimating) {
          _pillFrom = updatedTarget;
        }
      }
    }
    var hoverInitialized = false;
    if (_handoffPointer != null &&
        _hoveredIndex == null &&
        !_isScrollable &&
        _handoffPosition != null) {
      final local = _toMenuLocal(_handoffPosition!);
      final initialHit = local != null ? _hitSelectableIndex(local) : null;
      if (initialHit != null) {
        _suppressInitialHoverHaptic = false;
        _hoveredIndex = initialHit;
        _showPillAt(_itemRects[initialHit], immediate: true);
        hoverInitialized = true;
      }
    }
    if ((needRebuildForLayout || hoverInitialized) && mounted) {
      setState(() {});
    }
  }

  static bool _sameRects(List<Rect> a, List<Rect> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if ((a[i].left - b[i].left).abs() > 0.5 ||
          (a[i].top - b[i].top).abs() > 0.5 ||
          (a[i].width - b[i].width).abs() > 0.5 ||
          (a[i].height - b[i].height).abs() > 0.5) {
        return false;
      }
    }
    return true;
  }

  Rect get _currentPillRect {
    final t = _pillSlide.value;
    if (_pillFrom.isEmpty) return _pillTo;
    return Rect.lerp(_pillFrom, _pillTo, t) ?? _pillTo;
  }

  void _showPillAt(Rect target, {required bool immediate}) {
    if (immediate) {
      _pillSlide.stop();
      _pillSlide.value = 1.0;
      _pillFrom = target;
      _pillTo = target;
    } else {
      final current = _currentPillRect;
      final travel = (target.center.dy - current.center.dy).abs();
      _pillFrom = current;
      _pillTo = target;
      _pillSlide.animateWith(SpringSimulation(_pillSpring, 0.0, 1.0, 0.0));
      final stretchPeak = (travel / 52.0).clamp(0.0, 1.0);
      if (stretchPeak > 0.05) {
        _pillStretch.animateWith(
          SpringSimulation(_presenceSpring, stretchPeak, 0.0, 0.0),
        );
      }
    }
    _pillPresence.animateWith(
      SpringSimulation(_presenceSpring, _pillPresence.value, 1.0, 0.0),
    );
  }

  void _hidePill() {
    if (_pillPresence.value <= 0.001 && !_pillPresence.isAnimating) return;
    _pillPresence.animateWith(
      SpringSimulation(_presenceSpring, _pillPresence.value, 0.0, 0.0),
    );
  }

  void _setPressLift(double target) {
    final alreadyAtTarget =
        !_pressLift.isAnimating && (target - _pressLift.value).abs() < 0.005;
    final alreadyHeadingToTarget =
        _pressLift.isAnimating && (_pressLiftTarget - target).abs() < 0.001;
    if (alreadyAtTarget || alreadyHeadingToTarget) return;
    _pressLiftTarget = target;
    if ((target - _pressLift.value).abs() < 0.005) {
      _pressLift.stop();
      _pressLift.value = target;
      return;
    }
    _pressLift.animateWith(
      SpringSimulation(_presenceSpring, _pressLift.value, target, 0.0),
    );
  }

  void _setRubberDirect(Offset offset) {
    _rubberAnim.stop();
    _rubberOffset.value = offset;
  }

  void _springRubberHome() {
    final current = _rubberOffset.value;
    if (current.distance < 0.1) {
      _setRubberDirect(Offset.zero);
      return;
    }
    _rubberFrom = current;
    _rubberTarget = Offset.zero;
    _rubberAnim.animateWith(SpringSimulation(_rubberSpring, 0.0, 1.0, 0.0));
  }

  void _hapticTick() {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  Offset? _toMenuLocal(Offset globalPosition) {
    final target = _targetRect;
    if (target == null) return null;
    // 直接按未缩放的目标菜单坐标映射，避免展开形变动画期间 Transform.scale 把坐标放大，
    // 导致静止/初移手指误命中下方菜单项后再一路滑回上方。
    final overlayBox = Overlay.of(
      context,
      rootOverlay: true,
    ).context.findRenderObject();
    final inOverlay = overlayBox is RenderBox && overlayBox.hasSize
        ? overlayBox.globalToLocal(globalPosition)
        : globalPosition;
    final scrollY = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    return inOverlay -
        target.topLeft -
        _rubberOffset.value +
        Offset(0, scrollY);
  }

  int? _nearestSelectable(int around, {required bool preferAbove}) {
    if (preferAbove) {
      for (var i = around - 1; i >= 0; i--) {
        if (!widget.items[i].isDivider && widget.items[i].enabled) return i;
      }
      for (var i = around + 1; i < widget.items.length; i++) {
        if (!widget.items[i].isDivider && widget.items[i].enabled) return i;
      }
    } else {
      for (var i = around + 1; i < widget.items.length; i++) {
        if (!widget.items[i].isDivider && widget.items[i].enabled) return i;
      }
      for (var i = around - 1; i >= 0; i--) {
        if (!widget.items[i].isDivider && widget.items[i].enabled) return i;
      }
    }
    return null;
  }

  int? _hitSelectableIndex(Offset local) {
    if (_menuSize.isEmpty || _itemRects.length != widget.items.length) {
      return null;
    }
    if (local.dx < 0 ||
        local.dx > _menuSize.width ||
        local.dy < 0 ||
        local.dy > _menuSize.height) {
      return null;
    }
    for (var i = 0; i < _itemRects.length; i++) {
      final rect = _itemRects[i];
      if (!rect.contains(local)) continue;
      final item = widget.items[i];
      if (item.isDivider) {
        // 跨分割线时按纵坐标中线无缝吸附上方或下方菜单项，滑动胶囊不闪烁、不中断。
        return _nearestSelectable(i, preferAbove: local.dy < rect.center.dy);
      }
      if (!item.enabled) return null;
      return i;
    }
    return null;
  }

  static double _rubberDelta(double delta, double maxPull) {
    if (delta == 0) return 0;
    return delta.sign * maxPull * (1.0 - math.exp(-delta.abs() / 48.0));
  }

  void _updateHoverState(int? nextIndex, {required bool hapticOnSwitch}) {
    if (nextIndex == _hoveredIndex) return;
    final wasNull = _hoveredIndex == null;
    setState(() => _hoveredIndex = nextIndex);
    if (nextIndex != null) {
      final shouldHaptic = hapticOnSwitch && !_suppressInitialHoverHaptic;
      _suppressInitialHoverHaptic = false;
      if (shouldHaptic) _hapticTick();
      _showPillAt(_itemRects[nextIndex], immediate: wasNull);
    } else {
      _hidePill();
    }
  }

  void _commitSelection(int index) {
    if (_committed || !mounted) return;
    final item = widget.items[index];
    if (item.isDivider || !item.enabled) return;
    _committed = true;
    widget.session.dismiss(item.value);
  }

  void closeWithResult(T? picked) {
    if (!mounted) {
      widget.onDismissed(picked);
      widget.onEntryDisposeReady();
      return;
    }
    _committed = true;
    _detachGlobalPointerRouter();
    widget.onDismissed(picked);
    unawaited(
      _widthMorph.animateTo(
        0.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeInCubic,
      ),
    );
    unawaited(
      _heightMorph.animateTo(
        0.0,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeInCubic,
      ),
    );
    _openAnim.reverse().whenCompleteOrCancel(() {
      widget.onEntryDisposeReady();
    });
  }

  void _onPointerDown(PointerDownEvent event) {
    if (_committed) return;
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryButton == 0)) {
      return;
    }
    _measure();
    final local = _toMenuLocal(event.position);
    if (local == null) return;

    _activePointer = event.pointer;
    _setPressLift(1.0);
    if (_isScrollable || _itemRects.length != widget.items.length) return;
    final hit = _hitSelectableIndex(local);
    _setRubberDirect(Offset.zero);
    _updateHoverState(hit, hapticOnSwitch: hit != null);
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointer != event.pointer || _committed || _isScrollable) return;
    final local = _toMenuLocal(event.position);
    if (local == null || _menuSize.isEmpty) return;

    final inside =
        local.dx >= 0 &&
        local.dx <= _menuSize.width &&
        local.dy >= 0 &&
        local.dy <= _menuSize.height;

    if (inside) {
      _setRubberDirect(Offset.zero);
      _setPressLift(1.0);
      final hit = _hitSelectableIndex(local);
      final isTouch =
          event.kind == PointerDeviceKind.touch ||
          event.kind == PointerDeviceKind.stylus;
      _updateHoverState(hit, hapticOnSwitch: isTouch && hit != null);
      return;
    }

    // 从触发按钮按住下拉/上拉进入菜单途中，手指仍在按钮与菜单之间的缝隙时先不施加上拉橡皮筋，保持展开稳定。
    final inAnchorGap = _openUp
        ? local.dy > _menuSize.height && local.dy <= _menuSize.height + 24
        : local.dy < 0 && local.dy >= -24;
    if (_handoffPointer == event.pointer &&
        _hoveredIndex == null &&
        inAnchorGap &&
        local.dx >= -14 &&
        local.dx <= _menuSize.width + 14) {
      return;
    }

    // 滑出菜单边界：取消任何候选高亮（松手也不选不关），并对整卡施加微橡皮筋张力跟随动效。
    _updateHoverState(null, hapticOnSwitch: false);
    final ox = local.dx < 0
        ? local.dx
        : (local.dx > _menuSize.width ? local.dx - _menuSize.width : 0.0);
    final oy = local.dy < 0
        ? local.dy
        : (local.dy > _menuSize.height ? local.dy - _menuSize.height : 0.0);
    _setRubberDirect(Offset(_rubberDelta(ox, 8.0), _rubberDelta(oy, 10.0)));
    // 移出菜单范围后仍保持按住放大态，松手时再统一回弹。
    _setPressLift(1.0);
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    final picked = _hoveredIndex;
    _springRubberHome();
    _setPressLift(0.0);
    if (_isScrollable) return;
    if (picked != null) {
      _commitSelection(picked);
      return;
    }
    // 在菜单外部或从触发按钮按住没滑到任何菜单项就松手：保持菜单打开，弹性复位。
    _updateHoverState(null, hapticOnSwitch: false);
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_activePointer != event.pointer) return;
    _activePointer = null;
    _springRubberHome();
    _setPressLift(0.0);
    _updateHoverState(null, hapticOnSwitch: false);
  }

  void _onMouseHover(PointerEvent event) {
    if (_activePointer != null || _isScrollable || _committed) return;
    _measure();
    if (_isScrollable || _itemRects.length != widget.items.length) return;
    final local = _toMenuLocal(event.position);
    if (local == null) return;
    _updateHoverState(_hitSelectableIndex(local), hapticOnSwitch: false);
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerTheme;
    final scheme = Theme.of(context).colorScheme;
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

    final menuStack = Stack(
      key: _menuStackKey,
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: AnimatedBuilder(
              animation: Listenable.merge(<Listenable>[
                _pillSlide,
                _pillPresence,
                _pillStretch,
              ]),
              builder: (context, _) {
                final presence = _pillPresence.value.clamp(0.0, 1.0);
                if (presence <= 0.001 || _pillTo.isEmpty) {
                  return const SizedBox.shrink();
                }
                final rect = _currentPillRect;
                if (rect.isEmpty) {
                  return const SizedBox.shrink();
                }
                final stretch = _pillStretch.value.clamp(0.0, 1.0);
                final scale = 0.90 + 0.10 * presence;
                final insetRect = Rect.fromLTRB(
                  rect.left + 6,
                  rect.top + 2,
                  rect.right - 6,
                  rect.bottom - 2,
                );
                final stretched = Rect.fromCenter(
                  center: insetRect.center,
                  width: insetRect.width * scale * (1 - 0.025 * stretch),
                  height: insetRect.height * scale * (1 + 0.12 * stretch),
                );
                return CustomPaint(
                  painter: _MenuPillPainter(
                    rect: stretched,
                    color: scheme.primary.withValues(alpha: 0.11 * presence),
                    rimColor: scheme.primary.withValues(alpha: 0.18 * presence),
                  ),
                );
              },
            ),
          ),
        ),
        AnimatedBuilder(
          animation: _openAnim,
          builder: (context, _) {
            final t = _openAnim.value.clamp(0.0, 1.0);
            return ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 168.0),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (var i = 0; i < widget.items.length; i++)
                      _buildStaggeredItem(divider, i, t),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );

    final innerContent = ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: math.max(168.0, widget.overlaySize.width - 16.0),
        maxHeight: widget.maxHeight,
      ),
      child: SingleChildScrollView(
        controller: _scrollController,
        child: IntrinsicWidth(child: menuStack),
      ),
    );

    // 首次布局前（_targetRect 尚未算好）：放到无边距定位位置透明测出真实尺寸，
    // 第二帧起即可从按钮外框（anchor）精确容器形变展开，且零跳变。
    final targetRect = _targetRect;
    if (targetRect == null) {
      return Positioned.fill(
        child: IgnorePointer(
          child: Opacity(
            opacity: 0.0,
            child: CustomSingleChildLayout(
              delegate: _FallbackMeasureLayout(anchor: widget.anchor),
              child: KeyedSubtree(
                key: _restBoxKey,
                child: Material(
                  color: scheme.surfaceContainerLowest,
                  surfaceTintColor: Colors.transparent,
                  borderRadius: BorderRadius.circular(20),
                  child: innerContent,
                ),
              ),
            ),
          ),
        ),
      );
    }

    final alignY = _openUp ? 1.0 : -1.0;
    final alignX = _alignRight ? 1.0 : -1.0;
    final align = Alignment(alignX, alignY);

    final shellFade = CurvedAnimation(
      parent: _openAnim,
      curve: const Interval(0.0, 0.18, curve: Curves.easeOut),
      reverseCurve: const Interval(0.0, 0.30, curve: Curves.easeIn),
    );

    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          AnimatedBuilder(
            animation: Listenable.merge(<Listenable>[
              _openAnim,
              _widthMorph,
              _heightMorph,
              _pressLift,
              _rubberOffset,
            ]),
            builder: (context, child) {
              final morphValue = (_widthMorph.value + _heightMorph.value) * 0.5;
              final morphClamped = morphValue.clamp(0.0, 1.0);
              final startScale =
                  (widget.anchor.shortestSide /
                          math.max(1.0, targetRect.shortestSide))
                      .clamp(0.22, 0.45);
              final openScale = lerpDouble(startScale, 1.0, morphValue) ?? 1.0;
              final liftSpan =
                  (0.05 + 6.0 / math.max(120.0, targetRect.longestSide)).clamp(
                    0.065,
                    0.095,
                  );
              final interactiveScale = 1.0 + liftSpan * _pressLift.value;
              final totalScale = math.max(0.01, openScale * interactiveScale);
              final rubber = _rubberOffset.value;

              Widget card = Material(
                color: scheme.surfaceContainerLowest,
                surfaceTintColor: Colors.transparent,
                elevation: 8 * morphClamped,
                shadowColor: Colors.black.withValues(alpha: 0.16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                  side: BorderSide(
                    color: scheme.outlineVariant.withValues(
                      alpha: 0.36 - 0.14 * morphClamped,
                    ),
                    width: 1.0,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: SizedBox(
                  width: targetRect.width,
                  height: targetRect.height,
                  child: child,
                ),
              );

              card = Transform.translate(
                offset: rubber,
                child: Transform.scale(
                  alignment: align,
                  scale: totalScale,
                  child: card,
                ),
              );

              return Positioned(
                left: targetRect.left,
                top: targetRect.top,
                width: targetRect.width,
                height: targetRect.height,
                child: FadeTransition(
                  opacity: shellFade,
                  child: KeyedSubtree(
                    key: _restBoxKey,
                    child: MouseRegion(
                      onHover: _onMouseHover,
                      onExit: (_) {
                        if (_activePointer == null) {
                          _updateHoverState(null, hapticOnSwitch: false);
                        }
                      },
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerDown: _onPointerDown,
                        onPointerMove: _onPointerMove,
                        onPointerUp: _onPointerUp,
                        onPointerCancel: _onPointerCancel,
                        child: card,
                      ),
                    ),
                  ),
                ),
              );
            },
            child: innerContent,
          ),
        ],
      ),
    );
  }

  /// 单项错峰浮现：在容器展开后依序利落滑入，任意时刻反转均可无跳变回退。
  Widget _buildStaggeredItem(DividerThemeData divider, int index, double t) {
    final item = widget.items[index];
    final step = index < 6 ? index : 6;
    final start = 0.05 + step * 0.035;
    final end = math.min(1.0, start + 0.42);
    final raw = ((t - start) / math.max(0.01, end - start)).clamp(0.0, 1.0);
    final itemT = t >= 1.0 ? 1.0 : Curves.easeOutCubic.transform(raw);

    final Widget child;
    if (item.isDivider) {
      final baseColor = divider.color;
      child = Divider(
        height: 1,
        thickness: divider.thickness,
        color: baseColor == null || itemT >= 1.0
            ? baseColor
            : baseColor.withValues(alpha: baseColor.a * itemT),
      );
    } else {
      child = _MenuTile<T>(
        item: item,
        hovered: _hoveredIndex == index || _pressedScrollableIndex == index,
        opacity: itemT,
        onTap: () => _commitSelection(index),
        onPressChanged: (pressed) {
          if (!_isScrollable || !mounted) return;
          setState(() {
            _pressedScrollableIndex = pressed ? index : null;
          });
        },
      );
    }

    return KeyedSubtree(key: _itemKeys[index], child: child);
  }
}

class _FallbackMeasureLayout extends SingleChildLayoutDelegate {
  _FallbackMeasureLayout({required this.anchor});
  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(168.0, constraints.maxWidth - 16),
        maxHeight: math.max(120.0, constraints.maxHeight - 16),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset.zero;

  @override
  bool shouldRelayout(covariant _FallbackMeasureLayout oldDelegate) =>
      oldDelegate.anchor != anchor;
}

class _MenuPillPainter extends CustomPainter {
  _MenuPillPainter({
    required this.rect,
    required this.color,
    required this.rimColor,
  });

  final Rect rect;
  final Color color;
  final Color rimColor;

  @override
  void paint(Canvas canvas, Size size) {
    // 外层菜单圆角 20dp，胶囊四边统一距外框 6dp，同心圆角取 20 - 6 = 14dp。
    final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(14));
    canvas.drawRRect(rrect, Paint()..color = color);
    if (rimColor.a > 0) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = rimColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MenuPillPainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.color != color ||
      oldDelegate.rimColor != rimColor;
}

class _MenuTile<T> extends StatelessWidget {
  const _MenuTile({
    super.key,
    required this.item,
    required this.hovered,
    required this.opacity,
    required this.onTap,
    required this.onPressChanged,
  });

  final AppMenuItem<T> item;
  final bool hovered;
  final double opacity;
  final VoidCallback onTap;
  final ValueChanged<bool> onPressChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final highlighted = item.selected || hovered;
    final baseColor = !item.enabled
        ? theme.hintColor
        : highlighted
        ? scheme.primary
        : scheme.onSurface;
    final baseIconColor = item.enabled
        ? (highlighted ? scheme.primary : scheme.onSurfaceVariant)
        : theme.hintColor;
    final color = opacity >= 1.0
        ? baseColor
        : baseColor.withValues(alpha: baseColor.a * opacity);
    final iconColor = opacity >= 1.0
        ? baseIconColor
        : baseIconColor.withValues(alpha: baseIconColor.a * opacity);
    final fontWeight = highlighted ? FontWeight.w600 : FontWeight.normal;
    return InkWell(
      // 彻底屏蔽旧版 Material 水波纹与灰底阴影，仅留无障碍与可测试句柄，高亮全权交给滑动胶囊。
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: Colors.transparent,
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      onTapDown: item.enabled ? (_) => onPressChanged(true) : null,
      onTapCancel: item.enabled ? () => onPressChanged(false) : null,
      onTap: item.enabled
          ? () {
              onPressChanged(false);
              onTap();
            }
          : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Align(
          alignment: Alignment.centerLeft,
          widthFactor: 1.0,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                if (item.icon != null) ...<Widget>[
                  Transform.scale(
                    scale: hovered ? 1.08 : 1.0,
                    child: Icon(item.icon, size: 18, color: iconColor),
                  ),
                  const SizedBox(width: 12),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontWeight: fontWeight,
                    ),
                  ),
                ),
                if (item.trailing != null) ...<Widget>[
                  const SizedBox(width: 16),
                  Opacity(opacity: opacity, child: item.trailing!),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
