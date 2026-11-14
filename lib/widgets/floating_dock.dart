/// 底部悬浮 dock：在各主标签页（课表 / 学业 / 设置）之间切换。
///
/// 外观：纯色胶囊 + 细描边 + 阴影，**不用毛玻璃**：`BackdropFilter` 在 Windows
/// 桌面上每帧都要重绘下层，滚动课表时明显掉帧。
///
/// 动效（"液态透镜"，参考 FlClash / iOS 26 标签栏）：
///  - **按下**：指示块从 dock 里"鼓"出来，变成比 dock 还高的半透明透镜
///    （白色高光描边 + 投影），透镜下的图标同步放大；松手缩回 dock 并回弹；
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
    show TargetPlatform, defaultTargetPlatform;
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

  /// 外壳用它加底部留白：让页面最后一行不被悬浮条压住。
  static const double height = 54;
  static const double bottomMargin = 16;

  static double contentInset(BuildContext context) =>
      height + bottomMargin * 2 + MediaQuery.of(context).padding.bottom;

  @override
  State<FloatingDock> createState() => FloatingDockState();
}

class FloatingDockState extends State<FloatingDock>
    with TickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _itemKeys = <GlobalKey>[];
  List<Rect> _rects = const <Rect>[];

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

  /// 透镜鼓起：欠阻尼，鼓出来时带一下过冲；缩回时也有一点回弹。
  static const SpringDescription _liftUpSpring = SpringDescription(
    mass: 1.0,
    stiffness: 520.0,
    damping: 22.0,
  );
  static const SpringDescription _liftDownSpring = SpringDescription(
    mass: 1.0,
    stiffness: 420.0,
    damping: 20.0,
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
    _slide.removeListener(_reportPillProgress);
    _physics.dispose();
    _physicsFrame.dispose();
    _slide.dispose();
    _lift.dispose();
    _edge.dispose();
    super.dispose();
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
    widget.onPressStart?.call();
    final double x = _clampX(_rawLocalX(details.globalPosition));
    final int target = _indexAt(x);
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
    if (nextPreview != _preview) _hapticTick();
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

  /// 该高亮哪一项：手指按着 → 跟手指；松手后保持落点，直到 `widget.index` 追上来
  /// （否则高亮会先弹回旧项再弹回来，看起来"闪两下"）。
  int get _visualIndex {
    if (_dragging || _pressed) return _preview;
    return _preview == widget.index ? widget.index : _preview;
  }

  /// 透镜中心对应的连续下标（0..n-1），驱动各按钮连续高亮与放大。
  double get _liveItemPosition {
    if (_rects.length < 2) return _visualIndex.toDouble();
    final first = _rects.first.center.dx;
    final last = _rects.last.center.dx;
    final span = last - first;
    if (span.abs() < 0.001) return _visualIndex.toDouble();
    final ratio = ((_livePillRect.center.dx - first) / span).clamp(0.0, 1.0);
    return ratio * (_rects.length - 1);
  }

  /// 透镜的最终绘制矩形：在中心位置的基础上叠加鼓起与速度形变。
  Rect _lensRect(Rect base, double lift, double stretch) {
    final double l = lift.clamp(-0.2, 1.3);
    final double s = stretch.clamp(-1.2, 1.2);
    final double mag = s.abs();
    // 鼓起：宽 +16%、高 +42%（44 → ~62，比 60 高的 dock 还高一点，"鼓"出来）。
    double w = base.width * (1 + 0.16 * l);
    double h = base.height * (1 + 0.42 * l);
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

    final int visualIndex = _visualIndex;

    return Padding(
      padding: EdgeInsets.only(
        bottom:
            FloatingDock.bottomMargin + MediaQuery.of(context).padding.bottom,
      ),
      child: Center(
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
                      padding: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(
                          FloatingDock.height / 2,
                        ),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: 0.08 + 0.03 * t.clamp(0.0, 1.0),
                            ),
                            blurRadius: 22 + 8 * t,
                            offset: const Offset(0, 6),
                          ),
                        ],
                        border: Border.all(
                          color: scheme.outlineVariant.withValues(alpha: 0.34),
                        ),
                      ),
                      child: child,
                    ),
                  ),
                );
              },
              child: Stack(
                key: _stackKey,
                // 透镜鼓起时比 dock 还高，不能被裁掉。
                clipBehavior: Clip.none,
                // 必须显式居中：Stack 默认 topStart，按钮会被顶到胶囊上沿。
                alignment: Alignment.center,
                children: <Widget>[
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: Listenable.merge(<Listenable>[
                          _slide,
                          _lift,
                          _physicsFrame,
                        ]),
                        builder: (context, _) {
                          final base = _livePillRect;
                          if (base.isEmpty || base.width <= 0) {
                            return const SizedBox.shrink();
                          }
                          return CustomPaint(
                            painter: _LensPainter(
                              rect: _lensRect(base, _lift.value, _stretch),
                              lift: _lift.value.clamp(0.0, 1.0),
                              restColor: scheme.primary.withValues(alpha: 0.11),
                              lensColor: Color.alphaBlend(
                                scheme.primary.withValues(alpha: 0.07),
                                scheme.surfaceContainerLowest.withValues(
                                  alpha: 0.82,
                                ),
                              ),
                              rimColor: scheme.primary.withValues(alpha: 0.22),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  AnimatedBuilder(
                    animation: Listenable.merge(<Listenable>[
                      _slide,
                      _lift,
                      _physicsFrame,
                    ]),
                    builder: (context, _) {
                      final double livePos = _liveItemPosition;
                      final double lift = _lift.value.clamp(0.0, 1.2);
                      return Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          for (
                            var position = 0;
                            position < widget.items.length;
                            position++
                          )
                            _DockButton(
                              key: _itemKeys[position],
                              item: widget.items[position],
                              selected: position == visualIndex,
                              focus: (1.0 - (livePos - position).abs()).clamp(
                                0.0,
                                1.0,
                              ),
                              lift: lift,
                            ),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 液态透镜：静止时是 dock 里一块淡主色胶囊；鼓起时过渡成半透明白色透镜
/// （白色高光描边 + 主色细边 + 投影），并超出 dock 的上下沿。
class _LensPainter extends CustomPainter {
  _LensPainter({
    required this.rect,
    required this.lift,
    required this.restColor,
    required this.lensColor,
    required this.rimColor,
  });

  final Rect rect;
  final double lift;
  final Color restColor;
  final Color lensColor;
  final Color rimColor;

  @override
  void paint(Canvas canvas, Size size) {
    final double radius = rect.shortestSide / 2;
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    // 1. 鼓起时的投影：让透镜看起来悬浮在 dock 之上。
    if (lift > 0.01) {
      canvas.drawRRect(
        rrect.shift(Offset(0, 3 * lift)),
        Paint()
          ..color = Colors.black.withValues(alpha: 0.14 * lift)
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 4 + 6 * lift),
      );
    }

    // 2. 填充：淡主色 → 半透明白色透镜。
    canvas.drawRRect(
      rrect,
      Paint()..color = Color.lerp(restColor, lensColor, lift) ?? restColor,
    );

    // 静止时保留一道极轻的细边与柔和高光，避免平板贴纸感；鼓起时过渡成强折射透镜边。
    if (lift <= 0.01) {
      canvas.drawRRect(
        rrect.deflate(0.6),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.white.withValues(alpha: 0.45),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.8
          ..color = rimColor.withValues(alpha: 0.14),
      );
    }

    if (lift > 0.01) {
      // 3. 顶部镜面高光（只在上半部分），模拟玻璃的反光。
      final Rect upper = Rect.fromLTRB(
        rect.left + radius * 0.35,
        rect.top + 1.5,
        rect.right - radius * 0.35,
        rect.center.dy,
      );
      canvas.drawRRect(
        RRect.fromRectAndRadius(upper, Radius.circular(upper.height / 2)),
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.white.withValues(alpha: 0.55 * lift),
              Colors.white.withValues(alpha: 0.0),
            ],
          ).createShader(upper),
      );

      // 4. 白色内描边 + 主色外描边：透镜的"边缘折射"。
      canvas.drawRRect(
        rrect.deflate(1.0),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.2
          ..color = Colors.white.withValues(alpha: 0.85 * lift),
      );
      canvas.drawRRect(
        rrect,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = rimColor.withValues(alpha: rimColor.a * lift),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _LensPainter oldDelegate) =>
      oldDelegate.rect != rect ||
      oldDelegate.lift != lift ||
      oldDelegate.restColor != restColor ||
      oldDelegate.lensColor != lensColor ||
      oldDelegate.rimColor != rimColor;
}

/// 单个按钮。
///
/// **刻意不带自己的 `onTap`**：内层识别器会赢下手势仲裁，外层 `onTapUp` 就不再
/// 触发 —— "点哪"和"指示块归位"会变成两条路径，落点不一致。
class _DockButton extends StatelessWidget {
  const _DockButton({
    super.key,
    required this.item,
    required this.selected,
    required this.focus,
    required this.lift,
  });

  final FloatingDockItem item;
  final bool selected;

  /// 透镜离这一项有多近（1 = 正下方，0 = 远离）。
  final double focus;

  /// 透镜鼓起程度：鼓起时透镜下的图标与文字一起"被放大"。
  final double lift;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color =
        Color.lerp(scheme.onSurfaceVariant, scheme.primary, focus) ??
        (selected ? scheme.primary : scheme.onSurfaceVariant);
    // 静止时选中项轻微放大；透镜鼓起时透镜下的内容再放大一截（放大镜效果）。
    final double magnify = 1.0 + 0.08 * focus + 0.16 * lift * focus;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      // 固定 40 高：指示块的高度就取这个矩形，滑动时才不会"胖瘦不匀"。
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          child: Transform.scale(
            scale: magnify,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  focus >= 0.5 ? item.activeIcon : item.icon,
                  size: 19,
                  color: color,
                ),
                const SizedBox(width: 5),
                Text(
                  item.label,
                  style: TextStyle(
                    fontSize: 13,
                    color: color,
                    fontWeight: focus >= 0.5
                        ? FontWeight.w600
                        : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
