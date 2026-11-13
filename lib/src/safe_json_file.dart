/// 具备「路径级串行队列 + 临时文件原子替换 + `.bak` 自动自愈备份」的安全 JSON 文件管家。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// 单个安全 JSON 文件的读取结果。
class SafeJsonReadResult {
  const SafeJsonReadResult({
    required this.data,
    this.recoveredFromBackup = false,
    this.hadUnrecoverableCorruption = false,
  });

  /// 解析并校验通过的 JSON 对象；若无可用文件或均损坏则为 `null`。
  final Object? data;

  /// 主文件异常后是否从 `.bak` 自动恢复成功。
  final bool recoveredFromBackup;

  /// 是否检测到磁盘上存在文件但主文件与备份均已损坏、无法恢复。
  final bool hadUnrecoverableCorruption;
}

class _PendingWrite {
  _PendingWrite(this.buildPayload);

  Object? Function() buildPayload;
  final Completer<void> completer = Completer<void>();
  bool canceled = false;
}

/// 统一保障本地设置与离线缓存读/改/写安全的文件操作工具：
/// 1. 同一文件路径下的读取、修改、写入、清空共享同一条串行异步队列，杜绝并发覆写冲突；
/// 2. 连续全量写入自动合并为最新一份（最多 1 个写入中 + 1 个最新待写），防止连点堆积长队列；
/// 3. 写入先落 `.tmp` 并强制 `flush: true`，完整后再原子重命名替换主文件；
/// 4. 开启备份时保留最后一份确认完好的 `.bak` 副本；主文件破损或丢失时自动救回并自愈。
class SafeJsonFile {
  SafeJsonFile(this.file, {this.keepBackup = true});

  final File file;
  final bool keepBackup;

  File get backupFile => File('${file.path}.bak');
  File get _tempFile => File('${file.path}.tmp');
  File get _backupTempFile => File('${file.path}.bak.tmp');

  static final Map<String, Future<void>> _queues = <String, Future<void>>{};
  static final Map<String, _PendingWrite> _pendingWrites =
      <String, _PendingWrite>{};

  String get _lockKey => file.absolute.path;

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final prev = _queues[_lockKey] ?? Future<void>.value();
    final completer = Completer<T>();
    final next = prev.whenComplete(() async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    _queues[_lockKey] = next;
    next.whenComplete(() {
      if (identical(_queues[_lockKey], next)) {
        _queues.remove(_lockKey);
      }
    });
    return completer.future;
  }

  /// 安全读取并校验 JSON；若主文件损坏或丢失则尝试从 `.bak` 自动自愈恢复。
  Future<SafeJsonReadResult> readJson({
    bool Function(Object? decoded)? isValid,
  }) {
    // 封口之前的待合并写入批次，避免后续写入越过当前读取重排。
    _pendingWrites.remove(_lockKey);
    return _synchronized(() => _readLocked(isValid: isValid));
  }

  /// 排队并以原子替换方式写入最新内容；默认合并待写队列中的过期中间快照。
  Future<void> writeJson(
    Object? Function() buildPayload, {
    bool coalesce = true,
  }) {
    if (!coalesce) {
      _pendingWrites.remove(_lockKey);
      return _synchronized(() async {
        final payload = buildPayload();
        await _writeEncodedLocked(jsonEncode(payload));
      });
    }

    final existing = _pendingWrites[_lockKey];
    if (existing != null) {
      existing.buildPayload = buildPayload;
      return existing.completer.future;
    }

    final pending = _PendingWrite(buildPayload);
    _pendingWrites[_lockKey] = pending;
    unawaited(
      _synchronized(() async {
        if (identical(_pendingWrites[_lockKey], pending)) {
          _pendingWrites.remove(_lockKey);
        }
        if (pending.canceled) {
          if (!pending.completer.isCompleted) {
            pending.completer.complete();
          }
          return;
        }
        try {
          final payload = pending.buildPayload();
          await _writeEncodedLocked(jsonEncode(payload));
          if (!pending.completer.isCompleted) {
            pending.completer.complete();
          }
        } catch (error, stackTrace) {
          if (!pending.completer.isCompleted) {
            pending.completer.completeError(error, stackTrace);
          }
        }
      }),
    );
    return pending.completer.future;
  }

