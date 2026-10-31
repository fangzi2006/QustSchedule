/// 新正方教务客户端：登录 → 保存 Cookie → 课表查询。
///
/// 覆盖范围：表单直登（RSA 密码加密 + 验证码 + 登录前清理会话）、会话校验、
/// 学期目录、课表查询、课表入口的路由发现。
///
/// **统一认证（CAS）不在支持范围**：`probe()` 如实报告 `requiresCas`，
/// `login()` 遇到 CAS 学校抛 `WEB_LOGIN_REQUIRED`。
///
/// 几处容易踩的实现约定：
///  - `checkSession()` 是三态：`unknown`（页面 404 / 读不到身份）**不当作过期**，
///    否则上层会拿错误信号驱动无谓的重新登录；
///  - "登录挑战过期"用 `STALE_CONTEXT`，不冒充 `SESSION_EXPIRED`；
///  - `session.authenticated` 以**读到身份信息**为准，不能只看有没有 Cookie；
///  - 文件持久化不在本类（纯 Dart 不依赖 dart:io）：用 `zf_academic_io.dart` 的
///    `FileCookieStorage` 搭配 `exportCookies()` / `importCookies()`。
library;

import 'dart:convert';
import 'dart:math';

import 'cookies.dart';
import 'credential_store.dart' show Credentials;
import 'crypto.dart';
import 'errors.dart';
import 'html.dart';
import 'http_client.dart';
import 'respond.dart';
import 'schedule.dart';
import 'types.dart';
import 'urls.dart';
import 'util.dart';

const String _indexMenuPath = '/xtgl/index_initMenu.html';
const int _scheduleRouteMaxCandidates = 20;
const int _pendingTtlMs = 300000;
const List<String> _messageIds = [
  'showMsg',
  'error',
  'errorMessage',
  'Label1',
  'lblMessage'
];
const List<String> _messageClasses = ['alert-danger', 'alert-error'];

int _sequence = 0;

String _newContinuationId() {
  _sequence += 1;
  final stamp = DateTime.now().millisecondsSinceEpoch;
  return 'login_${stamp.toRadixString(36)}_${_sequence.toRadixString(36)}';
}

int _nowMs() => DateTime.now().millisecondsSinceEpoch;

class ZfRoute {
  final String page;
  final String query;
  final String code;
  final bool personal;

  const ZfRoute({
    required this.page,
    required this.query,
    required this.code,
    this.personal = false,
  });
}

sealed class PendingLogin {
  final String id;
  final int generation;
  final int expiresAt;
  final String username;
  final String password;

  const PendingLogin({
    required this.id,
    required this.generation,
    required this.expiresAt,
    required this.username,
    required this.password,
  });
}

final class FormPendingLogin extends PendingLogin {
  final String pageUrl;
  final Map<String, String> hidden;
  final String captchaField;
  final String captchaUrl;

  const FormPendingLogin({
    required super.id,
    required super.generation,
    required super.expiresAt,
    required super.username,
    required super.password,
    required this.pageUrl,
    required this.hidden,
    required this.captchaField,
    required this.captchaUrl,
  });
}

/// 登录失败的归类结果。
typedef LoginFailure = ({ErrorCode code, String message});

String _messageElementText(String html) {
  return allTags(html)
      .where((element) =>
          _messageIds.contains(element.attrs['id'] ?? '') ||
          _messageClasses.any((token) => hasClass(element.attrs, token)))
      .map((element) => textOf(html, element))
      .join(' ');
}

String _jsonMessageField(String html) {
  try {
    final parsed = jsonDecode(html);
    if (parsed is Map) {
      for (final key in const ['message', 'msg', 'msgContent', 'error']) {
        final value = parsed[key];
        if (value is String && value.trim().isNotEmpty && value != 'null') {
          return value.trim();
        }
      }
    }
  } catch (_) {
    // 不是 JSON，按空处理
  }
  return '';
}

/// 读页面里的密码加密开关（`mmsfjm`）。对齐 SDK 的口径：取**所有** `input[name=mmsfjm]`
/// 或 `input#mmsfjm`（不限 type），取值必须唯一且是 `0`/`1`，否则按结构变化处理，
/// 而不是拿着一个不确定的值去赌。
String? _readEncryptionFlag(String html) {
  final values = allTags(html)
      .where((element) =>
          element.tag == 'input' &&
          (element.attrs['name'] == 'mmsfjm' ||
              element.attrs['id'] == 'mmsfjm'))
      .map((element) => element.attrs['value'] ?? '')
      .toList();
  final distinct = values.toSet().toList();
  if (distinct.length > 1 ||
      distinct.any((value) => !const ['0', '1'].contains(value))) {
    throw AcademicError(ErrorCode.pageChanged, '学校密码加密标记异常（mmsfjm 取值不一致或无效）');
  }
  return firstOf(distinct);
}

class ZhengfangClient {
  final ZfClientConfig _config;
  final ZfEndpoints _endpoints;
  final String _origin;
  final String _basePath;
  final CookieStore _cookies;
  final AcademicHttpClient _http;

  PendingLogin? _pending;
  Identity _identity = const Identity(studentName: '', studentId: '');
  String _username = '';
  ZfRoute? _route;
  String? _csrfTokenLogout;
  bool _closed = false;

  /// CAS 入口探测缓存（同实例同主机只需探测一次）
  String? _cachedCasLoginUrl;
  bool _casDiscoveryDone = false;

  /// RSA 公钥缓存（正方系统服务端公钥静态稳定，同实例登录可复用）
  String? _cachedModulus;
  String? _cachedExponent;

