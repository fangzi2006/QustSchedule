# 全量精确文件地图与导出符号索引 (`docs/dev/FILE_MAP.md`)

> **维护契约**：所有路径均以本仓库根目录（`qustschedule/`）为基准。新增、删除或重命名任意源码/测试文件时，必须同步更新本表。

---

## 一、Flutter 主工程 (`lib/`)

### 1.1 入口与主题 (`lib/main.dart`, `lib/theme/`)

| 文件路径 | 核心导出类 / 函数 | 职责与架构契约 |
|---|---|---|
| [`lib/main.dart`](../../lib/main.dart) | `main()`, `CourseApp`, `_AppShell`, `pageForStatus()` | 应用根入口；并行异步读取 `loadAppVersion()`；在 `boot()` 前初始化并挂载 `ReminderService` 与 `DesktopWidgetService`（仅 Android）；仅监听 `model.routeNotifier` 与 `model.hints`；`AppLifecycleListener(onShow)` 调 `model.onAppShown()`，并带 60s 同日冷却 + 600ms 延迟兜底同步提醒与小组件 |
| [`lib/theme/app_theme.dart`](../../lib/theme/app_theme.dart) | `AppRadius`, `AppColors`, `buildLightTheme()`, `AppScrollBehavior` | Material 3 浅色主题；`AppRadius` 5 级圆角（`20`/`14`/`8`/`6`/`999`）；`AppColors` 25 个语义色令牌；全宽水平滑动转场 `_SmoothSlidePageTransition`（正向 260ms / 反向 240ms，双向连续缓动，内置 `RepaintBoundary` + `AppMenuScope`） |
| [`lib/theme/course_palette.dart`](../../lib/theme/course_palette.dart) | `CourseColor`, `CoursePalette` | 9 组课程浅色/深色配对色板；`CoursePalette.indexOf(courseName)` 使用 FNV-1a 32 位哈希，与 Android 原生 `WidgetThemeResolver.kt` 严格同构 |

### 1.2 状态门面与五大专职控制器 (`lib/src/app_model.dart`, `lib/src/state/`)

| 文件路径 | 核心导出类 | 职责与专属通知源 |
|---|---|---|
| [`lib/src/app_model.dart`](../../lib/src/app_model.dart) | `AppModel`, `AppStatus` | 全局门面与协调器：串联 5 大控制器、认证代数 `_authEpoch`、冷启动 `boot()`、登录/切校/登出、前后台 `onAppShown()` 与改密账号解析 |
| [`lib/src/state/auth_session_controller.dart`](../../lib/src/state/auth_session_controller.dart) | `AuthSessionController` | 管理 `ScheduleService`、教务线路 `schoolBaseUrl`、学生身份快照、重登验证码挂起 `Completer` 与脱敏调试日志 |
| [`lib/src/state/schedule_controller.dart`](../../lib/src/state/schedule_controller.dart) | `ScheduleController`, `WeekNotifier` | 管理 `Schedule`、学期 `Terms`、当前周/最大周（默认 18 周保底）、校历起点 `termStart`、按周记忆化调课视图与冲突布局缓存；提供 `weekNotifier` 与 `refreshingNotifier` |
| [`lib/src/state/academic_controller.dart`](../../lib/src/state/academic_controller.dart) | `AcademicController` | 独立 `ChangeNotifier`（`academicNotifier`）：考试、成绩、记忆化 `gradeStats`、未评教标志、`academicTermId`/`loadedAcademicTerm`、`_academicLoadSeq` 与静默同步差量提醒 |
| [`lib/src/state/preferences_controller.dart`](../../lib/src/state/preferences_controller.dart) | `PreferencesController` | 管理 `Preferences` 读写、外观滑块 300ms 防抖草稿、`preferencesLoaded` 门控、存储故障通知与自动更新延时检测器；提供 `prefsNotifier` |
| [`lib/src/state/hint_notice_controller.dart`](../../lib/src/state/hint_notice_controller.dart) | `HintNoticeController`, `HintScope` | 独立 `ChangeNotifier`（`hints`）：`HintScope`（`global`/`schedule`/`academic`）气泡与自动消隐 Timer、存储告警计数与 `humanizeError` |

