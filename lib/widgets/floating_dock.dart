/// 底部悬浮 dock：在各主标签页（课表 / 学业 / 设置）之间切换。
///
/// 外观：纯色胶囊 + 细描边 + 阴影，**不用毛玻璃**：`BackdropFilter` 在 Windows
/// 桌面上每帧都要重绘下层，滚动课表时明显掉帧。
///
/// 动效（"液态透镜"，参考 FlClash / iOS 26 标签栏）：
///  - **按下**：指示块从 dock 里"鼓"出来，变成比 dock 还高的半透明透镜
///    （主色细描边，无模糊高光带与独立投影），透镜下的图标与文字同步裁剪着色并原地放大；
///    松手缩回 dock 并回弹；
///  - **拖动**：透镜带一点点滞后地跟随手指（不是生硬贴着手指）；
///  - **流动形变**：透镜按**实际移动速度**沿运动方向拉长、前缘领先后缘跟随，
///    停下时用欠阻尼弹簧反向挤压一下再回圆，产生"果冻 / 水滴"的余震；
///  - **点击切换**：指示块中心走临界阻尼弹簧（无往返），形变由速度自动产生，
///    所以点击也有"液体流过去"的拉伸与落点回弹。
///
/// 页面同步：外壳的页面位移只跟**指示块中心**走（见 [_reportPillProgress]），
/// 形变/放大都是纯视觉，不影响中心位置 —— 所以页面平移依旧单调、无回弹。
///
/// 交互是"整条可按住滑动"：在胶囊任意位置按下并左右拖，松手才真正切页。
/// "松手切到哪一页"按等宽分段判定（阈值在等分点上，不在按钮中心），
/// 指示块**落点**则用实测的按钮矩形（GlobalKey + `localToGlobal`）。
library;

import 'dart:async' show unawaited;
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, listEquals, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart'
    show SpringDescription, SpringSimulation, Tolerance;
import 'package:flutter/scheduler.dart' show Ticker;
import 'package:flutter/services.dart' show HapticFeedback;

class FloatingDockItem {
  final IconData icon;
  final IconData activeIcon;
  final String label;

  const FloatingDockItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
  });
}

class FloatingDock extends StatefulWidget {
  const FloatingDock({
    super.key,
    required this.items,
    required this.index,
    this.onTap,
    this.onDragEnd,
    this.onPillProgress,
    this.onPressStart,
    this.onTargetIndexHint,
  });

  final List<FloatingDockItem> items;
  final int index;

  /// 用户**点**了某一项（没拖动）。不传则只靠 [onPillProgress] 同步页。
  final ValueChanged<int>? onTap;

  /// 用户**按住拖动后松手**，松手时指示块停在下标 `index`。
  final ValueChanged<int>? onDragEnd;

  /// 指示块中心滑到首末两项中心的哪一段（0..1）。
  final ValueChanged<double>? onPillProgress;

  /// 指针按下的那一帧（还没动）：外壳利用这瞬间提前唤醒下一页。
  final VoidCallback? onPressStart;

  /// 指针按下或横向滑动进入某分段时通知目标下标，便于按需单页懒建。
  final ValueChanged<int>? onTargetIndexHint;

  /// 外壳用它加底部留白：让页面最后一行不被悬浮条压住。
  static const double height = 58;
  static const double bottomMargin = 16;

  static double contentInset(BuildContext context) =>
      height + bottomMargin * 2 + MediaQuery.of(context).padding.bottom;

  @visibleForTesting
  static Path buildLensPathForTest(Rect rect) => _buildLensPath(rect);

  @visibleForTesting
  static Path buildOutsideLensClipForTest(Rect rect, Size size) =>
      _OutsideLensClipper(rect: rect, path: _buildLensPath(rect)).getClip(size);

  @override
  State<FloatingDock> createState() => FloatingDockState();
}

