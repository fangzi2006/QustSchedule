/// 教务 HTTP 客户端（核心逻辑，不依赖任何平台 API）。
///
/// 这些细节看着"多余"，但都被真实学校的行为验证过：
///  - 手动跟随重定向（不用自动重定向），每一跳都重新做主机/协议白名单校验；
///  - 写请求遇到重定向一律报 RESULT_UNKNOWN，绝不跨重定向重放 POST；
///  - POST 收到 307/308 报 PAGE_CHANGED，因为那意味着需要重新登录；
///  - 401/403 → SESSION_EXPIRED；读请求 429/5xx → SERVER_ERROR（服务器坏了，
///    与"网络断了"分开）；写请求 5xx → RESULT_UNKNOWN；
///  - 响应体上限 5 MB，超限报 PAGE_CHANGED；
///  - 读请求网络中断自动重试一次，写请求不重试；
///  - 按主机限速，避免短时间高频请求触发学校侧风控。
///
/// 传输层（`ZfHttpTransport`）可注入：默认实现见 `dart_io_transport.dart`
/// （依赖 dart:io，从 `zf_academic_io.dart` 入口导出）；测试里可注入假传输，
/// 把重定向/白名单/重试逻辑做成无套接字的确定性用例。
///
/// Cookie 由外部的 `CookieStore` 持有：本类只负责"读出来发出去、把响应的 Set-Cookie 存回去"。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'cookies.dart';
import 'errors.dart';
import 'respond.dart' show looksLikeServerError;
import 'types.dart';
import 'urls.dart';
import 'util.dart';

const String _defaultAccept =
    'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8';
const String _defaultAcceptLanguage = 'zh-CN,zh;q=0.9';
const String _defaultUa =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36';
const int _defaultMaxBodyBytes = 5 * 1024 * 1024;
const int _defaultMaxRedirects = 12;
const Map<String, int> _defaultPaceHosts = <String, int>{'jw.cqiivc.com': 1200};

/// Content-Type 里的 charset 声明。`\x22` 是双引号（raw string 里不能直接写 `\"`）。
final RegExp _charsetPattern = RegExp(
  r"charset\s*=\s*['\x22]?([A-Za-z0-9_-]+)",
  caseSensitive: false,
);

class HttpRequestOptions {
  /// 表单字段（同名键只保留一个）。需要重复键（登录页两个 `name=mm`）时用 [formPairs]。
  final Map<String, String>? form;
  final List<(String, String)>? formPairs;
  final String? referer;

  /// 写请求：禁止跨重定向重放，且失败时不能盲目重试。
  final bool write;
  final bool ajax;
  final RequestPurpose purpose;

  /// 默认 true。设为 false 时把 3xx 原样返回给调用方——统一认证探测和验票必须看到
  /// 302 的 Location，不能被自动跟随掉（对应原项目的 `followRedirects(false)`）。
  final bool followRedirects;

  const HttpRequestOptions({
    this.form,
    this.formPairs,
    this.referer,
    this.write = false,
    this.ajax = false,
    this.purpose = RequestPurpose.query,
    this.followRedirects = true,
  });
}

class HttpResponse {
  final int status;
  final String url;
  final String body;
  final Map<String, List<String>> headers;
  final Uint8List bytes;

  const HttpResponse({
    required this.status,
    required this.url,
    required this.body,
    required this.headers,
    required this.bytes,
  });
}

class ImageResponse {
  final Uint8List bytes;
  final String mimeType;
  final String url;

  const ImageResponse({
    required this.bytes,
    required this.mimeType,
    required this.url,
  });
}

class AcademicHttpOptions {
  final CookieStore cookies;
  final Iterable<String> allowedHosts;
  final SchoolProtocol protocol;
  final String? pageCharset;
  final String? userAgent;
  final int? maxRedirects;
  final int? maxBodyBytes;
  final int? timeoutMs;
  final Map<String, int>? paceHosts;

