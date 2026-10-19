/// 课表获取编排：Cookie 优先，失效才回退到账密登录。
///
/// 对应需求：
///  1. 保存账号密码后，用已保存的 Cookie 获取课表（[bootstrap] / [getSchedule]）；
///  2. 获取过程中检测到 Cookie 失效时，自动用保存的账号密码重新登录并换新 Cookie
///     （只有 `SESSION_EXPIRED` 触发；页面结构变化等错误原样上抛——重登解决不了，
///     还会白耗学校的失败次数，青科大 3 次失败锁号）；
///  3. 登录与课表可单独调用：本类两个入口互不依赖，也可以只用 [ZhengfangClient]。
///
/// 防呆设计（全部有对应测试）：
///  - 单 flight：并发取课表同时遇失效，只登一次，其余复用同一次登录的结果；
///  - 回滚：重登失败时把旧 Cookie 快照恢复回去，不会从"会话过期"恶化成"彻底掉登录"；
///  - 熔断：窗口内自动登录次数上限（默认 10 分钟 2 次），超限抛 SESSION_EXPIRED
///    要求手动登录，防止"失效误报 + 重登失败"连锁锁号；
///  - 验证码：无人值守时不静默失败，通过 [captchaHandler] 上抛给 UI；返回 null 视为放弃。
library;

import 'dart:async';

import 'package:zf_academic/zf_academic_io.dart';

import 'backends.dart';
import 'school.dart';
import 'session_repository.dart';

/// 无人值守时对验证码的默认处理：直接放弃，抛错让上层提示。
Future<String?> _defaultCaptchaHandler(CaptchaState state) async => null;

class ScheduleService {
  ScheduleService({
    required this.credentials,
    required this.cookieStorage,
    this.captchaHandler = _defaultCaptchaHandler,
    this.autoLoginLimit = 2,
    this.autoLoginWindow = const Duration(minutes: 10),
    this.backendFactory = defaultBackendFactory,
    String? baseUrl,
  }) : _baseUrl = baseUrl ?? defaultSchool.baseUrl;

  /// 客户端工厂（测试注入假实现）。
  final ScheduleBackend Function(ZfClientConfig config) backendFactory;

  /// 账密来源（安全存储）。回退登录的原料。
  final CredentialStore credentials;

  /// Cookie 快照持久化。非 final：app 启动拿到目录后 [rebindCookieStorage] 替换。
  SessionRepository cookieStorage;

  /// 需要验证码时调用；返回用户输入的码，null 表示放弃。
  /// 非 final：app 启动后再接线（handler 需要引用 UI 状态机）。
  Future<String?> Function(CaptchaState state) captchaHandler;

  /// 阶段回调：`relogin` 表示正在用保存的账密重新登录。
  /// UI 用它把"正在更新课表"换成"正在重新登录"，但不遮挡页面。
  void Function(String stage)? onStage;

  static const String stageRelogin = 'relogin';

  /// 熔断窗口内允许的自动登录次数。
  final int autoLoginLimit;

  /// 熔断窗口。
  final Duration autoLoginWindow;

  String _baseUrl;

  /// 上次登录的账号（由 app 从设置里恢复后传入）。
  ///
  /// 凭据按「地址|账号」存，账号必须能算出来；而免登冷启动时
  /// `sessionInfo.username` 是空的（身份还没从网络读回来），
  /// 只靠它拼 key 就会取不到保存的密码，Cookie 失效后无法自动重登。
  String? accountHint;

  ScheduleBackend? _client;

  /// 单 flight：进行中的取课表任务。
  Future<Schedule>? _inFlight;

  /// 自动登录时间戳（熔断判定用）。
  final List<DateTime> _autoLogins = <DateTime>[];

  /// 熔断是否已打开（需要用户手动登录一次来解除）。
  bool _breakerOpen = false;

  bool get breakerOpen => _breakerOpen;

  String get baseUrl => _baseUrl;

  SessionInfo? get sessionInfo => _client?.session;