### 1.3 核心服务、领域模型、持久化与原生桥接 (`lib/src/`)

| 文件路径 | 核心导出类 / 函数 | 职责与架构契约 |
|---|---|---|
| [`lib/src/schedule_service.dart`](../../lib/src/schedule_service.dart) | `ScheduleService`, `ScheduleStageCallback` | 课表/学期抓取与会话生命周期；10s 超时；单飞重登互斥锁 `_reloginFlight`；10 分钟 2 次自动重登熔断；`_accountKey` 非空串回退链 |
| [`lib/src/schedule_cache.dart`](../../lib/src/schedule_cache.dart) | `ScheduleCache`, `FileScheduleCache`, `InMemoryScheduleCache`, `LateScheduleCache`, `CachedSchedule` | 课表离线缓存（`zf-schedule-cache.json`，基于 `SafeJsonFile`） |
| [`lib/src/academic_service.dart`](../../lib/src/academic_service.dart) | `AcademicService`, `GradeStats` | 考试与成绩抓取、未评教保留历史成绩标志写入、后台静默同步与加权 GPA 计算 |
| [`lib/src/academic_cache.dart`](../../lib/src/academic_cache.dart) | `ExamCache`, `GradesCache`, `File*Cache`, `CachedTerm*`, `InMemory*`, `Late*` | 按 `termId` 分桶的考试与成绩缓存（`zf-exam-cache.json` / `zf-grades-cache.json`） |
| [`lib/src/term_selector_helper.dart`](../../lib/src/term_selector_helper.dart) | `parseEnrollmentYear()`, `estimateCurrentAcademicYear()`, `filterTerms()`, `resolveSemesterCode()`, `formatTermPrimaryLabel()` | 10 位学号入学年推导（`2000 + YY`）、大一至大五两学期制过滤与年级标签格式化 |
| [`lib/src/backends.dart`](../../lib/src/backends.dart) | `ScheduleBackend`, `ZfBackend`, `defaultBackendFactory` | 教务客户端窄门面抽象与正方直连实现（供测试替身注入） |
| [`lib/src/school.dart`](../../lib/src/school.dart) | `SchoolProfile`, `qustProfile`, `qustLines`, `presetSchoolUrls`, `defaultSchool`, `schoolLabel()`, `sameSchool()` | 青科大默认教务线路定义、URL 规范化与同源比对 |
| [`lib/src/timetable.dart`](../../lib/src/timetable.dart) | `PeriodGroup`, `SectionTime`, `BigBreak`, `Timetable`, `QuickSetup`, `buildSections()`, `activeTimetableAt()`, `reconcileSections()` | 多套作息时间表模型、按 `month*100+day` 跨年循环切换与三段节次推导 |
| [`lib/src/term_calendar.dart`](../../lib/src/term_calendar.dart) | `dayOnly()`, `mondayOf()`, `weekOf()`, `dateOf()`, `termStartFromWeek()`, `estimateTermStart()`, `formatExamTimeLabel()`, `conflictLayout()` | 校历换算（全用 `DateTime.utc` 整日差消除夏令时偏差）、考试周次标签与同天冲突并列槽位 |
| [`lib/src/reschedule.dart`](../../lib/src/reschedule.dart) | `RescheduleRule`, `RescheduleConflict`, `RescheduleWeekView`, `rescheduleWeekView()` | 按日期平移单日课程的本地调课引擎 |
| [`lib/src/course_text.dart`](../../lib/src/course_text.dart) | `roomOnly()` | 课表格子与课程提醒共用的地点短名清洗 |
| [`lib/src/formatted_text_span.dart`](../../lib/src/formatted_text_span.dart) | `FormattedSegmentKind`, `FormattedSegment`, `parseFormattedSegments()`, `buildTextSpanFromSegments()`, `buildFormattedTextSpan()` | 更新日志 Markdown 轻量行内富文本解析（支持后台 Isolate 预解析） |
| [`lib/src/route_settled.dart`](../../lib/src/route_settled.dart) | `runInBackground()`, `scheduleAfterRouteSettled()`, `RouteSettledHandle`, `RouteSettledStateMixin`, `RouteSettledGate` | 二级页 260ms 入场转场与后台加载并行协调器 |
| [`lib/src/background_isolate_io.dart`](../../lib/src/background_isolate_io.dart) | `runIsolateComputation()` | VM 平台 `Isolate.run` 实现 |
| [`lib/src/background_isolate_stub.dart`](../../lib/src/background_isolate_stub.dart) | `runIsolateComputation()` | 非 `dart:isolate` 环境的 `Future.microtask` 降级桩 |
| [`lib/src/safe_json_file.dart`](../../lib/src/safe_json_file.dart) | `SafeJsonFile`, `SafeJsonReadResult`, `isolateJsonDecodeThreshold` (16KB) | 路径级串行异步锁 + 待写合并 + `.tmp` 原子替换 + `.bak` 自愈 + `>= 16KB` 后台 Isolate 解码 |
| [`lib/src/preferences_repository.dart`](../../lib/src/preferences_repository.dart) | `Preferences`, `preferencesSchema` (15), `presetUpdateProxies` | 用户偏好持久化（`app_prefs.json`，Schema 15），支持平滑迁移与损坏自愈 |
| [`lib/src/credentials_repository.dart`](../../lib/src/credentials_repository.dart) | `SecureCredentialStore` | `CredentialStore` 的 `flutter_secure_storage` 实现（Android Keystore / Windows DPAPI） |
| [`lib/src/session_repository.dart`](../../lib/src/session_repository.dart) | `SessionRepository`, `FileSessionRepository`, `InMemorySessionRepository`, `LateSessionRepository` | 教务 Cookie 会话快照持久化（`zf-session.json`） |
| [`lib/src/app_version.dart`](../../lib/src/app_version.dart) | `appVersion`, `appVersionFull`, `loadAppVersion()`, `parsePubspecVersion()` | 从打包资产 `pubspec.yaml` 动态解析版本号 |
| [`lib/src/reminder_planner.dart`](../../lib/src/reminder_planner.dart) | `ReminderStyle`, `CourseReminderEvent`, `ReminderPlan`, `planCourseReminders()`, `reminderFingerprint()`, `defaultReminderLeadMinutes` (10) | 未来 14 天课前提醒规划纯函数与 FNV-1a 指纹 |
| [`lib/src/reminder_gateway.dart`](../../lib/src/reminder_gateway.dart) | `ReminderGateway`, `MethodChannelReminderGateway`, `ReminderSyncResult`, `ReminderRuntimeStatus` | `MethodChannel('qustschedule/reminder')` 通信网关 |
| [`lib/src/reminder_service.dart`](../../lib/src/reminder_service.dart) | `ReminderService` | 监听 `AppModel`，300ms 防抖 + 单飞队列同步原生提醒 |
| [`lib/src/widget_style.dart`](../../lib/src/widget_style.dart) | `DesktopWidgetKind`, `WidgetThemeMode`, `WidgetDensity`, `FinishedCourseMode`, `WeekendColumnMode`, `WidgetStylePreset`, `DesktopWidgetStyle`, `DesktopWidgetConfigSet` | 三类桌面小组件独立样式模型、5 套精选预设与 JSON 容错序列化 |
| [`lib/src/widget_planner.dart`](../../lib/src/widget_planner.dart) | `WidgetTimelineItem`, `WidgetDayPlan`, `WidgetUpcomingExam`, `WidgetWeekBlock`, `WidgetWeekPlan`, `WidgetSnapshot`, `buildWidgetSnapshot()`, `buildSignedOutWidgetSnapshot()` | 未来 14 天日程+考试混排、30 天未结束考试、2~3 周网格快照与 FNV-1a 指纹 |
| [`lib/src/widget_gateway.dart`](../../lib/src/widget_gateway.dart) | `DesktopWidgetGateway`, `MethodChannelDesktopWidgetGateway` | `MethodChannel('qustschedule/widget')` 通信网关与已添加实例计数监听 |
| [`lib/src/widget_service.dart`](../../lib/src/widget_service.dart) | `WidgetSnapshotInput`, `DesktopWidgetService` | 监听课表/学业/偏好，300ms 防抖 + 单飞队列同步原生小组件 |

