/// 桌面小组件编排服务测试：偏好未读守卫、防抖合并、指纹去重、跨学期考试隔离与销毁安全。
library;

import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/widget_gateway.dart';
import 'package:qustschedule/src/widget_service.dart';
import 'package:qustschedule/src/widget_style.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';

const String _baseUrl = 'https://jw.example.edu.cn/jwglxt';
final DateTime _now = DateTime(2026, 9, 7, 8, 30);

class FakeDesktopWidgetGateway implements DesktopWidgetGateway {
  int syncCount = 0;
  int clearCount = 0;
  String? lastPayloadJson;
  DesktopWidgetKind? lastPinnedKind;
  bool pinResult = true;
  Map<DesktopWidgetKind, int> pinnedCounts = const <DesktopWidgetKind, int>{};
  Completer<void>? syncGate;
  final List<String> ops = <String>[];

  @override
  Future<bool> syncSnapshot(String payloadJson) async {
    ops.add('sync:start');
    if (syncGate != null) {
      await syncGate!.future;
    }
    syncCount++;
    lastPayloadJson = payloadJson;
    ops.add('sync:end');
    return true;
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
  Future<Map<DesktopWidgetKind, int>> getPinnedCounts() async => pinnedCounts;
}

AppModel _buildModel({Preferences? preferences}) => AppModel(
  service: ScheduleService(
    credentials: InMemoryCredentialStore(),
    cookieStorage: FakeSessionRepository(),
    backendFactory: (_) => FakeBackend(),
    baseUrl: _baseUrl,
  ),
  preferences: preferences,
  schoolBaseUrl: _baseUrl,
);

void main() {
  test('preferencesLoaded 为 false 时绝不下发，防止默认值覆盖原生', () async {
    final model = _buildModel(preferences: null);
    final gateway = FakeDesktopWidgetGateway();
    final service = DesktopWidgetService(
      model: model,
      gateway: gateway,
      debounce: const Duration(milliseconds: 1),
      now: () => _now,
    );
    addTearDown(() {
      service.dispose();
      model.dispose();
    });

    final ok = await service.syncNow();
    expect(ok, isFalse);
    expect(gateway.syncCount, 0);
  });

  test('指纹去重与 force=true 强制下发，且修改样式后触发防抖重发', () async {
    final model = _buildModel(preferences: Preferences.inMemory());
    model.hydrateForTest(
      schedule: sampleSchedule(),
      termStart: DateTime(2026, 9, 7),
      week: 1,
    );
    final gateway = FakeDesktopWidgetGateway();
    final service = DesktopWidgetService(
      model: model,
      gateway: gateway,
      debounce: const Duration(milliseconds: 10),
      now: () => _now,
    );
    addTearDown(() {
      service.dispose();
      model.dispose();
    });

    expect(await service.syncNow(), isTrue);
    expect(gateway.syncCount, 1);
    final firstPayload = gateway.lastPayloadJson;
    expect(firstPayload, isNotNull);

    // 同指纹第二次同步跳过
    expect(await service.syncNow(), isTrue);
    expect(gateway.syncCount, 1);

    // force = true 强制下发时直接复用上次 JSON 字符串实例，避免重复序列化与原生冗余解析
    expect(await service.syncNow(force: true), isTrue);
    expect(gateway.syncCount, 2);
    expect(identical(gateway.lastPayloadJson, firstPayload), isTrue);

    // 改小组件样式通过 prefsNotifier 防抖触发重新下发新载荷
    await model.setWidgetStyle(
      DesktopWidgetKind.today,
      model
          .widgetStyleOf(DesktopWidgetKind.today)
          .applyPreset(WidgetStylePreset.frostedGlass),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(gateway.syncCount, 3);
    expect(identical(gateway.lastPayloadJson, firstPayload), isFalse);
  });

  test('跨学期考试隔离与退出登录下发未登录空态快照', () async {
    final model = _buildModel(preferences: Preferences.inMemory());
    model.hydrateForTest(
      schedule: sampleSchedule('2026-2027-1'),
      termStart: DateTime(2026, 9, 7),
      week: 1,
    );
    final gateway = FakeDesktopWidgetGateway();
    final service = DesktopWidgetService(
      model: model,
      gateway: gateway,
      debounce: const Duration(milliseconds: 1),
      now: () => _now,
    );
    addTearDown(() {
      service.dispose();
      model.dispose();
    });

    // 模拟内存考试属于别的学期：不得混入当前学期小组件快照
    model.academic.hydrateForTest(
      termId: '2025-2026-2',
      exams: sampleExams('2025-2026-2'),
    );
    await service.syncNow();
    final payload1 =
        jsonDecode(gateway.lastPayloadJson!) as Map<String, Object?>;
    expect(payload1['signedIn'], isTrue);
    expect(payload1['upcomingExams'], isEmpty);

    // 退出登录（清空课表）→ 自动下发 signedIn: false 快照覆盖旧数据
    await model.signOut();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    final payload2 =
        jsonDecode(gateway.lastPayloadJson!) as Map<String, Object?>;
    expect(payload2['signedIn'], isFalse);
    expect(payload2['days'], isEmpty);
    expect(payload2['weeks'], isEmpty);
  });

  test('clearAll 等待在途 syncSnapshot 完成后再清空，避免竞态回写', () async {
    final model = _buildModel(preferences: Preferences.inMemory());
    model.hydrateForTest(
      schedule: sampleSchedule('2026-2027-1'),
      termStart: DateTime(2026, 9, 7),
      week: 1,
    );
    final gateway = FakeDesktopWidgetGateway()..syncGate = Completer<void>();
    final service = DesktopWidgetService(
      model: model,
      gateway: gateway,
      debounce: const Duration(milliseconds: 1),
      now: () => _now,
    );
    addTearDown(() {
      service.dispose();
      model.dispose();
    });

    final syncFuture = service.syncNow();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.ops, <String>['sync:start']);

    final clearFuture = service.clearAll();
    await Future<void>.delayed(Duration.zero);
    expect(gateway.ops, <String>['sync:start']);

    gateway.syncGate!.complete();
    await Future.wait(<Future<void>>[syncFuture, clearFuture]);

    expect(gateway.ops, <String>['sync:start', 'sync:end', 'clear']);
    expect(service.lastSnapshot, isNull);
  });
}
