/// 带轻描边与物理手感的灵动触控按钮：支持按压回弹、跟手微拖拽以及"按住下拉直接滑入菜单"。
///
/// 为什么用底层 [Listener] 追踪按压/拖拽形变而不是包一层 `GestureDetector`：
///  - 避免与内部的 [IconButton]（例如刷新、前后翻周，单测会通过 `widgetWithIcon(IconButton, ...)` 查找）抢夺手势竞技场；
///  - 点按、长按、下拉滑入菜单三种交互共用同一套弹簧状态，无跳变切换。
library;

import 'dart:async' show Timer;
import 'dart:math' as math;

import 'package:flutter/gestures.dart'
    show
        GestureDisposition,
        GestureRecognizerState,
        PointerDeviceKind,
        PrimaryPointerGestureRecognizer,
        kPrimaryButton,
        kTouchSlop;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;

import 'app_menu.dart' show activeAppMenuMorph, activeTactileDragStart;

/// 当菜单触发按钮被点击或按住下拉展开时的回调。
///
/// [dragPointer] 不为 null 时，表示用户按住未松手并已长按或下拉，菜单可直接接管这根手指。
typedef TactileMenuTrigger = void Function(
  BuildContext anchorContext,
  int? dragPointer,
);

/// 触控按钮的表面风格：
///  - [elevated]：直接落在画布背景（如顶栏）上的纯白按钮，带一圈轻柔阴影与白色弹出菜单无缝衔接；
///  - [tinted]：落在纯白卡片内部（如卡片操作、设置页步进器）的柔和浅灰底按钮，避免白底融成一片；
///  - [transparent]：外层仅保留触控缩放手感，不绘制额外底色与阴影（如彩色 FAB、[TactileActionButton]）。
enum TactileSurfaceStyle { elevated, tinted, transparent }

