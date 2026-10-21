/// 课表翻页的滚动行为：**一次滑动只翻一页**，只认拖拽，落页更快。
///
/// 替换默认 [PageController] 后，框架的拖拽物理与页码吸附仍然照用，改四件事：
///  1. 松手后的落点以"起手那一页"为锚（[_WeekPagerPosition.goBallistic]），
///     而不是按当前位置的小数位推算 —— 这是"滑一下翻一页"的关键；
///  2. 指针按下不再冻结正在跑的翻页（[_WeekPagerPosition.hold]）；
///  3. 拖拽等到真的移动了才接管（[_DeferredDrag]），静止时零死区；
///  4. 落页弹簧调快（[_kSnapSpring]），停稳时间大约从 640ms 缩到 250ms。
library;

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show precisionErrorTolerance;
import 'package:flutter/gestures.dart' show Drag, kTouchSlop;
import 'package:flutter/material.dart';

/// 落页弹簧：按"感知时长"定义（≈ 收敛所需时间），比框架默认（约 260ms）利落
/// 一档；`bounce: 0` 表示无过冲 —— 不会冲过头再弹回来才对正。
/// 翻页节奏的另一半是页面里的 `_flipDuration`（点箭头 / 回到本周的动画）。
final SpringDescription _kSnapSpring = SpringDescription.withDurationAndBounce(
  duration: const Duration(milliseconds: 170),
  bounce: 0,
);

/// 课表页的翻页控制器。
///
/// ## 为什么不能直接用 [PageController] 的落点
/// `PageView` 的吸附目标算的是"**当前**位置 + 半页再取整"：
///
/// ```dart
/// double page = position.pixels / viewport;
/// if (velocity > tolerance.velocity) page += 0.5;
/// return page.roundToDouble() * viewport;
/// ```
///
/// 它默认"手势本身几乎没把页面拖动"，只靠 +0.5 决定翻不翻。可实际滑动时手指
/// 已经把页面拖走了：手机上横扫半个屏幕就有 0.4~0.6 页，宽窗口下更夸张。
/// 于是 `0.6 + 0.5 = 1.1 → 1`（正常）但只要拖过 1.0 页就变成 `1.0 + 0.5 = 1.5 → 2`，
/// 一次滑动直接跳过一页 —— 这就是"滑一下翻两页 / 跳页"的来源。
///
/// 这里改成以**起手页**为锚：快速滑动固定走相邻一页，方向跟手；
/// 只有慢慢松开（速度被识别为 0）时才就近吸附，和框架一致。
///
/// ## 为什么要换掉 `hold()`
/// [Scrollable] 在指针**按下**的瞬间就调用 `position.hold()`，把当前活动
/// （翻页动画或甩动惯性）停掉、位置冻在半页上；如果这一下没形成拖拽，抬手时
/// `hold.cancel()` 又按 0 速度重新落点，页面从半页"退回"来。用户连续快滑时，
/// 第二下手指落下正好踩在这里 —— 上一页的翻页被打断、落点被改写，
/// 表现出来就是"滑了一下却没翻页"。
///
/// 因此位置层把这些行为按"只有拖拽能改变位置"重写：按下/抬起不碰位置，
/// 只有真的拖起来（[_DeferredDrag]）才接管。
///
/// `PageController` 内部会把位置强转成私有的 `_PagePosition`，所以
/// [attach]、[page]、[animateToPage]、[jumpToPage] 要一起接管。
class WeekPagerController extends PageController {
  WeekPagerController({super.initialPage});