### 1.4 自动更新子系统 (`lib/src/updater/`)

| 文件路径 | 核心导出类 / 函数 | 职责与架构契约 |
|---|---|---|
| [`lib/src/updater/update_flow_controller.dart`](../../lib/src/updater/update_flow_controller.dart) | `UpdateFlowController`, `UpdateFlowStage` | 单弹窗更新状态机，支持后台下载胶囊与当次会话静音 |
| [`lib/src/updater/update_service.dart`](../../lib/src/updater/update_service.dart) | `UpdateService`, `CancelToken` | GitHub Releases 检查、代理轮询测速、`>=4MB` 3 线程 Range 分块下载与 SHA-256 校验 |
| [`lib/src/updater/update_models.dart`](../../lib/src/updater/update_models.dart) | `UpdateStatus`, `ReleaseInfo`, `ReleaseAsset`, `DownloadProgress`, `ProxyTestResult`, `UpdateCheckResult`, `displayProxyName()` | 更新检查、资产匹配与代理延迟模型 |
| [`lib/src/updater/app_installer.dart`](../../lib/src/updater/app_installer.dart) | `AppInstaller` | Android APK 安装桥接；Windows 安装版静默升级与便携版 `.update_staging` + VBS + `robocopy /mir` 无黑框热替换 |
| [`lib/src/updater/version_comparator.dart`](../../lib/src/updater/version_comparator.dart) | `compareSemanticVersions()`, `isVersionNewer()` | 语义化版本与预发布标签比较器 |