class FloatingDockState extends State<FloatingDock>
    with TickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _itemKeys = <GlobalKey>[];
  List<Rect> _rects = const <Rect>[];
  List<_LensGlyphEntry> _cachedGlyphs = const <_LensGlyphEntry>[];
  final List<_LensGlyphEntry> _pendingDisposeGlyphs = <_LensGlyphEntry>[];
  Color? _cachedGlyphPrimaryColor;
  List<FloatingDockItem>? _cachedGlyphItems;
  List<Rect>? _cachedGlyphRects;

  /// 拖动中的即时高亮项（指针还没松，index 还没真切过去）。
  late int _preview;
  bool _pressed = false;
  bool _dragging = false;
  bool _hovering = false;

  /// 手指此刻的位置（已夹在 0..胶囊宽 内）。
  double _dragX = 0;

  /// 透镜中心实际所在的 x：拖动时以轻微滞后追随 [_dragX]。
  double _followX = 0;

  /// 手指未夹紧的原始 x：越过两端的量用来做边缘橡皮筋。
  double _rawDragX = 0;
  double _dockWidth = 0;

  // ───────────────────────── 弹簧参数 ─────────────────────────

  /// 指示块中心位置弹簧：临界阻尼，快启轻收、无水平往返，保证页面位移单调。
  static const SpringDescription _slideSpring = SpringDescription(
    mass: 1.0,
    stiffness: 1150.0,
    damping: 68.0,
  );
  static const Tolerance _slideTolerance = Tolerance(
    distance: 2e-3,
    velocity: 4e-2,
  );

  /// 透镜鼓起：鼓起带轻微弹性过冲；回落使用接近临界阻尼，避免零点往复触发阴影闪烁。
  static const SpringDescription _liftUpSpring = SpringDescription(
    mass: 1.0,
    stiffness: 520.0,
    damping: 22.0,
  );
  static const SpringDescription _liftDownSpring = SpringDescription(
    mass: 1.0,
    stiffness: 420.0,
    damping: 36.0,
  );

  /// 边缘橡皮筋回弹。
  static const SpringDescription _edgeSpring = SpringDescription(
    mass: 1.0,
    stiffness: 420.0,
    damping: 18.0,
  );

  /// 拖动时透镜追手指的速率（越大越贴手；28 ≈ 一帧内追上约 37%）。
  static const double _followRate = 28.0;

  /// 速度形变弹簧（自己积分的欠阻尼振子：k=刚度，c=阻尼；阻尼比约 0.4）。
  static const double _stretchK = 340.0;
  static const double _stretchC = 15.0;

  /// 多快的移动算"满形变"（逻辑像素 / 秒）。
  static const double _fullStretchSpeed = 1500.0;

  // ───────────────────────── 动画状态 ─────────────────────────

  /// 指示块中心的滑动：0 → 1 表示从 [_from] 滑到 [_to]。
  late final AnimationController _slide = AnimationController.unbounded(
    vsync: this,
    value: 1,
  );

  /// 透镜鼓起程度：0 = 平贴在 dock 里；悬停 ≈ 0.25；按下/拖动 = 1。
  late final AnimationController _lift = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  /// 越过两端时整条 dock 的橡皮筋位移（逻辑像素）。
  late final AnimationController _edge = AnimationController.unbounded(
    vsync: this,
    value: 0,
  );

  /// 物理帧：负责"追手指"、测速度、积分形变振子。只在有东西在动时运行。
  late final Ticker _physics = createTicker(_onPhysicsTick);
  Duration _lastTick = Duration.zero;
  double _lastCx = 0;

  /// 形变量（带符号：正 = 向右运动的拉伸，负 = 向左；停下后会过冲到反向）。
  double _stretch = 0;
  double _stretchVel = 0;

  /// 每个物理帧 +1，驱动透镜与按钮重绘（不走 setState，避免整条重建）。
  final ValueNotifier<int> _physicsFrame = ValueNotifier<int>(0);

  Rect _from = Rect.zero;
  Rect _to = Rect.zero;
  int _slideGen = 0;

  // ───────────────────────── 生命周期 ─────────────────────────

  @override
  void initState() {
    super.initState();
    _preview = widget.index;
    _syncKeys();
    // 指示块自己的滑动（按下 / 松手 / 取消）也要逐帧报给外壳。
    _slide.addListener(_reportPillProgress);
  }

  @override
  void didUpdateWidget(FloatingDock oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.items.length != widget.items.length) {
      _syncKeys();
      _rects = const <Rect>[];
    }
    // `_pressed` 也要排除：手指还按着时页面先到位了，此时把指示块拽到按钮中心
    // 会从手指底下滑走。
    if (!_dragging && !_pressed && oldWidget.index != widget.index) {
      if (_preview != widget.index) {
        _preview = widget.index;
        if (_rects.length == widget.items.length) {
          _placePill(_rects[widget.index]);
          _reportPillProgress();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposeGlyphCache();
    _slide.removeListener(_reportPillProgress);
    _physics.dispose();
    _physicsFrame.dispose();
    _slide.dispose();
    _lift.dispose();
    _edge.dispose();
    super.dispose();
  }

  void _disposeGlyphCache() {
    for (final entry in _cachedGlyphs) {
      entry.dispose();
    }
    for (final entry in _pendingDisposeGlyphs) {
      entry.dispose();
    }
    _cachedGlyphs = const <_LensGlyphEntry>[];
    _pendingDisposeGlyphs.clear();
    _cachedGlyphPrimaryColor = null;
    _cachedGlyphItems = null;
    _cachedGlyphRects = null;
  }

  List<_LensGlyphEntry> _resolveGlyphs(Color primaryColor) {
    final count = math.min(widget.items.length, _rects.length);
    if (_cachedGlyphPrimaryColor == primaryColor &&
        listEquals(_cachedGlyphItems, widget.items) &&
        identical(_cachedGlyphRects, _rects) &&
        _cachedGlyphs.length == count) {
      return _cachedGlyphs;
    }
    if (_cachedGlyphs.isNotEmpty) {
      // 延后到本帧绘制结束后再释放旧 TextPainter，避免极少数中断帧读到已释放对象。
      final stale = _cachedGlyphs;
      _pendingDisposeGlyphs.addAll(stale);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        for (final entry in stale) {
          entry.dispose();
          _pendingDisposeGlyphs.remove(entry);
        }
      });
    }
    final entries = <_LensGlyphEntry>[
      for (var i = 0; i < count; i++)
        _LensGlyphEntry.layout(
          item: widget.items[i],
          itemRect: _rects[i],
          primaryColor: primaryColor,
        ),
    ];
    _cachedGlyphs = entries;
    _cachedGlyphPrimaryColor = primaryColor;
    _cachedGlyphItems = List<FloatingDockItem>.of(
      widget.items,
      growable: false,
    );
    _cachedGlyphRects = _rects;
    return entries;
  }

  void _syncKeys() {
    _itemKeys
      ..clear()
      ..addAll(<GlobalKey>[
        for (var i = 0; i < widget.items.length; i++)
          GlobalKey(debugLabel: 'dock-$i'),
      ]);
  }

  /// 按钮矩形是否均已测量就绪，可供动画驱动。
  bool get canAnimate => _rects.length == widget.items.length;

  /// 编程式平滑滑动到指定项（例如点击通知气泡时由外壳驱动）。
  void animateToIndex(int target) {
    if (target < 0 || target >= widget.items.length) return;
    widget.onTargetIndexHint?.call(target);
    if (_rects.length != widget.items.length) {
      _preview = target;
      return;
    }
    setState(() {
      _pressed = false;
      _dragging = false;
      _preview = target;
      _snapTo(_rects[target]);
    });
    _syncLift();
    _reportPillProgress();
  }

  // ───────────────────────── 物理帧 ─────────────────────────

  void _ensurePhysics() {
    if (_physics.isActive) return;
    _lastTick = Duration.zero;
    _lastCx = _livePillRect.center.dx;
    _physics.start();
  }

  void _onPhysicsTick(Duration elapsed) {
    if (!mounted) return;
    final double dt = ((elapsed - _lastTick).inMicroseconds / 1e6).clamp(
      0.0,
      0.05,
    );
    _lastTick = elapsed;
    if (dt <= 0) return;

    // 1. 拖动时：透镜带轻微滞后追随手指（指数趋近，帧率无关）。
    if (_dragging) {
      final double k = 1 - math.exp(-_followRate * dt);
      _followX += (_dragX - _followX) * k;
      if ((_dragX - _followX).abs() < 0.05) _followX = _dragX;
      _reportPillProgress();
    }

    // 2. 用透镜**实际**移动速度驱动形变振子：动得快就拉长，停下就过冲挤压再回圆。
    final double cx = _livePillRect.center.dx;
    final double v = (cx - _lastCx) / dt;
    _lastCx = cx;
    final double target = (v / _fullStretchSpeed).clamp(-1.0, 1.0);
    final double acc =
        _stretchK * (target - _stretch) - _stretchC * _stretchVel;
    _stretchVel += acc * dt;
    _stretch += _stretchVel * dt;
    _stretch = _stretch.clamp(-1.2, 1.2);

    _physicsFrame.value++;

    // 3. 全部静止后停帧（pumpAndSettle / 省电都依赖这一点）。
    final bool chasing = _dragging && (_dragX - _followX).abs() > 0.05;
    final bool settled =
        !chasing &&
        !_slide.isAnimating &&
        target.abs() < 1e-3 &&
        _stretch.abs() < 2e-3 &&
        _stretchVel.abs() < 1e-2;
    if (settled && !_dragging) {
      _stretch = 0;
      _stretchVel = 0;
      _physicsFrame.value++;
      _physics.stop();
    }
  }

  // ───────────────────────── 指示块位置 ─────────────────────────

  /// 按当前交互状态把透镜鼓起程度推到该有的值。
  void _syncLift() {
    final target = (_dragging || _pressed) ? 1.0 : (_hovering ? 0.25 : 0.0);
    final spring = target > _lift.value ? _liftUpSpring : _liftDownSpring;
    _lift.animateWith(SpringSimulation(spring, _lift.value, target, 0));
  }

  /// 触发跨项轻触震动反馈（仅移动端，桌面端保持安静）。
  void _hapticTick() {
    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      unawaited(HapticFeedback.selectionClick());
    }
  }

  /// 指示块当前（非拖动时）应该在哪。
  Rect get _pillRect {
    // 弹簧收敛后直接对齐 `_to`，避免仿真容差造成 0.999x 的亚像素悬停；
    // 运行期间钳制在 0..1，保证水平单调无越界。
    final double t = _slide.value.clamp(0.0, 1.0);
    if (!_slide.isAnimating || t >= 1.0) return _to;
    return Rect.lerp(_from, _to, t) ?? _to;
  }

  /// 直接到位（首次布局、外部切页时用）。
  void _placePill(Rect rect) {
    ++_slideGen;
    _slide.stop();
    _slide.value = 1.0;
    _from = rect;
    _to = rect;
  }

  /// 用临界阻尼弹簧把指示块中心滑到 [rect]。
  ///
  /// [from] 用于"调用者即将改掉 `_dragging`"的场合：那时 [_livePillRect] 已经
  /// 不再指向透镜位置了，必须在改状态**之前**把起点取出来传进来。
  void _snapTo(Rect rect, {Rect? from}) {
    if (_to == rect && from == null) return;
    _from = from ?? _pillRect;
    _to = rect;
    final int gen = ++_slideGen;
    _slide.stop();
    _slide
        .animateWith(
          SpringSimulation(
            _slideSpring,
            0.0,
            1.0,
            0.0,
            tolerance: _slideTolerance,
          ),
        )
        .whenCompleteOrCancel(() {
          if (!mounted || gen != _slideGen || _dragging || _slide.isAnimating) {
            return;
          }
          _slide.value = 1.0;
          _reportPillProgress();
        });
    _ensurePhysics();
  }

  /// 量出每个按钮的矩形。只在结果**真的变了**才 setState，否则会自激死循环。
  void _measure() {
    if (!mounted) return;
    final box = _stackKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _dockWidth = box.size.width;
    final measured = <Rect>[];
    for (final key in _itemKeys) {
      final itemRender = key.currentContext?.findRenderObject();
      if (itemRender is! RenderBox || !itemRender.hasSize) return;
      final topLeft = itemRender.localToGlobal(Offset.zero, ancestor: box);
      measured.add(topLeft & itemRender.size);
    }
    if (!_rectsChanged(measured)) return;
    setState(() {
      _rects = measured;
      if (measured.isEmpty) {
        _placePill(Rect.zero);
        return;
      }
      final target = measured[_preview.clamp(0, measured.length - 1)];
      if (_to.isEmpty) {
        _placePill(target);
      } else {
        _snapTo(target);
      }
    });
  }

  bool _rectsChanged(List<Rect> next) {
    if (_rects.length != next.length) return true;
    for (var i = 0; i < next.length; i++) {
      final a = _rects[i];
      final b = next[i];
      if ((a.left - b.left).abs() > 0.5 ||
          (a.top - b.top).abs() > 0.5 ||
          (a.width - b.width).abs() > 0.5 ||
          (a.height - b.height).abs() > 0.5) {
        return true;
      }
    }
    return false;
  }

  double _rawLocalX(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0;
    return box.globalToLocal(global).dx;
  }

  double _clampX(double x) =>
      _dockWidth <= 0 ? 0 : x.clamp(0.0, _dockWidth).toDouble();

  /// 指针 x（0..胶囊宽）映射到按钮连续下标 `0 .. n-1`。
  double _positionAt(double x) {
    final n = _rects.length;
    if (n <= 1) return 0;
    if (_dockWidth <= 0) return 0;
    final half = _dockWidth / (2 * n);
    final usable = _dockWidth - 2 * half;
    if (usable <= 0) return 0;
    return ((x - half) / usable).clamp(0.0, 1.0) * (n - 1);
  }

  Rect _rectAt(double position) {
    if (_rects.isEmpty) return Rect.zero;
    if (_rects.length == 1) return _rects.first;
    final max = _rects.length - 1;
    final clamped = position.clamp(0.0, max.toDouble());
    final index = clamped.floor().clamp(0, max - 1);
    final next = (index + 1).clamp(0, max);
    final t = (clamped - index).clamp(0.0, 1.0);
    return Rect.lerp(_rects[index], _rects[next], t) ?? _rects[index];
  }

  int _indexAt(double x) {
    final n = _rects.length;
    if (n <= 1) return widget.index;
    if (_dockWidth <= 0) return widget.index;
    // 每段占 1/n 宽，落在哪段就是哪项——阈值在等分点上，不在按钮中心。
    return (x / (_dockWidth / n)).floor().clamp(0, n - 1);
  }

  /// 指示块矩形：**中心对准 x**，尺寸取所在位置插值出的按钮大小。
  Rect _centeredAt(double x) {
    if (_rects.isEmpty) return Rect.zero;
    final base = _rectAt(_positionAt(x));
    final half = base.width / 2;
    final cx = x.clamp(half, math.max(half, _dockWidth - half)).toDouble();
    return Rect.fromCenter(
      center: Offset(cx, base.center.dy),
      width: base.width,
      height: base.height,
    );
  }

  /// 指示块中心此刻**真的**在哪。拖动时跟透镜（带滞后），其余时候由弹簧决定。
  /// 画和"上报给页面的位置"必须用同一个值，否则页面会比透镜快/慢半拍。
  Rect get _livePillRect => _dragging ? _centeredAt(_followX) : _pillRect;

  /// 把指示块中心换算成 0..1，报给外壳（页面跟着这个值平移）。
  void _reportPillProgress() {
    final ValueChanged<double>? callback = widget.onPillProgress;
    if (callback == null || _rects.length < 2) return;
    final double first = _rects.first.center.dx;
    final double last = _rects.last.center.dx;
    final double span = last - first;
    if (span.abs() < 0.001) return;
    final double center = _livePillRect.center.dx;
    callback(((center - first) / span).clamp(0.0, 1.0));
  }

  // ───────────────────────── 边缘橡皮筋 ─────────────────────────

  static double _rubber(double over, double maxPull) {
    if (over == 0) return 0;
    return over.sign * maxPull * (1.0 - math.exp(-over.abs() / 60.0));
  }

  void _updateEdgePull() {
    if (_dockWidth <= 0) return;
    final double over = _rawDragX < 0
        ? _rawDragX
        : (_rawDragX > _dockWidth ? _rawDragX - _dockWidth : 0.0);
    _edge.stop();
    _edge.value = _rubber(over, 10.0);
  }

  void _releaseEdge() {
    if (_edge.value.abs() < 0.05) {
      _edge.stop();
      _edge.value = 0;
      return;
    }
    _edge.animateWith(SpringSimulation(_edgeSpring, _edge.value, 0, 0));
  }

  // ───────────────────────── 手势 ─────────────────────────

  /// 指针按下（还没拖）：透镜鼓起并立刻滑向指针；同时页面开始跟着走。
  void _onPressDown(DragDownDetails details) {
    if (_rects.length != widget.items.length) return;
    final double x = _clampX(_rawLocalX(details.globalPosition));
    final int target = _indexAt(x);
    widget.onTargetIndexHint?.call(target);
    widget.onPressStart?.call();
    if (target != _preview) _hapticTick();
    setState(() {
      _pressed = true;
      _preview = target;
      _snapTo(_centeredAt(x));
    });
    _syncLift();
    _reportPillProgress();
  }

  void _onDragStart(DragStartDetails details) {
    if (_rects.length != widget.items.length) return;
    _rawDragX = _rawLocalX(details.globalPosition);
    final double x = _clampX(_rawDragX);
    final int nextPreview = _indexAt(x);
    if (nextPreview != _preview) {
      _hapticTick();
      widget.onTargetIndexHint?.call(nextPreview);
    }
    // 透镜从它当前所在的位置开始追手指，而不是瞬移到手指下。
    final double startX = _livePillRect.center.dx;
    setState(() {
      _dragging = true;
      _dragX = x;
      _followX = startX;
      _preview = nextPreview;
    });
    ++_slideGen;
    _slide.stop();
    _updateEdgePull();
    _syncLift();
    _ensurePhysics();
    _reportPillProgress();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    _rawDragX = _rawLocalX(details.globalPosition);
    final double x = _clampX(_rawDragX);
    final int nextPreview = _indexAt(x);
    if (nextPreview != _preview) {
      _hapticTick();
      widget.onTargetIndexHint?.call(nextPreview);
      setState(() => _preview = nextPreview);
    }
    _dragX = x;
    _updateEdgePull();
    _ensurePhysics();
  }

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    final int target = _preview.clamp(0, widget.items.length - 1);
    // 必须在清 `_dragging` **之前**取起点：那之后 `_livePillRect` 就不再指向透镜。
    final Rect from = _livePillRect;
    setState(() {
      _dragging = false;
      _pressed = false;
      _preview = target;
      _snapTo(_rects.isEmpty ? Rect.zero : _rects[target], from: from);
    });
    _releaseEdge();
    _syncLift();
    // 覆盖"透镜本来就在目标上、动画不启动"的情况（否则页面会停在半路）。
    _reportPillProgress();
  }

  void _onDragCancel() {
    // 没真的拖起来过 → 这是"点击赢了手势仲裁"，松手交给 `_onTapUp`。
    if (!_dragging) return;
    final Rect from = _livePillRect;
    setState(() {
      _dragging = false;
      _pressed = false;
      if (_rects.isNotEmpty) _snapTo(_rects[_preview], from: from);
    });
    _releaseEdge();
    _syncLift();
    _reportPillProgress();
  }

  void _onTapUp(TapUpDetails details) {
    if (_rects.length != widget.items.length) {
      setState(() => _pressed = false);
      _syncLift();
      return;
    }
    final int target = _indexAt(_clampX(_rawLocalX(details.globalPosition)));
    setState(() {
      _pressed = false;
      _preview = target;
      // 手指可能落在按钮边缘：松手后归位到按钮本身。
      _snapTo(_rects[target]);
    });
    _releaseEdge();
    _syncLift();
    _reportPillProgress();
  }

  void _onTapCancel() {
    // 点击没成立（被拖动接管或被系统取消）：按下时已经报过目标，这里**不**往回撤。
    setState(() {
      _pressed = false;
      if (!_dragging && _rects.length == widget.items.length) {
        _snapTo(_rects[_preview]);
      }
    });
    _syncLift();
    _reportPillProgress();
  }

  // ───────────────────────── 绘制 ─────────────────────────

  /// 透镜的最终绘制矩形：在中心位置的基础上叠加鼓起与速度形变。
  Rect _lensRect(Rect base, double lift, double stretch) {
    final double l = lift.clamp(-0.15, 1.3);
    final double s = stretch.clamp(-1.2, 1.2);
    final double mag = s.abs();
    // 鼓起：宽 +16%、高 +34%（46 → ~62，温和鼓出 58 高的 dock 上下沿）。
    double w = base.width * (1 + 0.16 * l);
    double h = base.height * (1 + 0.34 * l);
    // 形变：沿运动方向拉长、竖向收窄；反向过冲时（s 与运动方向相反）同样成立，
    // 视觉上就是停下瞬间"挤一下再回圆"。
    w *= 1 + 0.30 * mag;
    h *= 1 - 0.14 * mag;
    // 前缘领先：中心朝运动方向偏一点，于是前缘走在前面、后缘拖在后面。
    final double lead = s * base.width * 0.08;
    return Rect.fromCenter(
      center: base.center.translate(lead, 0),
      width: w,
      height: h,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 布局完成才知道按钮在哪：每帧补一次测量，量到就不再来。
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

    return Padding(
      padding: EdgeInsets.only(
        bottom:
            FloatingDock.bottomMargin + MediaQuery.of(context).padding.bottom,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const idealItemWidth = 74.0;
          const idealGap = 10.0;
          const shellHPad = 6.0;
          final count = widget.items.length;
          final idealTotal =
              shellHPad * 2 +
              count * idealItemWidth +
              math.max(0, count - 1) * idealGap;
          final maxAvailable = constraints.maxWidth.isFinite
              ? math.max(120.0, constraints.maxWidth - 24.0)
              : idealTotal;
          final ratio = maxAvailable >= idealTotal
              ? 1.0
              : ((maxAvailable - shellHPad * 2) /
                        math.max(1.0, idealTotal - shellHPad * 2))
                    .clamp(0.58, 1.0);
          final itemMinWidth = idealItemWidth * ratio;
          final itemGap = maxAvailable >= idealTotal
              ? idealGap
              : math.max(2.0, idealGap * ratio);

          return Center(
            child: MouseRegion(
              onEnter: (_) {
                _hovering = true;
                _syncLift();
              },
              onExit: (_) {
                _hovering = false;
                _syncLift();
              },
              child: GestureDetector(
                // 整条胶囊都是操作区：按钮之间的留白、两侧内边距都算。
                behavior: HitTestBehavior.opaque,
                onTapUp: _onTapUp,
                onTapCancel: _onTapCancel,
                onHorizontalDragDown: _onPressDown,
                onHorizontalDragStart: _onDragStart,
                onHorizontalDragUpdate: _onDragUpdate,
                onHorizontalDragEnd: _onDragEnd,
                onHorizontalDragCancel: _onDragCancel,
                child: AnimatedBuilder(
                  animation: Listenable.merge(<Listenable>[_lift, _edge]),
                  builder: (context, child) {
                    final double t = _lift.value.clamp(0.0, 1.2);
                    return Transform.translate(
                      offset: Offset(_edge.value, 0),
                      child: Transform.scale(
                        // 整条 dock 只做很轻的呼吸，主角是透镜。
                        scale: 1 + 0.015 * t,
                        child: Container(
                          height: FloatingDock.height,
                          padding: const EdgeInsets.symmetric(
                            horizontal: shellHPad,
                          ),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(
                              FloatingDock.height / 2,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.17),
                                blurRadius: 30,
                                spreadRadius: 1.5,
                                offset: const Offset(0, 12),
                              ),
                            ],
                            border: Border.all(
                              color: scheme.outlineVariant.withValues(
                                alpha: 0.36,
                              ),
                            ),
                          ),
                          child: child,
                        ),
                      ),
                    );
                  },
                  child: Builder(
                    builder: (context) {
                      // 必须先与纯白底色预混合，避免 Color.lerp 在半透插值中段产生暗灰蓝色阶下陷（变深→变浅）。
                      final restColor = Color.alphaBlend(
                        scheme.primary.withValues(alpha: 0.11),
                        scheme.surfaceContainerLowest,
                      );
                      final lensColor = Color.alphaBlend(
                        scheme.primary.withValues(alpha: 0.04),
                        scheme.surfaceContainerLowest,
                      ).withValues(alpha: 0.92);
                      final rimColor = scheme.primary.withValues(alpha: 0.22);
                      final glyphs = _resolveGlyphs(scheme.primary);

                      return AnimatedBuilder(
                        animation: Listenable.merge(<Listenable>[
                          _slide,
                          _lift,
                          _physicsFrame,
                        ]),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            for (
                              var position = 0;
                              position < widget.items.length;
                              position++
                            ) ...<Widget>[
                              if (position > 0) SizedBox(width: itemGap),
                              _DockButton(
                                key: _itemKeys[position],
                                item: widget.items[position],
                                minWidth: itemMinWidth,
                              ),
                            ],
                          ],
                        ),
                        builder: (context, child) {
                          final base = _livePillRect;
                          final valid = _isValidLensRect(base);
                          final lensRect = valid
                              ? _lensRect(base, _lift.value, _stretch)
                              : Rect.zero;
                          final Path lensPath = valid
                              ? _buildLensPath(lensRect)
                              : Path();
                          final double liftClamped = _lift.value.clamp(
                            0.0,
                            1.0,
                          );

                          return Stack(
                            key: _stackKey,
                            // 透镜鼓起时比 dock 还高，不能被裁掉。
                            clipBehavior: Clip.none,
                            // 必须显式居中：Stack 默认 topStart，按钮会被顶到胶囊上沿。
                            alignment: Alignment.center,
                            children: <Widget>[
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: valid
                                      ? CustomPaint(
                                          painter: _LensBackdropPainter(
                                            rect: lensRect,
                                            path: lensPath,
                                            lift: liftClamped,
                                            restColor: restColor,
                                            lensColor: lensColor,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                              ClipPath(
                                clipper: _OutsideLensClipper(
                                  rect: lensRect,
                                  path: lensPath,
                                ),
                                child: child,
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: valid
                                      ? CustomPaint(
                                          painter: _LensForegroundPainter(
                                            rect: lensRect,
                                            path: lensPath,
                                            lift: liftClamped,
                                            glyphs: glyphs,
                                            rimColor: rimColor,
                                          ),
                                        )
                                      : const SizedBox.shrink(),
                                ),
                              ),
                            ],
                          );
                        },
                      );
                    },
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

bool _isValidLensRect(Rect rect) =>
    !rect.isEmpty && rect.isFinite && rect.width > 0 && rect.height > 0;

/// 构建 FlClash 原生风格的连续圆角透镜轮廓路径（[RSuperellipse]）：
/// 保留上下平直中段，并与两端圆弧保持连续曲率顺滑衔接。
Path _buildLensPath(Rect rect) {
  if (!_isValidLensRect(rect)) {
    return Path();
  }
  final double radius = math.min(rect.width, rect.height) / 2;
  return Path()..addRSuperellipse(
    RSuperellipse.fromRectAndRadius(rect, Radius.circular(radius)),
  );
}

/// 反向裁剪底层普通图标/文字：透镜区域内部完全掏空，避免与透镜层主色放大内容重影。
class _OutsideLensClipper extends CustomClipper<Path> {
  _OutsideLensClipper({required this.rect, required this.path});

  final Rect rect;
  final Path path;

  @override
  Path getClip(Size size) {
    final bounds = Offset.zero & size;
    if (!_isValidLensRect(rect)) {
      return Path()..addRect(bounds.inflate(40));
    }
    // 必须先包住 rect 再外扩，防止高速水平拉伸超出 size 左右 40dp 时 evenOdd 奇偶反转。
    final outer = bounds.expandToInclude(rect).inflate(40);
    return Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(outer)
      ..addPath(path, Offset.zero);
  }

  @override
  bool shouldReclip(covariant _OutsideLensClipper oldClipper) =>
      oldClipper.rect != rect;
}

/// 液态透镜底色层：负责渲染静止淡主色胶囊向半透明白色透镜的平滑过渡。
class _LensBackdropPainter extends CustomPainter {
  _LensBackdropPainter({
    required this.rect,
    required this.path,
    required this.lift,
    required this.restColor,
    required this.lensColor,
  });

  final Rect rect;
  final Path path;
  final double lift;
  final Color restColor;
  final Color lensColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!_isValidLensRect(rect)) {
      return;
    }
    final double elev = Curves.easeOut.transform(lift.clamp(0.0, 1.0));
    canvas.drawPath(
      path,
      Paint()..color = Color.lerp(restColor, lensColor, elev) ?? restColor,
    );
  }

  @override
  bool shouldRepaint(covariant _LensBackdropPainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.lift != lift ||
      oldDelegate.restColor != restColor ||
      oldDelegate.lensColor != lensColor;
}

/// 预排版缓存的透镜单项字形与标签绘制数据，避免每次动画帧重复创建与排版 [TextPainter]。
class _LensGlyphEntry {
  _LensGlyphEntry._({
    required this.itemRect,
    required this.iconPainter,
    required this.labelPainter,
    required this.iconOffset,
    required this.labelOffset,
  });

  factory _LensGlyphEntry.layout({
    required FloatingDockItem item,
    required Rect itemRect,
    required Color primaryColor,
  }) {
    final iconPainter = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(item.activeIcon.codePoint),
        style: TextStyle(
          fontFamily: item.activeIcon.fontFamily,
          package: item.activeIcon.fontPackage,
          fontSize: 20,
          height: 1.0,
          color: primaryColor,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final labelPainter = TextPainter(
      text: TextSpan(
        text: item.label,
        style: TextStyle(
          fontSize: 11,
          height: 1.15,
          color: primaryColor,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();

    final double contentHeight = 20.0 + 2.0 + labelPainter.height;
    final double topY = itemRect.center.dy - contentHeight / 2;
    return _LensGlyphEntry._(
      itemRect: itemRect,
      iconPainter: iconPainter,
      labelPainter: labelPainter,
      iconOffset: Offset(
        itemRect.center.dx - iconPainter.width / 2,
        topY + (20.0 - iconPainter.height) / 2,
      ),
      labelOffset: Offset(
        itemRect.center.dx - labelPainter.width / 2,
        topY + 20.0 + 2.0,
      ),
    );
  }

  final Rect itemRect;
  final TextPainter iconPainter;
  final TextPainter labelPainter;
  final Offset iconOffset;
  final Offset labelOffset;
  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    iconPainter.dispose();
    labelPainter.dispose();
  }
}

/// 液态透镜前景层：在连续圆角胶囊边界内裁剪绘制主色图标与文字（以各自中心原地放大，不随透镜横向漂移），
/// 并在外缘叠加干净的细描边（无模糊高光带）。
class _LensForegroundPainter extends CustomPainter {
  _LensForegroundPainter({
    required this.rect,
    required this.path,
    required this.lift,
    required this.glyphs,
    required this.rimColor,
  });

  final Rect rect;
  final Path path;
  final double lift;
  final List<_LensGlyphEntry> glyphs;
  final Color rimColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (!_isValidLensRect(rect)) {
      return;
    }
    final double elev = Curves.easeOut.transform(lift.clamp(0.0, 1.0));
    final double zoom = 1.0 + 0.28 * elev;

    // 1. 透镜裁剪区内：每项以自身 itemRect.center 为原点原地放大，绝不跟随透镜中心横向移动。
    canvas.save();
    canvas.clipPath(path);

    for (final entry in glyphs) {
      final itemRect = entry.itemRect;
      if (!_isValidLensRect(itemRect) ||
          !itemRect.inflate(8.0).overlaps(rect)) {
        continue;
      }

      canvas.save();
      final Offset pivot = itemRect.center;
      canvas.translate(pivot.dx, pivot.dy);
      canvas.scale(zoom, zoom);
      canvas.translate(-pivot.dx, -pivot.dy);
      entry.iconPainter.paint(canvas, entry.iconOffset);
      entry.labelPainter.paint(canvas, entry.labelOffset);
      canvas.restore();
    }
    canvas.restore();

    // 2. 干净的边缘细描边：无顶部模糊高光，保持通透。
    final double rimAlpha = 0.14 + 0.45 * elev;
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.9 + 0.2 * elev
        ..color = rimColor.withValues(
          alpha: (rimColor.a * rimAlpha).clamp(0.0, 1.0),
        ),
    );
  }

  @override
  bool shouldRepaint(covariant _LensForegroundPainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.lift != lift ||
      oldDelegate.rimColor != rimColor ||
      !identical(oldDelegate.glyphs, glyphs);
}

/// 单个按钮（图标在上、文字在下），底层始终保持 1.0× 中性色，
/// 不再根据距离提前变色或放大，由上层光学透镜按实际边界裁剪放大与着色。
///
/// **刻意不带自己的 `onTap`**：内层识别器会赢下手势仲裁，外层 `onTapUp` 就不再
/// 触发 —— "点哪"和"指示块归位"会变成两条路径，落点不一致。
class _DockButton extends StatelessWidget {
  const _DockButton({super.key, required this.item, required this.minWidth});

  final FloatingDockItem item;
  final double minWidth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = scheme.onSurfaceVariant;
    return ConstrainedBox(
      constraints: BoxConstraints(minWidth: minWidth, minHeight: 46),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(item.icon, size: 20, color: color),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              softWrap: false,
              style: TextStyle(
                fontSize: 11,
                height: 1.15,
                color: color,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