  ZhengfangClient._(
    this._config,
    this._endpoints,
    this._origin,
    this._basePath,
    this._cookies,
    this._http,
  );

  factory ZhengfangClient(ZfClientConfig config) {
    final parsed = parseAcademicAddress(config.baseUrl);
    final protocol =
        config.address?.protocol ?? parsed?.protocol ?? SchoolProtocol.https;
    final domain = config.address?.domain ?? parsed?.domain ?? '';
    final basePath = config.address?.basePath ?? parsed?.basePath ?? '';
    if (domain.isEmpty) {
      throw AcademicError(
        ErrorCode.validationFailed,
        '无法从地址中解析出学校主机：${config.baseUrl}',
      );
    }
    final origin =
        '${protocol == SchoolProtocol.https ? 'https' : 'http'}://$domain';
    final endpoints = normalizeEndpoints(config.endpoints);
    final cookies = CookieStore(baseUrl: resolveAppUrl(origin, basePath, ''));
    final http = AcademicHttpClient(AcademicHttpOptions(
      cookies: cookies,
      allowedHosts: <String>[
        normalizeHost(domain),
        ...(config.allowedHosts ?? const <String>[]),
      ],
      protocol: protocol,
      pageCharset: config.pageCharset,
      userAgent: config.userAgent,
      maxRedirects: config.maxRedirects,
      maxBodyBytes: config.maxBodyBytes,
      timeoutMs: config.requestTimeoutMs,
      paceHosts: config.paceHosts,
      transport: config.transport,
      onRequest: config.onRequest,
      onDispose: config.onDispose,
    ));
    final client =
        ZhengfangClient._(config, endpoints, origin, basePath, cookies, http);
    final saved = config.cookies;
    if (saved != null) client._cookies.import(saved);
    return client;
  }

  // -------------------------------------------------------------------------
  // 会话状态
  // -------------------------------------------------------------------------

  /// 教务根地址，用于把 Cookie 交给别的 HTTP 客户端。
  String get baseUrl => _cookies.baseUrl;

  /// 当前生效的 `Cookie: ...` 头。未登录时为 ''。
  String get cookieHeader => _cookies.header();

  List<String> get allowedHosts => _http.allowedHosts;

  /// 运行时可放行额外主机（例如探测到的 CAS 域）。
  void allowHost(String host) => _http.allowHost(host);

  SessionInfo get session => SessionInfo(
        username: _username,
        studentId: _identity.studentId,
        studentName: _identity.studentName,
        // 以读到身份信息为准：有 Cookie 不等于已登录。
        authenticated:
            _identity.studentId.isNotEmpty || _identity.studentName.isNotEmpty,
      );

  /// 会话世代：每次登录/作废递增，可用于判断旧回调是否已过期。
  int get generation => _cookies.generation;

  // -------------------------------------------------------------------------
  // Cookie 的导出 / 导入
  // -------------------------------------------------------------------------

  /// 导出可 JSON 序列化的 Cookie 快照。登录成功后调用它即可完成"保存 Cookie"。
  CookieStoreSnapshot exportCookies() => _cookies.export();

  /// 从快照恢复会话，省掉重新登录。
  void importCookies(CookieStoreSnapshot snapshot) {
    assertActive();
    _cookies.import(snapshot);
    _pending = null;
  }

  /// 从 `a=1; b=2` 形式的头字符串恢复会话（例如从 WebView 复制出来的会话）。
  void importCookieHeader(String header) {
    assertActive();
    _cookies.importCookieHeader(header);
    _pending = null;
  }

  /// 作废当前会话：清空 Cookie、递增世代、丢弃登录续期信息。
  void invalidate() {
    _cookies.invalidate();
    _pending = null;
    _identity = const Identity(studentName: '', studentId: '');
    _route = null;
  }

  void dispose() {
    _closed = true;
    invalidate();
  }

  /// 释放底层传输（dart:io 连接池）。注入的传输层经 `onDispose` 一并释放。
  void close() {
    _closed = true;
    _http.close();
  }

  // -------------------------------------------------------------------------
  // 探测与登录
  // -------------------------------------------------------------------------

