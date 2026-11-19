/// 桌面小组件的原生通道抽象。
///
/// 保持与 `reminder_gateway.dart` 同构的窄接口设计：
/// - Flutter 侧页面与 [DesktopWidgetService] 绝不直接碰 [MethodChannel]；
/// - 测试可零成本替换为假实现，离线验证快照同步与置顶交互。
library;

import 'package:flutter/services.dart';

import 'widget_style.dart';

abstract class DesktopWidgetGateway {
  const DesktopWidgetGateway();

  /// 下发完整小组件快照 JSON 并刷新桌面全部活跃实例。
  Future<bool> syncSnapshot(String payloadJson);

  /// 清空本地小组件快照（退出登录或课表被清除时调用）。
  Future<void> clearSnapshot();

  /// 请求系统桌面将指定形态小组件一键添加到主屏幕（Android 8.0+）。
  ///
  /// 返回 `true` 表示系统确认弹框/请求已受理；返回 `false` 表示启动器不支持或被拒绝。
  Future<bool> requestPinWidget(DesktopWidgetKind kind);

  /// 查询各形态小组件当前已添加到桌面的实例数量。
  Future<Map<DesktopWidgetKind, int>> getPinnedCounts();
}

class MethodChannelDesktopWidgetGateway implements DesktopWidgetGateway {
  const MethodChannelDesktopWidgetGateway([
    this.channel = const MethodChannel('qustschedule/widget'),
  ]);

  final MethodChannel channel;

  @override
  Future<bool> syncSnapshot(String payloadJson) async {
    try {
      final result = await channel.invokeMethod<bool>(
        'syncSnapshot',
        <String, Object?>{'payload': payloadJson},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<void> clearSnapshot() async {
    try {
      await channel.invokeMethod<void>('clearSnapshot');
    } on MissingPluginException {
      // 桌面端 / 单测无原生插件实现，安全忽略。
    } on PlatformException {
      // 忽略瞬时通道错误。
    }
  }

  @override
  Future<bool> requestPinWidget(DesktopWidgetKind kind) async {
    try {
      final result = await channel.invokeMethod<bool>(
        'requestPinWidget',
        <String, Object?>{'kind': kind.wireName},
      );
      return result ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  @override
  Future<Map<DesktopWidgetKind, int>> getPinnedCounts() async {
    try {
      final raw = await channel.invokeMethod<Map<Object?, Object?>>(
        'getPinnedCounts',
      );
      if (raw == null) return const <DesktopWidgetKind, int>{};
      final counts = <DesktopWidgetKind, int>{};
      for (final kind in DesktopWidgetKind.values) {
        final v = raw[kind.wireName];
        if (v is num) counts[kind] = v.toInt();
      }
      return counts;
    } on MissingPluginException {
      return const <DesktopWidgetKind, int>{};
    } on PlatformException {
      return const <DesktopWidgetKind, int>{};
    }
  }
}
