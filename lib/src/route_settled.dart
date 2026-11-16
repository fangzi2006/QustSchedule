/// 路由落稳后调度辅助：用于二级页将非首帧必须的磁盘清理或原生查询推迟到
/// 入场转场动画完全结束且离开 `offstage` 之后执行，不引入全局调度器或定时器。
library;

import 'dart:async';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

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
/// 若当前已处于稳定前台状态（无推入动画或转场已完成），则通过微任务直接执行。
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

  statusListener = (status) {
    if (handle.isDone) return;
    if (status == AnimationStatus.completed) {
      if (route?.offstage ?? false) return;
      fireOnce();
    } else if (status == AnimationStatus.reverse ||
        (status == AnimationStatus.dismissed && !(route?.isActive ?? true))) {
      handle.cancel();
    }
  };
  animation.addStatusListener(statusListener!);

  if (route != null && route.offstage) {
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
      } else if (animation.status == AnimationStatus.reverse ||
          (animation.status == AnimationStatus.dismissed && !route.isActive)) {
        handle.cancel();
      }
    }

    SchedulerBinding.instance.addPostFrameCallback((_) => checkOffstage());
  }

  return handle;
}
