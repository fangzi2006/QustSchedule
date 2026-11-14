/// 带轻描边与物理手感的灵动触控按钮：支持按压回弹、跟手微拖拽以及"按住下拉直接滑入菜单"。
///
/// 为什么用底层 [Listener] 追踪按压/拖拽形变而不是包一层 `GestureDetector`：
///  - 避免与内部的 [IconButton]（例如刷新、前后翻周，单测会通过 `widgetWithIcon(IconButton, ...)` 查找）抢夺手势竞技场；
///  - 点按、长按、下拉滑入菜单三种交互共用同一套弹簧状态，无跳变切换。
library;

import 'dart:async' show Timer;
import 'dart:math' as math;

import 'package:flutter/gestures.dart' show PointerDeviceKind, kPrimaryButton;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart' show SpringDescription, SpringSimulation;

import 'app_menu.dart' show activeAppMenuMorph;

/// 当菜单触发按钮被点击或按住下拉展开时的回调。
///
/// [dragPointer] 不为 null 时，表示用户按住未松手并已长按或下拉，菜单可直接接管这根手指。
typedef TactileMenuTrigger = void Function(
  BuildContext anchorContext,
  int? dragPointer,
);

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
  final String? tooltip;

  /// 给内嵌 [IconButton] 使用的干净样式：关闭旧式水波纹与灰底阴影，保留无障碍与查找兼容性。
  static ButtonStyle cleanIconButtonStyle(ColorScheme scheme) =>
      IconButton.styleFrom(
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        disabledForegroundColor: scheme.onSurface.withValues(alpha: 0.34),
      );

  @override
  State<TactileSurfaceButton> createState() => _TactileSurfaceButtonState();
}

class _TactileSurfaceButtonState extends State<TactileSurfaceButton>
    with TickerProviderStateMixin {
  static const SpringDescription _pressSpring = SpringDescription(
    mass: 1.0,
    stiffness: 640.0,
    damping: 30.0,
  );
  static const SpringDescription _releaseSpring = SpringDescription(
    mass: 1.0,
    stiffness: 460.0,
    damping: 20.0,
  );
  static const SpringDescription _rubberSpring = SpringDescription(
    mass: 1.0,
    stiffness: 440.0,
    damping: 21.0,
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
  Offset _dragFrom = Offset.zero;
  Offset _dragTarget = Offset.zero;
  bool _hovering = false;
  bool _dragOpenedMenu = false;
  Timer? _holdTimer;

  bool get _interactive => widget.enabled;

  @override
  void initState() {
    super.initState();
    _dragAnim.addListener(_syncDragOffset);
  }

  void _syncDragOffset() {
    _dragOffset.value =
        Offset.lerp(_dragFrom, _dragTarget, _dragAnim.value) ?? _dragTarget;
  }

  @override
  void didUpdateWidget(TactileSurfaceButton oldWidget) {
    super.didUpdateWidget(oldWidget);
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

  void _openMenuWithDrag(int pointer) {
    if (_dragOpenedMenu || !_interactive || widget.onMenuOpen == null) return;
    _dragOpenedMenu = true;
    _holdTimer?.cancel();
    _holdTimer = null;
    _drivePress(_hovering ? 0.35 : 0.0);
    _springDragHome();
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
    final delta = event.position - _downPos;
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
    _drivePress(_hovering ? 0.35 : 0.0);
    _springDragHome();

    if (wasOpened) return;
    // 如果没有内嵌 IconButton（即按钮本身直接接管点击），在这里触发点击或短按展开菜单。
    final renderBox = context.findRenderObject();
    if (renderBox is RenderBox && renderBox.hasSize) {
      final local = renderBox.globalToLocal(event.position);
      final hitBounds = renderBox.paintBounds.inflate(6.0);
      if (hitBounds.contains(local)) {
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
    _drivePress(_hovering ? 0.35 : 0.0);
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

    Widget surface = AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        _press,
        _dragOffset,
        activeAppMenuMorph,
      ]),
      builder: (_, child) {
        final p = _press.value;
        final pressT = p.clamp(0.0, 1.2);
        final scale = 1.0 - 0.055 * p;
        final drag = _dragOffset.value;

        final (morphTarget, morphT) = activeAppMenuMorph.value;
        final isOwnMenuOpen =
            morphTarget != null &&
            identical(morphTarget, context.findRenderObject());
        final morphOpacity = isOwnMenuOpen
            ? (1.0 - morphT * 3.5).clamp(0.0, 1.0)
            : 1.0;

        // 统一柔和浅灰底胶囊：平时无生硬白框，仅靠柔和底色统一形制；按下时带微主色反馈。
        final restFill = scheme.surfaceContainerHigh.withValues(
          alpha: _interactive ? 0.56 : 0.28,
        );
        final activeFill = Color.alphaBlend(
          scheme.primary.withValues(alpha: 0.12),
          scheme.surfaceContainerLowest,
        );
        final bgColor = widget.filled
            ? Color.lerp(restFill, activeFill, pressT.clamp(0.0, 1.0))
            : Colors.transparent;
        final activeRim = _interactive && pressT > 0.02
            ? scheme.primary.withValues(alpha: 0.28 * pressT.clamp(0.0, 1.0))
            : Colors.transparent;

        return FadeTransition(
          opacity: AlwaysStoppedAnimation<double>(morphOpacity),
          child: Transform.translate(
            offset: drag,
            child: Transform.scale(
              scale: scale,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: radius,
                  border: activeRim.a > 0
                      ? Border.all(color: activeRim, width: 1.0)
                      : null,
                ),
                child: ClipRRect(borderRadius: radius, child: child),
              ),
            ),
          ),
        );
      },
      child: content,
    );

    surface = MouseRegion(
      cursor: _interactive
          ? SystemMouseCursors.click
          : SystemMouseCursors.basic,
      onEnter: (_) {
        _hovering = true;
        if (_pointer == null && _interactive) _drivePress(0.35);
      },
      onExit: (_) {
        _hovering = false;
        if (_pointer == null) _drivePress(0.0);
      },
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: _onPointerDown,
        onPointerMove: _onPointerMove,
        onPointerUp: _onPointerUp,
        onPointerCancel: _onPointerCancel,
        child: surface,
      ),
    );

    if (widget.tooltip != null && widget.tooltip!.isNotEmpty) {
      surface = Tooltip(message: widget.tooltip!, child: surface);
    }

    return Semantics(button: true, enabled: _interactive, child: surface);
  }
}
