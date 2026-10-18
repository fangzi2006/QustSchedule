/// Cookie 存储：登录成功后保存会话、并在后续请求里自动带上。
///
/// 教务域（`/jwglxt`）与会话建立时的认证域分开存：互相不污染，也能回查
/// "某个主机种下过哪些 Cookie"，换学校时据此精确清理。
///
/// 匹配规则按 RFC 6265：host-only 精确匹配、Domain 后缀匹配、Path 前缀 + 边界匹配、
/// Secure 只在 https 发送、过期即淘汰。本文件不依赖任何平台 API；
/// 文件持久化在 `cookie_storage.dart`（依赖 dart:io，见 `zf_academic_io.dart` 入口）。
library;

import 'errors.dart';

class CookieRecord {
  final String name;
  final String value;

  /// 小写、不带前导点。
  final String domain;
  final String path;

  /// true 表示未声明 Domain 属性，只回发给同主机。
  final bool hostOnly;
  final bool secure;
  final bool httpOnly;

  /// epoch 毫秒；null 表示会话 Cookie（进程结束即失效）。
  final int? expiresAt;
  final int createdAt;

  /// 种下这条 Cookie 的响应来源主机（小写），用于 CAS → 教务的会话迁移。
  final String setByHost;
  final int setByPort;

  const CookieRecord({
    required this.name,
    required this.value,
    required this.domain,
    required this.path,
    required this.hostOnly,
    required this.secure,
    required this.httpOnly,
    required this.expiresAt,
    required this.createdAt,
    required this.setByHost,
    required this.setByPort,
  });

  Map<String, Object?> toJson() => {
        'name': name,
        'value': value,
        'domain': domain,
        'path': path,
        'hostOnly': hostOnly,
        'secure': secure,
        'httpOnly': httpOnly,
        'expiresAt': expiresAt,
        'createdAt': createdAt,
        'setByHost': setByHost,
        'setByPort': setByPort,
      };

