/// 底部悬浮 dock：两页（课表 / 设置）之间切换。
///
/// 纯色胶囊 + 阴影，**不用毛玻璃**：`BackdropFilter` 在 Windows 桌面上
/// 每帧都要重绘下层，滚动课表时明显掉帧。
///
/// 交互是"整条可按住滑动"：在胶囊任意位置按下并左右拖，选中块会跟着手指走，
/// 松手才真正切页。没有液态玻璃那种折射/形变，只有一块纯色胶囊在两项之间滑。
///
/// 为什么不用两个独立的 `InkWell` 各管一段：
///  - 那样只有按钮本身能点，**按钮之间与两侧的留白点不动**；
///  - 也没有"按住拖动"这个手感——手机上（dock 在拇指区）拖着换页比点点点自然。
///
/// 指示块的**落点**来自实测的按钮矩形（GlobalKey + `localToGlobal`），
/// 不靠"均分宽度"估算：两项的文字长度不一样时，均分会让块对不齐。
///
/// 但"松手切到哪一页"的**判定**是均分的：胶囊宽度切成 n 等份，手指落在哪段就切哪页，
/// 阈值在等分点上，而不是某个按钮的中心——这样轻微滑动不会误切。
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

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
    required this.index,
    required this.items,
    this.onPillProgress,
    this.onPressStart,
  });

  final int index;
  final List<FloatingDockItem> items;

  /// 指示块**每一帧**的位置（0 = 第一项正中，1 = 最后一项正中）。
  ///
  /// 外壳拿它直接写页面位置 —— 页面不是"自己再跑一套动画"，而是**跟着指示块走**：
  /// 指示块在哪，两页之间的分界就在哪。
  ///
  /// 三种时机都会报：
  ///  - 按下时指示块滑向手指；
  ///  - 拖动时跟手指；
  ///  - 松手后落向目标按钮。
  ///
  /// 之所以不给"拖动进度"和"落点"两套回调：两套就意味着两个动画、两条时序，
  /// 阴影到位了页面还在路上（或者反过来）。只有一处动，才不会错位。
  final ValueChanged<double>? onPillProgress;

  /// 指针按下 dock（还没开始拖动）。
  ///
  /// 外壳用它提前把另一页建好：滑到一半才建，那一帧会卡住。
  final VoidCallback? onPressStart;

  static const double height = 60;

  /// 页面内容底部要给 dock 留出的空间（含阴影与安全区）。
  static double contentInset(BuildContext context) =>
      height + 16 + MediaQuery.of(context).padding.bottom + 12;

  @override
  State<FloatingDock> createState() => _FloatingDockState();
}

