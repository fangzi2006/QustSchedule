/// 全局/局部提示气泡、存储异常轻提醒与错误码文案转换。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:zf_academic/zf_academic.dart';

/// 提示气泡的页面作用域。
enum HintScope {
  /// 全局通用（如重新登录、登录中、会话失效等）。
  global,

  /// 课表专属（如课表拉取中、已更新、课表刷新失败等）。
  schedule,

  /// 学业专属（如学业刷新中、已更新、学业刷新失败等）。
  academic,
}

/// 管理右上角状态气泡、一次性存储异常提示与错误码人性化翻译。
///
/// 独立为单独的 [ChangeNotifier]，避免显示或自动消失提示时触发整页课表与外壳重建。
class HintNoticeController extends ChangeNotifier {
  String _scheduleHint = '';
  String get scheduleHint => _scheduleHint;
  bool _scheduleHintIsError = false;
  bool get scheduleHintIsError => _scheduleHintIsError;
  Timer? _scheduleHintTimer;

  String _academicHint = '';
  String get academicHint => _academicHint;
  bool _academicHintIsError = false;
  bool get academicHintIsError => _academicHintIsError;
  Timer? _academicHintTimer;

  String _globalHint = '';
  String get globalHint => _globalHint;
  bool _globalHintIsError = false;
  bool get globalHintIsError => _globalHintIsError;
  bool _isAcademicUpdateHint = false;
  Timer? _globalHintTimer;

  int _storageNoticeEvent = 0;
  int get storageNoticeEvent => _storageNoticeEvent;

  String? _storageNoticeMessage;
  String? get storageNoticeMessage => _storageNoticeMessage;

  bool _disposed = false;

  /// 当前展示的全局提示是否为学业数据更新提示。
  bool get isAcademicUpdateHint =>
      _isAcademicUpdateHint && _globalHint.isNotEmpty;

  /// 给定应用主状态，判断全局浮层是否正处于忙碌/错误/全局提示占据状态。
  bool isGlobalPopupActive({required bool isStatusBusyOrFailed}) =>
      isStatusBusyOrFailed || _globalHint.isNotEmpty;

  /// 当前处于活跃态的提示文案（优先级：全局 > 课表 > 学业）。
  String get hint {
    if (_globalHint.isNotEmpty) return _globalHint;
    if (_scheduleHint.isNotEmpty) return _scheduleHint;
    if (_academicHint.isNotEmpty) return _academicHint;
    return '';
  }

  bool get hintIsError {
    if (_globalHint.isNotEmpty) return _globalHintIsError;
    if (_scheduleHint.isNotEmpty) return _scheduleHintIsError;
    if (_academicHint.isNotEmpty) return _academicHintIsError;
    return false;
  }

  HintScope get hintScope {
    if (_globalHint.isNotEmpty) return HintScope.global;
    if (_scheduleHint.isNotEmpty) return HintScope.schedule;
    if (_academicHint.isNotEmpty) return HintScope.academic;
    return HintScope.global;
  }

  void emitStorageNotice(String message) {
    if (_disposed) return;
    _storageNoticeMessage = message;
    _storageNoticeEvent++;
    notifyListeners();
  }

  void showAcademicUpdateHint(String message) {
    showHint(
      message,
      isAcademicUpdate: true,
      scope: HintScope.global,
      clearAfter: const Duration(seconds: 2),
    );
  }

  void showHint(
    String message, {
    bool error = false,
    bool isAcademicUpdate = false,
    Duration? clearAfter,
    HintScope scope = HintScope.global,
  }) {
    if (_disposed) return;
    switch (scope) {
      case HintScope.schedule:
        _scheduleHint = message;
        _scheduleHintIsError = error;
        _scheduleHintTimer?.cancel();
        if (clearAfter != null) {
          _scheduleHintTimer = Timer(clearAfter, () {
            if (_disposed) return;
            _scheduleHint = '';
            notifyListeners();
          });
        }
        break;
      case HintScope.academic:
        _academicHint = message;
        _academicHintIsError = error;
        _academicHintTimer?.cancel();
        if (clearAfter != null) {
          _academicHintTimer = Timer(clearAfter, () {
            if (_disposed) return;
            _academicHint = '';
            notifyListeners();
          });
        }
        break;
      case HintScope.global:
        _globalHint = message;
        _globalHintIsError = error;
        _isAcademicUpdateHint = isAcademicUpdate;
        _globalHintTimer?.cancel();
        if (clearAfter != null) {
          _globalHintTimer = Timer(clearAfter, () {
            if (_disposed) return;
            _globalHint = '';
            _isAcademicUpdateHint = false;
            notifyListeners();
          });
        }
        break;
    }
    notifyListeners();
  }

