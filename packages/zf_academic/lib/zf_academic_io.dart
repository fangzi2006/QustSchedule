/// 依赖 dart:io 的入口（VM / Flutter 移动与桌面可用，Web 不可用）。
///
/// ```dart
/// import 'package:zf_academic/zf_academic_io.dart';
///
/// final storage = FileCookieStorage('./zf-session.json');
/// final snapshot = await storage.load();          // 启动时恢复会话
/// await storage.save(store.export());             // 登录成功后保存
///
/// // 带 dart:io 传输层的客户端
/// final client = vmZhengfangClient(
///   const ZfClientConfig(baseUrl: 'https://jwglxt1.qust.edu.cn/jwglxt'),
/// );
/// final state = await client.login(Credentials('2407720102', '…'));
/// await client.close();
/// ```
library zf_academic_io;

import 'src/dart_io_transport.dart';
import 'src/types.dart';
import 'src/zhengfang_client.dart';

export 'src/cookie_storage.dart' show FileCookieStorage;
export 'src/dart_io_transport.dart' show DartIoTransport;
export 'zf_academic.dart';

/// 用 dart:io 传输层构造新正方客户端。用完调用 `client.close()` 释放连接池。
ZhengfangClient vmZhengfangClient(ZfClientConfig config,
    {DartIoTransport? transport}) {
  final ioTransport = transport ?? DartIoTransport();
  return ZhengfangClient(ZfClientConfig(
    baseUrl: config.baseUrl,
    address: config.address,
    allowedHosts: config.allowedHosts,
    pageCharset: config.pageCharset,
    userAgent: config.userAgent,
    casLoginUrl: config.casLoginUrl,
    casServiceUrl: config.casServiceUrl,
    endpoints: config.endpoints,
    cookies: config.cookies,
    requestTimeoutMs: config.requestTimeoutMs,
    maxRedirects: config.maxRedirects,
    maxBodyBytes: config.maxBodyBytes,
    paceHosts: config.paceHosts,
    onRequest: config.onRequest,
    onDebug: config.onDebug,
    transport: ioTransport.call,
    onDispose: ioTransport.close,
  ));
}
