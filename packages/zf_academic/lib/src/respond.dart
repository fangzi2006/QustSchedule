/// 教务响应分类。
///
/// 核心约定：**错误不能被当成空数据**。查询失败必须抛出对应状态码，
/// 否则上层会把"没读到"记成"这门课没有"，进而覆盖有效缓存。
library;

import 'dart:convert';

import 'errors.dart';
import 'html.dart' show isLoginPage, stripTags;
import 'util.dart' show str;

Object? _tryParseJson(String text) {
  try {
    return jsonDecode(text);
  } catch (_) {
    return null;
  }
}

Map<String, dynamic>? _asObject(Object? value) =>
    value is Map<String, dynamic> ? value : null;

/// 从 HTML 源码中提取 <title> 标签内的文本。
String? extractHtmlTitle(String html) {
  if (html.isEmpty) return null;
  final match = RegExp(r'<title[^>]*>([\s\S]*?)</title>', caseSensitive: false)
      .firstMatch(html);
  if (match == null) return null;
  final raw = stripTags(match.group(1) ?? '').trim();
  return raw.isEmpty ? null : raw;
}

/// HTTP 响应的健康状态分类。
enum ResponseKind {
  /// 正常业务响应（包括正常的 HTML 页面或 JSON 数据）。
  ok,

  /// 服务端故障（5xx、系统维护、Tomcat/Nginx 崩溃、正方系统错误）。
  serverError,

  /// 访问策略拦截 / 403（外网访问受限、防火墙或深信服网关策略拦截）。
  accessForbidden,
}

/// 统一响应诊断结果（保留深挖能力，附带诊断原因）。
final class ResponseDiagnosis {
  final ResponseKind kind;

  /// 提取到的页面标题或错误特征描述，直接供 RequestLog 和调试回溯。
  final String? detail;

  const ResponseDiagnosis(this.kind, [this.detail]);

  bool get isOk => kind == ResponseKind.ok;
  bool get isServerError => kind == ResponseKind.serverError;
  bool get isAccessForbidden => kind == ResponseKind.accessForbidden;

  @override
  String toString() =>
      'ResponseDiagnosis($kind${detail != null ? ', detail: $detail' : ''})';
}

/// 判定正文与标题是否明确属于服务端故障（500/502/维护/系统崩溃）。
bool _isDefiniteServerError(String lowerBody, String? lowerTitle) {
  if (lowerTitle != null) {
    // 排除明确带 403 的拦截标题（如"访问出错-403"）
    if (!lowerTitle.contains('403')) {
      if (lowerTitle == '访问出错' ||
          lowerTitle.contains('server error') ||
          lowerTitle.contains('bad gateway') ||
          lowerTitle.contains('gateway timeout') ||
          lowerTitle.contains('gateway time-out') ||
          lowerTitle.contains('service temporarily unavailable') ||
          lowerTitle.contains('系统维护') ||
          lowerTitle.contains('系统繁忙') ||
          lowerTitle.contains('服务器错误')) {
        return true;
      }
    }
  }

  const markers = <String>[
    'internal server error',
    'bad gateway',
    'gateway time-out',
    'gateway timeout',
    'service temporarily unavailable',
    'whitelabel error page',
    'application error',
    '<center>nginx',
    '系统维护',
    '系统繁忙',
    '服务器错误',
    '服务暂时不可用',
    '服务暂不可用',
    '数据库连接异常',
  ];
  for (final marker in markers) {
    if (lowerBody.contains(marker)) return true;
  }
  return false;
}

/// 判定正文与标题是否明确属于访问策略拦截（校园网防火墙 / 403 拦截）。
bool _isDefiniteAccessForbidden(String lowerBody, String? lowerTitle) {
  if (lowerTitle != null) {
    if (lowerTitle.contains('访问出错-403') ||
        lowerTitle.contains('403 forbidden') ||
        lowerTitle.contains('access denied') ||
        lowerTitle.contains('request forbidden')) {
      return true;
    }
  }

  // 高置信度的校园网/网关拦截特征（已移除宽泛模糊词：'访问出错' 与单独的 '访问策略'）
  const markers = <String>[
    '访问出错-403',
    '访问策略禁止',
    '禁止您访问',
    '仅限校园网',
    '仅限校内',
    '校园网内访问',
    '非校园网网段',
    '403 forbidden',
    'access denied',
    'request forbidden',
  ];
  for (final marker in markers) {
    if (lowerBody.contains(marker)) return true;
  }

  // 复合特征：包含 403 并且明确提示受限/禁止/未授权
  if (lowerBody.contains('403') &&
      (lowerBody.contains('禁止访问') ||
          lowerBody.contains('拒绝访问') ||
          lowerBody.contains('访问策略') ||
          lowerBody.contains('策略限制') ||
          lowerBody.contains('错误代码'))) {
    return true;
  }

  return false;
}

