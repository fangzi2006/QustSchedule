/// zf_academic —— 新正方教务系统客户端基座（Dart）。
///
/// ```dart
/// import 'package:zf_academic/zf_academic.dart';
///
/// // 1. 凭据（app 侧应注入 flutter_secure_storage 实现，见 example/）
/// final credentials = Credentials('20240001', '…');
/// final store = InMemoryCredentialStore()..save('qust', credentials);
///
/// // 2. Cookie（登录成功后 export()，之后 fromSnapshot() 恢复）
/// final cookies = CookieStore(baseUrl: 'https://jw.example.edu.cn/jwglxt');
///
/// // 3. 密码加密
/// final mm = zfFormEncryptPassword(modulusBase64, 'AQAB', '…');
/// ```
///
/// 本入口是**纯 Dart**（无 Flutter 依赖）。依赖 dart:io 的文件持久化与默认传输层
/// 在 `zf_academic_io.dart` 入口里导出。
library zf_academic;

export 'src/cookies.dart' show CookieRecord, CookieStore, CookieStoreSnapshot;
export 'src/credential_store.dart'
    show
        CredentialStore,
        Credentials,
        InMemoryCredentialStore,
        credentialStoreKey;
export 'src/crypto.dart' show zfCasEncryptPassword, zfFormEncryptPassword;
export 'src/errors.dart' show AcademicError, ErrorCode, asAcademicError;
export 'src/schedule.dart' show defaultMaxWeeks, maxWeeksOf;
export 'src/types.dart'
    show
        AuthState,
        AuthenticatedState,
        CaptchaState,
        ExamItem,
        GradeItem,
        RawHttpRequest,
        RawHttpResponse,
        RequestLog,
        RequestPurpose,
        Schedule,
        ScheduleDetail,
        ScheduleEntry,
        ScheduleRemark,
        SchoolAddress,
        SchoolProtocol,
        SessionState,
        SessionStatus,
        Term,
        Terms,
        WebLoginState,
        ZfClientConfig,
        ZfEndpoints,
        ZfHttpTransport,
        ZfProbeReport,
        qustZfEndpoints;
export 'src/urls.dart' show calendarTerm, parseTerm;
export 'src/zhengfang_client.dart' show SessionInfo, ZhengfangClient;
