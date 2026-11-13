/// Cookie 快照的文件持久化（VM / Flutter 移动与桌面可用，Web 不可用）。
///
/// 会话凭据（JSESSIONID 等）属于 bearer token，落盘时：
///  - POSIX 上显式 `chmod 600`；
///  - Windows 上文件位于应用私有目录，由 ACL 兜底（Dart 没有跨平台 chmod API）。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'cookies.dart';

class _PendingCookieSave {
  _PendingCookieSave(this.snapshot);

  CookieStoreSnapshot snapshot;
  final Completer<void> completer = Completer<void>();
  bool canceled = false;
}

class FileCookieStorage {
  final String path;

  const FileCookieStorage(this.path);

  static final Map<String, Future<void>> _queues = <String, Future<void>>{};
  static final Map<String, _PendingCookieSave> _pendingSaves =
      <String, _PendingCookieSave>{};

  String get _lockKey => File(path).absolute.path;

  Future<T> _synchronized<T>(Future<T> Function() action) {
    final key = _lockKey;
    final prev = _queues[key] ?? Future<void>.value();
    final completer = Completer<T>();
    final next = prev.whenComplete(() async {
      try {
        completer.complete(await action());
      } catch (e, st) {
        completer.completeError(e, st);
      }
    });
    _queues[key] = next;
    next.whenComplete(() {
      if (identical(_queues[key], next)) {
        _queues.remove(key);
      }
    });
    return completer.future;
  }

  /// 文件不存在或内容损坏时返回 null。
  Future<CookieStoreSnapshot?> load() {
    _pendingSaves.remove(_lockKey);
    return _synchronized(() async {
      final file = File(path);
      if (!file.existsSync()) return null;
      try {
        final text = await file.readAsString();
        final decoded = jsonDecode(text);
        if (decoded is! Map<String, dynamic>) return null;
        return CookieStoreSnapshot.fromJson(decoded);
      } catch (_) {
        return null;
      }
    });
  }

  Future<void> save(CookieStoreSnapshot snapshot) {
    final key = _lockKey;
    final existing = _pendingSaves[key];
    if (existing != null) {
      existing.snapshot = snapshot;
      return existing.completer.future;
    }

    final pending = _PendingCookieSave(snapshot);
    _pendingSaves[key] = pending;
    unawaited(
      _synchronized(() async {
        if (identical(_pendingSaves[key], pending)) {
          _pendingSaves.remove(key);
        }
        if (pending.canceled) {
          if (!pending.completer.isCompleted) {
            pending.completer.complete();
          }
          return;
        }
        try {
          await _writeSnapshotLocked(pending.snapshot);
          if (!pending.completer.isCompleted) {
            pending.completer.complete();
          }
        } catch (e, st) {
          if (!pending.completer.isCompleted) {
            pending.completer.completeError(e, st);
          }
        }
      }),
    );
    return pending.completer.future;
  }

  Future<void> _writeSnapshotLocked(CookieStoreSnapshot snapshot) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmpFile = File('$path.tmp');
    try {
      await tmpFile.writeAsString(
        jsonEncode(snapshot.toJson()),
        flush: true,
      );
      await tmpFile.rename(path);
    } finally {
      if (tmpFile.existsSync()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
    }
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', path]);
      } catch (_) {}
    }
  }

  Future<void> clear() {
    final pending = _pendingSaves.remove(_lockKey);
    if (pending != null) {
      pending.canceled = true;
    }
    return _synchronized(() async {
      final file = File(path);
      if (file.existsSync()) await file.delete();
      final tmpFile = File('$path.tmp');
      if (tmpFile.existsSync()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
    });
  }
}
