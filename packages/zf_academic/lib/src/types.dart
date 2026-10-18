/// 公共数据契约。
///
/// 登录态、学期、课表与课表备注等对外类型都定义在这里。协议层与 UI 之间只通过
/// 这些类型通信，所以协议层可以脱离 Flutter 单独测试。
library;

import 'cookies.dart';
import 'dart:typed_data';

// ---------------------------------------------------------------------------
// 登录
// ---------------------------------------------------------------------------

/// 登录成功。
final class AuthenticatedState implements AuthState {
  final String studentId;
  final String studentName;

  const AuthenticatedState(
      {required this.studentId, required this.studentName});
}

/// 需要验证码。`imageBase64` 是原始图片字节的 base64（不带 data: 前缀）。
final class CaptchaState implements AuthState {
  final String continuationId;
  final String imageBase64;
  final String mimeType;

  const CaptchaState({
    required this.continuationId,
    required this.imageBase64,
    required this.mimeType,
  });
}

/// 学校要求走统一认证 / 网页端人工验证，调用方需要打开 [url] 并在 [completionUrl] 结束。
final class WebLoginState implements AuthState {
  final String continuationId;
  final String url;
  final String completionUrl;

  const WebLoginState({
    required this.continuationId,
    required this.url,
    required this.completionUrl,
  });
}

sealed class AuthState {}

enum SessionStatus {
  authenticated('authenticated'),
  expired('expired'),

  /// 无法确认（页面 404 / 结构变化 / 读取失败）——不等于失效，不得驱动重新登录。
  unknown('unknown');

  final String wire;
  const SessionStatus(this.wire);
}

/// `checkSession()` 的返回：只可能是已登录或会话失效。
final class SessionState {
  final SessionStatus status;
  final String studentId;
  final String studentName;

  const SessionState({
    required this.status,
    required this.studentId,
    required this.studentName,
  });
}

// ---------------------------------------------------------------------------
// 学期与课表
// ---------------------------------------------------------------------------

final class Term {
  final String id;
  final String name;
  final int? year;
  final int? semester;

  const Term({required this.id, required this.name, this.year, this.semester});
}

final class Terms {
  final List<Term> items;
  final String currentId;

  const Terms({required this.items, required this.currentId});
}

final class ScheduleDetail {
  final String id;
  final String label;
  final String value;

  const ScheduleDetail({
    required this.id,
    required this.label,
    required this.value,
  });
}

/// 与 SDK `ScheduleEntry` 一致：同一门课按连续节次拆成多条，`id` 稳定可去重。
final class ScheduleEntry {
  final List<ScheduleDetail>? details;
  final String id;
  final String name;
  final String? teacher;
  final String? location;
  final int day;
  final int startPeriod;
  final int endPeriod;
  final List<int> weeks;

  const ScheduleEntry({
    this.details,
    required this.id,
    required this.name,
    this.teacher,
    this.location,
    required this.day,
    required this.startPeriod,
    required this.endPeriod,
    required this.weeks,
  });
}

final class Schedule {
  final String termId;
  final List<ScheduleEntry> entries;

  /// 课表"备注"：教务在课表页底部给出的**实践课程 / 其他课程**（来自响应的 `sjkList`）。
  final List<ScheduleRemark> remarks;
  final int maxWeeks;

  const Schedule({
    required this.termId,
    required this.entries,
    this.remarks = const <ScheduleRemark>[],
    required this.maxWeeks,
  });
}

/// 一条课表"备注"（实践课程 / 其他课程）。
///
/// 教务在课表查询响应里除 `kbList`（有固定时间的课）外，还会给一份 `sjkList`，
/// 对应网页课表最下方"备注"里的**实践课程**与**其他课程**：
///  - `sfsjk = 1` → 实践课程；`sfsjk = 0` → 其他课程；
///  - `sjkcgs` 是教务网页上显示的字段（实践/其他课程的内容）。
class ScheduleRemark {
  const ScheduleRemark({
    required this.practical,
    required this.content,
    this.courseName,
    this.teacher,
    this.weeks,
    this.location,
  });

  /// true = 实践课程（`sfsjk = 1`）；false = 其他课程（`sfsjk = 0`）。
  final bool practical;

  /// 教务网页显示的字段（`sjkcgs`）。
  final String content;

  /// 课程名（`kcmc`），可选。
  final String? courseName;

  /// 教师（`xm`），可选。
  final String? teacher;

  /// 周次（`zcd`），可选。
  final String? weeks;

  /// 地点（校区 + 教室），可选。
  final String? location;
}

final class Page<T> {
  final List<T> items;
  final String? nextCursor;

  const Page({required this.items, this.nextCursor});
}

// ---------------------------------------------------------------------------
// 学校配置
// ---------------------------------------------------------------------------

/// 支持的新正方教务系统子类型（仅本模块覆盖范围）。
enum AcademicSystemId { zf }

enum SchoolProtocol { http, https }

final class SchoolAddress {
  final SchoolProtocol protocol;

  /// 形如 `jw.example.edu.cn` 或 `jw.example.edu.cn:8080`。
  final String domain;

  /// 应用根路径，形如 `/jwglxt`；没有则传空串。
  final String basePath;

  const SchoolAddress({
    required this.protocol,
    required this.domain,
    required this.basePath,
  });
}

/// 新正方端点与 gnmkdm 默认值，取自原项目 `SchoolConfig.java`。
final class ZfEndpoints {
  final String loginPagePath;
  final String publicKeyPath;
  final String captchaPath;
  final String studentInfoPath;
  final String schedulePath;
  final String scheduleGnmkdm;
  final String gradesPath;
  final String gradeGnmkdm;

