/// 凭据存储：需求 1「保存账号密码」与需求 2「失效自动重登」的原料。
///
/// 接口只有五个动作：save / load / has / remove / clearAll，按 accountKey 分桶。
/// **核心包保持纯 Dart**：flutter_secure_storage 是 Flutter 插件，不能进依赖；
/// app 侧实现见 `example/secure_storage_flutter.dart`，拷进你的项目即可。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' show sha256;

import 'crypto.dart' show bytesToHex;

/// 一对登录凭据。password 只在内存与平台安全存储里流动，模块不写盘。
class Credentials {
  final String username;
  final String password;

  const Credentials(this.username, this.password);
}

abstract class CredentialStore {
  const CredentialStore();

  /// 取不到返回 null（未保存 / 已删除 / 解密失败都应如此）。
  Future<Credentials?> get(String accountKey);

  Future<void> save(String accountKey, Credentials credentials);

  Future<void> remove(String accountKey);

  Future<bool> has(String accountKey);

  Future<void> clearAll();
}

/// 内存实现：进程重启即丢失，供测试与"仅在本次会话记住密码"的场景使用。
class InMemoryCredentialStore implements CredentialStore {
  final Map<String, Credentials> _data = <String, Credentials>{};

  @override
  Future<Credentials?> get(String accountKey) async => _data[accountKey];

  @override
  Future<void> save(String accountKey, Credentials credentials) async {
    _data[accountKey] = credentials;
  }

  @override
  Future<void> remove(String accountKey) async {
    _data.remove(accountKey);
  }

  @override
  Future<bool> has(String accountKey) async => _data.containsKey(accountKey);

  @override
  Future<void> clearAll() async {
    _data.clear();
  }
}

/// 派生安全存储 key：`zf_pw_` + sha256(accountKey)。
/// 与主分支 `CredentialStore.kt` 的 `prefKey` 一致——存储键里不出现账号明文。
String credentialStoreKey(String accountKey) {
  final digest = sha256.convert(utf8.encode(accountKey));
  return 'zf_pw_${bytesToHex(Uint8List.fromList(digest.bytes))}';
}
