/// 测试用假后端与假存储：让编排逻辑（单 flight / 熔断 / 回滚 / 验证码）
/// 可以在没有网络、没有平台通道的情况下被确定性验证。
library;

import 'package:qustschedule/src/backends.dart';
import 'package:qustschedule/src/schedule_cache.dart';
import 'package:qustschedule/src/session_repository.dart';
import 'package:zf_academic/zf_academic_io.dart';

Schedule sampleSchedule([String termId = '2026-2027-1']) => Schedule(
  termId: termId,
  maxWeeks: 16,
  entries: const <ScheduleEntry>[
    ScheduleEntry(
      id: 'e1',
      name: '电力电子技术',
      teacher: '李云超',
      location: '高密校区 M1-239',
      day: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: <int>[1, 2, 3, 4],
    ),
  ],
);

CookieStoreSnapshot snapshotOf(String baseUrl, {String value = 'old'}) =>
    CookieStoreSnapshot(
      version: 1,
      baseUrl: baseUrl,
      savedAt: 1,
      cookies: <CookieRecord>[
        CookieRecord(
          name: 'JSESSIONID',
          value: value,
          domain: Uri.parse(baseUrl).host,
          path: '/',
          hostOnly: true,
          secure: true,
          httpOnly: true,
          expiresAt: null,
          createdAt: 1,
          setByHost: Uri.parse(baseUrl).host,
          setByPort: 443,
        ),
      ],
    );

List<ExamItem> sampleExams([String termId = '2026-2027-1']) => <ExamItem>[
  ExamItem(
    courseName: '大学物理B',
    examType: '$termId期末考试',
    startTime: DateTime(2026, 12, 25, 8, 30),
    endTime: DateTime(2026, 12, 25, 10, 30),
    campus: '崂山校区',
    classroom: '弘毅楼 201',
    seatNumber: '32',
    examForm: '闭卷',
    rawTimeStr: '2026-12-25 08:30-10:30',
    status: '正常',
  ),
  ExamItem(
    courseName: '离散数学',
    examType: '$termId期末考试',
    startTime: DateTime(2026, 12, 28, 14, 0),
    endTime: DateTime(2026, 12, 28, 16, 0),
    campus: '崂山校区',
    classroom: '弘毅楼 305',
    seatNumber: '15',
    examForm: '闭卷',
    rawTimeStr: '2026-12-28 14:00-16:00',
    status: '正常',
  ),
];

List<GradeItem> sampleGrades([String termId = '2026-2027-1']) => <GradeItem>[
  GradeItem(
    courseName: '高等数学A(1)',
    courseCode: 'MATH101',
    credit: 4.5,
    gradePoint: 4.0,
    rawScore: '90',
    numericScore: 90.0,
    courseNature: '必修',
    courseCategory: '通识必修',
    examNature: '正常考试',
    termId: termId,
  ),
  GradeItem(
    courseName: '大学英语(1)',
    courseCode: 'ENG101',
    credit: 3.0,
    gradePoint: 3.5,
    rawScore: '85',
    numericScore: 85.0,
    courseNature: '必修',
    courseCategory: '通识必修',
    examNature: '正常考试',
    termId: termId,
  ),
];

/// 假客户端：按注入的行为脚本响应，并记录调用次数。
class FakeBackend implements ScheduleBackend {
  FakeBackend({
    this.fetchBehavior,
    this.examsBehavior,
    this.gradesBehavior,
    this.loginBehavior,
    this.submitBehavior,
    this.termsBehavior,
    this.studentId = '20240001',
    this.studentName = '测试学生',
    this.checkSessionReadsIdentity = true,
    this.sessionExpired = false,
    CookieStoreSnapshot? cookies,
  }) : cookies = cookies ?? snapshotOf('https://jw.example.edu.cn/jwglxt');

  /// 当前"已知"的身份。默认就是已登录状态；测试可置空来模拟
  /// "Cookie 有效但客户端还不知道我是谁"（冷启动免登）。
  String studentId;
  String studentName;

  /// `checkSession()` 能否读到身份。
  bool checkSessionReadsIdentity;

  /// 会话是否已失效。
  bool sessionExpired;

  int checkSessionCount = 0;

  Future<Schedule> Function(int call, String? termId)? fetchBehavior;
  Future<List<ExamItem>> Function(int call, String? termId)? examsBehavior;
  Future<List<GradeItem>> Function(int call, String? termId)? gradesBehavior;
  Future<AuthState> Function(int call, Credentials credentials)? loginBehavior;
  Future<AuthState> Function(int call, String code)? submitBehavior;
  Future<Terms> Function(int call)? termsBehavior;

  CookieStoreSnapshot cookies;

  int fetchCount = 0;
  int examsCount = 0;
  int gradesCount = 0;
  int termsCount = 0;
  int loginCount = 0;
  int submitCount = 0;
  int refreshCount = 0;
  int importCount = 0;
  int closeCount = 0;

  /// 最近一次 importCookies 收到的快照（回滚断言）。
  CookieStoreSnapshot? lastImported;

