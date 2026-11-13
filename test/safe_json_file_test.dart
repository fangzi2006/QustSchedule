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
    test('初次读取不存在文件不报损坏；二次写入轮转生成 .bak 备份', () async {
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
    });

    test('主文件损坏或被截断为空时，自动从 .bak 无感救回并自愈主文件', () async {
      final file = File('${tempDir.path}/prefs.json');
      final store = SafeJsonFile(file);

      await store.writeJson(() => <String, Object?>{'step': 1});
      await store.writeJson(() => <String, Object?>{'step': 2});

      // 模拟断电导致主文件写半截或成空文件
      file.writeAsStringSync('{corrupted json');

      final healed = await store.readJson(isValid: (d) => d is Map);
      expect(healed.recoveredFromBackup, isTrue);
      expect(healed.hadUnrecoverableCorruption, isFalse);
      expect((healed.data as Map)['step'], 1);

      // 主文件应已被 .bak 内容自愈修复
      final secondRead = await store.readJson(isValid: (d) => d is Map);
      expect(secondRead.recoveredFromBackup, isFalse);
      expect((secondRead.data as Map)['step'], 1);
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

      // 排队中的待写快照遇到后续 clear 时应直接作废，不会在 clear 后死灰复燃
      final delayedWrite = store.writeJson(() => <String, Object?>{'step': 99});
      await store.clear();
      await delayedWrite;
      expect(file.existsSync(), isFalse);
      expect(store.backupFile.existsSync(), isFalse);
    });
  });

  group('Preferences 抗损坏、并发排队与错误提示联动', () {
    test('高频连续改设置串行落盘，全部变更完整保留', () async {
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
    });

    test('主设置文件损坏时优先从 .bak 恢复且不标为重置；双坏才标记重置', () async {
      final file = File('${tempDir.path}/app_prefs.json');
      final prefs = await Preferences.openFile(file);
      await prefs.setShowTeacher(false); // 写入第 1 版
      await prefs.setCellHeight(92); // 写入第 2 版并把第 1 版留作 .bak

      // 破坏主文件
      file.writeAsStringSync('{not valid json');
      final recovered = await Preferences.openFile(file);
      expect(recovered.didResetFromCorruption, isFalse);
      expect(recovered.showTeacher, isFalse);

      // 双重破坏主文件与备份文件
      file.writeAsStringSync('{broken');
      File('${file.path}.bak').writeAsStringSync('{broken');
      final reset = await Preferences.openFile(file);
      expect(reset.didResetFromCorruption, isTrue);
      expect(reset.showTeacher, isTrue);
    });

    test('设置写入目录被同名文件阻塞时通过 AppModel 发出节流提示，不崩溃', () async {
      // 把父路径建造成普通文件，必然触发磁盘写入异常
      final blocker = File('${tempDir.path}/blocker');
      blocker.writeAsStringSync('not a directory');
      final blockedFile = File('${blocker.path}/app_prefs.json');

      final prefs = Preferences.decode('', file: blockedFile);
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

      expect(model.storageNoticeEvent, 0);
      await model.setShowTeacher(false);
      expect(model.storageNoticeEvent, 1);
      expect(model.storageNoticeMessage, '本地设置保存失败，请检查存储空间');

      // 连续失败只提醒一次，不刷屏
      await model.setShowLocation(false);
      expect(model.storageNoticeEvent, 1);
    });

    test('拨动开关先即时刷新界面通知，不等待磁盘落盘完成', () async {
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
      // 尚未 await 落盘前，内存状态与界面通知均应已同步到位
      expect(model.showTeacher, isFalse);
      expect(notifyCount, 1);
      expect(prefsNotifyCount, 1);

      await flushing;
      final reloaded = await Preferences.openFile(file);
      expect(reloaded.showTeacher, isFalse);
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

      // 主文件被破坏
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