  /// 只探测、不提交凭据：判断地址是不是新正方、登录页要验证码还是走统一认证、
  /// 密码是否需要前端加密。建议在真正输入密码之前先跑一次。
  Future<ZfProbeReport> probe() async {
    assertActive();
    final notes = <String>[];
    final loginPageUrl = _app('${_endpoints.loginPagePath}?time=${_nowMs()}');
    var reachable = false;
    int? httpStatus;
    var looksLikeZhengfang = false;
    var requiresCas = false;
    String? casLoginUrl;
    var captchaRequired = false;
    var passwordEncryption = false;

    try {
      casLoginUrl = await _discoverCasLoginUrl();
      if (casLoginUrl != null) {
        requiresCas = true;
        notes.add('发现统一认证入口，登录将走正方定制 CAS（多一步票据交换）');
      }
    } catch (error) {
      notes.add('统一认证入口探测失败：${_describe(error)}');
    }

    HttpResponse page;
    try {
      page = await _http.get(
          loginPageUrl, const HttpRequestOptions(purpose: RequestPurpose.auth));
    } catch (error) {
      notes.add('无法打开登录页：${_describe(error)}');
      return ZfProbeReport(
        baseUrl: _app(''),
        loginPageUrl: loginPageUrl,
        reachable: false,
        looksLikeZhengfang: false,
        requiresCas: requiresCas,
        casLoginUrl: casLoginUrl,
        captchaRequired: false,
        passwordEncryption: false,
        hasCookies: _cookies.size > 0,
        notes: notes,
      );
    }
    reachable = true;
    httpStatus = page.status;

    final hidden = hiddenFields(page.body);
    if (isLoginPage(page.body)) looksLikeZhengfang = true;
    if (hidden['csrftoken'] != null) looksLikeZhengfang = true;
    if (RegExp(r'login_getPublicKey|xtgl/|教学管理信息服务平台', caseSensitive: false)
        .hasMatch(page.body)) {
      looksLikeZhengfang = true;
    }
    try {
      passwordEncryption = _readEncryptionFlag(page.body) == '1';
    } catch (error) {
      passwordEncryption = false;
      notes.add('密码加密标记无法判定：${_describe(error)}');
    }

    final captcha = detectCaptcha(page.body);
    captchaRequired = captcha.control != null;
    if (captcha.imageOnly != null || captcha.fieldOnly != null) {
      notes.add('验证码控件形式不完整（只有图或只有输入框），可能需要改用教务网页登录');
    }

    if (!looksLikeZhengfang) {
      notes.add('登录页没有发现新正方特征，本模块只覆盖新正方。');
    }
    if (_cookies.size > 0) {
      notes.add('当前实例已带 Cookie；请用 checkSession() 确认是否仍然有效');
    }
    return ZfProbeReport(
      baseUrl: _app(''),
      loginPageUrl: loginPageUrl,
      reachable: reachable,
      httpStatus: httpStatus,
      looksLikeZhengfang: looksLikeZhengfang,
      requiresCas: requiresCas,
      casLoginUrl: casLoginUrl,
      captchaRequired: captchaRequired,
      passwordEncryption: passwordEncryption,
      hasCookies: _cookies.size > 0,
      notes: notes,
    );
  }

  /// 登录。探测到统一认证时抛 UNSUPPORTED（CAS 支持下阶段提供），否则走表单直登。
  ///
  /// 成功返回 `{status:'authenticated'}`；需要验证码返回 `{status:'captcha'}`；
  /// 其余失败抛 `AcademicError`（INVALID_CREDENTIALS / PAGE_CHANGED / NETWORK_RETRYABLE ...）。
  Future<AuthState> login(Credentials credentials) async {
    assertActive();
    _pending = null;
    _route = null;
    // 新登录作废旧会话：与原项目 `session.invalidate()` 的行为一致。
    _cookies.invalidate();
    _identity = const Identity(studentName: '', studentId: '');
    _username = credentials.username;

    final casLoginUrl = await _discoverCasLoginUrl();
    if (casLoginUrl != null) {
      throw AcademicError(
        ErrorCode.unsupported,
        '该校使用正方统一认证（CAS），登录支持下阶段提供；可先在教务网页登录后导入 Cookie',
      );
    }
    return _loginViaForm(credentials);
  }

  /// 提交验证码，继续上一次未完成的登录。
  Future<AuthState> submitCaptcha(String code) async {
    assertActive();
    final pending = _requirePending();
    if (code.trim().isEmpty) {
      throw AcademicError(ErrorCode.captchaRequired, '请输入验证码');
    }
    if (pending is FormPendingLogin) {
      return _submitFormLogin(
        username: pending.username,
        password: pending.password,
        referer: pending.pageUrl,
        hidden: pending.hidden,
        extra: <String, String>{pending.captchaField: code.trim()},
        fromCaptchaRetry: true,
      );
    }
    throw AcademicError(ErrorCode.staleContext, 'CAS 验证码提交尚未实现');
  }

  /// 换一张验证码图片。刷新不新建账号会话，continuationId 保持不变。
  Future<CaptchaState> refreshCaptcha() async {
    assertActive();
    final pending = _requirePending();
    if (pending is FormPendingLogin) {
      final image = await _http.getImage(
        withQuery(pending.captchaUrl, <String, String>{'_': '${_nowMs()}'}),
        referer: pending.pageUrl,
      );
      return CaptchaState(
        continuationId: pending.id,
        imageBase64: base64.encode(image.bytes),
        mimeType: image.mimeType,
      );
    }
    throw AcademicError(ErrorCode.staleContext, 'CAS 验证码刷新尚未实现');
  }

  /// 校验已保存的会话是否仍然有效。`expired` 时抛 SESSION_EXPIRED，
  /// `unknown`（无法确认）时抛 VALIDATION_FAILED——两者都不是"重新登录"的信号。
  Future<AuthenticatedState> validateSession() async {
    final state = await checkSession();
    if (state.status == SessionStatus.expired) {
      throw AcademicError(ErrorCode.sessionExpired, '登录已失效，请重新登录');
    }
    if (state.status == SessionStatus.unknown) {
      throw AcademicError(ErrorCode.validationFailed, '无法确认会话状态，请重新登录或稍后重试');
    }
    return AuthenticatedState(
      studentId: state.studentId,
      studentName: state.studentName,
    );
  }