  /// 注入传输层（测试用）。为 null 时使用 dart:io 实现（需 `zf_academic_io.dart` 提供）。
  final ZfHttpTransport? transport;
  final void Function(RequestLog info)? onRequest;

  /// 注入传输层的销毁回调（例如 `DartIoTransport.close`），由 [AcademicHttpClient.close] 调用。
  final void Function()? onDispose;

  const AcademicHttpOptions({
    required this.cookies,
    required this.allowedHosts,
    required this.protocol,
    this.pageCharset,
    this.userAgent,
    this.maxRedirects,
    this.maxBodyBytes,
    this.timeoutMs,
    this.paceHosts,
    this.transport,
    this.onRequest,
    this.onDispose,
  });
}

/// 按魔数识别图片类型；不是已知图片格式时返回 `application/octet-stream`。
/// 用于把"学校返回了登录页而不是验证码图片"和真图片区分开。
String sniffMimeType(Uint8List bytes) {
  bool startsWith(List<int> signature) {
    if (bytes.length < signature.length) return false;
    for (var i = 0; i < signature.length; i++) {
      if (bytes[i] != signature[i]) return false;
    }
    return true;
  }

  if (startsWith(const [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) {
    return 'image/png';
  }
  if (startsWith(const [0x47, 0x49, 0x46, 0x38])) return 'image/gif';
  if (startsWith(const [0xff, 0xd8, 0xff])) return 'image/jpeg';
  if (startsWith(const [0x42, 0x4d])) return 'image/bmp';
  if (startsWith(const [0x52, 0x49, 0x46, 0x46]) && bytes.length >= 12) {
    if (String.fromCharCodes(bytes.sublist(8, 12)) == 'WEBP') {
      return 'image/webp';
    }
  }
  return 'application/octet-stream';
}

class AcademicHttpClient {
  final CookieStore _cookies;
  final Set<String> _allowed;
  final SchoolProtocol _protocol;
  final int _maxRedirects;
  final int _maxBodyBytes;
  final int _timeoutMs;
  final Map<String, int> _paceHosts;
  final void Function(RequestLog info)? _onRequest;
  final void Function()? _disposeTransport;
  final Map<String, int> _lastRequestAt = <String, int>{};

  /// 注入的传输层；未注入时 [late _transport] 在首次请求才解析默认实现。
  ZfHttpTransport? _transportOverride;
  late final ZfHttpTransport _transport =
      _transportOverride ?? _requireIoTransport();

  String _userAgent;
  String _pageCharset;

  AcademicHttpClient(AcademicHttpOptions options)
      : _cookies = options.cookies,
        _allowed = <String>{},
        _protocol = options.protocol,
        _maxRedirects = options.maxRedirects ?? _defaultMaxRedirects,
        _maxBodyBytes = options.maxBodyBytes ?? _defaultMaxBodyBytes,
        _timeoutMs = options.timeoutMs ?? 30000,
        _paceHosts = <String, int>{
          ..._defaultPaceHosts,
          ...(options.paceHosts ?? const <String, int>{}),
        },
        _onRequest = options.onRequest,
        _disposeTransport = options.onDispose,
        _userAgent = options.userAgent?.trim().isNotEmpty == true
            ? options.userAgent!.trim()
            : _defaultUa,
        _pageCharset = options.pageCharset ?? 'UTF-8' {
    for (final host in options.allowedHosts) {
      final normalized = normalizeHost(host);
      if (normalized.isNotEmpty) _allowed.add(normalized);
    }
    _transportOverride = options.transport;
  }

  /// dart:io 传输在 `zf_academic_io.dart` 里注入；核心包不依赖 dart:io。
  static ZfHttpTransport _requireIoTransport() {
    throw UnsupportedError(
      'AcademicHttpClient 需要传输层：请从 zf_academic_io.dart 导入 dartIoTransport，'
      '或通过 AcademicHttpOptions.transport 注入。',
    );
  }

  List<String> get allowedHosts => List.unmodifiable(_allowed);

  /// 运行时放行新主机：CAS 统一认证域在发现后加入，与原项目的做法一致。
  void allowHost(String host) {
    final normalized = normalizeHost(host);
    if (normalized.isNotEmpty) _allowed.add(normalized);
  }

  String get charset => _pageCharset;

  String get ua => _userAgent;

  /// 关闭底层传输（例如 dart:io 的连接池）。注入的传输层也应在此释放。
  void close() {
    _disposeTransport?.call();
  }

  void setUserAgent(String value) {
    _userAgent = value.trim().isNotEmpty ? value.trim() : _defaultUa;
  }

  Future<HttpResponse> get(String url,
      [HttpRequestOptions options = const HttpRequestOptions()]) {
    return _request('GET', url, null, options);
  }

  Future<HttpResponse> postForm(
    String url,
    Map<String, String> fields, [
    HttpRequestOptions options = const HttpRequestOptions(),
  ]) {
    return _request(
      'POST',
      url,
      fields.entries.map((entry) => (entry.key, entry.value)).toList(),
      options,
    );
  }

  Future<HttpResponse> postPairs(
    String url,
    List<(String, String)> pairs, [
    HttpRequestOptions options = const HttpRequestOptions(),
  ]) {
    return _request('POST', url, pairs, options);
  }

  /// 取图片并校验魔数。非图片内容按 PAGE_CHANGED 处理，避免把登录页当验证码展示。
  Future<ImageResponse> getImage(String url, {String? referer}) async {
    final response = await get(
      url,
      HttpRequestOptions(referer: referer, purpose: RequestPurpose.auth),
    );
    final mimeType = sniffMimeType(response.bytes);
    if (response.status < 200 ||
        response.status >= 300 ||
        mimeType == 'application/octet-stream') {
      throw AcademicError(
        ErrorCode.pageChanged,
        '学校未返回有效的验证码图片，请重新登录',
        httpStatus: response.status,
      );
    }
    return ImageResponse(
      bytes: response.bytes,
      mimeType: mimeType,
      url: response.url,
    );
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  Future<HttpResponse> _request(
    String method,
    String initialUrl,
    List<(String, String)>? form,
    HttpRequestOptions options,
  ) async {
    final write = options.write;
    var url = initialUrl;
    var currentMethod = method;
    var body = form == null ? null : encodeForm(form);
    var redirects = 0;
    var retries = 0;

    for (;;) {
      _ensureAllowed(url);
      await _pace(url);
      final headers = _buildHeaders(url, options, currentMethod);
      // 必须显式声明表单类型：否则服务端解析不到任何表单参数
      // （登录会变成"空账号空密码"——TS 版实测过的 bug）。
      if (body != null) {
        headers['Content-Type'] =
            'application/x-www-form-urlencoded; charset=utf-8';
      }

      RawHttpResponse raw;
      try {
        raw = await _transport(RawHttpRequest(
          method: currentMethod,
          url: Uri.parse(url),
          headers: headers,
          body: currentMethod == 'POST' ? body : null,
        )).timeout(Duration(milliseconds: _timeoutMs));
      } on TimeoutException catch (error) {
        throw AcademicError(ErrorCode.timeout, '请求超时，请稍后重试', cause: error);
      } on AcademicError {
        rethrow;
      } catch (error) {
        if (!write && retries++ < 1) {
          await delay(250);
          continue;
        }
        throw AcademicError(
          write ? ErrorCode.resultUnknown : ErrorCode.networkRetryable,
          write ? '请求中断，结果尚未确认，请先刷新已选课程' : '无法连接教务系统，请检查网络或稍后重试',
          cause: error,
        );
      }

      if (raw.bytes.length > _maxBodyBytes) {
        throw AcademicError(ErrorCode.pageChanged, '教务响应过大，已中止');
      }

      // Set-Cookie 收集放在客户端（对应 TS 版 collect() 的职责），传输层只负责搬字节。
      final setCookie = raw.headers['set-cookie'];
      if (setCookie != null && setCookie.isNotEmpty) {
        _cookies.setCookies(Uri.parse(raw.url), setCookie);
      }

      _onRequest?.call(RequestLog(
        method: currentMethod,
        url: raw.url,
        status: raw.status,
        purpose: options.purpose == RequestPurpose.auth
            ? RequestPurpose.auth
            : RequestPurpose.query,
        // 状态码看不出"200 的错误页"，这里一并判掉：调试页据此显示
        // "HTTP 200 · 返回错误页"，而不是给个绿勾。
        issue: _issueFor(raw),
      ));

      if (raw.status >= 300 && raw.status <= 399) {
        if (!options.followRedirects) return _finish(raw);
        final location = _firstHeader(raw.headers, 'location');
        if (location == null || location.isEmpty) {
          throw AcademicError(
              ErrorCode.pageChanged, 'Redirect has no location');
        }
        if (write) {
          // 写操作一旦被重定向就无法判断教务是否已受理，交给上层去核对已选课程。
          throw AcademicError(
              ErrorCode.resultUnknown, 'Write request was redirected');
        }
        if (currentMethod == 'POST') {
          if (raw.status == 307 || raw.status == 308) {
            throw AcademicError(
                ErrorCode.pageChanged, 'POST redirect requires a new login');
          }
          currentMethod = 'GET';
          body = null;
        }
        redirects += 1;
        if (redirects > _maxRedirects) {
          throw AcademicError(ErrorCode.pageChanged, 'Too many redirects');
        }
        final next = _upgradeDowngrade(raw.url, resolveUrl(raw.url, location));
        try {
          _ensureAllowed(next);
        } on AcademicError catch (error) {
          // 会话过期时，学校常把请求 302 到另一个主机的统一认证地址
          // （`cas.` / `sso.` / `auth.`，或带 `service=` 回跳参数的登录页）。
          // 这不是可疑跳转，而是"该重新登录了"；当成 UNTRUSTED_URL 会让刷新
          // 直接失败、也不触发自动重登，用户只能看到"更新失败"。
          if (error.code == ErrorCode.untrustedUrl &&
              _looksLikeAuthRedirect(next)) {
            final host = Uri.tryParse(next)?.host ?? next;
            throw AcademicError(
              ErrorCode.sessionExpired,
              '登录已失效（被跳转到 $host）',
              httpStatus: raw.status,
            );
          }
          rethrow;
        }
        url = next;
        continue;
      }

      if (raw.status == 401 || raw.status == 403) {
        throw AcademicError(ErrorCode.sessionExpired, '登录已失效，请重新登录',
            httpStatus: raw.status);
      }
      if (raw.status == 429 || raw.status >= 500) {
        // 写操作无法确认是否已被受理，仍然按 resultUnknown 处理。
        if (write && raw.status >= 500) {
          throw AcademicError(
            ErrorCode.resultUnknown,
            '教务系统返回 HTTP ${raw.status}，写操作结果未知，请刷新核对',
            httpStatus: raw.status,
          );
        }
        // 读操作：这是**服务器自己坏了**，不是手机网络问题 —— 分成独立错误码，
        // 提示里带上状态码，用户和我们都一眼能分清该等还是该查网络。
        throw AcademicError(
          ErrorCode.serverError,
          '教务系统服务端异常（HTTP ${raw.status}），请稍后重试',
          httpStatus: raw.status,
        );
      }

      return _finish(raw);
    }
  }

  /// 这条响应看起来哪里不对（null = 正常）。用于调试页的"请求记录"。
  String? _issueFor(RawHttpResponse raw) {
    if (raw.status >= 500) return 'HTTP ${raw.status} 服务端异常';
    if (raw.status == 429) return 'HTTP 429 请求过多';
    if (raw.status >= 400) return 'HTTP ${raw.status}';
    final contentType =
        (_firstHeader(raw.headers, 'content-type') ?? '').toLowerCase();
    if (!contentType.contains('html') && !contentType.contains('text')) {
      return null;
    }
    // 只看开头 4KB：错误页/维护页的原因都在前面，没必要整个解析一遍。
    final snippet = _decodeWith(_charsetLabelOf(raw), _head(raw.bytes, 4096));
    return looksLikeServerError(snippet) ? '返回错误页' : null;
  }

  Uint8List _head(Uint8List bytes, int max) =>
      bytes.length <= max ? bytes : bytes.sublist(0, max);

  /// 响应正文的字符集：Content-Type 声明 > 正文前 4KB 里的 meta > 页面默认。
  String _charsetLabelOf(RawHttpResponse raw) {
    final contentType = _firstHeader(raw.headers, 'content-type');
    final declared = _charsetPattern.firstMatch(contentType ?? '')?.group(1);
    final sniffed = declared ??
        _charsetPattern
            .firstMatch(String.fromCharCodes(_head(raw.bytes, 4096)))
            ?.group(1);
    return _normalizeCharset(declared) ??
        _normalizeCharset(sniffed) ??
        _normalizeCharset(_pageCharset) ??
        'utf-8';
  }

  HttpResponse _finish(RawHttpResponse raw) {
    final contentType = _firstHeader(raw.headers, 'content-type');
    final label = _charsetLabelOf(raw);
    if ((contentType ?? '').toLowerCase().contains('html')) {
      _pageCharset = label;
    }
    var text = _decodeWith(label, raw.bytes);
    if (text.isNotEmpty && text.codeUnitAt(0) == 0xfeff) {
      text = text.substring(1);
    }
    return HttpResponse(
      status: raw.status,
      url: raw.url,
      body: text,
      headers: raw.headers,
      bytes: raw.bytes,
    );
  }

  Map<String, String> _buildHeaders(
      String url, HttpRequestOptions options, String method) {
    final headers = <String, String>{
      'Accept': _defaultAccept,
      'User-Agent': _userAgent,
      'Accept-Language': _defaultAcceptLanguage,
    };
    if (options.ajax) headers['X-Requested-With'] = 'XMLHttpRequest';
    // 浏览器对同源 POST 也会带 Origin；不伪造（URL 带 userinfo 时不发）。
    if (method == 'POST') {
      final target = Uri.tryParse(url);
      if (target != null && target.userInfo.isEmpty) {
        headers['Origin'] = target.origin;
      }
    }
    final referer = options.referer;
    if (referer != null) headers['Referer'] = referer;
    final cookie = _cookies.cookieHeaderFor(Uri.parse(url));
    if (cookie.isNotEmpty) headers['Cookie'] = cookie;
    return headers;
  }

  Future<void> _pace(String url) async {
    final host = Uri.tryParse(url)?.host.toLowerCase();
    if (host == null) return;
    final interval = _paceHosts[host];
    if (interval == null) return;
    final previous = _lastRequestAt[host];
    final now = DateTime.now().millisecondsSinceEpoch;
    if (previous != null) {
      final remaining = interval - (now - previous);
      if (remaining > 0) await delay(remaining);
    }
    _lastRequestAt[host] = DateTime.now().millisecondsSinceEpoch;
  }

  /// 跨主机跳转是不是"去登录 / 统一认证"。
  ///
  /// 判据只看形态，不看具体学校：认证域名（`cas.` / `sso.` / `auth.` / `idp.` 等）、
  /// 路径里带 `login` / `cas` / `sso` / `auth`，或者带 `service=` / `redirect_uri=` /
  /// `ticket=` 这类回跳参数。命中即视为会话失效，交给上层重新登录。
  ///
  /// 注意：命中后**不会**去访问那个地址，只把错误码换成 `SESSION_EXPIRED`；
  /// 真正的重登仍然发往配置的 `baseUrl`，所以不存在被劫持到外部域的风险。
  static bool _looksLikeAuthRedirect(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return false;
    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    final query = uri.query.toLowerCase();
    for (final prefix in const <String>[
      'cas.',
      'sso.',
      'auth.',
      'login.',
      'idp.',
      'passport.',
    ]) {
      if (host.startsWith(prefix)) return true;
    }
    for (final marker in const <String>['.cas.', '.sso.', '.auth.', '.idp.']) {
      if (host.contains(marker)) return true;
    }
    if (path.contains('login') ||
        path.contains('sso') ||
        path.contains('/cas') ||
        path.contains('auth')) {
      return true;
    }
    return query.contains('service=') ||
        query.contains('redirect_uri=') ||
        query.contains('ticket=');
  }

  void _ensureAllowed(String value) {
    if (!isAllowedUrl(value, _protocol, _allowed)) {
      throw AcademicError(ErrorCode.untrustedUrl, '请求目标不在配置的学校主机范围内');
    }
    if (_protocol == SchoolProtocol.https && !value.startsWith('https://')) {
      throw AcademicError(ErrorCode.untrustedUrl, 'HTTPS 学校配置不允许降级到 HTTP');
    }
  }

  /// 部分学校（实测青岛科技大学等）在登录后会把浏览器 302 到**同主机的 http** 地址。
  /// 这里照主分支 `AcademicRedirects.preferVerifiedHttps` 的做法：同主机默认端口的 http
  /// 跳转升级回 https（沿用来源端口），既不违反"不允许降级"的安全约定，也不会被学校的
  /// 随意跳转卡死。非标准端口的 http 跳转与跨主机跳转一律拒绝（由 ensureAllowed 兜底）。
  String _upgradeDowngrade(String currentUrl, String target) {
    if (_protocol != SchoolProtocol.https) return target;
    final from = Uri.tryParse(currentUrl);
    final to = Uri.tryParse(target);
    if (from == null || to == null || to.scheme != 'http') return target;
    if (from.host != to.host) return target;
    if (to.hasPort && to.port != 80) return target;
    return to
        .replace(scheme: 'https', port: from.hasPort ? from.port : null)
        .toString();
  }
}

/// 表单体编码。接受键值对列表（可表达重复键——新正方登录页有两个 `mm`）。
///
/// 新正方（本模块的覆盖范围）使用 UTF-8 页面，因此请求体按 UTF-8 百分号编码，
/// 空格编码为 `+`，与原项目 OkHttp FormBody / URLSearchParams 的行为一致。
String encodeForm(List<(String, String)> fields) {
  return fields
      .map((pair) =>
          '${Uri.encodeQueryComponent(pair.$1)}=${Uri.encodeQueryComponent(pair.$2)}')
      .join('&');
}

String? _firstHeader(Map<String, List<String>> headers, String name) {
  final values = headers[name];
  if (values == null || values.isEmpty) return null;
  return values.first;
}

/// 取响应头的第一个值（`set-cookie` 等多值头请直接读 `headers[name]` 列表）。
String? firstHeader(Map<String, List<String>> headers, String name) =>
    _firstHeader(headers, name);

String? _normalizeCharset(String? label) {
  if (label == null) return null;
  final key = label.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  const aliases = <String, String>{
    'utf8': 'utf-8',
    'gb2312': 'gbk',
    'gb18030': 'gb18030',
    'gbk': 'gbk',
    'iso88591': 'iso-8859-1',
    'latin1': 'iso-8859-1',
  };
  final alias = aliases[key];
  if (alias != null) return alias;
  return key.startsWith('utf') ? 'utf-8' : null;
}

String _decodeWith(String label, Uint8List bytes) {
  final encoding = Encoding.getByName(label);
  if (encoding == null ||
      identical(encoding, utf8) ||
      identical(encoding, ascii)) {
    // utf-8 容错解码：图片字节 / 损坏内容不抛异常（对齐 JS TextDecoder 的行为）。
    // 注意：Dart 原生只支持 utf-8 / latin1 / ascii。GBK 等字符集会走到这里按
    // utf-8 兜底——新正方页面均为 UTF-8；若未来要覆盖 GBK 页面（旧正方），
    // 需要在此注入第三方 codec（pub.dev 当前不可达，暂不引入）。
    return utf8.decode(bytes, allowMalformed: true);
  }
  // latin1 等单字节编码按字符集逐字节映射，不会抛格式异常。
  return encoding.decode(bytes);
}
