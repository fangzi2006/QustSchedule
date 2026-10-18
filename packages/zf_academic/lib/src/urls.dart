/// 地址处理与学校地址策略。
///
/// 两件事：把用户填的地址规范化成"应用根"（到 `/jwglxt` 为止），以及解析学期参数。
///
/// 关键约束：必须是 http/https、不能带 userinfo、配置为 https 时不允许降级到 http、
/// 端口必须与白名单一致。这不是可选加固——它决定了重定向后还能不能继续访问。
library;

import 'errors.dart';
import 'types.dart';

export 'types.dart' show ZfEndpoints;

/// 从用户给的地址里推导 protocol / domain / basePath，调用方只填 `baseUrl` 也能用。
SchoolAddress? parseAcademicAddress(String input) {
  final text = input.trim();
  final uri = Uri.tryParse(text.contains('://') ? text : 'https://$text');
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  if (uri.userInfo.isNotEmpty) return null;
  // 主机名必须是合法形态（Dart 的 Uri 对空格等字符比 JS 的 URL 宽容，这里补上校验）。
  if (!RegExp(r'^[a-zA-Z0-9.\-:\[\]]+$').hasMatch(uri.host) ||
      uri.host.isEmpty) {
    return null;
  }
  final path = uri.path.replaceAll(RegExp(r'/+$'), '');
  final feature = RegExp(r'/(?:framework|xtgl|xsxk|xsxkkc|xk|xkgl)(?:/|$)')
      .firstMatch(path);
  late final String root;
  if (feature != null) {
    root = path.substring(0, feature.start);
  } else if (RegExp(r'\.(?:aspx|jsp|htmlx?|do|action)$', caseSensitive: false)
      .hasMatch(path)) {
    root = path.substring(0, path.lastIndexOf('/'));
  } else {
    root = path;
  }
  final port = uri.hasPort ? ':${uri.port}' : '';
  return SchoolAddress(
    protocol:
        uri.scheme == 'https' ? SchoolProtocol.https : SchoolProtocol.http,
    domain: uri.host.toLowerCase() + port,
    basePath: root,
  );
}

/// 与 Kotlin `AcademicUrls.resolve` 等价：应用根路径总是补上，除非端点本身已包含它。
String resolveAppUrl(String origin, String basePath, String path) {
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(path)) return path;
  final root =
      basePath.replaceAll(RegExp(r'^/+'), '').replaceAll(RegExp(r'/+$'), '');
  final endpoint = path.replaceAll(RegExp(r'^/+'), '');
  final base = '${origin.replaceAll(RegExp(r'/+$'), '')}/';
  if (endpoint.isEmpty) {
    return base.replaceAll(RegExp(r'/+$'), '') + (root.isEmpty ? '' : '/$root');
  }
  final relative =
      root.isEmpty || endpoint == root || endpoint.startsWith('$root/')
          ? endpoint
          : '$root/$endpoint';
  return Uri.parse(base).resolve(relative).toString();
}

/// 相对地址解析（移植自手写的 `resolve`，保留其 `//` 与 `?` 的特殊分支）。
String resolveUrl(String base, String relative) {
  if (RegExp(r'^https?://', caseSensitive: false).hasMatch(relative)) {
    return relative;
  }
  final match = RegExp(r'^(https?)://([^/]+)(/[^?#]*)?').firstMatch(base);
  if (match == null) throw AcademicError(ErrorCode.untrustedUrl, '无效学校地址');
  final scheme = match.group(1)!;
  final host = match.group(2)!;
  final pathPart = match.group(3);
  if (relative.startsWith('//')) return '$scheme:$relative';
  if (relative.startsWith('?')) {
    return '$scheme://$host${pathPart ?? '/'}$relative';
  }
  final path = relative.startsWith('/')
      ? relative
      : (pathPart ?? '/').replaceAll(RegExp(r'[^/]*$'), '') + relative;
  final suffix = RegExp(r'[?#].*$').firstMatch(path)?.group(0) ?? '';
  final pieces = <String>[];
  for (final piece in path.replaceAll(RegExp(r'[?#].*$'), '').split('/')) {
    if (piece == '..') {
      if (pieces.isNotEmpty) pieces.removeLast();
    } else if (piece != '.') {
      pieces.add(piece);
    }
  }
  return '$scheme://$host${pieces.join('/')}$suffix';
}

/// 合并查询参数（保留原参数，同名覆盖）。
String withQuery(String url, Map<String, String> fields) {
  final fragmentIndex = url.indexOf('#');
  final fragment = fragmentIndex >= 0 ? url.substring(fragmentIndex) : '';
  final withoutFragment =
      fragmentIndex >= 0 ? url.substring(0, fragmentIndex) : url;
  final queryIndex = withoutFragment.indexOf('?');
  final path = queryIndex >= 0
      ? withoutFragment.substring(0, queryIndex)
      : withoutFragment;
  final search =
      queryIndex >= 0 ? withoutFragment.substring(queryIndex + 1) : '';
  final pairs = <String, String>{};
  for (final part in search.split('&')) {
    if (part.isEmpty) continue;
    final index = part.indexOf('=');
    pairs[index < 0
            ? Uri.decodeComponent(part)
            : Uri.decodeComponent(part.substring(0, index))] =
        index < 0 ? '' : Uri.decodeComponent(part.substring(index + 1));
  }
  pairs.addAll(fields);
  final query = pairs.entries
      .map((entry) =>
          '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}')
      .join('&');
  return '$path${query.isEmpty ? '' : '?$query'}$fragment';
}

