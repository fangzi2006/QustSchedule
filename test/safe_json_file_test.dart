import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/academic_cache.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/safe_json_file.dart';
import 'package:qustschedule/src/schedule_cache.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('safe_json_file_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('SafeJsonFile 原子写入与备份自愈', () {
    test('初次读取不存在文件不报损坏、二次写入轮转生成 .bak 并在主文件损坏时自愈恢复', () async {
      final file = File('${tempDir.path}/sample.json');
      final store = SafeJsonFile(file);

      final empty = await store.readJson(isValid: (d) => d is Map);
      expect(empty.data, isNull);
      expect(empty.recoveredFromBackup, isFalse);
      expect(empty.hadUnrecoverableCorruption, isFalse);

      await store.writeJson(() => <String, Object?>{'version': 1});
      expect(file.existsSync(), isTrue);
      expect(store.backupFile.existsSync(), isFalse);

      await store.writeJson(() => <String, Object?>{'version': 2});
      expect(file.existsSync(), isTrue);
      expect(store.backupFile.existsSync(), isTrue);

      final latest = await store.readJson(isValid: (d) => d is Map);
      expect((latest.data as Map)['version'], 2);

      // 模拟断电导致主文件损坏，应自动从 .bak 救回第 1 版并自愈主文件
      file.writeAsStringSync('{corrupted json');
      final healed = await store.readJson(isValid: (d) => d is Map);
      expect(healed.recoveredFromBackup, isTrue);
      expect(healed.hadUnrecoverableCorruption, isFalse);
      expect((healed.data as Map)['version'], 1);

      final secondRead = await store.readJson(isValid: (d) => d is Map);
      expect(secondRead.recoveredFromBackup, isFalse);
      expect((secondRead.data as Map)['version'], 1);
    });

    test('主文件与 .bak 均损坏时标记不可恢复损坏；clear 一并清除主文件与备份', () async {
      final file = File('${tempDir.path}/broken.json');
      final store = SafeJsonFile(file);
      await store.writeJson(() => <String, Object?>{'ok': true});
      await store.writeJson(() => <String, Object?>{'ok': true});

      file.writeAsStringSync('oops');
      store.backupFile.writeAsStringSync('also oops');

      final failed = await store.readJson(isValid: (d) => d is Map);
      expect(failed.data, isNull);
      expect(failed.hadUnrecoverableCorruption, isTrue);

      await store.clear();
      expect(file.existsSync(), isFalse);
      expect(store.backupFile.existsSync(), isFalse);
    });

    test('高并发读写按序排队执行，不发生临时文件冲突或写入丢失', () async {
      final file = File('${tempDir.path}/concurrent.json');
      final store = SafeJsonFile(file);

      await Future.wait(<Future<void>>[
        for (var i = 1; i <= 15; i++)
          store.updateJson(
            isValid: (d) => d is Map,
            transform: (current) {
              final map = current is Map
                  ? Map<String, Object?>.from(current)
                  : <String, Object?>{};
              map['k$i'] = i;
              return map;
            },
          ),
      ]);

      final result = await store.readJson(isValid: (d) => d is Map);
      final map = result.data as Map;
      for (var i = 1; i <= 15; i++) {
        expect(map['k$i'], i);
      }
    });

    test('连续快速全量写入取消中间排队，仅保留最新一份并可被 clear 取消', () async {
      final file = File('${tempDir.path}/coalesce.json');
      final store = SafeJsonFile(file);

      var executedBuilds = 0;
      await Future.wait(<Future<void>>[
        for (var i = 1; i <= 20; i++)
          store.writeJson(() {
            executedBuilds++;
            return <String, Object?>{'step': i};
          }),
      ]);

      expect(executedBuilds, lessThan(20));
      final latest = await store.readJson(isValid: (d) => d is Map);
      expect((latest.data as Map)['step'], 20);

      final delayedWrite = store.writeJson(() => <String, Object?>{'step': 99});
      await store.clear();
      await delayedWrite;
      expect(file.existsSync(), isFalse);
      expect(store.backupFile.existsSync(), isFalse);
    });
  });

  group('Preferences 抗损坏、并发排队与错误提示联动', () {
    test('高频连续改设置串行落盘完整保留；主文件损坏优先从 .bak 恢复，双坏才标记重置', () async {
      final file = File('${tempDir.path}/app_prefs.json');
      final prefs = await Preferences.openFile(file);

      await Future.wait(<Future<void>>[
        prefs.setShowTeacher(false),
        prefs.setShowLocation(false),
        prefs.setCellHeight(88),
        prefs.setCourseTextScale(1.2),
        prefs.setAutoRefreshIntervalMinutes(120),
      ]);

      final reloaded = await Preferences.openFile(file);
      expect(reloaded.showTeacher, isFalse);
      expect(reloaded.showLocation, isFalse);
      expect(reloaded.cellHeight, 88);
      expect(reloaded.courseTextScale, 1.2);
      expect(reloaded.autoRefreshIntervalMinutes, 120);
      expect(reloaded.didResetFromCorruption, isFalse);

      // 再写入一版使上一版成为 .bak，随后破坏主文件验证从 .bak 恢复
      await reloaded.setCellHeight(92);
      file.writeAsStringSync('{not valid json');
      final recovered = await Preferences.openFile(file);
      expect(recovered.didResetFromCorruption, isFalse);
      expect(recovered.showTeacher, isFalse);
      expect(recovered.cellHeight, 88);

      // 双重破坏主文件与备份文件
      file.writeAsStringSync('{broken');
      File('${file.path}.bak').writeAsStringSync('{broken');
      final reset = await Preferences.openFile(file);
      expect(reset.didResetFromCorruption, isTrue);
      expect(reset.showTeacher, isTrue);
    });

    test('拨动开关先即时刷新界面通知；存储写入失败时通过 AppModel 发出节流提示且不崩溃', () async {
      final file = File('${tempDir.path}/instant_ui_prefs.json');
      final prefs = await Preferences.openFile(file);
      final model = AppModel(
        service: ScheduleService(
          credentials: InMemoryCredentialStore(),
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => FakeBackend(),
        ),
        preferences: prefs,
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
      );
      addTearDown(model.dispose);

      var notifyCount = 0;
      var prefsNotifyCount = 0;
      model.addListener(() => notifyCount++);
      model.prefsNotifier.addListener(() => prefsNotifyCount++);

      final flushing = model.setShowTeacher(false);
      expect(model.showTeacher, isFalse);
      expect(notifyCount, 1);
      expect(prefsNotifyCount, 1);
      await flushing;

      // 构造父路径阻塞文件，验证磁盘写入失败时的节流通知
      final blocker = File('${tempDir.path}/blocker');
      blocker.writeAsStringSync('not a directory');
      final blockedFile = File('${blocker.path}/app_prefs.json');
      final blockedModel = AppModel(
        service: ScheduleService(
          credentials: InMemoryCredentialStore(),
          cookieStorage: FakeSessionRepository(),
          backendFactory: (_) => FakeBackend(),
        ),
        preferences: Preferences.decode('', file: blockedFile),
        examCache: InMemoryExamCache(),
        gradesCache: InMemoryGradesCache(),
      );
      addTearDown(blockedModel.dispose);

      expect(blockedModel.storageNoticeEvent, 0);
      await blockedModel.setShowTeacher(false);
      expect(blockedModel.storageNoticeEvent, 1);
      expect(blockedModel.storageNoticeMessage, '本地设置保存失败，请检查存储空间');

      await blockedModel.setShowLocation(false);
      expect(blockedModel.storageNoticeEvent, 1);
    });
  });

  group('FileScheduleCache 备份自愈与清理', () {
    test('主课表缓存损坏时自动从 .bak 恢复；clear 一并删除 .bak', () async {
      final file = File('${tempDir.path}/schedule.json');
      final cache = FileScheduleCache.fromFile(file);

      await cache.save(
        CachedSchedule(
          baseUrl: 'https://jw.example.edu.cn',
          schedule: sampleSchedule('2026-2027-1'),
          fetchedAt: DateTime(2026, 9, 1, 8, 0),
        ),
      );
      await cache.save(
        CachedSchedule(
          baseUrl: 'https://jw.example.edu.cn',
          schedule: sampleSchedule('2026-2027-2'),
          fetchedAt: DateTime(2026, 9, 2, 8, 0),
        ),
      );

      file.writeAsStringSync('corrupt');
      final loaded = await cache.load();
      expect(loaded, isNotNull);
      expect(loaded!.schedule.termId, '2026-2027-1');

      await cache.clear();
      expect(file.existsSync(), isFalse);
      expect(File('${file.path}.bak').existsSync(), isFalse);
    });
  });
}