### 1.5 页面层 (`lib/pages/`，共 18 页)

| 文件路径 | 核心组件类 / 函数 | 职责与订阅边界 |
|---|---|---|
| [`lib/pages/home_shell.dart`](../../lib/pages/home_shell.dart) | `HomeShell` | 课表/学业/设置三页常驻横向轨道外壳，`FloatingDock` 单运动源驱动，内置页级 `AppMenuScope` |
| [`lib/pages/schedule_page.dart`](../../lib/pages/schedule_page.dart) | `SchedulePage` | 周视图课表主页、顶栏菜单、`WeekPager` 与右下角「今」悬浮按钮 |
| [`lib/pages/academic_page.dart`](../../lib/pages/academic_page.dart) | `AcademicPage` | 学业概览页（`CustomScrollView` + `SliverList.builder` 零阴影分段白卡、考试倒计时、学期 GPA 与成绩列表） |
| [`lib/pages/appearance_sheet.dart`](../../lib/pages/appearance_sheet.dart) | `showAppearanceSheet()` | 课表外观底部调节抽屉（格子高度、字号缩放、教师/地点/备注开关） |
| [`lib/pages/reschedule_page.dart`](../../lib/pages/reschedule_page.dart) | `ReschedulePage` | 按日期调课管理页 |
| [`lib/pages/settings_page.dart`](../../lib/pages/settings_page.dart) | `SettingsPage` | 设置页：账号线路、课表作息、「提醒与小组件」统一板块（含忽略电池优化/精确闹钟/自启动三项系统权限）、关于与更新 |
| [`lib/pages/timetable_list_page.dart`](../../lib/pages/timetable_list_page.dart) | `TimetableListPage` | 多套作息时间表管理与快捷生成 |
| [`lib/pages/timetable_edit_page.dart`](../../lib/pages/timetable_edit_page.dart) | `TimetableEditPage` | 单张作息表草稿编辑页 |
| [`lib/pages/school_address_page.dart`](../../lib/pages/school_address_page.dart) | `SchoolAddressPage` | 默认教务线路与自定义地址切换/管理页 |
| [`lib/pages/login_page.dart`](../../lib/pages/login_page.dart) | `LoginPage` | 教务直连登录页（支持展开高级选项切换教务线路） |
| [`lib/pages/captcha_page.dart`](../../lib/pages/captcha_page.dart) | `CaptchaPage` | 验证码输入页（固定浅色画布保证深色验证码可读） |
| [`lib/pages/reminder_page.dart`](../../lib/pages/reminder_page.dart) | `ReminderPage` | Android 课程提醒子页面（`RouteSettledStateMixin`、横幅/流体云模式、提前量滑块、测试与诊断卡片） |
| [`lib/pages/widget_settings_page.dart`](../../lib/pages/widget_settings_page.dart) | `WidgetSettingsPage`, `computeWidgetSettingsSnapshots()` | Android 桌面小组件设置页（后台 Isolate 首屏预计算、同构预览、滑块草稿、60s 回前台防重算冷却与一键固定） |
| [`lib/pages/debug_page.dart`](../../lib/pages/debug_page.dart) | `DebugPage` | 脱敏调试信息页（仅 Cookie 键名、HTTP 状态与课表原始行，单层 `SelectionArea`） |
| [`lib/pages/about_page.dart`](../../lib/pages/about_page.dart) | `AboutPage`, `LicenseTextPage` | 关于页与 GPL-3.0 开源协议全文页 |
| [`lib/pages/changelog_page.dart`](../../lib/pages/changelog_page.dart) | `ChangelogPage` | 更新日志页（后台 Isolate 解析 `CHANGELOG.md`） |
| [`lib/pages/update_dialog.dart`](../../lib/pages/update_dialog.dart) | `UpdateDialog`, `showUpdateDialog()` | 单弹窗全流程更新对话框 |
| [`lib/pages/update_proxy_page.dart`](../../lib/pages/update_proxy_page.dart) | `UpdateProxyPage` | GitHub 加速代理选择、自定义代理与并发测速页 |