  /// 只支持"一页占满视口"（[PageController.viewportFraction] 恒为 1）：
  /// 页码与像素的换算依赖这个前提。
  _WeekPagerPosition? get _pager {
    if (positions.length != 1) return null;
    final ScrollPosition position = positions.first;
    return position is _WeekPagerPosition ? position : null;
  }

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _WeekPagerPosition(
      physics: physics,
      context: context,
      initialPage: initialPage,
      oldPosition: oldPosition,
    );
  }

  @override
  void attach(ScrollPosition position) {
    try {
      super.attach(position);
    } on TypeError {
      // `PageController.attach` 先做正事（登记 position、转发通知），最后一句
      // 才把 position 强转成私有的 `_PagePosition` 去设 viewportFraction，
      // 我们的实现不是那个类型，这里注定失败。登记已完成，忽略即可；
      // 万一将来 Flutter 调整顺序导致没登记，下面的断言会立刻炸出来。
      assert(
        positions.contains(position),
        '自定义 ScrollPosition 未被登记：Flutter 内部 attach 流程可能变了',
      );
    }
  }

  /// 未挂载 / 还没布局时返回 null，而不是像父类那样断言后强转。
  @override
  double? get page => _pager?.page;

  @override
  Future<void> animateToPage(
    int page, {
    required Duration duration,
    required Curve curve,
  }) {
    final pager = _pager;
    if (pager == null) return Future<void>.value();
    if (!pager.hasViewportDimension || pager.viewportDimension <= 0) {
      pager.pendingPage = page.toDouble();
      return Future<void>.value();
    }
    // 记下"正在去哪一页"：动画途中手指接管时，这一页就是新的起手页。
    pager.headingTo = page.toDouble();
    return pager.animateTo(
      pager.pixelsForPage(page.toDouble()),
      duration: duration,
      curve: curve,
    );
  }

  @override
  void jumpToPage(int page) {
    final pager = _pager;
    if (pager == null) return;
    if (!pager.hasViewportDimension || pager.viewportDimension <= 0) {
      pager.pendingPage = page.toDouble();
      return;
    }
    // 瞬移没有"在途目标"，清掉免得下一次手势拿它当起手页。
    pager.headingTo = null;
    pager.jumpTo(pager.pixelsForPage(page.toDouble()));
  }
}

