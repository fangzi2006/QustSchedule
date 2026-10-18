/// 密码加密。
///
/// 新正方有两种密码提交方式：
///
///  1. **表单登录**：`xtgl/login_getPublicKey.html` 返回 base64 的 modulus / exponent
///     → RSA/ECB/PKCS1Padding（PKCS#1 v1.5 随机填充）→ base64。
///  2. **统一认证（CAS）**：`v2/getPubKey` 返回 hex 公钥 → 无填充裸 RSA + 自定义分块。
///
/// pointycastle 可以直接用 BigInt 构造 `RSAPublicKey(modulus, exponent)`，
/// 不必手写 DER 拼 SPKI；两条链路的数学结果由黄金向量测试锁定。
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

import 'errors.dart';

// ---------------------------------------------------------------------------
// 编码助手
// ---------------------------------------------------------------------------

/// base64 解码。学校公钥格式非法时抛 PAGE_CHANGED，而不是带着垃圾数据继续走。
Uint8List bytesFromBase64(String value) {
  try {
    return base64.decode(value);
  } on FormatException catch (error) {
    throw AcademicError(ErrorCode.pageChanged, '学校公钥格式无效', cause: error);
  }
}

String base64FromBytes(Uint8List bytes) => base64.encode(bytes);

/// hex 解码。奇数长度自动前面补零；非 hex 字符抛 PAGE_CHANGED。
Uint8List hexToBytes(String value) {
  if (!RegExp(r'^[0-9a-fA-F]+$').hasMatch(value)) {
    throw AcademicError(ErrorCode.pageChanged, '学校公钥格式无效');
  }
  final padded = value.length.isOdd ? '0$value' : value;
  final out = Uint8List(padded.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(padded.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

String bytesToHex(Uint8List bytes) =>
    bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();

/// 大端字节 → BigInt（前导零不影响取值）。
BigInt bigIntFromBytes(Uint8List bytes) {
  var result = BigInt.zero;
  for (final byte in bytes) {
    result = (result << 8) | BigInt.from(byte);
  }
  return result;
}

/// BigInt → 最小大端字节表示。
Uint8List bigIntToBytes(BigInt value) {
  if (value == BigInt.zero) return Uint8List(1);
  final bytes = <int>[];
  var rest = value;
  while (rest > BigInt.zero) {
    bytes.insert(0, (rest & BigInt.from(0xff)).toInt());
    rest >>= 8;
  }
  return Uint8List.fromList(bytes);
}

// ---------------------------------------------------------------------------
// RSA
// ---------------------------------------------------------------------------

/// 学校表单登录公钥：base64 的 modulus / exponent。
RSAPublicKey rsaPublicKeyFromBase64(String modulus, String exponent) =>
    RSAPublicKey(
      bigIntFromBytes(bytesFromBase64(modulus)),
      bigIntFromBytes(bytesFromBase64(exponent)),
    );

/// 正方 CAS 公钥：hex 的 modulus / exponent。
RSAPublicKey rsaPublicKeyFromHex(String modulusHex, String exponentHex) =>
    RSAPublicKey(
      bigIntFromBytes(hexToBytes(modulusHex)),
      bigIntFromBytes(hexToBytes(exponentHex)),
    );

/// RSA/ECB/PKCS1Padding 加密（PKCS#1 v1.5 随机填充），输出 base64。
/// 对应 Java 的 `Cipher.getInstance("RSA/ECB/PKCS1Padding")`。
String rsaEncryptPkcs1(RSAPublicKey publicKey, String text) {
  final cipher = PKCS1Encoding(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  return base64.encode(cipher.process(Uint8List.fromList(utf8.encode(text))));
}

/// 同 [rsaEncryptPkcs1]，输入输出都是字节。
Uint8List rsaEncryptPkcs1Bytes(RSAPublicKey publicKey, Uint8List data) {
  final cipher = PKCS1Encoding(RSAEngine())
    ..init(true, PublicKeyParameter<RSAPublicKey>(publicKey));
  return cipher.process(data);
}

/// 校验 / 排障用：用私钥解回 PKCS1 密文。
String rsaDecryptPkcs1(RSAPrivateKey privateKey, String cipherBase64) {
  final cipher = PKCS1Encoding(RSAEngine())
    ..init(false, PrivateKeyParameter<RSAPrivateKey>(privateKey));
  return utf8.decode(cipher.process(bytesFromBase64(cipherBase64)));
}

/// 新正方表单登录：学校直接给 base64 的 modulus / exponent。
String zfFormEncryptPassword(
        String modulus, String exponent, String password) =>
    rsaEncryptPkcs1(rsaPublicKeyFromBase64(modulus, exponent), password);

/// 正方定制 CAS 的密码加密（无填充裸 RSA + 自定义分块）。
///
/// 规格（与 `ZhengfangRsaCrypto.encryptPassword` 一致）：
/// 反转 UTF-16 码元序列 → 按 chunk 分块 → 块内每两个码元组成小端 16 位数字、
/// 按 2^16 进位拼成大整数 → m^e mod n → 每块输出 16 进制，块间以空格连接。
/// chunk = 2 ×（模数的 16 位数字个数 - 1），与密钥长度联动，必须动态计算。
String zfCasEncryptPassword(
    String password, String modulusHex, String exponentHex) {
  if (!RegExp(r'^[0-9a-fA-F]{128,1024}$').hasMatch(modulusHex) ||
      !RegExp(r'^[0-9a-fA-F]{1,8}$').hasMatch(exponentHex) ||
      password.length > 512) {
    throw AcademicError(ErrorCode.pageChanged, '统一认证公钥或密码长度无效');
  }
  final n = bigIntFromBytes(hexToBytes(modulusHex));
  final exponent = bigIntFromBytes(hexToBytes(exponentHex));

  // 块长（码元数）= 2 × (ceil(模数位数 / 16) - 1)。512 位模数 → 62。
  final chunk = 2 * ((n.bitLength + 15) ~/ 16 - 1);
  if (chunk <= 0) throw AcademicError(ErrorCode.pageChanged, '统一认证模数过小');

  // UTF-16 码元序列反转（与主分支 Kotlin `toCharArray().reversed()` 同语义；
  // TS 参考实现对 BMP 密码完全等价）。末尾补 0 到块长的整数倍。
  final units = password.codeUnits.reversed.toList();
  while (units.length % chunk != 0) {
    units.add(0);
  }

  final blocks = <String>[];
  for (var i = 0; i < units.length; i += chunk) {
    var value = BigInt.zero;
    var multiplier = BigInt.one;
    for (var j = 0; j < chunk ~/ 2; j++) {
      final word = units[i + 2 * j] + (units[i + 2 * j + 1] << 8);
      value += BigInt.from(word) * multiplier;
      multiplier <<= 16;
    }
    blocks.add(value.modPow(exponent, n).toRadixString(16));
  }
  return blocks.join(' ');
}
