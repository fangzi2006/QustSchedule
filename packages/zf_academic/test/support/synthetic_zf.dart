/// 合成新正方服务端（测试支持）。
///
/// 不是"随便返回点 JSON"的假服务：它会
///  - 用真实 RSA 私钥解出登录表单里的 `mm` 字段，核对密码是否被正确加密；
///  - 在受保护端点上强制校验 JSESSIONID，因此"登录后有没有把 Cookie 存下来并带上"会被真实验证到；
///  - 记录每一次请求的方法、路径、查询、表单原文与 Cookie，供用例断言请求形状。
///
/// 所有密钥、账号、课程都是临时合成数据。对应 TS 版 test/support/synthetic-zf.ts。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';
import 'package:zf_academic/zf_academic.dart';

class RecordedRequest {
  final String method;
  final String path;
  final Map<String, String> query;
  final Map<String, String> form;
  final String rawBody;
  final String cookie;
  final String userAgent;
  final String referer;

  const RecordedRequest({
    required this.method,
    required this.path,
    required this.query,
    required this.form,
    required this.rawBody,
    required this.cookie,
    required this.userAgent,
    required this.referer,
  });
}

class SyntheticZfOptions {
  final String basePath;
  final String username;
  final String password;
  final String studentId;
  final String studentName;

  /// 是否开启 `mmsfjm=1` 的 RSA 密码加密。
  final bool encrypt;

  /// 登录页是否带验证码；`code` 是唯一正确的验证码。
  final String? captchaCode;

  /// 让登录按指定方式失败一次，用于验证错误分类。
  final String? reject;

  /// 课表接口返回体；默认一条与 plugin-sdk 样本同形的 kbList。
  final String? scheduleBody;

  /// 让课表接口返回这段裸文本（用于测试"没有访问权限"分支）。
  final bool scheduleDenied;

  /// 学期下拉框 HTML。
  final String? scheduleIndexBody;

  /// 完全覆盖登录页 HTML（用于注入异常结构，如互相矛盾的 mmsfjm）。
  final String? loginPageOverride;

  /// 学生信息页的 HTTP 状态码（用于测试"无法确认"分支）。
  final int identityStatus;

  /// 让 `/sso/zfiotlogin` 模拟跳转到 CAS 登录页（测试 CAS 探测）。
  final bool casRedirect;

  const SyntheticZfOptions({
    this.basePath = '/jwglxt',
    this.username = '2026000001',
    this.password = 'Test1234',
    this.studentId = '2026000001',
    this.studentName = '合成学生',
    this.encrypt = true,
    this.captchaCode,
    this.reject,
    this.scheduleBody,
    this.scheduleDenied = false,
    this.scheduleIndexBody,
    this.loginPageOverride,
    this.identityStatus = 200,
    this.casRedirect = false,
  });
}

String defaultScheduleBody() {
  return jsonEncode(<String, dynamic>{
    'kbList': <Map<String, dynamic>>[
      <String, dynamic>{
        'kcmc': '离散数学',
        'kch_id': 'C1',
        'kch': 'C1',
        'xm': '合成教师',
        'cdmc': '教室A',
        'xqmc': '东校区',
        'xqj': '1',
        'jcs': '1-2',
        'zcd': '1-4周(单)',
        'jxbmc': '教学班1',
        'xf': '3',
      },
      <String, dynamic>{
        'kcmc': '大学英语',
        'kch_id': 'C2',
        'xm': '合成教师二',
        'cdmc': '教室B',
        'xqj': '3',
        'jcor': '5-6',
        'zcd': '2-8周',
        'kxh': '02',
      },
    ],
  });
}

String defaultScheduleIndexBody() {
  return '<select name="xnm"><option value="2026" selected>2026-2027</option></select>'
      '<select name="xqm"><option value="3" selected>1</option><option value="12">2</option></select>';
}

({RSAPublicKey publicKey, RSAPrivateKey privateKey}) _generateKeyPair(
    int bitLength) {
  final random = FortunaRandom();
  random.seed(KeyParameter(
    Uint8List.fromList(
        List<int>.generate(32, (_) => Random.secure().nextInt(256))),
  ));
  final generator = RSAKeyGenerator()
    ..init(ParametersWithRandom(
      RSAKeyGeneratorParameters(BigInt.from(65537), bitLength, 64),
      random,
    ));
  final pair = generator.generateKeyPair();
  return (
    publicKey: pair.publicKey as RSAPublicKey,
    privateKey: pair.privateKey as RSAPrivateKey,
  );
}

class SyntheticZfServer {
  final List<RecordedRequest> requests = <RecordedRequest>[];
  final String username;
  final String password;
  final String studentId;
  final String studentName;
  late final String modulusBase64;
  late final String exponentBase64;
  late final RSAPrivateKey privateKey;

