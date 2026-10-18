import 'package:test/test.dart';
import 'package:zf_academic/zf_academic.dart';

void main() {
  group('InMemoryCredentialStore', () {
    test('保存 / 读取 / 删除 / 清空', () async {
      final store = InMemoryCredentialStore();
      expect(await store.get('qust'), isNull);
      expect(await store.has('qust'), isFalse);

      await store.save('qust', const Credentials('2407720102', 'secret'));
      expect(await store.has('qust'), isTrue);
      final loaded = await store.get('qust');
      expect(loaded, isNotNull);
      expect(loaded!.username, '2407720102');
      expect(loaded.password, 'secret');

      await store.remove('qust');
      expect(await store.get('qust'), isNull);

      await store.save('other', const Credentials('u', 'p'));
      await store.clearAll();
      expect(await store.has('other'), isFalse);
    });

    test('多账号互不干扰', () async {
      final store = InMemoryCredentialStore();
      await store.save('a', const Credentials('ua', 'pa'));
      await store.save('b', const Credentials('ub', 'pb'));
      expect((await store.get('a'))!.username, 'ua');
      expect((await store.get('b'))!.username, 'ub');
    });
  });

  group('credentialStoreKey', () {
    test('同一账号稳定、不同账号不同、且不含账号明文', () {
      final key = credentialStoreKey('2407720102');
      expect(credentialStoreKey('2407720102'), key);
      expect(key != credentialStoreKey('2407720103'), isTrue);
      expect(key.startsWith('zf_pw_'), isTrue);
      expect(RegExp(r'^zf_pw_[0-9a-f]{64}$').hasMatch(key), isTrue);
      expect(key.contains('2407720102'), isFalse, reason: '存储键必须是账号的哈希，不能出现明文');
    });
  });
}