class TactileSurfaceButton extends StatefulWidget {
  const TactileSurfaceButton({
    super.key,
    required this.child,
    this.onTap,
    this.onMenuOpen,
    this.borderRadius = const BorderRadius.all(Radius.circular(18)),
    this.padding = EdgeInsets.zero,
    this.minSize = const Size(36, 36),
    this.enabled = true,
    this.filled = true,
    this.surfaceStyle,
    this.clipContent = false,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final TactileMenuTrigger? onMenuOpen;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry padding;
  final Size? minSize;
  final bool enabled;
  final bool filled;
  final TactileSurfaceStyle? surfaceStyle;
  final bool clipContent;
  final String? tooltip;

  TactileSurfaceStyle get effectiveSurfaceStyle =>
      surfaceStyle ??
      (filled ? TactileSurfaceStyle.elevated : TactileSurfaceStyle.transparent);

  /// 给内嵌 [IconButton] 或 [BackButton] 使用的干净样式：关闭旧式水波纹与灰底叠加层，
  /// 并对齐 36×36 触控盒尺寸，同时保留无障碍与单测句柄兼容性。
  static ButtonStyle cleanIconButtonStyle(
    ColorScheme scheme, {
    Color? foregroundColor,
    double size = 36,
    double iconSize = 20,
  }) {
    final fg = foregroundColor ?? scheme.onSurface;
    return IconButton.styleFrom(
      splashFactory: NoSplash.splashFactory,
      backgroundColor: Colors.transparent,
      disabledBackgroundColor: Colors.transparent,
      shadowColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      focusColor: Colors.transparent,
      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
      minimumSize: Size(size, size),
      fixedSize: Size(size, size),
      padding: EdgeInsets.zero,
      iconSize: iconSize,
      foregroundColor: fg,
      disabledForegroundColor: fg.withValues(alpha: 0.34),
    ).copyWith(
      overlayColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
    );
  }

  @override
  State<TactileSurfaceButton> createState() => _TactileSurfaceButtonState();
}

class _TactileSurfaceButtonState extends State<TactileSurfaceButton>
    with TickerProviderStateMixin {
  static const SpringDescription _pressSpring = SpringDescription(
    mass: 1.0,
    stiffness: 1100.0,
    damping: 40.0,
  );
  static const SpringDescription _releaseSpring = SpringDescription(
    mass: 1.0,
    stiffness: 760.0,
    damping: 46.0,
  );
  static const SpringDescription _rubberSpring = SpringDescription(
    mass: 1.0,
    stiffness: 740.0,
    damping: 45.0,
  );

  late final AnimationController _press = AnimationController.unbounded(
    vsync: this,
    value: 0.0,
  );
  late final AnimationController _dragAnim = AnimationController.unbounded(
    vsync: this,
    value: 1.0,
  );
  final ValueNotifier<Offset> _dragOffset = ValueNotifier<Offset>(Offset.zero);

  int? _pointer;
  Offset _downPos = Offset.zero;
  Offset _lastPos = Offset.zero;
  Offset _dragFrom = Offset.zero;
  Offset _dragTarget = Offset.zero;
  bool _hovering = false;
  bool _dragOpenedMenu = false;
  Timer? _holdTimer;
  _TactileArenaRecognizer? _arenaRecognizer;
  late Listenable _motionListenable;
  bool _inScrollable = false;
  double _touchSlop = kTouchSlop;

  bool get _interactive => widget.enabled;

  @override
  void initState() {
    super.initState();
    _dragAnim.addListener(_syncDragOffset);
    _motionListenable = _buildMotionListenable();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inScrollable = Scrollable.maybeOf(context) != null;
    _touchSlop =
        MediaQuery.maybeGestureSettingsOf(context)?.touchSlop ?? kTouchSlop;
  }

  Listenable _buildMotionListenable() {
    if (widget.onMenuOpen != null) {
      return Listenable.merge(<Listenable>[
        _press,
        _dragOffset,
        activeAppMenuMorph,
      ]);
    }
    return Listenable.merge(<Listenable>[_press, _dragOffset]);
  }

  void _syncDragOffset() {
    _dragOffset.value =
        Offset.lerp(_dragFrom, _dragTarget, _dragAnim.value) ?? _dragTarget;
  }

  @override
  void didUpdateWidget(TactileSurfaceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.onMenuOpen != null) != (widget.onMenuOpen != null)) {
      _motionListenable = _buildMotionListenable();
    }
    if (!widget.enabled ||
        (widget.onTap == null && widget.onMenuOpen == null)) {
      _arenaRecognizer = null;
    }
    if (!widget.enabled && oldWidget.enabled) {
      _cancelPointer();
    }
  }

  @override
  void dispose() {
    _holdTimer?.cancel();
    _dragAnim.removeListener(_syncDragOffset);
    _dragOffset.dispose();
    _press.dispose();
    _dragAnim.dispose();
    super.dispose();
  }

  static double _rubberDelta(double delta, double maxPull) {
    if (delta == 0) return 0;
    return delta.sign * maxPull * (1.0 - math.exp(-delta.abs() / 36.0));
  }

  void _drivePress(double target) {
    if ((_press.value - target).abs() < 1e-4 && !_press.isAnimating) {
      return;
    }
    final spring = target > _press.value ? _pressSpring : _releaseSpring;
    _press.animateWith(SpringSimulation(spring, _press.value, target, 0.0));
  }

  void _setDragDirect(Offset offset) {
    _dragAnim.stop();
    _dragOffset.value = offset;
  }

  void _springDragHome() {
    final current = _dragOffset.value;
    if (current.distance < 0.1) {
      _setDragDirect(Offset.zero);
      return;
    }
    _dragFrom = current;
    _dragTarget = Offset.zero;
    _dragAnim.animateWith(SpringSimulation(_rubberSpring, 0.0, 1.0, 0.0));
  }

  void _onArenaRejected(int pointer) {
    if (_pointer == pointer && !_dragOpenedMenu) {
      _cancelPointer();
    }
  }