  /// 客户端是否已持有会话 Cookie（不保证有效，只保证"有凭据可试"）。
  bool get hasCookies => (_client?.cookieHeader.isNotEmpty ?? false);

  /// 当前会话的 Cookie 头。**仅供调试页解析名字**，不要写进日志或发到远端。
  String get cookieHeaderForDebug => _client?.cookieHeader ?? '';

  /// 最近若干条请求记录（调试页用）。只存元数据，不含 Cookie 值与请求体。
  final List<RequestLog> requestLog = <RequestLog>[];

  static const int _requestLogLimit = 120;

  /// 最近一次课表查询的原始响应文本（未解析）。
  String? get lastScheduleRawBody => _client?.lastScheduleRawBody;

  /// 最近一次课表查询解析出的 kbList 原始行。
  List<Map<String, dynamic>> get lastScheduleRows =>
      _client?.lastScheduleRows ?? const <Map<String, dynamic>>[];

  /// 最近一次学期列表查询的原始页面。
  String? get lastTermsRawBody => _client?.lastTermsRawBody;

  // -------------------------------------------------------------------------
  // 生命周期
  // -------------------------------------------------------------------------

  /// 释放底层传输。之后本实例不再可用。
  void dispose() {
    _client?.close();
    _client = null;
  }

  /// 用户换了学校：丢掉旧客户端与旧 Cookie（快照与主机绑定，不能跨校复用）。
  void switchSchool(String baseUrl) {
    if (sameSchool(_baseUrl, baseUrl)) return;
    _baseUrl = baseUrl;
    _client?.close();
    _client = null;
    _inFlight = null;
    _breakerOpen = false;
    _autoLogins.clear();
    // 换了学校就不能沿用上一个学校的账号，等 app 恢复目标学校的账号。
    accountHint = null;
  }

  /// 替换 Cookie 持久化目标（app 启动：path_provider 目录就绪后调用）。
  void rebindCookieStorage(SessionRepository storage) {
    cookieStorage = storage;
  }

  // -------------------------------------------------------------------------
  // 学期列表（课表页的学期切换器）
  // -------------------------------------------------------------------------

  /// 取学期列表。与取课表共用同一个客户端；失效时同样走回退登录。
  Future<Terms> fetchTerms() async {
    final client = await _ensureClient();
    try {
      return await client.fetchTerms();
    } on AcademicError catch (error) {
      if (error.code != ErrorCode.sessionExpired) rethrow;
    }
    await _reloginOnly();
    return (await _ensureClient()).fetchTerms();
  }

  /// 只做回退登录（不重试原请求），供 [fetchTerms] 使用。
  Future<void> _reloginOnly() async {
    final saved = await credentials.get(_accountKey());
    if (saved == null) {
      throw AcademicError(ErrorCode.sessionExpired, '会话已过期，且没有保存账号密码，请重新登录');
    }
    if (_breakerOpen || !_autoLoginAllowed()) {
      throw AcademicError(
        ErrorCode.sessionExpired,
        '自动登录次数过多（可能是账号密码已变更），请手动登录',
      );
    }
    _recordAutoLogin();
    final client = await _ensureClient();
    final rollback = client.exportCookies();
    try {
      final state = await client.login(saved);
      if (state is! AuthenticatedState) {
        _restore(client, rollback);
        throw AcademicError(
          ErrorCode.sessionExpired,
          '自动登录未完成（${state.runtimeType}）',
        );
      }
    } catch (_) {
      _restore(client, rollback);
      rethrow;
    }
    await _persist(client);
    // 注意：这里不重置熔断——只有手动登录才重置。
    // 若在此清零，"重登成功但请求仍失败"就会无限自动重登，学校侧会计失败次数。
  }

  // -------------------------------------------------------------------------
  // 入口一：启动时恢复会话（需求 1）
  // -------------------------------------------------------------------------