String originOf(String url) =>
    RegExp(r'^(https?://[^/?#]+)', caseSensitive: false)
        .firstMatch(url)
        ?.group(1) ??
    '';

/// 重定向/请求目标是否落在已声明的主机与端口上。与原项目 `AcademicUrlPolicy.isAllowed` 等价。
bool isAllowedUrl(
    String value, SchoolProtocol protocol, Iterable<String> hosts) {
  final url = Uri.tryParse(value);
  if (url == null) return false;
  if (url.scheme != 'http' && url.scheme != 'https') return false;
  if (url.userInfo.isNotEmpty) return false;
  if (protocol == SchoolProtocol.https && url.scheme != 'https') return false;
  final port = url.hasPort ? url.port : (url.scheme == 'https' ? 443 : 80);
  for (final configured in hosts) {
    final candidate = Uri.tryParse(
      configured.contains('://') ? configured : '${url.scheme}://$configured',
    );
    if (candidate == null) continue;
    final allowedPort = candidate.hasPort
        ? candidate.port
        : (candidate.scheme == 'https' ? 443 : 80);
    if (candidate.host.toLowerCase() == url.host.toLowerCase() &&
        port == allowedPort) {
      return true;
    }
  }
  return false;
}

String normalizeHost(String value) => value
    .trim()
    .toLowerCase()
    .replaceAll(RegExp(r'^https?://'), '')
    .replaceAll(RegExp(r'^\.'), '')
    .split('/')
    .first;

/// 端点配置合并：空字符串字段回退到默认值（对应 TS 版 `normalizeEndpoints`）。
ZfEndpoints normalizeEndpoints(ZfEndpoints? endpoints) {
  final merged = endpoints ?? const ZfEndpoints();
  return ZfEndpoints(
    loginPagePath: merged.loginPagePath.isEmpty
        ? const ZfEndpoints().loginPagePath
        : merged.loginPagePath,
    publicKeyPath: merged.publicKeyPath.isEmpty
        ? const ZfEndpoints().publicKeyPath
        : merged.publicKeyPath,
    captchaPath: merged.captchaPath.isEmpty
        ? const ZfEndpoints().captchaPath
        : merged.captchaPath,
    studentInfoPath: merged.studentInfoPath.isEmpty
        ? const ZfEndpoints().studentInfoPath
        : merged.studentInfoPath,
    schedulePath: merged.schedulePath.isEmpty
        ? const ZfEndpoints().schedulePath
        : merged.schedulePath,
    scheduleGnmkdm: merged.scheduleGnmkdm.isEmpty
        ? const ZfEndpoints().scheduleGnmkdm
        : merged.scheduleGnmkdm,
    gradesPath: merged.gradesPath.isEmpty
        ? const ZfEndpoints().gradesPath
        : merged.gradesPath,
    gradeGnmkdm: merged.gradeGnmkdm.isEmpty
        ? const ZfEndpoints().gradeGnmkdm
        : merged.gradeGnmkdm,
  );
}

// ---------------------------------------------------------------------------
// 学期
// ---------------------------------------------------------------------------

/// `2026-2027 第1学期` / `2026-2027-1` → Term；学年必须相邻。
Term? parseTerm(String value) {
  final match =
      RegExp(r'(\d{4})\D+(\d{4})\D+([123])(?:\D|$)').firstMatch(value);
  if (match == null) return null;
  final year = int.parse(match.group(1)!);
  final nextYear = int.parse(match.group(2)!);
  final semester = int.parse(match.group(3)!);
  if (nextYear != year + 1) return null;
  return Term(
    id: '$year-$nextYear-$semester',
    name: '$year-$nextYear 第$semester学期',
    year: year,
    semester: semester,
  );
}

/// 新正方把学期编码成 `xqm`：第 1 学期 = 3，第 2 学期 = 12，第 3 学期 = 16。
const Map<int, String> semesterCodes = {1: '3', 2: '12', 3: '16'};

/// 学期 id → 新正方表单参数。解析不了时返回空串（调用方按"不带学期"处理）。
({String xnm, String xqm}) zfTermParams(String? termId) {
  final parsed = termId == null ? null : parseTerm(termId);
  return (
    xnm: parsed?.year?.toString() ?? '',
    xqm:
        parsed?.semester == null ? '' : (semesterCodes[parsed!.semester] ?? ''),
  );
}

/// 当前自然年推导出的学年学期，只在没有学校数据时用于兜底排序，不用来"发明"可选学期。
Term calendarTerm([DateTime? now]) {
  final date = now ?? DateTime.now();
  final month = date.toUtc().month;
  final year = month >= 8 ? date.toUtc().year : date.toUtc().year - 1;
  final semester = month >= 8 || month == 1 ? 1 : 2;
  return parseTerm('$year-${year + 1}-$semester')!;
}