  void _openMenuWithDrag(int pointer) {
    if (_dragOpenedMenu || !_interactive || widget.onMenuOpen == null) return;
    _dragOpenedMenu = true;
    _holdTimer?.cancel();
    _holdTimer = null;
    _arenaRecognizer?.claimPointer(pointer);
    _drivePress(_hovering ? 0.22 : 0.0);
    _springDragHome();
    activeTactileDragStart = (pointer, _lastPos);
    widget.onMenuOpen!(context, pointer);
  }

  void _onPointerDown(PointerDownEvent event) {
    if (!_interactive) return;
    if (event.kind == PointerDeviceKind.mouse &&
        (event.buttons & kPrimaryButton == 0)) {
      return;
    }
    _pointer = event.pointer;
    _downPos = event.position;
    _lastPos = event.position;
    _dragOpenedMenu = false;
    _dragAnim.stop();
    _drivePress(1.0);

    _holdTimer?.cancel();
    if (widget.onMenuOpen != null && event.kind != PointerDeviceKind.mouse) {
      final pointer = event.pointer;
      _holdTimer = Timer(const Duration(milliseconds: 190), () {
        if (mounted && _pointer == pointer) {
          _openMenuWithDrag(pointer);
        }
      });
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_pointer != event.pointer) return;
    _lastPos = event.position;
    final delta = event.position - _downPos;
    // 处于可滚动/可移动容器内的内嵌按钮（如设置页加减号、卡片操作按钮），
    // 开始滑动且超过触控容差即取消按压效果，与竞技场接管型按钮（如提醒时间胶囊）保持一致；
    // 固定位置按钮（顶栏、弹窗等）则保留原有的拖拽跟随效果直至松手。
    if (_inScrollable &&
        widget.onTap == null &&
        widget.onMenuOpen == null &&
        delta.distance > _touchSlop) {
      _cancelPointer();
      return;
    }
    _setDragDirect(
      Offset(_rubberDelta(delta.dx, 6.0), _rubberDelta(delta.dy, 7.0)),
    );
    if (widget.onMenuOpen != null &&
        !_dragOpenedMenu &&
        delta.dy > 14.0 &&
        delta.dy > delta.dx.abs() * 0.9) {
      _openMenuWithDrag(event.pointer);
    }
  }

  void _onPointerUp(PointerUpEvent event) {
    if (_pointer != event.pointer) return;
    final wasOpened = _dragOpenedMenu;
    _pointer = null;
    _holdTimer?.cancel();
    _holdTimer = null;
    _drivePress(_hovering ? 0.22 : 0.0);
    _springDragHome();

    if (wasOpened) return;
    // 如果没有内嵌 IconButton（即按钮本身直接接管点击），在这里触发点击或短按展开菜单。
    final renderBox = context.findRenderObject();
    if (renderBox is RenderBox && renderBox.hasSize) {
      final local = renderBox.globalToLocal(event.position);
      final hitBounds = renderBox.paintBounds.inflate(6.0);
      if (hitBounds.contains(local)) {
        _arenaRecognizer?.claimPointer(event.pointer);
        if (widget.onMenuOpen != null) {
          widget.onMenuOpen!(context, null);
        } else {
          widget.onTap?.call();
        }
      }
    }
  }

  void _onPointerCancel(PointerCancelEvent event) {
    if (_pointer != event.pointer) return;
    _cancelPointer();
  }