  @override
  Future<Schedule> fetchSchedule([String? termId]) async {
    fetchCount++;
    final behavior = fetchBehavior;
    if (behavior != null) return behavior(fetchCount, termId);
    return sampleSchedule(termId ?? '2026-2027-1');
  }

  @override
  Future<List<ExamItem>> fetchExams([String? termId]) async {
    examsCount++;
    final behavior = examsBehavior;
    if (behavior != null) return behavior(examsCount, termId);
    return sampleExams(termId ?? '2026-2027-1');
  }

  @override
  Future<List<GradeItem>> fetchGrades([String? termId]) async {
    gradesCount++;
    final behavior = gradesBehavior;
    if (behavior != null) return behavior(gradesCount, termId);
    return sampleGrades(termId ?? '2026-2027-1');
  }

  @override
  Future<Terms> fetchTerms() async {
    termsCount++;
    final behavior = termsBehavior;
    if (behavior != null) return behavior(termsCount);
    return const Terms(
      currentId: '2026-2027-1',
      items: <Term>[Term(id: '2026-2027-1', name: '2026-2027 第1学期')],
    );
  }

  @override
  Future<AuthState> login(Credentials credentials) async {
    loginCount++;
    // 真客户端的 login() 入口会先作废旧 Cookie，这里如实模拟。
    cookies = snapshotOf('https://jw.example.edu.cn/jwglxt', value: '');
    final behavior = loginBehavior;
    if (behavior != null) return behavior(loginCount, credentials);
    cookies = snapshotOf('https://jw.example.edu.cn/jwglxt', value: 'fresh');
    return const AuthenticatedState(studentId: '20240001', studentName: '测试学生');
  }

  @override
  Future<AuthState> submitCaptcha(String code) async {
    submitCount++;
    final behavior = submitBehavior;
    if (behavior != null) return behavior(submitCount, code);
    cookies = snapshotOf('https://jw.example.edu.cn/jwglxt', value: 'fresh');
    return const AuthenticatedState(studentId: '20240001', studentName: '测试学生');
  }

  @override
  Future<CaptchaState> refreshCaptcha() async {
    refreshCount++;
    return const CaptchaState(
      continuationId: 'c2',
      imageBase64: 'iVBORw0KGgo=',
      mimeType: 'image/png',
    );
  }

  @override
  Future<SessionState> checkSession() async {
    checkSessionCount++;
    if (sessionExpired) {
      return const SessionState(
        status: SessionStatus.expired,
        studentId: '',
        studentName: '',
      );
    }
    if (checkSessionReadsIdentity) {
      studentId = '20240001';
      studentName = '测试学生';
    }
    return SessionState(
      status: SessionStatus.authenticated,
      studentId: studentId,
      studentName: studentName,
    );
  }

  @override
  CookieStoreSnapshot exportCookies() => cookies;

  @override
  void importCookies(CookieStoreSnapshot snapshot) {
    importCount++;
    lastImported = snapshot;
    cookies = snapshot;
  }

  @override
  SessionInfo get session => SessionInfo(
    username: studentId,
    studentId: studentId,
    studentName: studentName,
    authenticated: studentId.isNotEmpty || studentName.isNotEmpty,
  );

  @override
  String get cookieHeader => cookies.cookies.isEmpty ? '' : 'JSESSIONID=x';

  /// 调试数据：测试里可以注入，用来验证 DebugPage 的渲染。
  @override
  String? lastScheduleRawBody;

  @override
  List<Map<String, dynamic>> lastScheduleRows = const <Map<String, dynamic>>[];

  @override
  String? lastTermsRawBody;

  @override
  void close() => closeCount++;
}

/// 内存 Cookie 存储，记录写入次数与最后快照。
class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository([this.snapshot]);

  CookieStoreSnapshot? snapshot;
  int saveCount = 0;
  int clearCount = 0;

  @override
  Future<CookieStoreSnapshot?> load() async => snapshot;

  @override
  Future<void> save(CookieStoreSnapshot value) async {
    saveCount++;
    snapshot = value;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    snapshot = null;
  }
}

/// 内存课表缓存，记录写入/清空次数与最后写入的内容。
class FakeScheduleCache implements ScheduleCache {
  FakeScheduleCache([this.cached]);

  CachedSchedule? cached;
  int saveCount = 0;
  int clearCount = 0;
  CachedSchedule? lastSaved;

  @override
  Future<CachedSchedule?> load() async => cached;

  @override
  Future<void> save(CachedSchedule value) async {
    saveCount++;
    lastSaved = value;
    cached = value;
  }

  @override
  Future<void> clear() async {
    clearCount++;
    cached = null;
  }
}

/// 常见的失效错误。
AcademicError expired() =>
    const AcademicError(ErrorCode.sessionExpired, '会话已过期', httpStatus: 302);

AcademicError pageChanged() =>
    const AcademicError(ErrorCode.pageChanged, '页面结构变化');

AcademicError badCredentials() =>
    const AcademicError(ErrorCode.invalidCredentials, '用户名或密码不正确');