  /// 反序列化并归一化（与 TS 版 `import()` 的字段默认值一致）。
  factory CookieRecord.fromJson(Map<String, dynamic> json, {int? now}) {
    return CookieRecord(
      name: json['name'] as String? ?? '',
      value: json['value'] as String? ?? '',
      domain: (json['domain'] as String? ?? '').toLowerCase(),
      path: json['path'] as String? ?? '/',
      hostOnly: json['hostOnly'] as bool? ?? true,
      secure: json['secure'] as bool? ?? false,
      httpOnly: json['httpOnly'] as bool? ?? false,
      expiresAt: (json['expiresAt'] as num?)?.toInt(),
      createdAt: (json['createdAt'] as num?)?.toInt() ?? now ?? 0,
      setByHost:
          (json['setByHost'] as String? ?? json['domain'] as String? ?? '')
              .toLowerCase(),
      setByPort: (json['setByPort'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 可 JSON 序列化的 Cookie 快照：直接写文件 / KV / 数据库都行。
class CookieStoreSnapshot {
  final int version;
  final String baseUrl;
  final int savedAt;
  final List<CookieRecord> cookies;

  const CookieStoreSnapshot({
    required this.version,
    required this.baseUrl,
    required this.savedAt,
    required this.cookies,
  });

  Map<String, Object?> toJson() => {
        'version': version,
        'baseUrl': baseUrl,
        'savedAt': savedAt,
        'cookies': cookies.map((record) => record.toJson()).toList(),
      };

  static CookieStoreSnapshot fromJson(Map<String, dynamic> json) {
    final cookies = (json['cookies'] as List<dynamic>? ?? const [])
        .map((item) => CookieRecord.fromJson(item as Map<String, dynamic>))
        .toList();
    return CookieStoreSnapshot(
      version: (json['version'] as num?)?.toInt() ?? 0,
      baseUrl: json['baseUrl'] as String? ?? '',
      savedAt: (json['savedAt'] as num?)?.toInt() ?? 0,
      cookies: cookies,
    );
  }
}

final RegExp _cookieName = RegExp(r"^[!#$%&'*+\-.^_`|~0-9A-Za-z]+$");

const List<String> _monthNames = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

const List<String> _weekdayNames = [
  'Sun',
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
];

/// 默认 Path：请求路径去掉最后一段（RFC 6265 §5.1.4）。
String _defaultPath(String requestPath) {
  if (requestPath.isEmpty || !requestPath.startsWith('/')) return '/';
  final lastSlash = requestPath.lastIndexOf('/');
  if (lastSlash <= 0) return '/';
  return requestPath.substring(0, lastSlash);
}

/// 解析 Set-Cookie 里的 Expires（RFC 1123，兼容 `21 Oct 2015` 与 `21-Oct-2015`）。
/// 解析失败返回 null（调用方保留原值，与 TS 版一致）。
int? parseCookieDate(String value) {
  final match = RegExp(
    r'^[A-Za-z]{3,9},?\s+(\d{1,2})[-\s]([A-Za-z]{3})[-\s](\d{2,4})\s+(\d{2}):(\d{2}):(\d{2})',
  ).firstMatch(value.trim());
  if (match == null) return null;
  final day = int.parse(match.group(1)!);
  final month = _monthNames.indexOf(match.group(2)!) + 1;
  var year = int.parse(match.group(3)!);
  if (year < 100) year += year < 70 ? 2000 : 1900;
  if (month <= 0) return null;
  return DateTime.utc(
    year,
    month,
    day,
    int.parse(match.group(4)!),
    int.parse(match.group(5)!),
    int.parse(match.group(6)!),
  ).millisecondsSinceEpoch;
}

/// 生成 Set-Cookie 用的 Expires 值（GMT）。
String formatCookieDate(DateTime time) {
  final utc = time.toUtc();
  final weekday = _weekdayNames[utc.weekday % 7];
  final month = _monthNames[utc.month - 1];
  final dd = utc.day.toString().padLeft(2, '0');
  final hh = utc.hour.toString().padLeft(2, '0');
  final mm = utc.minute.toString().padLeft(2, '0');
  final ss = utc.second.toString().padLeft(2, '0');
  return '$weekday, $dd $month ${utc.year} $hh:$mm:$ss GMT';
}

/// 解析单条 Set-Cookie 头。逗号只可能出现在 Expires 值内部，因此先按 ';' 切分是安全的。
CookieRecord? parseSetCookie(String header, Uri url, int now) {
  final segments = header.split(';');
  final first = segments.removeAt(0).trim();
  final separator = first.indexOf('=');
  if (separator <= 0) return null;
  final name = first.substring(0, separator).trim();
  if (!_cookieName.hasMatch(name)) return null;
  var value = first.substring(separator + 1).trim();
  if (value.length >= 2 && value.startsWith('"') && value.endsWith('"')) {
    value = value.substring(1, value.length - 1);
  }

  String? domain;
  String? path;
  var secure = false;
  var httpOnly = false;
  int? expiresAt;
  int? maxAge;

  for (final segment in segments) {
    final eq = segment.indexOf('=');
    final key =
        (eq < 0 ? segment : segment.substring(0, eq)).trim().toLowerCase();
    final raw = eq < 0 ? '' : segment.substring(eq + 1).trim();
    switch (key) {
      case 'domain':
        final candidate = raw.replaceFirst(RegExp(r'^\.'), '').toLowerCase();
        if (candidate.isNotEmpty) domain = candidate;
      case 'path':
        if (raw.startsWith('/')) path = raw;
      case 'secure':
        secure = true;
      case 'httponly':
        httpOnly = true;
      case 'expires':
        expiresAt = parseCookieDate(raw) ?? expiresAt;
      case 'max-age':
        final parsed = int.tryParse(raw);
        if (parsed != null) maxAge = parsed;
      default:
        break;
    }
  }
  if (maxAge != null) expiresAt = now + maxAge * 1000;

  final host = url.host.toLowerCase();
  // 声明的 Domain 必须是主机名的后缀，否则按 RFC 6265 直接丢弃。
  if (domain != null && domain != host && !host.endsWith('.$domain')) {
    return null;
  }
  final hostOnly = domain == null;

  return CookieRecord(
    name: name,
    value: value,
    domain: hostOnly ? host : domain,
    path: path ?? _defaultPath(url.path),
    hostOnly: hostOnly,
    secure: secure,
    httpOnly: httpOnly,
    expiresAt: expiresAt,
    createdAt: now,
    setByHost: host,
    setByPort: url.hasPort ? url.port : (url.scheme == 'https' ? 443 : 80),
  );
}

bool _sameIdentity(CookieRecord a, CookieRecord b) =>
    a.name == b.name && a.domain == b.domain && a.path == b.path;

bool _domainMatches(String host, CookieRecord record) {
  if (record.hostOnly) return host == record.domain;
  if (host == record.domain) return true;
  final isIp =
      RegExp(r'^\d{1,3}(\.\d{1,3}){3}$').hasMatch(host) || host.contains(':');
  return !isIp && host.endsWith('.${record.domain}');
}

bool _pathMatches(String requestPath, String cookiePath) {
  final path = requestPath.isEmpty ? '/' : requestPath;
  if (path == cookiePath) return true;
  if (!path.startsWith(cookiePath)) return false;
  if (cookiePath.endsWith('/')) return true;
  return path[cookiePath.length] == '/';
}

bool _isDefaultPort(int port, bool secure) =>
    (secure && port == 443) || (!secure && port == 80);

class CookieStore {
  final List<CookieRecord> _records = [];
  final int Function() _clock;

  /// 计算 Cookie 头所用的地址；`import()` 会用快照中的值覆盖。
  String baseUrl;

  int _era = 0;

  CookieStore({this.baseUrl = '', int Function()? now})
      : _clock = now ?? _systemClock;

  static int _systemClock() => DateTime.now().millisecondsSinceEpoch;

  /// 会话世代。`invalidate()` 后递增，调用方可据此判断旧回调是否已过期。
  int get generation => _era;

  int get size => _live().length;

  /// 记录一批响应 Cookie。
  void setCookies(Uri url, List<String> header) {
    final now = _clock();
    for (final raw in header) {
      if (raw.isEmpty) continue;
      final record = parseSetCookie(raw, url, now);
      if (record == null) continue;
      _records.removeWhere((existing) => _sameIdentity(existing, record));
      // 过期的 Set-Cookie 等价于删除。
      if (record.expiresAt == null || record.expiresAt! > now) {
        _records.add(record);
      }
    }
  }

  void setCookie(Uri url, String header) => setCookies(url, [header]);

  /// 指定地址应当带上的 Cookie 头；没有可用 Cookie 时返回空串。
  String cookieHeaderFor(Uri url) {
    final now = _clock();
    final host = url.host.toLowerCase();
    final secureTransport = url.scheme == 'https';
    final matching = _live(now)
        .where((record) =>
            _domainMatches(host, record) && _pathMatches(url.path, record.path))
        .where((record) => !record.secure || secureTransport)
        .indexed
        .toList()
      ..sort((a, b) {
        // 长 path 优先，同长按种下时间；最后按插入顺序，保证输出确定。
        final byPath = b.$2.path.length.compareTo(a.$2.path.length);
        if (byPath != 0) return byPath;
        final byAge = a.$2.createdAt.compareTo(b.$2.createdAt);
        if (byAge != 0) return byAge;
        return a.$1.compareTo(b.$1);
      });
    return matching
        .map((entry) => '${entry.$2.name}=${entry.$2.value}')
        .join('; ');
  }

  /// 以构造时的教务根地址计算 Cookie 头（登录后交给别的 HTTP 客户端时用）。
  String header() => baseUrl.isEmpty ? '' : cookieHeaderFor(Uri.parse(baseUrl));

  List<CookieRecord> list() => List.unmodifiable(_live());

  /// 回查某个来源（host[:port]）种下的全部 Cookie，不受 path / secure 限制。
  List<CookieRecord> cookiesSetBy(String host, {int? port}) {
    final target = host.toLowerCase();
    return _live()
        .where((record) =>
            record.setByHost == target &&
            (port == null || record.setByPort == port))
        .toList();
  }

  /// 把另一份存储里符合来源条件的 Cookie 迁入本存储（CAS 验票后迁移教务 Cookie）。
  int adopt(CookieStore source, String host, {int? port, bool secure = true}) {
    final incoming = source.cookiesSetBy(host, port: port);
    if (incoming.isEmpty) return 0;
    final scheme = secure ? 'https' : 'http';
    final portSuffix =
        port != null && !_isDefaultPort(port, secure) ? ':$port' : '';
    final origin = '$scheme://$host$portSuffix/';
    setCookies(
      Uri.parse(origin),
      incoming.map((record) {
        final parts = <String>[
          '${record.name}=${record.value}',
          'Path=${record.path}',
        ];
        if (!record.hostOnly) parts.add('Domain=${record.domain}');
        if (record.secure) parts.add('Secure');
        if (record.httpOnly) parts.add('HttpOnly');
        if (record.expiresAt != null) {
          parts.add('Expires=${formatCookieDate(
            DateTime.fromMillisecondsSinceEpoch(record.expiresAt!, isUtc: true),
          )}');
        }
        return parts.join('; ');
      }).toList(),
    );
    return incoming.length;
  }

  /// 直接把一个 Cookie 头字符串按"主机级"导入（例如从 WebView / 浏览器复制出来的会话）。
  int adoptCookieHeader(String header, Uri url, {bool? secure}) {
    final isSecure = secure ?? url.scheme == 'https';
    final stamp = _clock();
    var count = 0;
    for (final part in header.split(';')) {
      final separator = part.indexOf('=');
      if (separator <= 0) continue;
      final name = part.substring(0, separator).trim();
      if (!_cookieName.hasMatch(name)) continue;
      final record = CookieRecord(
        name: name,
        value: part.substring(separator + 1).trim(),
        domain: url.host.toLowerCase(),
        path: '/',
        hostOnly: true,
        secure: isSecure,
        httpOnly: false,
        expiresAt: null,
        createdAt: stamp,
        setByHost: url.host.toLowerCase(),
        setByPort: url.hasPort ? url.port : (url.scheme == 'https' ? 443 : 80),
      );
      _records.removeWhere((existing) => _sameIdentity(existing, record));
      _records.add(record);
      count += 1;
    }
    return count;
  }

  /// 清空 Cookie，并递增会话世代（等价原项目 `AcademicSession.invalidate()`）。
  void invalidate() {
    _records.clear();
    _era += 1;
  }

  void clear() => _records.clear();

  CookieStoreSnapshot export() => CookieStoreSnapshot(
        version: 1,
        baseUrl: baseUrl,
        savedAt: _clock(),
        cookies: list(),
      );

  /// 从快照恢复。已过期的条目会被丢弃。
  void import(CookieStoreSnapshot snapshot) {
    if (snapshot.version != 1) {
      throw AcademicError(ErrorCode.validationFailed, 'Cookie 快照格式不受支持');
    }
    if (snapshot.baseUrl.isNotEmpty) baseUrl = snapshot.baseUrl;
    final now = _clock();
    for (final record in snapshot.cookies) {
      if (record.expiresAt != null && record.expiresAt! <= now) continue;
      _records.removeWhere((existing) => _sameIdentity(existing, record));
      _records.add(record);
    }
  }

  /// 把一个 Cookie 头字符串按当前 baseUrl 的主机导入。
  void importCookieHeader(String header) {
    if (baseUrl.isEmpty) {
      throw AcademicError(
          ErrorCode.validationFailed, '导入 Cookie 头前需要先设置 baseUrl');
    }
    adoptCookieHeader(header, Uri.parse(baseUrl));
  }

  factory CookieStore.fromSnapshot(
    CookieStoreSnapshot snapshot, {
    String baseUrl = '',
    int Function()? now,
  }) {
    final store = CookieStore(baseUrl: baseUrl, now: now);
    store.import(snapshot);
    return store;
  }

  /// 从 `Cookie: a=1; b=2` 这样的头字符串建一个存储（其它项目的 HTTP 客户端也能直接用）。
  factory CookieStore.fromCookieHeader(
    String header,
    Uri url, {
    int Function()? now,
  }) {
    final store = CookieStore(baseUrl: url.toString(), now: now);
    store.adoptCookieHeader(header, url);
    return store;
  }

  List<CookieRecord> _live([int? now]) {
    final at = now ?? _clock();
    _records.removeWhere(
      (record) => record.expiresAt != null && record.expiresAt! <= at,
    );
    return _records;
  }
}
