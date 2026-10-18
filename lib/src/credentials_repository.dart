/// 凭据存储的 Flutter 实现：密码进 OS 安全存储，永不落明文盘。
///
/// 平台行为（flutter_secure_storage v11）：
///  - Android：EncryptedSharedPreferences + Tink + Android Keystore（默认行为）；
///  - Windows：DPAPI（绑定当前 Windows 用户；换用户/换机读失败 → get() 返回 null）；
///  - iOS/macOS：Keychain。
///
/// 对应 `zf_academic/example/secure_storage_flutter.dart`，按 v11 API 调整。
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zf_academic/zf_academic.dart';

class SecureCredentialStore implements CredentialStore {
  SecureCredentialStore([FlutterSecureStorage? storage])
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<Credentials?> get(String accountKey) async {
    try {
      final username = await _storage.read(key: _userKey(accountKey));
      final password = await _storage.read(key: credentialStoreKey(accountKey));
      if (username == null || password == null) return null;
      return Credentials(username, password);
    } catch (_) {
      // Keystore 损坏 / 换用户 / 换机：一律按"无凭据"处理，由上层引导重新登录。
      return null;
    }
  }

  @override
  Future<void> save(String accountKey, Credentials credentials) async {
    await _storage.write(
      key: _userKey(accountKey),
      value: credentials.username,
    );
    await _storage.write(
      key: credentialStoreKey(accountKey),
      value: credentials.password,
    );
  }

  @override
  Future<void> remove(String accountKey) async {
    await _storage.delete(key: _userKey(accountKey));
    await _storage.delete(key: credentialStoreKey(accountKey));
  }

  @override
  Future<bool> has(String accountKey) async {
    try {
      return await _storage.containsKey(key: credentialStoreKey(accountKey));
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> clearAll() async {
    await _storage.deleteAll();
  }

  /// 用户名单独存一份（存储键同样是哈希，不出账号明文），
  /// 这样"记住密码"的账号可以在登录页预填。
  String _userKey(String accountKey) => '${credentialStoreKey(accountKey)}#u';
}