### 1.6 通用物理动效与 UI 组件层 (`lib/widgets/`，共 15 个)

| 文件路径 | 核心导出类 / 函数 | 职责与核心不变量 |
|---|---|---|
| [`lib/widgets/floating_dock.dart`](../../lib/widgets/floating_dock.dart) | `FloatingDock`, `FloatingDockState`, `FloatingDockItem` | 液态透镜底部悬浮导航栏：三页轨道唯一运动源、可打断拖拽、按下懒建 |
| [`lib/widgets/tactile_button.dart`](../../lib/widgets/tactile_button.dart) | `TactileAppBar`, `TactileSurfaceScope`, `TactileSurfaceButton`, `TactileIconButton`, `TactileBackButton`, `TactileActionButton` | 按压放大触感反馈体系与四层合绘顶栏 |
| [`lib/widgets/app_menu.dart`](../../lib/widgets/app_menu.dart) | `AppMenuScope`, `AppMenuScopeController`, `AppMenuItem`, `showAppMenu()`, `RenderMenuMorphBox` | 双轴弹性原地展开菜单与页面级空间作用域 |
| [`lib/widgets/app_bottom_sheet.dart`](../../lib/widgets/app_bottom_sheet.dart) | `showAppModalBottomSheet()`, `ScrollableBottomSheetFrame` | 统一圆角底部弹窗容器与可滚动抽屉骨架 |
| [`lib/widgets/app_snack_bar.dart`](../../lib/widgets/app_snack_bar.dart) | `AppSnackBarType`, `buildAppSnackBar()`, `showAppSnackBar()` | 浅色悬浮胶囊提示条（自动避让底部 Dock） |
| [`lib/widgets/course_tile.dart`](../../lib/widgets/course_tile.dart) | `CourseBlock`, `CourseBlockLayoutSnapshot` | 课表网格课程卡片（`TextPainter` 四步预算求解器 + 512 LRU 缓存 + 空闲字形预热） |
| [`lib/widgets/course_detail_sheet.dart`](../../lib/widgets/course_detail_sheet.dart) | `showEntryDetails()`, `compressWeeks()` | 课程详情底部抽屉（单层 `SelectionArea`） |
| [`lib/widgets/week_pager.dart`](../../lib/widgets/week_pager.dart) | `WeekPager`, `WeekPagerController` | 周视图水平翻页器（跨 4+ 周 180ms 跳页 + 邻近周预热） |
| [`lib/widgets/desktop_widget_preview.dart`](../../lib/widgets/desktop_widget_preview.dart) | `DesktopWidgetPreview`, `PreviewWallpaper`, `buildSampleWidgetSnapshot()` | 与 Android 原生像素级同构的纯 Flutter 桌面小组件实时预览 |
| [`lib/widgets/page_skeleton.dart`](../../lib/widgets/page_skeleton.dart) | `CardListTransitionPlaceholder`, `DocumentTransitionPlaceholder`, `PreviewSettingsTransitionPlaceholder` | 260ms 路由入场零 Ticker 静态骨架屏占位 |
| [`lib/widgets/reminder_permission_tile.dart`](../../lib/widgets/reminder_permission_tile.dart) | `ReminderPermissionTile`, `showReminderGuideToast()` | 后台与提醒权限条目及跨应用跳设置指路 Toast |
| [`lib/widgets/section_title.dart`](../../lib/widgets/section_title.dart) | `SectionTitle` | 设置页与二级页分组小标题 |
| [`lib/widgets/status_popup.dart`](../../lib/widgets/status_popup.dart) | `StatusPopup` | 顶栏右侧状态/错误浮动气泡弹窗 |
| [`lib/widgets/time_wheel_picker.dart`](../../lib/widgets/time_wheel_picker.dart) | `showTimeWheel()`, `showTimeRangeWheel()`, `showWeekCalibrationWheel()` 等 | 作息时间、节数与周次底部滚轮选择器 |
| [`lib/widgets/changelog_category_badge.dart`](../../lib/widgets/changelog_category_badge.dart) | `ChangelogCategoryBadge` | 更新日志分类着色徽章 |