  /// 与 `validateSession()` 相同，但把"已失效/无法确认"作为正常返回值而不是异常。
  Future<SessionState> checkSession() async {
    assertActive();
    if (_cookies.size == 0) {
      return const SessionState(
        status: SessionStatus.expired,
        studentId: '',
        studentName: '',
      );
    }
    HttpResponse response;
    try {
      response = await _http.get(
        _app(withQuery(_endpoints.studentInfoPath, const {'gnmkdm': 'index'})),
        const HttpRequestOptions(),
      );
    } on AcademicError catch (error) {
      if (error.code == ErrorCode.sessionExpired) {
        return const SessionState(
          status: SessionStatus.expired,
          studentId: '',
          studentName: '',
        );
      }
      rethrow;
    }
    // 登录页 = 确证失效；非 2xx = 无法确认（学校没开这个页面/结构变了），不能驱动重登。
    if (isLoginPage(response.body)) {
      return const SessionState(
        status: SessionStatus.expired,
        studentId: '',
        studentName: '',
      );
    }
    if (response.status < 200 || response.status >= 300) {
      return const SessionState(
        status: SessionStatus.unknown,
        studentId: '',
        studentName: '',
      );
    }
    var parsed = identity(response.body);
    if (parsed.studentId.isEmpty) parsed = await _menuIdentityFallback(parsed);
    final authenticated = parsed.studentId.isNotEmpty ||
        parsed.studentName.isNotEmpty ||
        const ['xsxk.aspx', 'xklc_list', '退出登录', '学期理论课表', '选课结果']
            .any(response.body.contains);
    if (!authenticated) {
      return const SessionState(
        status: SessionStatus.unknown,
        studentId: '',
        studentName: '',
      );
    }
    _identity = parsed;
    if (parsed.studentId.isNotEmpty) _username = parsed.studentId;
    return SessionState(
      status: SessionStatus.authenticated,
      studentId: parsed.studentId.isNotEmpty ? parsed.studentId : _username,
      studentName: parsed.studentName,
    );
  }

  // -------------------------------------------------------------------------
  // 课表
  // -------------------------------------------------------------------------

  /// 可取到的学期目录。`currentId` 一定指向 items 中的一项。
  Future<Terms> fetchTerms() async {
    assertActive();
    final items = <Term>[];
    final selected = <Term>[];
    AcademicError? firstError;

    final loaders = <Future<String> Function()>[
      () async => (await _zfScheduleRequest(null)).body,
      () async => (await _http.get(
            _app(withQuery(_endpoints.gradesPath,
                <String, String>{'gnmkdm': _endpoints.gradeGnmkdm})),
            const HttpRequestOptions(),
          ))
              .body,
    ];
    for (final load in loaders) {
      try {
        final body = await load();
        lastTermsRawBody ??= body;
        if (isLoginPage(body)) {
          throw AcademicError(ErrorCode.sessionExpired, '登录已失效，请重新登录');
        }
        if (looksLikeAccessForbidden(body)) {
          throw AcademicError(
            ErrorCode.accessForbidden,
            '访问被拒绝（403）：访问策略禁止外网访问，请连接校园网后重试',
            httpStatus: 403,
          );
        }
        if (looksLikeServerError(body)) {
          throw AcademicError(
            ErrorCode.serverError,
            '教务返回了错误/维护页面，不是学期数据',
          );
        }
        final current = selectedTermFromHtml(body);
        items.addAll(termsFromHtml(body));
        if (current != null) {
          items.add(current);
          selected.add(current);
        }
        // 当前页面已取到学期列表与当前活跃学期，不再请求备用页面（如成绩页）。
        if (items.isNotEmpty && selected.isNotEmpty) {
          break;
        }
      } catch (error) {
        // 会话过期、取消、权限类错误不能被吞掉，否则会把"读不到"当成"没有学期"。
        final academic =
            error is AcademicError ? error : asAcademicError(error);
        if (!const [
          ErrorCode.networkRetryable,
          ErrorCode.pageChanged,
          ErrorCode.unsupported,
          ErrorCode.notOpen,
        ].contains(academic.code)) {
          rethrow;
        }
        firstError ??= academic;
      }
    }

    final unique = <String, Term>{};
    for (final item in items) {
      unique[item.id] = item;
    }
    final sorted = unique.values.toList()..sort((a, b) => b.id.compareTo(a.id));
    if (sorted.isEmpty) {
      if (firstError != null) throw firstError;
      changed('学校未返回可识别的学期选项，请刷新学期列表');
    }
    final current = firstOf(selected) ??
        firstOf(sorted.where((item) => item.id == calendarTerm().id)) ??
        sorted.first;
    return Terms(items: sorted, currentId: current.id);
  }

  /// 查询课表。不传 `termId` 时用 `fetchTerms()` 推出来的当前学期。
  /// 返回结构与 SDK 的 `Schedule` 一致，可直接给已有课表消费者使用。
  ///
  /// 解析前的原始数据会留在 [lastScheduleRawBody] / [lastScheduleRows]，
  /// 供 app 的调试页核对"学校给的数据"与"我们解析出的课表"是否一致。
  Future<Schedule> fetchSchedule([String? termId]) async {
    assertActive();
    final id = termId ?? (await fetchTerms()).currentId;
    final page = await _zfScheduleRequest(id);
    lastScheduleRawBody = page.body;
    // 会话过期但跳转落在同主机登录页时，拿到的是登录页 HTML 而不是 JSON。
    // 不识别的话会把"没读到"解析成"这学期没课"，进而用空课表覆盖缓存。
    if (isLoginPage(page.body)) {
      throw AcademicError(ErrorCode.sessionExpired, '登录已失效，请重新登录');
    }
    final rows = listRows(page.body, const ['kbList', 'data']);
    lastScheduleRows = rows;
    final entries = jsonSchedule(rows);
    // 备注：实践课程 / 其他课程（sjkList，可能没有——取不到就是空，不影响主流程）。
    final remarks = jsonScheduleRemarks(
      listRowsOrEmpty(page.body, const ['sjkList', 'data']),
    );
    _debug('schedule:parsed', <String, Object?>{
      'termId': id,
      'bodyLength': page.body.length,
      'rows': rows.length,
      'entries': entries.length,
      'remarks': remarks.length,
      'maxWeeks': maxWeeksOf(entries),
      'weekRange': _weekRangeOf(entries),
      'missingWeeks': entries.where((entry) => entry.weeks.isEmpty).length,
    });
    return Schedule(
      termId: id,
      entries: entries,
      remarks: remarks,
      maxWeeks: maxWeeksOf(entries),
    );
  }