/// 统一诊断 HTTP 响应的健康状态。
///
/// 具备严格的优先级保证：
/// 1. 显式 HTTP 5xx 状态码优先判定为服务端故障；
/// 2. HTML 语义结构中优先判定服务端故障（解决"正方 500 页面标题也是访问出错"的误判根因）；
/// 3. 基于高置信度指纹判定访问策略拦截（403 校园网限制）；
/// 4. 诊断详情 [ResponseDiagnosis.detail] 携带关键标题或特征，供 [RequestLog] 与异常溯源。
ResponseDiagnosis inspectResponse({
  required int statusCode,
  required String body,
  bool isAuth = false,
}) {
  if (statusCode >= 500) {
    return ResponseDiagnosis(
        ResponseKind.serverError, 'HTTP $statusCode 服务端异常');
  }

  final trimmed = body.trim();
  if (trimmed.isEmpty) {
    if (statusCode == 403 && isAuth) {
      return const ResponseDiagnosis(ResponseKind.accessForbidden, 'HTTP 403');
    }
    return const ResponseDiagnosis(ResponseKind.ok);
  }

  final title = extractHtmlTitle(trimmed);
  final lowerTitle = title?.toLowerCase();
  final lowerBody = trimmed.toLowerCase();

  // 优先判定服务端故障（正方 500、Nginx 502/504、运维维护等）
  if (_isDefiniteServerError(lowerBody, lowerTitle)) {
    return ResponseDiagnosis(
      ResponseKind.serverError,
      title != null ? '返回错误页（$title）' : '返回错误页',
    );
  }

  // 判定策略拦截（深信服/防火墙阻断、校园网限制）
  if (_isDefiniteAccessForbidden(lowerBody, lowerTitle) ||
      (statusCode == 403 && isAuth)) {
    return ResponseDiagnosis(
      ResponseKind.accessForbidden,
      title != null ? '访问被拦截（403）[标题: $title]' : '访问被拦截（403）',
    );
  }

  return const ResponseDiagnosis(ResponseKind.ok);
}

/// 这段响应像不像"后端挂了"的页面（而不是正常的教务页）。
///
/// 典型来源：网关/Nginx 的 502/504 页、Spring 的 Whitelabel 错误页、
/// 学校运维挂的"系统维护中"页，以及正方系统报错页。它们通常**仍是 HTTP 200**。
bool looksLikeServerError(String body) {
  if (body.isEmpty) return false;
  final title = extractHtmlTitle(body);
  return _isDefiniteServerError(body.toLowerCase(), title?.toLowerCase());
}

/// 响应正文是否像防火墙 / 网关策略拦截页（如外网被校园网网关拦截时的「访问出错-403」页）。
///
/// 典型来源：深信服 / 校园网防火墙对非校园网 IP 返回的拦截页，标题为「访问出错-403」，
/// 正文提示「访问策略禁止您访问该网站」及「错误代码：403」。与 [looksLikeServerError]
/// 区分开：此类错误并非教务服务器崩溃，而是学校限制了外网直连。
bool looksLikeAccessForbidden(String body) {
  if (body.isEmpty) return false;
  final title = extractHtmlTitle(body);
  return _isDefiniteAccessForbidden(body.toLowerCase(), title?.toLowerCase());
}

/// 从 JSON 字段、`alert()` 或可见文本里取一句人话错误信息（截断 180 字，与原实现一致）。
String messageOf(String body) {
  // 新正方的错误页会把原因写在 .error_text / .error_text0 里，优先取它。
  final errorBlocks = RegExp(
    r'<[^>]*class="[^"]*error_text0?[^"]*"[^>]*>([\s\S]*?)</[a-zA-Z]+>',
    caseSensitive: false,
  )
      .allMatches(body)
      .map((match) => stripTags(match.group(1) ?? ''))
      .where((text) => text.isNotEmpty)
      .toList();
  if (errorBlocks.isNotEmpty) {
    return errorBlocks.join('；').length > 180
        ? errorBlocks.join('；').substring(0, 180)
        : errorBlocks.join('；');
  }

  final object = _asObject(
      _tryParseJson(body.trim().replaceFirst(RegExp(r'^\uFEFF'), '')));
  if (object != null) {
    for (final key in const ['message', 'msg', 'msgContent', 'error']) {
      final value = str(object[key]);
      if (value.isNotEmpty && value != 'null') {
        return value.length > 180 ? value.substring(0, 180) : value;
      }
    }
  }
  final alerts = RegExp(r"""alert\s*\(\s*['"]([^'"\r\n]+)['"]\s*\)""")
      .allMatches(body)
      .map((match) => match.group(1) ?? '')
      .join(' ');
  if (alerts.isNotEmpty) {
    return alerts.length > 180 ? alerts.substring(0, 180) : alerts;
  }
  final text = stripTags(body);
  return text.length > 180 ? text.substring(0, 180) : text;
}

