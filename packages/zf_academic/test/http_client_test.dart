import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:test/test.dart';
import 'package:zf_academic/zf_academic_io.dart';

const _origin = 'https://jw.example.edu.cn';
const _root = '$_origin/jwglxt';

/// 按脚本回放的假传输：不发任何套接字，专门测重定向/白名单/重试逻辑。
class FakeTransport {
  final List<RawHttpResponse> script;
  final List<RawHttpRequest> seen = <RawHttpRequest>[];
  int _index = 0;

  /// 前 N 次调用抛网络错误（模拟连接中断）。
  int failuresBeforeSuccess = 0;

  FakeTransport(this.script);

  Future<RawHttpResponse> call(RawHttpRequest request) async {
    seen.add(request);
    if (failuresBeforeSuccess > 0) {
      failuresBeforeSuccess -= 1;
      throw Exception('connection reset');
    }
    final response = script[_index.clamp(0, script.length - 1)];
    _index += 1;
    return response;
  }
}

RawHttpResponse _response(
  int status, {
  String body = '',
  String? location,
  List<String> setCookie = const <String>[],
  String contentType = 'text/html; charset=utf-8',
  String url = '$_root/xtgl/login_slogin.html',
}) {
  return RawHttpResponse(
    status: status,
    url: url,
    bytes: Uint8List.fromList(utf8.encode(body)),
    headers: <String, List<String>>{
      'content-type': <String>[contentType],
      if (location != null) 'location': <String>[location],
      if (setCookie.isNotEmpty) 'set-cookie': setCookie,
    },
  );
}

AcademicHttpClient _client(
  FakeTransport fake, {
  CookieStore? cookies,
  SchoolProtocol protocol = SchoolProtocol.https,
  List<String> allowedHosts = const <String>['jw.example.edu.cn'],
  int? maxBodyBytes,
  void Function(RequestLog info)? onRequest,
}) {
  return AcademicHttpClient(AcademicHttpOptions(
    cookies: cookies ?? CookieStore(baseUrl: _root),
    allowedHosts: allowedHosts,
    protocol: protocol,
    transport: fake.call,
    maxBodyBytes: maxBodyBytes,
    onRequest: onRequest,
  ));
}