  /// 最近一次课表查询的原始响应体（未解析）。调试用，可能是几十 KB。
  String? lastScheduleRawBody;

  /// 最近一次课表查询解析出的 `kbList` 原始行（字段未归一化）。调试用。
  List<Map<String, dynamic>> lastScheduleRows = const <Map<String, dynamic>>[];

  /// 最近一次学期列表查询的原始页面（可能是课表页或成绩页，取决于哪个先成功）。
  String? lastTermsRawBody;

  static String _weekRangeOf(List<ScheduleEntry> entries) {
    final all = <int>{};
    for (final entry in entries) {
      all.addAll(entry.weeks);
    }
    if (all.isEmpty) return '-';
    final sorted = all.toList()..sort();
    return '${sorted.first}-${sorted.last}';
  }

  // -------------------------------------------------------------------------
  // 表单直登
  // -------------------------------------------------------------------------

  Future<AuthState> _loginViaForm(Credentials credentials) async {
    final url = _app('${_endpoints.loginPagePath}?time=${_nowMs()}');
    final page = await _http.get(
        url, const HttpRequestOptions(purpose: RequestPurpose.auth));
    final hidden = hiddenFields(page.body);
    final encryption = _readEncryptionFlag(page.body);
    if (encryption != null) hidden['mmsfjm'] = encryption;
    if (hidden['csrftoken'] == null) {
      if (looksLikeAccessForbidden(page.body)) {
        throw AcademicError(
          ErrorCode.accessForbidden,
          '访问被拒绝（403）：访问策略禁止外网访问，请连接校园网后重试',
          httpStatus: 403,
        );
      }
      if (looksLikeServerError(page.body)) {
        throw AcademicError(
          ErrorCode.serverError,
          '教务返回了错误/维护页面，无法打开登录页',
        );
      }
      throw AcademicError(ErrorCode.pageChanged, '学校登录页缺少 csrftoken');
    }

    // login_logoutAccount.html 需要的令牌：按 id 或 name 找，找不到就留空（与浏览器一致）。
    final logoutField = firstOf(allTags(page.body).where((element) =>
        element.tag == 'input' &&
        (element.attrs['id'] == 'csrfTokenLogout' ||
            element.attrs['name'] == 'csrfTokenLogout')));
    _csrfTokenLogout = logoutField?.attrs['value'] ?? '';

    _debug('auth:login-page', <String, Object?>{
      'url': page.url,
      'httpStatus': page.status,
      'csrftoken': hidden['csrftoken'] != null,
      'mmsfjm': encryption ?? '(无此标记，按明文)',
      'hiddenKeys': (hidden.keys.toList()..sort()).join(','),
      'title': RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
              .firstMatch(page.body)
              ?.group(1)
              ?.trim() ??
          '',
      'hasForm': allTags(page.body).any((element) => element.tag == 'form'),
    });

    final captcha = detectCaptcha(page.body);
    if (captcha.control != null) {
      final imageUrl = _resolveUrlOrThrow(page.url, captcha.control!.imageSrc);
      final continuationId = _newContinuationId();
      _pending = FormPendingLogin(
        id: continuationId,
        generation: _cookies.generation,
        expiresAt: _nowMs() + _pendingTtlMs,
        username: credentials.username,
        password: credentials.password,
        pageUrl: page.url,
        hidden: hidden,
        captchaField: captcha.control!.fieldName,
        captchaUrl: imageUrl,
      );
      final image = await _http.getImage(imageUrl, referer: page.url);
      return CaptchaState(
        continuationId: continuationId,
        imageBase64: base64.encode(image.bytes),
        mimeType: image.mimeType,
      );
    }
    if (captcha.imageOnly != null || captcha.fieldOnly != null) {
      // 验证码控件形式特殊（只有图或只有输入框）：不在本模块用启发式去猜，交给网页端完成。
      throw AcademicError(ErrorCode.webLoginRequired, '学校验证码形式暂不支持，请在教务网页完成验证');
    }

    return _submitFormLogin(
      username: credentials.username,
      password: credentials.password,
      referer: page.url,
      hidden: hidden,
      extra: const <String, String>{},
      fromCaptchaRetry: false,
    );
  }