  /// 启动调用：有可用快照就返回它（调用方接着 [getSchedule] 试），没有返回 null。
  ///
  /// 换校后的旧快照会被丢弃（baseUrl 不匹配），并清掉磁盘文件，避免下次再读到。
  Future<CookieStoreSnapshot?> bootstrap() async {
    final snapshot = await cookieStorage.load();
    if (snapshot == null) return null;
    if (!sameSchool(snapshot.baseUrl, _baseUrl)) {
      await cookieStorage.clear();
      return null;
    }
    if (snapshot.cookies.isEmpty) {
      await cookieStorage.clear();
      return null;
    }
    return snapshot;
  }

  // -------------------------------------------------------------------------
  // 入口二：取课表（Cookie 优先，失效回退登录——需求 2）
  // -------------------------------------------------------------------------

  /// 取课表。并发调用共享同一次任务（单 flight）。
  Future<Schedule> getSchedule({String? termId}) {
    final pending = _inFlight;
    if (pending != null) return pending;
    final task = _getScheduleOnce(termId: termId);
    _inFlight = task;
    return task.whenComplete(() {
      if (_inFlight == task) _inFlight = null;
    });
  }

  Future<Schedule> _getScheduleOnce({String? termId}) async {
    final client = await _ensureClient();
    try {
      return await client.fetchSchedule(termId);
    } on AcademicError catch (error) {
      if (error.code != ErrorCode.sessionExpired) rethrow;
    }
    // 走到这里：Cookie 失效。回退到账密登录。
    return _reloginAndRetry(termId: termId);
  }

  Future<Schedule> _reloginAndRetry({String? termId}) async {
    final client = await _ensureClient();
    final accountKey = _accountKey();
    final saved = await credentials.get(accountKey);
    if (saved == null) {
      throw AcademicError(ErrorCode.sessionExpired, '会话已过期，且没有保存账号密码，请重新登录');
    }
    if (_breakerOpen || !_autoLoginAllowed()) {
      throw AcademicError(
        ErrorCode.sessionExpired,
        '自动登录次数过多（可能是账号密码已变更），请手动登录',
      );
    }
    _recordAutoLogin();
    onStage?.call(stageRelogin);

    // 回滚点：ZhengfangClient.login() 入口会作废旧 Cookie，失败时恢复它，
    // 否则一次不成功的重登会把"会话过期"恶化成"彻底掉登录"。
    final rollback = client.exportCookies();
    AuthState state;
    try {
      state = await client.login(saved);
    } catch (_) {
      _restore(client, rollback);
      rethrow;
    }

    // 验证码 / 网页验证：无人值守时上抛给调用方处理，不当作普通失败。
    if (state is CaptchaState) {
      final code = await captchaHandler(state);
      if (code == null) {
        _restore(client, rollback);
        throw AcademicError(ErrorCode.captchaRequired, '需要验证码，已取消自动登录');
      }
      try {
        state = await client.submitCaptcha(code);
      } catch (_) {
        _restore(client, rollback);
        rethrow;
      }
    }
    if (state is WebLoginState) {
      _restore(client, rollback);
      throw AcademicError(ErrorCode.webLoginRequired, '学校要求先完成网页统一认证，暂不支持自动登录');
    }
    if (state is! AuthenticatedState) {
      _restore(client, rollback);
      throw AcademicError(
        ErrorCode.sessionExpired,
        '自动登录未完成（${state.runtimeType}）',
      );
    }

    await _persist(client);
    // 不在此重置熔断：自动登录次数必须跨轮次累计（见 _recordAutoLogin）。

    // 重登后只重试一次，不循环。
    try {
      return await client.fetchSchedule(termId);
    } catch (_) {
      _restore(client, rollback);
      rethrow;
    }
  }

  // -------------------------------------------------------------------------
  // 入口三：手动登录（设置页 / 重登失败后）
  // -------------------------------------------------------------------------

  /// 用账号密码登录。[remember] 为 true 时把凭据写入安全存储。
  ///
  /// 返回登录结果：验证码状态下调用方应展示验证码页并调用 [submitCaptcha]。
  Future<AuthState> signIn(
    String username,
    String password, {
    bool remember = true,
  }) async {
    final client = await _ensureClient();
    final state = await client.login(Credentials(username, password));
    if (state is AuthenticatedState) {
      // 记下账号：后续所有凭据读写都靠它拼 key。
      accountHint = username;
      if (remember) {
        await credentials.save(
          _accountKey(username: username),
          Credentials(username, password),
        );
      }
      await _persist(client);
      resetBreaker();
    }
    return state;
  }