  void _cancelPointer() {
    _pointer = null;
    _dragOpenedMenu = false;
    _holdTimer?.cancel();
    _holdTimer = null;
    _drivePress(_hovering ? 0.22 : 0.0);
    _springDragHome();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = widget.borderRadius;

    Widget content = Padding(padding: widget.padding, child: widget.child);
    if (widget.minSize != null) {
      content = ConstrainedBox(
        constraints: BoxConstraints(
          minWidth: widget.minSize!.width,
          minHeight: widget.minSize!.height,
        ),
        child: content,
      );
    }

    final hasMenuTrigger = widget.onMenuOpen != null;
    final style = widget.effectiveSurfaceStyle;

    Widget surface = AnimatedBuilder(
      animation: _motionListenable,
      builder: (_, child) {
        final p = _press.value;
        final drag = _dragOffset.value;

        var morphOpacity = 1.0;
        var morphScale = 1.0;
        if (hasMenuTrigger) {
          final (morphTarget, morphT) = activeAppMenuMorph.value;
          if (morphTarget != null &&
              identical(morphTarget, context.findRenderObject())) {
            final fadePhase = (morphT * 2.8).clamp(0.0, 1.0);
            morphOpacity = 1.0 - fadePhase;
            morphScale = 1.0 - 0.12 * fadePhase;
          }
        }
        // 按下改为按控件尺寸自适应的明显放大反馈，取消旧版下沉缩小与变暗阴影效果。
        final buttonBox = context.findRenderObject();
        final extent = buttonBox is RenderBox && buttonBox.hasSize
            ? buttonBox.size.longestSide
            : (widget.minSize?.longestSide ?? 36.0);
        final pressAmplitude = (0.07 + 8.4 / math.max(24.0, extent)).clamp(
          0.095,
          0.26,
        );
        final scale = (1.0 + pressAmplitude * p) * morphScale;

        Widget body = child!;
        if (widget.clipContent) {
          body = ClipRRect(borderRadius: radius, child: body);
        }

        if (style != TactileSurfaceStyle.transparent) {
          final Color bgColor;
          final List<BoxShadow>? boxShadow;
          switch (style) {
            case TactileSurfaceStyle.elevated:
              bgColor = scheme.surfaceContainerLowest;
              boxShadow = <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha: _interactive ? 0.045 : 0.02,
                  ),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ];
            case TactileSurfaceStyle.tinted:
              bgColor = scheme.surfaceContainerHigh.withValues(
                alpha: _interactive ? 0.56 : 0.28,
              );
              boxShadow = null;
            case TactileSurfaceStyle.transparent:
              bgColor = Colors.transparent;
              boxShadow = null;
          }
          body = DecoratedBox(
            decoration: BoxDecoration(
              color: bgColor,
              borderRadius: radius,
              boxShadow: boxShadow,
            ),
            child: body,
          );
        }

        // 保持动画子树结构在静态 / 按压 / 拖拽各帧间完全一致，避免动态增删 Transform
        // 导致内嵌 Material 按钮的 Element 与 TapGestureRecognizer 在按压中途被销毁。
        body = Transform.translate(
          offset: drag,
          child: Transform.scale(scale: scale, child: body),
        );
        if (hasMenuTrigger) {
          body = FadeTransition(
            opacity: AlwaysStoppedAnimation<double>(morphOpacity),
            child: body,
          );
        }
        return body;
      },
      child: content,
    );

    final hasSelfHandler = widget.onTap != null || hasMenuTrigger;

    surface = MouseRegion(
      cursor: _interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) {
        _hovering = true;
        if (_pointer == null && _interactive) _drivePress(0.22);
      },
      onExit: (_) {
        _hovering = false;
        if (_pointer == null) _drivePress(0.0);
      },
      child: Listener(
        behavior: hasSelfHandler
            ? HitTestBehavior.opaque
            : HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: surface,
      ),
    );

    if (hasSelfHandler) {
      // 直接接管点击/菜单的按钮需参与手势竞技场，避免嵌套在 InkWell / ListTile
      // 卡片内时被外层父容器同步触发点击跳转。
      surface = RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: _interactive
            ? <Type, GestureRecognizerFactory>{
                _TactileArenaRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                      _TactileArenaRecognizer
                    >(
                      () => _TactileArenaRecognizer(
                        debugOwner: this,
                        onArenaRejected: _onArenaRejected,
                      ),
                      (_TactileArenaRecognizer instance) {
                        instance.onArenaRejected = _onArenaRejected;
                        _arenaRecognizer = instance;
                      },
                    ),
              }
            : const <Type, GestureRecognizerFactory>{},
        child: surface,
      );
    }

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      // 可长按展开菜单的按钮屏蔽触控长按 Tooltip，保留桌面端悬停与无障碍提示，
      // 避免长按时弹出按钮名称并叠加一次长按震动。
      surface = Tooltip(
        message: widget.tooltip!,
        triggerMode: hasMenuTrigger ? TooltipTriggerMode.manual : null,
        enableFeedback: !hasMenuTrigger,
        child: surface,
      );
    }

    // 当组件自带直接触控回调时对外暴露语义点击，内嵌原生按钮的场景由内部 Button 自行提供，避免双重 Semantics 节点。
    if (widget.onTap != null || widget.onMenuOpen != null) {
      return Semantics(
        button: true,
        enabled: _interactive,
        onTap: _interactive
            ? () {
                if (widget.onMenuOpen != null) {
                  widget.onMenuOpen!(context, null);
                } else {
                  widget.onTap?.call();
                }
              }
            : null,
        child: surface,
      );
    }
    return surface;
  }
}