  /// 提交登录表单。`extra` 用于带上验证码；没有验证码时为空。
  /// 失败一律抛异常，"失败"与"成功"不会被混淆。
  Future<AuthState> _submitFormLogin({
    required String username,
    required String password,
    required String referer,
    required Map<String, String> hidden,
    required Map<String, String> extra,
    required bool fromCaptchaRetry,
  }) async {
    final fields = <String, String>{...hidden, ...extra};
    var mm = password;
    if (fields['mmsfjm'] == '1') {
      var modulus = _cachedModulus ?? '';
      var exponent = _cachedExponent ?? '';
      if (modulus.isEmpty || exponent.isEmpty) {
        final keyUrl =
            _app('${_endpoints.publicKeyPath}?time=${_nowMs()}&_=${_nowMs()}');
        final response = await _http.get(
            keyUrl, const HttpRequestOptions(purpose: RequestPurpose.auth));
        if (response.status < 200 || response.status >= 300) {
          throw AcademicError(
            ErrorCode.networkRetryable,
            '学校公钥获取失败（HTTP ${response.status}）',
            httpStatus: response.status,
          );
        }
        Map<String, dynamic> key;
        try {
          final decoded = jsonDecode(response.body);
          if (decoded is! Map<String, dynamic>) {
            throw const FormatException('公钥不是 JSON 对象');
          }
          key = decoded;
        } catch (error) {
          throw AcademicError(ErrorCode.pageChanged, '学校公钥格式无效', cause: error);
        }
        modulus = str(key['modulus']);
        exponent = str(key['exponent']);
        if (modulus.isEmpty || exponent.isEmpty) {
          throw AcademicError(ErrorCode.pageChanged, '学校公钥格式无效');
        }
        _cachedModulus = modulus;
        _cachedExponent = exponent;
        _debug('auth:public-key', <String, Object?>{
          'url': response.url,
          'modulusLength': modulus.length,
          'modulusPreview': modulus.substring(0, min(24, modulus.length)),
          'exponent': exponent,
          'looksHex':
              RegExp(r'^[0-9a-f]+$', caseSensitive: false).hasMatch(modulus),
          'looksBase64': RegExp(r'^[A-Za-z0-9+/]+=*$').hasMatch(modulus),
        });
      }
      mm = zfFormEncryptPassword(modulus, exponent, password);
    }
    fields['yhm'] = username;
    fields['mm'] = mm;
    final language = fields['language'];
    fields['language'] =
        language != null && language.isNotEmpty ? language : 'zh_CN';

    // 登录前清理会话：浏览器 login.js 的 yhdl() 会先 POST login_logoutAccount.html
    // （带 csrfTokenLogout），再提交登录表单。缺失该字段时按空串发送，与浏览器一致。
    await _logoutAccount(referer);

    // 浏览器会把 form action 追加 ?time=（缓存破坏）；登录页有两个 name=mm 的输入框
    // （可见 #mm 与隐藏 #hidMm），两者都会提交同一份密文，服务端可能校验这一点。
    final pairs = <(String, String)>[
      ...fields.entries.map((entry) => (entry.key, entry.value)),
      ('mm', mm),
    ];
    final postUrl = '${_app(_endpoints.loginPagePath)}?time=${_nowMs()}';

    _debug('auth:submit', <String, Object?>{
      'url': postUrl,
      'fieldKeys': pairs.map((pair) => pair.$1).toSet().toList()..sort(),
      'mmsfjm': fields['mmsfjm'] ?? '(未提交)',
      'mmEncrypted': mm != password,
      'mmLength': mm.length,
      // 密码本身的形状信息（不含密码内容），用于核对输入是否被敲错。
      'passwordLength': password.length,
      'passwordCodepoints': password.runes.length,
      'passwordHasControlChars':
          RegExp(r'[\u0000-\u001f\u007f]').hasMatch(password),
    });

    final result = await _http.postPairs(
      postUrl,
      pairs,
      HttpRequestOptions(referer: referer, purpose: RequestPurpose.auth),
    );

    final plainPreview = stripTags(result.body).replaceAll(RegExp(r'\s+'), ' ');
    final bodyPreview = plainPreview.length > 500
        ? plainPreview.substring(0, 500)
        : plainPreview;
    _debug('auth:response', <String, Object?>{
      'status': result.status,
      'url': result.url,
      'isLoginPage': isLoginPage(result.body),
      'bodyText': password.isNotEmpty
          ? bodyPreview.split(password).join('***')
          : bodyPreview,
    });

    // 学校真的拒绝了这次登录时，先报它的原因，再去试着读身份信息——否则错误会被后续
    // 的"登录页重定向"覆盖成一句含糊的提示。
    if (isLoginPage(result.body)) {
      _cachedModulus = null;
      _cachedExponent = null;
      final failure = _classifyLoginFailure(result.body);
      if (failure != null && failure.code == ErrorCode.invalidCredentials) {
        _pending = null;
        throw AcademicError(ErrorCode.invalidCredentials, failure.message);
      }
      if (failure != null && failure.code == ErrorCode.captchaRequired) {
        if (fromCaptchaRetry) return refreshCaptcha();
        throw AcademicError(ErrorCode.captchaRequired, failure.message);
      }
    }

    final identity = await _readIdentity();
    if (identity.studentName.isNotEmpty || identity.studentId.isNotEmpty) {
      _pending = null;
      _identity = identity;
      if (identity.studentId.isNotEmpty) _username = identity.studentId;
      return AuthenticatedState(
        studentId:
            identity.studentId.isNotEmpty ? identity.studentId : username,
        studentName: identity.studentName,
      );
    }
    if (RegExp(r'密码错误|用户名或密码').hasMatch(result.body)) {
      throw AcademicError(ErrorCode.invalidCredentials, '用户名或密码不正确');
    }
    throw AcademicError(ErrorCode.validationFailed, '登录响应无法验证，请重试或使用教务网页登录');
  }