bool hasSuccess(String body) {
  final object = _asObject(
      _tryParseJson(body.trim().replaceFirst(RegExp(r'^\uFEFF'), '')));
  if (object == null) return false;
  if (object.containsKey('success')) return object['success'] == true;
  final flag = str(object['flag']);
  if (flag == '1') return true;
  final code = str(object['code']);
  return code == '0';
}

/// 把响应归到一个状态码。顺序与原实现一致，因为学校的不同失败形态会同时命中多个关键词，
/// 先判定的才是"更具体的原因"。
ErrorCode statusOf(String body, {int httpStatus = 200}) {
  if (httpStatus == 401 || httpStatus == 403) return ErrorCode.sessionExpired;
  if (httpStatus == 429) return ErrorCode.networkRetryable;
  if (httpStatus >= 500) return ErrorCode.resultUnknown;
  if (isLoginPage(body)) return ErrorCode.sessionExpired;
  final lower = body.toLowerCase();
  if (const ['请先登录', '登录超时', '会话失效', 'notlogin'].any(lower.contains)) {
    return ErrorCode.sessionExpired;
  }
  final detail = messageOf(body);
  if (const ['密码错误', '用户名或密码', '账号或密码'].any(detail.contains)) {
    return ErrorCode.invalidCredentials;
  }
  if (detail.contains('验证码') ||
      RegExp('verifyCode', caseSensitive: false).hasMatch(detail)) {
    return ErrorCode.webLoginRequired;
  }
  final conflictId = _asObject(_tryParseJson(
      body.trim().replaceFirst(RegExp(r'^\uFEFF'), '')))?['yxjx0404id'];
  if (detail.contains('冲突') ||
      (conflictId != null && str(conflictId) != 'null')) {
    return ErrorCode.conflict;
  }
  if (const ['学分上限', '超过学分', '超出学分', '学分限制'].any(detail.contains)) {
    return ErrorCode.creditLimit;
  }
  if (const [
    '未开始',
    '未开放',
    '已结束',
    '选课时间已过',
    '不在选课时间',
    '当前不属于选课阶段',
    '只可退课',
  ].any(detail.contains)) {
    return ErrorCode.notOpen;
  }
  if (const ['已选该', '已经选', '重复选课'].any(detail.contains)) {
    return ErrorCode.alreadySelected;
  }
  if (const ['已满', '无余量', '名额不足', '容量不足'].any(detail.contains)) {
    return ErrorCode.noCapacity;
  }
  if (httpStatus < 200 || httpStatus >= 300) return ErrorCode.validationFailed;
  return hasSuccess(body) ? ErrorCode.success : ErrorCode.validationFailed;
}

/// 新正方课表/查询页用一句裸文案表示"这个账号没有该功能权限"。
bool isPermissionDenied(String body) {
  final text = body
      .trim()
      .replaceAll(RegExp(r'^"|"$'), '')
      .replaceAll(RegExp(r'[!！。]+$'), '');
  return text == '没有访问权限' || text == '无访问权限';
}

