/// 轻量选择性遮罩锚定菜单：支持按钮到菜单的无缝容器形变衔接、按住下拉直选、
/// 短菜单指尖滑选与越界橡皮筋回弹，以及“点菜单外即关闭、唯有 Dock 栏可直达切页”。
///
/// 为什么用自定义 [OverlayEntry] 选择性遮罩而不直接用 `PopupRoute`：
///  1. 传统的 `PopupRoute` `ModalBarrier` 会吃掉全部外部点击，打开菜单后想直接点击或
///     拖动底部 [FloatingDock] 切页时必须先点一次空白关闭菜单，再点一次 Dock；
///  2. 这里在 [OverlayEntry] 底层铺设选择性命中遮罩：菜单外除 [FloatingDock] 之外的
///     一切区域（课表卡片、翻周手势、其它按钮等）一律拦截触控并只关闭菜单，不穿透触发；
///  3. 唯有与当前路由同属一页的 [FloatingDock] 保持最高优先级，在命中测试中放行直达
///     Dock 翻页并同步启动菜单收起动画；同时保留 [LocalHistoryEntry] 支持系统返回键关闭。
library;

import 'dart:async' show Completer, unawaited;
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart'
    show
        TargetPlatform,
        ValueListenable,
        defaultTargetPlatform,
        visibleForTesting;
import 'package:flutter/gestures.dart'
    show GestureBinding, PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart'
    show SpringDescription, SpringSimulation, Tolerance;
import 'package:flutter/rendering.dart'
    show
        BoxHitTestEntry,
        BoxHitTestResult,
        ClipRRectLayer,
        LayerHandle,
        OpacityLayer,
        PaintingContext,
        PipelineOwner,
        RenderProxyBox,
        TransformLayer;
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/services.dart' show HapticFeedback;

import 'floating_dock.dart' show FloatingDock;

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