  const ZfEndpoints({
    this.loginPagePath = '/xtgl/login_slogin.html',
    this.publicKeyPath = '/xtgl/login_getPublicKey.html',
    this.captchaPath = '/kaptcha',
    this.studentInfoPath = '/xtgl/index_cxYhxxIndex.html',
    this.schedulePath = '/kbcx/xskbcx_cxXsKb.html',
    this.scheduleGnmkdm = 'N253508',
    this.gradesPath = '/cjcx/cjcx_cxDgXscj.html',
    this.gradeGnmkdm = 'N305005',
  });

  ZfEndpoints copyWith({
    String? loginPagePath,
    String? publicKeyPath,
    String? captchaPath,
    String? studentInfoPath,
    String? schedulePath,
    String? scheduleGnmkdm,
    String? gradesPath,
    String? gradeGnmkdm,
  }) {
    return ZfEndpoints(
      loginPagePath: loginPagePath ?? this.loginPagePath,
      publicKeyPath: publicKeyPath ?? this.publicKeyPath,
      captchaPath: captchaPath ?? this.captchaPath,
      studentInfoPath: studentInfoPath ?? this.studentInfoPath,
      schedulePath: schedulePath ?? this.schedulePath,
      scheduleGnmkdm: scheduleGnmkdm ?? this.scheduleGnmkdm,
      gradesPath: gradesPath ?? this.gradesPath,
      gradeGnmkdm: gradeGnmkdm ?? this.gradeGnmkdm,
    );
  }
}

enum RequestPurpose { auth, query }

final class RequestLog {
  final String method;
  final String url;
  final int status;
  final RequestPurpose purpose;

  const RequestLog({
    required this.method,
    required this.url,
    required this.status,
    required this.purpose,
  });
}

/// 建立一个新正方客户端所需的全部外部事实。只填 [baseUrl] 也能用。
final class ZfClientConfig {
  /// 教务系统地址，可带路径。例：`https://jw.example.edu.cn/jwglxt`。
  final String baseUrl;
  final SchoolAddress? address;
  final List<String>? allowedHosts;
  final String? pageCharset;
  final String? userAgent;
  final String? casLoginUrl;
  final String? casServiceUrl;
  final ZfEndpoints? endpoints;

  /// 已保存的 Cookie 快照，用于免登录恢复会话。
  final CookieStoreSnapshot? cookies;
  final int? requestTimeoutMs;
  final int? maxRedirects;
  final int? maxBodyBytes;
  final Map<String, int>? paceHosts;
  final void Function(RequestLog info)? onRequest;

  /// 调试钩子：登录流程的关键中间产物，不含密码明文与 Cookie 值。
  final void Function(String event, Map<String, Object?> data)? onDebug;

  /// 注入 HTTP 传输层（默认 dart:io 实现见 `zf_academic_io.dart` 的
  /// [vmZhengfangClient]；测试可注入假传输）。为 null 时抛 UnsupportedError。
  final ZfHttpTransport? transport;

  /// 传输层的销毁回调（例如 `DartIoTransport.close`），由 `ZhengfangClient.close()` 调用。
  final void Function()? onDispose;

  const ZfClientConfig({
    required this.baseUrl,
    this.address,
    this.allowedHosts,
    this.pageCharset,
    this.userAgent,
    this.casLoginUrl,
    this.casServiceUrl,
    this.endpoints,
    this.cookies,
    this.requestTimeoutMs,
    this.maxRedirects,
    this.maxBodyBytes,
    this.paceHosts,
    this.onRequest,
    this.onDebug,
    this.transport,
    this.onDispose,
  });
}

// ---------------------------------------------------------------------------
// HTTP 传输层契约（实现见 dart_io_transport.dart；测试可注入假实现）
// ---------------------------------------------------------------------------

/// 一次原始传输的输入。
final class RawHttpRequest {
  final String method;
  final Uri url;
  final Map<String, String> headers;

  /// 已编码的表单体；GET 为 null。
  final String? body;

  const RawHttpRequest({
    required this.method,
    required this.url,
    required this.headers,
    this.body,
  });
}

/// 一次原始传输的输出。`headers` 是小写键，**保留多值**（set-cookie 必须逐条）。
final class RawHttpResponse {
  final int status;

  /// 最终地址（重定向链上的最后一跳由调用方自行跟踪）。
  final String url;
  final Uint8List bytes;
  final Map<String, List<String>> headers;

  const RawHttpResponse({
    required this.status,
    required this.url,
    required this.bytes,
    required this.headers,
  });
}

/// 传输层函数类型。默认实现 `DartIoTransport`；测试可注入假实现。
typedef ZfHttpTransport = Future<RawHttpResponse> Function(
    RawHttpRequest request);

/// `probe()` 的返回：**不提交任何凭据**，只回答"这个地址是不是新正方、
/// 登录页要什么、是否走统一认证"。
final class ZfProbeReport {
  final String baseUrl;
  final String loginPageUrl;
  final bool reachable;
  final int? httpStatus;
  final bool looksLikeZhengfang;
  final bool requiresCas;
  final String? casLoginUrl;
  final bool captchaRequired;
  final bool passwordEncryption;
  final bool hasCookies;
  final List<String> notes;

  const ZfProbeReport({
    required this.baseUrl,
    required this.loginPageUrl,
    required this.reachable,
    this.httpStatus,
    required this.looksLikeZhengfang,
    required this.requiresCas,
    this.casLoginUrl,
    required this.captchaRequired,
    required this.passwordEncryption,
    required this.hasCookies,
    required this.notes,
  });
}
