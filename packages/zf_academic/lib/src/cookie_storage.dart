/// Cookie 快照的文件持久化（VM / Flutter 移动与桌面可用，Web 不可用）。
///
/// 会话凭据（JSESSIONID 等）属于 bearer token，落盘时：
///  - POSIX 上显式 `chmod 600`；
///  - Windows 上文件位于应用私有目录，由 ACL 兜底（Dart 没有跨平台 chmod API）。
library;

import 'dart:convert';
import 'dart:io';

import 'cookies.dart';

class FileCookieStorage {
  final String path;

  const FileCookieStorage(this.path);

  /// 文件不存在或内容损坏时返回 null。
  Future<CookieStoreSnapshot?> load() async {
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
  }

  Future<void> save(CookieStoreSnapshot snapshot) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    final tmpFile = File('$path.tmp');
    try {
      await tmpFile.writeAsString(
        jsonEncode(snapshot.toJson()),
        flush: true,
      );
      await tmpFile.rename(path);
    } catch (_) {
      if (tmpFile.existsSync()) {
        try {
          await tmpFile.delete();
        } catch (_) {}
      }
      rethrow;
    }
    if (!Platform.isWindows) {
      try {
        await Process.run('chmod', ['600', path]);
      } catch (_) {}
    }
  }

  Future<void> clear() async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}
