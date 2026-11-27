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
///  - 单 flight + 会话版本号：并发遇失效合并为单次重登，慢半拍旧请求检测到版本号已升级时直接用新会话重试，不重复重登；
///  - 回滚边界：仅重登动作本身失败时恢复旧 Cookie；重登成功持久化后，后续业务重试失败绝不回滚成过期旧 Cookie；
///  - 精细熔断：仅真实认证失败计次（密码错立刻熔断防锁号；其余真认证失败默认 10 分钟 3 次；一切网络/超时/劫持/维护/取消验证码永不计次）；
///  - 可见/静默阶段解耦：仅当至少存在一个需要进度反馈的任务等待重登时广播 `relogin`，重登结束统一广播 `relogin_finished` 自己摘牌；
///  - 验证码：无人值守时不静默失败，通过 [captchaHandler] 上抛给 UI；返回 null 视为放弃且不扣熔断次数。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
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
    this.autoLoginLimit = 3,
    this.autoLoginWindow = const Duration(minutes: 10),
    this.backendFactory = defaultBackendFactory,
    this.paceHosts = defaultAcademicPaceHosts,
    String? baseUrl,
  }) : _baseUrl = baseUrl ?? defaultSchool.baseUrl;

  /// 客户端工厂（测试注入假实现）。
  final ScheduleBackend Function(ZfClientConfig config) backendFactory;

  /// 按主机名配置的最小请求间隔（毫秒）。
  final Map<String, int> paceHosts;

  /// 账密来源（安全存储）。回退登录的原料。
  final CredentialStore credentials;

  /// Cookie 快照持久化。非 final：app 启动拿到目录后 [rebindCookieStorage] 替换。
  SessionRepository cookieStorage;

  /// 需要验证码时调用；返回用户输入的码，null 表示放弃。
  /// 非 final：app 启动后再接线（handler 需要引用 UI 状态机）。
  Future<String?> Function(CaptchaState state) captchaHandler;

  /// 阶段回调：
  /// - `relogin`：存在需要展示进度的任务等待自动重登；
  /// - `relogin_finished`：前述已亮牌的自动重登结束（成功或失败均由网关自行摘牌）；
  /// - `fetching_schedule`：课表自动重登成功，正在重新抓取课表。
  void Function(String stage)? onStage;

  static const String stageRelogin = 'relogin';
  static const String stageReloginFinished = 'relogin_finished';
  static const String stageFetchingSchedule = 'fetching_schedule';

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
  Future<ScheduleBackend>? _clientFlight;

  /// 单 flight：进行中的取课表任务。
  Future<Schedule>? _inFlight;

  /// 登录遇到验证码时暂存本次凭据，待验证码提交成功后按用户意愿持久化。
  ({Credentials credentials, bool remember})? _pendingSignIn;

  /// 自动登录失败时间戳（熔断判定用；仅记录有效认证失败与重登后立即再过期）。
  final List<DateTime> _autoLoginFailures = <DateTime>[];

  /// 自动重登完成世代号（用于同轮并发请求共享重登后的即时失效去重计次）。
  int _reloginEpoch = 0;
  int _lastFailureRecordedReloginEpoch = -1;

  /// 会话凭证版本号：每次登录成功、切校或退出递增；
  /// 慢半拍并发请求返回 sessionExpired 时若检测到版本号已前进，直接复用新凭证重试而不再发起二次重登。
  int _sessionVersion = 0;

  /// 当前在途自动重登是否已向 UI 广播过 `stageRelogin`。
  bool _reloginStageNotified = false;

  /// 熔断是否已打开（需要用户手动登录一次来解除）。
  bool _breakerOpen = false;

  bool get breakerOpen => _breakerOpen;

  String get baseUrl => _baseUrl;

  SessionInfo? get sessionInfo => _client?.session;

  /// 客户端是否已持有会话 Cookie（不保证有效，只保证"有凭据可试"）。
  bool get hasCookies => (_client?.cookieHeader.isNotEmpty ?? false);

  /// 当前会话的 Cookie 头。**仅供调试页解析名字**，不要写进日志或发到远端。
  String get cookieHeaderForDebug => _client?.cookieHeader ?? '';

  /// 导出当前内存客户端持有的 Cookie 快照（不触碰磁盘；未建客户端或无 Cookie 时返回 null）。
  CookieStoreSnapshot? exportCurrentCookies() {
    final client = _client;
    if (client == null) return null;
    final snapshot = client.exportCookies();
    if (snapshot.cookies.isEmpty) return null;
    return snapshot;
  }

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
    _clientFlight = null;
    _inFlight = null;
    _reloginFlight = null;
    _reloginStageNotified = false;
    _sessionVersion++;
  }

  /// 用户换了学校：丢掉旧客户端与旧 Cookie（快照与主机绑定，不能跨校复用）。
  void switchSchool(String baseUrl) {
    if (sameSchool(_baseUrl, baseUrl)) {
      _baseUrl = baseUrl;
      return;
    }
    _baseUrl = baseUrl;
    _client?.close();
    _client = null;
    _clientFlight = null;
    _inFlight = null;
    _reloginFlight = null;
    _reloginStageNotified = false;
    _sessionVersion++;
    _breakerOpen = false;
    _autoLoginFailures.clear();
    _lastFailureRecordedReloginEpoch = -1;
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
  Future<Terms> fetchTerms({bool reportReloginStage = true}) =>
      _runWithReloginRetry(
        (client) => client.fetchTerms(),
        reportReloginStage: reportReloginStage,
      );

  /// 取考试安排。与取课表共用同一个客户端；失效时同样走回退登录。
  Future<List<ExamItem>> fetchExams([
    String? termId,
    bool reportReloginStage = true,
  ]) => _runWithReloginRetry(
    (client) => client.fetchExams(termId),
    reportReloginStage: reportReloginStage,
  );

  /// 取成绩明细。与取课表共用同一个客户端；失效时同样走回退登录。
  Future<List<GradeItem>> fetchGrades([
    String? termId,
    bool reportReloginStage = true,
  ]) => _runWithReloginRetry(
    (client) => client.fetchGrades(termId),
    reportReloginStage: reportReloginStage,
  );

  void _promoteReloginStageIfNeeded(bool reportReloginStage) {
    if (!reportReloginStage || _reloginStageNotified) return;
    _reloginStageNotified = true;
    onStage?.call(stageRelogin);
  }

  Future<T> _runWithReloginRetry<T>(
    Future<T> Function(ScheduleBackend client) run, {
    bool reportReloginStage = true,
    VoidCallback? onAfterReloginBeforeRetry,
  }) async {
    final waitedOnEntry = _reloginFlight != null;
    await _waitForRelogin(reportReloginStage: reportReloginStage);
    if (waitedOnEntry) {
      onAfterReloginBeforeRetry?.call();
    }
    final versionAtStart = _sessionVersion;
    final client = await _ensureClient();
    try {
      return await run(client);
    } on AcademicError catch (error) {
      if (error.code != ErrorCode.sessionExpired) rethrow;
    }

    int reloginEpoch;
    if (_sessionVersion != versionAtStart) {
      // 并发时间差防重复重登：出发后已有其他任务完成重登并更新会话版本号，
      // 直接等待可能存在的新一轮重登后拿现成新凭证重试 1 次，绝不发起二次重登。
      await _waitForRelogin(reportReloginStage: reportReloginStage);
      reloginEpoch = _reloginEpoch;
    } else {
      reloginEpoch = await _reloginWithSavedCredentials(
        reportReloginStage: reportReloginStage,
      );
    }
    onAfterReloginBeforeRetry?.call();

    // 重登后只重试一次，不循环。
    try {
      final result = await run(await _ensureClient());
      _onReloginRetrySucceeded();
      return result;
    } on AcademicError catch (error) {
      if (error.code == ErrorCode.sessionExpired) {
        _recordReloginPostRetryExpired(reloginEpoch);
      }
      rethrow;
    }
  }

  Future<int>? _reloginFlight;

  Future<void>? get reloginFlight => _reloginFlight;

  @visibleForTesting
  Future<void>? get reloginFlightForTest => _reloginFlight;

  /// 等待当前正在进行的回退登录（若有）。
  ///
  /// 确保重登期间为全局阻塞式，防止一边登录一边发出业务查询请求；
  /// 若有需要展示进度的任务加入等待，立即升格广播 `stageRelogin`；
  /// 若重登失败，向等待方传递错误，防止使用失效凭据盲目重发请求。
  Future<void> _waitForRelogin({bool reportReloginStage = false}) {
    final pending = _reloginFlight;
    if (pending != null) {
      _promoteReloginStageIfNeeded(reportReloginStage);
      return pending;
    }
    return Future.value();
  }

  /// 全局阻塞式回退登录。
  ///
  /// 无论是取课表、学期、考试还是成绩遇会话过期，均共用同一单 flight 登录任务。
  /// 并发请求合并为单次登录，避免多次重复并发登录与重复扣减熔断额度；
  /// 若本次重登曾向 UI 亮牌，结束时由网关自己广播 `stageReloginFinished` 摘牌。
  Future<int> _reloginWithSavedCredentials({bool reportReloginStage = true}) {
    final pending = _reloginFlight;
    if (pending != null) {
      _promoteReloginStageIfNeeded(reportReloginStage);
      return pending;
    }
    _reloginStageNotified = false;
    _promoteReloginStageIfNeeded(reportReloginStage);
    final task = _loginWithSavedCredentials();
    _reloginFlight = task;
    return task.whenComplete(() {
      if (_reloginFlight == task) {
        _reloginFlight = null;
        if (_reloginStageNotified) {
          _reloginStageNotified = false;
          onStage?.call(stageReloginFinished);
        }
      }
    });
  }

  Future<int> _loginWithSavedCredentials() async {
    final client = await _ensureClient();
    final saved = await readSavedCredentials();
    if (saved == null) {
      throw AcademicError(ErrorCode.sessionExpired, '会话已过期，且没有保存账号密码，请重新登录');
    }
    if (_breakerOpen || !_autoLoginAllowed()) {
      throw AcademicError(
        ErrorCode.sessionExpired,
        '自动登录次数过多（可能是账号密码已变更），请手动登录',
      );
    }

    // 回滚点：ZhengfangClient.login() 入口会作废旧 Cookie，仅登录本身失败时恢复它，
    // 否则一次不成功的重登会把"会话过期"恶化成"彻底掉登录"。
    final rollback = client.exportCookies();
    AuthState state;
    try {
      state = await client.login(saved);
    } catch (error) {
      _restore(client, rollback);
      _recordAutoLoginFailure(error);
      rethrow;
    }

    // 验证码 / 网页验证：用户在验证码页主动取消不扣熔断次数。
    if (state is CaptchaState) {
      final code = await captchaHandler(state);
      if (code == null) {
        _restore(client, rollback);
        throw AcademicError(ErrorCode.captchaRequired, '需要验证码，已取消自动登录');
      }
      try {
        state = await client.submitCaptcha(code);
      } catch (error) {
        _restore(client, rollback);
        _recordAutoLoginFailure(error);
        rethrow;
      }
    }
    if (state is WebLoginState) {
      _restore(client, rollback);
      _autoLoginFailures.add(DateTime.now());
      throw AcademicError(
        ErrorCode.webLoginRequired,
        '教务系统要求先完成网页统一认证，暂不支持自动登录',
      );
    }
    if (state is! AuthenticatedState) {
      _restore(client, rollback);
      _autoLoginFailures.add(DateTime.now());
      throw AcademicError(
        ErrorCode.sessionExpired,
        '自动登录未完成（${state.runtimeType}）',
      );
    }

    if (_client != client) {
      throw const AcademicError(ErrorCode.sessionExpired, '登录已取消或客户端已重置');
    }

    await _persist(client);
    _sessionVersion++;
    return ++_reloginEpoch;
  }

  // -------------------------------------------------------------------------
  // 入口一：启动时恢复会话（需求 1）
  // -------------------------------------------------------------------------

  /// 启动调用：有可用快照就返回它（调用方接着 [getSchedule] 试），没有返回 null。
  ///
  /// 换地址后的旧快照会被丢弃（baseUrl 不匹配），并清掉磁盘文件，避免下次再读到。
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
  Future<Schedule> getSchedule({
    String? termId,
    bool reportReloginStage = true,
  }) {
    final pending = _inFlight;
    if (pending != null) {
      if (_reloginFlight != null) {
        _promoteReloginStageIfNeeded(reportReloginStage);
      }
      return pending;
    }
    final task = _getScheduleOnce(
      termId: termId,
      reportReloginStage: reportReloginStage,
    );
    _inFlight = task;
    return task.whenComplete(() {
      if (_inFlight == task) _inFlight = null;
    });
  }

  Future<Schedule> _getScheduleOnce({
    String? termId,
    bool reportReloginStage = true,
  }) => _runWithReloginRetry(
    (client) => client.fetchSchedule(termId),
    reportReloginStage: reportReloginStage,
    onAfterReloginBeforeRetry: reportReloginStage
        ? () => onStage?.call(stageFetchingSchedule)
        : null,
  );

  // -------------------------------------------------------------------------
  // 入口三：手动登录（设置页 / 重登失败后）
  // -------------------------------------------------------------------------

  Future<void> _saveAuthenticatedSignIn(
    ScheduleBackend client,
    Credentials creds,
    bool remember,
  ) async {
    // 记下账号：后续所有凭据读写都靠它拼 key。
    accountHint = creds.username;
    if (remember) {
      await credentials.save(_accountKey(username: creds.username), creds);
    }
    await _persist(client);
    _sessionVersion++;
    resetBreaker();
  }

  /// 用账号密码登录。[remember] 为 true 时把凭据写入安全存储。
  ///
  /// 返回登录结果：验证码状态下调用方应展示验证码页并调用 [submitCaptcha]。
  Future<AuthState> signIn(
    String username,
    String password, {
    bool remember = true,
  }) async {
    try {
      await _waitForRelogin();
    } catch (_) {}
    final creds = Credentials(username, password);
    _pendingSignIn = null;
    // 登录入口本身会作废内存 Cookie，跳过 bootstrap 避免切校试登阶段误删磁盘上原校 Cookie 快照。
    final client = await _ensureClient(loadCookies: false);
    final state = await client.login(creds);
    if (state is AuthenticatedState) {
      await _saveAuthenticatedSignIn(client, creds, remember);
    } else if (state is CaptchaState) {
      _pendingSignIn = (credentials: creds, remember: remember);
    }
    return state;
  }

  /// 提交验证码（登录流程的续期）。沿用最近一次登录挑战。
  Future<AuthState> submitCaptcha(String code) async {
    final client = await _ensureClient();
    final state = await client.submitCaptcha(code);
    if (state is AuthenticatedState) {
      final pending = _pendingSignIn;
      _pendingSignIn = null;
      if (pending != null) {
        await _saveAuthenticatedSignIn(
          client,
          pending.credentials,
          pending.remember,
        );
      } else {
        await _persist(client);
        _sessionVersion++;
        resetBreaker();
      }
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
    await _waitForRelogin();
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
    final fallbackKeys = _fallbackAccountKeys();
    final fallbackKeysByName = _fallbackAccountKeys(
      username: sessionInfo?.username ?? '',
    );
    _client?.close();
    _client = null;
    _clientFlight = null;
    _inFlight = null;
    _reloginFlight = null;
    _reloginStageNotified = false;
    _sessionVersion++;
    _pendingSignIn = null;
    accountHint = null;
    await cookieStorage.clear();
    if (forgetCredentials) {
      final keysToRemove = <String>{
        key,
        keyByName,
        ...fallbackKeys,
        ...fallbackKeysByName,
      };
      for (final targetKey in keysToRemove) {
        await credentials.remove(targetKey);
      }
    }
  }

  /// 读取当前学校与账号保存的凭据；若规范化键未命中，依次回退兼容协议切换与历史末尾斜杠键。
  Future<Credentials?> readSavedCredentials({String? username}) async {
    final canonicalKey = _accountKey(username: username);
    final direct = await credentials.get(canonicalKey);
    if (direct != null) return direct;
    for (final fallbackKey in _fallbackAccountKeys(username: username)) {
      final fallback = await credentials.get(fallbackKey);
      if (fallback != null) return fallback;
    }
    return null;
  }

  // -------------------------------------------------------------------------
  // 内部
  // -------------------------------------------------------------------------

  String _accountKey({String? username}) {
    // accountKey 只用"地址 + 账号"：同一账号换学校不共享凭据。
    // 账号的优先级：显式传入 > app 恢复的本地账号 > 当前会话里的用户名。
    final account = username ?? accountHint ?? sessionInfo?.username ?? '';
    return buildAccountKey(_baseUrl, account);
  }

  List<String> _fallbackAccountKeys({String? username}) {
    final account = username ?? accountHint ?? sessionInfo?.username ?? '';
    final normalizedBase = normalizeSchoolKeyUrl(_baseUrl);
    if (normalizedBase.isEmpty) return const <String>[];
    final canonicalKey = buildAccountKey(_baseUrl, account);
    final String? alternateBase;
    if (normalizedBase.startsWith('https://')) {
      alternateBase = 'http://${normalizedBase.substring('https://'.length)}';
    } else if (normalizedBase.startsWith('http://')) {
      alternateBase = 'https://${normalizedBase.substring('http://'.length)}';
    } else {
      alternateBase = null;
    }
    final candidates = <String>[
      if (alternateBase != null && alternateBase.isNotEmpty)
        '$alternateBase|$account',
      '$normalizedBase/|$account',
      if (alternateBase != null && alternateBase.isNotEmpty)
        '$alternateBase/|$account',
    ];
    final result = <String>[];
    for (final key in candidates) {
      if (key != canonicalKey && !result.contains(key)) {
        result.add(key);
      }
    }
    return result;
  }

  Future<ScheduleBackend> _ensureClient({bool loadCookies = true}) {
    final existing = _client;
    if (existing != null) return Future.value(existing);
    final pending = _clientFlight;
    if (pending != null) return pending;
    final task = _createClient(loadCookies: loadCookies);
    _clientFlight = task;
    return task.whenComplete(() {
      if (_clientFlight == task) _clientFlight = null;
    });
  }

  Future<ScheduleBackend> _createClient({bool loadCookies = true}) async {
    final snapshot = loadCookies ? await bootstrap() : null;
    final client = backendFactory(
      ZfClientConfig(
        baseUrl: _baseUrl,
        endpoints: qustZfEndpoints,
        cookies: snapshot,
        requestTimeoutMs: 10000,
        paceHosts: paceHosts,
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
    _autoLoginFailures.removeWhere(
      (at) => now.difference(at) > autoLoginWindow,
    );
    if (_autoLoginFailures.length >= autoLoginLimit) {
      _breakerOpen = true;
      return false;
    }
    return true;
  }

  static bool _isRealAuthFailure(AcademicError error) {
    return const <ErrorCode>{
      ErrorCode.captchaRequired,
      ErrorCode.webLoginRequired,
    }.contains(error.code);
  }

  /// 仅对真实登录/认证失败计次：
  /// - 密码错误（invalidCredentials）立刻熔断防锁号；
  /// - 验证码校验失败/统一认证拦截计入 10 分钟窗口；
  /// - 一切网络/超时/5xx/403/劫持/页面残缺/验证无法确认/取消永不计次。
  void _recordAutoLoginFailure(Object error) {
    final academic = asAcademicError(error);
    if (academic.code == ErrorCode.invalidCredentials) {
      _breakerOpen = true;
      return;
    }
    if (_isRealAuthFailure(academic)) {
      _autoLoginFailures.add(DateTime.now());
    }
  }

  /// 自动重登刚成功、紧接着的业务重试仍报 sessionExpired 时记 1 次（按重登世代去重）。
  void _recordReloginPostRetryExpired(int reloginEpoch) {
    if (reloginEpoch <= 0 || _lastFailureRecordedReloginEpoch == reloginEpoch) {
      return;
    }
    _lastFailureRecordedReloginEpoch = reloginEpoch;
    _autoLoginFailures.add(DateTime.now());
  }

  /// 自动重登且紧接着的业务请求成功拿到数据，清空窗口内历史失败计数。
  void _onReloginRetrySucceeded() {
    if (!_breakerOpen) {
      _autoLoginFailures.clear();
    }
  }

  void _recordRequest(RequestLog info) {
    requestLog.add(info);
    if (requestLog.length > _requestLogLimit) {
      requestLog.removeRange(0, requestLog.length - _requestLogLimit);
    }
  }

  /// 手动登录成功后解除熔断。
  void resetBreaker() {
    _breakerOpen = false;
    _autoLoginFailures.clear();
    _lastFailureRecordedReloginEpoch = -1;
  }
}
