import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:test/test.dart';
import 'package:zf_academic/zf_academic.dart';

// 来自 plugin-starter-v3/tests/protocol-auth.test.mjs 与主分支
// ZhengfangCasProtocolTest.kt 共用的对拍锚点：同一 modulus/exponent/明文必须得到同一密文。
// TS 参考实现（zf-academic-client/test/crypto.test.ts）用同一组常量。
const _casModulus =
    'b1d2af160ebaa47adfef6e4f98a6f1045bd6dc5bfba4bf427c9a653307424d955'
    'bf9bbe79a6f5444b7bb04dc8fd4d4c36063d67fbab5c6732b6a2ed6bbf6f45d';
const _casCipherTest1234 =
    '67c1c3ced32581ae2625105404296e398ce4c021eec4483f55ba63b7f4752c09'
    '70b92d0c17c50481346d8d2fc5d89ff906d35091a0792f74e0b0ff5ce977a370';

({RSAPublicKey publicKey, RSAPrivateKey privateKey}) _generateKeyPair(
  int bitLength,
) {
  final random = FortunaRandom();
  random.seed(
    KeyParameter(
      Uint8List.fromList(
        List<int>.generate(32, (_) => Random.secure().nextInt(256)),
      ),
    ),
  );
  final generator = RSAKeyGenerator()
    ..init(
      ParametersWithRandom(
        RSAKeyGeneratorParameters(BigInt.from(65537), bitLength, 64),
        random,
      ),
    );
  final pair = generator.generateKeyPair();
  return (
    publicKey: pair.publicKey as RSAPublicKey,
    privateKey: pair.privateKey as RSAPrivateKey,
  );
}

void main() {
  group('正方定制 CAS 加密（无填充裸 RSA + 自定义分块）', () {
    test('CAS 加密的确定性向量（已知答案对拍）', () {
      expect(
        zfCasEncryptPassword('Test1234', _casModulus, '10001'),
        _casCipherTest1234,
      );
    });

    test('分块长度随模数变化：512 位模数块长 62 码元，多块空格连接且都落在模数内', () {
      final modulus = bigIntFromBytes(hexToBytes(_casModulus));
      expect(
        zfCasEncryptPassword('a', _casModulus, '10001').contains(' '),
        isFalse,
      );
      final blocks =
          zfCasEncryptPassword('a' * 64, _casModulus, '10001').split(' ');
      expect(blocks.length, 2, reason: '64 个字符应分成两块');
      for (final block in blocks) {
        expect(RegExp(r'^[0-9a-f]{1,128}$').hasMatch(block), isTrue);
        expect(bigIntFromBytes(hexToBytes(block)) < modulus, isTrue);
      }
      // 确定性：同样输入必须得到同样输出。
      expect(
        zfCasEncryptPassword('a' * 64, _casModulus, '10001'),
        blocks.join(' '),
      );
    });

    test('UTF-16 码元语义：中文密码可用且格式正确', () {
      final cipher = zfCasEncryptPassword('密码', _casModulus, '10001');
      expect(cipher.contains(' '), isFalse);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(cipher), isTrue);
    });

    test('会拒绝畸形公钥，而不是发出可疑请求', () {
      expect(
        () => zfCasEncryptPassword('x', 'zz', '10001'),
        throwsA(
          isA<AcademicError>().having(
            (error) => error.code,
            'code',
            ErrorCode.pageChanged,
          ),
        ),
      );
      expect(
        () => zfCasEncryptPassword('x', _casModulus, ''),
        throwsA(isA<AcademicError>()),
      );
    });
  });

  group('表单登录 PKCS#1 v1.5 加密', () {
    test('加密结果能被私钥解回明文；两次加密不同（随机填充）', () {
      final keys = _generateKeyPair(1024);
      final cipher = rsaEncryptPkcs1(keys.publicKey, 'Test1234');
      expect(rsaDecryptPkcs1(keys.privateKey, cipher), 'Test1234');
      expect(rsaEncryptPkcs1(keys.publicKey, 'Test1234'), isNot(cipher));
    });

    test('学校给 base64 modulus/exponent：产出可解密密文，长度与 1024 位密钥匹配', () {
      final keys = _generateKeyPair(1024);
      final modulus = base64.encode(bigIntToBytes(keys.publicKey.modulus!));
      final exponent = base64.encode(bigIntToBytes(keys.publicKey.exponent!));
      const password = 'p@ssw0rd-20060304';
      final cipher = zfFormEncryptPassword(modulus, exponent, password);
      expect(
        cipher.length,
        172,
        reason: '1024 位密钥 → 128 字节密文 → 172 个 base64 字符'
            '（青岛科技大学实测同值）',
      );
      expect(rsaDecryptPkcs1(keys.privateKey, cipher), password);
    });

    test('畸形 modulus 直接报错，不带着垃圾数据继续', () {
      expect(
        () => zfFormEncryptPassword('not base64!!', 'AQAB', 'x'),
        throwsA(isA<AcademicError>()),
      );
    });

    test('编码助手：base64 / hex / BigInt 往返', () {
      final bytes = Uint8List.fromList([0, 1, 127, 128, 255, 0x0a]);
      expect(base64FromBytes(bytes), base64.encode(bytes));
      expect(hexToBytes('0a0bff'), Uint8List.fromList([0x0a, 0x0b, 0xff]));
      expect(bytesToHex(Uint8List.fromList([0x0a, 0x0b, 0xff])), '0a0bff');
      expect(bigIntFromBytes(hexToBytes('0100')), BigInt.from(256));
      expect(bigIntToBytes(BigInt.from(256)), Uint8List.fromList([1, 0]));
      expect(hexToBytes('a'), Uint8List.fromList([0x0a]), reason: '奇数长度补零');
    });
  });
}