/// 一次手势 = 一页的翻页位置。
class _WeekPagerPosition extends ScrollPositionWithSingleContext
    implements PageMetrics {
  _WeekPagerPosition({
    required super.physics,
    required super.context,
    required this.initialPage,
    super.oldPosition,
  }) : _pendingPage = initialPage.toDouble(),
       super(initialPixels: null, keepScrollOffset: false);

  final int initialPage;

  /// 视口尺寸未知（或为 0）时先记住页序号，等有尺寸了再换算成像素。
  double _pendingPage;

  set pendingPage(double value) => _pendingPage = value;

  /// 这次手势从哪一页起手（松手算落点时用）。
  double? _gestureOrigin;

  /// 正在吸附 / 动画去往的页；不在途中时为 null。
  double? _headingTo;

  set headingTo(double? value) => _headingTo = value;

  @override
  double get viewportFraction => 1.0;

  @override
  double? get page {
    if (!hasPixels) return null;
    // 尺寸为 0 时返回 0 而不是 null：`PageView` 会把 onPageChanged 的 metrics
    // 强转成 PageMetrics 后直接 `page!.round()`，null 会炸。
    if (viewportDimension <= 0) return 0;
    return pageForPixels(pixels);
  }

  /// 像素 → 页码。整页附近取整，免得浮点误差让"停在第 3 周"变成 2.9999。
  double pageForPixels(double pixels) {
    final double page = pixels / viewportDimension;
    final double rounded = page.roundToDouble();
    return (page - rounded).abs() < 1e-4 ? rounded : page;
  }

  double pixelsForPage(double page) => page * viewportDimension;

  /// 最后一页的序号。
  int get _lastPage => (maxScrollExtent / viewportDimension).round();

  @override
  bool applyViewportDimension(double viewportDimension) {
    final double? previous = hasViewportDimension
        ? this.viewportDimension
        : null;
    if (viewportDimension == previous) return true;
    final bool result = super.applyViewportDimension(viewportDimension);

    // 尺寸变化（旋转 / 拖动窗口）时保持"正在看第几周"不变，而不是保持像素。
    final double page = hasPixels && previous != null && previous > 0
        ? pixels / previous
        : _pendingPage;
    _pendingPage = page;
    final double next = viewportDimension > 0 ? page * viewportDimension : 0;
    if (!hasPixels || (next - pixels).abs() > precisionErrorTolerance) {
      correctPixels(next);
      return false;
    }
    return result;
  }

  @override
  PageMetrics copyWith({
    double? minScrollExtent,
    double? maxScrollExtent,
    double? pixels,
    double? viewportDimension,
    AxisDirection? axisDirection,
    double? viewportFraction,
    double? devicePixelRatio,
  }) {
    return PageMetrics(
      minScrollExtent:
          minScrollExtent ??
          (hasContentDimensions ? this.minScrollExtent : null),
      maxScrollExtent:
          maxScrollExtent ??
          (hasContentDimensions ? this.maxScrollExtent : null),
      pixels: pixels ?? (hasPixels ? this.pixels : null),
      viewportDimension:
          viewportDimension ??
          (hasViewportDimension ? this.viewportDimension : null),
      axisDirection: axisDirection ?? this.axisDirection,
      viewportFraction: viewportFraction ?? this.viewportFraction,
      devicePixelRatio: devicePixelRatio ?? this.devicePixelRatio,
    );
  }

  /// 按下不冻结位置（原因见类注释）。
  ///
  /// 返回一个什么都不做的控制器，但 `cancel()` 必须回调 `holdCancelCallback`：
  /// `Scrollable` 靠它清空自己的 `_hold`，抬手时还有 `assert(_hold == null)`。
  @override
  ScrollHoldController hold(VoidCallback holdCancelCallback) {
    return _IgnoredHold(holdCancelCallback);
  }

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    // 起手页：如果上一次翻页还在吸附途中，就用它要落的那一页 ——
    // 连滑两下时，第二下应该从"第一下要落的页"继续，而不是从半页继续，
    // 否则第二下会被算成"原地不动"，看起来就像丢了一页。
    // 但落差超过一页半就不认它（比如点了箭头连跳好几周、途中又被手接管），
    // 那种情况下按当前页算，免得手一拨就飞出好几页。
    final double? current = page;
    final double? heading = _headingTo;
    _gestureOrigin =
        heading != null && current != null && (heading - current).abs() <= 1.5
        ? heading
        : current?.roundToDouble();
    _headingTo = null;

    // 静止时没有任何东西需要保护：手指一动就接管（零死区，最跟手）。
    // 动画 / 惯性还在跑时要先攒够 kTouchSlop，否则一次纯按住就会把活动停掉。
    final bool inFlight =
        activity is DrivenScrollActivity || activity is BallisticScrollActivity;
    return _DeferredDrag(
      () => _beginDrag(details, dragCancelCallback),
      dragCancelCallback,
      threshold: inFlight ? kTouchSlop : 0,
    );
  }

  /// 真正接管位置：走框架原本那套（`ScrollDragController` + `DragScrollActivity`）。
  /// 抽成方法是为了能在闭包里对 `super` 发调用。
  Drag _beginDrag(DragStartDetails details, VoidCallback onCanceled) =>
      super.drag(details, onCanceled);

  /// 松手后的落点：**以起手页为锚，一次手势只走一页**。
  @override
  void goBallistic(double velocity) {
    final double? target = _snapPixels(velocity);
    if (target == null) {
      super.goBallistic(velocity);
      return;
    }
    final Tolerance tolerance = physics.toleranceFor(this);
    if ((target - pixels).abs() < tolerance.distance) {
      // 已经在这一页上，不用再跑动画。
      goIdle();
      return;
    }
    _headingTo = target / viewportDimension;
    beginActivity(
      BallisticScrollActivity(
        this,
        ScrollSpringSimulation(
          _kSnapSpring,
          pixels,
          target,
          velocity,
          tolerance: tolerance,
        ),
        context.vsync,
        shouldIgnorePointer,
      ),
    );
  }

  /// 落点（像素）；返回 null 表示交给框架自己处理。
  double? _snapPixels(double velocity) {
    if (!hasPixels || !hasViewportDimension || viewportDimension <= 0) {
      return null;
    }
    final int last = _lastPage;
    final double current = pixels / viewportDimension;
    // 没有起手页记录（滚轮、尺寸变化触发的吸附）就按当前页算。
    final double origin = (_gestureOrigin ?? current.roundToDouble()).clamp(
      0,
      last.toDouble(),
    );
    _gestureOrigin = null;

    double target;
    if (velocity == 0) {
      // 慢慢松开：就近吸附。与框架一致，也让"拖一点再松手"能回到原页。
      target = current.roundToDouble();
    } else {
      // 快速滑动：只翻到相邻一页，方向跟手。
      final double oneStep = origin + (velocity > 0 ? 1 : -1);
      // 手已经把页面拖过一页以上时，不往回拽（物理上几乎做不到，但别写出
      // 一个"松手把页面拉回去"的怪行为）。
      target = velocity > 0
          ? math.max(current.roundToDouble(), oneStep)
          : math.min(current.roundToDouble(), oneStep);
    }
    return target.clamp(0, last.toDouble()) * viewportDimension;
  }
}

