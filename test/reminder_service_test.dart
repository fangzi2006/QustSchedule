/// 提醒编排层测试：什么时候该下发、什么时候该取消、失败怎么办。
///
/// 全部走 [FakeReminderGateway]，不碰平台通道，也不依赖真实时间。
library;

import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/reminder_gateway.dart';
import 'package:qustschedule/src/reminder_planner.dart';
import 'package:qustschedule/src/reminder_service.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';
import 'support/fake_reminder_gateway.dart';

const String _baseUrl = 'https://jw.example.edu.cn/jwglxt';

/// 2026-09-07 是周一，课表第 1 周。
final DateTime _now = DateTime(2026, 9, 7, 6);

AppModel buildModel({Preferences? preferences}) => AppModel(
  service: ScheduleService(
    credentials: InMemoryCredentialStore(),
    cookieStorage: FakeSessionRepository(),
    backendFactory: (_) => FakeBackend(),
    baseUrl: _baseUrl,
  ),
  preferences: preferences,
  schoolBaseUrl: _baseUrl,
);

({AppModel model, FakeReminderGateway gateway, ReminderService service})
buildRig({
  bool enabled = true,
  int lead = 10,
  bool hydrate = true,
  Duration debounce = const Duration(milliseconds: 1),
}) {
  final model = buildModel(
    preferences: Preferences.inMemory(
      reminderEnabled: enabled,
      reminderLeadMinutes: lead,
    ),
  );
  if (hydrate) {
    model.hydrateForTest(
      schedule: sampleSchedule(),
      termStart: DateTime(2026, 9, 7),
      week: 1,
    );
  }
  final gateway = FakeReminderGateway();
  final service = ReminderService(
    model: model,
    gateway: gateway,
    debounce: debounce,
    now: () => _now,
  );
  addTearDown(() {
    service.dispose();
    model.dispose();
  });
  return (model: model, gateway: gateway, service: service);
}

