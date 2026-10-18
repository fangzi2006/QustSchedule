/// 客户端门面：把 `ZhengfangClient` 收窄成编排层真正用到的能力。
///
/// 存在的理由只有一个——可测试性。`ZhengfangClient` 用 factory 构造、
/// 内部直接持有 HTTP 客户端，测试里无法替换；编排层的单 flight / 熔断 /
/// 回滚逻辑又必须被确定性验证，所以在这里定义一个窄接口。
///
/// 生产环境用 [ZfBackend] 转发到真客户端；测试注入假实现。
library;

import 'package:zf_academic/zf_academic_io.dart';

abstract class ScheduleBackend {
  Future<Schedule> fetchSchedule([String? termId]);

  Future<Terms> fetchTerms();

  Future<AuthState> login(Credentials credentials);

  Future<AuthState> submitCaptcha(String code);

  Future<CaptchaState> refreshCaptcha();

  /// 读一次会话/身份信息。
  ///
  /// 用 Cookie 免登时客户端不知道"我是谁"，课表能取但设置页会显示未登录；
  /// 这个调用负责补齐。
  Future<SessionState> checkSession();

  CookieStoreSnapshot exportCookies();

  void importCookies(CookieStoreSnapshot snapshot);

  SessionInfo get session;

  String get cookieHeader;

  /// 最近一次课表查询的原始响应文本（调试用，未解析）。
  String? get lastScheduleRawBody;

  /// 最近一次课表查询解析出的 kbList 原始行（字段未归一化）。
  List<Map<String, dynamic>> get lastScheduleRows;

  /// 最近一次学期列表查询的原始页面。
  String? get lastTermsRawBody;

  void close();
}

/// 转发到真实的 `ZhengfangClient`（dart:io 传输层）。
class ZfBackend implements ScheduleBackend {
  ZfBackend(this._client);

  final ZhengfangClient _client;

  @override
  Future<Schedule> fetchSchedule([String? termId]) =>
      _client.fetchSchedule(termId);

  @override
  Future<Terms> fetchTerms() => _client.fetchTerms();

  @override
  Future<AuthState> login(Credentials credentials) =>
      _client.login(credentials);

  @override
  Future<AuthState> submitCaptcha(String code) => _client.submitCaptcha(code);

  @override
  Future<CaptchaState> refreshCaptcha() => _client.refreshCaptcha();

  @override
  Future<SessionState> checkSession() => _client.checkSession();

  @override
  CookieStoreSnapshot exportCookies() => _client.exportCookies();

  @override
  void importCookies(CookieStoreSnapshot snapshot) =>
      _client.importCookies(snapshot);

  @override
  SessionInfo get session => _client.session;

  @override
  String get cookieHeader => _client.cookieHeader;

  @override
  String? get lastScheduleRawBody => _client.lastScheduleRawBody;

  @override
  List<Map<String, dynamic>> get lastScheduleRows => _client.lastScheduleRows;

  @override
  String? get lastTermsRawBody => _client.lastTermsRawBody;

  @override
  void close() => _client.close();
}

/// 生产默认工厂：带 dart:io 传输层的真客户端。
ScheduleBackend defaultBackendFactory(ZfClientConfig config) =>
    ZfBackend(vmZhengfangClient(config));
