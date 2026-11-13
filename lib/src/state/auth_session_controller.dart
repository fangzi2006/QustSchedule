/// 登录会话、账号身份缓存、验证码挂起、切换教务线路与调试日志控制器。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zf_academic/zf_academic.dart';

import '../credentials_repository.dart';
import '../schedule_service.dart';
import '../school.dart';
import '../session_repository.dart';
import 'preferences_controller.dart';

/// 管理 [ScheduleService]、当前线路地址、学生身份信息、验证码挂起与请求调试快照。
class AuthSessionController {
  AuthSessionController({
    required this._prefs,
    required this._onStateChanged,
    required this._onRouteChanged,
    ScheduleService? service,
    SessionRepository? repository,
    CredentialStore? credentials,
    String? schoolBaseUrl,
  }) : _schoolBaseUrl = schoolBaseUrl ?? defaultSchool.baseUrl,
       _schoolFixed = schoolBaseUrl != null,
       service =
           service ??
           ScheduleService(
             credentials: credentials ?? SecureCredentialStore(),
             cookieStorage: repository ?? LateSessionRepository(),
           );

  final ScheduleService service;
  final PreferencesController _prefs;
  final VoidCallback _onStateChanged;
  final VoidCallback _onRouteChanged;

  String _schoolBaseUrl;
  final bool _schoolFixed;
  String get schoolBaseUrl => _schoolBaseUrl;
  bool get isSchoolFixed => _schoolFixed;

  String _studentName = '';
  String get studentName => _studentName;

  String _studentId = '';
  String get studentId => _studentId;

  CaptchaState? _captcha;
  CaptchaState? get captcha => _captcha;

  String _username = '';
  String get username => _username;
  set username(String value) {
    _username = value;
    _onStateChanged();
  }

  Completer<String?> _captchaCompleter = Completer<String?>();
  Future<void>? _identitySync;
  bool _disposed = false;

  Future<void>? get identitySyncForTest => _identitySync;

  void setCaptcha(CaptchaState? state) {
    _captcha = state;
  }

  void setIdentity({String? studentName, String? studentId}) {
    if (studentName != null) _studentName = studentName;
    if (studentId != null) _studentId = studentId;
  }

  String accountKey({String? username}) =>
      '$_schoolBaseUrl|${username ?? _username}';

  void rebindRepository(SessionRepository repository) {
    service.rebindCookieStorage(repository);
  }

  void restoreSavedSchoolIfNeeded() {
    if (!_schoolFixed) {
      final savedSchool = _prefs.raw.currentSchool;
      if (savedSchool.isNotEmpty) _schoolBaseUrl = savedSchool;
    }
    service.switchSchool(_schoolBaseUrl);
  }

  void switchSchoolTarget(String baseUrl) {
    _schoolBaseUrl = baseUrl;
    service.switchSchool(baseUrl);
  }

  void resetIdentityFields() {
    _username = '';
    _studentId = '';
    _studentName = '';
  }

  /// 冷启动恢复「上次在这个学校登录的账号与姓名」（不联网）。
  void restoreAccount() {
    final savedAccount = _prefs.raw.accountOf(_schoolBaseUrl);
    final savedName = _prefs.raw.studentNameOf(_schoolBaseUrl);
    if (_username.isEmpty && savedAccount.isNotEmpty) {
      _username = savedAccount;
      service.accountHint = savedAccount;
    }
    if (_studentId.isEmpty && savedAccount.isNotEmpty) {
      _studentId = savedAccount;
    }
    if (_studentName.isEmpty && savedName.isNotEmpty) {
      _studentName = savedName;
    }
  }

  /// 记住这台设备在这所学校的身份（学号与姓名），供下次冷启动使用。
  Future<void> rememberIdentity({
    required String studentId,
    String studentName = '',
  }) async {
    final id = studentId.trim();
    final name = studentName.trim();
    if (id.isEmpty && name.isEmpty) return;
    if (id.isNotEmpty) {
      _username = id;
      service.accountHint = id;
      _studentId = id;
    }
    if (name.isNotEmpty) {
      _studentName = name;
    }
    await _prefs.raw.setIdentityOf(
      _schoolBaseUrl,
      studentId: id,
      studentName: name,
    );
    if (_disposed) return;
    _onStateChanged();
    _prefs.notifyPrefs();
  }

