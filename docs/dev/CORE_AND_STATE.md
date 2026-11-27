# 核心状态、服务、持久化、更新与正方协议层速查 (`CORE_AND_STATE.md`)

## 0. 目录与全局符号速查

[1. 状态架构](#1-状态架构appmodel--libsrcstate) · [2. 并发与互斥不变量](#2-并发与互斥不变量) · [3. 业务服务与缓存](#3-业务服务与缓存) · [4. 排布/校历/调课/工具](#4-排布校历调课与工具库) · [5. 持久化与安全存储](#5-持久化与安全存储) · [6. 应用内更新与安装器](#6-应用内更新与跨平台安装器) · [7. Windows 原生壳](#7-windows-原生壳与安装包) · [8. `zf_academic` 协议层](#8-packageszf_academic-协议层)

| 模块域 | 路径（相对 `qustschedule/`） | 核心符号 | 职责摘要 |
| :--- | :--- | :--- | :--- |
| 状态协调器 | `lib/src/app_model.dart` | `AppModel`, `AppStatus` | 串联 5 大控制器；管 `routeNotifier`/`_authEpoch`/`_idleAcademicRestoreTimer`/`boot()`/`onAppShown()` |
| 认证会话 | `lib/src/state/auth_session_controller.dart` | `AuthSessionController` | `ScheduleService`/`schoolBaseUrl`/`username`/`studentId`/`studentName`/验证码 `Completer`/请求日志 |
| 课表周历 | `lib/src/state/schedule_controller.dart` | `ScheduleController`, `WeekNotifier` | `Schedule`/`Terms`/`week`/`weekNotifier`/`refreshingNotifier`/校历/调课与冲突缓存 (`_dataRevision`) |
| 学业数据 | `lib/src/state/academic_controller.dart` | `AcademicController` | `exams`/`grades`/`gradeStats`（引用记忆化）/`isNotEvaluated`/`_academicLoadSeq`/静默同步与变更比对 |
| 偏好防抖 | `lib/src/state/preferences_controller.dart` | `PreferencesController` | `Preferences` 读写、滑块 300ms 草稿防抖（`dispose()` 清理不落盘）、启动自动检查新版本 |
| 提示气泡 | `lib/src/state/hint_notice_controller.dart` | `HintNoticeController`, `HintScope` | 四槽隔离（`systemGlobalHint`/`academicUpdateHint`/`scheduleHint`/`academicHint`）、喜报遮挡延后计时、`storageNoticeEvent`、`humanizeError` |
| 课表服务 | `lib/src/schedule_service.dart` | `ScheduleService` | Cookie 优先抓取；`SESSION_EXPIRED` 单 flight 重登 (`_reloginFlight`) + `_sessionVersion` 防时间差二次重登、仅登录失败回滚、10m/3次白名单熔断、`reportReloginStage`、`readSavedCredentials()`/`_fallbackAccountKeys()` |
| 测试门面 | `lib/src/backends.dart` | `ScheduleBackend`, `ZfBackend`, `defaultBackendFactory` | 收窄 `ZhengfangClient` 供 DI 与单测替换 |
| 学业服务 | `lib/src/academic_service.dart` | `AcademicService`, `GradeStats` | 抓取/缓存考试与成绩；`notEvaluated` 保留旧成绩；原生 `jd` 加权 GPA |
| 课表缓存 | `lib/src/schedule_cache.dart` | `CachedSchedule`, `ScheduleCache`, `FileScheduleCache`, `LateScheduleCache` | `zf-schedule-cache.json` (`baseUrl`/`fetchedAt`/`schedule`/`remarks`) |
| 学业缓存 | `lib/src/academic_cache.dart` | `CachedTermExams`, `ExamCache`, `FileExamCache`, `CachedTermGrades`, `GradesCache`, `FileGradesCache`, `InMemory*`, `Late*` | 按 `termId` 分桶持久化 `zf-exam-cache.json` / `zf-grades-cache.json` (`SafeJsonFile.updateJson`) |
| 学期筛选 | `lib/src/term_selector_helper.dart` | `parseEnrollmentYear`, `estimateCurrentAcademicYear`, `filterTerms`, `resolveSemesterCode`, `formatTermPrimaryLabel` | 学号推入学年；过滤入学前/未来/短学期 (`xqm=16`)；映射「大一~大五 上/下学期」 |
| 学校线路 | `lib/src/school.dart` | `SchoolProfile`, `qustProfile`, `qustLines`, `knownSchools`, `presetSchoolUrls`, `defaultSchool`, `defaultAcademicPaceHosts`, `schoolLabel`, `sameSchool`, `normalizeSchoolKeyUrl`, `buildAccountKey` | 青科大默认线路、站点降频配置、URL 规范化与凭据键拼接 |
| 作息表 | `lib/src/timetable.dart` | `PeriodGroup`, `SectionTime`, `BigBreak`, `Timetable`, `QuickSetup`, `buildSections`, `activeTimetableAt`, `reconcileSections`, `sectionOfPeriod`, `sectionStartMinutes`, `sectionEndMinutes` | 多套作息表按月日 (`month*100+day`) 跨年循环切换；三段节数对齐与节次时刻推导 |
| 校历换算 | `lib/src/term_calendar.dart` | `dayOnly`, `dateAtMinutes`, `mondayOf`, `estimateTermStart`, `weekOf`, `dateOf`, `termStartFromWeek`, `weekRangeLabel`, `conflictLayout` | 开学日估算/反推、周次互转、同天重叠课程并列槽位 (`index, total`) |
| 按日调课 | `lib/src/reschedule.dart` | `RescheduleRule`, `RescheduleConflict`, `RescheduleWeekView`, `rescheduleWeekView` | 纯渲染层按实例调课叠加，不改原 `Schedule`；冲突时调入课优先 |
| 地点短名 | `lib/src/course_text.dart` | `roomOnly` | 取空白分隔末段并剥离 `^.*?校区` 前缀 |
| 轻量分词 | `lib/src/formatted_text.dart` | `FormattedSegmentKind`, `FormattedSegment`, `parseFormattedSegments` | 纯 Dart 解析 `**加粗**` 与 `` `行内代码` ``（供 Isolate 与 `widgets/formatted_text_span.dart` 消费） |
| 稳定哈希 | `lib/src/stable_hash.dart` | `coursePaletteColorCount`, `fnv1a32`, `fnv1a32Hex`, `courseColorIndex` | 纯 Dart FNV-1a 32 位哈希与 9 色板索引（供主题/提醒/小组件共享） |
| 路由落稳 | `lib/src/route_settled.dart` | `runInBackground`, `RouteSettledHandle`, `scheduleAfterRouteSettled`, `RouteSettledStateMixin`, `RouteSettledGate` | 入场与后台 Isolate 并行；重子树在非 `offstage` 且 `completed` 时粘性挂载 |
| 动态版本 | `lib/src/app_version.dart` | `appVersion`, `appVersionFull`, `loadAppVersion` | 从 `pubspec.yaml` 资产解析版本 |
| 偏好存储 | `lib/src/preferences_repository.dart` | `Preferences`, `preferencesSchema` (15), `defaultUpdateProxyUrl`, `presetUpdateProxies`, `setAppearance` | `app_prefs.json` Schema 15 读写、迁移、合并外观落盘、`didResetFromCorruption` |
| 安全凭据 | `lib/src/credentials_repository.dart` | `SecureCredentialStore` | `flutter_secure_storage` v11 (Keystore/DPAPI)，SHA-256 键名存账密 |
| 会话快照 | `lib/src/session_repository.dart` | `SessionRepository`, `FileSessionRepository`, `LateSessionRepository` | `zf-session.json` Cookie 持久化 |
| 安全 JSON | `lib/src/safe_json_file.dart` | `SafeJsonFile`, `SafeJsonReadResult`, `isolateJsonDecodeThreshold` (16KB) | 路径串行队列、写合并、`.tmp` 原子替换、`.bak` 自愈、`>=16KB` Isolate 解码 |
| 更新状态机 | `lib/src/updater/update_flow_controller.dart` | `UpdateFlowController`, `UpdateFlowStage` | 全局更新状态机：注入 `UpdaterGateway`/`isAndroid`、`_downloadEpoch`/`_isTriggeringInstall` 防竞态、后台下载与权限续装 |
| 更新服务 | `lib/src/updater/update_service.dart` | `UpdateService`, `CancelToken` | Release 检查、代理轮询、Range 探测、`>=4MB` 3 线程分块与单流降级、旧包清理 |
| 更新模型 | `lib/src/updater/update_models.dart` | `ReleaseAsset`, `ReleaseInfo`, `UpdateStatus`, `UpdateCheckResult`, `DownloadProgress`, `ProxyTestResult`, `UpdateProxyPreset`, `defaultUpdateProxyUrl`, `kPresetUpdateProxyEntries`, `presetUpdateProxies`, `displayProxyName`, `cleanReleaseBody` | Release 解析、预设代理真源、CI 表清洗、进度/测速模型 |
| 更新网关 | `lib/src/updater/updater_gateway.dart` | `UpdaterGateway`, `MethodChannelUpdaterGateway` | 隔离 `AppInstaller` 通道与 `url_launcher` 外部浏览器调用 |
| 安装器 | `lib/src/updater/app_installer.dart` | `AppInstaller` | Android MethodChannel (`defaultChannel`/`isAndroid`)；Windows 便携 `.update_staging` + VBS/CMD + `robocopy` / 安装版静默升级 |
| 版本比对 | `lib/src/updater/version_comparator.dart` | `compareSemanticVersions`, `isVersionNewer` | 支持 `v`/`V`、`+build`、`-alpha/-beta/-rc` |
| Android 桥 | `android/.../updater/AppUpdaterBridge.kt` | `AppUpdaterBridge`, `UpdaterWorker` | `com.fangzi.qustschedule/updater`：`UpdaterWorker` 校验文件/`FileProvider` + `postReply` (`@Volatile disposed`) |
| Windows 壳 | `windows/runner/*`, `windows/packaging/setup.iss` | `wWinMain`, `FlutterWindow`, `Win32Window` | 单实例 Mutex（30×100ms 退避）、最小 `360×520`、深色标题栏 |
| 正方协议包 | `packages/zf_academic/lib/*` | `ZhengfangClient`, `AcademicHttpClient`, `CookieStore`, `FileCookieStorage`, `ErrorCode`, `AcademicError` | 纯 Dart 零 Flutter 依赖：RSA 表单登录、验证码、课表/学期/考试/成绩、主机白名单与重定向策略 |

---

## 1. 状态架构 (`AppModel` & `lib/src/state/*`)

### 1.1 `Listenable` 局部订阅表

`AppModel` 为 Facade，内部拆为 5 控制器 + 独立监听源；UI 须按最小作用域订阅，禁盲目监听顶层 `AppModel`。**薄透传冻结**：`AppModel` 既有 1:1 转发（上限冻结 `<= 134`，`architecture_guard_test.dart` 守护）仅作向后兼容，后续新增状态或动作由新页面直接读/订对应子控制器，不再往 `AppModel` 新增透传包装：

| 监听源 | 暴露位置 | 触发时机 | 订阅方 | 不触发场景 |
| :--- | :--- | :--- | :--- | :--- |
| `routeNotifier` (`ChangeNotifier`) | `AppModel.routeNotifier` | `AppStatus`/`message`/`errorCode` 变化或 `refreshCaptcha()` 完成 | 顶层路由切换器 | 翻页、转圈、气泡、学业、滑块 |
| `hints` (`HintNoticeController`) | `AppModel.hints` | `globalHint`/`scheduleHint`/`academicHint` 变更；`storageNoticeEvent++` | `StatusPopup`、存储异常 `SnackBar` | 课表/周次/设置变更 |
| `scheduleState` (`ScheduleController`) | `AppModel.scheduleState` | `schedule`/`terms`/`termStart`/跨天同步变更 | 课表网格、学期选择器 | 翻页 (`weekNotifier`)、转圈 (`refreshingNotifier`) |
| `weekNotifier` (`WeekNotifier`) | `AppModel.weekNotifier` / `scheduleState.weekNotifier` | `goToWeek`/`goToThisWeek`/校准周次（支持同值 `.notify()`） | `WeekPager`、顶栏周次、回本周 | 静默刷新、学业、气泡 |
| `refreshingNotifier` (`ValueNotifier<bool>`) | `AppModel.refreshingNotifier` / `scheduleState.refreshingNotifier` | 课表拉取或自动重登起止 | 刷新旋转动画、加载指示器 | 课表网格卡片 |
| `academic` (`AcademicController`) | `AppModel.academic` / `academicNotifier` | `exams`/`grades`/`isNotEvaluated`/`academicLoading`/`academicError`/跨天倒计时 | `AcademicPage` | 翻页、课表刷新、滑块 |
| `prefsNotifier` (`ValueNotifier<int>`) | `AppModel.prefsNotifier` / `prefs.prefsNotifier` | 偏好落盘、身份记忆、开学日、滑块防抖草稿（值 `++`） | 设置页、课表外观、`ReminderService`、`WidgetService` | `saveQuickSetup(notifyPrefsChanged: false)` |
| `updateFlow` (`UpdateFlowController`) | `AppModel.updateFlow` / `prefs.updateFlow` | `stage`/`progress`/代理切换/后台事件序号变更 | `UpdateDialog`、更新角标 | 教务请求与课表操作 |

### 1.2 `AppStatus` 流转

| 状态 | 进入条件 | UI 行为 |
| :--- | :--- | :--- |
| `booting` | 初始态或 `boot()` | 启动过渡；`isGlobalPopupActive == true` |
| `needLogin` | 冷启动无缓存无凭据；自动重登失败且无旧课表；`signOut()`/`cancelCaptcha()`/`retryAfterSessionLoss()`/`changeSchool(relogin: false)` | 切 `LoginPage`；清空课表与学业气泡 |
| `signingIn` | `signIn()` / `submitCaptcha()` | 锁登录按钮；`isGlobalPopupActive == true` |
| `needCaptcha` | 手动登录返回 `CaptchaState`，或后台重登 `_handleCaptcha` 挂起 | 切 `CaptchaPage`（按 `hasPendingReloginCaptcha` 区分） |
| `loading` | 无缓存 `_loadSchedule()`、`retry()` 前台重拉、`changeSchool(relogin: true)` | 全局加载气泡；`isGlobalPopupActive == true` |
| `ready` | `_restoreCachedSchedule()` 命中同校缓存，或 `_loadSchedule()` 成功 | 常驻 `HomeShell` |
| `failed` | 前台 `_loadSchedule`/`signIn`/`submitCaptcha`/`changeSchool` 抛错，或手动 `refresh()` 遇 `sessionExpired`/`invalidCredentials` | 有缓存留 `HomeShell` 弹常驻错窗，无缓存留 `LoginPage`；`dismissError()` 有课表回 `ready` 否则 `needLogin` |

### 1.3 `AppModel` 核心签名与 `boot()` 流水线

```dart
class AppModel extends ChangeNotifier {
  AppModel({ScheduleService? service, SessionRepository? repository, CredentialStore? credentials,
    Preferences? preferences, ScheduleCache? scheduleCache, ExamCache? examCache, GradesCache? gradesCache,
    AcademicService? academicService, UpdateFlowController? updateFlow, String? schoolBaseUrl,
    Future<Directory> Function()? supportDirectoryLoader});
  Future<void> boot();
  Future<void> onAppShown();
  Future<void> syncSilently(); // 独立单飞总调度：并行拉起课表线与学业静默线（跨学期自动补跑）
  Future<void> refresh();      // 仅课表线（不触发学业同步）
  Future<void> signIn(String username, String password);
  Future<void> submitCaptcha(String code);
  Future<void> refreshCaptcha();
  void cancelCaptcha();
  Future<void> changeSchool(String baseUrl, {bool relogin = true});
  Future<void> changePassword(String newPassword);
  Future<void> retry(); // 失败切校 -> needsReloginError 跳登录 -> 前台重拉课表
  void retryAfterSessionLoss();
  Future<void> signOut();
  void dismissError();
  bool get hasPendingSchoolSwitch;
  bool get canRetryError;      // schedule != null && errorCode != 'WEB_LOGIN_REQUIRED'
  bool get needsReloginError;  // 非切校失败且 SESSION_EXPIRED / INVALID_CREDENTIALS
  bool get academicNeedsRelogin;
  void goToWeek(int week);
  void goToThisWeek();
  Future<void> calibrateCurrentWeek(int week);
  Future<void> resetCalendar();
  void setAcademicTerm(String termId);
  Future<UpdateCheckResult> checkForUpdates();
  Future<ProxyTestResult> testUpdateProxy(String proxyUrl);
  Future<int> cleanOldUpdateFiles({String? currentVersion, Directory? targetDirectory});
  Future<bool> openExternalUrl(String rawUrl);
  Future<void> setAutoCheckUpdate(bool value);
  Future<void> loadAcademicData({String? termId, bool forceRefresh = false, bool showHint = false});
  Future<void> refreshAcademicData({bool showHint = true});
  Future<void> clearAcademicDataForDebug();
}
```

**`boot()` 流水线**：
1. 取消 `_idleAcademicRestoreTimer`，置 `AppStatus.booting`。
2. 未注入的持久化组件以 `supportDirectoryLoader ?? getApplicationSupportDirectory()` 并发打开：`FileSessionRepository` (`zf-session.json`)、`Preferences` (`app_prefs.json`)、`FileScheduleCache` (`zf-schedule-cache.json`)、`FileExamCache` (`zf-exam-cache.json`)、`FileGradesCache` (`zf-grades-cache.json`)。
3. `rebind` 到各子控制器；若 `Preferences.didResetFromCorruption`，调 `hints.emitStorageNotice('本地设置文件已损坏且无法恢复，已重置为默认设置')`；置 `prefs.preferencesLoaded = true`（此前 `ReminderService` 禁因默认 `reminderEnabled == false` 清空闹钟）。
4. `session.restoreSavedSchoolIfNeeded()`（同步 `service.switchSchool`）与 `session.restoreAccount()`（从 `accountOf`/`studentNameOf` 恢复 `_username`/`_studentId`/`_studentName`/`service.accountHint`）。
5. 并发执行 `session.service.bootstrap()` 与 `scheduleState.scheduleCache.load()`。
6. **分支 A（`cached != null && sameSchool(cached.baseUrl, schoolBaseUrl)`）**：`_restoreCachedSchedule(cached)` 直达 `ready`（0 延迟）；若需静默同步则由 `syncSilently()` 并行拉起课表与学业（学业线先读旧缓存兜底并比对），否则 `Timer(Duration.zero)` 恢复 `academic.restoreCachedData(termId)`；若 `snapshot != null` 且姓名/学号空则 `unawaited(session.syncIdentityQuietly())`；直接返回。
7. **分支 B（无缓存）**：`snapshot == null` 时调 `session.service.readSavedCredentials()`（含规范化键与兼容键回退），有则恢复 `session.username` 并 `_loadSchedule()`，无则置 `needLogin`；`snapshot != null` 直接 `await _loadSchedule()`。

### 1.4 五大子控制器契约 (`lib/src/state/*`)

- **`AuthSessionController` (`auth_session_controller.dart`)**：
  - `accountKey({String? username}) => buildAccountKey(_schoolBaseUrl, username ?? _username)`（`ScheduleService._accountKey` 同调 `buildAccountKey(_baseUrl, account)`，账号回退：`显式 > accountHint > sessionInfo?.username ?? ''`）。
  - **空 `username` 兜底**：免登冷启动必须经 `restoreAccount()` 将 `accountOf` 写入 `service.accountHint`，否则重登时 `accountKey` 缺账号导致取不到密码。
  - **改密账号解析 (`_resolveAccountForPasswordChange`)**：`service.sessionInfo?.username` -> `username` -> `service.accountHint` -> `studentId`。
  - **重登验证码挂起**：`handleCaptcha` 建 `_captchaCompleter`（旧未完成先 `complete(null)`）切 `needCaptcha`，`hasPendingReloginCaptcha == true`；`submitCaptcha` 走 `completePendingCaptcha` 唤醒原 `_reloginFlight`。
  - **切校事务回滚 (`rollbackSchool`)**：切校前仅从内存取 `previousCookies = service.exportCurrentCookies()`；`service.signIn()` 用 `_ensureClient(loadCookies: false)` 跳过 `bootstrap()` 防误删磁盘原校快照；仅 `AuthenticatedState` 后落盘 `currentSchool` 并清旧缓存（同校重登不清 `scheduleCache`）。失败/遇 `WebLoginState`/取消验证码时 `rollbackSchool` 恢复原校、账号与非空内存 Cookie。
- **`ScheduleController` (`schedule_controller.dart`)**：
  - `maxWeek = max(defaultMaxWeeks(18), maxWeeksOf(entries))`，手动校准超出时自动撑大；`gridSectionCount = max(_dataMaxPeriod, _prefs.sectionCount)`（超出时 `hasSectionsBeyondTimetable == true`）。
  - 缓存 `_rescheduleCache` / `_conflictLayoutCache` 由 `_ensureWeekViewCacheValid()` 校验 `identical(schedule)` / `_termStart` / `_maxWeek` / `listEquals(reschedules)`，失效或 `_invalidateWeekCaches()` 清空并 `_dataRevision++`。
  - `syncCalendarDay()`：跨天且停在昨日自然周时自动推进 `_week`；`shouldRefreshOnShow`：`autoRefresh && !refreshing && hasSchedule && (lastFetchedAt == null || elapsed >= intervalMinutes)`。
- **`AcademicController` (`academic_controller.dart`)**：
  - `academicTermId` 优先级：显式选中 `_academicTermId` > `_fallbackTermIdReader()` (`scheduleState.termId`) > `_termsReader()?.currentId` > `''`。
  - `loadedAcademicTerm` 防串台：切到无缓存新学期拉取前立即清空 `_exams`/`_grades`、置 `_isNotEvaluated = false`、更新 `_loadedAcademicTerm = target`。
  - 错误处理：考试 `ErrorCode.notOpen` 静默；成绩 `ErrorCode.notEvaluated` 置 `_isNotEvaluated = true`、保留 `existingGrades` 并写回 `GradesCache`、不写 `_academicError`；其余经 `humanizeError` 写 `_academicError`，若 `sessionExpired`/`invalidCredentials` 置 `_academicNeedsRelogin = true`。
  - `_diffChangeMessage`：原有缓存 (`hasOldExams || hasOldGrades`) 或 `_academicDataClearedForDebug` 且 `!listEquals` 时弹 2s 全局提示（`isAcademicUpdate: true`）。
- **`PreferencesController` (`preferences_controller.dart`)**：
  - 300ms 防抖草稿：`setCellHeight` / `setCourseTextScale` 仅更 `_cellHeightDraft` / `_courseTextScaleDraft` 并重置 `_appearanceTimer`，到期或 `flushAppearance()` 合并调 `Preferences.setAppearance()` 落盘；`dispose()` 置 `_disposed = true`、取消定时器并清空草稿（**不触发落盘**）。
  - `checkAutoUpdate`：`!_hasCheckedAutoUpdate && autoCheckUpdate && !_disposed` 时延迟 `initialDelay = 1s` 执行（`updateService == null` 时委托 `_updateFlow.checkForUpdates`）；遇 `UpdateStatus.networkError`/异常重试 2 次（间隔 2s）；`hasUpdate` 调 `_updateFlow.setAvailableUpdate` + `onHasUpdate`。
- **`HintNoticeController` (`hint_notice_controller.dart`)**：
  - 四槽独立隔离与显示优先级：`systemGlobalHint` > `academicUpdateHint` > `scheduleHint` > `academicHint`；`clearGlobalHint()` 仅清系统全局槽、绝不误清 `academicUpdateHint`；`setSystemStatusBusy()` 联动系统忙碌/错误态，使跨页喜报在被系统层遮挡时延后至真正露面才启动 2s 倒计时；`isGlobalPopupActive`：`AppStatus` 为 `booting`/`loading`/`signingIn`/`failed` 或 `_globalHint`/`_academicUpdateHint` 非空。
  - `humanizeError(AcademicError)` 映射：

| `ErrorCode` | 中文文案 |
| :--- | :--- |
| `invalidCredentials` | `'账号或密码错误，请核对后重试。'` |
| `sessionExpired` | 熔断 `'自动登录已暂停（多次失败或密码已变更），请重新登录。'`；无密 `'登录凭证已失效且未保存密码，请重新登录。'`；其余 `'登录凭证已失效，请重新登录。'` |
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
| 其余 (`notOpen`/`timeout` 等) | 原样 `error.message` |

---

## 2. 并发与互斥不变量

| 机制 / 变量 | 位置 | 核心不变量 |
| :--- | :--- | :--- |
| `_authEpoch` (`int`) | `AppModel` | `_resetAuthFlight()`（`signIn`/`changeSchool`/`signOut` 触发）自增 `_authEpoch` 并清空 `scheduleLoad`/`refreshing`/`_reloginStageActive`/挂起 `captcha`。重登恢复后须校验 `epoch == _authEpoch`。 |
| `scheduleLoad` (`Future<Schedule>?`) | `ScheduleController` | `_loadSchedule` 登记所有权指针；`await` 返回/异常后须校验 `scheduleLoad == loadFuture` 才写状态；置 `null` 即作废在途请求。 |
| `_reloginFlight` / `_reloginEpoch` / `_sessionVersion` | `ScheduleService` | `getSchedule`/`fetchTerms`/`fetchExams`/`fetchGrades` 遇 `sessionExpired` 先比对 `_sessionVersion`（已升级则直接拿新凭证重试 1 次，防并发时间差二次重登），否则共享全局单 flight 重登（返回递增 `_reloginEpoch`）；`reportReloginStage` 隔离可见/静默重登，网关自行广播 `stageRelogin`/`stageReloginFinished` 摘牌，不触碰课表 `refreshing`；同批次并发再过期按 `_reloginEpoch` 去重仅计 1 次。 |
| `_silentSyncFlight` | `AppModel` | `syncSilently()` 总调度单飞防重入；并行拉起课表与学业静默线（课表失败不连累学业），课表返回跨学期时自动为学业补跑；静默重登遇验证码取消且有本地课表时留 `ready` 轻提示不踢登录页。 |
| `_schoolSwitchInFlight` / `_schoolSwitchSeq` | `AppModel` | 覆盖读安全存储到新校登录完整窗口防连点重入；`_resetAuthFlight()` 递增 `_schoolSwitchSeq` 作废在途切校。 |
| `_inFlight` / `_clientFlight` | `ScheduleService` | `_inFlight` 合并并发 `getSchedule()`；`_clientFlight` 合并 `_ensureClient()` 首次构造与 `bootstrap()`。 |
| `_academicLoadSeq` / `_networkSyncedRevision` | `AcademicController` | `loadAcademicData()` / `resetOnSignOut()` 自增 `_academicLoadSeq`；`restoreCachedData` 额外校验 `_networkSyncedRevision` 防冷启动旧读盘结果覆盖已落盘的新网络同步。 |
| `SafeJsonFile._queues` & `_pendingWrites` | `SafeJsonFile` | 以 `file.absolute.path` 为键串行化 `readJson`/`writeJson`/`updateJson`/`clear`；`writeJson(coalesce: true)` 最多保留 1 在写 + 1 待写 `_PendingWrite`（原地替换 `buildPayload`）；读/改/清立即封口或取消待写。 |

---

## 3. 业务服务与缓存

### 3.1 `ScheduleService` (`lib/src/schedule_service.dart`)

- **常量**：`autoLoginLimit = 3`，`autoLoginWindow = Duration(minutes: 10)`，`requestTimeoutMs = 10000`，`_requestLogLimit = 120`，`stageRelogin = 'relogin'`，`stageReloginFinished = 'relogin_finished'`，`stageFetchingSchedule = 'fetching_schedule'`。
- **自动重登与白名单熔断 (`_loginWithSavedCredentials`)**：
  1. 调 `readSavedCredentials()`（先查规范化 `_accountKey()` `buildAccountKey(_baseUrl, account)`，未命中再遍历 `_fallbackAccountKeys()` 兼容 `http↔https` 与历史末尾 `/` 键，均在 `signOut()` 同步清理）；无则抛 `SESSION_EXPIRED`（未保存密码）。
  2. `_breakerOpen || !_autoLoginAllowed()`（10m 内真实认证失败 >= 3）置 `_breakerOpen = true` 并抛 `SESSION_EXPIRED`（自动登录次数过多）。
  3. 备份 `rollback = client.exportCookies()`（`client.login()` 入口会 `_cookies.invalidate()`）；**仅登录动作本身失败时 `_restore(client, rollback)`**，重登成功持久化并递增 `_sessionVersion` 后，后续业务重试失败绝不回滚为过期旧 Cookie。
  4. `client.login(saved)` 严格白名单计次：
     - **立即熔断 (`_breakerOpen = true`)**：`invalidCredentials`（防锁号）；
     - **计入 10m/3次窗口**：`captchaRequired`（验证码提交失败）/ `webLoginRequired` / 未知非成功态，及重登后紧接业务重试仍报 `sessionExpired`（按 `_reloginEpoch` 去重计 1 次）；
     - **永不计次**：用户在验证码页主动取消（`code == null`），以及一切网络/环境异常（`networkRetryable`/`timeout`/`serverError`/`accessForbidden`/`untrustedUrl`/`pageChanged`/`validationFailed`/`staleContext`/`resultUnknown`/`cancelled`）；
     - **清零/解除**：重登后业务成功清空 `_autoLoginFailures`；`_breakerOpen == true` 仅手动 `signIn`/`submitCaptcha` 成功或 `switchSchool` 调 `resetBreaker()` 解除。
  5. 校验 `_client == client` 后 `_persist(client)`、递增 `_sessionVersion` 并返回新 `_reloginEpoch`。
  6. `signIn()` 走 `_ensureClient(loadCookies: false)` 跳过 `bootstrap()`；`exportCurrentCookies()` 仅导出当前内存非空快照。

### 3.2 `AcademicService` & `GradeStats` (`lib/src/academic_service.dart`)

- `GradeStats`：`averageGpa` (`sum(gradePoint * credit) / sum(credit where gradePoint != null && credit > 0)`)、`totalCredits`、`passedCredits`、`totalCourses`、`passedCourses`。
- **铁律**：`GradeStats.calculate` 仅用教务原生 `grade.gradePoint` (`jd`)，禁自行按百分制换算。
- **`isGradePassed(grade)`**（满足其一）：① `numericScore ?? double.tryParse(rawScore) >= 60.0`；② `passingScoreLabels` (`['通过','合格','优秀','良好','中等','及格','免修','免考','P','p']`) 命中 `rawScore.trim()`；③ `gradePoint != null && gradePoint! > 0`。

### 3.3 离线缓存 (`schedule_cache.dart`, `academic_cache.dart`)

| 类 | 文件名 | 顶层 JSON 与校验 | 损坏处理 |
| :--- | :--- | :--- | :--- |
| `FileScheduleCache` | `zf-schedule-cache.json` | `{"baseUrl": 非空, "fetchedAt": ISO8601, "schedule": {"termId": 非空, "maxWeeks": int, "entries": [...], "remarks": [...]}}` | `hadUnrecoverableCorruption` 时 `clear()` 并返 `null` |
| `FileExamCache` | `zf-exam-cache.json` | `{"updatedAt": ISO8601, "terms": {"<termId>": {"termId", "fetchedAt", "items": [ExamItem]}}}` | 同上；共享 `_TermJsonCacheStore`，单学期写入走 `SafeJsonFile.updateJson` |
| `FileGradesCache` | `zf-grades-cache.json` | `{"updatedAt": ISO8601, "terms": {"<termId>": {"termId", "fetchedAt", "isNotEvaluated": bool, "items": [GradeItem]}}}` | 同上 |

### 3.4 学期选择与学校线路 (`term_selector_helper.dart`, `school.dart`)

- **`parseEnrollmentYear(studentId, {now})`**：合法区间 `[currentYear - 15, currentYear + 1]`；取首个连续数字串 `digits`（长 `<2` 或 `==3` 返 `null`）：① 8 位且 `19`/`20` 开头 -> 前 4 位；② 4 位 -> 直接取；③ 10 位本科号 -> 前 2 位 `y2 >= 80 ? 1900+y2 : 2000+y2`；④ 其他 `>=4` 位先试前 4 位再试前 2 位。
- **`filterTerms`**：① 无条件保留/补入 `currentTermId`；② 过滤 `termSemester > 2` (`xqm=16`)；③ 过滤 `< resolvedEnrollmentYear`；④ 过滤 `> maxYear/maxSemester`；⑤ 输入空且已知入学年时逆序生成 `[resolvedEnrollmentYear..maxYear]`。
- **`formatTermPrimaryLabel`**：`offset = termYear - resolvedEnrollmentYear`，`0..4` 映射 `大一..大五 + 上/下/第N学期`，否则 `'$termYear-${termYear+1} 第$semester学期'`。
- **`school.dart`**：`defaultSchool`/`qustProfile`/`qustLines`/`presetSchoolUrls` 仅保留外网可登默认线路 `https://jwglxt.qust.edu.cn/jwglxt`（`青岛科技大学`）；`defaultAcademicPaceHosts = {'jw.cqiivc.com': 1200}` 经 `ScheduleService.paceHosts` 注入协议包。`normalizeSchoolKeyUrl(baseUrl)` 剥首尾空白、转小写并去除末尾 `/`；`buildAccountKey(baseUrl, username)` 构造规范化凭据键；`sameSchool(a, b)` 基于 `normalizeSchoolKeyUrl()` 再剥 `^https?://` 比对。

---

## 4. 排布、校历、调课与工具库

### 4.1 作息表 (`lib/src/timetable.dart`)

- `PeriodGroup`：`morning('上午')` / `afternoon('下午')` / `evening('晚上')`；`defaultSectionCounts = {4, 4, 2}` (`defaultSectionCount = 10`)。
- 约束：`minLessonMinutes = 20`，`maxLessonMinutes = 180`，`maxShortBreakMinutes = 60`，`maxBigBreakMinutes = 120`，`maxTimetables = 20`，`maxSections = 20`。
- 内置 `defaultTimetables()`（均 45m 课 / 5m 小课间 / 上午第 2 节后与下午第 2 节后 20m 大课间）：
  - `'default'`（`'秋冬作息'`，10/1）：`08:30`(510) / `13:30`(810) / `18:00`(1080)
  - `'default-summer'`（`'春夏作息'`，5/1）：`08:30`(510) / `14:00`(840) / `18:30`(1110)
- `activeTimetableAt(tables, today)`：按 `month * 100 + day` 升序取 `<= todayKey` 末项，全大于时回绕取最大月日项（忽略年份）。
- `reconcileSections(sections, counts)`：节数全局生效，按 `PeriodGroup` 逐段裁尾或按「段末节时长 + 5m」补齐。

### 4.2 校历与冲突布局 (`lib/src/term_calendar.dart`)

- `estimateTermStart(term)`：第 1 学期 `mondayOf(year, 9, 1)`，第 2 学期 `mondayOf(year+1, 2, 23)`，第 3 学期 `mondayOf(year+1, 7, 1)`。
- `weekOf(termStart, date)`：`DateTime.utc` 防 DST 误差，早于 `mondayOf(termStart)` 返 `1`。
- `conflictLayout(entries)`：返 `Map<String, ({int index, int total})>`（键 `entry.id`），同天节次相交组按 `id` 字典序分配并列槽位。

### 4.3 按日调课 (`lib/src/reschedule.dart`)

- `RescheduleRule(id, fromMonth, fromDay, toMonth, toDay)` 仅作用于 `RescheduleWeekView`，不改持久化 `Schedule`。
- `_dateInTerm` 以 `termStart` 为锚定年份（早于锚点自动 `+1` 年），`toDate` 以 `fromDate` 为锚点。
- `rescheduleWeekView`：① 展开各 `ScheduleEntry` 周次（空周次展为 `1..maxWeek`）；② 命中 `_firstRuleFor` 则移出原周，目标周为当前周时生成调入实例入 `movedIn`，未命中入 `staying`；③ 同天节次重叠时 `movedIn` 优先，被顶原课入 `suppressed` 并记 `RescheduleConflict(displaced, winner)` 至 `conflicts[day]`；④ 同 `entry.id` 同天重叠保留先到项。

### 4.4 路由落稳与后台计算 (`lib/src/route_settled.dart`)

- `runInBackground<T>`：生产 (`WidgetsFlutterBinding`) 与纯 Dart 单测用 `Isolate.run`；Web (`kIsWeb`) 或 `flutter_test` (`is! WidgetsFlutterBinding`) 降级 `Future.microtask`。
- `RouteSettledStateMixin` / `RouteSettledGate` / `scheduleAfterRouteSettled`：条件 `!(route?.offstage ?? false) && (animation == null || animation.status == AnimationStatus.completed)`；粘性落稳（pop 不卸载，手势取消返回不提前作废）；`SchedulerPhase.persistentCallbacks` 下延至 `addPostFrameCallback`。

---

## 5. 持久化与安全存储

### 5.1 `Preferences` (`app_prefs.json`) Schema 15 全字段表 (`lib/src/preferences_repository.dart`)

`const int preferencesSchema = 15;`

| JSON 键 | 类型 | 默认值 | 范围 / 归一化 | 迁移与契约 |
| :--- | :--- | :--- | :--- | :--- |
| `schema` | `int` | `15` | 固定写出 `15` | Schema 15 覆写模型：忽略旧 `schools`/`currentSchool`，升级自动跟随 `defaultSchool.baseUrl` |
| `termStarts` | `Map<String,String>` | `{}` | `termId -> ISO8601` | 手动校准过的学期第 1 周周一 |
| `sectionCounts` | `Map<String,int>` | `{morning:4, afternoon:4, evening:2}` | `clampCounts`: 单段 `0..20`，总和 `1..20`（全 0 回退 4/4/2） | 兼容旧整数键 `sectionCount` 按 `splitCounts` 迁移 |
| `customSchools` | `List<String>` | `[]` | `_normalizeCustomSchools`: 过滤空串与 `presetSchoolUrls`，`sameSchool` 去重 | `Preferences.schools` 动态拼接 `[...presetSchoolUrls, ...customSchools]` |
| `customSchool` | `String` | `''` | `_normalizeCustomSchool`: 与 `defaultSchool.baseUrl` 同源归为 `''` | 空串时 `currentSchool` 返 `defaultSchool.baseUrl`；删当前自定义校或切回默认归 `''` |
| `lastAccounts` | `Map<String,String>` | `{}` | `baseUrl -> studentId`（`sameSchool` 匹配，`setIdentityOf` 移至末尾） | Schema 7：冷启动 `accountKey` 依据；`latestAccount` 供 `loginPrefillUsername`（`username`→`accountOf`→`latestAccount`）预填学号 |
| `lastStudentNames` | `Map<String,String>` | `{}` | `baseUrl -> studentName`（`sameSchool` 匹配） | Schema 13：冷启动免联网展示姓名 |
| `showTeacher` | `bool` | `true` | `bool` | 格子显示教师 |
| `showLocation` | `bool` | `true` | `bool` | 格子显示地点 |
| `cellHeight` | `double` | `60.0` (`defaultCellHeight`) | `clampCellHeight`: `50.0..120.0` (`minCellHeight..maxCellHeight`) | 单节行高（逻辑像素） |
| `courseTextScale` | `double` | `1.0` (`defaultCourseTextScale`) | `clampCourseTextScale`: `0.8..1.4` (`minCourseTextScale..maxCourseTextScale`) | 卡片字号倍率 |
| `autoRefresh` | `bool` | `true` | `bool` | Schema 5：冷启动/回前台数据静默同步（并行课表与学业） |
| `autoRefreshIntervalMinutes` | `int` | `180` (`defaultAutoRefreshIntervalMinutes`) | `clampAutoRefreshIntervalMinutes`: `60..1440` | Schema 5：数据静默同步最小间隔（分） |
| `reschedules` | `List<Map>` | `[]` | `RescheduleRule.fromJson` | Schema 5：按日调课规则 |
| `showScheduleRemarks` | `bool` | `true` | `bool` | Schema 6：底部实践/其他备注 |
| `reminderEnabled` | `bool` | `false` | `bool` | Schema 9：课前提醒开关（默认关） |
| `reminderLeadMinutes` | `int` | `10` (`defaultReminderLeadMinutes`) | `clampReminderLead`: `1..60` | Schema 9：提前提醒分钟 |
| `reminderStyle` | `String` | `'banner'` (`ReminderStyle.banner`) | `ReminderStyle.parse`: `'banner'`\|`'fluid'` | Schema 10：横幅 / 流体云 |
| `reminderFluidUntilEnd` | `bool` | `false` (`defaultReminderFluidUntilEnd`) | `bool` | Schema 11：流体云持续至下课 |
| `selectedUpdateProxy` | `String` | `'https://gh-proxy.org'` (`defaultUpdateProxyUrl`) | 兼容旧键 `updateProxyUrl`；`''` 为直连（真源归 `update_models.dart`，由 `preferences_repository.dart` 再导出） | Schema 12：当前更新代理 |
| `customUpdateProxies` | `List<String>` | `[]` | 过滤空串与 `presetUpdateProxies`（`update_models.dart`） | Schema 12：自定义代理（删当前选中回退默认） |
| `autoCheckUpdate` | `bool` | `true` (`defaultAutoCheckUpdate`) | `bool` | Schema 12：启动自动检查应用新版本 |
| `widgetConfig` | `Map<String,dynamic>` | `DesktopWidgetConfigSet.defaults()` | 按 `DesktopWidgetKind` (`today`/`week`/`next`) 存储 | Schema 14：桌面小组件样式（见 `WIDGET.md`） |
| `timetables` | `List<Map>` | `[defaultTimetable(), defaultSummerTimetable()]` | `_withBuiltinSummerTable` 自动补春夏表；上限 20，传空抛 `ArgumentError` | 作息时间表列表（至少 1 张） |
| `quickSetup` | `Map<String,dynamic>?` | `null`（未保存不写出） | `QuickSetup.fromJson` | 快捷作息参数记忆 |

### 5.2 `SafeJsonFile` (`lib/src/safe_json_file.dart`)

- `isolateJsonDecodeThreshold = 16 * 1024`（`>= 16KB` 走 `Isolate.run(() => jsonDecode(rawText))`）。
- **原子写入 (`_writeEncodedLocked`)**：① `keepBackup == true` 且主文件存在且 JSON 完好时，写 `${path}.bak.tmp` (`flush: true`) 原子改名 `.bak`（主文件已坏则跳过备份，保护旧 `.bak`）；② 写 `${path}.tmp` (`flush: true`) 原子改名主文件，`finally` 清临时文件。
- **读取自愈 (`_readLocked`)**：主文件缺失/解析失败/`isValid == false` 时尝试 `.bak`；`.bak` 完好则经 `.tmp` 覆写修复主文件并返 `SafeJsonReadResult(data, recoveredFromBackup: true)`；均坏返 `SafeJsonReadResult(data: null, hadUnrecoverableCorruption: true)`。

### 5.3 凭据与会话仓库 (`credentials_repository.dart`, `session_repository.dart`)

- **`SecureCredentialStore`**：`FlutterSecureStorage` v11（Android `EncryptedSharedPreferences + Tink + Keystore` / Windows `DPAPI`）。`credentialStoreKey(accountKey)` 派生 `'zf_pw_' + sha256(utf8(accountKey)).hex`（密码存该键，用户名存 `#u` 后缀）。解密异常 `get()` 捕获返 `null`。
- **`FileSessionRepository`**：委托 `FileCookieStorage('${supportDir.path}/zf-session.json')`，同具路径串行、写合并、`>=16KB` Isolate 解码、`.tmp` 原子替换，非 Windows 写入后 `chmod 600`。

---

## 6. 应用内更新与跨平台安装器

### 6.1 `UpdateFlowController` (`lib/src/updater/update_flow_controller.dart`) & `UpdaterGateway`

- **依赖注入与对外能力**：构造注入 `UpdaterGateway? gateway`（默认 `MethodChannelUpdaterGateway`）与 `@visibleForTesting bool Function()? isAndroid`，并向 `AppModel`/UI 暴露 `checkForUpdates`、`testProxy`、`cleanOldUpdateFiles`、`openExternalUrl`（页面层禁直建 `UpdateService()` 或 `MethodChannel`）。
- `UpdateFlowStage`：`idle` -> `available` -> `downloading` -> `readyToInstall` / `error`。
- 事件计数器：`backgroundReadyEvent` / `backgroundErrorEvent`（`!isDialogOpen` 后台终态时 `++`）；`requestCloseEvent`（`executeInstall()` 成功且 `isDialogOpen` 时 `++`）。
- 同版本保持：`setAvailableUpdate` 若 `release.version` + `targetAsset.name` 相同且处于 `downloading`/`readyToInstall`，保留进度/文件不重置。
- **竞态与权限防线**：`startDownload()` 在 `_isTriggeringInstall == true` 时直接拦截；`cancelDownload()` 重置 `_isTriggeringInstall = false` 并递增 `_downloadEpoch`；已有 `_downloadedFile` 直接 `readyToInstall`；下载前经 `_service.fetchExpectedSha256` 拉取 `SHA256SUMS`（需 `release != null && _allowAvailableFallback`）。**Android**：下载完查 `_gateway.canRequestPackageInstalls()`（异常按 `false` 处理）置 `_needsPermission`，弹窗打开且已授权立即 `executeInstall()`，未授权则切回前台经 `refreshInstallPermissionAndAutoInstall()` 续装；`executeInstall()` 的 `catch`/`finally` 严格校验 `epoch == _downloadEpoch && !_disposed` 后才写状态。**Windows**：进 `readyToInstall` 绝不自动退出，须用户点击触发 `executeInstall()`。

### 6.2 `UpdateService` (`lib/src/updater/update_service.dart`) & `update_models.dart`

- 常量：`repoOwner = 'fangzi2006'`，`repoName = 'QustSchedule'`；`probeTimeout = 5s`，`apiTimeout = 6s`，`downloadConnectTimeout = 15s`，`downloadIdleTimeout = 30s`；`maxConcurrentChunks = 3`，`minChunkingBytes = 4 * 1024 * 1024`；`browserUserAgent`（Chrome 130 + `QustSchedule/App` 防限流）。
- 预设代理真源（`update_models.dart` `kPresetUpdateProxyEntries` / `presetUpdateProxies`）：① `'https://gh-proxy.org'` (`主加速节点(默认推荐)`)；② `'https://axisnow.gh-proxy.org'` (`副加速节点`)；③ `'https://gh-proxy.com'` (`加速主站（最稳定但是部分网络环境下速度较慢）`)。`displayProxyName()` 按规范 HTTPS 根地址（无端口/无路径/无用户info）精确匹配 `matchHost`。`_buildCandidates` 构造 `[selectedProxy, ...其余 backupProxies, '']`（末项直连）。
- 产物匹配 (`findTargetAsset` & `isWindowsPortable`)：`isWindowsPortable()` 检查 `File(Platform.resolvedExecutable).parent` 下无 `unins000.exe` 为 `true`。Windows 便携：`windows-x64` `.zip` -> 任意 `.zip` -> `.exe`/`.zip`；Windows 安装：`setup` `.exe` -> 任意 `.exe` -> `.exe`/`.zip`；Android：`Abi.current()` (`arm64-v8a`/`armeabi-v7a`) 匹配 `archKey` `.apk` -> `arm64` `.apk` -> 任意 `.apk`。
- `downloadAssetWithFallback`：① 本地同名文件 `length == asset.size > 0` 且 SHA-256 通过直接复用；② Range `bytes=0-0` 探测：`206` 且 `totalBytes >= 4MB` 走 `_downloadMultiChunk`（3 切片 `.part0`~`.part2`，独立 30s 空闲看门狗与边界校验，350ms 测速 EMA `0.7*instant + 0.3*prev`，非取消失败同节点回退 `_downloadSingleUrl`，完后流式合并删片）；`200` 零额外握手直接将 `probeRes` 传 `_downloadSingleStream`；③ 落盘后若 `expectedSha256` 非空校验不通过删文件抛 `StateError`。
- `cleanOldUpdateFiles`：查更启动时异步清理 `QustSchedule_*.part*`、版本 `<= currentVersion` 旧包及 `AppInstaller.cleanLegacyUpdaterScriptAsync`（残余 `.cmd`/`.vbs`/`.update_staging`）。

### 6.3 `AppInstaller` & `AppUpdaterBridge.kt`

- **Android MethodChannel**：`"com.fangzi.qustschedule/updater"`（`AppInstaller.defaultChannel`，支持 `@visibleForTesting bool? isAndroid`，仅捕获 `MissingPluginException`/`PlatformException`）。
- **`AppUpdaterBridge.kt` 线程契约**：`installApk` 经 `UpdaterWorker`（`"qust-updater-worker"` 单线程池）异步校验 `File.exists()` 与 `FileProvider.getUriForFile`，`appContext` + `@Volatile disposed` + `postReply` 回主线程 `startActivity`（防 Flutter 3.29+ 主线程 I/O 阻塞与分离后空回调）。

| Method | 参数 | 返回 / 错误码 | 原生行为 (`AppUpdaterBridge.kt`) |
| :--- | :--- | :--- | :--- |
| `canRequestPackageInstalls` | 无 | `bool` | Android 8.0 (`O`) 及以上 `canRequestPackageInstalls()`；低版本 `true` |
| `openInstallSettings` | 无 | `true` / `OPEN_SETTINGS_FAILED` | `Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES` (`package:${context.packageName}`, `FLAG_ACTIVITY_NEW_TASK`) |
| `installApk` | `{"filePath": String}` | `true` / `INVALID_PATH`, `FILE_NOT_FOUND`, `INSTALL_FAILED` | Android 7.0 (`N`) 及以上 `FileProvider` (`${packageName}.fileprovider`) `content://` URI + `FLAG_GRANT_READ_URI_PERMISSION \| FLAG_ACTIVITY_NEW_TASK` |

- **Windows 自替换重启 (`app_installer.dart`)**：

| 维度 | 便携版 (`.zip` 热更新) | 安装版 (`setup.exe` 静默升级) |
| :--- | :--- | :--- |
| 前置准备 | ① `appDir` 创建/删 `.write_test_<ts>.tmp` 验写权限（无权限抛 `FileSystemException`）；② 清空建 `${appDir}\.update_staging`；③ `tar.exe -xf <zip> -C <.update_staging>`；④ 校验 `.update_staging\qustschedule.exe` 非空 | 在 `setupDir`（临时目录）生成脚本 |
| 脚本名 | `qustschedule_updater.cmd` + `qustschedule_launcher.vbs` (`appDir`) | `qustschedule_setup_updater.cmd` + `qustschedule_setup_launcher.vbs` (`tempDir`) |
| 隐窗启动 | `wscript.exe` `ProcessStartMode.detached` 跑纯 ASCII VBS `WScript.Shell.Run "cmd.exe /c ""...""", 0, False`（失败回退 `cmd.exe /c`），主进程立即 `exit(0)` | 同左 |
| PID 轮询 | `buildWindowsPidWaitBlock(pid)`：`tasklist /FI "PID eq <pid>" /FO CSV /NH \| find ",""<pid>"","` + `ping 127.0.0.1 -n 2 >nul`，最多 20 次（约 20s） | 同左 |
| 替换命令 | `robocopy ".update_staging" "." /E /IS /IT /NFL /NDL /NP /NJH /NJS /R:5 /W:1 >nul 2>nul`；`not errorlevel 8` 删 `.update_staging`；`start "" "qustschedule.exe"` 并自删 `.vbs`/`.cmd` | `start "" "<setupFileName>" /VERYSILENT /SUPPRESSMSGBOXES /NORESTART /CLOSEAPPLICATIONS /AUTOSTART=1` 并自删 `.vbs`/`.cmd` |

---

## 7. Windows 原生壳与安装包

- **单实例 (`windows/runner/main.cpp`)**：互斥量 `Local\com.fangzi.qustschedule.SingleInstance`；类名 `kWindowClassName = L"FLUTTER_RUNNER_WIN32_WINDOW"`，标题 `kAppWindowTitle = L"\u9752\u79D1\u8bfe\u8868\u901a"`（`\u` 转义防 MSVC CP936 C4819）。`AcquireSingleInstanceMutex` 遇 `ERROR_ALREADY_EXISTS` 循环最多 30 次 × 100ms：① `FindWindowW` 命中则 `ActivateExistingWindow` (`SW_RESTORE`/`SW_SHOW` + `SetForegroundWindow` + `BringWindowToTop`) 并 `EXIT_SUCCESS`；② 未找到则 `WaitForSingleObject(mutex, 100)`，获 `WAIT_OBJECT_0` 或 `WAIT_ABANDONED` 接管启动。
- **窗口与主题 (`win32_window.cpp`, `flutter_window.cpp`)**：初始 `(10, 10)` `1280×720`（按 `dpi / 96.0` 缩放）；`WM_GETMINMAXINFO` 最小尺寸 `360×520` 逻辑像素；`UpdateTheme` 读 `HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize\AppsUseLightTheme == 0` 启 `DWMWA_USE_IMMERSIVE_DARK_MODE (20)`；`SetNextFrameCallback` 内调用 `Show()` + `ForceRedraw()` 防白屏。
- **安装包 (`windows/packaging/setup.iss`)**：`AppId={{A7F3E2D1-6B4C-4E8A-9D52-1C3B5E7F9A24}`，`AppMutex=Local\com.fangzi.qustschedule.SingleInstance`，`MyAppExeName="qustschedule.exe"`（**严禁改名**，防 `path_provider`/DPAPI 路径变化丢数据）；`PrivilegesRequired=lowest`，默认 `{localappdata}\Programs\青科课表通`；`[Run]` `Check: ShouldAutoStart` 支持 `/AUTOSTART=1` 静默升级重启；`ssPostInstall` 经 `IsVCRedistInstalled` 查 `SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64\Installed` 缺失引导 `vc_redist.x64.exe`。

---

## 8. `packages/zf_academic` 协议层

### 8.1 双入口、最小导出与 `ZfEndpoints` (`types.dart`)

- `package:zf_academic/zf_academic.dart`：100% 纯 Dart（无 `dart:io`/Flutter），仅经 8 个 `show` 子句收窄导出 **43 项公开符号**（禁暴露 `Page` 及内部 HTML/RSA/HTTP 工具）；`example/secure_storage_flutter.dart` 对齐 `flutter_secure_storage` v11。
- `package:zf_academic/zf_academic_io.dart`：额外导出 `FileCookieStorage`、`DartIoTransport`、`vmZhengfangClient(ZfClientConfig, {DartIoTransport?})`。

| 字段 | 默认值 | `qustZfEndpoints` | 用途 |
| :--- | :--- | :--- | :--- |
| `loginPagePath` | `'/xtgl/login_slogin.html'` | 同默认 | 表单登录 GET/POST |
| `publicKeyPath` | `'/xtgl/login_getPublicKey.html'` | 同默认 | RSA 公钥 JSON (`modulus`, `exponent`) |
| `captchaPath` | `'/kaptcha'` | 同默认 | 验证码默认路径 |
| `studentInfoPath` | `'/xtgl/index_cxYhxxIndex.html'` | 同默认 | 学号/姓名 (`?gnmkdm=index`)，回退 `/xtgl/index_initMenu.html` |
| `schedulePath` | `'/kbcx/xskbcx_cxXsKb.html'` | **`'/kbcx/xskbcx_cxXskbcxIndex.html'`** | 课表页 HTML 与 Referer |
| `scheduleQueryPath` | `null`（回退 `schedulePath`） | **`'/kbcx/xskbcx_cxXsgrkb.html'`** | 课表 JSON POST |
| `scheduleGnmkdm` | `'N253508'` | **`'N2151'`** | 课表模块码 |
| `personal` | `false` | **`true`** | 为 `true` 时 POST 附加 `kzlx:'ck', xsdm:'', kclbdm:'', kclxdm:''` |
| `gradesPath` | `'/cjcx/cjcx_cxDgXscj.html'` | 同默认 | 成绩页/POST (`doType=query`) |
| `gradeGnmkdm` | `'N305005'` | 同默认 | 成绩模块码 |
| `examsPath` | `'/kwgl/kscx_cxXsksxxIndex.html'` | 同默认 | 考试页/POST (`doType=query`) |
| `examGnmkdm` | `'N358105'` | 同默认 | 考试模块码 |

### 8.2 `ZhengfangClient` (`zhengfang_client.dart`)

1. **生命周期与取消保护**：`close()` 幂等置 `_closed = true`、清空 `_username`/`_csrfTokenLogout`/`last*RawBody`/`last*Rows` 并调用 `_http.close()`；`dispose() => close()`；每个公开请求入口及关键 `await` 后调用 `assertActive()`，关闭后统一抛 `ErrorCode.cancelled`。
2. **表单登录 (`login` -> `_loginViaForm` -> `_submitFormLogin`)**：
   - 入口 `_cookies.invalidate()` 递增 `generation`；探测 `/sso/zfiotlogin` (`followRedirects: false`)，遇 CAS 跳抛 `ErrorCode.unsupported`。
   - GET 登录页提 `input[type=hidden]`（缺 `csrftoken` 先 `inspectResponse` 否则 `PAGE_CHANGED`）、`mmsfjm`（须唯一且为 `'0'`/`'1'` 否则 `PAGE_CHANGED`）、`csrfTokenLogout`。
   - `detectCaptcha` 扫 `RANDOMCODE`/`yzm`/`authcode`/`captcha`：命中存 `FormPendingLogin`（`_pendingTtlMs = 300000` 5m，绑 `generation`），拉图经 `sniffMimeType` 验 PNG/GIF/JPEG/BMP/WEBP 魔数返 `CaptchaState`。
   - `mmsfjm == '1'` 时每次针对新 `JSESSIONID` 实时 GET `publicKeyPath`（**禁跨登录缓存 RSA 公钥**），`zfFormEncryptPassword` 执行 `RSA/ECB/PKCS1Padding` + base64。
   - 先 POST `/xtgl/login_logoutAccount.html` (`csrfTokenLogout`，忽略异常)；POST `login_slogin.html?time=<ms>` 用 `postPairs` 发双同名 `('mm', mm)`（`#mm` + `#hidMm`）。
   - 仍为 `isLoginPage` 时 `_classifyLoginFailure` 区分 `invalidCredentials` / `captchaRequired`（`submitCaptcha` 错码自动 `refreshCaptcha()`）；成功调 `_readIdentity()` 返 `AuthenticatedState`。
3. **三态会话 (`checkSession()`)**：返 `SessionState(status, studentId, studentName)`：`authenticated`（读到身份或已登录词）/ `expired`（无 Cookie、`SESSION_EXPIRED` 或 `isLoginPage`）/ `unknown`（非 2xx 或无特征非登录页，**绝不当过期触发重登**）。
4. **课表路由发现 (`_discoverScheduleRoute`)**：遇 `"没有访问权限"`/`"无访问权限"` (`isPermissionDenied`) 查 `/xtgl/index_initMenu.html` 扫 `clickMenu('N...', '/kbcx/...', ...)` 提取 `gnmkdm`/路径重试；`fetchTerms()` 每次刷新 `lastTermsRawBody`。
5. **成绩查询 (`fetchGrades`)**：先 `listRowsOrEmpty(body, ['items','data','rows'])`，**`rows.isNotEmpty` 直接返回**；仅 `rows.isEmpty` 时查 `messageOf` 含 `'评价'`/`'评教'` 或正文含 `'教学质量评价'`/`'请先评教'` 抛 `ErrorCode.notEvaluated`；`listRows()`/`requireQueryPage()` 与 `changed(..., httpStatus)` 透传真实 HTTP 状态码。

### 8.3 `AcademicHttpClient` & `respond.dart`

- `DartIoTransport` 固定 `followRedirects = false`，客户端手动逐跳（`_defaultMaxRedirects = 12`），每跳 `_ensureAllowed` 校白名单并收 `Set-Cookie`。
- 站点降频表由 `ZfClientConfig.paceHosts` 注入，客户端经 `_paceHostKey()`/`_buildPaceHosts()` 归一化，内部不硬编码学校域名；`close()` 幂等置 `_closed = true` 并调用 `_assertActive()`（触发 `ErrorCode.cancelled`）。
- `_upgradeDowngrade`：同主机默认 80 端口 `http` 302 自动升级回 `https`（沿用原端口）。
- `_looksLikeAuthRedirect`：302 到白名单外 `cas.`/`sso.`/`auth.`/`idp.` 或含 `service=`/`ticket=` 直接转 `ErrorCode.sessionExpired`（不访问外域）。
- `_reclassifyUntrustedRedirect`：非白名单拦截跳发最多 2 跳无 Cookie 纯 GET 探测，重分类为 `accessForbidden` (403) 或 `serverError` (5xx)。
- 读请求 (`write == false`) 网络异常延迟 250ms 重试 1 次；写请求 (`write == true`) 禁重试，遇 3xx/5xx 抛 `resultUnknown`。响应体上限 `_defaultMaxBodyBytes = 5 * 1024 * 1024`（超限 `pageChanged`）。
- `inspectResponse` 优先级：① HTTP `>=500` -> `serverError`；② 标题/正文含服务端崩溃维护词（`访问出错` 且不含 `403`、`bad gateway`、`whitelabel error page`、`系统维护`、`数据库连接异常`）-> `serverError`（**优先于 403**）；③ 防火墙词（`访问出错-403`、`访问策略禁止`、`仅限校园网`、含 `403`+`禁止访问`/`访问策略`）-> `accessForbidden`；④ 其余 `ok`。

### 8.4 解析器与确定性 ID (`schedule.dart`, `academic_query.dart`, `urls.dart`, `util.dart`)

- `zfSemesterCodes = {1: '3', 2: '12', 3: '16'}`；`calendarTerm`（本地月）：`month >= 8` 当年第 1 学期，`month == 1` 上年第 1 学期，`2..7` 上年第 2 学期。
- `periods(value)`：剥非数字，解析 `1..30` 合并连续 `(startPeriod, endPeriod)`；`tryParseWeeks(value)`：归一化全角/连接符/`(周)`/`(全)`，支持单双周（`1..60`，单段跨度 `<=53`），失败返 `[]` 并记 `details` (`id: 'rawWeeks', label: '周次说明'`)。
- `rowKey([courseKey, name, '$day', '$startPeriod', '$endPeriod', rawWeeks])`：32 位 FNV-1a（初值 `2166136261`，乘数 `16777619`，`\u0000` 分隔）16 进制前缀 + `:` + 非空字段 `|` 串（截断至 `<=96` 字符）。
- `parseExamTime`：支持 `YYYY-MM-DD HH:mm-HH:mm`、括号/`~`/`至`/中文年月日/单点/纯日期；`ExamItem.effectiveEndTime`：有 `endTime` 直返，仅有 `startTime` 含 `HH:mm` 按 `+2h`，纯日期按当日 `23:59:59.999`。

### 8.5 `ErrorCode` 全量枚举 (`packages/zf_academic/lib/src/errors.dart`)

| 枚举 (`ErrorCode.*`) | `wire` | 触发场景 |
| :--- | :--- | :--- |
| `unsupported` | `'UNSUPPORTED'` | CAS 统一认证，或路由发现后仍无权限 |
| `notOpen` | `'NOT_OPEN'` | 未开放 / 未开始 / 已结束（考试查到静默） |
| `invalidCredentials` | `'INVALID_CREDENTIALS'` | 账密错误 |
| `sessionExpired` | `'SESSION_EXPIRED'` | Cookie 失效、登录页、401、302 到外部 CAS（**唯一触发自动重登**；403 不归此码） |
| `captchaRequired` | `'CAPTCHA_REQUIRED'` | 需验证码、空码、错码或重登取消验证码 |
| `webLoginRequired` | `'WEB_LOGIN_REQUIRED'` | 验证码控件残缺或需网页人工验证 |
| `noCapacity` | `'NO_CAPACITY'` | 选课容量满 |
| `conflict` | `'CONFLICT'` | 选课时间冲突 |
| `alreadySelected` | `'ALREADY_SELECTED'` | 重复选课 |
| `creditLimit` | `'CREDIT_LIMIT'` | 超学分上限 |
| `pageChanged` | `'PAGE_CHANGED'` | 缺 `csrftoken`、非法 `mmsfjm`/RSA 公钥、验证码非图、体 `>5MB`、重定向无 `Location`/>12 跳、JSON 结构异常 |
| `networkRetryable` | `'NETWORK_RETRYABLE'` | 套接字/DNS 失败、读重试仍断、`asAcademicError` 兜底 |
| `serverError` | `'SERVER_ERROR'` | 读 429/5xx，或 `inspectResponse` 判正方 500/502/维护页 |
| `accessForbidden` | `'ACCESS_FORBIDDEN'` | HTTP 403，或 `inspectResponse`/探测判防火墙 403 拦截 |
| `resultUnknown` | `'RESULT_UNKNOWN'` | 写请求 (`write: true`) 断网、3xx 或 5xx |
| `untrustedUrl` | `'UNTRUSTED_URL'` | 目标不在 `allowedHosts`、端口不匹配或非同主机 80 端口降级 HTTP |
| `validationFailed` | `'VALIDATION_FAILED'` | URL 无主机、Cookie `version != 1`、登录后无身份、改密未知账号 |
| `timeout` | `'TIMEOUT'` | 单次请求超 `requestTimeoutMs` (10000ms) |
| `cancelled` | `'CANCELLED'` | 调用已 `close()`/`dispose()` 的 `ZhengfangClient` |
| `resourceLimit` | `'RESOURCE_LIMIT'` | 资源超限预留 |
| `staleContext` | `'STALE_CONTEXT'` | 验证码挂起超 5m (`_pendingTtlMs`) 或 `generation` 递增 |
| `notEvaluated` | `'NOT_EVALUATED'` | 成绩空列表且提示教学质量评价/请先评教 |
| `success` | `'SUCCESS'` | JSON 显式 `success: true` / `flag: '1'` / `code: '0'` |