/// 仅用于参与 Flutter 手势竞技场仲裁，使自接管点击/菜单的 [TactileSurfaceButton]
/// 在嵌套于 [InkWell] / [ListTile] 卡片内时可靠独占点击与长按，不让外层容器同步触发，
/// 同时在未激活菜单前保留超出 slop 后交给外层滚动容器的能力。
class _TactileArenaRecognizer extends PrimaryPointerGestureRecognizer {
  _TactileArenaRecognizer({super.debugOwner, this.onArenaRejected})
    : super(postAcceptSlopTolerance: null);

  ValueChanged<int>? onArenaRejected;

  void claimPointer(int pointer) {
    if (primaryPointer == pointer && state == GestureRecognizerState.possible) {
      resolve(GestureDisposition.accepted);
    }
  }

  @override
  void handlePrimaryPointer(PointerEvent event) {
    if (event is PointerUpEvent) {
      resolve(GestureDisposition.accepted);
      stopTrackingPointer(event.pointer);
    } else if (event is PointerCancelEvent) {
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void rejectGesture(int pointer) {
    super.rejectGesture(pointer);
    onArenaRejected?.call(pointer);
  }

  @override
  String get debugDescription => 'tactile button arena';
}

/// 统一触控圆形图标按钮：内嵌无波纹 [IconButton] 保证测试与无障碍兼容，
/// 外层由 [TactileSurfaceButton] 提供柔和浅灰胶囊、按压回弹与轻跟随手感。
class TactileIconButton extends StatelessWidget {
  const TactileIconButton({
    super.key,
    this.buttonKey,
    required this.icon,
    this.tooltip,
    this.onPressed,
    this.color,
    this.size = 36,
    this.iconSize = 20,
    this.filled = true,
    this.surfaceStyle,
  });

  final Key? buttonKey;
  final Widget icon;
  final String? tooltip;
  final VoidCallback? onPressed;
  final Color? color;
  final double size;
  final double iconSize;
  final bool filled;
  final TactileSurfaceStyle? surfaceStyle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return TactileSurfaceButton(
      minSize: Size(size, size),
      borderRadius: BorderRadius.circular(size / 2),
      enabled: onPressed != null,
      filled: filled,
      surfaceStyle: surfaceStyle,
      child: SizedBox(
        width: size,
        height: size,
        child: IconButton(
          key: buttonKey,
          icon: icon,
          iconSize: iconSize,
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          style: TactileSurfaceButton.cleanIconButtonStyle(
            scheme,
            foregroundColor: color,
            size: size,
            iconSize: iconSize,
          ),
          onPressed: onPressed,
        ),
      ),
    );
  }
}

/// 二级页统一触控返回按钮：内部保留原生 [BackButton] 以完整兼容 `find.byType(BackButton)`
/// 与 `tester.pageBack()`，外观统一为 36×36 柔和圆胶囊并屏蔽 Material 旧水波纹。
class TactileBackButton extends StatelessWidget {
  const TactileBackButton({super.key, this.onPressed});

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 12),
        child: TactileSurfaceButton(
          minSize: const Size(36, 36),
          borderRadius: BorderRadius.circular(18),
          child: SizedBox(
            width: 36,
            height: 36,
            child: BackButton(
              onPressed: onPressed,
              style: TactileSurfaceButton.cleanIconButtonStyle(
                scheme,
                size: 36,
                iconSize: 20,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 统一操作按钮风格变体。
enum TactileActionVariant { filled, tonal, outlined, text }

/// 全应用统一触感操作按钮：复用 [TactileSurfaceButton] 按压缩放与微拖拽物理手感，
/// 内部保留原生 [FilledButton] / [OutlinedButton] / [TextButton] 语义与测试句柄，屏蔽 Material 旧水波纹。
class TactileActionButton extends StatelessWidget {
  const TactileActionButton({
    super.key,
    required this.onPressed,
    required this.label,
    this.icon,
    this.variant = TactileActionVariant.tonal,
    this.borderRadius = 999.0,
    this.padding,
    this.foregroundColor,
    this.backgroundColor,
    this.visualDensity,
    this.tapTargetSize,
    this.minimumSize,
    this.textStyle,
  });

  final VoidCallback? onPressed;
  final Widget label;
  final Widget? icon;
  final TactileActionVariant variant;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final VisualDensity? visualDensity;
  final MaterialTapTargetSize? tapTargetSize;
  final Size? minimumSize;
  final TextStyle? textStyle;

  ButtonStyle _sharedActionStyle({
    required RoundedRectangleBorder shape,
    BorderSide? side,
  }) {
    const noOverlay = WidgetStatePropertyAll<Color>(Colors.transparent);
    return ButtonStyle(
      splashFactory: NoSplash.splashFactory,
      shape: WidgetStatePropertyAll<OutlinedBorder>(shape),
      padding: padding != null
          ? WidgetStatePropertyAll<EdgeInsetsGeometry>(padding!)
          : null,
      visualDensity: visualDensity,
      tapTargetSize: tapTargetSize,
      minimumSize: minimumSize != null
          ? WidgetStatePropertyAll<Size>(minimumSize!)
          : null,
      textStyle: textStyle != null
          ? WidgetStatePropertyAll<TextStyle>(textStyle!)
          : null,
      side: side != null ? WidgetStatePropertyAll<BorderSide>(side) : null,
      elevation: const WidgetStatePropertyAll<double>(0),
      shadowColor: const WidgetStatePropertyAll<Color>(Colors.transparent),
      overlayColor: noOverlay,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(borderRadius);
    final shape = RoundedRectangleBorder(borderRadius: radius);
    final shared = _sharedActionStyle(shape: shape);

    final Widget inner;
    switch (variant) {
      case TactileActionVariant.filled:
        final style = FilledButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
        ).merge(shared);
        inner = icon != null
            ? FilledButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon!,
                label: label,
              )
            : FilledButton(onPressed: onPressed, style: style, child: label);
      case TactileActionVariant.tonal:
        final style = FilledButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
        ).merge(shared);
        inner = icon != null
            ? FilledButton.tonalIcon(
                onPressed: onPressed,
                style: style,
                icon: icon!,
                label: label,
              )
            : FilledButton.tonal(
                onPressed: onPressed,
                style: style,
                child: label,
              );
      case TactileActionVariant.outlined:
        final style =
            OutlinedButton.styleFrom(
              foregroundColor: foregroundColor,
              backgroundColor: backgroundColor,
            ).merge(
              _sharedActionStyle(
                shape: shape,
                side: BorderSide(
                  color: scheme.outlineVariant.withValues(alpha: 0.78),
                ),
              ),
            );
        inner = icon != null
            ? OutlinedButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon!,
                label: label,
              )
            : OutlinedButton(onPressed: onPressed, style: style, child: label);
      case TactileActionVariant.text:
        final style = TextButton.styleFrom(
          foregroundColor: foregroundColor,
          backgroundColor: backgroundColor,
        ).merge(shared);
        inner = icon != null
            ? TextButton.icon(
                onPressed: onPressed,
                style: style,
                icon: icon!,
                label: label,
              )
            : TextButton(onPressed: onPressed, style: style, child: label);
    }

    return TactileSurfaceButton(
      minSize: null,
      borderRadius: radius,
      filled: false,
      enabled: onPressed != null,
      child: inner,
    );
  }
}