  late final HttpServer _server;
  final SyntheticZfOptions _options;
  final String _basePath;
  int _port = 0;
  bool _rejected = false;

  SyntheticZfServer([SyntheticZfOptions options = const SyntheticZfOptions()])
      : _options = options,
        _basePath = options.basePath,
        username = options.username,
        password = options.password,
        studentId = options.studentId,
        studentName = options.studentName {
    final keys = _generateKeyPair(1024);
    privateKey = keys.privateKey;
    modulusBase64 = base64.encode(bigIntToBytes(keys.publicKey.modulus!));
    exponentBase64 = base64.encode(bigIntToBytes(keys.publicKey.exponent!));
  }

  String get origin => 'http://127.0.0.1:$_port';

  String get baseUrl => '$origin$_basePath';

  String get hostWithPort => '127.0.0.1:$_port';

  List<String> paths() => requests.map((item) => item.path).toList();

  Future<void> start() async {
    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    _server.listen(_handle);
    _port = _server.port;
  }

  Future<void> close() async {
    await _server.close(force: true);
  }

  String _loginPageHtml() {
    if (_options.loginPageOverride != null) return _options.loginPageOverride!;
    final captchaImage =
        _options.captchaCode == null ? '' : '<img id="icode" src="/kaptcha">';
    final captchaInput =
        _options.captchaCode == null ? '' : '<input name="yzm">';
    return '<html><head><title>登录</title></head><body>'
        '<form action="$_basePath/xtgl/login_slogin.html" method="post">'
        '<input type="hidden" name="csrftoken" value="fixture-csrf-token">'
        '<input type="hidden" name="mmsfjm" value="${_options.encrypt ? '1' : '0'}">'
        '<input type="hidden" name="language" value="zh_CN">'
        '<input name="yhm">$captchaInput$captchaImage'
        '<input type="password" name="mm">'
        '</form></body></html>';
  }

  String _identityHtml() {
    return '<html><body><input name="xh" value="$studentId">'
        '<span class="media-heading">$studentName</span>'
        '<span>学期理论课表</span><a href="javascript:logout();">退出登录</a></body></html>';
  }

  String _menuHtml() {
    return '<html><body><form id="requestMap"><input type="hidden" id="sessionUserKey" value="'
        '$studentId"></form>'
        '<div class="navbar"><span>学期理论课表</span><span>选课结果</span></div>'
        '<div onclick="clickMenu(\'N253508\',\'/kbcx/xskbcx_cxXsKb.html\',\'理论课表\')"></div>'
        '</body></html>';
  }