void main() {
  group('同步与指纹', () {
    test('开启且有课表时下发一次，指纹未变不重复下发，force 强制重排', () async {
      final rig = buildRig();
      final result = await rig.service.syncNow();

      expect(result, isNotNull);
      expect(result!.ok, isTrue);
      expect(rig.gateway.syncedPayloads.length, 1);
      // 第 1 周的周一与第 2 周的周一（14 天窗口内）
      expect(rig.gateway.lastEventCount, 2);
      expect(rig.gateway.lastPayload['leadMinutes'], 10);
      expect(rig.service.lastPlan?.fingerprint, isNotEmpty);

      // 指纹没变时不重复下发
      await rig.service.syncNow();
      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 1);

      // force 时忽略指纹，强制重排（force-stop 后恢复靠它）
      await rig.service.syncNow(force: true);
      expect(rig.gateway.syncedPayloads.length, 2);
    });

    test('改提前量或切换形态均更新指纹并重新下发', () async {
      final rig = buildRig();
      await rig.service.syncNow();
      await rig.model.setReminderLeadMinutes(20);
      await rig.service.syncNow();

      expect(rig.gateway.syncedPayloads.length, 2);
      expect(rig.gateway.lastPayload['leadMinutes'], 20);
      expect(rig.gateway.lastPayload['fingerprint'], isNotEmpty);

      await rig.model.setReminderStyle(ReminderStyle.fluid);
      await rig.service.syncNow();

      expect(rig.gateway.syncedPayloads.length, 3);
      expect(rig.gateway.lastPayload['style'], 'fluid');
    });

    test('原生失败时保留指纹不清空，下次还会重试', () async {
      final rig = buildRig();
      rig.gateway.syncResult = const ReminderSyncResult.failure('boom');

      final first = await rig.service.syncNow();
      expect(first?.ok, isFalse);
      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 2, reason: '失败必须重试');

      rig.gateway.syncResult = const ReminderSyncResult(scheduled: 2);
      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 3);
      // 成功后记住指纹，再同步就跳过。
      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 3);
    });

    test('在途 syncNow 期间再改提前量，串行跟进重排确保最新提前量与指纹落盘', () async {
      final rig = buildRig(lead: 10);
      final gate = Completer<void>();
      rig.gateway.syncGate = gate;

      final first = rig.service.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(rig.gateway.syncedPayloads.length, 1);

      await rig.model.setReminderLeadMinutes(25);
      final second = rig.service.syncNow(force: true);
      rig.gateway.syncGate = null;
      gate.complete();

      await Future.wait(<Future<ReminderSyncResult?>>[first, second]);
      expect(rig.gateway.syncedPayloads.length, 2);
      expect(rig.gateway.lastPayload['leadMinutes'], 25);
      expect(rig.service.lastPlan?.leadMinutes, 25);
    });
  });

  group('取消', () {
    test('关闭开关或没有课表时取消提醒，且重复取消只调一次原生', () async {
      final rig = buildRig();
      await rig.service.syncNow();
      expect(rig.gateway.cancelCount, 0);

      await rig.model.setReminderEnabled(false);
      final result = await rig.service.syncNow();

      expect(result, isNull);
      expect(rig.gateway.cancelCount, 1);
      expect(rig.gateway.syncedPayloads.length, 1, reason: '关闭后不再下发');

      // 重复同步不会重复调用原生取消
      await rig.service.syncNow();
      expect(rig.gateway.cancelCount, 1);

      // 没有课表时同样取消且幂等
      final noScheduleRig = buildRig(hydrate: false);
      expect(await noScheduleRig.service.syncNow(), isNull);
      await noScheduleRig.service.syncNow();
      expect(noScheduleRig.gateway.cancelCount, 1);
      expect(noScheduleRig.gateway.syncedPayloads, isEmpty);
    });

    test('cancelAll 之后再同步会重新下发（换账号场景）', () async {
      final rig = buildRig();
      await rig.service.syncNow();
      await rig.service.cancelAll();
      expect(rig.gateway.cancelCount, 1);

      await rig.service.syncNow();
      expect(rig.gateway.syncedPayloads.length, 2);
    });
  });

  group('冷启动保护', () {
    test('偏好还没读到时不动作（不能把默认 false 当用户关闭）', () async {
      final model = buildModel(preferences: null);
      final gateway = FakeReminderGateway();
      final service = ReminderService(model: model, gateway: gateway);
      addTearDown(() {
        service.dispose();
        model.dispose();
      });

      expect(model.preferencesLoaded, isFalse);
      expect(await service.syncNow(), isNull);
      expect(gateway.syncedPayloads, isEmpty);
      expect(gateway.cancelCount, 0);
    });
  });

  group('防抖', () {
    test('连续通知只合并成一次下发', () async {
      final rig = buildRig(debounce: const Duration(milliseconds: 30));
      // 还没有任何下发：这几次通知应当被合并。
      unawaited(rig.model.setShowTeacher(false));
      unawaited(rig.model.setShowLocation(false));
      expect(rig.gateway.syncedPayloads, isEmpty);

      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(rig.gateway.syncedPayloads.length, 1);
    });
  });

  group('权限与测试提醒', () {
    test('测试提醒与预览提醒按当前形态和提前量派发', () async {
      final rig = buildRig(lead: 25);
      await rig.service.previewReminder();
      expect(rig.gateway.previewRequests, <String>['banner|25|false']);
      expect(rig.gateway.testRequests, isEmpty);
      expect(rig.gateway.syncedPayloads, isEmpty);

      await rig.service.sendTestReminder();
      await rig.model.setReminderStyle(ReminderStyle.fluid);
      await rig.service.sendTestReminder(delaySeconds: 30);

      expect(rig.gateway.testRequests, <String>['banner|60', 'fluid|30']);
    });

    test('stopFluid、打开自启动与权限设置调用会转发并刷新状态', () async {
      final rig = buildRig();
      rig.gateway.autostartVendorPage = true;

      await rig.service.stopFluid();
      expect(await rig.service.openAutostartSettings(), isTrue);
      await rig.service.requestNotificationPermission();
      await rig.service.openNotificationSettings();
      await rig.service.openExactAlarmSettings();
      await rig.service.openBatterySettings();

      expect(rig.gateway.stopFluidCount, 1);
      expect(rig.gateway.autostartSettingsCount, 1);
      expect(rig.gateway.notificationRequests, 1);
      expect(rig.gateway.notificationSettingsCount, 1);
      expect(rig.gateway.exactAlarmSettingsCount, 1);
      expect(rig.gateway.batterySettingsCount, 1);
      expect(rig.gateway.statusCount, 6);
      expect(rig.service.lastStatus, isNotNull);
    });
  });

  group('prefsNotifier 订阅与 cancelAll 竞态防护', () {
    test('仅 prefsNotifier 通知即可触发防抖同步，dispose 后不再响应', () async {
      final rig = buildRig(debounce: const Duration(milliseconds: 20));
      expect(rig.gateway.syncedPayloads, isEmpty);

      rig.model.prefs.notifyPrefs();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(rig.gateway.syncedPayloads.length, 1);

      rig.service.dispose();
      rig.model.prefs.notifyPrefs();
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(rig.gateway.syncedPayloads.length, 1);
    });

    test('cancelAll 等待在途 sync 完成后再调用原生 cancel（成功与异常场景）', () async {
      final rig = buildRig();
      final gate = Completer<void>();
      rig.gateway.syncGate = gate;

      final syncFuture = rig.service.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(rig.gateway.syncedPayloads.length, 1);
      expect(rig.gateway.cancelCount, 0);

      final cancelFuture = rig.service.cancelAll();
      await Future<void>.delayed(Duration.zero);
      expect(
        rig.gateway.cancelCount,
        0,
        reason: '在途 sync 尚未结束时 cancelAll 不得提前调用原生 cancel',
      );

      rig.gateway.syncGate = null;
      gate.complete();
      await Future.wait(<Future<Object?>>[syncFuture, cancelFuture]);
      expect(rig.gateway.cancelCount, 1);
      expect(rig.service.lastPlan, isNull);
      expect(rig.service.lastResult, isNull);

      // 即使在途 sync 抛出异常，cancelAll 仍应安全落到 _gateway.cancel()。
      final throwingGateway = _ThrowingSyncReminderGateway();
      final throwingModel = buildModel(
        preferences: Preferences.inMemory(reminderEnabled: true),
      );
      throwingModel.hydrateForTest(
        schedule: sampleSchedule(),
        termStart: DateTime(2026, 9, 7),
        week: 1,
      );
      final throwingService = ReminderService(
        model: throwingModel,
        gateway: throwingGateway,
        debounce: const Duration(milliseconds: 1),
        now: () => _now,
      );
      addTearDown(() {
        throwingService.dispose();
        throwingModel.dispose();
      });

      final failingSync = throwingService.syncNow();
      await Future<void>.delayed(Duration.zero);
      final cancelAfterThrow = throwingService.cancelAll();
      await Future<void>.delayed(Duration.zero);
      expect(throwingGateway.cancelCount, 0);

      throwingGateway.failGate.completeError(StateError('native boom'));
      await expectLater(failingSync, throwsStateError);
      await cancelAfterThrow;
      expect(throwingGateway.cancelCount, 1);
    });

    test('T3c: cancelAll 等待在途 sync 期间到达的 syncNow 不得在 cancel 前触发额外同步', () async {
      final gw = _OrderedReminderGateway();
      final model = buildModel(
        preferences: Preferences.inMemory(reminderEnabled: true),
      );
      model.hydrateForTest(
        schedule: sampleSchedule(),
        termStart: DateTime(2026, 9, 7),
        week: 1,
      );
      final service = ReminderService(
        model: model,
        gateway: gw,
        debounce: const Duration(milliseconds: 1),
        now: () => _now,
      );
      addTearDown(() {
        service.dispose();
        model.dispose();
      });

      final syncGate1 = Completer<void>();
      gw.syncGates.add(syncGate1);

      final sync1 = service.syncNow();
      await Future<void>.delayed(Duration.zero);
      expect(gw.ops, <String>['sync:start']);

      final cancelFuture = service.cancelAll();
      // cancelAll 等待在途 sync 期间触发 syncNow（以及 prefsNotifier 触发）
      final sync2 = service.syncNow();
      model.prefs.notifyPrefs();
      await Future<void>.delayed(const Duration(milliseconds: 5));
      expect(gw.ops, <String>[
        'sync:start',
      ], reason: 'cancelAll 尚未完成时不得启动第二次同步');

      syncGate1.complete();
      await Future.wait(<Future<Object?>>[sync1, cancelFuture, sync2]);

      expect(gw.ops, <String>[
        'sync:start',
        'sync:end',
        'cancel:start',
        'cancel:end',
        'sync:start',
        'sync:end',
      ]);
    });

    test(
      'T3a: cancelAll 正在 await _gateway.cancel 期间到达的 syncNow 串行排在其后且之后可继续同步',
      () async {
        final gw = _OrderedReminderGateway();
        final model = buildModel(
          preferences: Preferences.inMemory(reminderEnabled: true),
        );
        model.hydrateForTest(
          schedule: sampleSchedule(),
          termStart: DateTime(2026, 9, 7),
          week: 1,
        );
        final service = ReminderService(
          model: model,
          gateway: gw,
          debounce: const Duration(milliseconds: 1),
          now: () => _now,
        );
        addTearDown(() {
          service.dispose();
          model.dispose();
        });

        final cancelGate = Completer<void>();
        gw.cancelGates.add(cancelGate);

        final cancelFuture = service.cancelAll();
        await Future<void>.delayed(Duration.zero);
        expect(gw.ops, <String>['cancel:start']);

        final syncDuringCancel = service.syncNow();
        await Future<void>.delayed(Duration.zero);
        expect(gw.ops, <String>[
          'cancel:start',
        ], reason: 'cancel 尚未结束前不得并发调用 _gateway.sync');

        cancelGate.complete();
        await Future.wait(<Future<Object?>>[cancelFuture, syncDuringCancel]);
        expect(gw.ops, <String>[
          'cancel:start',
          'cancel:end',
          'sync:start',
          'sync:end',
        ]);

        // cancelAll 彻底结束后继续调 syncNow(force: true) 仍能正常工作
        final after = await service.syncNow(force: true);
        expect(after?.ok, isTrue);
        expect(gw.ops, <String>[
          'cancel:start',
          'cancel:end',
          'sync:start',
          'sync:end',
          'sync:start',
          'sync:end',
        ]);
      },
    );

    test('T3b: 在途 sync 抛错时已排队的二次 syncNow 仍独立执行并解析各自结果', () async {
      final gw = _OrderedReminderGateway();
      final model = buildModel(
        preferences: Preferences.inMemory(
          reminderEnabled: true,
          reminderLeadMinutes: 10,
        ),
      );
      model.hydrateForTest(
        schedule: sampleSchedule(),
        termStart: DateTime(2026, 9, 7),
        week: 1,
      );
      final service = ReminderService(
        model: model,
        gateway: gw,
        debounce: const Duration(milliseconds: 1),
        now: () => _now,
      );
      addTearDown(() {
        service.dispose();
        model.dispose();
      });

      final firstGate = Completer<void>();
      gw.syncGates.add(firstGate);
      gw.syncErrors.add(StateError('sync failed'));

      final first = service.syncNow();
      await Future<void>.delayed(Duration.zero);

      await model.setReminderLeadMinutes(30);
      final second = service.syncNow(force: true);

      firstGate.complete();
      await expectLater(first, throwsStateError);
      final secondResult = await second;
      expect(secondResult, isNotNull);
      expect(secondResult!.ok, isTrue);
      expect(service.lastPlan?.leadMinutes, 30);
      expect(gw.ops, <String>[
        'sync:start',
        'sync:throw',
        'sync:start',
        'sync:end',
      ]);
    });

    test('dispose 期间存在挂起 sync/cancel/post-cancel 排队时安全收尾不卡死且不越界调用原生', () async {
      final gw = _OrderedReminderGateway();
      final model = buildModel(
        preferences: Preferences.inMemory(reminderEnabled: true),
      );
      model.hydrateForTest(
        schedule: sampleSchedule(),
        termStart: DateTime(2026, 9, 7),
        week: 1,
      );
      final service = ReminderService(
        model: model,
        gateway: gw,
        debounce: const Duration(milliseconds: 1),
        now: () => _now,
      );
      addTearDown(model.dispose);

      final cancelGate = Completer<void>();
      gw.cancelGates.add(cancelGate);

      final cancelFuture = service.cancelAll();
      await Future<void>.delayed(Duration.zero);
      final queuedAfterCancel = service.syncNow();

      service.dispose();
      cancelGate.complete();

      await cancelFuture;
      expect(await queuedAfterCancel, isNull);
      expect(gw.ops, <String>['cancel:start', 'cancel:end']);
    });
  });

  group('ReminderRuntimeStatus 与 MethodChannelReminderGateway 契约', () {
    test('ReminderRuntimeStatus.fromMap 正确解析 dirty 与全字段及相等性', () {
      expect(
        ReminderRuntimeStatus.fromMap(null),
        const ReminderRuntimeStatus.unavailable(),
      );

      final parsed = ReminderRuntimeStatus.fromMap(<Object?, Object?>{
        'notificationPermission': true,
        'notificationsEnabled': true,
        'exactAlarmAllowed': false,
        'batteryOptimizationIgnored': true,
        'autoStartVendorPage': true,
        'scheduled': 5,
        'nextTriggerMs': 1700000100000,
        'payloadAtMs': 1700000000000,
        'fingerprint': 'fp-123',
        'style': 'fluid',
        'dirty': true,
        'fluidCasting': true,
      });

      expect(parsed.available, isTrue);
      expect(parsed.canNotify, isTrue);
      expect(parsed.exactAlarmAllowed, isFalse);
      expect(parsed.batteryOptOut, isTrue);
      expect(parsed.autoStartVendorPage, isTrue);
      expect(parsed.scheduled, 5);
      expect(parsed.nextTriggerMs, 1700000100000);
      expect(parsed.payloadAtMs, 1700000000000);
      expect(parsed.fingerprint, 'fp-123');
      expect(parsed.style, 'fluid');
      expect(parsed.dirty, isTrue);
      expect(parsed.fluidCasting, isTrue);

      const cleanCopy = ReminderRuntimeStatus(
        notificationPermission: true,
        notificationsEnabled: true,
        exactAlarmAllowed: false,
        batteryOptimizationIgnored: true,
        autoStartVendorPage: true,
        scheduled: 5,
        nextTriggerMs: 1700000100000,
        payloadAtMs: 1700000000000,
        fingerprint: 'fp-123',
        style: 'fluid',
        dirty: false,
        fluidCasting: true,
      );
      expect(parsed, isNot(equals(cleanCopy)));
      expect(parsed.hashCode, isNot(equals(cleanCopy.hashCode)));
    });

    test(
      'MethodChannelReminderGateway 往返 status/previewReminder/toast 与异常处理',
      () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        const gw = MethodChannelReminderGateway();
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        addTearDown(
          () => messenger.setMockMethodCallHandler(
            MethodChannelReminderGateway.channel,
            null,
          ),
        );

        final calls = <MethodCall>[];
        messenger.setMockMethodCallHandler(
          MethodChannelReminderGateway.channel,
          (call) async {
            calls.add(call);
            return switch (call.method) {
              'status' => <String, Object?>{
                'notificationPermission': true,
                'notificationsEnabled': true,
                'exactAlarmAllowed': true,
                'scheduled': 2,
                'style': 'banner',
                'dirty': true,
                'fluidCasting': false,
              },
              'previewReminder' => true,
              'toast' => null,
              _ => null,
            };
          },
        );

        final st = await gw.status();
        expect(st.available, isTrue);
        expect(st.dirty, isTrue);
        expect(st.scheduled, 2);

        final previewed = await gw.previewReminder(
          style: 'fluid',
          leadMinutes: 10,
          untilEnd: true,
        );
        expect(previewed, isTrue);

        await gw.showToast('已打开自启动设置', longDuration: true);

        expect(calls[0].method, 'status');
        expect(calls[1].method, 'previewReminder');
        expect(calls[1].arguments, <String, Object?>{
          'style': 'fluid',
          'leadMinutes': 10,
          'untilEnd': true,
        });
        expect(calls[2].method, 'toast');
        expect(calls[2].arguments, <String, Object?>{
          'message': '已打开自启动设置',
          'long': true,
        });

        // MissingPluginException -> 安全降级
        messenger.setMockMethodCallHandler(
          MethodChannelReminderGateway.channel,
          null,
        );
        expect(await gw.status(), const ReminderRuntimeStatus.unavailable());
        expect((await gw.sync('{}')).ok, isFalse);

        // PlatformException -> 安全降级
        messenger.setMockMethodCallHandler(
          MethodChannelReminderGateway.channel,
          (call) async {
            throw PlatformException(code: 'ERR', message: 'native error');
          },
        );
        expect(await gw.status(), const ReminderRuntimeStatus.unavailable());
        final syncFailed = await gw.sync('{}');
        expect(syncFailed.ok, isFalse);
        expect(syncFailed.error, 'native error');
        expect(
          await gw.previewReminder(style: 'banner', leadMinutes: 10),
          isFalse,
        );
        await gw.showToast('ignored');
      },
    );
  });
}

class _ThrowingSyncReminderGateway extends FakeReminderGateway {
  final Completer<void> failGate = Completer<void>();

  @override
  Future<ReminderSyncResult> sync(String payloadJson) async {
    syncedPayloads.add(payloadJson);
    await failGate.future;
    return syncResult;
  }
}

class _OrderedReminderGateway extends FakeReminderGateway {
  final List<String> ops = <String>[];
  final List<Completer<void>> syncGates = <Completer<void>>[];
  final List<Object> syncErrors = <Object>[];
  final List<Completer<void>> cancelGates = <Completer<void>>[];

  @override
  Future<ReminderSyncResult> sync(String payloadJson) async {
    ops.add('sync:start');
    syncedPayloads.add(payloadJson);
    if (syncGates.isNotEmpty) {
      await syncGates.removeAt(0).future;
    }
    if (syncErrors.isNotEmpty) {
      ops.add('sync:throw');
      throw syncErrors.removeAt(0);
    }
    ops.add('sync:end');
    return syncResult;
  }

  @override
  Future<void> cancel() async {
    ops.add('cancel:start');
    cancelCount++;
    if (cancelGates.isNotEmpty) {
      await cancelGates.removeAt(0).future;
    }
    ops.add('cancel:end');
  }
}