---

## 二、正方教务协议子包 (`packages/zf_academic/`，纯 Dart)

| 文件路径 | 核心导出类 / 函数 | 职责说明 |
|---|---|---|
| [`packages/zf_academic/lib/zf_academic.dart`](../../packages/zf_academic/lib/zf_academic.dart) | 纯 Dart 统一导出入口 | 导出全部模型、客户端、解析器、加密与 Cookie 工具 |
| [`packages/zf_academic/lib/zf_academic_io.dart`](../../packages/zf_academic/lib/zf_academic_io.dart) | `DartIoTransport`, `FileCookieStorage` | 基于 `dart:io` 的默认 HTTP 传输层与文件 Cookie 存储 |
| [`packages/zf_academic/lib/src/zhengfang_client.dart`](../../packages/zf_academic/lib/src/zhengfang_client.dart) | `ZhengfangClient`, `SessionInfo` | 正方教务核心状态机：探测登录页、RSA 表单/CAS 登录、验证码、会话检查与课表/考试/成绩请求 |
| [`packages/zf_academic/lib/src/http_client.dart`](../../packages/zf_academic/lib/src/http_client.dart) | `AcademicHttpClient`, `HttpRequestOptions`, `HttpResponse` | 自动 Cookie 管理、HTTP→HTTPS 升级、跨主机安全审计与脱敏请求日志 |
| [`packages/zf_academic/lib/src/dart_io_transport.dart`](../../packages/zf_academic/lib/src/dart_io_transport.dart) | `DartIoTransport` | `dart:io` `HttpClient` 底层传输实现（禁用自动重定向） |
| [`packages/zf_academic/lib/src/cookies.dart`](../../packages/zf_academic/lib/src/cookies.dart) | `CookieStore`, `CookieRecord`, `CookieStoreSnapshot`, `parseSetCookie()` | RFC 6265 Cookie 解析、Domain/Path 隔离匹配与快照导入导出 |
| [`packages/zf_academic/lib/src/cookie_storage.dart`](../../packages/zf_academic/lib/src/cookie_storage.dart) | `CookieStorage`, `FileCookieStorage`, `InMemoryCookieStorage` | Cookie 快照持久化接口与默认实现 |
| [`packages/zf_academic/lib/src/credential_store.dart`](../../packages/zf_academic/lib/src/credential_store.dart) | `CredentialStore`, `Credentials`, `InMemoryCredentialStore`, `credentialStoreKey()` | 账号密码安全存储抽象接口 |
| [`packages/zf_academic/lib/src/crypto.dart`](../../packages/zf_academic/lib/src/crypto.dart) | `zfFormEncryptPassword()`, `zfCasEncryptPassword()`, `rsaEncryptPkcs1()` | 正方 RSA PKCS#1 v1.5 密码加密 |
| [`packages/zf_academic/lib/src/schedule.dart`](../../packages/zf_academic/lib/src/schedule.dart) | `jsonSchedule()`, `termsFromHtml()`, `tryParseWeeks()`, `maxWeeksOf()`, `defaultMaxWeeks` (18) | 课表 JSON 解析、周次字符串解析、最大周计算与两学期制过滤 |
| [`packages/zf_academic/lib/src/academic_query.dart`](../../packages/zf_academic/lib/src/academic_query.dart) | `jsonExams()`, `jsonGrades()`, `parseExamTime()` | 考试与成绩 JSON 解析、起止时间提取与考查课等级归一 |
| [`packages/zf_academic/lib/src/html.dart`](../../packages/zf_academic/lib/src/html.dart) | `loginForm()`, `detectCaptcha()`, `identity()`, `selectOptions()` | 零第三方 DOM 依赖 HTML 表单/验证码/身份提取器 |
| [`packages/zf_academic/lib/src/respond.dart`](../../packages/zf_academic/lib/src/respond.dart) | `inspectResponse()`, `ResponseDiagnosis`, `ResponseKind` | HTTP 响应分类诊断（5xx/403/会话过期/未评教/正常 JSON） |
| [`packages/zf_academic/lib/src/urls.dart`](../../packages/zf_academic/lib/src/urls.dart) | `parseAcademicAddress()`, `normalizeEndpoints()`, `isAllowedUrl()`, `zfTermParams()` | 教务地址规范化、同源白名单与 `xnm`/`xqm` 映射 |
| [`packages/zf_academic/lib/src/errors.dart`](../../packages/zf_academic/lib/src/errors.dart) | `AcademicError`, `ErrorCode`, `asAcademicError()` | 标准教务 23 项错误码枚举 |
| [`packages/zf_academic/lib/src/types.dart`](../../packages/zf_academic/lib/src/types.dart) | `Schedule`, `ScheduleEntry`, `Term`, `Terms`, `ExamItem`, `GradeItem`, `CaptchaState`, `RequestLog`, `qustZfEndpoints` | 协议层核心不可变数据结构与青科大 `N2151` 端点预设 |
| [`packages/zf_academic/lib/src/util.dart`](../../packages/zf_academic/lib/src/util.dart) | `str()`, `number()`, `field()`, `firstOf()`, `rowKey()` | JSON 安全提取与 FNV-1a 课程去重签名 |

