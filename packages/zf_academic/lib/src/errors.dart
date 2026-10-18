/// 统一错误类型。
///
/// `wire` 是稳定不变的 SCREAMING_SNAKE 名称。调用方应把 `error.code` 当作
/// 业务分支条件，而不是解析 message 文案。
library;

enum ErrorCode {
  unsupported('UNSUPPORTED'),
  notOpen('NOT_OPEN'),
  invalidCredentials('INVALID_CREDENTIALS'),
  sessionExpired('SESSION_EXPIRED'),
  captchaRequired('CAPTCHA_REQUIRED'),
  webLoginRequired('WEB_LOGIN_REQUIRED'),
  noCapacity('NO_CAPACITY'),
  conflict('CONFLICT'),
  alreadySelected('ALREADY_SELECTED'),
  creditLimit('CREDIT_LIMIT'),
  pageChanged('PAGE_CHANGED'),
  networkRetryable('NETWORK_RETRYABLE'),
  resultUnknown('RESULT_UNKNOWN'),
  untrustedUrl('UNTRUSTED_URL'),
  validationFailed('VALIDATION_FAILED'),
  timeout('TIMEOUT'),
  cancelled('CANCELLED'),
  resourceLimit('RESOURCE_LIMIT'),
  staleContext('STALE_CONTEXT'),
  success('SUCCESS');

  /// 跨栈共用的名称，例如 `SESSION_EXPIRED`。
  final String wire;

  const ErrorCode(this.wire);

  static ErrorCode fromWire(String value) {
    for (final code in values) {
      if (code.wire == value) return code;
    }
    throw ArgumentError.value(value, 'value', '未知的错误码');
  }
}

/// 教务客户端抛出的唯一异常类型。
class AcademicError implements Exception {
  final ErrorCode code;
  final String message;

  /// 触发该错误的 HTTP 状态码，非网络导致时为 null。
  final int? httpStatus;
  final Object? cause;

  const AcademicError(
    this.code,
    this.message, {
    this.httpStatus,
    this.cause,
  });

  @override
  String toString() => 'AcademicError(${code.wire}): $message';
}

/// 与原项目 `changed()` 等价：把解析失败统一报成 PAGE_CHANGED，
/// 避免用空数据覆盖有效缓存。
Never changed([String message = '学校页面结构已变化，请在学校网页核实']) =>
    throw AcademicError(ErrorCode.pageChanged, message);

/// 把任意异常归一成 AcademicError；未识别的异常按 NETWORK_RETRYABLE 处理。
AcademicError asAcademicError(
  Object error, [
  ErrorCode fallback = ErrorCode.networkRetryable,
]) {
  if (error is AcademicError) return error;
  return AcademicError(fallback, error.toString(), cause: error);
}