  Future<void> _handle(HttpRequest request) async {
    final url = Uri.parse(request.uri.toString());
    final rawBody = await utf8.decodeStream(request);
    final form = Uri.splitQueryString(rawBody, encoding: utf8);
    final record = RecordedRequest(
      method: request.method,
      path: url.path,
      query: url.queryParameters,
      form: form,
      rawBody: rawBody,
      cookie: request.cookies
          .map((item) => '${item.name}=${item.value}')
          .join('; '),
      userAgent: request.headers.value(HttpHeaders.userAgentHeader) ?? '',
      referer: request.headers.value(HttpHeaders.refererHeader) ?? '',
    );
    requests.add(record);

    final relative = url.path.startsWith(_basePath)
        ? url.path.substring(_basePath.length)
        : url.path;
    void send(int status, String contentType, String payload,
        {Map<String, List<String>>? headers}) {
      request.response.statusCode = status;
      request.response.headers.contentType = ContentType.parse(contentType);
      headers?.forEach((key, values) {
        for (final value in values) {
          request.response.headers.add(key, value);
        }
      });
      request.response.write(payload);
      request.response.close();
    }

    void loginPage([int status = 200]) =>
        send(status, 'text/html; charset=utf-8', _loginPageHtml());

    final authed = record.cookie.contains('JSESSIONID=fixture-session');

    // 统一认证入口：默认 404（迫使客户端走表单直登）；casRedirect 时模拟 CAS 跳转。
    if (relative.startsWith('/sso/zfiotlogin')) {
      if (_options.casRedirect) {
        send(302, 'text/plain; charset=utf-8', '',
            headers: <String, List<String>>{
              'location': <String>[
                '$origin/cas/login?service=${Uri.encodeComponent(baseUrl)}',
              ],
            });
        return;
      }
      send(404, 'text/plain; charset=utf-8', '');
      return;
    }

    if (relative == '/cas/login') {
      send(
          200,
          'text/html; charset=utf-8',
          '<html><body><form><input name="username"><input type="password" name="password">'
              '<input name="execution" value="e1"></form></body></html>');
      return;
    }

    if (relative == '/kaptcha') {
      request.response.statusCode = 200;
      request.response.headers.contentType = ContentType('image', 'png');
      // 真 PNG 魔数（不是 ASCII 的 hex 字符串）。
      request.response.add(const <int>[
        0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, //
        0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      ]);
      await request.response.close();
      return;
    }

    if (relative == '/xtgl/login_slogin.html') {
      if (request.method == 'GET') {
        loginPage();
        return;
      }
      // 表单 Content-Type 缺失时服务端解析不到任何参数（真实学校就是这么表现的：
      // 收到空 yhm/mm 后回登录页并提示"用户名或密码不正确"）。这里刻意复现该行为，
      // 防止"fetch 对字符串 body 默认设 text/plain"这个 bug 回归。
      final contentType =
          request.headers.value(HttpHeaders.contentTypeHeader) ?? '';
      if (!contentType.contains('application/x-www-form-urlencoded')) {
        loginPage();
        return;
      }
      if (_options.captchaCode != null && form['yzm'] != _options.captchaCode) {
        send(200, 'text/html; charset=utf-8',
            '${_loginPageHtml()}<div id="showMsg">验证码错误，请重新输入</div>');
        return;
      }
      if (form['csrftoken'] != 'fixture-csrf-token') {
        send(200, 'text/html; charset=utf-8',
            '${_loginPageHtml()}<div>会话已失效</div>');
        return;
      }
      if (_options.reject == 'credentials' && !_rejected) {
        _rejected = true;
        send(200, 'text/html; charset=utf-8',
            '${_loginPageHtml()}<div id="tips">用户名或密码不正确，请重新输入！</div>');
        return;
      }
      if (form['yhm'] != username) {
        send(200, 'text/html; charset=utf-8',
            '${_loginPageHtml()}<div id="tips">用户名或密码不正确</div>');
        return;
      }
      var submitted = form['mm'] ?? '';
      if (form['mmsfjm'] == '1') {
        try {
          final decrypted = rsaDecryptPkcs1(privateKey, submitted);
          submitted = decrypted;
          form['mm_decrypted'] = decrypted;
        } catch (_) {
          send(200, 'text/html; charset=utf-8',
              '${_loginPageHtml()}<div>密码格式错误</div>');
          return;
        }
      }
      if (submitted != password) {
        send(200, 'text/html; charset=utf-8',
            '${_loginPageHtml()}<div id="tips">用户名或密码不正确</div>');
        return;
      }
      send(
        200,
        'text/html; charset=utf-8',
        '<script>window.location.href="xtgl/index_initMenu.html";</script>退出登录',
        headers: <String, List<String>>{
          'set-cookie': <String>[
            'JSESSIONID=fixture-session; Path=/; HttpOnly'
          ],
        },
      );
      return;
    }

    if (relative == '/xtgl/login_getPublicKey.html') {
      send(
          200,
          'application/json; charset=utf-8',
          jsonEncode(<String, String>{
            'modulus': modulusBase64,
            'exponent': exponentBase64,
          }));
      return;
    }

    if (relative == '/xtgl/login_logoutAccount.html') {
      send(200, 'application/json; charset=utf-8', 'null');
      return;
    }

    // 以下端点都要求已登录：不带 Cookie 就回登录页。
    if (!authed) {
      loginPage();
      return;
    }

    if (relative == '/xtgl/index_initMenu.html') {
      send(200, 'text/html; charset=utf-8', _menuHtml());
      return;
    }
    if (relative == '/xtgl/index_cxYhxxIndex.html') {
      send(
          _options.identityStatus, 'text/html; charset=utf-8', _identityHtml());
      return;
    }
    if (relative == '/kbcx/xskbcx_cxXsKb.html') {
      if (_options.scheduleDenied) {
        send(200, 'text/html; charset=utf-8', '"没有访问权限"');
        return;
      }
      if (request.method == 'POST') {
        send(200, 'application/json; charset=utf-8',
            _options.scheduleBody ?? defaultScheduleBody());
        return;
      }
      send(200, 'text/html; charset=utf-8',
          _options.scheduleIndexBody ?? defaultScheduleIndexBody());
      return;
    }
    if (relative == '/cjcx/cjcx_cxDgXscj.html') {
      send(200, 'text/html; charset=utf-8', defaultScheduleIndexBody());
      return;
    }
    send(404, 'text/plain; charset=utf-8', 'not found');
  }
}

Future<T> withServer<T>(
  Future<T> Function(SyntheticZfServer server) run, [
  SyntheticZfOptions options = const SyntheticZfOptions(),
]) async {
  final server = SyntheticZfServer(options);
  await server.start();
  try {
    return await run(server);
  } finally {
    await server.close();
  }
}