class _FloatingDockState extends State<FloatingDock>
    with TickerProviderStateMixin {
  final GlobalKey _stackKey = GlobalKey();
  final List<GlobalKey> _itemKeys = <GlobalKey>[];

  /// 每个按钮在胶囊坐标系里的矩形（按实测，不是算的）。
  List<Rect> _rects = const <Rect>[];

  bool _dragging = false;

  /// 指针按着（还没松手）。按下时指示块就滑到指针位置，不等拖动。
  bool _pressed = false;

  /// 鼠标悬停在 dock 上（桌面端给轻微放大反馈）。
  bool _hovering = false;

  /// 拖动中手指所在的项（松手就切到这一项）。
  int _preview = 0;

  /// 拖动中手指的 x（相对胶囊）。只在这一层用，不参与持久化。
  double _dragX = 0;

  /// 胶囊（Stack）的实测宽度。均分判定要用它算每一段占多宽。
  double _dockWidth = 0;

  /// 指示块的回弹动画：0 → 1 表示从 [_from] 滑到 [_to]。
  late final AnimationController _slide = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 240),
    value: 1,
  );

  /// "强调"动画：0 = 静止；悬停约 0.45（轻微放大）；按下/拖动 = 1（放大 + 阴影外扩）。
  late final AnimationController _lift = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 0,
  );

  Rect _from = Rect.zero;
  Rect _to = Rect.zero;

  /// 按当前交互状态把 [_lift] 推到该有的程度。
  void _syncLift() {
    final target = (_dragging || _pressed) ? 1.0 : (_hovering ? 0.45 : 0.0);
    _lift.animateTo(
      target,
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
    );
  }

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
    // `_pressed` 也要排除：手指还按着时页面先到位了（按下就报目标），
    // 这时把指示块拽到按钮中心，会从手指底下滑走。
    if (!_dragging && !_pressed && oldWidget.index != widget.index) {
      _preview = widget.index;
      if (_rects.length == widget.items.length) _snapTo(_rects[widget.index]);
    }
  }

  @override
  void dispose() {
    _slide.removeListener(_reportPillProgress);
    _slide.dispose();
    _lift.dispose();
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

  /// 指示块当前应该在哪。
  Rect get _pillRect {
    // 按**进度值**判断，而不是 `_slide.isAnimating`：
    // `forward(from: 0)` 内部会先 stop() 再通知监听者，那一瞬间 isAnimating
    // 是 false，会把 `_to`（终点）当成当前位置报出去 —— 页面就会先跳到底、
    // 再退回起点重滑一遍。
    final double t = _slide.value.clamp(0.0, 1.0);
    if (t >= 1.0) return _to;
    return Rect.lerp(_from, _to, Curves.easeOutCubic.transform(t)) ?? _to;
  }

  /// 直接到位（首次布局、手指拖动时用）。
  void _placePill(Rect rect) {
    _slide.stop();
    _from = rect;
    _to = rect;
  }

  /// 滑过去（点按钮、翻页时用）。
  /// 滑到 [rect]。
  ///
  /// [from] 用于"调用者即将改掉 `_dragging`"的场合：那时 [_pillRect] 已经
  /// 不再指向手指位置了，必须在改状态**之前**把起点取出来传进来，
  /// 否则松手瞬间指示块会先跳回按下时的旧位置、再滑过去。
  void _snapTo(Rect rect, {Rect? from}) {
    if (_to == rect && from == null) return;
    _from = from ?? _pillRect;
    _to = rect;
    _slide.forward(from: 0);
  }

  /// 量出每个按钮的矩形。布局变化（窗口缩放、字体变化）后会自动重来一次。
  ///
  /// 只在结果**真的变了**才 setState：否则每帧测量 → setState → 重建 → 再测量，
  /// 会自己把自己转成死循环。
  void _measure() {
    if (!mounted) return;
    final box = _stackKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    _dockWidth = box.size.width;
    final measured = <Rect>[];
    for (final key in _itemKeys) {
      final render = key.currentContext?.findRenderObject();
      if (render is! RenderBox || !render.hasSize) return;
      measured.add(
        render.localToGlobal(Offset.zero, ancestor: box) & render.size,
      );
    }
    if (measured.isEmpty) return;
    if (_sameRects(measured, _rects)) return;
    setState(() {
      _rects = measured;
      _placePill(measured[_preview.clamp(0, measured.length - 1)]);
    });
    // 布局变了（窗口缩放 / 字体变化）：指示块的绝对位置变了，页面得跟上。
    _reportPillProgress();
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

  double _localX(Offset global) {
    final box = _stackKey.currentContext?.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return 0;
    return box.globalToLocal(global).dx;
  }

  /// 手指 x → 连续的项位置（0..n-1，带小数）。
  ///
  /// **均分**：把胶囊宽度切成 n 等份，手指在哪一段就落在哪一项附近。
  /// 不再用"按钮中心"当锚点——那是"稍微往右一滑就切到下一页"的元凶：
  /// 左按钮的中心远在胶囊中线左边，手指刚滑过它就被判成下一页。
  double _positionAt(double x) {
    final n = _rects.length;
    if (n <= 1) return 0;
    if (_dockWidth <= 0) return 0;
    return (x / (_dockWidth / n)).clamp(0.0, (n - 1).toDouble());
  }

  /// 连续位置 → 指示块矩形（相邻两项之间线性插值）。
  Rect _rectAt(double position) {
    if (_rects.isEmpty) return Rect.zero;
    final max = _rects.length - 1;
    final clamped = position.clamp(0.0, max.toDouble());
    final index = clamped.floor().clamp(0, max);
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

  /// 指示块矩形：**中心对准指针 x**（不是左缘贴着指针），尺寸取所在项的原始大小。
  /// 放大/回弹由外面的等比例缩放负责，这里只负责"位置跟手"。
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

  void _onDragStart(DragStartDetails details) {
    if (_rects.length != widget.items.length) return;
    final x = _localX(details.globalPosition);
    setState(() {
      _dragging = true;
      _dragX = x;
      _preview = _indexAt(x);
    });
    _syncLift();
    _reportPillProgress();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    if (!_dragging) return;
    setState(() {
      _dragX = _localX(details.globalPosition);
      _preview = _indexAt(_dragX);
    });
    _reportPillProgress();
  }

  /// 指示块此刻**真的**画在哪。
  ///
  /// 拖动时中心跟指针，其余时候由 [_pillRect]（带着滑动中的插值）决定。
  /// 画和"上报给页面的位置"必须用同一个值，否则页面会比阴影快/慢半拍。
  Rect get _livePillRect => _dragging ? _centeredAt(_dragX) : _pillRect;

  /// 把指示块中心换算成 0..1，报给外壳（页面跟着这个值平移）。
  ///
  /// 用的是**指示块中心**在首末两项中心之间的比例，而不是手指落在哪一段：
  /// 页面跟着指示块走，才叫"同步位移"。
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

  void _onDragEnd(DragEndDetails details) {
    if (!_dragging) return;
    final target = _preview.clamp(0, widget.items.length - 1);
    // 必须在清 `_dragging` **之前**取起点：那之后 `_livePillRect` 就不再
    // 指向手指了。
    final Rect from = _livePillRect;
    setState(() {
      _dragging = false;
      _pressed = false;
      _preview = target;
      _snapTo(_rects.isEmpty ? Rect.zero : _rects[target], from: from);
    });
    _syncLift();
    // 落点由指示块自己滑过去，页面跟着它走 —— 不再单独报"目标页"。
    // 这里补报一次，覆盖"指示块本来就在目标上、动画不启动"的情况
    // （否则页面会停在拖动到一半的位置）。
    _reportPillProgress();
  }

  void _onDragCancel() {
    // 没真的拖起来过 → 这是"点击赢了手势仲裁"：拖动识别器被拒也会走到这里。
    // 那时松手该由 `_onTapUp` 决定落点，这里一旦回弹 + 上报旧页，就会和它打架：
    // 指示块先弹回旧位置、再弹到新位置，看起来像闪了一下。
    if (!_dragging) return;
    final Rect from = _livePillRect;
    setState(() {
      _dragging = false;
      _pressed = false;
      if (_rects.isNotEmpty) _snapTo(_rects[_preview], from: from);
    });
    _syncLift();
    _reportPillProgress();
  }

  /// 指针按下（还没拖）：指示块立刻滑到指针所在的位置——
  /// 不用等到拖动才开始跟手，点哪就滑到哪。预选状态**不改尺寸**。
  ///
  /// 同时把目标页报给外壳：指示块都挪过去了，页面留在原地会显得"没反应"
  /// （用户会以为没点上，于是补一次滑动）。按下就报，页面从这一刻开始滑。
  void _onPressDown(DragDownDetails details) {
    if (_rects.length != widget.items.length) return;
    // 按下的瞬间就告诉外壳：另一页该提前建好了。
    widget.onPressStart?.call();
    final x = _localX(details.globalPosition);
    final int target = _indexAt(x);
    setState(() {
      _pressed = true;
      _preview = target;
      _snapTo(_centeredAt(x));
    });
    _syncLift();
    // 指示块从这一刻开始滑向手指，页面跟着它走；
    // 不用再单独报一个"目标页"让页面自己跑另一套动画。
    _reportPillProgress();
  }

  void _onTapUp(TapUpDetails details) {
    if (_rects.length != widget.items.length) {
      setState(() => _pressed = false);
      _syncLift();
      return;
    }
    final int target = _indexAt(_localX(details.globalPosition));
    setState(() {
      _pressed = false;
      _preview = target;
      // 手指可能落在按钮边缘：松手后指示块归位到按钮本身，
      // 否则会停在指针那一点、等页面停稳时再补一段小滑动。
      _snapTo(_rects[target]);
    });
    _syncLift();
    _reportPillProgress();
  }

  void _onTapCancel() {
    // 点击没成立：可能是被横向拖动接管（拖动会自己管位置），也可能是系统
    // 把手势取消了。按下时已经报过目标（页面可能正在过去），所以这里**不**
    // 往回撤 —— 撤了就会出现"指示块回到旧项、页面却停在新页"的错位。
    // 只清按下态，把指示块收到它当前该在的那一项上。
    setState(() {
      _pressed = false;
      if (!_dragging && _rects.length == widget.items.length) {
        _snapTo(_rects[_preview]);
      }
    });
    _syncLift();
    _reportPillProgress();
  }

  /// 该高亮（并放大）哪一项。
  ///
  /// 不能简单用 `widget.index`：它要等页面真的落定才更新，而指示块在松手瞬间
  /// 就已经在目标上了。若此时退回 `widget.index`，高亮会先弹回旧项、等页面
  /// 到位再弹回来 —— 也就是"阴影闪两下"。
  /// 所以：手指按着 → 跟手指；松手后 → 保持落点，直到 `widget.index` 追上来。
  int get _visualIndex {
    if (_dragging || _pressed) return _preview;
    return _preview == widget.index ? widget.index : _preview;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 布局完成才知道按钮在哪：每帧补一次测量，量到就不再来。
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());

    final int visualIndex = _visualIndex;

    return Padding(
      padding: EdgeInsets.only(
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      child: Center(
        child: MouseRegion(
          // 桌面端悬停就给轻微放大反馈（_lift 推到 0.45）。
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
            // 指针一落下（还没决定是点还是拖）就触发：指示块滑到指针位置。
            onHorizontalDragDown: _onPressDown,
            onHorizontalDragStart: _onDragStart,
            onHorizontalDragUpdate: _onDragUpdate,
            onHorizontalDragEnd: _onDragEnd,
            onHorizontalDragCancel: _onDragCancel,
            child: AnimatedBuilder(
              animation: _lift,
              builder: (context, _) {
                // 拖动时：阴影往外扩一圈（液态玻璃那种"范围变大"的光晕），
                // 整条 dock 也略微放大，松手回弹到静止值。
                final t = _lift.value.clamp(0.0, 1.0);
                return Transform.scale(
                  scale: 1 + 0.04 * t,
                  child: Container(
                    height: FloatingDock.height,
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(
                        FloatingDock.height / 2,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: 0.10 + 0.04 * t,
                          ),
                          blurRadius: 18 + 30 * t,
                          spreadRadius: 10 * t,
                          offset: Offset(0, 6 + 2 * t),
                        ),
                      ],
                      border: Border.all(
                        color: scheme.outlineVariant.withValues(alpha: 0.6),
                      ),
                    ),
                    child: Stack(
                      key: _stackKey,
                      // 必须显式居中：Stack 默认 `topStart`，而 Row 只有 44 高、
                      // 胶囊内高 58，不给 alignment 的话整排按钮和指示块会被顶到胶囊顶部
                      // （看起来就是"错位"——指示块上沿贴着胶囊上沿）。
                      alignment: Alignment.center,
                      children: <Widget>[
                        // 指示块画在最底下，按钮是透明的。
                        Positioned.fill(
                          child: IgnorePointer(
                            child: AnimatedBuilder(
                              animation: Listenable.merge(<Listenable>[
                                _slide,
                                _lift,
                              ]),
                              builder: (context, _) {
                                // 与上报给页面的位置共用同一个矩形：
                                // 拖动中中心跟指针，其余（预选 / 滑动 / 静止）用 _pillRect。
                                final base = _livePillRect;
                                if (base.isEmpty || base.width <= 0) {
                                  return const SizedBox.shrink();
                                }
                                // 从按下就开始放大（等比例），松手回弹——
                                // 不做"加宽 + 拉高"那种会变成圆角方框的形变。
                                final k =
                                    1 + 0.15 * _lift.value.clamp(0.0, 1.0);
                                final rect = Rect.fromCenter(
                                  center: base.center,
                                  width: base.width * k,
                                  height: base.height * k,
                                );
                                return CustomPaint(
                                  painter: _PillPainter(
                                    rect: rect,
                                    color: scheme.primary.withValues(
                                      alpha: 0.10,
                                    ),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                        Row(
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
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// 指示块：一个圆角胶囊。
///
/// 用 `CustomPaint` 而不是 `AnimatedPositioned`：它可以直接作为 Stack 的子节点
/// （`Positioned` 不能藏在 builder 里），而且重绘只动一层，按钮不用跟着重建。
class _PillPainter extends CustomPainter {
  _PillPainter({required this.rect, required this.color});

  final Rect rect;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(24)),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _PillPainter oldDelegate) =>
      oldDelegate.rect != rect || oldDelegate.color != color;
}

/// 单个按钮。
///
/// **刻意不带自己的 `onTap`**：如果这里放一个 `InkWell(onTap:)`，点击时内层
/// 识别器会赢下手势仲裁，外层的 `onTapUp` 就不再触发 —— 于是"点哪"和"指示块
/// 归位"变成两条不同的路径，落点会不一致。
/// 点击统一由外层 [GestureDetector] 处理（它本来就要覆盖整条胶囊）。
class _DockButton extends StatelessWidget {
  const _DockButton({super.key, required this.item, required this.selected});

  final FloatingDockItem item;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      // 固定 44 高（不是靠 padding 撑）：指示块的高度就取这个矩形，
      // 高度不随字体度量忽大忽小，滑动时才不会"胖瘦不匀"。
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(
                selected ? item.activeIcon : item.icon,
                size: 20,
                color: color,
              ),
              const SizedBox(width: 7),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w500 : FontWeight.w400,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