  /// 在同一串行锁内完成「安全读取 -> 变更合并 -> 原子写回」，防止多方并发修改互相覆盖。
  Future<void> updateJson({
    bool Function(Object? decoded)? isValid,
    required Object? Function(Object? current) transform,
  }) {
    _pendingWrites.remove(_lockKey);
    return _synchronized(() async {
      final readResult = await _readLocked(isValid: isValid);
      final updated = transform(readResult.data);
      await _writeEncodedLocked(jsonEncode(updated));
    });
  }

  /// 清理主文件及其 `.bak` 备份与 `.tmp` 残留临时文件，并取消尚未落盘的待写快照。
  Future<void> clear() {
    final pending = _pendingWrites.remove(_lockKey);
    if (pending != null) {
      pending.canceled = true;
    }
    return _synchronized(() async {
      await _deleteIfExists(file);
      await _deleteIfExists(backupFile);
      await _deleteIfExists(_tempFile);
      await _deleteIfExists(_backupTempFile);
    });
  }

  Future<SafeJsonReadResult> _readLocked({
    bool Function(Object? decoded)? isValid,
  }) async {
    final primary = await _tryParseFile(file, isValid: isValid);
    if (primary.parsed != null) {
      return SafeJsonReadResult(data: primary.parsed);
    }

    var backupExisted = false;
    if (keepBackup) {
      final backup = await _tryParseFile(backupFile, isValid: isValid);
      backupExisted = backup.existed;
      if (backup.parsed != null && backup.rawText != null) {
        // 用完好的 `.bak` 自动修复破损或缺失的主文件
        try {
          await _writeTextAtomic(file, _tempFile, backup.rawText!);
        } catch (_) {}
        return SafeJsonReadResult(
          data: backup.parsed,
          recoveredFromBackup: true,
        );
      }
    }

    final hadCorruption = primary.existed || backupExisted;
    return SafeJsonReadResult(
      data: null,
      hadUnrecoverableCorruption: hadCorruption,
    );
  }

  Future<void> _writeEncodedLocked(String encoded) async {
    await file.parent.create(recursive: true);

    // 若开启备份且当前主文件本身完好，先安全轮转一份 `.bak` 再覆盖主文件
    if (keepBackup && await file.exists()) {
      try {
        final existingText = await file.readAsString();
        if (existingText.trim().isNotEmpty) {
          jsonDecode(existingText);
          await _writeTextAtomic(backupFile, _backupTempFile, existingText);
        }
      } catch (_) {
        // 主文件若已破损，保留旧 `.bak` 不被坏数据覆盖
      }
    }

    await _writeTextAtomic(file, _tempFile, encoded);
  }

  static Future<({bool existed, String? rawText, Object? parsed})>
  _tryParseFile(File target, {bool Function(Object? decoded)? isValid}) async {
    try {
      if (!await target.exists()) {
        return (existed: false, rawText: null, parsed: null);
      }
      final rawText = await target.readAsString();
      if (rawText.trim().isEmpty) {
        return (existed: true, rawText: rawText, parsed: null);
      }
      final decoded = jsonDecode(rawText);
      if (isValid != null && !isValid(decoded)) {
        return (existed: true, rawText: rawText, parsed: null);
      }
      return (existed: true, rawText: rawText, parsed: decoded);
    } catch (_) {
      return (existed: true, rawText: null, parsed: null);
    }
  }

  static Future<void> _writeTextAtomic(
    File target,
    File temp,
    String text,
  ) async {
    await target.parent.create(recursive: true);
    try {
      await temp.writeAsString(text, flush: true);
      await temp.rename(target.path);
    } finally {
      await _deleteIfExists(temp);
    }
  }

  static Future<void> _deleteIfExists(File target) async {
    try {
      if (await target.exists()) {
        await target.delete();
      }
    } catch (_) {}
  }
}
