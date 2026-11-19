/// 桌面小组件编排服务测试：偏好未读守卫、防抖合并、指纹去重、跨学期考试隔离与销毁安全。
library;

import 'dart:convert';
import 'dart:typed_data';

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

  @override
  Future<bool> syncSnapshot(String payloadJson) async {
    syncCount++;
    lastPayloadJson = payloadJson;
    return true;
  }

  @override
  Future<void> clearSnapshot() async {
    clearCount++;
    lastPayloadJson = null;
  }

  @override
  Future<bool> requestPinWidget(DesktopWidgetKind kind) async {
    lastPinnedKind = kind;
    return pinResult;
  }

  @override
  Future<Map<DesktopWidgetKind, int>> getPinnedCounts() async => pinnedCounts;

  @override
  Future<Uint8List?> renderPreview({
    required DesktopWidgetKind kind,
    required String payloadJson,
    required int widthDp,
    required int heightDp,
    required int nowMs,
    required bool isDarkWallpaper,
  }) async => null;
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

    // 同指纹第二次同步跳过
    expect(await service.syncNow(), isTrue);
    expect(gateway.syncCount, 1);

    // force = true 强制下发
    expect(await service.syncNow(force: true), isTrue);
    expect(gateway.syncCount, 2);

    // 改小组件样式通过 prefsNotifier 防抖触发重新下发
    await model.setWidgetStyle(
      DesktopWidgetKind.today,
      model
          .widgetStyleOf(DesktopWidgetKind.today)
          .applyPreset(WidgetStylePreset.frostedGlass),
    );
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(gateway.syncCount, 3);
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
}
