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

  /// 文件不存在时返回 null（首次运行的正常状态）。
  Future<CookieStoreSnapshot?> load() async {
    final file = File(path);
    if (!file.existsSync()) return null;
    final text = await file.readAsString();
    return CookieStoreSnapshot.fromJson(
      jsonDecode(text) as Map<String, dynamic>,
    );
  }

  Future<void> save(CookieStoreSnapshot snapshot) async {
    final file = File(path);
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(snapshot.toJson()));
    try {
      await Process.run('chmod', ['600', path]);
    } catch (_) {
      // Windows 等没有 chmod 的平台忽略即可。
    }
  }

  Future<void> clear() async {
    final file = File(path);
    if (file.existsSync()) await file.delete();
  }
}
