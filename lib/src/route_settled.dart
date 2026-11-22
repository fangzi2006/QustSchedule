/// 路由落稳协调与并行后台计算辅助：
///
/// 核心原则——**入场转场动画与页面数据加载并行且互不干扰**：
/// 1. 数据读取、后台 Isolate 解析或原生后台线程查询在进入页面时**立即并行启动**，
///    不再苦等 260ms 转场结束才开始加载；
/// 2. 重子树首次挂载（如大段 `SelectionArea` 富文本、复杂预览舞台）与首屏异步结果提交
///    统一避让入场转场窗口，在路由离开 `offstage` 且动画达到 `completed` 的瞬间落稳提交，
///    杜绝首帧与滑入中途的构建/排版/光栅化抖动；
/// 3. 路由落稳后保持粘性状态，退场（pop）绝不卸载内容；入场中途触发取消返回
///    （`forward -> reverse -> forward -> completed`）也能正常落稳而不卡死。
library;

import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import 'background_isolate_stub.dart'
    if (dart.library.isolate) 'background_isolate_io.dart'
    as background_isolate;

/// 将纯 Dart 计算（如资产 UTF-8 解码与 Markdown/协议全文解析）卸载到后台 Isolate。
///
/// - 生产环境（[WidgetsFlutterBinding]）与纯 Dart 单元测试均走真实 `Isolate.run`，
///   UI 线程 0ms 解析开销；
/// - Web 平台（条件导入无 `dart:isolate` 依赖）及 `flutter_test` 的 `FakeAsync`
///   （[WidgetsBinding.instance] 非 [WidgetsFlutterBinding]）退回微任务异步执行，
///   保证组件测试确定性收口。
Future<T> runInBackground<T>(T Function() computation) {
  if (kIsWeb || _isTestWidgetsBinding()) {
    return Future<T>.microtask(computation);
  }
  return background_isolate.runIsolateComputation<T>(computation);
}

bool _isTestWidgetsBinding() {
  try {
    return WidgetsBinding.instance is! WidgetsFlutterBinding;
  } on Error {
    // 纯 Dart 单元测试尚未初始化 WidgetsBinding，允许直接走真实 Isolate。
    return false;
  }
}

/// 路由落稳一次性任务句柄：供调用方在 `dispose` 时取消尚未触发的监听与回调。
class RouteSettledHandle {
  RouteSettledHandle._(this._onCancel);

  final void Function() _onCancel;
  bool _cancelled = false;
  bool _completed = false;

  /// 任务是否已被取消。
  bool get isCancelled => _cancelled;

  /// 任务是否已触发完成或被取消。
  bool get isDone => _cancelled || _completed;

  void _markCompleted() {
    _completed = true;
  }

  /// 取消尚未触发的回调并解除路由动画监听。
  void cancel() {
    if (_cancelled || _completed) return;
    _cancelled = true;
    _onCancel();
  }
}

/// 在当前路由结束 `offstage` 且入场动画完成后触发一次 [task]。
///
/// - 若当前已处于稳定前台状态（无推入动画或转场已完成），则通过微任务直接执行；
/// - 若入场中途发生取消返回（`forward -> reverse -> forward -> completed`），
///   不会在 `reverse` 时提前作废，最终完成入场后仍会正常触发；
/// - 仅在页面彻底退场（`dismissed && !isActive`）或调用 [RouteSettledHandle.cancel]
///   时取消。
RouteSettledHandle scheduleAfterRouteSettled({
  required BuildContext context,
  required bool Function() isMounted,
  required FutureOr<void> Function() task,
}) {
  final route = ModalRoute.of(context);
  final animation = route?.animation;

  late final RouteSettledHandle handle;
  void Function(AnimationStatus)? statusListener;

  void detachListener() {
    final listener = statusListener;
    statusListener = null;
    if (listener != null && animation != null) {
      animation.removeStatusListener(listener);
    }
  }

  handle = RouteSettledHandle._(detachListener);

  void fireOnce() {
    if (handle.isDone) return;
    detachListener();
    scheduleMicrotask(() {
      if (handle.isDone || !isMounted()) {
        handle.cancel();
        return;
      }
      handle._markCompleted();
      final result = task();
      if (result is Future<void>) {
        unawaited(result.catchError((_) {}));
      }
    });
  }

  final alreadySettled =
      animation == null ||
      (!(route?.offstage ?? false) &&
          animation.status == AnimationStatus.completed);
  if (alreadySettled) {
    fireOnce();
    return handle;
  }

  if (animation.status == AnimationStatus.dismissed &&
      !(route?.isActive ?? true)) {
    handle.cancel();
    return handle;
  }

  void scheduleOffstageCheck() {
    if (route == null || handle.isDone) return;
    void checkOffstage() {
      if (handle.isDone) return;
      if (!isMounted()) {
        handle.cancel();
        return;
      }
      if (route.offstage) {
        SchedulerBinding.instance.addPostFrameCallback((_) => checkOffstage());
        return;
      }
      if (animation.status == AnimationStatus.completed) {
        fireOnce();
      } else if (animation.status == AnimationStatus.dismissed &&
          !route.isActive) {
        handle.cancel();
      }
    }

    SchedulerBinding.instance.addPostFrameCallback((_) => checkOffstage());
  }

  statusListener = (status) {
    if (handle.isDone) return;
    if (status == AnimationStatus.completed) {
      if (route?.offstage ?? false) {
        scheduleOffstageCheck();
        return;
      }
      fireOnce();
    } else if (status == AnimationStatus.dismissed &&
        !(route?.isActive ?? true)) {
      handle.cancel();
    }
  };
  animation.addStatusListener(statusListener!);

  // 仅当动画已 completed 但路由仍处于 offstage 时才需要轮询 offstage 解除；
  // 动画进行中（forward）由 statusListener 在 completed 时接管，避免无意义逐帧轮询。
  if (route != null &&
      route.offstage &&
      animation.status == AnimationStatus.completed) {
    scheduleOffstageCheck();
  }

  return handle;
}