  /// 提交验证码（登录流程的续期）。沿用最近一次登录挑战。
  Future<AuthState> submitCaptcha(String code) async {
    final client = await _ensureClient();
    final state = await client.submitCaptcha(code);
    if (state is AuthenticatedState) {
      await _persist(client);
      resetBreaker();
    }
    return state;
  }

  /// 换一张验证码。
  Future<CaptchaState> refreshCaptcha() async {
    final client = await _ensureClient();
    return client.refreshCaptcha();
  }

  /// 用 Cookie 恢复会话后补齐身份信息。
  ///
  /// 课表接口不返回"我是谁"，所以冷启动免登时 `sessionInfo` 里的姓名学号是空的。
  /// 失败不影响课表，静默忽略即可。
  Future<void> ensureIdentity() async {
    final client = _client;
    if (client == null) return;
    if (client.session.authenticated) return;
    try {
      await client.checkSession();
    } catch (_) {
      // 读不到身份不是错误：课表已经拿到了。
    }
  }

  /// 退出登录：清 Cookie 快照与保存的凭据。
  ///
  /// 默认连凭据一起清（UI 只有一个"退出登录"）：这个 app 的密码只为自动重登
  /// 存在，用户主动退出通常意味着"别再自动登了"。
  Future<void> signOut({bool forgetCredentials = true}) async {
    // 先算 key：关掉客户端后 sessionInfo 就取不到用户名了。
    final key = _accountKey();
    final keyByName = _accountKey(username: sessionInfo?.username ?? '');
    _client?.close();
    _client = null;
    _inFlight = null;
    accountHint = null;
    await cookieStorage.clear();
    if (forgetCredentials) {
      await credentials.remove(key);
      if (keyByName != key) await credentials.remove(keyByName);
    }
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  String _accountKey({String? username}) {
    // accountKey 只用"地址 + 账号"：同一账号换学校不共享凭据。
    // 账号的优先级：显式传入 > app 恢复的本地账号 > 当前会话里的用户名。
    final base = _baseUrl.toLowerCase();
    final account = username ?? accountHint ?? sessionInfo?.username ?? '';
    return '$base|$account';
  }

  Future<ScheduleBackend> _ensureClient() async {
    final existing = _client;
    if (existing != null) return existing;
    final snapshot = await bootstrap();
    final client = backendFactory(
      ZfClientConfig(
        baseUrl: _baseUrl,
        cookies: snapshot,
        onRequest: _recordRequest,
      ),
    );
    _client = client;
    return client;
  }

  Future<void> _persist(ScheduleBackend client) async {
    await cookieStorage.save(client.exportCookies());
  }

  /// 恢复旧 Cookie（重登失败的回滚）。快照作废后 generation 会变，上层回调据此丢弃。
  void _restore(ScheduleBackend client, CookieStoreSnapshot snapshot) {
    if (snapshot.cookies.isEmpty) return;
    client.importCookies(snapshot);
  }

  /// 窗口内的自动登录是否还允许。超限时打开熔断并返回 false。
  bool _autoLoginAllowed() {
    final now = DateTime.now();
    _autoLogins.removeWhere((at) => now.difference(at) > autoLoginWindow);
    if (_autoLogins.length >= autoLoginLimit) {
      _breakerOpen = true;
      return false;
    }
    return true;
  }

  void _recordAutoLogin() => _autoLogins.add(DateTime.now());

  void _recordRequest(RequestLog info) {
    requestLog.add(info);
    if (requestLog.length > _requestLogLimit) {
      requestLog.removeRange(0, requestLog.length - _requestLogLimit);
    }
  }

  /// 手动登录成功后解除熔断。
  void resetBreaker() {
    _breakerOpen = false;
    _autoLogins.clear();
  }
}