/// 贴着 [context] 对应的控件展开菜单；选中后回调 [onSelected]。
///
/// [anchorRadius] 用于按钮 → 菜单容器形变衔接的起始圆角半径；
/// [dragPointer] 不为 null 时，菜单会直接接管该手指实现“按住按钮不放下滑直选”；
/// [centerHorizontally] 为 true 时，菜单水平方向以触发按钮中轴线对齐并向下展开；
/// [minWidth] 指定菜单最小宽度；[centerItems] 为 true 时菜单文字水平居中对齐。
Future<void> showAppMenu<T>({
  required BuildContext context,
  required List<AppMenuItem<T>> items,
  required ValueChanged<T> onSelected,
  double maxHeight = 380,
  double anchorRadius = 18,
  double minWidth = 168.0,
  int? dragPointer,
  bool centerHorizontally = false,
  bool centerItems = false,
}) async {
  final box = context.findRenderObject();
  final overlayState = Overlay.of(context, rootOverlay: true);
  final overlayBox = overlayState.context.findRenderObject();
  if (box is! RenderBox || overlayBox is! RenderBox || !box.hasSize) return;

  // 若同一按钮对应的菜单正打开着（例如键盘/无障碍直接触发），直接收起。
  final existing = _activeSession;
  if (existing != null &&
      !existing.closing &&
      identical(existing.triggerRenderObject, box)) {
    existing.dismiss();
    return;
  }
  _ActiveMenuSession? handoffClosingSession;
  if (existing != null) {
    if (existing.closing &&
        identical(existing.triggerRenderObject, box) &&
        existing.state != null &&
        existing.state!.mounted &&
        existing.state!._targetRect != null) {
      handoffClosingSession = existing;
    } else {
      existing.dismiss();
      existing.cleanupEntry();
    }
  }

  final anchor =
      box.localToGlobal(Offset.zero, ancestor: overlayBox) & box.size;
  final overlaySize = overlayBox.size;
  final modalRoute = ModalRoute.of(context);

  final completer = Completer<T?>();
  late final _ActiveMenuSession session;
  late final OverlayEntry entry;

  final menuKey = GlobalKey<_AppMenuState<T>>();
  Widget? cachedMenu;

  entry = OverlayEntry(
    builder: (_) => cachedMenu ??= _AppMenu<T>(
      key: menuKey,
      session: session,
      previousClosingSession: handoffClosingSession,
      items: items,
      maxHeight: maxHeight,
      anchor: anchor,
      anchorRadius: anchorRadius,
      minWidth: minWidth,
      overlaySize: overlaySize,
      dragPointer: dragPointer,
      centerHorizontally: centerHorizontally,
      centerItems: centerItems,
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
    entry: entry,
    modalRoute: modalRoute,
    pendingDragPointer: dragPointer,
    onRequestClose: ([Object? result]) {
      final state = menuKey.currentState;
      if (state != null) {
        state.closeWithResult(result as T?);
      } else {
        if (!completer.isCompleted) {
          completer.complete(result as T?);
        }
        session.cleanupEntry();
      }
    },
  );

  _activeSession = session;
  if (handoffClosingSession == null) {
    activeAppMenuMorph.value = (box, 0.0);
  }
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
    required this.entry,
    required this.modalRoute,
    required this.onRequestClose,
    this.pendingDragPointer,
  });

  final RenderObject triggerRenderObject;
  final OverlayEntry entry;
  final ModalRoute<dynamic>? modalRoute;
  final void Function([Object? result]) onRequestClose;
  final int? pendingDragPointer;

  bool closing = false;
  bool cleaned = false;
  bool dragPointerEnded = false;
  bool _pendingDragAttached = false;
  LocalHistoryEntry? _historyEntry;
  bool _removingHistory = false;
  _AppMenuState<dynamic>? state;

  void attach() {
    if (pendingDragPointer != null && !_pendingDragAttached) {
      _pendingDragAttached = true;
      GestureBinding.instance.pointerRouter.addGlobalRoute(
        _handlePendingDragPointer,
      );
    }
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

  void _handlePendingDragPointer(PointerEvent event) {
    if (event.pointer != pendingDragPointer) return;
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      dragPointerEnded = true;
      detachPendingDragListener();
    }
  }

  void detachPendingDragListener() {
    if (!_pendingDragAttached) return;
    _pendingDragAttached = false;
    GestureBinding.instance.pointerRouter.removeGlobalRoute(
      _handlePendingDragPointer,
    );
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
    detachPendingDragListener();
    _removeHistoryEntry();
    if (identical(_activeSession, this)) {
      _activeSession = null;
      if (identical(activeAppMenuMorph.value.$1, triggerRenderObject)) {
        activeAppMenuMorph.value = (null, 0.0);
      }
    } else if (_activeSession == null &&
        identical(activeAppMenuMorph.value.$1, triggerRenderObject)) {
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
    this.previousClosingSession,
    required this.items,
    required this.maxHeight,
    required this.anchor,
    required this.anchorRadius,
    required this.minWidth,
    required this.overlaySize,
    required this.dragPointer,
    required this.centerHorizontally,
    required this.centerItems,
    required this.overlayVsync,
    required this.onDismissed,
    required this.onEntryDisposeReady,
  });

  final _ActiveMenuSession session;
  final _ActiveMenuSession? previousClosingSession;
  final List<AppMenuItem<T>> items;
  final double maxHeight;
  final Rect anchor;
  final double anchorRadius;
  final double minWidth;
  final Size overlaySize;
  final int? dragPointer;
  final bool centerHorizontally;
  final bool centerItems;
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

  /// 容器展开宽度弹簧：略先于高度舒展并带灵动微弹（ζ≈0.66，~325ms 收敛）。
  static const SpringDescription _widthSpring = SpringDescription(
    mass: 1.0,
    stiffness: 960.0,
    damping: 41.0,
  );

  /// 容器展开高度弹簧：带惯性跟进并保留统一微弹（ζ≈0.65，~345ms 收敛）。
  static const SpringDescription _heightSpring = SpringDescription(
    mass: 1.0,
    stiffness: 820.0,
    damping: 37.5,
  );

  static const Tolerance _morphTolerance = Tolerance(
    distance: 4e-3,
    velocity: 4e-2,
  );

  /// 容器收起弹簧：与展开同源的双轴容器形变逻辑，保留余速惯性与轻盈缓冲收敛（ζ≈0.91，~160ms 收敛）。
  static const SpringDescription _widthCloseSpring = SpringDescription(
    mass: 1.0,
    stiffness: 1650.0,
    damping: 74.0,
  );

  static const SpringDescription _heightCloseSpring = SpringDescription(
    mass: 1.0,
    stiffness: 1900.0,
    damping: 80.0,
  );

  static const Tolerance _closeMorphTolerance = Tolerance(
    distance: 8e-3,
    velocity: 1e-1,
  );

  /// 滑出菜单外松手后的整卡橡皮筋回弹弹簧。
  static const SpringDescription _rubberSpring = SpringDescription(
    mass: 1.0,
    stiffness: 880.0,
    damping: 50.0,
  );

  final GlobalKey _morphBoxKey = GlobalKey();
  final GlobalKey _cardHitKey = GlobalKey();
  final GlobalKey _menuStackKey = GlobalKey();
  final ScrollController _scrollController = ScrollController();
  final List<GlobalKey> _itemKeys = <GlobalKey>[];

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
  late final Listenable _pillListenable = Listenable.merge(<Listenable>[
    _pillSlide,
    _pillPresence,
    _pillStretch,
  ]);
  late final Listenable _morphGeometryListenable = Listenable.merge(
    <Listenable>[_widthMorph, _heightMorph],
  );
  late final Listenable _cardMorphListenable = Listenable.merge(<Listenable>[
    _widthMorph,
    _heightMorph,
    _pressLift,
    _rubberOffset,
  ]);

  List<Rect> _itemRects = const <Rect>[];
  Size _menuSize = Size.zero;
  Rect? _targetRect;
  bool _openUp = false;
  double _alignX = -1.0;
  bool _isScrollable = false;
  bool _needsMeasure = true;
  final ValueNotifier<int?> _highlightedIndex = ValueNotifier<int?>(null);

  double _closePeakMorph = 1.0;

  double get _rawMorphProgress =>
      ((_widthMorph.value + _heightMorph.value) * 0.5).clamp(0.0, 1.0);

  double _effectiveFadeMorph() {
    final raw = _rawMorphProgress;
    if (!_closing) return raw;
    if (raw < _closePeakMorph) {
      _closePeakMorph = raw;
    }
    return _closePeakMorph;
  }

  void _syncAnchorMorph() {
    if (!mounted || !identical(_activeSession, widget.session)) return;
    activeAppMenuMorph.value = (
      widget.session.triggerRenderObject,
      _effectiveFadeMorph(),
    );
  }

  int? _activePointer;
  int? _handoffPointer;
  Offset? _handoffPosition;
  bool _suppressInitialHoverHaptic = false;
  int? _hoveredIndex;
  int? _pressedScrollableIndex;
  bool _committed = false;
  bool _closing = false;
  bool _disposed = false;
  _ActiveMenuSession? _pendingPreviousClosing;
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
    widget.session.detachPendingDragListener();
    _syncKeys();
    _rubberAnim.addListener(_syncRubberOffset);
    _morphGeometryListenable.addListener(_syncAnchorMorph);
    _attachGlobalPointerRouter();

    if (widget.dragPointer != null && !widget.session.dragPointerEnded) {
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
    } else if (widget.dragPointer != null &&
        activeTactileDragStart?.$1 == widget.dragPointer) {
      activeTactileDragStart = null;
    }

    _pendingPreviousClosing = widget.previousClosingSession;
    if (_pendingPreviousClosing == null) {
      _startOpenSprings(0.0, 0.0, 0.0, 0.0);
    }
  }

  void _startOpenSprings(
    double fromWidth,
    double widthVelocity,
    double fromHeight,
    double heightVelocity,
  ) {
    unawaited(
      _widthMorph
          .animateWith(
            SpringSimulation(
              _widthSpring,
              fromWidth,
              1.0,
              widthVelocity,
              tolerance: _morphTolerance,
            ),
          )
          .whenComplete(() {
            if (mounted &&
                !_closing &&
                !_committed &&
                (_widthMorph.value - 1.0).abs() < 0.02) {
              _widthMorph.value = 1.0;
            }
          }),
    );
    unawaited(
      _heightMorph
          .animateWith(
            SpringSimulation(
              _heightSpring,
              fromHeight,
              1.0,
              heightVelocity,
              tolerance: _morphTolerance,
            ),
          )
          .whenComplete(() {
            if (mounted &&
                !_closing &&
                !_committed &&
                (_heightMorph.value - 1.0).abs() < 0.02) {
              _heightMorph.value = 1.0;
            }
          }),
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

    // 放行 Dock 栏命中后，仍需在全局指针入口同步收起菜单；非 Dock 外部区域则由底层
    // 选择性遮罩拦截并触发收起，不向底层课表/按钮穿透。
    if (event is PointerDownEvent && !widget.session.closing && !_committed) {
      if (_activePointer != null || _isInsideVisualCard(event.position)) {
        return;
      }
      widget.session.dismiss();
    }
  }

  bool _isInsideVisualCard(Offset globalPosition) {
    if (_targetRect == null) return false;
    final morphRo = _morphBoxKey.currentContext?.findRenderObject();
    if (morphRo is RenderMenuMorphBox && morphRo.attached && morphRo.hasSize) {
      return morphRo.containsGlobalPosition(globalPosition);
    }
    final ro = _cardHitKey.currentContext?.findRenderObject();
    if (ro is! RenderBox || !ro.attached || !ro.hasSize) {
      return false;
    }
    final local = ro.globalToLocal(globalPosition);
    return ro.paintBounds.contains(local);
  }

  void _syncRubberOffset() {
    _rubberOffset.value =
        Offset.lerp(_rubberFrom, _rubberTarget, _rubberAnim.value) ??
        _rubberTarget;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _needsMeasure = true;
  }

  @override
  void didUpdateWidget(_AppMenu<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _syncKeys();
      _itemRects = const <Rect>[];
      _targetRect = null;
      _needsMeasure = true;
      if (_hoveredIndex != null && _hoveredIndex! >= widget.items.length) {
        _hoveredIndex = null;
        _highlightedIndex.value = null;
        _hidePill();
      }
      if (_pressedScrollableIndex != null &&
          _pressedScrollableIndex! >= widget.items.length) {
        _pressedScrollableIndex = null;
        _highlightedIndex.value = null;
      }
    } else if (oldWidget.items != widget.items ||
        oldWidget.maxHeight != widget.maxHeight ||
        oldWidget.minWidth != widget.minWidth ||
        oldWidget.overlaySize != widget.overlaySize ||
        oldWidget.centerHorizontally != widget.centerHorizontally ||
        oldWidget.centerItems != widget.centerItems) {
      _targetRect = null;
      _needsMeasure = true;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _pendingPreviousClosing?.cleanupEntry();
    _pendingPreviousClosing = null;
    _detachGlobalPointerRouter();
    _morphGeometryListenable.removeListener(_syncAnchorMorph);
    final triggerRo = widget.session.triggerRenderObject;
    final canClearMorph =
        identical(_activeSession, widget.session) ||
        identical(_activeSession?.state, this) ||
        _activeSession == null;
    if (canClearMorph && identical(activeAppMenuMorph.value.$1, triggerRo)) {
      if (SchedulerBinding.instance.schedulerPhase ==
          SchedulerPhase.persistentCallbacks) {
        Future<void>.microtask(() {
          if ((identical(_activeSession, widget.session) ||
                  _activeSession == null) &&
              identical(activeAppMenuMorph.value.$1, triggerRo)) {
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
    _highlightedIndex.dispose();
    _rubberOffset.dispose();
    _scrollController.dispose();
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
    final double x;
    if (widget.centerHorizontally) {
      x = (widget.anchor.center.dx - menuSize.width * 0.5).clamp(margin, maxX);
      final focalRatio =
          ((widget.anchor.center.dx - x) / math.max(1.0, menuSize.width)).clamp(
            0.0,
            1.0,
          );
      _alignX = focalRatio * 2.0 - 1.0;
    } else {
      final alignRight = widget.anchor.center.dx > screen.width * 0.5;
      _alignX = alignRight ? 1.0 : -1.0;
      x =
          (alignRight
                  ? widget.anchor.right - menuSize.width
                  : widget.anchor.left)
              .clamp(margin, maxX);
    }

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
    final closing = _closing || _committed || widget.session.closing;
    if (closing && _targetRect != null) return;
    final stackBox = _menuStackKey.currentContext?.findRenderObject();
    if (stackBox is! RenderBox || !stackBox.hasSize) {
      if (_targetRect == null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
      }
      return;
    }
    final rects = <Rect>[];
    for (final key in _itemKeys) {
      final itemRender = key.currentContext?.findRenderObject();
      if (itemRender is! RenderBox || !itemRender.hasSize) {
        if (_targetRect == null && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
        }
        return;
      }
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
    final needRebuildForLayout =
        _targetRect == null || targetChanged || scrollable != _isScrollable;
    if (_targetRect == null && !closing) {
      _needsMeasure = true;
    }
    _menuSize = clampedSize;
    _targetRect = computedTarget;
    _itemRects = rects;
    _isScrollable = scrollable;
    if (_pendingPreviousClosing != null) {
      final prev = _pendingPreviousClosing;
      _pendingPreviousClosing = null;
      var initW = 0.0;
      var initWV = 0.0;
      var initH = 0.0;
      var initHV = 0.0;
      final prevState = prev?.state;
      if (prevState != null &&
          prevState.mounted &&
          prevState._targetRect != null) {
        initW = prevState._widthMorph.value;
        initWV = prevState._widthMorph.velocity;
        initH = prevState._heightMorph.value;
        initHV = prevState._heightMorph.velocity;
      }
      prev?.cleanupEntry();
      _startOpenSprings(initW, initWV, initH, initHV);
      _syncAnchorMorph();
    }
    final hovered = _hoveredIndex;
    if (!closing &&
        hovered != null &&
        hovered >= 0 &&
        hovered < _itemRects.length) {
      final updatedTarget = _itemRects[hovered];
      if (_pillTo != updatedTarget) {
        _pillTo = updatedTarget;
        if (!_pillSlide.isAnimating) {
          _pillFrom = updatedTarget;
        }
      }
    }
    var hoverInitialized = false;
    if (!closing &&
        _handoffPointer != null &&
        _hoveredIndex == null &&
        !_isScrollable &&
        _handoffPosition != null) {
      final local = _toMenuLocal(_handoffPosition!, useVisualTransform: false);
      final initialHit = local != null ? _hitSelectableIndex(local) : null;
      if (initialHit != null) {
        _suppressInitialHoverHaptic = false;
        _hoveredIndex = initialHit;
        _highlightedIndex.value = initialHit;
        _showPillAt(_itemRects[initialHit], immediate: true);
        hoverInitialized = true;
      }
    }
    if (needRebuildForLayout && mounted) {
      setState(() {});
    } else if (hoverInitialized && _isScrollable) {
      _highlightedIndex.value = _hoveredIndex;
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

  Offset? _toMenuLocal(
    Offset globalPosition, {
    bool useVisualTransform = true,
  }) {
    final target = _targetRect;
    if (target == null) return null;
    final scrollY = _scrollController.hasClients
        ? _scrollController.offset
        : 0.0;
    if (useVisualTransform) {
      final morphRo = _morphBoxKey.currentContext?.findRenderObject();
      if (morphRo is RenderMenuMorphBox &&
          morphRo.attached &&
          morphRo.hasSize) {
        final childLocal = morphRo.globalToChildLocal(globalPosition);
        if (childLocal != null) {
          return childLocal + Offset(0, scrollY);
        }
      }
    }
    // 长按交接初帧期间按未缩放的目标菜单坐标映射，避免静止/微抖动手指误命中下方菜单项后再滑回上方。
    final overlayBox = Overlay.of(
      context,
      rootOverlay: true,
    ).context.findRenderObject();
    final inOverlay = overlayBox is RenderBox && overlayBox.hasSize
        ? overlayBox.globalToLocal(globalPosition)
        : globalPosition;
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
    _hoveredIndex = nextIndex;
    if (!_isScrollable) {
      _highlightedIndex.value = nextIndex;
    }
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
    if (_isScrollable && _pressedScrollableIndex != index) {
      _pressedScrollableIndex = index;
      _highlightedIndex.value = index;
    }
    _committed = true;
    widget.session.dismiss(item.value);
  }

  void closeWithResult(T? picked) {
    if (!mounted) {
      widget.onDismissed(picked);
      widget.onEntryDisposeReady();
      return;
    }
    if (_closing) {
      widget.onDismissed(picked);
      return;
    }
    _closePeakMorph = _rawMorphProgress;
    _closing = true;
    _committed = true;
    _activePointer = null;
    _handoffPointer = null;
    _handoffPosition = null;
    _detachGlobalPointerRouter();
    widget.onDismissed(picked);

    final hasStarted =
        _targetRect != null &&
        (_widthMorph.value.abs() > 0.001 || _heightMorph.value.abs() > 0.001);
    if (!hasStarted) {
      _pendingPreviousClosing?.cleanupEntry();
      _pendingPreviousClosing = null;
      _widthMorph.stop();
      _heightMorph.stop();
      widget.onEntryDisposeReady();
      return;
    }

    _setPressLift(0.0);
    _springRubberHome();

    final widthFuture = _widthMorph.animateWith(
      SpringSimulation(
        _widthCloseSpring,
        _widthMorph.value,
        0.0,
        _widthMorph.velocity,
        tolerance: _closeMorphTolerance,
      ),
    );
    final heightFuture = _heightMorph.animateWith(
      SpringSimulation(
        _heightCloseSpring,
        _heightMorph.value,
        0.0,
        _heightMorph.velocity,
        tolerance: _closeMorphTolerance,
      ),
    );

    var remaining = 2;
    void onClosePartFinished() {
      remaining--;
      if (remaining == 0 && !_disposed && mounted) {
        widget.onEntryDisposeReady();
      }
    }

    widthFuture.whenCompleteOrCancel(onClosePartFinished);
    heightFuture.whenCompleteOrCancel(onClosePartFinished);
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
    final local = _toMenuLocal(
      event.position,
      useVisualTransform: _handoffPointer != event.pointer,
    );
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

  bool _isDockHit(Offset globalPosition) => FloatingDock.hitTestGlobalPosition(
    globalPosition,
    route: widget.session.modalRoute,
  );

  bool _isClosingSession() => widget.session.closing || _committed || _closing;

  void _dismissFromBarrier() {
    if (widget.session.closing || _committed) return;
    if (_activePointer != null) return;
    widget.session.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).dividerTheme;
    final scheme = Theme.of(context).colorScheme;
    if (_needsMeasure) {
      _needsMeasure = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    }

    final targetRect = _targetRect;
    final menuStack = Stack(
      key: _menuStackKey,
      children: <Widget>[
        Positioned.fill(
          child: IgnorePointer(
            child: RepaintBoundary(
              child: AnimatedBuilder(
                animation: _pillListenable,
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
                    rect.left + _kMenuPillHorizontalInset,
                    rect.top + _kMenuPillVerticalInset,
                    rect.right - _kMenuPillHorizontalInset,
                    rect.bottom - _kMenuPillVerticalInset,
                  );
                  final stretched = Rect.fromCenter(
                    center: insetRect.center,
                    width: insetRect.width * scale * (1 - 0.025 * stretch),
                    height: insetRect.height * scale * (1 + 0.12 * stretch),
                  );
                  return CustomPaint(
                    painter: _MenuPillPainter(
                      rect: stretched,
                      color: scheme.primary.withValues(
                        alpha: _kMenuPillFillAlpha * presence,
                      ),
                      rimColor: scheme.primary.withValues(
                        alpha: _kMenuPillRimAlpha * presence,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        ConstrainedBox(
          constraints: BoxConstraints(minWidth: widget.minWidth),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: RepaintBoundary(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _buildStaggeredChildren(divider),
              ),
            ),
          ),
        ),
      ],
    );

    final Widget scrollChild = targetRect == null
        ? IntrinsicWidth(child: menuStack)
        : SizedBox(width: targetRect.width, child: menuStack);

    final innerContent = RepaintBoundary(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: math.max(widget.minWidth, widget.overlaySize.width - 16.0),
          maxHeight: widget.maxHeight,
        ),
        child: SingleChildScrollView(
          controller: _scrollController,
          child: scrollChild,
        ),
      ),
    );

    // 首次布局前（_targetRect 尚未算好）：放到无边距定位位置透明测出真实尺寸，
    // 第二帧起即可从按钮外框（anchor）精确容器形变展开，且零跳变。
    if (targetRect == null) {
      return Positioned.fill(
        child: Stack(
          children: <Widget>[
            Positioned.fill(
              child: _MenuBarrier(
                excludeHitTest: _isDockHit,
                isClosing: _isClosingSession,
                onDismiss: _dismissFromBarrier,
              ),
            ),
            Positioned.fill(
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.0,
                  child: CustomSingleChildLayout(
                    delegate: _FallbackMeasureLayout(
                      anchor: widget.anchor,
                      minWidth: widget.minWidth,
                    ),
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
          ],
        ),
      );
    }

    final alignY = _openUp ? 1.0 : -1.0;
    // 菜单卡片面积较大，采用克制的按压抬升倍率，既明显可见又不显突兀。
    final liftSpan = (0.025 + 4.0 / math.max(140.0, targetRect.longestSide))
        .clamp(0.032, 0.048);

    final cardMaterial = Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: targetRect.width,
        height: targetRect.height,
        child: innerContent,
      ),
    );

    final interactiveCard = MouseRegion(
      key: _cardHitKey,
      onHover: _onMouseHover,
      onExit: (_) {
        if (_activePointer == null) {
          _updateHoverState(null, hapticOnSwitch: false);
        }
      },
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: cardMaterial,
      ),
    );

    return Positioned.fill(
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: _MenuBarrier(
              excludeHitTest: _isDockHit,
              isClosing: _isClosingSession,
              onDismiss: _dismissFromBarrier,
            ),
          ),
          Positioned(
            left: targetRect.left,
            top: targetRect.top,
            width: targetRect.width,
            height: targetRect.height,
            child: _ClosingIgnorePointer(
              isClosing: _isClosingSession,
              child: _MenuMorphBox(
                key: _morphBoxKey,
                morphListenable: _cardMorphListenable,
                widthMorph: _widthMorph,
                heightMorph: _heightMorph,
                pressLift: _pressLift,
                rubberOffset: _rubberOffset,
                isClosing: () => _closing,
                getClosePeakMorph: _effectiveFadeMorph,
                anchor: widget.anchor,
                targetRect: targetRect,
                anchorRadius: widget.anchorRadius,
                cardRadius: 20.0,
                alignX: _alignX,
                alignY: alignY,
                liftSpan: liftSpan,
                isScrollable: _isScrollable,
                cardColor: scheme.surfaceContainerLowest,
                borderColor: scheme.outlineVariant,
                child: interactiveCard,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildItemContent(DividerThemeData divider, int index) {
    final item = widget.items[index];
    if (item.isDivider) {
      return Divider(
        height: 1,
        thickness: divider.thickness,
        color: divider.color,
      );
    }
    return _MenuTile<T>(
      item: item,
      index: index,
      highlightedIndex: _highlightedIndex,
      showCapsule: _isScrollable,
      centerItems: widget.centerItems,
      onTap: () => _commitSelection(index),
      onPressChanged: (pressed) {
        if (!_isScrollable || _committed || !mounted) return;
        _pressedScrollableIndex = pressed ? index : null;
        _highlightedIndex.value = _pressedScrollableIndex;
      },
    );
  }

  List<Widget> _buildStaggeredChildren(DividerThemeData divider) {
    return <Widget>[
      for (var i = 0; i < widget.items.length; i++)
        KeyedSubtree(key: _itemKeys[i], child: _buildItemContent(divider, i)),
    ];
  }
}

class _MenuMorphBox extends SingleChildRenderObjectWidget {
  const _MenuMorphBox({
    super.key,
    required this.morphListenable,
    required this.widthMorph,
    required this.heightMorph,
    required this.pressLift,
    required this.rubberOffset,
    required this.isClosing,
    required this.getClosePeakMorph,
    required this.anchor,
    required this.targetRect,
    required this.anchorRadius,
    required this.cardRadius,
    required this.alignX,
    required this.alignY,
    required this.liftSpan,
    required this.isScrollable,
    required this.cardColor,
    required this.borderColor,
    required super.child,
  });

  final Listenable morphListenable;
  final ValueListenable<double> widthMorph;
  final ValueListenable<double> heightMorph;
  final ValueListenable<double> pressLift;
  final ValueListenable<Offset> rubberOffset;
  final bool Function() isClosing;
  final double Function() getClosePeakMorph;
  final Rect anchor;
  final Rect targetRect;
  final double anchorRadius;
  final double cardRadius;
  final double alignX;
  final double alignY;
  final double liftSpan;
  final bool isScrollable;
  final Color cardColor;
  final Color borderColor;

  @override
  RenderObject createRenderObject(BuildContext context) => RenderMenuMorphBox(
    morphListenable: morphListenable,
    widthMorph: widthMorph,
    heightMorph: heightMorph,
    pressLift: pressLift,
    rubberOffset: rubberOffset,
    isClosing: isClosing,
    getClosePeakMorph: getClosePeakMorph,
    anchor: anchor,
    targetRect: targetRect,
    anchorRadius: anchorRadius,
    cardRadius: cardRadius,
    alignX: alignX,
    alignY: alignY,
    liftSpan: liftSpan,
    isScrollable: isScrollable,
    cardColor: cardColor,
    borderColor: borderColor,
  );

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderMenuMorphBox renderObject,
  ) {
    renderObject.updateProps(
      morphListenable: morphListenable,
      widthMorph: widthMorph,
      heightMorph: heightMorph,
      pressLift: pressLift,
      rubberOffset: rubberOffset,
      isClosing: isClosing,
      getClosePeakMorph: getClosePeakMorph,
      anchor: anchor,
      targetRect: targetRect,
      anchorRadius: anchorRadius,
      cardRadius: cardRadius,
      alignX: alignX,
      alignY: alignY,
      liftSpan: liftSpan,
      isScrollable: isScrollable,
      cardColor: cardColor,
      borderColor: borderColor,
    );
  }
}

class _MenuMorphFrame {
  const _MenuMorphFrame({
    required this.finalLocalRect,
    required this.rrectLocal,
    required this.morphRadius,
    required this.shellAlpha,
    required this.contentAlpha,
    required this.contentScale,
    required this.childTransform,
    required this.rubber,
    required this.shadowAlpha,
    required this.shadowBlurRadius,
    required this.shadowOffsetY,
    required this.borderAlpha,
    required this.needsClip,
    required this.needsTransform,
    required this.isSettled,
  });

  final Rect finalLocalRect;
  final RRect rrectLocal;
  final double morphRadius;
  final double shellAlpha;
  final double contentAlpha;
  final double contentScale;
  final Matrix4 childTransform;
  final Offset rubber;
  final double shadowAlpha;
  final double shadowBlurRadius;
  final double shadowOffsetY;
  final double borderAlpha;
  final bool needsClip;
  final bool needsTransform;
  final bool isSettled;
}

/// 在渲染层直接执行 FlClash 风格容器形变（位置、宽高、圆角、阴影、单层内容淡入与各向同性缩放），
/// 动画全过程零 Widget 重建与零布局重算，并复用合成图层句柄且不产生逐帧 `Path` 阴影分配。
@visibleForTesting
class RenderMenuMorphBox extends RenderProxyBox {
  RenderMenuMorphBox({
    required this._morphListenable,
    required this._widthMorph,
    required this._heightMorph,
    required this._pressLift,
    required this._rubberOffset,
    required this._isClosing,
    required this._getClosePeakMorph,
    required this._anchor,
    required this._targetRect,
    required this._anchorRadius,
    required this._cardRadius,
    required this._alignX,
    required this._alignY,
    required this._liftSpan,
    required this._isScrollable,
    required this._cardColor,
    required this._borderColor,
  });

  Listenable _morphListenable;
  ValueListenable<double> _widthMorph;
  ValueListenable<double> _heightMorph;
  ValueListenable<double> _pressLift;
  ValueListenable<Offset> _rubberOffset;
  bool Function() _isClosing;
  double Function() _getClosePeakMorph;
  Rect _anchor;
  Rect _targetRect;
  double _anchorRadius;
  double _cardRadius;
  double _alignX;
  double _alignY;
  double _liftSpan;
  bool _isScrollable;
  Color _cardColor;
  Color _borderColor;

  final LayerHandle<ClipRRectLayer> _clipLayer = LayerHandle<ClipRRectLayer>();
  final LayerHandle<TransformLayer> _transformLayer =
      LayerHandle<TransformLayer>();
  final LayerHandle<OpacityLayer> _opacityLayer = LayerHandle<OpacityLayer>();

  final Paint _fillPaint = Paint()..style = PaintingStyle.fill;
  final Paint _borderPaint = Paint()
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.0;
  final Paint _shadowPaint = Paint()..style = PaintingStyle.fill;
  double _lastShadowSigma = -1.0;

  @override
  bool get isRepaintBoundary => true;

  @override
  Rect get paintBounds {
    final frame = _computeMorphFrame();
    final shadowSpread = frame.shadowBlurRadius * 1.8 + 4.0;
    final shadowRect = frame.finalLocalRect
        .shift(Offset(0.0, frame.shadowOffsetY))
        .inflate(shadowSpread);
    return (Offset.zero & size)
        .expandToInclude(frame.finalLocalRect.inflate(4.0))
        .expandToInclude(shadowRect);
  }

  @visibleForTesting
  Rect get morphRect => _computeMorphFrame().finalLocalRect;

  @visibleForTesting
  double get morphRadius => _computeMorphFrame().morphRadius;

  @visibleForTesting
  double get shellOpacity => _computeMorphFrame().shellAlpha;

  @visibleForTesting
  double get contentOpacity => _computeMorphFrame().contentAlpha;

  @visibleForTesting
  double get contentScale => _computeMorphFrame().contentScale;

  @visibleForTesting
  Offset get currentRubberOffset => _rubberOffset.value;

  @visibleForTesting
  Alignment get alignment => Alignment(_alignX, _alignY);

  @visibleForTesting
  bool get isClipping => _computeMorphFrame().needsClip;

  @visibleForTesting
  bool get isSettled => _computeMorphFrame().isSettled;

  @visibleForTesting
  double get shadowAlpha => _computeMorphFrame().shadowAlpha;

  @visibleForTesting
  double get shadowBlurRadius => _computeMorphFrame().shadowBlurRadius;

  void updateProps({
    required Listenable morphListenable,
    required ValueListenable<double> widthMorph,
    required ValueListenable<double> heightMorph,
    required ValueListenable<double> pressLift,
    required ValueListenable<Offset> rubberOffset,
    required bool Function() isClosing,
    required double Function() getClosePeakMorph,
    required Rect anchor,
    required Rect targetRect,
    required double anchorRadius,
    required double cardRadius,
    required double alignX,
    required double alignY,
    required double liftSpan,
    required bool isScrollable,
    required Color cardColor,
    required Color borderColor,
  }) {
    final listenableChanged = !identical(_morphListenable, morphListenable);
    if (listenableChanged && attached) {
      _morphListenable.removeListener(markNeedsPaint);
    }
    _morphListenable = morphListenable;
    if (listenableChanged && attached) {
      _morphListenable.addListener(markNeedsPaint);
    }

    final changed =
        listenableChanged ||
        !identical(_widthMorph, widthMorph) ||
        !identical(_heightMorph, heightMorph) ||
        !identical(_pressLift, pressLift) ||
        !identical(_rubberOffset, rubberOffset) ||
        _anchor != anchor ||
        _targetRect != targetRect ||
        _anchorRadius != anchorRadius ||
        _cardRadius != cardRadius ||
        _alignX != alignX ||
        _alignY != alignY ||
        _liftSpan != liftSpan ||
        _isScrollable != isScrollable ||
        _cardColor != cardColor ||
        _borderColor != borderColor;

    _widthMorph = widthMorph;
    _heightMorph = heightMorph;
    _pressLift = pressLift;
    _rubberOffset = rubberOffset;
    _isClosing = isClosing;
    _getClosePeakMorph = getClosePeakMorph;
    _anchor = anchor;
    _targetRect = targetRect;
    _anchorRadius = anchorRadius;
    _cardRadius = cardRadius;
    _alignX = alignX;
    _alignY = alignY;
    _liftSpan = liftSpan;
    _isScrollable = isScrollable;
    _cardColor = cardColor;
    _borderColor = borderColor;

    if (changed) {
      markNeedsPaint();
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _morphListenable.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _morphListenable.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  void dispose() {
    _morphListenable.removeListener(markNeedsPaint);
    _clipLayer.layer = null;
    _transformLayer.layer = null;
    _opacityLayer.layer = null;
    super.dispose();
  }

  bool containsGlobalPosition(Offset globalPosition) {
    if (!attached || !hasSize) return false;
    final local = globalToLocal(globalPosition);
    final frame = _computeMorphFrame();
    if (frame.shellAlpha <= 0.001) return false;
    return frame.rrectLocal.contains(local);
  }

  Offset? globalToChildLocal(Offset globalPosition) {
    if (!attached || !hasSize) return null;
    final local = globalToLocal(globalPosition);
    final frame = _computeMorphFrame();
    final scale = frame.contentScale;
    if (scale <= 0.0) return null;
    final tx = frame.childTransform.storage[12];
    final ty = frame.childTransform.storage[13];
    return Offset((local.dx - tx) / scale, (local.dy - ty) / scale);
  }

  _MenuMorphFrame _computeMorphFrame() {
    final wx = _widthMorph.value;
    final wy = _heightMorph.value;
    final wxRect = math.max(0.0, wx);
    final wyRect = math.max(0.0, wy);
    final rawAvg = (wx + wy) * 0.5;
    final clampedAvg = rawAvg.clamp(0.0, 1.0);
    final fadeMorph = _isClosing()
        ? math.min(clampedAvg, _getClosePeakMorph())
        : clampedAvg;

    final shellU = (fadeMorph / 0.18).clamp(0.0, 1.0);
    final shellAlpha = Curves.easeOut.transform(shellU);

    final contentU = ((fadeMorph - 0.06) / 0.42).clamp(0.0, 1.0);
    final contentAlpha = Curves.easeOutCubic.transform(contentU);

    final targetSize = _targetRect.size;
    final anchorLocal = _anchor.shift(-_targetRect.topLeft);
    final rawLeft = lerpDouble(anchorLocal.left, 0.0, wxRect)!;
    final rawRight = lerpDouble(anchorLocal.right, targetSize.width, wxRect)!;
    final rawTop = lerpDouble(anchorLocal.top, 0.0, wyRect)!;
    final rawBottom = lerpDouble(
      anchorLocal.bottom,
      targetSize.height,
      wyRect,
    )!;

    final baseLeft = math.min(rawLeft, rawRight);
    final baseRight = math.max(rawRight, baseLeft + 1.0);
    final baseTop = math.min(rawTop, rawBottom);
    final baseBottom = math.max(rawBottom, baseTop + 1.0);
    final baseRect = Rect.fromLTRB(baseLeft, baseTop, baseRight, baseBottom);

    final interactiveScale = 1.0 + _liftSpan * _pressLift.value;
    final rubber = _rubberOffset.value;
    final ax = (_alignX + 1.0) * 0.5;
    final ay = (_alignY + 1.0) * 0.5;
    final focal = Offset(
      lerpDouble(baseRect.left, baseRect.right, ax)!,
      lerpDouble(baseRect.top, baseRect.bottom, ay)!,
    );
    final scaledW = math.max(1.0, baseRect.width * interactiveScale);
    final scaledH = math.max(1.0, baseRect.height * interactiveScale);
    final finalLocalRect = Rect.fromLTWH(
      focal.dx - ax * scaledW + rubber.dx,
      focal.dy - ay * scaledH + rubber.dy,
      scaledW,
      scaledH,
    );

    final clampedStartRadius = _anchorRadius.clamp(
      0.0,
      math.min(_anchor.width, _anchor.height) * 0.5,
    );
    final rawRadius = lerpDouble(clampedStartRadius, _cardRadius, clampedAvg)!;
    final morphRadius = rawRadius.clamp(
      0.0,
      math.min(finalLocalRect.width, finalLocalRect.height) * 0.5,
    );
    final rrectLocal = RRect.fromRectAndRadius(
      finalLocalRect,
      Radius.circular(morphRadius),
    );

    final startContentScale =
        (math.min(
                      _anchor.width / math.max(1.0, targetSize.width),
                      _anchor.height / math.max(1.0, targetSize.height),
                    ) *
                    0.35 +
                0.58)
            .clamp(0.60, 0.86);
    final scaleMorph = rawAvg.clamp(-0.04, 1.15);
    final openScale = lerpDouble(startContentScale, 1.0, scaleMorph) ?? 1.0;
    final contentScale = math.max(0.1, openScale * interactiveScale);

    final childAnchor = Offset(targetSize.width * ax, targetSize.height * ay);
    final rectAnchor = Offset(
      lerpDouble(finalLocalRect.left, finalLocalRect.right, ax)!,
      lerpDouble(finalLocalRect.top, finalLocalRect.bottom, ay)!,
    );
    final dx = rectAnchor.dx - contentScale * childAnchor.dx;
    final dy = rectAnchor.dy - contentScale * childAnchor.dy;
    final childTransform = Matrix4.identity()
      ..translateByDouble(dx, dy, 0.0, 1.0)
      ..scaleByDouble(contentScale, contentScale, 1.0, 1.0);

    final isSettled =
        (wx - 1.0).abs() < 1e-3 &&
        (wy - 1.0).abs() < 1e-3 &&
        (interactiveScale - 1.0).abs() < 1e-4 &&
        rubber.distanceSquared < 1e-4;
    final needsClip = _isScrollable || !isSettled;
    final needsTransform =
        (contentScale - 1.0).abs() > 1e-4 || dx.abs() > 1e-4 || dy.abs() > 1e-4;

    final shadowAlpha = (lerpDouble(0.045, 0.15, clampedAvg)!) * shellAlpha;
    final shadowBlurRadius = lerpDouble(8.0, 18.0, clampedAvg)!;
    final shadowOffsetY = lerpDouble(2.0, 6.0, clampedAvg)!;
    final borderAlpha = 0.22 * shellAlpha * clampedAvg;

    return _MenuMorphFrame(
      finalLocalRect: finalLocalRect,
      rrectLocal: rrectLocal,
      morphRadius: morphRadius,
      shellAlpha: shellAlpha,
      contentAlpha: contentAlpha,
      contentScale: contentScale,
      childTransform: childTransform,
      rubber: rubber,
      shadowAlpha: shadowAlpha,
      shadowBlurRadius: shadowBlurRadius,
      shadowOffsetY: shadowOffsetY,
      borderAlpha: borderAlpha,
      needsClip: needsClip,
      needsTransform: needsTransform,
      isSettled: isSettled,
    );
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!attached || !hasSize) return false;
    final frame = _computeMorphFrame();
    if (frame.shellAlpha <= 0.001 || !frame.rrectLocal.contains(position)) {
      return false;
    }
    if (hitTestChildren(result, position: position) || hitTestSelf(position)) {
      result.add(BoxHitTestEntry(this, position));
      return true;
    }
    return false;
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final child = this.child;
    if (child == null) return false;
    final frame = _computeMorphFrame();
    if (frame.contentAlpha <= 0.001) return false;
    return result.addWithPaintTransform(
      transform: frame.childTransform,
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformedPosition) {
        return child.hitTest(result, position: transformedPosition);
      },
    );
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    final frame = _computeMorphFrame();
    transform.multiply(frame.childTransform);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final frame = _computeMorphFrame();
    if (frame.shellAlpha <= 0.001) {
      _clipLayer.layer = null;
      _transformLayer.layer = null;
      _opacityLayer.layer = null;
      return;
    }

    final rrectPaint = offset == Offset.zero
        ? frame.rrectLocal
        : frame.rrectLocal.shift(offset);

    if (frame.shadowAlpha > 0.001) {
      final sigma = Shadow.convertRadiusToSigma(frame.shadowBlurRadius);
      if ((sigma - _lastShadowSigma).abs() > 0.1) {
        _lastShadowSigma = sigma;
        _shadowPaint.maskFilter = MaskFilter.blur(BlurStyle.normal, sigma);
      }
      _shadowPaint.color = Colors.black.withValues(alpha: frame.shadowAlpha);
      context.canvas.drawRRect(
        rrectPaint.shift(Offset(0.0, frame.shadowOffsetY)),
        _shadowPaint,
      );
    }

    _fillPaint.color = _cardColor.withValues(alpha: frame.shellAlpha);
    context.canvas.drawRRect(rrectPaint, _fillPaint);

    final child = this.child;
    final alphaByte = (frame.contentAlpha * 255).round().clamp(0, 255);
    if (child == null || alphaByte <= 0) {
      _clipLayer.layer = null;
      _transformLayer.layer = null;
      _opacityLayer.layer = null;
    } else {
      void paintContent(PaintingContext opCtx, Offset opOffset) {
        if (alphaByte < 255) {
          _opacityLayer.layer = opCtx.pushOpacity(
            opOffset,
            alphaByte,
            (PaintingContext c, Offset o) => c.paintChild(child, o),
            oldLayer: _opacityLayer.layer,
          );
        } else {
          _opacityLayer.layer = null;
          opCtx.paintChild(child, opOffset);
        }
      }

      void paintTransformed(PaintingContext txCtx, Offset txOffset) {
        if (frame.needsTransform) {
          _transformLayer.layer = txCtx.pushTransform(
            needsCompositing,
            txOffset,
            frame.childTransform,
            paintContent,
            oldLayer: _transformLayer.layer,
          );
        } else {
          _transformLayer.layer = null;
          paintContent(txCtx, txOffset);
        }
      }

      if (frame.needsClip) {
        _clipLayer.layer = context.pushClipRRect(
          needsCompositing,
          offset,
          frame.finalLocalRect,
          frame.rrectLocal,
          paintTransformed,
          oldLayer: _clipLayer.layer,
        );
      } else {
        _clipLayer.layer = null;
        paintTransformed(context, offset);
      }
    }

    if (frame.borderAlpha > 0.001) {
      _borderPaint.color = _borderColor.withValues(alpha: frame.borderAlpha);
      context.canvas.drawRRect(rrectPaint.deflate(0.5), _borderPaint);
    }
  }
}

class _FallbackMeasureLayout extends SingleChildLayoutDelegate {
  _FallbackMeasureLayout({required this.anchor, required this.minWidth});
  final Rect anchor;
  final double minWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.max(minWidth, constraints.maxWidth - 16),
        maxHeight: math.max(120.0, constraints.maxHeight - 16),
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) => Offset.zero;

  @override
  bool shouldRelayout(covariant _FallbackMeasureLayout oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.minWidth != minWidth;
}

const double _kMenuPillHorizontalInset = 6.0;
const double _kMenuPillVerticalInset = 2.0;
const double _kMenuPillRadius = 14.0;
const double _kMenuPillFillAlpha = 0.11;
const double _kMenuPillRimAlpha = 0.18;
const double _kMenuPillRimWidth = 1.0;

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
    final rrect = RRect.fromRectAndRadius(
      rect,
      const Radius.circular(_kMenuPillRadius),
    );
    canvas.drawRRect(rrect, Paint()..color = color);
    if (rimColor.a > 0) {
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = rimColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = _kMenuPillRimWidth,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MenuPillPainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.color != color ||
      oldDelegate.rimColor != rimColor;
}

class _MenuTile<T> extends StatefulWidget {
  const _MenuTile({
    super.key,
    required this.item,
    required this.index,
    required this.highlightedIndex,
    required this.showCapsule,
    required this.centerItems,
    required this.onTap,
    required this.onPressChanged,
  });

  final AppMenuItem<T> item;
  final int index;
  final ValueListenable<int?> highlightedIndex;

  /// 长菜单不可滑动切换，按住/选中条目时直接在条目内绘制与短菜单同源的选择胶囊；
  /// 已选中的常态条目保持自身高亮与对勾指示，无需常驻胶囊。
  final bool showCapsule;
  final bool centerItems;
  final VoidCallback onTap;
  final ValueChanged<bool> onPressChanged;

  @override
  State<_MenuTile<T>> createState() => _MenuTileState<T>();
}

class _MenuTileState<T> extends State<_MenuTile<T>> {
  late bool _hovered = widget.highlightedIndex.value == widget.index;

  @override
  void initState() {
    super.initState();
    widget.highlightedIndex.addListener(_onHighlightChanged);
  }

  @override
  void didUpdateWidget(_MenuTile<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.highlightedIndex != widget.highlightedIndex ||
        oldWidget.index != widget.index) {
      oldWidget.highlightedIndex.removeListener(_onHighlightChanged);
      widget.highlightedIndex.addListener(_onHighlightChanged);
      _hovered = widget.highlightedIndex.value == widget.index;
    }
  }

  @override
  void dispose() {
    widget.highlightedIndex.removeListener(_onHighlightChanged);
    super.dispose();
  }

  void _onHighlightChanged() {
    final next = widget.highlightedIndex.value == widget.index;
    if (next != _hovered) {
      setState(() => _hovered = next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final item = widget.item;
    final highlighted = item.selected || _hovered;
    final double capsuleStrength = (widget.showCapsule && _hovered) ? 1.0 : 0.0;
    final color = !item.enabled
        ? theme.hintColor
        : highlighted
        ? scheme.primary
        : scheme.onSurface;
    final iconColor = item.enabled
        ? (highlighted ? scheme.primary : scheme.onSurfaceVariant)
        : theme.hintColor;
    final fontWeight = highlighted ? FontWeight.w600 : FontWeight.normal;
    final Widget tileBody;
    if (widget.centerItems) {
      tileBody = Stack(
        alignment: Alignment.center,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 27,
              vertical: 12 - _kMenuPillVerticalInset,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                if (item.icon != null) ...<Widget>[
                  Transform.scale(
                    scale: _hovered ? 1.08 : 1.0,
                    child: Icon(item.icon, size: 18, color: iconColor),
                  ),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    item.label,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      color: color,
                      fontWeight: fontWeight,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (item.trailing != null)
            Positioned(
              right: 6,
              top: 0,
              bottom: 0,
              child: Center(child: item.trailing!),
            ),
        ],
      );
    } else {
      tileBody = Align(
        alignment: Alignment.centerLeft,
        widthFactor: 1.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: 18 - _kMenuPillHorizontalInset,
            vertical: 12 - _kMenuPillVerticalInset,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (item.icon != null) ...<Widget>[
                Transform.scale(
                  scale: _hovered ? 1.08 : 1.0,
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
                item.trailing!,
              ],
            ],
          ),
        ),
      );
    }
    return InkWell(
      // 彻底屏蔽旧版 Material 水波纹与灰底阴影，仅留无障碍与可测试句柄，高亮全权交给滑动/选择胶囊。
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      hoverColor: Colors.transparent,
      highlightColor: Colors.transparent,
      focusColor: Colors.transparent,
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      onTapDown: item.enabled ? (_) => widget.onPressChanged(true) : null,
      onTapCancel: item.enabled ? () => widget.onPressChanged(false) : null,
      onTap: item.enabled ? widget.onTap : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: _kMenuPillHorizontalInset,
            vertical: _kMenuPillVerticalInset,
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: capsuleStrength > 0.001
                  ? scheme.primary.withValues(
                      alpha: _kMenuPillFillAlpha * capsuleStrength,
                    )
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(_kMenuPillRadius),
              border: Border.all(
                color: capsuleStrength > 0.001
                    ? scheme.primary.withValues(
                        alpha: _kMenuPillRimAlpha * capsuleStrength,
                      )
                    : Colors.transparent,
                width: _kMenuPillRimWidth,
              ),
            ),
            child: tileBody,
          ),
        ),
      ),
    );
  }
}

/// 选择性命中遮罩：拦截菜单外除 [FloatingDock] 之外的一切触控并在按下时收起菜单；
/// 当 [excludeHitTest] 返回 true（即命中活跃 Dock 胶囊）时直接放行，确保 Dock 栏
/// 保持最高优先级可一指直接切页。
class _MenuBarrier extends SingleChildRenderObjectWidget {
  _MenuBarrier({
    required this.excludeHitTest,
    required this.isClosing,
    required VoidCallback onDismiss,
  }) : super(
         child: Listener(
           behavior: HitTestBehavior.opaque,
           onPointerDown: (_) => onDismiss(),
         ),
       );

  final bool Function(Offset globalPosition) excludeHitTest;
  final bool Function() isClosing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMenuBarrier(excludeHitTest: excludeHitTest, isClosing: isClosing);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderMenuBarrier renderObject,
  ) {
    renderObject
      ..excludeHitTest = excludeHitTest
      ..isClosing = isClosing;
  }
}

class _RenderMenuBarrier extends RenderProxyBox {
  _RenderMenuBarrier({required this.excludeHitTest, required this.isClosing});

  bool Function(Offset globalPosition) excludeHitTest;
  bool Function() isClosing;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (!size.contains(position) || isClosing()) {
      return false;
    }
    final globalPosition = localToGlobal(position);
    if (excludeHitTest(globalPosition)) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}

/// 菜单开始收起后即刻退出命中测试，无需触发 widget 重建即可避免遮挡后续手势。
class _ClosingIgnorePointer extends SingleChildRenderObjectWidget {
  const _ClosingIgnorePointer({required this.isClosing, required super.child});

  final bool Function() isClosing;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderClosingIgnorePointer(isClosing: isClosing);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderClosingIgnorePointer renderObject,
  ) {
    renderObject.isClosing = isClosing;
  }
}

class _RenderClosingIgnorePointer extends RenderProxyBox {
  _RenderClosingIgnorePointer({required this.isClosing});

  bool Function() isClosing;

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (isClosing()) {
      return false;
    }
    return super.hitTest(result, position: position);
  }
}