  void clearScheduleHint() {
    _scheduleHintTimer?.cancel();
    if (_scheduleHint.isEmpty) return;
    _scheduleHint = '';
    notifyListeners();
  }

  void clearAcademicHint() {
    _academicHintTimer?.cancel();
    if (_academicHint.isEmpty) return;
    _academicHint = '';
    notifyListeners();
  }

  void clearGlobalHint() {
    _globalHintTimer?.cancel();
    _isAcademicUpdateHint = false;
    if (_globalHint.isEmpty) return;
    _globalHint = '';
    notifyListeners();
  }

  /// 手动关掉提示：若指定了 [scope] 则关掉对应作用域；不指定则清除所有提示。
  void clearHint([HintScope? scope]) {
    if (scope == null) {
      _scheduleHintTimer?.cancel();
      _academicHintTimer?.cancel();
      _globalHintTimer?.cancel();
      final hasAny =
          _scheduleHint.isNotEmpty ||
          _academicHint.isNotEmpty ||
          _globalHint.isNotEmpty;
      _scheduleHint = '';
      _academicHint = '';
      _globalHint = '';
      _isAcademicUpdateHint = false;
      if (hasAny) notifyListeners();
    } else {
      switch (scope) {
        case HintScope.schedule:
          clearScheduleHint();
          break;
        case HintScope.academic:
          clearAcademicHint();
          break;
        case HintScope.global:
          clearGlobalHint();
          break;
      }
    }
  }

  /// 错误码 → 用户能懂的话。新增错误码时必须在这里补分支。
  static String humanizeError(AcademicError error) {
    switch (error.code) {
      case ErrorCode.invalidCredentials:
        return '账号或密码错误，请核对后重试。';
      case ErrorCode.sessionExpired:
        return '登录凭证已失效，请重新登录。';
      case ErrorCode.captchaRequired:
        return '需要输入验证码，请在验证码页输入后重试。';
      case ErrorCode.webLoginRequired:
        return '教务系统要求先完成网页统一认证，暂不支持自动登录。';
      case ErrorCode.networkRetryable:
        return '网络不稳定或无法连接教务系统，请检查网络后重试。';
      case ErrorCode.serverError:
        // 和"网络不行"分开说：这里网络是通的，是教务那边坏了。
        final status = error.httpStatus == null
            ? ''
            : '（HTTP ${error.httpStatus}）';
        return '教务系统异常$status：返回错误或维护页面。请稍后重试或切换线路。';
      case ErrorCode.pageChanged:
        return '课表数据格式与预期不符。若持续出现，请前往「调试信息」查看请求记录。';
      case ErrorCode.unsupported:
        return '该账号无课表查询权限。';
      case ErrorCode.accessForbidden:
        return '访问被拒绝（403）：学校限制了外网访问，请连接校园网后重试。';
      case ErrorCode.untrustedUrl:
        return '检测到未受信跳转，已中止。若在非校园网环境，请连接校园网后重试；'
            '若学校更换了入口，请更新教务地址。';
      case ErrorCode.cancelled:
        return '操作已取消。';
      case ErrorCode.validationFailed:
        return '输入不合法：${error.message}';
      case ErrorCode.staleContext:
        return '登录会话已过期，请重新登录。';
      case ErrorCode.resultUnknown:
        return '教务系统未返回明确结果，请刷新后查看。';
      case ErrorCode.notEvaluated:
        return '本学期教学质量评价未完成，教务系统暂不开放成绩查询，请前往教务网完成评教。';
      case ErrorCode.notOpen:
      case ErrorCode.noCapacity:
      case ErrorCode.conflict:
      case ErrorCode.alreadySelected:
      case ErrorCode.creditLimit:
      case ErrorCode.timeout:
      case ErrorCode.resourceLimit:
      case ErrorCode.success:
        return error.message;
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _scheduleHintTimer?.cancel();
    _academicHintTimer?.cancel();
    _globalHintTimer?.cancel();
    super.dispose();
  }
}
