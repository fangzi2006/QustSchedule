/// 原生 VM 平台的真实后台 Isolate 执行实现。
library;

import 'dart:isolate';

Future<T> runIsolateComputation<T>(T Function() computation) {
  return Isolate.run<T>(computation);
}
