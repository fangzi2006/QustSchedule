/// Cookie 快照持久化：放在 app 私有目录（path_provider），
/// 只有密码进安全存储（见 credentials_repository.dart）。
///
/// 为什么不放安全存储：Cookie 可重新获取、每次登录都会重写，
/// 放安全存储只会放大 Keystore 的读写频次与失败面。
library;

import 'package:path_provider/path_provider.dart';
import 'package:zf_academic/zf_academic_io.dart';

/// Cookie 快照的存取接口。抽象出来是为了让 app 在拿到
/// path_provider 目录之前就能构造状态机（启动占位 → boot() 时替换）。
abstract class SessionRepository {
  Future<CookieStoreSnapshot?> load();

  Future<void> save(CookieStoreSnapshot snapshot);

  Future<void> clear();
}

/// 文件实现：app 私有目录下的单个 JSON。
class FileSessionRepository implements SessionRepository {
  FileSessionRepository._(this._storage);

  final FileCookieStorage _storage;

  static Future<FileSessionRepository> open({
    String fileName = 'zf-session.json',
  }) async {
    final directory = await getApplicationSupportDirectory();
    return FileSessionRepository._(
      FileCookieStorage('${directory.path}/$fileName'),
    );
  }

  @override
  Future<CookieStoreSnapshot?> load() => _storage.load();

  @override
  Future<void> save(CookieStoreSnapshot snapshot) => _storage.save(snapshot);

  @override
  Future<void> clear() => _storage.clear();
}

/// 占位实现：目录还没就绪前的空转（load=无快照，save=丢弃）。
class LateSessionRepository implements SessionRepository {
  @override
  Future<CookieStoreSnapshot?> load() async => null;

  @override
  Future<void> save(CookieStoreSnapshot snapshot) async {}

  @override
  Future<void> clear() async {}
}