  /// 静默同步身份信息（姓名 / 学号），不阻塞课表更新与主界面。
  Future<void> syncIdentityQuietly() {
    final future = _runSyncIdentityQuietly();
    _identitySync = future;
    return future;
  }

  Future<void> _runSyncIdentityQuietly() async {
    if (_disposed) return;
    if (_studentId.isNotEmpty && _studentName.isNotEmpty) return;

    try {
      var info = service.sessionInfo;
      if (info == null || info.studentName.isEmpty || info.studentId.isEmpty) {
        await service.ensureIdentity();
        if (_disposed) return;
        info = service.sessionInfo;
      }
      var updated = false;
      if (info != null) {
        if (info.studentName.isNotEmpty && _studentName != info.studentName) {
          _studentName = info.studentName;
          updated = true;
        }
        if (info.studentId.isNotEmpty && _studentId != info.studentId) {
          _studentId = info.studentId;
          updated = true;
        }
      }
      if (_studentName.isEmpty && _studentId.isEmpty && _username.isNotEmpty) {
        _studentId = _username;
        updated = true;
      }
      if (updated ||
          (_studentName.isNotEmpty &&
              _prefs.raw.studentNameOf(_schoolBaseUrl).isEmpty)) {
        await rememberIdentity(
          studentId: _studentId.isNotEmpty ? _studentId : _username,
          studentName: _studentName,
        );
      }
    } catch (_) {
      // 身份拉取失败不影响课表展示，静默吞掉
    }
  }

  void rollbackSchool(String baseUrl) {
    if (sameSchool(_schoolBaseUrl, baseUrl)) return;
    _schoolBaseUrl = baseUrl;
    service.switchSchool(baseUrl);
    unawaited(_prefs.raw.setCurrentSchool(baseUrl));
    _prefs.notifyPrefs();
  }

  /// 自动回登遇到验证码时挂起等待用户输入。
  Future<String?> handleCaptcha(
    CaptchaState state, {
    required VoidCallback onNeedCaptcha,
  }) async {
    _captcha = state;
    _captchaCompleter = Completer<String?>();
    onNeedCaptcha();
    return _captchaCompleter.future;
  }

  bool get hasPendingReloginCaptcha => !_captchaCompleter.isCompleted;

  void completePendingCaptcha(String code) {
    if (!_captchaCompleter.isCompleted) {
      _captchaCompleter.complete(code);
    }
  }

  void cancelCaptcha({required VoidCallback onCanceled}) {
    if (!_captchaCompleter.isCompleted) _captchaCompleter.complete(null);
    _captcha = null;
    _captchaCompleter = Completer<String?>();
    onCanceled();
  }

  Future<void> refreshCaptcha() async {
    final state = await service.refreshCaptcha();
    _captcha = state;
    _onRouteChanged();
    _onStateChanged();
  }

  Future<void> signOutReset() async {
    await service.signOut(forgetCredentials: true);
    if (_disposed) return;
    await _prefs.raw.clearIdentityOf(_schoolBaseUrl);
    resetIdentityFields();
    _captcha = null;
  }

  void hydrateForTest({
    required String termId,
    required String currentScheduleTermId,
    required String studentName,
    required String studentId,
  }) {
    final bool identityChanged =
        currentScheduleTermId != termId ||
        _studentName != studentName ||
        _studentId != studentId;
    _studentName = studentName;
    _studentId = studentId;
    if (identityChanged) _prefs.notifyPrefs();
  }

  // ---------------------------------------------------------------------------
  // 调试信息
  // ---------------------------------------------------------------------------

  List<RequestLog> get requestLog => service.requestLog;
  String? get rawScheduleBody => service.lastScheduleRawBody;
  List<Map<String, dynamic>> get rawScheduleRows => service.lastScheduleRows;
  String? get rawTermsBody => service.lastTermsRawBody;

  List<String> get cookieNames {
    final header = service.cookieHeaderForDebug;
    if (header.isEmpty) return const <String>[];
    return header
        .split(';')
        .map((part) => part.split('=').first.trim())
        .where((name) => name.isNotEmpty)
        .toList();
  }

  void dispose() {
    _disposed = true;
    service.dispose();
  }
}