  /// 登录前清理会话：浏览器 `login.js` 的 `yhdl()` 在提交登录表单前会先 POST
  /// `xtgl/login_logoutAccount.html`（携带 `csrfTokenLogout`）。这一步失败不影响登录本身
  /// （返回体通常是 `"null"`），因此这里刻意不把它的失败上报。
  Future<void> _logoutAccount(String referer) async {
    final token = _csrfTokenLogout ?? '';
    try {
      await _http.postPairs(
        _app('/xtgl/login_logoutAccount.html'),
        <(String, String)>[('csrfTokenLogout', token)],
        HttpRequestOptions(
            referer: referer, purpose: RequestPurpose.auth, ajax: true),
      );
    } catch (_) {
      // 清理会话失败不阻断登录
    }
  }

  LoginFailure? _classifyLoginFailure(String html) {
    final jsonMessage = _jsonMessageField(html);
    final alerts = RegExp(r"""alert\s*\(\s*['"]([^'"\r\n]+)['"]\s*\)""")
        .allMatches(html)
        .map((match) => match.group(1) ?? '')
        .toList();
    final messages = <String>[
      jsonMessage,
      _messageElementText(html),
      ...alerts,
      stripTags(html)
    ];

    final captchaFailure = RegExp(
      r'(?:验证码|校验码|附加码|captcha|verification\s*code).{0,24}(?:错误|不正确|有误|不对|失效|过期|incorrect|invalid|expired)|(?:invalid|incorrect|expired)\s+(?:captcha|verification\s*code)',
      caseSensitive: false,
    );
    if (messages.any(captchaFailure.hasMatch)) {
      return (code: ErrorCode.captchaRequired, message: '验证码错误或已过期，请重新输入');
    }
    final credentialFailure = RegExp(
      r'密码错误|密码不正确|密码有误|用户名或密码|账号或密码|帐号或密码|账户或密码|用户名不存在|用户不存在|账号不存在|帐号不存在|学号不存在|(?:invalid|incorrect)\s+(?:username|password|credentials)|password\s+(?:is\s+)?(?:incorrect|invalid)',
      caseSensitive: false,
    );
    if (messages.any(credentialFailure.hasMatch)) {
      return (code: ErrorCode.invalidCredentials, message: '用户名或密码不正确');
    }
    if (jsonMessage.contains('验证码')) {
      return (code: ErrorCode.captchaRequired, message: '请输入验证码');
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // 统一认证探测（CAS 登录本身尚未实现）
  // -------------------------------------------------------------------------

  /// 探测教务系统的正方 CAS 入口：GET `{教务根}/sso/zfiotlogin`（不跟随重定向）。
  /// 跳到 `/cas/login` 且 service 指回教务域时返回入口地址，否则 null。
  Future<String?> _discoverCasLoginUrl() async {
    if (_casDiscoveryDone) return _cachedCasLoginUrl;
    final serviceUrl = _config.casServiceUrl ?? _app('');
    if (_config.casLoginUrl != null) {
      _cachedCasLoginUrl = _config.casLoginUrl;
      _casDiscoveryDone = true;
      return _cachedCasLoginUrl;
    }
    final base = Uri.parse(serviceUrl);
    final probeUrl = Uri(
      scheme: base.scheme,
      host: base.host,
      port: base.hasPort ? base.port : null,
      path: '${base.path.replaceAll(RegExp(r'/+$'), '')}/sso/zfiotlogin',
    );
    try {
      final response = await _http.get(
        probeUrl.toString(),
        const HttpRequestOptions(
            followRedirects: false, purpose: RequestPurpose.auth),
      );
      if (response.status < 300 || response.status > 399) {
        _cachedCasLoginUrl = null;
        _casDiscoveryDone = true;
        return null;
      }
      final location = firstHeader(response.headers, 'location');
      if (location == null || location.isEmpty) {
        _cachedCasLoginUrl = null;
        _casDiscoveryDone = true;
        return null;
      }
      final target = Uri.tryParse(resolveUrl(probeUrl.toString(), location));
      if (target == null || !target.path.contains('/cas/login')) {
        _cachedCasLoginUrl = null;
        _casDiscoveryDone = true;
        return null;
      }
      final service = Uri.tryParse(target.queryParameters['service'] ?? '');
      if (service == null || service.host != base.host) {
        _cachedCasLoginUrl = null;
        _casDiscoveryDone = true;
        return null;
      }
      _http.allowHost(target.host);
      _cachedCasLoginUrl = target.toString();
      _casDiscoveryDone = true;
      return _cachedCasLoginUrl;
    } on AcademicError {
      _cachedCasLoginUrl = null;
      _casDiscoveryDone = true;
      return null;
    } catch (_) {
      _cachedCasLoginUrl = null;
      _casDiscoveryDone = true;
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // 身份读取
  // -------------------------------------------------------------------------

  Future<Identity> _readIdentity() async {
    final response = await _http.get(
      _app(withQuery(_endpoints.studentInfoPath, const {'gnmkdm': 'index'})),
      const HttpRequestOptions(),
    );
    if (isLoginPage(response.body)) {
      return const Identity(studentName: '', studentId: '');
    }
    var parsed = identity(response.body);
    if (parsed.studentId.isEmpty) parsed = await _menuIdentityFallback(parsed);
    return parsed;
  }

  /// 部分学校（如河北传媒学院）的 cxYhxx 页面是定制变体，只有姓名没有学号；
  /// 回退到框架首页 initMenu 读隐藏域 sessionUserKey（正方 v5 标准结构）。
  Future<Identity> _menuIdentityFallback(Identity current) async {
    String body;
    try {
      body = (await _http.get(_app(_indexMenuPath), const HttpRequestOptions()))
          .body;
    } catch (_) {
      return current;
    }
    if (isLoginPage(body)) return current;
    final fallback = identity(body);
    return Identity(
      studentName: current.studentName.isNotEmpty
          ? current.studentName
          : fallback.studentName,
      studentId: fallback.studentId,
    );
  }

  // -------------------------------------------------------------------------
  // 课表请求
  // -------------------------------------------------------------------------

  Future<HttpResponse> _zfScheduleRequest(String? termId) async {
    var route = _route ??
        ZfRoute(
          page: _endpoints.schedulePath,
          query: _endpoints.scheduleQueryPath ?? _endpoints.schedulePath,
          code: _endpoints.scheduleGnmkdm,
          personal: _endpoints.personal,
        );

    Future<HttpResponse> run() async {
      final target =
          withQuery(_app(termId != null ? route.query : route.page), {
        'gnmkdm': route.code,
      });
      if (termId != null) {
        final params = zfTermParams(termId);
        final fields = <String, String>{'xnm': params.xnm, 'xqm': params.xqm};
        if (route.personal) {
          fields.addAll(<String, String>{
            'kzlx': 'ck',
            'xsdm': '',
            'kclbdm': '',
            'kclxdm': '',
          });
        }
        return _http.postPairs(
          target,
          fields.entries.map((entry) => (entry.key, entry.value)).toList(),
          HttpRequestOptions(
            referer: withQuery(
                _app(route.page), <String, String>{'gnmkdm': route.code}),
            ajax: true,
          ),
        );
      }
      return _http.get(target);
    }

    var page = await run();
    if (isPermissionDenied(page.body)) {
      route = await _discoverScheduleRoute();
      _route = route;
      if (termId != null) {
        await _http.get(withQuery(_app(route.page), {'gnmkdm': route.code}));
      }
      page = await run();
    }
    if (isPermissionDenied(page.body)) {
      throw AcademicError(ErrorCode.unsupported, '学校未开放当前账号的课表查询权限');
    }
    return page;
  }

  /// 从 `xtgl/index_initMenu.html` 的 clickMenu 参数里找出真正可用的课表入口。
  Future<ZfRoute> _discoverScheduleRoute() async {
    final page =
        await _http.get(_app(_indexMenuPath), const HttpRequestOptions());
    final routes = <ZfRoute>[];
    for (final node in allTags(page.body)) {
      final onclick = node.attrs['onclick'];
      if (onclick == null) continue;
      final match = RegExp(
              r"""^\s*clickMenu\(\s*['"](N\d+)['"]\s*,\s*['"]([^'"]+)['"]\s*,""")
          .firstMatch(onclick);
      if (match == null) continue;
      if (match.group(2) == '/kbcx/xskbcx_cxXskbcxIndex.html') {
        routes.add(ZfRoute(
          page: match.group(2)!,
          query: '/kbcx/xskbcx_cxXsgrkb.html',
          code: match.group(1)!,
          personal: true,
        ));
      }
      if (match.group(2) == '/kbcx/xskbcx_cxXsKb.html') {
        routes.add(ZfRoute(
            page: match.group(2)!,
            query: match.group(2)!,
            code: match.group(1)!));
      }
    }
    if (routes.length > _scheduleRouteMaxCandidates) {
      changed('学校课表入口候选过多，无法确定');
    }
    final unique = <String, ZfRoute>{};
    for (final route in routes) {
      unique['${route.page}|${route.query}|${route.code}|${route.personal}'] =
          route;
    }
    final list = unique.values.toList();
    final configured =
        list.where((route) => route.code == _endpoints.scheduleGnmkdm).toList();
    final route = firstOf(configured.length == 1
        ? configured
        : list.length == 1
            ? list
            : const <ZfRoute>[]);
    if (route == null) changed('无法确定学校可用的个人课表入口');
    return route;
  }

  // -------------------------------------------------------------------------
  // 基础设施
  // -------------------------------------------------------------------------

  /// 应用根路径拼接：`xtgl/login_slogin.html` 与 `/xsxk/...` 都会补上 basePath。
  String _app(String path) => resolveAppUrl(_origin, _basePath, path);

  PendingLogin _requirePending() {
    final pending = _pending;
    if (pending == null) {
      throw AcademicError(ErrorCode.sessionExpired, '登录会话已失效，请重新登录');
    }
    if (pending.expiresAt < _nowMs() ||
        pending.generation != _cookies.generation) {
      _pending = null;
      throw AcademicError(ErrorCode.staleContext, '登录挑战已过期，请重新登录');
    }
    return pending;
  }

  void assertActive() {
    if (_closed) throw AcademicError(ErrorCode.cancelled, '客户端已释放');
  }

  void _debug(String event, Map<String, Object?> data) {
    _config.onDebug?.call(event, data);
  }

  static String _describe(Object error) {
    final academic = asAcademicError(error);
    return '${academic.code.wire} — ${academic.message}';
  }
}

/// 客户端自报的会话摘要。`authenticated` 以**读到身份信息**为准。
class SessionInfo {
  final String username;
  final String studentId;
  final String studentName;
  final bool authenticated;

  const SessionInfo({
    required this.username,
    required this.studentId,
    required this.studentName,
    required this.authenticated,
  });
}

String _resolveUrlOrThrow(String base, String relative) {
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(relative)) {
    return relative;
  }
  try {
    return resolveUrl(base, relative);
  } catch (error) {
    throw AcademicError(ErrorCode.pageChanged, '学校返回了无法解析的验证码地址', cause: error);
  }
}
