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

/// 这段响应像不像"后端挂了"的页面（而不是正常的教务页）。
///
/// 典型来源：网关/Nginx 的 502/504 页、Spring 的 Whitelabel 错误页、
/// 学校运维挂的"系统维护中"页。它们通常**仍是 HTTP 200**，只在正文里写着
/// 故障原因 —— 只按状态码判断会把它们当成正常页面，最后误报成
/// "页面结构与预期不一致"（PAGE_CHANGED），把人引向"学校升级了系统"。
///
/// 只收**特征明确**的写法，宁缺勿滥：漏判只是回到原来的 PAGE_CHANGED，
/// 误判却会把真正需要适配的结构变化说成"服务器故障"。
bool looksLikeServerError(String body) {
  if (body.isEmpty) return false;
  final text = body.toLowerCase();
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
    if (text.contains(marker)) return true;
  }
  return false;
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
  final root = _tryParseJson(text);
  if (root == null) {
    // 先分清"服务器坏了"和"页面改版了"：两者的处置完全不同。
    if (looksLikeServerError(text)) {
      throw AcademicError(
        ErrorCode.serverError,
        '教务返回了错误/维护页面，不是课表数据',
      );
    }
    changed('教务返回了无法识别的列表，请重新进入页面');
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
        final candidate = container[key];
        if (candidate is List) {
          found = candidate;
          break;
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
