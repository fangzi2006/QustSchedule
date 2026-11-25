# 核心状态、服务编排、持久化、更新系统与正方协议层 AI 速查手册 (`CORE_AND_STATE.md`)

> **定位**：本文档面向 AI 开发会话，提供 `qustschedule/` 核心状态协调器（`AppModel` 与 5 大子控制器）、业务编排服务、安全 JSON 持久化、应用内更新状态机、Windows 桌面原生壳以及 `packages/zf_academic/` 纯 Dart 协议基座的**零源码重读级（Zero-Re-Read）**精确技术契约。
> **铁律**：应用版本号的唯一事实源为 `pubspec.yaml` 的 `version:` 字段（运行时通过 `lib/src/app_version.dart` 读取 `rootBundle`），严禁在任何代码或文档中硬编码应用版本号。

---

## 0. 快速目录（Quick TOC）与文件/符号速查表

### 0.1 章节导航
- [1. 状态架构与局部通知频道 (`AppModel` & `lib/src/state/*`)](#1-状态架构与局部通知频道-appmodel--libsrcstate)
- [2. 核心并发、世代令牌与互斥不变量 (Concurrency & Mutex Invariants)](#2-核心并发世代令牌与互斥不变量-concurrency--mutex-invariants)
- [3. 业务服务与离线缓存层 (`ScheduleService`, `AcademicService`, Caches, School, TermSelector)](#3-业务服务与离线缓存层-scheduleservice-academicservice-caches-school-termselector)
- [4. 课表排布、校历换算、调课叠加与工具库 (`timetable`, `term_calendar`, `reschedule`, `route_settled`)](#4-课表排布校历换算调课叠加与工具库-timetable-term_calendar-reschedule-route_settled)
- [5. 持久化与安全存储层 (`Preferences` Schema 15, `SafeJsonFile`, Credentials, Session)](#5-持久化与安全存储层-preferences-schema-15-safejsonfile-credentials-session)
- [6. 应用内更新与跨平台安装器 (`lib/src/updater/*`, `AppUpdaterBridge.kt`, Windows 热替换)](#6-应用内更新与跨平台安装器-libsrcupdater-appupdaterbridgekt-windows-热替换)
- [7. Windows 桌面原生壳与安装包 (`windows/runner/*`, `windows/packaging/setup.iss`)](#7-windows-桌面原生壳与安装包-windowsrunner-windowspackagingsetupiss)
- [8. `packages/zf_academic` 纯 Dart 教务协议层参考](#8-packageszf_academic-纯-dart-教务协议层参考)

### 0.2 全局文件与核心符号速查表 (Symbol-to-File Lookup Table)

| 模块域 | 精确路径（相对于 `qustschedule/`） | 核心导出类 / 枚举 / 函数 | 职责与核心契约摘要 |
| :--- | :--- | :--- | :--- |
| **状态总协调器** | `lib/src/app_model.dart` | `AppModel`, `AppStatus` | 串联 5 大专职控制器；管理 `routeNotifier`、`_authEpoch`、`_idleAcademicRestoreTimer`、冷启动 `boot()` 与前后台 `onAppShown()` |
| **认证会话控制器** | `lib/src/state/auth_session_controller.dart` | `AuthSessionController` | 管理 `ScheduleService`、`schoolBaseUrl`、`username`、`studentId`、`studentName`、验证码挂起 `Completer` 与请求调试日志 |
| **课表周历控制器** | `lib/src/state/schedule_controller.dart` | `ScheduleController`, `WeekNotifier` | 管理 `Schedule`、`Terms`、`week`、`weekNotifier`、`refreshingNotifier`、校历校准、调课视图与冲突布局记忆化缓存（`_dataRevision`） |
| **学业数据控制器** | `lib/src/state/academic_controller.dart` | `AcademicController` | 管理 `exams`、`grades`、`gradeStats`（引用记忆化）、`isNotEvaluated`、`_academicLoadSeq`、静默后台同步与差异比对提示 |
| **偏好与防抖控制器** | `lib/src/state/preferences_controller.dart` | `PreferencesController` | 封装 `Preferences` 读写、外观滑块 300ms 草稿防抖（`_cellHeightDraft`/`_courseTextScaleDraft`）、存储故障监控、启动延迟自动检查更新 |
| **提示气泡控制器** | `lib/src/state/hint_notice_controller.dart` | `HintNoticeController`, `HintScope` | 隔离 `global`/`schedule`/`academic` 三作用域提示气泡、一次性存储异常计数 `storageNoticeEvent`、`humanizeError` 错误码转中文 |
| **课表编排服务** | `lib/src/schedule_service.dart` | `ScheduleService` | Cookie 优先取课表/学期/考试/成绩；`SESSION_EXPIRED` 触发全局单 flight 重登（`_reloginFlight`）、旧 Cookie 快照回滚、10 分钟 2 次熔断器 |
| **客户端测试门面** | `lib/src/backends.dart` | `ScheduleBackend`, `ZfBackend`, `defaultBackendFactory` | 收窄 `ZhengfangClient` 接口供 `ScheduleService` 依赖注入与单元测试假实现替换 |
| **学业编排与绩点** | `lib/src/academic_service.dart` | `AcademicService`, `GradeStats` | 抓取并缓存考试/成绩；处理 `ErrorCode.notEvaluated` 保留旧成绩并标记未评教；按教务原生 `jd` 计算加权 GPA |
| **课表离线缓存** | `lib/src/schedule_cache.dart` | `CachedSchedule`, `ScheduleCache`, `FileScheduleCache`, `LateScheduleCache` | 持久化 `zf-schedule-cache.json`（含 `baseUrl`、`fetchedAt`、`schedule` 完整条目与 `remarks`） |
| **学业离线缓存** | `lib/src/academic_cache.dart` | `CachedTermExams`, `ExamCache`, `FileExamCache`, `CachedTermGrades`, `GradesCache`, `FileGradesCache`, `InMemory*`, `Late*` | 按 `termId` 分桶持久化 `zf-exam-cache.json` 与 `zf-grades-cache.json`，基于 `SafeJsonFile.updateJson` 原子合并 |
| **学期筛选与换算** | `lib/src/term_selector_helper.dart` | `parseEnrollmentYear`, `estimateCurrentAcademicYear`, `filterTerms`, `resolveSemesterCode`, `formatTermPrimaryLabel` | 从 10 位/8 位/4 位学号推算入学年；过滤入学前与超前未来学期及短学期（`xqm=16`）；映射「大一~大五 上/下学期」 |
| **学校与线路配置** | `lib/src/school.dart` | `SchoolProfile`, `qustProfile`, `qustLines`, `knownSchools`, `presetSchoolUrls`, `defaultSchool`, `schoolLabel`, `sameSchool` | 青科大默认教务前端线路（`https://jwglxt.qust.edu.cn/jwglxt`）预设与 URL 归一化比对（忽略协议与末尾斜杠） |
| **作息时间表** | `lib/src/timetable.dart` | `PeriodGroup`, `SectionTime`, `BigBreak`, `Timetable`, `QuickSetup`, `buildSections`, `activeTimetableAt`, `reconcileSections` | 多套作息表按「月日 (`month*100+day`)」跨年循环自动切换；全局三段节数（上午/下午/晚上）逐段对齐 |
| **学期校历换算** | `lib/src/term_calendar.dart` | `dayOnly`, `mondayOf`, `estimateTermStart`, `weekOf`, `dateOf`, `termStartFromWeek`, `weekRangeLabel`, `conflictLayout` | 学期第 1 周周一估算与反推、日期与周次互转、同天重叠课程并列槽位（`index, total`）计算 |
| **按日调课叠加** | `lib/src/reschedule.dart` | `RescheduleRule`, `RescheduleConflict`, `RescheduleWeekView`, `rescheduleWeekView` | 纯渲染层按实例（「X月X日 → Y月Y日」）调课叠加，不改原始 `Schedule`；冲突时调入课优先并记录被顶掉的原课 |
| **课程地点文本** | `lib/src/course_text.dart` | `roomOnly` | 课表格子与课程提醒共用的地点短名提取（取空白分隔最后一段并剥离 `^.*?校区` 前缀） |
| **轻量行内富文本** | `lib/src/formatted_text_span.dart` | `FormattedSegmentKind`, `FormattedSegment`, `parseFormattedSegments`, `buildTextSpanFromSegments`, `buildFormattedTextSpan` | 零外部依赖解析 `**加粗**` 与 `` `行内代码` ``，支持后台 Isolate 预解析为纯 Dart `FormattedSegment` |
| **路由落稳与后台计算** | `lib/src/route_settled.dart` | `runInBackground`, `RouteSettledHandle`, `scheduleAfterRouteSettled`, `RouteSettledStateMixin`, `RouteSettledGate` | 入场动画与后台 Isolate 数据加载并行；重子树避让 260ms 转场，在离开 `offstage` 且 `completed` 瞬间粘性挂载 |
| **动态版本号读取** | `lib/src/app_version.dart` | `appVersion`, `appVersionFull`, `loadAppVersion` | 启动时从打包资产 `pubspec.yaml` 解析 `version:`，唯一版本事实源 |
| **偏好设置持久化** | `lib/src/preferences_repository.dart` | `Preferences`, `preferencesSchema` (15), `presetUpdateProxies` | 管理 `app_prefs.json`（Schema 15 覆盖式教务地址、全字段读写、旧版自动迁移、损坏标志 `didResetFromCorruption`） |
| **安全凭据存储** | `lib/src/credentials_repository.dart` | `SecureCredentialStore` | 基于 `flutter_secure_storage` v11（Android Keystore / Windows DPAPI）存储 SHA-256 哈希键名的账密 |
| **会话快照仓库** | `lib/src/session_repository.dart` | `SessionRepository`, `FileSessionRepository`, `LateSessionRepository` | 封装 `zf-session.json` Cookie 快照持久化 |
| **安全 JSON 管家** | `lib/src/safe_json_file.dart` | `SafeJsonFile`, `SafeJsonReadResult`, `isolateJsonDecodeThreshold` (16KB) | 路径级串行队列、连续写入合并（1 写 + 1 待写）、`.tmp` 原子替换、`.bak` 自动备份与自愈、`>=16KB` Isolate 解码 |
| **更新流程状态机** | `lib/src/updater/update_flow_controller.dart` | `UpdateFlowController`, `UpdateFlowStage` | 脱离弹窗生命周期的全局更新状态机：版本复用、后台下载、SHA256 校验、Android 权限自动续装 |
| **更新网络服务** | `lib/src/updater/update_service.dart` | `UpdateService`, `CancelToken` | GitHub Release 检查、代理节点轮询回退、Range 探测、`>=4MB` 3 线程分块并发下载与单流无缝降级、历史包清理 |
| **更新数据模型** | `lib/src/updater/update_models.dart` | `ReleaseAsset`, `ReleaseInfo`, `UpdateStatus`, `UpdateCheckResult`, `DownloadProgress`, `ProxyTestResult`, `displayProxyName` | Release JSON 解析、CI 下载表模板清洗（`cleanReleaseBody`）、进度与测速模型 |
| **跨平台安装器** | `lib/src/updater/app_installer.dart` | `AppInstaller` | Android MethodChannel 调起安装；Windows 便携版 `.update_staging` 解压 + VBS/CMD 隐藏窗口 PID 轮询 + `robocopy` 热替换 / 安装版静默升级 |
| **语义版本比对** | `lib/src/updater/version_comparator.dart` | `compareSemanticVersions`, `isVersionNewer` | 支持 `v`/`V` 前缀、`+build` 构建号、`-alpha/-beta/-rc` 预发布标签的语义化版本比对 |
| **Android 安装桥接** | `android/.../updater/AppUpdaterBridge.kt` | `AppUpdaterBridge` | MethodChannel `com.fangzi.qustschedule/updater`：检查未知来源权限、跳设置页、`FileProvider` 调起 APK 安装 |
| **Windows 原生壳** | `windows/runner/*`, `windows/packaging/setup.iss` | `wWinMain`, `FlutterWindow`, `Win32Window` | 单实例命名互斥量 `Local\com.fangzi.qustschedule.SingleInstance`（30×100ms 退避等待唤醒旧窗口）、最小尺寸 `360×520` 逻辑像素、深色标题栏跟随 |
| **正方协议核心包** | `packages/zf_academic/lib/*` | `ZhengfangClient`, `AcademicHttpClient`, `CookieStore`, `FileCookieStorage`, `ErrorCode`, `AcademicError` | 纯 Dart 零 Flutter 依赖教务客户端：表单 RSA 登录、验证码续期、课表/学期/考试/成绩解析、主机白名单与重定向安全策略 |

---

## 1. 状态架构与局部通知频道 (`AppModel` & `lib/src/state/*`)

### 1.1 状态机分层与 `Listenable` 局部订阅表（防整页白刷契约）

`AppModel` 作为外观门面（Facade）保持所有外部 API 兼容，内部将状态拆分为 **5 大专职控制器** 与 **7 个独立监听源**。UI 组件必须按最小作用域订阅对应的 `Listenable`，严禁盲目订阅顶层 `AppModel` 导致课表网格或外壳重绘：

| 监听源 (`Listenable`) | 暴露位置 | 触发时机 | 推荐订阅方 (UI / 服务) | 绝不触发的场景 |
| :--- | :--- | :--- | :--- | :--- |
| `model.routeNotifier` (`ChangeNotifier`) | `AppModel.routeNotifier` | 仅当 `AppStatus`、`message`、`errorCode` 变化，或 `refreshCaptcha()` 完成时 | 顶层路由切换器（决定展示启动页/登录页/验证码页/主外壳） | 周次翻页、背景刷新转圈、气泡消隐、学业加载、滑块拖动 |
| `model.hints` (`HintNoticeController`) | `AppModel.hints` | `globalHint` / `scheduleHint` / `academicHint` 显示或定时器清除；`storageNoticeEvent` 递增 | 右上角状态气泡 (`StatusPopup`)、全局存储异常 `SnackBar` 监听器 | 课表数据变更、周次切换、设置项修改 |
| `model.scheduleState` (`ScheduleController`) | `AppModel.scheduleState` | 课表数据 (`schedule`)、学期列表 (`terms`)、开学日校准 (`termStart`)、跨天同步变化 | 课表页主体网格、学期选择器 | 仅周次手势翻页 (`weekNotifier`)、仅刷新转圈 (`refreshingNotifier`) |
| `model.weekNotifier` (`WeekNotifier`) | `AppModel.weekNotifier` / `scheduleState.weekNotifier` | `goToWeek()`、`goToThisWeek()`、校准周次（支持同值强制广播 `.notify()`） | `WeekPager`、顶栏周次标题、回本周按钮 | 后台静默拉取课表、学业页刷新、提示气泡变化 |
| `model.refreshingNotifier` (`ValueNotifier<bool>`) | `AppModel.refreshingNotifier` / `scheduleState.refreshingNotifier` | 课表拉取或自动重登开始 (`true`) 与结束 (`false`) | 顶栏刷新按钮旋转动画、状态气泡加载指示器 | 课表网格卡片（网格在拉取完成前零重建） |
| `model.academic` (`AcademicController`) | `AppModel.academic` / `AppModel.academicNotifier` | `exams`、`grades`、`isNotEvaluated`、`academicLoading`、`academicError`、跨天倒计时重算 | 学业页 (`AcademicPage`) | 课表周次翻页、课表刷新、外观滑块调节 |
| `model.prefsNotifier` (`ValueNotifier<int>`) | `AppModel.prefsNotifier` / `prefs.prefsNotifier` | 任何用户偏好落盘、身份记忆更新、开学日变更、外观滑块防抖草稿更新（值自增 `++`） | 设置页、课表网格外观属性、`ReminderService`、`WidgetService` | `saveQuickSetup`（显式传 `notifyPrefsChanged: false`） |
| `model.updateFlow` (`UpdateFlowController`) | `AppModel.updateFlow` / `prefs.updateFlow` | 更新阶段 (`stage`)、下载进度 (`progress`)、代理切换、后台下载完成/失败事件序号变化 | 更新弹窗 (`UpdateDialog`)、课表顶栏更新角标 | 常规教务请求与课表操作 |

### 1.2 `AppStatus` 状态枚举与流转条件 (`lib/src/app_model.dart`)

| 枚举值 | 含义 | 进入条件 | 关联 UI 行为 |
| :--- | :--- | :--- | :--- |
| `AppStatus.booting` | 启动初始化中 | `AppModel` 初始默认值，或调用 `boot()` 时 | 展示启动加载过渡态；`isGlobalPopupActive` 为 `true` |
| `AppStatus.needLogin` | 需要手动登录 | 冷启动无缓存且无保存账密；自动重登彻底失败且无旧课表；调用 `signOut()` / `cancelCaptcha()` / `retryAfterSessionLoss()` / `changeSchool(relogin: false)` | 顶层路由切换至 `LoginPage`；清空课表与学业气泡 |
| `AppStatus.signingIn` | 手动或验证码登录中 | 调用 `signIn()` 或 `submitCaptcha()` 时 | 锁住登录按钮并展示进度；`isGlobalPopupActive` 为 `true` |
| `AppStatus.needCaptcha` | 等待输入验证码 | 手动登录返回 `CaptchaState`，或后台自动重登触发 `_handleCaptcha` 挂起 | 展示 `CaptchaPage`（区分手动登录验证码与 `hasPendingReloginCaptcha` 自动重登验证码） |
| `AppStatus.loading` | 首次无缓存拉取课表、前台重试或切换线路中 | 无本地课表缓存时的 `_loadSchedule()`、`retry()` 前台重拉课表，或 `changeSchool(relogin: true)` | 展示全局加载气泡（`StatusPopup`）；`isGlobalPopupActive` 为 `true` |
| `AppStatus.ready` | 课表就绪（主界面常驻态） | `_restoreCachedSchedule()` 命中同校缓存（0 延迟秒开），或 `_loadSchedule()` 成功 | 展示 `HomeShell`（课表页 / 学业页 / 设置页） |
| `AppStatus.failed` | 阻塞性失败（带错误文案与错误码） | 前台 `_loadSchedule()` / `signIn()` / `submitCaptcha()` / `changeSchool()` 抛错，或课表手动 `refresh()` 遇到 `sessionExpired` / `invalidCredentials` | 有离线课表时留在 `HomeShell` 并弹出常驻全局错误弹窗（提供「重试 / 重新登录」与「关闭」）；无课表时留在 `LoginPage`；`dismissError()` 有课表回 `ready`，否则回 `needLogin` |

### 1.3 `AppModel` 完整生命周期与方法签名

```dart
class AppModel extends ChangeNotifier {
  AppModel({
    ScheduleService? service,
    SessionRepository? repository,
    CredentialStore? credentials,
    Preferences? preferences,
    ScheduleCache? scheduleCache,
    ExamCache? examCache,
    GradesCache? gradesCache,
    AcademicService? academicService,
    UpdateFlowController? updateFlow,
    String? schoolBaseUrl,
    Future<Directory> Function()? supportDirectoryLoader,
  });

  // 核心编排入口
  Future<void> boot();
  Future<void> onAppShown();
  Future<void> syncSilently(); // _loadSchedule(background: true, triggerAcademic: true)
  Future<void> refresh();      // _loadSchedule(background: true, triggerAcademic: false)

  // 认证与线路切换
  Future<void> signIn(String username, String password);
  Future<void> submitCaptcha(String code);
  Future<void> refreshCaptcha();
  void cancelCaptcha();
  Future<void> changeSchool(String baseUrl, {bool relogin = true});
  Future<void> changePassword(String newPassword);
  Future<void> retry(); // 优先重试失败切校 → needsReloginError 跳登录 → 前台重拉课表
  void retryAfterSessionLoss();
  Future<void> signOut();
  void dismissError();

  // 错误动作判定只读属性
  bool get hasPendingSchoolSwitch;
  bool get canRetryError;      // schedule != null && errorCode != 'WEB_LOGIN_REQUIRED'
  bool get needsReloginError;  // 非切校失败且为 SESSION_EXPIRED / INVALID_CREDENTIALS
  bool get academicNeedsRelogin;

  // 周次与校历
  void goToWeek(int week);
  void goToThisWeek();
  Future<void> calibrateCurrentWeek(int week);
  Future<void> resetCalendar();

  // 学业数据
  void setAcademicTerm(String termId);
  Future<void> loadAcademicData({String? termId, bool forceRefresh = false, bool showHint = false});
  Future<void> refreshAcademicData({bool showHint = true});
  Future<void> clearAcademicDataForDebug();
}
```

#### `boot()` 冷启动精确流水线：
1. 取消未执行的 `_idleAcademicRestoreTimer`，状态置为 `AppStatus.booting`。
2. 若任一持久化组件（`SessionRepository` / `Preferences` / `ScheduleCache` / `ExamCache` / `GradesCache`）未由构造函数注入，调用 `supportDirectoryLoader ?? getApplicationSupportDirectory()` 获取应用私有支持目录，**并发** `Future` 打开：
   - `FileSessionRepository.open(directory: supportDir)` (`zf-session.json`)
   - `Preferences.open(directory: supportDir)` (`app_prefs.json`)
   - `FileScheduleCache.open(directory: supportDir)` (`zf-schedule-cache.json`)
   - `FileExamCache.open(directory: supportDir)` (`zf-exam-cache.json`)
   - `FileGradesCache.open(directory: supportDir)` (`zf-grades-cache.json`)
3. 将打开的实例 `rebind` 到各子控制器；若 `Preferences.didResetFromCorruption == true`，通过 `hints.emitStorageNotice('本地设置文件已损坏且无法恢复，已重置为默认设置')` 发出一次性通知；标记 `prefs.preferencesLoaded = true`（在此之前，`ReminderService` 严禁由于默认 `reminderEnabled == false` 清空系统闹钟）。
4. 调用 `session.restoreSavedSchoolIfNeeded()`（若构造函数未固定 `schoolBaseUrl`，从 `prefs.raw.currentSchool` 恢复并同步 `service.switchSchool`）与 `session.restoreAccount()`（从 `prefs.raw.accountOf(schoolBaseUrl)` 恢复 `_username`、`_studentId` 及 `service.accountHint`，从 `studentNameOf` 恢复 `_studentName`）。
5. 并发执行 `session.service.bootstrap()`（校验 Cookie 快照非空且 `sameSchool`）与 `scheduleState.scheduleCache.load()`。
6. **分支 A（命中同校离线课表缓存 `cached != null && sameSchool(cached.baseUrl, schoolBaseUrl)`）**：
   - 立即调用 `_restoreCachedSchedule(cached)`：应用课表与校历，状态直达 `AppStatus.ready`（**0 网络等待秒开**），并启动 `Timer(Duration.zero)` 延迟恢复同 `termId` 的学业离线缓存（`academic.restoreCachedData(termId)`）。
   - 若 `snapshot != null` 且姓名或学号为空，后台 `unawaited(session.syncIdentityQuietly())`。
   - 若 `snapshot != null && prefs.autoRefresh && scheduleState.shouldSilentRefresh(cached.fetchedAt)`（距上次抓取 `>= autoRefreshIntervalMinutes`），后台 `unawaited(syncSilently())`（同时静默刷新课表与当前学期学业数据）。
   - 直接 `return` 结束 `boot()`。
7. **分支 B（无可用课表缓存）**：
   - 若 `snapshot == null`，查询 `credentials.get(session.accountKey())`：有保存凭据则恢复 `session.username = saved.username` 并继续走 `_loadSchedule()`（内部触发自动重登）；无保存凭据则置为 `AppStatus.needLogin` 并返回。
   - 若 `snapshot != null`，直接 `await _loadSchedule()`。

### 1.4 五大子控制器详细契约 (`lib/src/state/*`)

#### (1) `AuthSessionController` (`lib/src/state/auth_session_controller.dart`)
- **账号凭据键拼接规则**：`accountKey({String? username}) => '$_schoolBaseUrl|${username ?? _username}'`。注意 `ScheduleService._accountKey` 内部会将 `_baseUrl` 转为 `.toLowerCase()`，且账号回退优先级为：`显式传入 username > accountHint > sessionInfo?.username ?? ''`。
- **冷启动空 `username` 兜底铁律**：免登冷启动时 `sessionInfo` 为空，必须由 `restoreAccount()` 将 `prefs.raw.accountOf(_schoolBaseUrl)` 写入 `service.accountHint` 和 `_username`。若缺少这一步，Cookie 过期触发 `_loginWithSavedCredentials()` 时拼出的 `accountKey` 为 `baseUrl|`（空账号），会导致无法从 `SecureCredentialStore` 取出密码而掉登录。
- **修改密码账号解析顺序 (`AppModel._resolveAccountForPasswordChange`)**：依次尝试 `session.service.sessionInfo?.username` -> `username` -> `session.service.accountHint` -> `studentId`，取第一个非空字符串。
- **自动重登验证码挂起机制**：当后台重登遇到验证码时，`ScheduleService` 调用 `captchaHandler` -> `AuthSessionController.handleCaptcha(state, onNeedCaptcha: ...)`，创建 `Completer<String?>` 赋给 `_captchaCompleter`（若已有未完成的旧 Completer 先 `complete(null)`），并将 `AppStatus` 切为 `needCaptcha`。此时 `hasPendingReloginCaptcha == true`。用户调用 `AppModel.submitCaptcha(code)` 时，走 `completePendingCaptcha(code)` 唤醒原 `_reloginFlight`，而非重新发起独立的 `service.submitCaptcha`。
- **切校事务性回滚 (`rollbackSchool`)**：切校 `changeSchool(relogin: true)` 前仅从内存导出 `previousCookies = service.exportCurrentCookies()`（冷启动未建客户端时为 `null`），且 `service.signIn()` 通过 `_ensureClient(loadCookies: false)` 跳过 `bootstrap()`，确保试登新校绝不误删磁盘上原校的 Cookie 快照；仅在确认 `AuthenticatedState` 后才落盘 `currentSchool` 并清理旧学业与旧课表缓存（同校重登不清空 `scheduleCache`）。若新校登录失败、遇 `WebLoginState` 或取消切校验证码，`rollbackSchool(previousBase, account: account, cookies: previousCookies)` 完整恢复 `_schoolBaseUrl`、`_username`、`service.accountHint`，且仅在内存备份非空时回写 `cookieStorage`。

#### (2) `ScheduleController` (`lib/src/state/schedule_controller.dart`)
- **周次与网格节数计算**：
  - `maxWeek`：取 `maxWeeksOf(schedule.entries)`（至少为 `defaultMaxWeeks = 18`）；用户手动校准周次 `safe > _maxWeek` 时自动撑大 `_maxWeek`。
  - `gridSectionCount`：`max(_dataMaxPeriod, _prefs.sectionCount)`。当课表实际存在超过用户配置总节数的课程时，`hasSectionsBeyondTimetable == true`，网格自动向下扩展行数以确保课程不丢失。
- **调课视图与冲突布局记忆化缓存**：
  - 缓存结构：`_rescheduleCache` (`Map<int, RescheduleWeekView>`) 与 `_conflictLayoutCache` (`Map<int, Map<String, ({int index, int total})>>`)。
  - 缓存校验 `_ensureWeekViewCacheValid()`：对比 `identical(_cachedViewSchedule, _schedule)`、`_cachedViewTermStart == _termStart`、`_cachedViewMaxWeek == _maxWeek`、`listEquals(_cachedViewRules, _prefs.reschedules)`。任一不一致或调用 `_invalidateWeekCaches()` 时清空两个 Map 并令 `_dataRevision++`。
- **跨天与回前台刷新判定 (`onAppShown`)**：
  - `syncCalendarDay()`：对比 `dayOnly(DateTime.now())` 与 `_lastSeenDay`。若跨天且用户停留在离开那天的自然周（`_week == weekOf(start, _lastSeenDay)`），自动推进 `_week` 到新一天所在的周次。
  - `shouldRefreshOnShow`：`autoRefresh && !refreshing && hasSchedule && (lastFetchedAt == null || now.difference(lastFetchedAt) >= Duration(minutes: intervalMinutes))`。

#### (3) `AcademicController` (`lib/src/state/academic_controller.dart`)
- **学期 ID 解析优先级 (`academicTermId`)**：
  1. 用户在学业页显式选中的 `_academicTermId`；
  2. 课表当前学期 `_fallbackTermIdReader()` (`scheduleState.termId`)；
  3. 学期列表当前学期 `_termsReader()?.currentId` (`scheduleState.terms?.currentId`)；
  4. 均无则返回 `''`。
- **`loadedAcademicTerm` 防串台契约**：记录当前内存中 `_exams` / `_grades` 实际归属的学期。切换到无离线缓存的新学期发起网络请求前，立即清空 `_exams`、`_grades` 并重置 `_isNotEvaluated = false`、更新 `_loadedAcademicTerm = target`，防止加载期间画面残留上一学期成绩。
- **特殊错误码容错与重登标记 (`academicNeedsRelogin`)**：
  - 考试查询返回 `ErrorCode.notOpen`：考试安排未开放属于正常学期周期状态，**保持静默，不写入 `_academicError` 也不弹错误气泡**。
  - 成绩查询返回 `ErrorCode.notEvaluated`：置 `_isNotEvaluated = true`；若本地缓存 `existingGrades` 有旧成绩列表则保留展示，同时将 `isNotEvaluated: true` 写回 `GradesCache`；**不写入 `_academicError`**（UI 据 `isNotEvaluated` 展示专门的未评教引导卡片）。
  - 其他 `AcademicError` 统一通过 `HintNoticeController.humanizeError()` 翻译写入 `_academicError`（与课表页文案完全一致）；若错误码为 `sessionExpired` 或 `invalidCredentials`，同步置 `_academicNeedsRelogin = true`，驱动 `AcademicPage` 横幅将右侧按钮切换为「重新登录」。
- **学业变更比对 (`_diffChangeMessage`)**：当本地原本有缓存（`hasOldExams || hasOldGrades`）或刚在调试页执行过 `clearDataForDebug()`（`_academicDataClearedForDebug == true`）时，若新抓取的数据与旧缓存 `!listEquals`，弹出 2 秒全局提示（`'学业数据有更新'` / `'考试安排有更新'` / `'成绩有更新'`，带 `isAcademicUpdate: true`）。

#### (4) `PreferencesController` (`lib/src/state/preferences_controller.dart`)
- **外观调节 300ms 防抖草稿**：
  - `setCellHeight(double)` 与 `setCourseTextScale(double)` 仅更新内存草稿 `_cellHeightDraft` / `_courseTextScaleDraft`，立即通知 UI 丝滑重绘，并重置 300ms `_appearanceTimer`。
  - 300ms 到期或显式调用 `flushAppearance()` / `dispose()` 时，才真正调用 `_preferences.setCellHeight` / `setCourseTextScale` 落盘。
- **启动自动检查更新 (`checkAutoUpdate`)**：
  - 仅在 `!_hasCheckedAutoUpdate && autoCheckUpdate && !_disposed` 时生效，默认延迟 `initialDelay = Duration(seconds: 1)` 后执行。
  - 遇到 `UpdateStatus.networkError` 或异常时，最多自动重试 **2 次**（间隔 `Duration(seconds: 2)`）。
  - 检测到 `UpdateStatus.hasUpdate` 时，调用 `_updateFlow.setAvailableUpdate(...)` 并触发 `onHasUpdate(result)` 回调。

#### (5) `HintNoticeController` (`lib/src/state/hint_notice_controller.dart`)
- **三作用域优先级**：`hint` 与 `hintIsError` 按 **`global` > `schedule` > `academic`** 优先级返回当前活跃提示。
- **`isGlobalPopupActive`**：当 `AppStatus` 处于 `booting` / `loading` / `signingIn` / `failed` 之一，或 `_globalHint.isNotEmpty` 时返回 `true`。
- **`humanizeError(AcademicError error)` 全量映射表**：

| `ErrorCode` | 转换后的用户可读文案 |
| :--- | :--- |
| `invalidCredentials` | `'账号或密码错误，请核对后重试。'` |
| `sessionExpired` | 细分为三档：熔断暂停 `'自动登录已暂停（多次失败或密码已变更），请重新登录。'`；未保存密码 `'登录凭证已失效且未保存密码，请重新登录。'`；其余 `'登录凭证已失效，请重新登录。'` |
| `captchaRequired` | `'需要输入验证码，请在验证码页输入后重试。'` |
| `webLoginRequired` | `'教务系统要求先完成网页统一认证，暂不支持自动登录。'` |
| `networkRetryable` | `'网络不稳定或无法连接教务系统，请检查网络后重试。'` |
| `serverError` | `'教务系统异常${httpStatus == null ? "" : "（HTTP $httpStatus）"}：返回错误或维护页面。请稍后重试或切换线路。'` |
| `pageChanged` | `'课表数据格式与预期不符。若持续出现，请前往「调试信息」查看请求记录。'` |
| `unsupported` | `'该账号无课表查询权限。'` |
| `accessForbidden` | `'访问被拒绝（403）：学校限制了外网访问，请连接校园网后重试。'` |
| `untrustedUrl` | `'检测到未受信跳转，已中止。若在非校园网环境，请连接校园网后重试；若学校更换了入口，请更新教务地址。'` |
| `cancelled` | `'操作已取消。'` |
| `validationFailed` | `'输入不合法：${error.message}'` |
| `staleContext` | `'登录会话已过期，请重新登录。'` |
| `resultUnknown` | `'教务系统未返回明确结果，请刷新后查看。'` |
| `notEvaluated` | `'本学期教学质量评价未完成，教务系统暂不开放成绩查询，请前往教务网完成评教。'` |
| 其余枚举 (`notOpen`, `timeout` 等) | 原样返回 `error.message` |

---

## 2. 核心并发、世代令牌与互斥不变量 (Concurrency & Mutex Invariants)

修改状态层、网络编排或文件存储时，必须严格遵守以下 7 条并发与一致性不变量：

| 机制 / 变量名 | 所在类 (`文件`) | 保护目标与核心不变量契约 |
| :--- | :--- | :--- |
| **`_authEpoch`** (`int`) | `AppModel` (`app_model.dart`) | **会话切换世代令牌**。每次调用 `_resetAuthFlight()`（由 `signIn`、`changeSchool`、`signOut` 触发）时 `_authEpoch++`，同时清空 `scheduleLoad`、`refreshing`、`_reloginStageActive` 与挂起的 `captcha`。异步等待 `reloginFlight` 恢复后必须校验 `epoch == _authEpoch`，防止旧会话重登回调污染新登录或已退出的状态。 |
| **`scheduleLoad`** (`Future<Schedule>?`) | `ScheduleController` (`schedule_controller.dart`) | **课表请求所有权指针**。`_loadSchedule` 发起请求时记录 `scheduleState.scheduleLoad = loadFuture`；`await` 返回或捕获异常后，必须校验 `scheduleState.scheduleLoad == loadFuture` 才允许写入课表或更新状态；`_resetAuthFlight` 或 `resetOnSignOut` 将其置 `null` 即可瞬时作废在途课表请求。 |
| **`_reloginFlight` & `_reloginEpoch`** | `ScheduleService` (`schedule_service.dart`) | **全局阻塞式单 flight 自动重登互斥锁与世代去重**。无论是 `getSchedule`、`fetchTerms`、`fetchExams` 还是 `fetchGrades` 遇到 `ErrorCode.sessionExpired`，均调用 `_reloginWithSavedCredentials()` 共享同一个 `_reloginFlight`（返回递增 `_reloginEpoch`）。所有业务请求入口必先 `await _waitForRelogin()`；重登后紧接着并发业务重试若仍全部立即报 `sessionExpired`，按 `_reloginEpoch` 去重仅计 1 次失败。 |
| **`_schoolSwitchInFlight` / `_schoolSwitchSeq`** | `AppModel` (`app_model.dart`) | **切校异步重入保护**。覆盖从 `await credentials.get(...)` 读取安全存储密码到完成新校登录的完整窗口，防止在 `AppStatus.failed` 下快速连点「重试」重入发起重复切校；`_resetAuthFlight()` 递增 `_schoolSwitchSeq` 可随时作废在途切校。 |
| **`_inFlight` / `_clientFlight`** | `ScheduleService` (`schedule_service.dart`) | `getSchedule()` 通过 `_inFlight` 合并并发课表拉取；`_ensureClient()` 通过 `_clientFlight` 合并客户端首次 `bootstrap()` 与构造。 |
| **`_academicLoadSeq`** (`int`) | `AcademicController` (`academic_controller.dart`) | **学业请求单调递增序列号**。每次 `loadAcademicData()` 或 `resetOnSignOut()` 时 `++_academicLoadSeq`。在 `restoreCachedData`、`loadAcademicData`、`_runQuietSync` 的每一个 `await` 切点之后，以及传给 `AcademicService` 的 `shouldCache: () => !_disposed && seq == _academicLoadSeq && !_isNeedLoginReader()` 回调中，都必须校验 `seq == _academicLoadSeq`，彻底杜绝切学期或退出登录后的乱序写盘与画面覆盖。 |
| **`_suppressStageHints`** (`bool`) | `AppModel` (`app_model.dart`) | **后台学业静默同步气泡抑制锁**。`AcademicController.syncQuietly` 执行期间将 `_suppressStageHints` 置为 `true`，使 `_onServiceStage` 忽略 `ScheduleService` 发出的 `relogin` / `fetching_schedule` 阶段事件，防止后台静默同步学业数据时突然弹出全局「正在重新登录…」气泡惊扰用户。 |
| **`SafeJsonFile._queues` & `_pendingWrites`** | `SafeJsonFile` (`safe_json_file.dart`) | **路径级静态串行队列与写合并**。以 `file.absolute.path` 为锁键：同一文件的所有 `readJson`、`writeJson`、`updateJson`、`clear` 严格串行；连续 `writeJson(coalesce: true)` 最多保持「1 个正在落盘 + 1 个最新待写 `_PendingWrite`」，中间高频快照直接原地替换 `buildPayload` 闭包；`readJson` / `updateJson` / `clear` 立即封口或取消未落盘的 `_pendingWrites`，防止读写重排。 |

---

## 3. 业务服务与离线缓存层 (`ScheduleService`, `AcademicService`, Caches, School, TermSelector)

### 3.1 `ScheduleService` 完整契约 (`lib/src/schedule_service.dart`)

- **默认配置常量**：
  - `autoLoginLimit = 2`（熔断窗口内最大自动登录次数）
  - `autoLoginWindow = Duration(minutes: 10)`（熔断滑窗时长）
  - `requestTimeoutMs = 10000`（传给 `ZfClientConfig` 的单次 HTTP 超时：10 秒快速失败）
  - `_requestLogLimit = 120`（内存保留最近 120 条 `RequestLog` 供调试页展示）
  - 阶段常量：`stageRelogin = 'relogin'`，`stageFetchingSchedule = 'fetching_schedule'`
- **自动重登、精细化熔断与回滚流程 (`_loginWithSavedCredentials`)**：
  1. 根据 `_accountKey()`（`baseUrl.toLowerCase()|account`）从 `credentials` 读取保存的账密；无账密直接抛 `SESSION_EXPIRED`（带「没有保存账号密码」提示）。
  2. 检查熔断器：若 `_breakerOpen || !_autoLoginAllowed()`（滑窗 10 分钟内有效失败已达 2 次），置 `_breakerOpen = true` 并抛 `SESSION_EXPIRED`（带「自动登录次数过多」提示）。
  3. **保存回滚点**：`final rollback = client.exportCookies()`（因为 `client.login()` 入口会立即调用 `_cookies.invalidate()` 清空旧 Cookie）。
  4. 调用 `client.login(saved)` 并按错误性质精细化计次：
     - **不计入熔断**：`networkRetryable` / `timeout` / `serverError` / `accessForbidden` / `cancelled`（网络或服务端波动）；
     - **立即打开熔断（`_breakerOpen = true`）**：`invalidCredentials`（密码已变更/错误，绝不再用旧密码自动重试防锁号）；
     - **计入 10 分钟 2 次窗口**：其余认证/验证码取消/网页认证/页面异常失败，以及「重登刚成功、紧接着业务重试仍立即报 `sessionExpired`」（按 `_reloginEpoch` 去重只计 1 次）；
     - **健康恢复清零**：单次自动重登成功且紧接着的业务请求成功拿到数据，立即清空 `_autoLoginFailures`（正常单次重登不消耗熔断额度）；一旦 `_breakerOpen == true`，仅手动 `signIn` / `submitCaptcha` 成功或 `switchSchool` 时调用 `resetBreaker()` 解除。
     - 任一登录/验证码阶段失败时均执行 `_restore(client, rollback)` 恢复旧 Cookie 快照并原样上抛。
  5. 校验 `_client == client` 后，调用 `_persist(client)` 将新 Cookie 快照写入 `cookieStorage` 并返回新 `_reloginEpoch`。
  6. `signIn()` 内部调用 `_ensureClient(loadCookies: false)` 跳过 `bootstrap()`，避免切校试登阶段误删磁盘上原校 Cookie 快照；并提供 `exportCurrentCookies()` 仅导出当前内存客户端持有的非空 Cookie 快照。

### 3.2 `AcademicService` 与 `GradeStats` GPA 算法 (`lib/src/academic_service.dart`)

```dart
class GradeStats {
  final double averageGpa;    // 加权平均绩点：sum(gradePoint * credit) / sum(credit where gradePoint != null && credit > 0)
  final double totalCredits;  // 全部课程学分之和
  final double passedCredits; // 及格课程学分之和
  final int totalCourses;     // 全部课程门数
  final int passedCourses;    // 及格课程门数

  static const List<String> passingScoreLabels = [
    '通过', '合格', '优秀', '良好', '中等', '及格', '免修', '免考', 'P', 'p',
  ];
  static bool isGradePassed(GradeItem grade);
  static GradeStats calculate(List<GradeItem> grades);
}
```
- **铁律**：`GradeStats.calculate` **严格使用教务系统原生返回的 `grade.gradePoint` (`jd`)** 计算学分加权平均绩点，严禁在客户端自行用百分制分数臆造换算公式。
- **及格判定 `isGradePassed(grade)`**（满足其一即及格）：
  1. `numericScore ?? double.tryParse(rawScore)` 非空且 `>= 60.0`；
  2. `passingScoreLabels.contains(rawScore.trim())`；
  3. `gradePoint != null && gradePoint! > 0`。

### 3.3 离线缓存 JSON 结构 (`schedule_cache.dart` & `academic_cache.dart`)

| 缓存类 | 默认文件名 | 顶层 JSON 结构与校验规则 (`isValid`) | 损坏处理策略 |
| :--- | :--- | :--- | :--- |
| `FileScheduleCache` | `zf-schedule-cache.json` | `{"baseUrl": String (非空), "fetchedAt": ISO8601, "schedule": {"termId": String (非空), "maxWeeks": int, "entries": [...], "remarks": [...]}}` | 主文件与 `.bak` 均损坏（`hadUnrecoverableCorruption`）时自动调用 `clear()` 删除坏文件并返回 `null` |
| `FileExamCache` | `zf-exam-cache.json` | `{"updatedAt": ISO8601, "terms": { "<termId>": {"termId": String, "fetchedAt": ISO8601, "items": [ExamItem.toJson()]} }}` | 同上，通过 `_TermJsonCacheStore` 共享逻辑，写单学期时调用 `SafeJsonFile.updateJson` 读-改-写合并 `terms` 字典 |
| `FileGradesCache` | `zf-grades-cache.json` | `{"updatedAt": ISO8601, "terms": { "<termId>": {"termId": String, "fetchedAt": ISO8601, "isNotEvaluated": bool, "items": [GradeItem.toJson()]} }}` | 同上 |

### 3.4 学期选择与学籍推导 (`lib/src/term_selector_helper.dart`)

- **`parseEnrollmentYear(String? studentId, {DateTime? now})`**：
  - 合法年份区间：`[currentYear - 15, currentYear + 1]`。
  - 提取首个连续数字串 `digits`（长度 `<2` 或 `==3` 返回 `null`）：
    1. **8 位且以 `19` 或 `20` 开头**（如 `20240001`）：取前 4 位。
    2. **恰好 4 位**（如 `2024`）：直接取 4 位年份。
    3. **恰好 10 位**（青科大标准本科 10 位学号 `YY+CC+MM+NN+SS`，如 `2412345678`）：取前 2 位 `y2`，`y2 >= 80 ? 1900 + y2 : 2000 + y2`。
    4. **其他长度 `>=4`**：先尝试前 4 位，若不在合法年份区间再尝试前 2 位。
- **`filterTerms` 过滤规则**：
  1. 当前已选中的 `currentTermId` **无条件保留**（若不在原列表中则自动补入）。
  2. 过滤掉 `termSemester > 2` 的短学期（青科大两学期制，正方自带的 `xqm=16` 第 3 学期不作为常规可选学期）。
  3. 过滤掉 `termYear < resolvedEnrollmentYear`（入学前历史学期）。
  4. 过滤掉 `termYear > maxYear` 或 `termYear == maxYear && termSemester > maxSemester`（超前未来学期）。
  5. 若输入 `terms` 为空但已知 `resolvedEnrollmentYear`，自动按 `[resolvedEnrollmentYear .. maxYear]` 逆序生成完整学期列表。
- **`formatTermPrimaryLabel` 年级标题映射**：
  - `offset = termYear - resolvedEnrollmentYear`。
  - 当 `0 <= offset < 5` 时映射为 `['大一', '大二', '大三', '大四', '大五'][offset] + ' ' + (semester == 1 ? '上学期' : semester == 2 ? '下学期' : '第$semester学期')`。
  - 当 `offset` 越界或无入学年份时，回退为 `'$termYear-${termYear + 1} 第$semester学期'`。

### 3.5 学校与教务线路 (`lib/src/school.dart`)

- **预设线路 (`qustLines` / `presetSchoolUrls`)**：
  - 默认线路（`defaultSchool` / `qustProfile`）：`https://jwglxt.qust.edu.cn/jwglxt`（名称：`青岛科技大学`；受登录策略影响，当前仅保留该外网可登录的默认线路，原 `jwglxt1`~`jwglxt6` 已从预设中移除）
- **`sameSchool(String a, String b)`**：去首尾空白、转小写、剥离末尾 `/`、剥离 `^https?://` 后比对相等。

---

## 4. 课表排布、校历换算、调课叠加与工具库 (`timetable`, `term_calendar`, `reschedule`, `route_settled`)

### 4.1 作息时间表 (`lib/src/timetable.dart`)

- **核心常量与默认分段**：
  - `PeriodGroup`：`morning('上午')`、`afternoon('下午')`、`evening('晚上')`
  - `defaultSectionCounts`：`{morning: 4, afternoon: 4, evening: 2}`（总计 `defaultSectionCount = 10` 节）
  - 约束常量：`minLessonMinutes = 20`，`maxLessonMinutes = 180`，`maxShortBreakMinutes = 60`，`maxBigBreakMinutes = 120`，`maxTimetables = 20`，`maxSections = 20`
- **内置两套预设作息表 (`defaultTimetables()`)**：

| 预设表 | `id` | `name` | 默认生效月日 (`effectiveFrom`) | 单节时长 / 小课间 / 大课间 | 三段起始时间 (`starts`) |
| :--- | :--- | :--- | :--- | :--- | :--- |
| 秋冬作息 | `'default'` | `'秋冬作息'` | 10 月 1 日 (`month: 10, day: 1`) | 45m / 5m / 上午第2节后20m、下午第2节后20m | 上午 `08:30` (510)、下午 `13:30` (810)、晚上 `18:00` (1080) |
| 春夏作息 | `'default-summer'` | `'春夏作息'` | 5 月 1 日 (`month: 5, day: 1`) | 45m / 5m / 上午第2节后20m、下午第2节后20m | 上午 `08:30` (510)、下午 `14:00` (840)、晚上 `18:30` (1110) |

- **按月日跨年循环切换 (`activeTimetableAt(tables, today)`)**：
  - 计算 `key = effectiveFrom.month * 100 + effectiveFrom.day` 与 `todayKey = today.month * 100 + today.day`（**年份不参与生效判定**）。
  - 升序排列后取 `key <= todayKey` 的最后一张；若今天比所有表的月日都早（如 1 月初），回绕取月日最大的最后一张（即上一年的秋冬作息继续生效）。
- **逐段对齐 (`reconcileSections(sections, counts)`)**：
  - 节数是**全局设置**，不属于单张作息表。当用户修改上/下/晚节数时，按 `PeriodGroup` 逐段裁剪尾部或按「该段最后一节时长 + 默认 5 分钟小课间」向后补齐，绝不会因为缩减上午节数而误删晚上的节次。

### 4.2 学期校历与同天冲突布局 (`lib/src/term_calendar.dart`)

- **`estimateTermStart(Term term, {DateTime? now})`**：
  - 第 1 学期（秋季）：`mondayOf(DateTime(year, 9, 1))`
  - 第 2 学期（春季）：`mondayOf(DateTime(year + 1, 2, 23))`
  - 第 3 学期（夏季）：`mondayOf(DateTime(year + 1, 7, 1))`
- **`weekOf(DateTime termStart, DateTime date)`**：使用 `DateTime.utc(y, m, d)` 消除夏令时/时分秒误差；早于 `mondayOf(termStart)` 时固定返回 `1`。
- **`conflictLayout(List<ScheduleEntry> entries)`**：
  - 返回 `Map<String, ({int index, int total})>`（键为 `entry.id`）。
  - 同一 `day` 内所有节次区间相交（`!(other.endPeriod < entry.startPeriod || other.startPeriod > entry.endPeriod)`）的课程按 `id` 字典序排序，分配并列列位 `(index, total)`。

### 4.3 按日调课渲染叠加 (`lib/src/reschedule.dart`)

- **核心不变量**：调课规则 `RescheduleRule(id, fromMonth, fromDay, toMonth, toDay)` **只影响渲染视图 `RescheduleWeekView`，绝不修改持久化的 `Schedule` 原始数据**。
- **跨年锚定 (`_dateInTerm`)**：月日无年份，以 `termStart` 为锚点构造 `DateTime(anchor.year, month, day)`；若早于 `dayOnly(anchor)` 则自动落入 `anchor.year + 1`（自然处理 9 月开学跨越至次年 1 月的学期）。`toDate` 以 `fromDate` 为锚点同理推导。
- **按实例调课与冲突抑制 (`rescheduleWeekView`)**：
  1. 展开每条 `ScheduleEntry` 的所有上课周次 `w`（`weeks.isEmpty` 时展开为 `1..maxWeek`），生成 `(w, entry.day)` 实例。
  2. 命中第一条匹配的 `RescheduleRule`（`_firstRuleFor`）时，该实例从原周调走；若 `rule.toWeek == week`，生成 `weeks: [week], day: rule.toDay` 的调入实例放入 `movedIn`。未命中的本周实例放入 `staying`。
  3. **冲突抑制（调入课优先）**：遍历 `movedIn` 与 `staying`，若同天且节次区间重叠，`staying` 中的原课被加入 `suppressed`（不在网格显示），并在 `conflicts[day]` 中记录 `RescheduleConflict(displaced: original, winner: moved)`（驱动课表表头星期几黄底高亮与点击详情弹窗）。
  4. **兜底去重**：若极端配置下多条规则将同一 `entry.id` 调到同一天且节次重叠，仅保留先到的一条。

### 4.4 路由落稳与并行后台 Isolate (`lib/src/route_settled.dart`)

- **`runInBackground<T>(T Function() computation)`**：
  - 在生产环境 (`WidgetsFlutterBinding`) 及未初始化 Binding 的纯 Dart 单元测试中，调用 `Isolate.run<T>(computation)` 将耗时解析卸载到后台 Isolate。
  - 在 Web (`kIsWeb`) 或 `flutter_test` 组件测试 (`WidgetsBinding.instance is! WidgetsFlutterBinding`) 中，自动降级为 `Future<T>.microtask(computation)`，保证 `FakeAsync` 测试确定性收敛。
- **`RouteSettledStateMixin` / `RouteSettledGate` / `scheduleAfterRouteSettled`**：
  - 判定落稳条件：`!(route?.offstage ?? false) && (animation == null || animation.status == AnimationStatus.completed)`。
  - 粘性落稳：一旦 `_routeSettled == true`，页面 pop 退场动画期间始终保持 `true`，绝不卸载已挂载的重子树；入场中途手势取消返回再恢复（`forward -> reverse -> forward -> completed`）不会提前作废监听。
  - 帧阶段保护：若动画完成回调触发于 `SchedulerPhase.persistentCallbacks` 期间，自动推迟到 `addPostFrameCallback` 再调用 `onRouteSettled()`，杜绝 build 期间 `setState` 报错。

---

## 5. 持久化与安全存储层 (`Preferences` Schema 15, `SafeJsonFile`, Credentials, Session)

### 5.1 `Preferences` (`app_prefs.json`) Schema 15 全字段速查表 (`lib/src/preferences_repository.dart`)

当前版本号常量：`const int preferencesSchema = 15;`（位于应用支持目录 `app_prefs.json`）。

| JSON 键名 | Dart 类型 | 出厂默认值 | 合法范围 / 归一化函数 | 引入/变更历史与特殊契约 |
| :--- | :--- | :--- | :--- | :--- |
| `schema` | `int` | `15` | 固定写出 `preferencesSchema` (15) | Schema 15 启用覆盖式教务地址模型：不再读取旧版 `schools`/`currentSchool`，升级用户自动动态跟随当前版本的 `defaultSchool.baseUrl` |
| `termStarts` | `Map<String, String>` | `{}` | `termId -> DateTime(y,m,d).toIso8601String()` | 用户手动校准过周次的学期第 1 周周一 |
| `sectionCounts` | `Map<String, int>` | `{"morning": 4, "afternoon": 4, "evening": 2}` | `clampCounts`: 每段 `0..20`，总和 `1..20`（全 0 回退默认 4/4/2） | 全局三段节数；兼容读取旧版单一整数键 `sectionCount` 并按 `splitCounts` (4/4/其余) 迁移 |
| `customSchools` | `List<String>` | `[]` | `_normalizeCustomSchools`: 过滤空串与内置 `presetSchoolUrls`，按 `sameSchool` 去重 | Schema 15：仅持久化用户自定义的教务地址；`Preferences.schools` 动态拼接 `[...presetSchoolUrls, ...customSchools]`，内置预设不可删除 |
| `customSchool` | `String` | `''` | `_normalizeCustomSchool`: 与 `defaultSchool.baseUrl` 同源时归一化为 `''` | Schema 15：用户显式覆盖的教务地址；为空串时 `Preferences.currentSchool` 动态返回当前版本 `defaultSchool.baseUrl`；删除当前生效的自定义地址或切回默认地址时自动重置为 `''` |
| `lastAccounts` | `Map<String, String>` | `{}` | `baseUrl -> studentId`（按 `sameSchool` 匹配读写，`setIdentityOf` 将最近更新项移至末尾） | Schema 7：每所学校上次登录的学号（冷启动拼 `accountKey` 自动重登的关键依据）；`Preferences.latestAccount` 返回最近一次记录的非空账号，供 `AppModel.loginPrefillUsername`（`username` → `accountOf(schoolBaseUrl)` → `latestAccount`）给 `LoginPage` 预填学号而不污染 `studentId` |
| `lastStudentNames` | `Map<String, String>` | `{}` | `baseUrl -> studentName`（按 `sameSchool` 匹配读写） | Schema 13：每所学校上次登录的学生姓名（冷启动免联网直接展示） |
| `showTeacher` | `bool` | `true` | `bool` | 课表格子内是否显示教师姓名 |
| `showLocation` | `bool` | `true` | `bool` | 课表格子内是否显示上课地点 |
| `cellHeight` | `double` | `60.0` (`defaultCellHeight`) | `clampCellHeight`: `50.0 .. 120.0` (`minCellHeight..maxCellHeight`) | 课表网格单节行高（逻辑像素） |
| `courseTextScale` | `double` | `1.0` (`defaultCourseTextScale`) | `clampCourseTextScale`: `0.8 .. 1.4` (`minCourseTextScale..maxCourseTextScale`) | 课程卡片文字缩放倍率 |
| `autoRefresh` | `bool` | `true` | `bool` | Schema 5：冷启动与回前台是否开启静默更新 |
| `autoRefreshIntervalMinutes` | `int` | `180` (`defaultAutoRefreshIntervalMinutes`) | `clampAutoRefreshIntervalMinutes`: `60 .. 1440` | Schema 5：静默更新最小间隔（分钟） |
| `reschedules` | `List<Map>` | `[]` | `RescheduleRule.fromJson` | Schema 5：按日调课规则列表 |
| `showScheduleRemarks` | `bool` | `true` | `bool` | Schema 6：是否在课表底部显示实践/其他课程备注 |
| `reminderEnabled` | `bool` | `false` | `bool` | Schema 9：课前提醒总开关（默认关闭，需用户授权通知与精确闹钟） |
| `reminderLeadMinutes` | `int` | `10` (`defaultReminderLeadMinutes`) | `clampReminderLead`: `1 .. 60` | Schema 9：课前提醒提前分钟数 |
| `reminderStyle` | `String` | `'banner'` (`ReminderStyle.banner`) | `ReminderStyle.parse`: `'banner'` \| `'fluid'` | Schema 10：提醒形态（标准横幅 / 实况流体云） |
| `reminderFluidUntilEnd` | `bool` | `false` (`defaultReminderFluidUntilEnd`) | `bool` | Schema 11：流体云是否持续显示到下课（`false` = 上课即收起） |
| `selectedUpdateProxy` | `String` | `'https://gh-proxy.org'` (`defaultUpdateProxyUrl`) | 兼容读取旧键 `updateProxyUrl`；空串 `''` 表示官方直连 | Schema 12：当前选中的 GitHub 更新加速代理 |
| `customUpdateProxies` | `List<String>` | `[]` | 过滤空串与已在 `presetUpdateProxies` 中的地址 | Schema 12：用户自定义的加速代理列表（删除正选中的自定义代理时自动回退 `defaultUpdateProxyUrl`） |
| `autoCheckUpdate` | `bool` | `true` (`defaultAutoCheckUpdate`) | `bool` | Schema 12：启动时是否自动检查软件更新 |
| `widgetConfig` | `Map<String, dynamic>` | `DesktopWidgetConfigSet.defaults()` | 按 `DesktopWidgetKind` (`today`/`week`/`next`) 独立存储样式 | Schema 14：桌面小组件样式配置集（详见 `WIDGET.md`） |
| `timetables` | `List<Map>` | `[defaultTimetable(), defaultSummerTimetable()]` | `_withBuiltinSummerTable`: 仅含单张未改名默认表时自动补齐春夏作息；上限 20 张 | 作息时间表列表（至少保留 1 张，传空抛 `ArgumentError`） |
| `quickSetup` | `Map<String, dynamic>?` | `null`（未保存时不写出该键） | `QuickSetup.fromJson` | 上次在作息快捷设置面板填写的参数记忆 |

### 5.2 `SafeJsonFile` 原子落盘与自愈契约 (`lib/src/safe_json_file.dart`)

- **后台 Isolate 解码阈值**：`const int isolateJsonDecodeThreshold = 16 * 1024;`（16KB）。当 JSON 文本长度 `>= 16384` 字符时，自动调用 `Isolate.run(() => jsonDecode(rawText))`；小于 16KB 时在当前线程直接 `jsonDecode` 避免 Isolate 切换开销。
- **原子写入与 `.bak` 轮转 (`_writeEncodedLocked`)**：
  1. 若 `keepBackup == true`（默认）且主文件已存在且内容非空，先尝试解析当前主文件确认其 JSON 完好，若完好则先写入 `${path}.bak.tmp` (`flush: true`) 并原子重命名为 `${path}.bak`（若当前主文件已损坏，则跳过备份轮转，保护旧 `.bak` 不被坏数据覆盖）。
  2. 将新 JSON 写入 `${path}.tmp` (`flush: true`)，完成后原子重命名为 `${path}`，并在 `finally` 中清理残留临时文件。
- **读取与 `.bak` 自动自愈 (`_readLocked`)**：
  1. 尝试读取并校验（`isValid`）主文件；成功则返回 `SafeJsonReadResult(data: parsed)`。
  2. 若主文件缺失、为空、JSON 解析失败或 `isValid` 返回 `false`，且 `keepBackup == true`，尝试读取并校验 `${path}.bak`。
  3. 若 `.bak` 完好：立即用 `.bak` 的原文通过 `.tmp` 原子覆写修复主文件，并返回 `SafeJsonReadResult(data: backup.parsed, recoveredFromBackup: true)`。
  4. 若主文件或 `.bak` 曾存在但均失败：返回 `SafeJsonReadResult(data: null, hadUnrecoverableCorruption: true)`。

### 5.3 凭据与会话安全存储 (`credentials_repository.dart` & `session_repository.dart`)

- **`SecureCredentialStore` (`lib/src/credentials_repository.dart`)**：
  - 底层插件：`FlutterSecureStorage` (v11)，Android 使用 `EncryptedSharedPreferences + Tink + Android Keystore`，Windows 使用 `DPAPI`（绑定当前 Windows 登录用户）。
  - **零明文键名派生**：调用 `credentialStoreKey(accountKey)` 计算 `'zf_pw_' + sha256(utf8.encode(accountKey)).hex`。
    - 密码存储在键 `zf_pw_<sha256>`；
    - 用户名存储在键 `zf_pw_<sha256>#u`。
  - 容错：Keystore 损坏、换机或 Windows 换用户导致解密异常时，`get()` 捕获所有异常并返回 `null`，由上层温和引导重新登录。
- **`FileSessionRepository` (`lib/src/session_repository.dart`)**：
  - 底层委托 `packages/zf_academic` 的 `FileCookieStorage('${supportDir.path}/zf-session.json')`。
  - 同样具备路径级串行队列、待写快照合并、`>= 16KB` Isolate 解码、`.tmp` 原子重命名，且在非 Windows 平台（POSIX/Android）写入后执行 `chmod 600`。

---

## 6. 应用内更新与跨平台安装器 (`lib/src/updater/*`, `AppUpdaterBridge.kt`, Windows 热替换)

### 6.1 `UpdateFlowController` 状态机 (`lib/src/updater/update_flow_controller.dart`)

- **阶段枚举 `UpdateFlowStage`**：`idle` -> `available` -> `downloading` -> `readyToInstall` / `error`。
- **关键事件计数器**（供 UI 监听并在弹窗收起时弹通知或自动关弹窗）：
  - `backgroundReadyEvent`：当 `!isDialogOpen`（用户收起了更新弹窗在后台下载）且下载完成进入 `readyToInstall` 时自增 `++`。
  - `backgroundErrorEvent`：当 `!isDialogOpen` 且下载失败进入 `error` 时自增 `++`。
  - `requestCloseEvent`：当 `executeInstall()` 成功拉起系统安装器且 `isDialogOpen` 时自增 `++`，通知弹窗自动关闭。
- **同版本进度保持契约**：调用 `setAvailableUpdate` 时，若新传入的 `release.version` 与 `targetAsset.name` 与当前一致，且当前正处于 `downloading` 或 `readyToInstall`，**保持既有下载进度或已下载文件不重置**。
- **本地复用与平台安装分流 (`startDownload` & `executeInstall`)**：
  - 若 `_downloadedFile` 已存在磁盘上，直接跳至 `readyToInstall`。
  - 下载前若 `release != null && _allowAvailableFallback`，先调用 `_service.fetchExpectedSha256` 从 Release 的 `SHA256SUMS` 产物拉取目标包 SHA-256 摘要。
  - **Android vs Windows 自动拉起差异**：
    - **Android**：下载完成时检查 `canInstallPackages()` 设置 `_needsPermission = !canInstall`。若此时弹窗正打开 (`isDialogOpen`) 且已授权 (`!_needsPermission`)，**自动立即调用 `executeInstall()`**；若未授权，用户跳系统设置页授权切回前台时，调用 `refreshInstallPermissionAndAutoInstall()` 会自动接续安装。
    - **Windows**：下载完成进入 `readyToInstall` 后**绝不自动退出进程**，必须等待用户在弹窗明确点击「立即重启更新」触发 `executeInstall()`。

### 6.2 `UpdateService` 网络加速、分块下载与产物匹配 (`lib/src/updater/update_service.dart`)

- **核心超时与并发常量**：
  - `repoOwner = 'fangzi2006'`，`repoName = 'QustSchedule'`
  - `probeTimeout = Duration(seconds: 5)`，`apiTimeout = Duration(seconds: 6)`
  - `downloadConnectTimeout = Duration(seconds: 15)`，`downloadIdleTimeout = Duration(seconds: 30)`
  - `maxConcurrentChunks = 3`（3 线程并发分块），`minChunkingBytes = 4 * 1024 * 1024`（4MB 阈值）
  - `browserUserAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 QustSchedule/App'`（规避反代/CDN 对非浏览器 UA 的低带宽限流）
- **预设加速代理 (`presetUpdateProxies` in `preferences_repository.dart`)**：
  1. `'https://gh-proxy.org'`（默认首选，`displayProxyName` -> `'主加速节点(默认推荐)'`）
  2. `'https://axisnow.gh-proxy.org'`（`displayProxyName` -> `'副加速节点'`）
  3. `'https://gh-proxy.com'`（`displayProxyName` -> `'加速主站（最稳定但是部分网络环境下速度较慢）'`）
  - 候选队列构造 `_buildCandidates(selectedProxy, backupProxies)`：`[selectedProxy, ...其余 backupProxies, '']`（末尾固定追加空串 `''` 代表 GitHub 官方直连兜底）。
- **平台与形态产物匹配 (`findTargetAsset` & `isWindowsPortable`)**：
  - **`isWindowsPortable()` 判定原理**：检查 `File(Platform.resolvedExecutable).parent` 目录下**是否存在 `unins000.exe`**（Inno Setup 安装版卸载程序）。不存在即为便携版 (`true`)，存在即为安装版 (`false`)。
  - **Windows 便携版**：优先匹配文件名含 `windows-x64` 的 `.zip` -> 任意 `.zip` -> 兜底 `.exe`/`.zip`。
  - **Windows 安装版**：优先匹配文件名含 `setup` 的 `.exe` -> 任意 `.exe` -> 兜底 `.exe`/`.zip`。
  - **Android**：通过 `Abi.current()` 识别 `arm64-v8a` 或 `armeabi-v7a`；优先匹配含对应 `archKey` 的 `.apk` -> 含 `arm64` 的 `.apk` -> 任意 `.apk`。
- **Range 探测、3 线程分块与零握手直通降级 (`downloadAssetWithFallback`)**：
  1. **本地 0 秒嗅探复用**：若临时目录已存在同名文件且 `length == asset.size (> 0)` 且 SHA-256 校验通过，直接回报 100% 进度并返回该文件。
  2. **Range `bytes=0-0` 探测**：
     - 返回 **`206 Partial Content`**：从 `Content-Range` 解析总字节数 `totalBytes`。若 `totalBytes >= 4MB` (`minChunkingBytes`)，启动 `_downloadMultiChunk`（3 个并发切片 `.part0`~`.part2`，每个切片独立 `30s` 空闲超时看门狗与字节边界强校验，每 `350ms` 按 `0.7 * instant + 0.3 * previous` 指数平滑计算网速；任一切片失败若非用户取消，立即在该代理节点内无缝回退 `_downloadSingleUrl` 单连接下载）。下载完按序流式合并 `.part0`~`.part2` 并删除分片。
     - 返回 **`200 OK`**（服务端不支持 Range 但响应流已打开）：**零额外网络握手**，直接将当前 `probeRes` 传给 `_downloadSingleStream` 落盘。
  3. **SHA-256 强校验**：落盘完成后若 `expectedSha256` 非空，计算文件 SHA-256，不匹配则立即删除文件并抛 `StateError`。
- **历史残余清理 (`cleanOldUpdateFiles`)**：在 `checkForUpdatesWithFallback` 启动时异步执行，清理临时目录中 `QustSchedule_*.part*` 碎片、版本号 `<= currentVersion` 的历史安装包，以及调用 `AppInstaller.cleanLegacyUpdaterScriptAsync` 清理残留的 `.cmd`/`.vbs`/`.update_staging`。

### 6.3 `AppInstaller` 与 `AppUpdaterBridge.kt` 跨平台安装契约

#### (1) Android 安装桥接 (`AppUpdaterBridge.kt` & `AppInstaller`)
- **MethodChannel 名称**：`"com.fangzi.qustschedule/updater"`
- **方法契约表**：

| Method 名称 | 参数 | 返回值 / 错误码 | Android 原生行为 (`AppUpdaterBridge.kt`) |
| :--- | :--- | :--- | :--- |
| `canRequestPackageInstalls` | 无 | `bool` | Android 8.0 (`O`) 及以上返回 `packageManager.canRequestPackageInstalls()`；低版本返回 `true` |
| `openInstallSettings` | 无 | `true` / `OPEN_SETTINGS_FAILED` | 启动 `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` (`package:${context.packageName}`, `FLAG_ACTIVITY_NEW_TASK`) |
| `installApk` | `{"filePath": String}` | `true` / `INVALID_PATH`, `FILE_NOT_FOUND`, `INSTALL_FAILED` | Android 7.0 (`N`) 及以上通过 `FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", apkFile)` 构造 `content://` URI，附加 `FLAG_GRANT_READ_URI_PERMISSION | FLAG_ACTIVITY_NEW_TASK` 拉起 `application/vnd.android.package-archive` 安装器 |

#### (2) Windows 便携版（`.zip`）与安装版（`.exe`）无黑框自替换重启机制 (`lib/src/updater/app_installer.dart`)

| 维度 | Windows 便携版 (`.zip` 热更新) | Windows 安装版 (`setup.exe` 静默升级) |
| :--- | :--- | :--- |
| **前置校验与准备** | 1. 在 `appDir` 创建并删除 `.write_test_<ts>.tmp` 校验写权限（若装在受保护的 `Program Files` 无写权限，抛 `FileSystemException` 提示手动解压）；<br>2. 清空并创建隔离暂存目录 `${appDir}\.update_staging`；<br>3. 调用系统内置 `tar.exe -xf <zip> -C <.update_staging>` 解压；<br>4. 校验 `.update_staging\qustschedule.exe` 存在且非空 | 在安装包所在临时目录 `setupDir` 生成脚本 |
| **辅助脚本文件名** | `qustschedule_updater.cmd` + `qustschedule_launcher.vbs`（位于 `appDir`） | `qustschedule_setup_updater.cmd` + `qustschedule_setup_launcher.vbs`（位于 `tempDir`） |
| **隐藏窗口启动器** | `wscript.exe` 以 `ProcessStartMode.detached` 运行纯 ASCII VBS：`CreateObject("WScript.Shell").Run "cmd.exe /c ""...""", 0, False`（失败回退 `cmd.exe /c`），随后 Dart 主进程立即调用 `exit(0)` | 同左 |
| **PID 退出轮询块** | `buildWindowsPidWaitBlock(pid)`：用 `tasklist /FI "PID eq <pid>" /FO CSV /NH \| find ",""<pid>"","` 配合 `ping 127.0.0.1 -n 2 >nul` 每秒轮询，**最多等待 20 次（约 20 秒）**，确保旧进程彻底释放文件句柄与单实例 Mutex | 同左 |
| **替换 / 安装命令** | `robocopy ".update_staging" "." /E /IS /IT /NFL /NDL /NP /NJH /NJS /R:5 /W:1 >nul 2>nul`；仅当 `not errorlevel 8`（robocopy 退出码 `< 8` 表示成功）时才删除 `.update_staging`；随后 `start "" "qustschedule.exe"` 并自删 `.vbs` 与 `.cmd` | `start "" "<setupFileName>" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /AUTOSTART=1`，随后自删 `.vbs` 与 `.cmd` |

---

## 7. Windows 桌面原生壳与安装包 (`windows/runner/*`, `windows/packaging/setup.iss`)

### 7.1 单实例互斥锁与窗口唤醒 (`windows/runner/main.cpp`)
- **命名互斥量**：`Local\com.fangzi.qustschedule.SingleInstance`
- **窗口类名与标题**：`kWindowClassName = L"FLUTTER_RUNNER_WIN32_WINDOW"`，`kAppWindowTitle = L"\u9752\u79D1\u8bfe\u8868\u901a"`（`"青科课表通"`，使用 `\u` 转义确保 MSVC CP936 代码页下无 C4819 编译错误）。
- **单实例冲突与热更新重启退避 (`AcquireSingleInstanceMutex`)**：
  - 当 `CreateMutexW` 返回 `ERROR_ALREADY_EXISTS` 时，可能是用户重复双击，也可能是刚执行完热更新重启、旧进程正处于退出收尾阶段。
  - 循环最多 **30 次**（每次间隔 `100ms`，共 3 秒）：
    1. 若 `FindWindowW(kWindowClassName, kAppWindowTitle)` 找到已存在的窗口，立即调用 `ActivateExistingWindow`（`SW_RESTORE` / `SW_SHOW` + `SetForegroundWindow` + `BringWindowToTop`）唤醒旧窗口并退出新进程（返回 `EXIT_SUCCESS`）。
    2. 若未找到窗口，调用 `WaitForSingleObject(mutex, 100)` 等待旧进程释放互斥量；一旦拿到 `WAIT_OBJECT_0` 或 `WAIT_ABANDONED`，新进程接管互斥量并继续正常启动。

### 7.2 窗口尺寸、DPI 与深色标题栏 (`windows/runner/win32_window.cpp`)
- **初始尺寸**：起点 `(10, 10)`，大小 `1280 × 720`（按当前显示器 DPI 缩放 `dpi / 96.0`）。
- **最小窗口尺寸限制 (`WM_GETMINMAXINFO`)**：`ptMinTrackSize.x = 360 * scale_factor`，`ptMinTrackSize.y = 520 * scale_factor`（逻辑像素 `360 × 520`），防止课表网格被挤压崩溃。
- **沉浸式深色标题栏 (`UpdateTheme`)**：读取注册表 `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme`，当值为 `0` 时调用 `DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE (20), ...)` 开启深色窗口边框。
- **首帧防白屏 (`flutter_window.cpp`)**：在 `SetNextFrameCallback` 中才调用 `this->Show()`，并配合 `ForceRedraw()` 确保首帧渲染就绪后再显示窗口。

### 7.3 Inno Setup 安装包契约 (`windows/packaging/setup.iss`)
- **固定标识**：`AppId={{A7F3E2D1-6B4C-4E8A-9D52-1C3B5E7F9A24}`，`AppMutex=Local\com.fangzi.qustschedule.SingleInstance`，`MyAppExeName="qustschedule.exe"`（**严禁修改 `qustschedule.exe` 文件名**，否则 `path_provider` 与 DPAPI 数据目录派生路径改变会导致用户丢失已存凭据与设置）。
- **免管理员权限安装**：`PrivilegesRequired=lowest`，默认安装路径 `{localappdata}\Programs\青科课表通`（免 UAC 弹窗，也确保应用内更新拥有写权限）。
- **静默升级自动重启支持**：`[Run]` 段配置 `Check: ShouldAutoStart`，当命令行传入 `/AUTOSTART=1`（由 `AppInstaller.windowsSetupSilentArgs` 传入）且处于静默模式时，安装完成后自动非阻塞拉起 `{app}\qustschedule.exe`。
- **VC++ 运行库检测 (`IsVCRedistInstalled`)**：非静默安装结束 (`ssPostInstall`) 时检查注册表 `SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64\Installed`，缺失时弹窗引导下载 `vc_redist.x64.exe`。

---

## 8. `packages/zf_academic` 纯 Dart 教务协议层参考

### 8.1 双入口架构
- `package:zf_academic/zf_academic.dart`：**100% 纯 Dart 入口**（无 `dart:io`、无 Flutter 依赖），可在任何环境或无套接字测试中运行。
- `package:zf_academic/zf_academic_io.dart`：**`dart:io` 扩展入口**，额外导出 `FileCookieStorage`、`DartIoTransport` 与工厂函数 `ZhengfangClient vmZhengfangClient(ZfClientConfig config, {DartIoTransport? transport})`。

### 8.2 `ZfEndpoints` 与青科大端点预设 (`packages/zf_academic/lib/src/types.dart`)

| 字段名 | `ZfEndpoints` 默认值 | `qustZfEndpoints`（青科大预设） | 用途 |
| :--- | :--- | :--- | :--- |
| `loginPagePath` | `'/xtgl/login_slogin.html'` | 同默认 | 表单登录 GET/POST 页 |
| `publicKeyPath` | `'/xtgl/login_getPublicKey.html'` | 同默认 | RSA 公钥 JSON 获取 (`modulus`, `exponent`) |
| `captchaPath` | `'/kaptcha'` | 同默认 | 验证码图片默认路径 |
| `studentInfoPath` | `'/xtgl/index_cxYhxxIndex.html'` | 同默认 | 学生姓名与学号读取页（带 `?gnmkdm=index`），失败回退 `/xtgl/index_initMenu.html` |
| `schedulePath` | `'/kbcx/xskbcx_cxXsKb.html'` | **`'/kbcx/xskbcx_cxXskbcxIndex.html'`** | 课表页面 HTML（含学期下拉框）与 Referer |
| `scheduleQueryPath` | `null`（回退用 `schedulePath`） | **`'/kbcx/xskbcx_cxXsgrkb.html'`** | 课表 JSON POST 查询端点 |
| `scheduleGnmkdm` | `'N253508'` | **`'N2151'`** | 课表功能模块代码 |
| `personal` | `false` | **`true`** | 为 `true` 时课表 POST 额外附加 `kzlx: 'ck'`, `xsdm: ''`, `kclbdm: ''`, `kclxdm: ''` |
| `gradesPath` | `'/cjcx/cjcx_cxDgXscj.html'` | 同默认 | 成绩查询页与 POST 端点 (`doType=query`) |
| `gradeGnmkdm` | `'N305005'` | 同默认 | 成绩功能模块代码 |
| `examsPath` | `'/kwgl/kscx_cxXsksxxIndex.html'` | 同默认 | 考试安排查询页与 POST 端点 (`doType=query`) |
| `examGnmkdm` | `'N358105'` | 同默认 | 考试功能模块代码 |

### 8.3 `ZhengfangClient` 核心认证与查询机制 (`packages/zf_academic/lib/src/zhengfang_client.dart`)

1. **表单直登流水线 (`login` -> `_loginViaForm` -> `_submitFormLogin`)**：
   - 入口先调用 `_cookies.invalidate()` 作废旧 Cookie 并递增 `generation`。
   - 探测 `/sso/zfiotlogin`（`followRedirects: false`）：若发现正方 CAS 统一认证跳转，抛 `ErrorCode.unsupported`。
   - GET 登录页提取所有 `input[type=hidden]`（含 `csrftoken`，缺失则先过 `inspectResponse` 判 5xx/403，否则抛 `PAGE_CHANGED`）、密码加密标志 `mmsfjm`（所有 `input[name=mmsfjm|#mmsfjm]` 取值必须唯一且为 `'0'` 或 `'1'`，否则抛 `PAGE_CHANGED`）及 `csrfTokenLogout`。
   - **验证码拦截**：调用 `detectCaptcha(page.body)` 扫描表单内 `RANDOMCODE` / `yzm` / `authcode` / `captcha` 输入框与验证码图片。若存在，保存 `FormPendingLogin`（有效期 `_pendingTtlMs = 300000` 即 5 分钟，绑定当前 `_cookies.generation`），拉取图片（经 `sniffMimeType` 校验 PNG/GIF/JPEG/BMP/WEBP 魔数，防把 HTML 登录页当图片）并返回 `CaptchaState`。
   - **RSA 密码加密**：当 `mmsfjm == '1'` 时，每次提交登录表单均针对当前新 `JSESSIONID` 实时 GET `publicKeyPath` 获取 base64 的 `modulus` 与 `exponent`（**严禁跨登录缓存 RSA 公钥**，正方服务端密钥对与当前会话绑定，复缓存旧公钥会导致二次重登解密失败误报「用户名或密码不正确」），调用 `zfFormEncryptPassword(modulus, exponent, password)` 执行 `RSA/ECB/PKCS1Padding` 加密并转 base64。
   - **登录前会话清理**：模仿浏览器 `login.js` 的 `yhdl()`，先向 `/xtgl/login_logoutAccount.html` 发送 POST (`csrfTokenLogout`)，忽略其异常。
   - **双 `mm` 字段提交**：表单 POST 到 `login_slogin.html?time=<ms>` 时，通过 `postPairs` 发送两个同名 `('mm', mm)` 键值对（对应页面可见 `#mm` 与隐藏 `#hidMm`）。
   - **结果判定**：若响应仍是登录页 (`isLoginPage`)，调用 `_classifyLoginFailure` 区分 `invalidCredentials` 与 `captchaRequired`（若来自 `submitCaptcha` 重试且验证码错误，自动调用 `refreshCaptcha()` 返回新 `CaptchaState`）；否则调用 `_readIdentity()` 读取学号姓名并返回 `AuthenticatedState`。

2. **三态会话校验 (`checkSession()`)**：
   - 返回 `SessionState(status: SessionStatus, studentId, studentName)`，其中 `SessionStatus` 为三态：
     - `authenticated`：成功从 `studentInfoPath` 或回退 `_indexMenuPath` 读到学号/姓名或已登录特征词；
     - `expired`：无 Cookie、请求抛 `SESSION_EXPIRED`、或返回 `isLoginPage(body)`；
     - `unknown`：HTTP 非 2xx 或页面不含身份特征但也不是登录页。**`unknown` 绝不当作会话过期，不得触发自动重登**。

3. **课表路由自动发现 (`_discoverScheduleRoute`)**：
   - 当默认课表端点返回 `"没有访问权限"` / `"无访问权限"` (`isPermissionDenied`) 时，自动请求 `/xtgl/index_initMenu.html` 扫描 `clickMenu('N...', '/kbcx/...', ...)`，从中提取学校实际启用的 `gnmkdm` 与路径并重试。

4. **成绩查询「数据优先 + 空数据未评教拦截」(`fetchGrades`)**：
   - 先用 `listRowsOrEmpty(response.body, ['items', 'data', 'rows'])` 尝试提取成绩行。
   - **若 `rows.isNotEmpty`，直接解析返回成绩**（防止某门课名叫「教学质量评价与监控」误触发未评教拦截）。
   - **仅当 `rows.isEmpty` 时**，检查 `messageOf(response.body)` 是否含 `'评价'`/`'评教'` 或正文含 `'教学质量评价'`/`'请先评教'`，命中则抛 `AcademicError(ErrorCode.notEvaluated, ...)`。

### 8.4 `AcademicHttpClient` 重定向、白名单与响应诊断 (`http_client.dart` & `respond.dart`)

- **手动跟随重定向与协议防降级**：
  - 底层 `DartIoTransport` 固定 `httpRequest.followRedirects = false`，由 `AcademicHttpClient` 手动逐跳跟随（上限 `_defaultMaxRedirects = 12`），每跳重新执行 `_ensureAllowed` 主机/端口/协议白名单校验并收集 `Set-Cookie`。
  - **同主机 HTTP 302 自动升级 (`_upgradeDowngrade`)**：青科大等校登录成功后会 302 到同主机的 `http://` 地址；客户端对「同主机 + 默认 80 端口」的 `http` 重定向自动升级回 `https://`（沿用原 HTTPS 端口），既满足「HTTPS 学校禁止降级到 HTTP」的安全约束，又避免跳转卡死。
  - **跨主机统一认证重定向识别 (`_looksLikeAuthRedirect`)**：当请求被 302 到白名单外的 `cas.` / `sso.` / `auth.` / `idp.` 主机或含 `service=` / `ticket=` 的登录地址时，不访问外部地址，直接将其转化为 `ErrorCode.sessionExpired` 以触发客户端自动重登，而非报 `UNTRUSTED_URL`。
  - **外网 403 / 维护页重定向重分类 (`_reclassifyUntrustedRedirect`)**：当外网访问被校园网防火墙/深信服网关 302 跳转到非白名单拦截页时，发送最多 2 跳不带 Cookie 的纯 GET 探测，识别出 403 拦截页（转化为 `ErrorCode.accessForbidden`）或 5xx 维护页（转化为 `ErrorCode.serverError`）。
- **读写分离重试与状态码映射**：
  - 读请求 (`write == false`) 网络层异常自动延迟 `250ms` 重试 1 次；写请求 (`write == true`) 绝不重试，且写请求遇到任何 3xx 重定向或 5xx 均抛 `ErrorCode.resultUnknown`。
  - 响应体大小上限 `_defaultMaxBodyBytes = 5 * 1024 * 1024`（5MB），超限立即中止流并抛 `ErrorCode.pageChanged`。
- **`inspectResponse` 诊断优先级 (`respond.dart`)**：
  1. HTTP `>= 500` -> `ResponseKind.serverError`；
  2. HTML `<title>` 或正文命中服务端崩溃/维护特征（如 `访问出错` 且不含 `403`、`bad gateway`、`whitelabel error page`、`系统维护`、`数据库连接异常`）-> `ResponseKind.serverError`（**优先于 403 判定，解决正方 500 页面标题也是「访问出错」的误判问题**）；
  3. 命中校园网防火墙特征（如 `访问出错-403`、`访问策略禁止`、`仅限校园网`、或含 `403` 且带 `禁止访问`/`访问策略`）-> `ResponseKind.accessForbidden`；
  4. 其余为 `ResponseKind.ok`。

### 8.5 数据解析器与 ID 确定性哈希 (`schedule.dart`, `academic_query.dart`, `urls.dart`, `util.dart`)

- **学期参数换算 (`urls.dart`)**：
  - `zfSemesterCodes`：`{1: '3', 2: '12', 3: '16'}`（第 1 学期 `xqm=3`，第 2 学期 `xqm=12`，第 3 学期 `xqm=16`）。
  - `calendarTerm([DateTime? now])`：使用本地时区月份，`month >= 8` 为当年第 1 学期，`month == 1` 为上一年第 1 学期，`2 <= month <= 7` 为上一年第 2 学期。
- **周次与节次解析 (`schedule.dart`)**：
  - `periods(String value)`：剥离首尾非数字字符（兼容 `[1-2节]`、`5-6节`），解析区间（`1..30`）并将相邻节次合并为连续 `(startPeriod, endPeriod)` 元组列表。
  - `tryParseWeeks(String value)`：归一化全角括号、`~`/`至`/`到`、`(周)`/`(全)`，支持 `1-4周(单)`、`1,3,5-9周(双)` 等复杂写法（合法周次范围 `1..60`，单段跨度 `<=53`）。无法解析时返回空列表 `[]`（并在 `ScheduleEntry.details` 中追加 `id: 'rawWeeks', label: '周次说明'`），不崩溃。
- **课程卡片确定性 ID (`rowKey` in `util.dart`)**：
  - `ScheduleEntry.id` 由 `rowKey([courseKey, name, '$day', '$startPeriod', '$endPeriod', rawWeeks])` 生成。
  - 算法：**32 位 FNV-1a 哈希**（初始值 `2166136261`，乘数 `16777619`，以 `\u0000` 连接字段）转 16 进制前缀 + `:` + 非空字段 `|` 连接串（截断至最多 96 字符）。保证同一门课跨刷新轮次 ID 恒定不变。
- **弹性考试时间解析 (`parseExamTime` in `academic_query.dart`)**：
  - 支持 `2025-01-08 08:30-10:30`、`2025-01-08(08:30~10:30)`、`2025年01月08日 08:30至10:30`、单点时间 `2025-01-08 08:30` 或纯日期 `2025-01-08`。
  - `ExamItem.effectiveEndTime`：若 `endTime != null` 直接返回；若仅有 `startTime` 且 `rawTimeStr` 含 `HH:mm` 具体时刻，按 `+2 小时` 估算；若仅含日期，按当日 `23:59:59.999` 估算。

### 8.6 `ErrorCode` 全量枚举速查表 (`packages/zf_academic/lib/src/errors.dart`)

| 枚举名 (`ErrorCode.*`) | `wire` 字符串常量 | 触发场景摘要 |
| :--- | :--- | :--- |
| `unsupported` | `'UNSUPPORTED'` | 学校启用正方 CAS 统一认证（暂不支持直登），或课表路由发现后仍返回「无访问权限」 |
| `notOpen` | `'NOT_OPEN'` | 教务返回「未开放 / 未开始 / 已结束」（学业页查考试遇到此码保持静默） |
| `invalidCredentials` | `'INVALID_CREDENTIALS'` | 账号或密码错误 |
| `sessionExpired` | `'SESSION_EXPIRED'` | Cookie 失效、返回登录页、HTTP 401、或被 302 到外部 CAS 认证域（**唯一触发 `ScheduleService` 自动重登的错误码**；HTTP 403 不再归入此码） |
| `captchaRequired` | `'CAPTCHA_REQUIRED'` | 登录需要验证码、验证码为空、验证码错误或自动重登时用户取消输入验证码 |
| `webLoginRequired` | `'WEB_LOGIN_REQUIRED'` | 验证码控件残缺（只有图或只有框）或教务要求网页端人工验证 |
| `noCapacity` | `'NO_CAPACITY'` | 选课容量已满 / 无余量 |
| `conflict` | `'CONFLICT'` | 选课时间冲突 |
| `alreadySelected` | `'ALREADY_SELECTED'` | 重复选课 |
| `creditLimit` | `'CREDIT_LIMIT'` | 超过学分上限 |
| `pageChanged` | `'PAGE_CHANGED'` | 登录页缺 `csrftoken`、`mmsfjm` 取值非法、RSA 公钥格式错误、验证码响应非图片魔数、响应体 `>5MB`、重定向无 `Location` 或超过 12 跳、JSON 列表结构无法识别 |
| `networkRetryable` | `'NETWORK_RETRYABLE'` | 套接字连接失败、DNS 失败、读请求重试后仍中断，以及 `asAcademicError` 的默认兜底码 |
| `serverError` | `'SERVER_ERROR'` | 读请求 HTTP 429 / 5xx，或 HTTP 200 但 `inspectResponse` 判定为正方 500 错误页 / Nginx 502 / 系统维护页 |
| `accessForbidden` | `'ACCESS_FORBIDDEN'` | 任意 HTTP 403 响应，或 `inspectResponse` / 重定向探测判定为校园网防火墙「访问出错-403」策略拦截页 |
| `resultUnknown` | `'RESULT_UNKNOWN'` | 写请求 (`write: true`) 发生网络中断、被 3xx 重定向或收到 HTTP 5xx |
| `untrustedUrl` | `'UNTRUSTED_URL'` | 请求或重定向目标不在 `allowedHosts` 白名单、端口不匹配、或 HTTPS 学校尝试降级到非同主机默认端口的 HTTP |
| `validationFailed` | `'VALIDATION_FAILED'` | 学校 URL 无法解析出主机、Cookie 快照 version != 1、登录成功后仍读不到身份、修改密码时未知当前账号 |
| `timeout` | `'TIMEOUT'` | 单次 HTTP 请求超过 `requestTimeoutMs`（默认 10000ms） |
| `cancelled` | `'CANCELLED'` | 调用了已 `close()` / `dispose()` 的 `ZhengfangClient` |
| `resourceLimit` | `'RESOURCE_LIMIT'` | 资源超限预留码 |
| `staleContext` | `'STALE_CONTEXT'` | 验证码挂起挑战超过 5 分钟 (`_pendingTtlMs`) 或期间会话 `generation` 已递增 |
| `notEvaluated` | `'NOT_EVALUATED'` | 成绩查询返回空列表且提示「教学质量评价 / 请先评教」 |
| `success` | `'SUCCESS'` | JSON 响应显式带有 `success: true` / `flag: '1'` / `code: '0'` |
