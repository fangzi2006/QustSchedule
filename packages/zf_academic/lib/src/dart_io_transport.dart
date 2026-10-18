/// dart:io 传输层实现（VM / Flutter 移动与桌面可用，Web 不可用）。
///
/// 从 `zf_academic_io.dart` 入口导出；核心包（`zf_academic.dart`）只依赖
/// `ZfHttpTransport` 函数类型，测试里可注入假传输。
///
/// 说明：
///  - `followRedirects = false`：重定向由 `AcademicHttpClient` 手动跟随并逐跳做白名单校验；
///  - 每个实例持有自己的 `HttpClient`（连接池复用），用完后调用 `close()`；
///  - 响应体在流式读取时限流（默认 5 MB），超限抛 PAGE_CHANGED，避免无限缓冲；
///  - dart:io 不会自动管理 Cookie（`HttpClient` 没有 cookieJar），Cookie 头完全由
///    调用方的 `CookieStore` 负责，不存在双边种 Cookie 的问题。
library;

import 'dart:io';
import 'dart:typed_data';

import 'errors.dart';
import 'types.dart' show RawHttpRequest, RawHttpResponse;

const int _defaultMaxBodyBytes = 5 * 1024 * 1024;

class DartIoTransport {
  final HttpClient client;
  final int maxBodyBytes;

  DartIoTransport({
    HttpClient? client,
    int? connectionTimeoutMs,
    this.maxBodyBytes = _defaultMaxBodyBytes,
  }) : client = client ??
            (HttpClient()
              ..connectionTimeout =
                  Duration(milliseconds: connectionTimeoutMs ?? 30000));

  Future<RawHttpResponse> call(RawHttpRequest request) async {
    final httpRequest = await client.openUrl(request.method, request.url);
    httpRequest.followRedirects = false;
    request.headers.forEach(httpRequest.headers.set);
    if (request.body != null) {
      // 表单体是百分号编码后的 ASCII，直接按字节写入。
      httpRequest.add(request.body!.codeUnits);
    }

    final response = await httpRequest.close();
    final headers = <String, List<String>>{};
    response.headers.forEach((name, values) {
      headers[name.toLowerCase()] = List<String>.of(values);
    });

    final builder = BytesBuilder(copy: false);
    var total = 0;
    await for (final chunk in response) {
      total += chunk.length;
      if (total > maxBodyBytes) {
        await response.drain<void>().catchError((Object _) {});
        throw AcademicError(ErrorCode.pageChanged, '教务响应过大，已中止');
      }
      builder.add(chunk);
    }

    return RawHttpResponse(
      status: response.statusCode,
      url: request.url.toString(),
      bytes: builder.takeBytes(),
      headers: headers,
    );
  }

  void close() {
    client.close(force: true);
  }
}
