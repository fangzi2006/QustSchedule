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
  bool _globalHintIsError = false;
  Timer? _globalHintTimer;

  /// 独立的跨页学业变动喜报槽位（与系统忙碌/重登槽位物理隔离，互不覆写误清）。
  String _academicUpdateHint = '';
  Duration _academicUpdateDuration = const Duration(seconds: 2);
  Timer? _academicUpdateTimer;

  /// 外部顶层路由状态是否正处于忙碌/错误遮挡（booting/loading/signingIn/failed）。
  bool _systemStatusBusy = false;

  int _storageNoticeEvent = 0;
  int get storageNoticeEvent => _storageNoticeEvent;

  String? _storageNoticeMessage;
  String? get storageNoticeMessage => _storageNoticeMessage;

  bool _disposed = false;

  /// 系统全局槽位（如正在重新登录、切校失败等），不含独立学业喜报槽位。
  String get systemGlobalHint => _globalHint;
  bool get systemGlobalHintIsError => _globalHintIsError;

  /// 独立跨页学业喜报槽位内容。
  String get academicUpdateHint => _academicUpdateHint;

  /// 对外兼容视图：优先返回系统全局槽位，系统槽位为空时返回跨页学业喜报。
  String get globalHint =>
      _globalHint.isNotEmpty ? _globalHint : _academicUpdateHint;

  bool get globalHintIsError =>
      _globalHint.isNotEmpty ? _globalHintIsError : false;

  /// 当前展示的全局提示是否为学业数据更新喜报。
  bool get isAcademicUpdateHint =>
      _globalHint.isEmpty && _academicUpdateHint.isNotEmpty;

  bool get _isSystemLayerBlocking =>
      _systemStatusBusy || _globalHint.isNotEmpty;

  /// 同步应用顶层路由忙碌/错误遮挡态；当遮挡解除时自动为待命中的学业喜报启动倒计时。
  void setSystemStatusBusy(bool busy) {
    if (_disposed || _systemStatusBusy == busy) return;
    _systemStatusBusy = busy;
    _syncAcademicUpdateTimer();
  }

  /// 给定应用主状态，判断全局浮层是否正处于忙碌/错误/全局提示或学业喜报占据状态。
  bool isGlobalPopupActive({required bool isStatusBusyOrFailed}) =>
      isStatusBusyOrFailed ||
      _globalHint.isNotEmpty ||
      _academicUpdateHint.isNotEmpty;

  /// 当前处于活跃态的提示文案（优先级：系统全局 > 跨页学业喜报 > 课表 > 学业）。
  String get hint {
    if (_globalHint.isNotEmpty) return _globalHint;
    if (_academicUpdateHint.isNotEmpty) return _academicUpdateHint;
    if (_scheduleHint.isNotEmpty) return _scheduleHint;
    if (_academicHint.isNotEmpty) return _academicHint;
    return '';
  }

  bool get hintIsError {
    if (_globalHint.isNotEmpty) return _globalHintIsError;
    if (_academicUpdateHint.isNotEmpty) return false;
    if (_scheduleHint.isNotEmpty) return _scheduleHintIsError;
    if (_academicHint.isNotEmpty) return _academicHintIsError;
    return false;
  }

  void _syncAcademicUpdateTimer() {
    if (_disposed || _academicUpdateHint.isEmpty) {
      _academicUpdateTimer?.cancel();
      _academicUpdateTimer = null;
      return;
    }
    if (_isSystemLayerBlocking) {
      _academicUpdateTimer?.cancel();
      _academicUpdateTimer = null;
      return;
    }
    if (_academicUpdateTimer != null) return;
    _academicUpdateTimer = Timer(_academicUpdateDuration, () {
      _academicUpdateTimer = null;
      if (_disposed || _academicUpdateHint.isEmpty) return;
      _academicUpdateHint = '';
      notifyListeners();
    });
  }

  void emitStorageNotice(String message) {
    if (_disposed) return;
    _storageNoticeMessage = message;
    _storageNoticeEvent++;
    notifyListeners();
  }

  void showAcademicUpdateHint(
    String message, {
    Duration duration = const Duration(seconds: 2),
  }) {
    if (_disposed) return;
    _academicUpdateHint = message;
    _academicUpdateDuration = duration;
    _academicUpdateTimer?.cancel();
    _academicUpdateTimer = null;
    _syncAcademicUpdateTimer();
    notifyListeners();
  }

  void showHint(
    String message, {
    bool error = false,
    bool isAcademicUpdate = false,
    Duration? clearAfter,
    HintScope scope = HintScope.global,
  }) {
    if (_disposed) return;
    if (isAcademicUpdate) {
      showAcademicUpdateHint(
        message,
        duration: clearAfter ?? const Duration(seconds: 2),
      );
      return;
    }
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
        _globalHintTimer?.cancel();
        if (clearAfter != null) {
          _globalHintTimer = Timer(clearAfter, () {
            if (_disposed) return;
            _globalHint = '';
            _syncAcademicUpdateTimer();
            notifyListeners();
          });
        }
        _syncAcademicUpdateTimer();
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

  void clearAcademicUpdateHint() {
    _academicUpdateTimer?.cancel();
    _academicUpdateTimer = null;
    if (_academicUpdateHint.isEmpty) return;
    _academicUpdateHint = '';
    notifyListeners();
  }

  /// 仅清理系统全局提示槽位，绝不误清独立跨页学业喜报槽位。
  void clearGlobalHint() {
    _globalHintTimer?.cancel();
    _globalHintTimer = null;
    if (_globalHint.isEmpty) return;
    _globalHint = '';
    _syncAcademicUpdateTimer();
    notifyListeners();
  }

  /// 手动关掉提示：若指定了 [scope] 则关掉对应作用域；不指定则清除全部槽位。
  void clearHint([HintScope? scope]) {
    if (scope == null) {
      _scheduleHintTimer?.cancel();
      _academicHintTimer?.cancel();
      _globalHintTimer?.cancel();
      _academicUpdateTimer?.cancel();
      _academicUpdateTimer = null;
      final hasAny =
          _scheduleHint.isNotEmpty ||
          _academicHint.isNotEmpty ||
          _globalHint.isNotEmpty ||
          _academicUpdateHint.isNotEmpty;
      _scheduleHint = '';
      _academicHint = '';
      _globalHint = '';
      _academicUpdateHint = '';
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
          if (_globalHint.isNotEmpty) {
            clearGlobalHint();
          } else {
            clearAcademicUpdateHint();
          }
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
        if (error.message.contains('自动登录次数过多') ||
            error.message.contains('已暂停')) {
          return '自动登录已暂停（多次失败或密码已变更），请重新登录。';
        }
        if (error.message.contains('没有保存账号密码')) {
          return '登录凭证已失效且未保存密码，请重新登录。';
        }
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
    _academicUpdateTimer?.cancel();
    super.dispose();
  }
}
