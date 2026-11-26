/// 测试用桌面小组件假通道：替代分散在多份测试中的重复假实现。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:qustschedule/src/widget_gateway.dart';
import 'package:qustschedule/src/widget_style.dart';

class FakeDesktopWidgetGateway implements DesktopWidgetGateway {
  FakeDesktopWidgetGateway({
    this.pinResult = true,
    this.syncResult = true,
    this.pinnedCounts = const <DesktopWidgetKind, int>{},
  });

  int syncCount = 0;
  int clearCount = 0;
  int pinnedQueryCount = 0;
  int ensureLiveUpdatesCount = 0;
  String? lastPayloadJson;
  DesktopWidgetKind? lastPinnedKind;
  bool pinResult;
  bool syncResult;
  Map<DesktopWidgetKind, int> pinnedCounts;
  Completer<void>? syncGate;
  final List<String> ops = <String>[];

  final ValueNotifier<Map<DesktopWidgetKind, int>?> _livePinnedCounts =
      ValueNotifier<Map<DesktopWidgetKind, int>?>(null);

  @override
  ValueListenable<Map<DesktopWidgetKind, int>?> get livePinnedCounts =>
      _livePinnedCounts;

  @override
  Future<void> ensureLivePinnedUpdates() async {
    ensureLiveUpdatesCount++;
  }

  void emitLivePinnedCounts(Map<DesktopWidgetKind, int>? counts) {
    _livePinnedCounts.value = counts;
  }

  void dispose() {
    _livePinnedCounts.dispose();
  }

  @override
  Future<bool> syncSnapshot(String payloadJson) async {
    ops.add('sync:start');
    if (syncGate != null) {
      await syncGate!.future;
    }
    syncCount++;
    lastPayloadJson = payloadJson;
    ops.add('sync:end');
    return syncResult;
  }

  @override
  Future<void> clearSnapshot() async {
    clearCount++;
    lastPayloadJson = null;
    ops.add('clear');
  }

  @override
  Future<bool> requestPinWidget(DesktopWidgetKind kind) async {
    lastPinnedKind = kind;
    return pinResult;
  }

  @override
  Future<Map<DesktopWidgetKind, int>> getPinnedCounts() async {
    pinnedQueryCount++;
    return pinnedCounts;
  }
}