/// 被忽略的 hold：只在抬手 / 取消时把 `Scrollable` 的 `_hold` 置空，不碰滚动。
///
/// `ScrollHoldController` 只有 `cancel()`；`Scrollable` 在起拖时会直接把
/// `_hold` 置空（不调 dispose），抬手时调 `cancel()`，两种路径下位置都不动。
class _IgnoredHold implements ScrollHoldController {
  _IgnoredHold(this._onReleased);

  final VoidCallback _onReleased;
  bool _released = false;

  @override
  void cancel() {
    if (_released) return;
    _released = true;
    _onReleased();
  }
}

/// 只在"手指真的移动了"之后才接管位置的拖拽。
///
/// `Scrollable` 判定"这一下是拖拽"比"手真的移动了"宽松得多：手势竞技场里只剩
/// 拖拽识别器一个成员时（翻页动画期间整个内容被 `IgnorePointer`，正好是这种
/// 情况），手指落下就被判赢、随即 `onStart`。直接交给框架的话，一次纯按住就会
/// 新建 `DragScrollActivity`、把正在跑的翻页 dispose 掉，抬手再
/// `goBallistic(0)` 吸附回最近一页 —— 用户看到的就是"按一下就抽搐/回弹"。
///
/// 接管时机因此分两种（阈值见 [threshold]）：
///  - **位置静止**：手指一动就接管，零死区，正常滑动跟手到 1:1；
///  - **动画/惯性在跑**：累计位移过了 [kTouchSlop] 才接管，避免一次按住
///    就把页面钉在半页上。
/// 接管那一刻会把已走掉的位移补上，所以不会出现"页面永远落后手指一截"。
/// 全程没动时一个活动都不新建，抬手也不触发 `goBallistic`，
/// 所以既不会掐断翻页，也不会往回弹。
class _DeferredDrag implements Drag {
  _DeferredDrag(this._beginDrag, this._onCanceled, {required this.threshold});

  /// 真正接管的动作：带着最初的 start details 调一次框架的 `position.drag()`。
  final Drag Function() _beginDrag;

  /// 接管前要先走掉的位移（逻辑像素）。0 = 手指一动就接管。
  final double threshold;

  /// `Scrollable` 传进来的 `_disposeDrag`：没接管过时得由我们自己调，
  /// 否则 `Scrollable._drag` 一直非空，下一次按下会撞断言。
  final VoidCallback _onCanceled;

  Drag? _drag;

  /// 累计位移（带符号，与框架 `_globalDistanceMoved` 同口径）：
  /// 来回抖动的净位移不算数，按住时的细微抖动不会把翻页抢过去。
  double _moved = 0;

  @override
  void update(DragUpdateDetails details) {
    final drag = _drag;
    if (drag != null) {
      drag.update(details);
      return;
    }
    _moved += details.primaryDelta ?? 0;
    if (_moved == 0 || _moved.abs() < threshold) return;

    final double pending = _moved;
    _moved = 0;
    final Drag started = _drag = _beginDrag();
    // 把接管之前已经走掉的那段位移补上，补完就是 1:1，手指到哪页面到哪。
    started.update(
      DragUpdateDetails(
        globalPosition: details.globalPosition,
        localPosition: details.localPosition,
        delta: Offset(pending, 0),
        primaryDelta: pending,
        sourceTimeStamp: details.sourceTimeStamp,
        kind: details.kind,
      ),
    );
  }

  @override
  void end(DragEndDetails details) {
    final drag = _drag;
    if (drag == null) {
      _onCanceled();
      return;
    }
    drag.end(details);
  }

  @override
  void cancel() {
    final drag = _drag;
    if (drag == null) {
      _onCanceled();
      return;
    }
    drag.cancel();
  }
}