void main() {
  group('Cookie 与会话', () {
    test('GET 发送 Cookie 并收集 Set-Cookie', () async {
      final cookies = CookieStore(baseUrl: _root);
      final fake = FakeTransport(<RawHttpResponse>[
        _response(200,
            setCookie: const <String>['JSESSIONID=abc; Path=/'], body: 'ok'),
        _response(200, body: 'again'),
      ]);
      final client = _client(fake, cookies: cookies);

      final first = await client.get('$_root/xtgl/index_initMenu.html');
      expect(first.body, 'ok');
      expect(cookies.cookieHeaderFor(Uri.parse(_root)), 'JSESSIONID=abc');

      await client.get('$_root/xtgl/index_initMenu.html');
      expect(fake.seen[1].headers['Cookie'], 'JSESSIONID=abc');
    });

    test('多条 Set-Cookie 逐条收集（逗号不被拆开）', () async {
      final cookies = CookieStore(baseUrl: _root);
      final fake = FakeTransport(<RawHttpResponse>[
        _response(
          200,
          setCookie: const <String>[
            'a=1; Path=/; Expires=Wed, 21 Oct 2099 07:28:00 GMT',
            'b=2; Path=/',
          ],
        ),
      ]);
      final client = _client(fake, cookies: cookies);
      await client.get('$_root/xtgl/index_initMenu.html');
      expect(cookies.cookieHeaderFor(Uri.parse(_root)), 'a=1; b=2');
    });
  });

  group('表单提交', () {
    test('POST 显式声明 Content-Type 并保真编码表单体', () async {
      final fake = FakeTransport(<RawHttpResponse>[_response(200, body: 'ok')]);
      final client = _client(fake);

      await client.postForm('$_root/xtgl/login_slogin.html', <String, String>{
        'yhm': '2407720102',
        'mm': 'CIPHER',
        'csrftoken': 'uuid-1,uuid2',
      });

      final request = fake.seen.single;
      expect(request.method, 'POST');
      expect(request.headers['Content-Type'],
          'application/x-www-form-urlencoded; charset=utf-8');
      expect(request.body, 'yhm=2407720102&mm=CIPHER&csrftoken=uuid-1%2Cuuid2');
    });

    test('表单值里的空格编码为 +（与浏览器 URLSearchParams 一致）', () async {
      final fake = FakeTransport(<RawHttpResponse>[_response(200)]);
      final client = _client(fake);
      await client.postForm('$_root/x', <String, String>{'kcmc': '高等 数学'});
      expect(
          fake.seen.single.body, 'kcmc=%E9%AB%98%E7%AD%89+%E6%95%B0%E5%AD%A6');
    });

    test('重复键表单：登录页两个 name=mm 都能提交', () async {
      final fake = FakeTransport(<RawHttpResponse>[_response(200)]);
      final client = _client(fake);
      await client
          .postPairs('$_root/xtgl/login_slogin.html', <(String, String)>[
        ('csrftoken', 't'),
        ('mm', 'CIPHER'),
        ('mm', 'CIPHER'),
      ]);
      expect(fake.seen.single.body, 'csrftoken=t&mm=CIPHER&mm=CIPHER');
    });

    test('请求头：同源 POST 带 Origin，ajax 带 X-Requested-With，referer 透传', () async {
      final fake = FakeTransport(<RawHttpResponse>[_response(200)]);
      final client = _client(fake);
      await client.postForm(
        '$_root/xtgl/login_slogin.html',
        <String, String>{'a': '1'},
        const HttpRequestOptions(
          referer: '$_root/xtgl/login_slogin.html?time=1',
          ajax: true,
        ),
      );
      final headers = fake.seen.single.headers;
      expect(headers['Origin'], _origin);
      expect(headers['Referer'], '$_root/xtgl/login_slogin.html?time=1');
      expect(headers['X-Requested-With'], 'XMLHttpRequest');
      expect(headers['Accept'], contains('text/html'));
      expect(headers['User-Agent'], contains('Chrome'));
    });
  });

  group('重定向', () {
    test('302 自动跟随；POST 的 302 转为 GET 且不再重放表单', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302, location: '/jwglxt/xtgl/index_initMenu.html'),
        _response(200, body: 'menu'),
      ]);
      final client = _client(fake);

      final result = await client.get('$_root/xtgl/login_slogin.html');
      expect(result.body, 'menu');
      expect(fake.seen.length, 2);
      expect(fake.seen[1].method, 'GET');
      expect(fake.seen[1].body, isNull);
    });

    test('POST 302 也转为 GET（学校登录失败的典型路径）', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302, location: '/jwglxt/xtgl/login_slogin.html'),
        _response(200, body: 'back'),
      ]);
      final client = _client(fake);
      await client.postForm(
          '$_root/xtgl/login_slogin.html', <String, String>{'yhm': 'u'});
      expect(fake.seen[1].method, 'GET');
      expect(fake.seen[1].body, isNull);
    });

    test('POST 307/308 报 PAGE_CHANGED（意味着需要重新登录）', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(307, location: '/jwglxt/xtgl/login_slogin.html'),
      ]);
      final client = _client(fake);
      await expectLater(
        client.postForm(
            '$_root/xtgl/login_slogin.html', <String, String>{'a': '1'}),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.pageChanged)),
      );
    });

    test('写请求被重定向报 RESULT_UNKNOWN，绝不跨重定向重放', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302, location: '/jwglxt/xsxk/xsxk_cxXsxkList.html'),
      ]);
      final client = _client(fake);
      await expectLater(
        client.postForm('$_root/xsxk/xsxk_xsxkList.html',
            <String, String>{'a': '1'}, const HttpRequestOptions(write: true)),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.resultUnknown)),
      );
      expect(fake.seen.length, 1, reason: '写请求不得重放');
    });

    test('followRedirects:false 时把 302 原样交还给调用方（CAS 探测用）', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302,
            location: 'https://cas.example.edu.cn/cas/login?service=x'),
      ]);
      final client = _client(fake);
      final result = await client.get(
        '$_root/sso/zfiotlogin',
        const HttpRequestOptions(
            followRedirects: false, purpose: RequestPurpose.auth),
      );
      expect(result.status, 302);
      expect(result.headers['location']!.single,
          contains('cas.example.edu.cn/cas/login'));
    });

    test('跳到未声明主机报 UNTRUSTED_URL', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302, location: 'https://evil.test/steal?cookie=1'),
      ]);
      final client = _client(fake);
      await expectLater(
        client.get('$_root/xtgl/login_slogin.html'),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.untrustedUrl)),
      );
    });

    test('跳到统一认证域按会话失效处理，而不是"不受信任"', () async {
      // 会话过期时学校会把请求 302 到 CAS 域：这是"该重新登录了"，
      // 不是可疑跳转。报 UNTRUSTED_URL 会让刷新直接失败、也不触发自动重登。
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302,
            location:
                'https://cas.example.edu.cn/cas/login?service=https%3A%2F%2Fjw.example.edu.cn%2Fjwglxt'),
      ]);
      final client = _client(fake);
      await expectLater(
        client.get('$_root/kbcx/xskbcx_cxXsKb.html'),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.sessionExpired)),
      );
    });

    test('跳到别的主机但带 service= 回跳参数，同样按会话失效处理', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302,
            location:
                'https://auth.example.edu.cn/login?service=https%3A%2F%2Fjw.example.edu.cn'),
      ]);
      final client = _client(fake);
      await expectLater(
        client.get('$_root/kbcx/xskbcx_cxXsKb.html'),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.sessionExpired)),
      );
    });

    test('同主机 http 降级跳转升级回 https（实测青岛科技大学）', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302,
            location: 'http://jw.example.edu.cn/jwglxt/xtgl/login_slogin.html'),
        _response(200, body: 'upgraded'),
      ]);
      final client = _client(fake);
      final result = await client.get('$_root/xtgl/login_slogin.html');
      expect(result.body, 'upgraded');
      expect(fake.seen[1].url.toString(), '$_root/xtgl/login_slogin.html');
    });

    test('非标准端口的 http 跳转一律拒绝（升级会连不上）', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302, location: 'http://jw.example.edu.cn:8080/jwglxt/x'),
      ]);
      final client = _client(fake);
      await expectLater(
        client.get('$_root/xtgl/login_slogin.html'),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.untrustedUrl)),
      );
    });

    test('运行时 allowHost 后可以跟随到 CAS 域', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        _response(302,
            location: 'https://cas.example.edu.cn/cas/login?service=x'),
        _response(200, body: 'cas page'),
      ]);
      final client = _client(fake);
      client.allowHost('cas.example.edu.cn');
      final result = await client.get('$_root/sso/zfiotlogin');
      expect(result.body, 'cas page');
      expect(fake.seen[1].url.host, 'cas.example.edu.cn');
    });
  });

  group('后端崩溃的识别', () {
    test('网关的 502 页面（HTTP 200）→ SERVER_ERROR，不是 PAGE_CHANGED', () {
      const body = '<html><head><title>502 Bad Gateway</title></head>'
          '<body><center>nginx</center></body></html>';
      expect(looksLikeServerError(body), isTrue);
      expect(
        () => listRows(body, const <String>['kbList']),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.serverError)),
      );
    });

    test('运维的"系统维护"页（HTTP 200）→ SERVER_ERROR', () {
      const body = '<html><body><h1>系统维护中</h1><p>预计 20:00 恢复</p></body></html>';
      expect(
        () => listRows(body, const <String>['kbList']),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.serverError)),
      );
    });

    test('真的改版（JSON 结构变了，但页面本身是正常的）→ 仍是 PAGE_CHANGED', () {
      expect(looksLikeServerError('{"code":"0","data":{"unexpected":1}}'),
          isFalse);
      expect(
        () => listRows(
            '<html><body>没有权限看这个页面</body></html>', const <String>['kbList']),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.pageChanged)),
      );
    });

    test('请求记录里，200 的错误页不会被打成"正常"', () async {
      const body =
          '<html><head><title>500 Internal Server Error</title></head></html>';
      final logs = <RequestLog>[];
      final fake = FakeTransport(<RawHttpResponse>[_response(200, body: body)]);
      final client = _client(fake, onRequest: logs.add);
      await client.get('$_root/kbcx/xskbcx_cxXsKb.html');

      expect(logs.single.status, 200);
      expect(logs.single.issue, '返回错误页', reason: '状态码正常也要标出正文是错误页');
    });

    test('请求记录里，正常页面不带 issue', () async {
      final logs = <RequestLog>[];
      final fake = FakeTransport(<RawHttpResponse>[
        _response(200,
            body: '{"code":"0","kbList":[]}',
            contentType: 'application/json; charset=utf-8'),
      ]);
      final client = _client(fake, onRequest: logs.add);
      await client.get('$_root/kbcx/xskbcx_cxXsKb.html');
      expect(logs.single.issue, isNull);
    });
  });

  group('状态码映射与重试', () {
    test('401/403 → SESSION_EXPIRED', () async {
      final fake = FakeTransport(<RawHttpResponse>[_response(401)]);
      final client = _client(fake);
      await expectLater(
        client.get('$_root/kbcx/xskbcx_cxXsKb.html'),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.sessionExpired)),
      );
    });

    test('读请求 5xx → SERVER_ERROR（与"网络断了"分开）', () async {
      final fake = FakeTransport(<RawHttpResponse>[_response(503)]);
      final client = _client(fake);
      await expectLater(
        client.get('$_root/kbcx/xskbcx_cxXsKb.html'),
        throwsA(
          isA<AcademicError>()
              .having((error) => error.code, 'code', ErrorCode.serverError)
              .having((error) => error.httpStatus, 'httpStatus', 503),
        ),
      );
    });

    test('429 → SERVER_ERROR（限流也属于服务端拒绝服务）', () async {
      final fake = FakeTransport(<RawHttpResponse>[_response(429)]);
      final client = _client(fake);
      await expectLater(
        client.get('$_root/kbcx/xskbcx_cxXsKb.html'),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.serverError)),
      );
    });

    test('读请求网络中断自动重试一次后成功', () async {
      final fake = FakeTransport(<RawHttpResponse>[_response(200, body: 'ok')]);
      fake.failuresBeforeSuccess = 1;
      final client = _client(fake);
      final result = await client.get('$_root/xtgl/index_initMenu.html');
      expect(result.body, 'ok');
      expect(fake.seen.length, 2);
    });

    test('写请求网络中断不重试，报 RESULT_UNKNOWN', () async {
      final fake = FakeTransport(<RawHttpResponse>[_response(200)]);
      fake.failuresBeforeSuccess = 1;
      final client = _client(fake);
      await expectLater(
        client.postForm('$_root/xsxk/xsxk_xsxkList.html',
            <String, String>{'a': '1'}, const HttpRequestOptions(write: true)),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.resultUnknown)),
      );
      expect(fake.seen.length, 1);
    });

    test('响应体超限报 PAGE_CHANGED', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        RawHttpResponse(
          status: 200,
          url: '$_root/x',
          bytes: Uint8List(64),
          headers: const <String, List<String>>{
            'content-type': <String>['text/html'],
          },
        ),
      ]);
      final client = _client(fake, maxBodyBytes: 16);
      await expectLater(
        client.get('$_root/x'),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.pageChanged)),
      );
    });
  });

  group('字符集与图片', () {
    test('latin1 页面按声明解码，并记住页面字符集', () async {
      final latin1 = Encoding.getByName('latin1')!;
      final fake = FakeTransport(<RawHttpResponse>[
        RawHttpResponse(
          status: 200,
          url: '$_root/x',
          bytes: Uint8List.fromList(latin1.encode('caf\u00e9')),
          headers: const <String, List<String>>{
            'content-type': <String>['text/html; charset=iso-8859-1'],
          },
        ),
      ]);
      final client = _client(fake);
      final result = await client.get('$_root/x');
      expect(result.body, 'café');
      expect(client.charset, 'iso-8859-1');
    });

    test('GBK 等 Dart 原生不支持的字符集按 utf-8 容错兜底，不抛异常', () async {
      final fake = FakeTransport(<RawHttpResponse>[
        RawHttpResponse(
          status: 200,
          url: '$_root/x',
          bytes: Uint8List.fromList(utf8.encode('教学管理信息服务平台')),
          headers: const <String, List<String>>{
            'content-type': <String>['text/html; charset=gbk'],
          },
        ),
      ]);
      final client = _client(fake);
      final result = await client.get('$_root/x');
      expect(result.body, '教学管理信息服务平台');
    });

    test('getImage：PNG 魔数通过，登录页内容报 PAGE_CHANGED', () async {
      final png = Uint8List.fromList(<int>[
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      ]);
      final fake = FakeTransport(<RawHttpResponse>[
        RawHttpResponse(
          status: 200,
          url: '$_root/kaptcha',
          bytes: png,
          headers: const <String, List<String>>{
            'content-type': <String>['image/png'],
          },
        ),
      ]);
      final client = _client(fake);
      final image = await client.getImage('$_root/kaptcha');
      expect(image.mimeType, 'image/png');

      final loginPage = FakeTransport(<RawHttpResponse>[
        _response(200, body: '<html><title>用户登录</title></html>'),
      ]);
      final client2 = _client(loginPage);
      await expectLater(
        client2.getImage('$_root/kaptcha'),
        throwsA(isA<AcademicError>()
            .having((error) => error.code, 'code', ErrorCode.pageChanged)),
      );
    });

    test('sniffMimeType 覆盖常见图片格式', () {
      expect(
          sniffMimeType(Uint8List.fromList(
              <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])),
          'image/png');
      expect(
          sniffMimeType(
              Uint8List.fromList(<int>[0x47, 0x49, 0x46, 0x38, 0x39, 0x61])),
          'image/gif');
      expect(sniffMimeType(Uint8List.fromList(<int>[0xff, 0xd8, 0xff, 0xe0])),
          'image/jpeg');
      expect(sniffMimeType(Uint8List.fromList(<int>[0x42, 0x4d, 0x00])),
          'image/bmp');
      expect(sniffMimeType(Uint8List.fromList(utf8.encode('<html>'))),
          'application/octet-stream');
    });
  });

  group('dart:io 真实传输', () {
    test('套接字下 Set-Cookie 收集、Cookie 回发、表单体保真、重定向跟随', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      final received = <String>[];
      server.listen((HttpRequest request) async {
        final body = await utf8.decodeStream(request);
        final cookie = request.cookies.isEmpty
            ? '-'
            : request.cookies
                .map((item) => '${item.name}=${item.value}')
                .join('; ');
        received.add(
            '${request.method} ${request.uri.path} cookie=[$cookie] body=[$body]');
        request.response.headers
            .add('set-cookie', 'JSESSIONID=socket-1; Path=/');
        if (request.uri.path == '/jwglxt/redir') {
          request.response.statusCode = 302;
          request.response.headers
              .set(HttpHeaders.locationHeader, '/jwglxt/echo');
        }
        request.response.write('ok:${request.uri.path}');
        await request.response.close();
      });
      addTearDown(() => server.close(force: true));

      final base = 'http://127.0.0.1:${server.port}/jwglxt';
      final cookies = CookieStore(baseUrl: base);
      final transport = DartIoTransport();
      final client = AcademicHttpClient(AcademicHttpOptions(
        cookies: cookies,
        allowedHosts: <String>['127.0.0.1:${server.port}'],
        protocol: SchoolProtocol.http,
        transport: transport.call,
        onDispose: transport.close,
      ));

      try {
        // 第一次请求：服务端种下 JSESSIONID，此时请求头里还没有 Cookie。
        final echo = await client.get('$base/echo');
        expect(echo.body, 'ok:/jwglxt/echo');
        expect(received.last, contains('cookie=[-]'));

        // 第二次请求：CookieStore 把 JSESSIONID 带上。
        await client.get('$base/echo');
        expect(received.last, contains('cookie=[JSESSIONID=socket-1]'));

        final form = await client.postForm('$base/form', <String, String>{
          'yhm': '2407720102',
          'mm': 'CIPHER',
        });
        expect(form.body, 'ok:/jwglxt/form');
        expect(received.last,
            'POST /jwglxt/form cookie=[JSESSIONID=socket-1] body=[yhm=2407720102&mm=CIPHER]');

        final redirected = await client.get('$base/redir');
        expect(redirected.body, 'ok:/jwglxt/echo');
        expect(received.last, contains('cookie=[JSESSIONID=socket-1]'));
      } finally {
        client.close();
      }
    });
  });
}