---

## 三、Android 原生工程 (`android/app/src/main/kotlin/com/fangzi/qustschedule/`)

| 模块 | 包含文件（共 30 个 Kotlin 源码） | 核心职责与专题链接 |
|---|---|---|
| **入口与更新桥接** | `MainActivity.kt`, `updater/AppUpdaterBridge.kt` | 注册 3 条 MethodChannel；`MainActivity` 采用 `RenderMode.texture` 消除小组件进出场黑闪；FileProvider APK 安装桥接 |
| **课前提醒与流体云 (`reminder/`, 13 个)** | `ReminderWorker.kt`, `ReminderBridge.kt`, `ReminderPayload.kt`, `ReminderStore.kt`, `ReminderScheduler.kt`, `ReminderReceiver.kt`, `ReminderDailyResyncReceiver.kt`, `ReminderRestoreReceiver.kt`, `ReminderNotifier.kt`, `ReminderFluidRenderer.kt`, `ReminderFluidService.kt`, `ReminderSamples.kt`, `ReminderPermissions.kt` | 后台单线程执行器、14 天落盘 + 10 天滚动闹钟窗、横幅/流体云 ID 隔离、开机/跨天自愈与权限诊断。详阅 [`REMINDER.md`](REMINDER.md) |
| **桌面小组件 (`widget/`, 15 个)** | `WidgetWorker.kt`, `WidgetBridge.kt`, `WidgetStore.kt`, `WidgetContentResolver.kt`, `WidgetThemeResolver.kt`, `WidgetBackgroundRenderer.kt`, `WidgetCoordinator.kt`, `WidgetRefreshScheduler.kt`, `WidgetRefreshReceiver.kt`, `TodayWidgetProvider.kt`, `TodayWidgetService.kt`, `TodayItemViewBinder.kt`, `NextClassWidgetProvider.kt`, `WeekGridWidgetProvider.kt`, `WeekGridCanvasRenderer.kt` | 后台单线程执行器、内存快照缓存、今日/下一节/本周三类小组件、动态取色与 0% 透明规范、单条 `RTC_WAKEUP` 靶向闹钟。详阅 [`WIDGET.md`](WIDGET.md) |

