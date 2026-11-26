/// 安全凭据存储（[SecureCredentialStore]）单元测试。
library;

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/credentials_repository.dart';
import 'package:zf_academic/zf_academic.dart';

class _ThrowingSecureStorage extends Fake implements FlutterSecureStorage {
  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw PlatformException(code: 'read_error', message: 'Keystore corrupted');
  }

  @override
  Future<bool> containsKey({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw PlatformException(code: 'has_error', message: 'Keystore unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('SecureCredentialStore', () {
    setUp(() {
      FlutterSecureStorage.setMockInitialValues(<String, String>{});
    });

    test('save / has / get 完整往返且存储键经过哈希不暴露账号明文', () async {
      final backing = <String, String>{};
      FlutterSecureStorage.setMockInitialValues(backing);
      final store = SecureCredentialStore();

      const key = 'https://jw.example.edu.cn/jwglxt|20240001';
      expect(await store.has(key), isFalse);
      expect(await store.get(key), isNull);

      await store.save(key, const Credentials('20240001', 'secret_pw'));
      expect(await store.has(key), isTrue);

      final loaded = await store.get(key);
      expect(loaded, isNotNull);
      expect(loaded!.username, '20240001');
      expect(loaded.password, 'secret_pw');

      final hashed = credentialStoreKey(key);
      expect(backing.containsKey(hashed), isTrue);
      expect(backing.containsKey('$hashed#u'), isTrue);
      expect(backing.keys.any((k) => k.contains('20240001')), isFalse);
    });

    test('仅存在用户名或仅存在密码时 get() 返回 null', () async {
      const key = 'https://jw.example.edu.cn/jwglxt|20240002';
      final hashed = credentialStoreKey(key);

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        '$hashed#u': '20240002',
      });
      final storeOnlyUser = SecureCredentialStore();
      expect(await storeOnlyUser.get(key), isNull);
      expect(await storeOnlyUser.has(key), isFalse);

      FlutterSecureStorage.setMockInitialValues(<String, String>{
        hashed: 'pw_only',
      });
      final storeOnlyPw = SecureCredentialStore();
      expect(await storeOnlyPw.get(key), isNull);
      expect(await storeOnlyPw.has(key), isTrue);
    });

    test('remove 仅移除指定账号，clearAll 清空全部凭据', () async {
      final store = SecureCredentialStore();
      const keyA = 'https://a.edu.cn/jwglxt|1001';
      const keyB = 'https://b.edu.cn/jwglxt|1002';

      await store.save(keyA, const Credentials('1001', 'pwA'));
      await store.save(keyB, const Credentials('1002', 'pwB'));

      await store.remove(keyA);
      expect(await store.has(keyA), isFalse);
      expect(await store.get(keyA), isNull);
      expect(await store.has(keyB), isTrue);
      expect((await store.get(keyB))?.password, 'pwB');

      await store.clearAll();
      expect(await store.has(keyB), isFalse);
      expect(await store.get(keyB), isNull);
    });

    test('底层安全存储抛异常时 get() 返回 null、has() 返回 false 且不崩溃', () async {
      final store = SecureCredentialStore(_ThrowingSecureStorage());

      expect(await store.get('any|key'), isNull);
      expect(await store.has('any|key'), isFalse);
    });
  });
}
