/// 无 `dart:isolate` 平台（如 Web）的后台计算降级实现。
library;

Future<T> runIsolateComputation<T>(T Function() computation) {
  return Future<T>.microtask(computation);
}