---

## 四、Windows 桌面壳 (`windows/`)

| 文件路径 | 职责与硬性约束 |
|---|---|
| [`windows/runner/main.cpp`](../../windows/runner/main.cpp) | Win32 入口：`Local\com.fangzi.qustschedule.SingleInstance` 互斥锁 + 旧窗口唤醒置顶（**严禁中文注释，标题用 `\uXXXX` 转义**） |
| [`windows/runner/flutter_window.cpp`](../../windows/runner/flutter_window.cpp) / [`win32_window.cpp`](../../windows/runner/win32_window.cpp) | Flutter 宿主与 DPI 感知窗口，限制最小尺寸 `360×520`（**严禁中文注释**） |
| [`windows/runner/Runner.rc`](../../windows/runner/Runner.rc) | Windows 版本信息与图标资源（保持 `UTF-16LE + BOM`） |
| [`windows/packaging/setup.iss`](../../windows/packaging/setup.iss) | Inno Setup 6 安装包构建脚本（支持 `/AUTOSTART=1` 静默升级重启） |

---

## 五、自动化测试索引 (`test/` & `packages/zf_academic/test/`)

| 目录 | 测试文件清单 | 守护重点 |
|---|---|---|
| **主工程 `test/` (23 测试 + 2 替身)** | `academic_cache_test.dart`, `academic_page_test.dart`, `academic_service_test.dart`, `app_model_test.dart`, `app_version_test.dart`, `boost_idle_optimization_test.dart`, `dock_transition_test.dart`, `formatted_text_span_test.dart`, `page_transition_test.dart`, `rebuild_scope_test.dart`, `reminder_planner_test.dart`, `reminder_service_test.dart`, `safe_json_file_test.dart`, `schedule_service_test.dart`, `term_calendar_test.dart`, `term_selector_helper_test.dart`, `timetable_test.dart`, `updater_test.dart`, `widget_planner_test.dart`, `widget_service_test.dart`, `widget_settings_page_test.dart`, `widget_style_test.dart`, `widget_test.dart`；测试替身：`support/fake_backend.dart`, `support/fake_reminder_gateway.dart` | L1 纯函数/服务单测、L2 页面交互、L3 性能与渲染防退化契约（0.5px 扫雷、Dock 动效、`AppMenuScope`、260ms 转场解耦、订阅隔离、`SafeJsonFile` Isolate）。详阅 [`UI_AND_TESTING.md`](UI_AND_TESTING.md) §6 |
| **协议包 `packages/zf_academic/test/` (9 测试 + 1 合成器)** | `cookies_test.dart`, `cookie_isolate_test.dart`, `credential_store_test.dart`, `crypto_test.dart`, `exams_test.dart`, `grades_test.dart`, `html_test.dart`, `http_client_test.dart`, `login_test.dart`；替身：`support/synthetic_zf.dart` | RFC 6265 Cookie、RSA 加密、正方登录/重定向白名单、课表/考试/成绩 HTML & JSON 解析 |
