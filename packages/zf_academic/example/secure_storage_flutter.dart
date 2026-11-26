// app 侧的凭据存储实现：把密码放进 OS 安全存储。
//
// 这个文件**不属于** zf_academic 包本身（核心包保持纯 Dart，零 Flutter 依赖），
// 请拷进你的 Flutter 项目（例如 lib/data/credential_store.dart）使用。
//
// 平台行为（flutter_secure_storage v11.x）：
//  - Android：EncryptedSharedPreferences + Tink + Android Keystore（默认行为）；
//  - Windows：DPAPI（绑定当前 Windows 用户，换用户/换机解不开 → get() 返回 null）；
//  - iOS/macOS：Keychain。
//
// 两个必配项：
//  1. Android 要把 EncryptedSharedPreferences 排除出自动备份，否则换机恢复后密钥对不上：
//     android/app/src/main/AndroidManifest.xml 里配置
//       android:allowBackup="false"
//       android:fullBackupContent="@xml/backup_rules"
//       android:dataExtractionRules="@xml/data_extraction_rules"
//     并创建对应的 res/xml/backup_rules.xml 与 res/xml/data_extraction_rules.xml
//     （排除 sharedpref 域）。
//  2. 读失败（换用户/换机/Keystore 损坏）必须容错为"无凭据 → 重新登录"，不能崩。

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:zf_academic/zf_academic.dart';

class FlutterSecureStorageCredentialStore implements CredentialStore {
  FlutterSecureStorageCredentialStore([
    FlutterSecureStorage? storage,
  ]) : _storage = storage ??
            const FlutterSecureStorage(
              iOptions: IOSOptions(
                accessibility: KeychainAccessibility.first_unlock,
              ),
            );

  final FlutterSecureStorage _storage;

  @override
  Future<Credentials?> get(String accountKey) async {
    try {
      final results = await Future.wait<String?>(<Future<String?>>[
        _storage.read(key: _userKey(accountKey)),
        _storage.read(key: credentialStoreKey(accountKey)),
      ]);
      final username = results[0];
      final password = results[1];
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
        key: _userKey(accountKey), value: credentials.username);
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
    // flutter_secure_storage 没有按前缀枚举；本 app 只用它存教务凭据，直接清空。
    await _storage.deleteAll();
  }

  String _userKey(String accountKey) => '${credentialStoreKey(accountKey)}#u';
}