/// 路由落稳状态混入：供重页面感知入场动画是否完成，并在落稳前保持轻量外壳与零中途 `setState`。
///
/// - 路由直接挂载在无动画或已完成状态（如根路由、测试直接挂载）时，首帧即 [isRouteSettled] 为 `true`；
/// - 路由推入动画进行期间保持 `false`，允许页面在 `initState` 中并行加载/解析数据而不打断滑入帧；
/// - 一旦落稳即粘性保持 `true`，退场滑出时绝不卸载已渲染页面内容；
/// - 当路由处于 `offstage == true`（如 Hero 预测量或外部显式离屏）时，
///   因为 `_ModalScopeStatus` 不包含 `offstage` 字段，故仅在 `offstage == true` 期间
///   按帧检测解除，解除瞬间保证触发一次 [onRouteSettled]。
mixin RouteSettledStateMixin<T extends StatefulWidget> on State<T> {
  ModalRoute<dynamic>? _settledRoute;
  Animation<double>? _settledAnimation;
  bool _hasInitializedRoute = false;
  bool _routeSettled = false;
  bool _offstagePollScheduled = false;

  /// 当前路由是否已完成入场转场且离开 `offstage`。
  bool get isRouteSettled => _routeSettled;

  /// 当路由从未落稳转为落稳时调用一次；子类可覆写以一并提交并行预加载结果。
  @protected
  void onRouteSettled() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_routeSettled) return;

    final wasInitialized = _hasInitializedRoute;
    _hasInitializedRoute = true;

    final route = ModalRoute.of(context);
    final animation = route?.animation;
    if (!identical(_settledRoute, route) ||
        !identical(_settledAnimation, animation)) {
      _detachRouteSettledListeners();
      _settledRoute = route;
      _settledAnimation = animation;
      _settledAnimation?.addStatusListener(_onRouteSettledAnimationStatus);
    }

    if (_isRouteCurrentlySettled(route, animation)) {
      if (!wasInitialized) {
        _completeRouteSettlement(notify: false);
      } else {
        // 先前处于未落稳，依赖变更后已满足落稳条件：
        // 同步置位让本帧 build 直出落稳内容，并在帧尾安全触发一次 onRouteSettled()。
        _routeSettled = true;
        _detachRouteSettledListeners();
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            onRouteSettled();
          }
        });
      }
      return;
    }

    if (route != null && route.offstage) {
      _scheduleOffstagePoll();
    }
  }

  @override
  void dispose() {
    _detachRouteSettledListeners();
    super.dispose();
  }

  static bool _isRouteCurrentlySettled(
    ModalRoute<dynamic>? route,
    Animation<double>? animation,
  ) {
    if (route != null && route.offstage) return false;
    return animation == null || animation.status == AnimationStatus.completed;
  }

  void _detachRouteSettledListeners() {
    _settledAnimation?.removeStatusListener(_onRouteSettledAnimationStatus);
    _settledAnimation = null;
    _settledRoute = null;
  }

  void _onRouteSettledAnimationStatus(AnimationStatus status) {
    if (_routeSettled || !mounted) return;
    if (status == AnimationStatus.completed) {
      final route = _settledRoute;
      if (route != null && route.offstage) {
        _scheduleOffstagePoll();
        return;
      }
      _triggerSettlementNotify();
    }
  }

  void _scheduleOffstagePoll() {
    if (_offstagePollScheduled || _routeSettled) return;
    _offstagePollScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _offstagePollScheduled = false;
      if (!mounted || _routeSettled) return;
      final route = _settledRoute;
      final animation = _settledAnimation;
      if (route != null && route.offstage) {
        _scheduleOffstagePoll();
        return;
      }
      if (_isRouteCurrentlySettled(route, animation)) {
        _triggerSettlementNotify();
      }
    });
  }

  void _triggerSettlementNotify() {
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_routeSettled) {
          _completeRouteSettlement(notify: true);
        }
      });
      return;
    }
    _completeRouteSettlement(notify: true);
  }

  void _completeRouteSettlement({required bool notify}) {
    if (_routeSettled) return;
    _routeSettled = true;
    _detachRouteSettledListeners();
    if (notify && mounted) {
      onRouteSettled();
    }
  }
}

/// 路由落稳延迟挂载容器：用于无状态重页面在 260ms 入场动画期间展示轻量占位，
/// 动画落稳瞬间挂载真实内容，退场期间保持已挂载内容不闪烁。
class RouteSettledGate extends StatefulWidget {
  const RouteSettledGate({
    super.key,
    required this.builder,
    required this.placeholder,
  });

  final WidgetBuilder builder;
  final Widget placeholder;

  @override
  State<RouteSettledGate> createState() => _RouteSettledGateState();
}

class _RouteSettledGateState extends State<RouteSettledGate>
    with RouteSettledStateMixin<RouteSettledGate> {
  @override
  Widget build(BuildContext context) {
    if (!isRouteSettled) {
      return widget.placeholder;
    }
    return widget.builder(context);
  }
}