/// 从 JSON 响应里取出列表，顺序与 plugin-sdk-v3 的 `list()` 一致：
/// 先看根对象是否显式失败，再从 root / root.data / root.result 里按 keys 找数组。
List<Map<String, dynamic>> listRows(String body, List<String> keys) {
  final text = body.trim().replaceFirst(RegExp(r'^\uFEFF'), '');
  if (isLoginPage(text)) {
    throw AcademicError(ErrorCode.sessionExpired, '登录已失效，请重新登录');
  }
  final Object? root;
  try {
    root = jsonDecode(text);
  } catch (_) {
    // 不是有效 JSON，结构化诊断是否是服务端错误页或防火墙拦截页
    final diagnosis = inspectResponse(statusCode: 200, body: text);
    if (diagnosis.isServerError) {
      throw AcademicError(
        ErrorCode.serverError,
        '教务返回了错误/维护页面，不是课表数据',
        cause: diagnosis.detail,
      );
    }
    if (diagnosis.isAccessForbidden) {
      throw AcademicError(
        ErrorCode.accessForbidden,
        '访问被拒绝（403）：访问策略禁止外网访问，请连接校园网后重试',
        httpStatus: 403,
        cause: diagnosis.detail,
      );
    }
    changed('教务返回了无法识别的列表，请重新进入页面');
  }

  if (root == null) {
    return const <Map<String, dynamic>>[];
  }

  final object = _asObject(root);
  if (object != null) {
    final success = object['success'];
    final code = object['code'] == null ? null : str(object['code']);
    final flag = str(object['flag']);
    final rejected = success == false ||
        (code != null && !const ['0', '200'].contains(code)) ||
        const ['false', '0'].contains(flag);
    if (rejected) {
      final status = statusOf(text);
      throw AcademicError(
        status == ErrorCode.success || status == ErrorCode.validationFailed
            ? ErrorCode.pageChanged
            : status,
        messageOf(text),
      );
    }
  }

  final containers = root is List
      ? const <Map<String, dynamic>?>[]
      : <Map<String, dynamic>?>[
          object,
          _asObject(object?['data']),
          _asObject(object?['result'])
        ];
  final searchKeys = <String>[...keys, 'data', 'aaData', 'rows', 'list'];
  List<dynamic>? found;
  if (root is List) {
    found = root;
  } else {
    for (final container in containers) {
      if (container == null) continue;
      for (final key in searchKeys) {
        if (container.containsKey(key)) {
          final candidate = container[key];
          if (candidate == null) {
            found = const <dynamic>[];
            break;
          }
          if (candidate is List) {
            found = candidate;
            break;
          }
        }
      }
      if (found != null) break;
    }
  }

  if (found == null || found.any((row) => row is! Map)) {
    changed('教务返回了无法识别的列表，请重新进入页面');
  }
  return found.cast<Map<String, dynamic>>();
}

/// 安全地取一个**可选**列表字段：找不到 / 不是列表就返回空，不像 [listRows] 那样抛错。
///
/// 用于课表响应里可能不存在的附加列表（如备注 `sjkList`）——主列表（`kbList`）
/// 已经由 [listRows] 校验过登录态与响应结构，这里只需"有就取、没有就空"。
List<Map<String, dynamic>> listRowsOrEmpty(String body, List<String> keys) {
  final text = body.trim().replaceFirst(RegExp(r'^\uFEFF'), '');
  final root = _tryParseJson(text);
  if (root == null) return const <Map<String, dynamic>>[];
  final object = _asObject(root);
  final containers = root is List
      ? const <Map<String, dynamic>?>[]
      : <Map<String, dynamic>?>[
          object,
          _asObject(object?['data']),
          _asObject(object?['result']),
        ];
  final searchKeys = <String>[...keys, 'data', 'aaData', 'rows', 'list'];
  for (final container in containers) {
    if (container == null) continue;
    for (final key in searchKeys) {
      final candidate = container[key];
      if (candidate is List && candidate.every((row) => row is Map)) {
        return candidate.cast<Map<String, dynamic>>();
      }
    }
  }
  return const <Map<String, dynamic>>[];
}

/// 读查询页前的统一校验，等价 `ZfResponses.requirePage`。
void requireQueryPage(String body, int httpStatus) {
  if (isLoginPage(body)) {
    throw AcademicError(ErrorCode.sessionExpired, '登录已失效，请重新登录');
  }
  final diagnosis = inspectResponse(statusCode: httpStatus, body: body);
  if (diagnosis.isServerError) {
    throw AcademicError(
      ErrorCode.serverError,
      '教务返回了错误/维护页面，无法正常读取页面',
      httpStatus: httpStatus >= 400 ? httpStatus : null,
      cause: diagnosis.detail,
    );
  }
  if (diagnosis.isAccessForbidden) {
    throw AcademicError(
      ErrorCode.accessForbidden,
      '访问被拒绝（403）：访问策略禁止外网访问，请连接校园网后重试',
      httpStatus: 403,
      cause: diagnosis.detail,
    );
  }
  if (httpStatus < 200 || httpStatus >= 300) {
    final ErrorCode status;
    if (httpStatus >= 500 || httpStatus == 429) {
      status = ErrorCode.networkRetryable;
    } else if (httpStatus == 401 || httpStatus == 403) {
      status = ErrorCode.sessionExpired;
    } else {
      status = ErrorCode.pageChanged;
    }
    throw AcademicError(status, '教务请求失败（HTTP $httpStatus），请稍后重试',
        httpStatus: httpStatus);
  }
  if (RegExp(r'class="(?:error_v5|error_con|error_text)"').hasMatch(body)) {
    final status = statusOf(body);
    throw AcademicError(
      status == ErrorCode.notOpen ? ErrorCode.notOpen : ErrorCode.pageChanged,
      messageOf(body),
    );
  }
}
