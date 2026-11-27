# 全量文件与符号地图 (`docs/dev/FILE_MAP.md`)

> 基准路径：`qustschedule/`。增删改文件路径同步本表（`test/architecture_guard_test.dart` 双向校验）。

## 一、Flutter 主工程 (`lib/`)

### 1.1 入口与主题
| 文件 | 核心导出 | 职责 |
|---|---|---|
| [`lib/main.dart`](../../lib/main.dart) | `main()`, `CourseApp`, `_AppShell`, `pageForStatus()` | 根入口；并行 `loadAppVersion()`；经 `routeWrapper` 注入 `AppMenuScope`；`boot()` 前挂 `ReminderService`/`DesktopWidgetService`（仅 Android）；仅听 `routeNotifier`/`hints`；`onShow` 60s 冷却 + 600ms 延迟兜底同步 |
| [`lib/theme/app_theme.dart`](../../lib/theme/app_theme.dart) | `AppRadius`, `AppColors`, `RouteTransitionWrapper`, `buildLightTheme()`, `AppScrollBehavior` | M3 浅色主题；5 级圆角；25 语义色；`_SlideTransitionsBuilder` (260ms/240ms + 可注入 `routeWrapper`) |
| [`lib/theme/course_palette.dart`](../../lib/theme/course_palette.dart) | `CourseColor`, `CoursePalette` | 9 组浅/深课程色板；委托 `courseColorIndex()` 与 `WidgetThemeResolver.kt` 同构 |

### 1.2 状态控制器 (`lib/src/app_model.dart`, `lib/src/state/`)
| 文件 | 核心导出 | 职责 / 通知源 |
|---|---|---|
| [`lib/src/app_model.dart`](../../lib/src/app_model.dart) | `AppModel`, `AppStatus` | 门面协调器；`_authEpoch`、`boot()`、登录/切校/登出、`onAppShown()`、改密账号解析、`updateFlow` 转发 |
| [`lib/src/state/auth_session_controller.dart`](../../lib/src/state/auth_session_controller.dart) | `AuthSessionController` | `ScheduleService`、`schoolBaseUrl`、`buildAccountKey`、身份快照、验证码 `Completer`、脱敏日志 |
| [`lib/src/state/schedule_controller.dart`](../../lib/src/state/schedule_controller.dart) | `ScheduleController`, `WeekNotifier` | `Schedule`/`Terms`/`week`/`maxWeek`/`termStart`、调课与冲突缓存；`weekNotifier`、`refreshingNotifier` |
| [`lib/src/state/academic_controller.dart`](../../lib/src/state/academic_controller.dart) | `AcademicController` | `academicNotifier`：考试/成绩/记忆化 `gradeStats`/未评教/`_academicLoadSeq`/静默差量 |
| [`lib/src/state/preferences_controller.dart`](../../lib/src/state/preferences_controller.dart) | `PreferencesController` | `prefsNotifier`：`Preferences`、外观 300ms 草稿（`dispose()` 清理不落盘）、`preferencesLoaded` 门控、更新延时检测 |
| [`lib/src/state/hint_notice_controller.dart`](../../lib/src/state/hint_notice_controller.dart) | `HintNoticeController`, `HintScope` | `hints`：三通道气泡 (`global`/`schedule`/`academic`)、存储告警与 `humanizeError` |

### 1.3 服务、领域模型与原生桥接 (`lib/src/`)
| 文件 | 核心导出 | 职责 |
|---|---|---|
| [`lib/src/schedule_service.dart`](../../lib/src/schedule_service.dart) | `ScheduleService`, `ScheduleStageCallback` | 课表/学期抓取；10s 超时；`_reloginFlight` 单飞锁；10m×2 熔断；`readSavedCredentials()`/`_fallbackAccountKeys()` |
| [`lib/src/schedule_cache.dart`](../../lib/src/schedule_cache.dart) | `ScheduleCache`, `File/InMemory/LateScheduleCache`, `CachedSchedule` | `zf-schedule-cache.json` (`SafeJsonFile`) |
| [`lib/src/academic_service.dart`](../../lib/src/academic_service.dart) | `AcademicService`, `GradeStats` | 考试/成绩抓取、未评教保历史成绩、静默同步、加权 GPA |
| [`lib/src/academic_cache.dart`](../../lib/src/academic_cache.dart) | `ExamCache`, `GradesCache`, `File/InMemory/Late*Cache`, `CachedTerm*` | 按 `termId` 分桶的 `zf-exam-cache.json` / `zf-grades-cache.json` |
| [`lib/src/term_selector_helper.dart`](../../lib/src/term_selector_helper.dart) | `parseEnrollmentYear()`, `estimateCurrentAcademicYear()`, `filterTerms()`, `resolveSemesterCode()`, `formatTermPrimaryLabel()` | 10 位学号推导入学年与学期选项过滤 |
| [`lib/src/backends.dart`](../../lib/src/backends.dart) | `ScheduleBackend`, `ZfBackend`, `defaultBackendFactory` | 教务客户端抽象（供测试替身注入） |
| [`lib/src/school.dart`](../../lib/src/school.dart) | `SchoolProfile`, `qustProfile`, `qustLines`, `presetSchoolUrls`, `defaultSchool`, `defaultAcademicPaceHosts`, `schoolLabel()`, `sameSchool()`, `normalizeSchoolKeyUrl()`, `buildAccountKey()` | 默认教务线路、站点降频配置、URL 规范化与凭据键拼接 |
| [`lib/src/timetable.dart`](../../lib/src/timetable.dart) | `PeriodGroup`, `SectionTime`, `BigBreak`, `Timetable`, `QuickSetup`, `buildSections()`, `activeTimetableAt()`, `reconcileSections()`, `sectionOfPeriod()`, `sectionStartMinutes()`, `sectionEndMinutes()` | 多套作息表按生效日循环切换与节次时间推导 |
| [`lib/src/term_calendar.dart`](../../lib/src/term_calendar.dart) | `dayOnly()`, `dateAtMinutes()`, `mondayOf()`, `weekOf()`, `dateOf()`, `termStartFromWeek()`, `estimateTermStart()`, `conflictLayout()` | `DateTime.utc` 校历换算与冲突分栏 |
| [`lib/src/reschedule.dart`](../../lib/src/reschedule.dart) | `RescheduleRule`, `RescheduleConflict`, `RescheduleWeekView`, `rescheduleWeekView()` | 按日期平移单日课程的本地调课引擎 |
| [`lib/src/course_text.dart`](../../lib/src/course_text.dart) | `roomOnly()` | 地点短名清洗（剥离校区前缀） |
| [`lib/src/formatted_text.dart`](../../lib/src/formatted_text.dart) | `FormattedSegmentKind`, `FormattedSegment`, `parseFormattedSegments()` | 纯 Dart 行内富文本分词（支持 Isolate） |
| [`lib/src/stable_hash.dart`](../../lib/src/stable_hash.dart) | `coursePaletteColorCount`, `fnv1a32()`, `fnv1a32Hex()`, `courseColorIndex()` | 纯 Dart FNV-1a 32 位哈希与 9 色板索引 |
| [`lib/src/route_settled.dart`](../../lib/src/route_settled.dart) | `runInBackground()`, `scheduleAfterRouteSettled()`, `RouteSettledHandle`, `RouteSettledStateMixin`, `RouteSettledGate` | 260ms 转场与后台加载并行协调器 |
| [`lib/src/background_isolate_io.dart`](../../lib/src/background_isolate_io.dart) | `runIsolateComputation()` | VM `Isolate.run` 实现 |
| [`lib/src/background_isolate_stub.dart`](../../lib/src/background_isolate_stub.dart) | `runIsolateComputation()` | 非 VM 环境 `Future.microtask` 降级 |
| [`lib/src/safe_json_file.dart`](../../lib/src/safe_json_file.dart) | `SafeJsonFile`, `SafeJsonReadResult`, `isolateJsonDecodeThreshold` (16KB) | 路径串行锁 + 待写合并 + `.tmp`/`.bak` 原子自愈 + `>=16KB` Isolate 解码 |
| [`lib/src/preferences_repository.dart`](../../lib/src/preferences_repository.dart) | `Preferences`, `preferencesSchema` (15), `defaultUpdateProxyUrl`, `presetUpdateProxies`, `setAppearance()` | `app_prefs.json` Schema 15 持久化与迁移 |
| [`lib/src/credentials_repository.dart`](../../lib/src/credentials_repository.dart) | `SecureCredentialStore` | Keystore / DPAPI 凭据加密存储 |
| [`lib/src/session_repository.dart`](../../lib/src/session_repository.dart) | `SessionRepository`, `File/InMemory/LateSessionRepository` | `zf-session.json` Cookie 快照持久化 |
| [`lib/src/app_version.dart`](../../lib/src/app_version.dart) | `appVersion`, `appVersionFull`, `loadAppVersion()` | 异步解析 `pubspec.yaml` 版本号 |
| [`lib/src/reminder_planner.dart`](../../lib/src/reminder_planner.dart) | `ReminderStyle`, `CourseReminderEvent`, `ReminderPlan`, `planCourseReminders()`, `reminderFingerprint()`, `defaultReminderLeadMinutes` (10) | 14 天课前提醒规划纯函数与 FNV-1a 指纹 |
| [`lib/src/reminder_gateway.dart`](../../lib/src/reminder_gateway.dart) | `ReminderGateway`, `MethodChannelReminderGateway`, `ReminderSyncResult`, `ReminderRuntimeStatus` | `qustschedule/reminder` 通道网关（12 方法 + `dirty` 状态） |
| [`lib/src/reminder_service.dart`](../../lib/src/reminder_service.dart) | `ReminderService` | 监听 `AppModel` + `prefsNotifier`，300ms 防抖 + 单飞队列 + `cancelAll()` 串行同步原生提醒 |
| [`lib/src/widget_style.dart`](../../lib/src/widget_style.dart) | `DesktopWidgetKind`, `WidgetThemeMode`, `WidgetDensity`, `FinishedCourseMode`, `WeekendColumnMode`, `WidgetStylePreset`, `DesktopWidgetStyle`, `DesktopWidgetConfigSet` | 三类小组件样式模型、5 预设与容错 JSON |
| [`lib/src/widget_planner.dart`](../../lib/src/widget_planner.dart) | `WidgetTimelineItem`, `WidgetDayPlan`, `WidgetUpcomingExam`, `WidgetWeekBlock`, `WidgetWeekPlan`, `WidgetSnapshot`, `buildWidgetSnapshot()`, `buildSignedOutWidgetSnapshot()` | 14 天日程/30 天考试/2~3 周网格快照与指纹 |
| [`lib/src/widget_gateway.dart`](../../lib/src/widget_gateway.dart) | `DesktopWidgetGateway`, `MethodChannelDesktopWidgetGateway` | `qustschedule/widget` 通道网关与实例计数监听 |
| [`lib/src/widget_service.dart`](../../lib/src/widget_service.dart) | `WidgetSnapshotInput`, `DesktopWidgetService` | 300ms 防抖 + 单飞队列同步原生小组件与 `livePinnedCounts` |

### 1.4 应用内更新（新版本） (`lib/src/updater/`，6 文件)
| 文件 | 核心导出 | 职责 |
|---|---|---|
| [`lib/src/updater/update_flow_controller.dart`](../../lib/src/updater/update_flow_controller.dart) | `UpdateFlowController`, `UpdateFlowStage` | 单弹窗更新状态机、后台胶囊、`_downloadEpoch`/`_isTriggeringInstall` 防竞态与注入 `UpdaterGateway` |
| [`lib/src/updater/update_service.dart`](../../lib/src/updater/update_service.dart) | `UpdateService`, `CancelToken` | Releases 检查、代理测速、`>=4MB` 3 线程分片下载与 SHA-256 |
| [`lib/src/updater/update_models.dart`](../../lib/src/updater/update_models.dart) | `UpdateStatus`, `ReleaseInfo`, `ReleaseAsset`, `DownloadProgress`, `ProxyTestResult`, `UpdateCheckResult`, `UpdateProxyPreset`, `defaultUpdateProxyUrl`, `kPresetUpdateProxyEntries`, `presetUpdateProxies`, `displayProxyName()` | 更新数据模型与预设代理真源 |
| [`lib/src/updater/updater_gateway.dart`](../../lib/src/updater/updater_gateway.dart) | `UpdaterGateway`, `MethodChannelUpdaterGateway` | 隔离 `AppInstaller` 通道与 `url_launcher` 外部浏览器的网关接口 |
| [`lib/src/updater/app_installer.dart`](../../lib/src/updater/app_installer.dart) | `AppInstaller` | Android APK 安装（`com.fangzi.qustschedule/updater`）；Windows 安装版升级与便携版 `.update_staging` + VBS + `robocopy /mir` |
| [`lib/src/updater/version_comparator.dart`](../../lib/src/updater/version_comparator.dart) | `compareSemanticVersions()`, `isVersionNewer()` | 语义化版本与预发布比较 |

### 1.5 页面层 (`lib/pages/`，18 页)
| 文件 | 核心组件 / 导出 | 职责 |
|---|---|---|
| [`lib/pages/home_shell.dart`](../../lib/pages/home_shell.dart) | `HomeShell` | 课表/学业/设置三页横向轨道外壳（`FloatingDock` 驱动 + 页级 `AppMenuScope`） |
| [`lib/pages/schedule_page.dart`](../../lib/pages/schedule_page.dart) | `SchedulePage` | 周视图课表主页、`WeekPager`、顶栏菜单与回本周按钮 |
| [`lib/pages/academic_page.dart`](../../lib/pages/academic_page.dart) | `AcademicPage`, `formatExamTimeLabel()`, `sortAcademicExams()` | 学业概览（`SliverList.builder`、考试倒计时、GPA、成绩列表） |
| [`lib/pages/appearance_sheet.dart`](../../lib/pages/appearance_sheet.dart) | `showAppearanceSheet()` | 外观调节抽屉（格高/字号/字段开关） |
| [`lib/pages/reschedule_page.dart`](../../lib/pages/reschedule_page.dart) | `ReschedulePage` | 按日期调课管理 |
| [`lib/pages/settings_page.dart`](../../lib/pages/settings_page.dart) | `SettingsPage` | 账号、课表作息、「提醒与小组件」（含电池/闹钟/自启动权限）、关于与更新 |
| [`lib/pages/timetable_list_page.dart`](../../lib/pages/timetable_list_page.dart) | `TimetableListPage` | 多套作息表管理与快捷生成 |
| [`lib/pages/timetable_edit_page.dart`](../../lib/pages/timetable_edit_page.dart) | `TimetableEditPage` | 单张作息表草稿编辑 |
| [`lib/pages/school_address_page.dart`](../../lib/pages/school_address_page.dart) | `SchoolAddressPage` | 默认线路与自定义教务地址管理 |
| [`lib/pages/login_page.dart`](../../lib/pages/login_page.dart) | `LoginPage` | 教务登录（支持高级切线） |
| [`lib/pages/captcha_page.dart`](../../lib/pages/captcha_page.dart) | `CaptchaPage` | 验证码输入（固定浅色画布） |
| [`lib/pages/reminder_page.dart`](../../lib/pages/reminder_page.dart) | `ReminderPage` | Android 课程提醒配置、测试与诊断 |
| [`lib/pages/widget_settings_page.dart`](../../lib/pages/widget_settings_page.dart) | `WidgetSettingsPage`, `computeWidgetSettingsSnapshots()` | Android 小组件配置、同构预览、60s 回前台冷却与一键固定 |
| [`lib/pages/debug_page.dart`](../../lib/pages/debug_page.dart) | `DebugPage` | 脱敏调试信息（仅 Cookie 键名/状态/原始行，单层 `SelectionArea`） |
| [`lib/pages/about_page.dart`](../../lib/pages/about_page.dart) | `AboutPage`, `LicenseTextPage` | 关于页与 GPL-3.0 协议全文 |
| [`lib/pages/changelog_page.dart`](../../lib/pages/changelog_page.dart) | `ChangelogPage` | 更新日志（后台 Isolate 解析 `CHANGELOG.md`） |
| [`lib/pages/update_dialog.dart`](../../lib/pages/update_dialog.dart) | `UpdateDialog`, `showUpdateDialog()`, `showDownloadProgressDialog()` | 单弹窗更新全流程 |
| [`lib/pages/update_proxy_page.dart`](../../lib/pages/update_proxy_page.dart) | `UpdateProxyPage` | 加速代理选择、自定义与并发测速 |

### 1.6 通用组件 (`lib/widgets/`，17 个)
| 文件 | 核心导出 | 职责 |
|---|---|---|
| [`lib/widgets/floating_dock.dart`](../../lib/widgets/floating_dock.dart) | `FloatingDock`, `FloatingDockState`, `FloatingDockItem` | 底部悬浮导航栏（唯一运动源、可打断拖拽、按下懒建） |
| [`lib/widgets/tactile_button.dart`](../../lib/widgets/tactile_button.dart) | `TactileAppBar`, `TactileSurfaceScope`, `Tactile*Button` | 按压放大触感体系与四层合绘顶栏 |
| [`lib/widgets/app_menu.dart`](../../lib/widgets/app_menu.dart) | `AppMenuScope`, `AppMenuScopeController`, `AppMenuItem`, `showAppMenu()`, `RenderMenuMorphBox` | 原地弹性展开菜单与页级空间作用域 |
| [`lib/widgets/app_bottom_sheet.dart`](../../lib/widgets/app_bottom_sheet.dart) | `showAppModalBottomSheet()`, `ScrollableBottomSheetFrame` | 统一圆角底部弹窗容器 |
| [`lib/widgets/app_snack_bar.dart`](../../lib/widgets/app_snack_bar.dart) | `AppSnackBarType`, `buildAppSnackBar()`, `showAppSnackBar()` | 浅色悬浮胶囊提示条 |
| [`lib/widgets/calibrate_sheet.dart`](../../lib/widgets/calibrate_sheet.dart) | `showCalibrateSheet()` | 学期周次校准底部抽屉（供课表页与设置页共享） |
| [`lib/widgets/course_tile.dart`](../../lib/widgets/course_tile.dart) | `CourseBlock`, `CourseBlockLayoutSnapshot` | 课表卡片（`TextPainter` 求解器 + 512 LRU + 空闲预热） |
| [`lib/widgets/course_detail_sheet.dart`](../../lib/widgets/course_detail_sheet.dart) | `showEntryDetails()`, `compressWeeks()` | 课程详情底部抽屉 |
| [`lib/widgets/week_pager.dart`](../../lib/widgets/week_pager.dart) | `WeekPager`, `WeekPagerController` | 周视图翻页器（跨 4+ 周 180ms 跳页 + 邻周预热） |
| [`lib/widgets/desktop_widget_preview.dart`](../../lib/widgets/desktop_widget_preview.dart) | `DesktopWidgetPreview`, `PreviewWallpaper`, `buildSampleWidgetSnapshot()` | 与原生同构的纯 Flutter 小组件预览 |
| [`lib/widgets/formatted_text_span.dart`](../../lib/widgets/formatted_text_span.dart) | `buildTextSpanFromSegments()`, `buildFormattedTextSpan()` | 更新日志行内富文本 `TextSpan` 拼装（消费 `formatted_text.dart`） |
| [`lib/widgets/page_skeleton.dart`](../../lib/widgets/page_skeleton.dart) | `CardList/Document/PreviewSettingsTransitionPlaceholder` | 260ms 路由入场零 Ticker 静态骨架 |
| [`lib/widgets/reminder_permission_tile.dart`](../../lib/widgets/reminder_permission_tile.dart) | `ReminderPermissionTile`, `showReminderGuideToast()` | 权限状态条目与跳设置指路 Toast |
| [`lib/widgets/section_title.dart`](../../lib/widgets/section_title.dart) | `SectionTitle` | 分组小标题 |
| [`lib/widgets/status_popup.dart`](../../lib/widgets/status_popup.dart) | `StatusPopup` | 顶栏右侧状态气泡 |
| [`lib/widgets/time_wheel_picker.dart`](../../lib/widgets/time_wheel_picker.dart) | `showTimeWheel()`, `showTimeRangeWheel()`, `showWeekCalibrationWheel()` | 时间/节数/周次滚轮选择器 |
| [`lib/widgets/changelog_category_badge.dart`](../../lib/widgets/changelog_category_badge.dart) | `ChangelogCategoryBadge` | 更新日志分类徽章 |

---

## 二、协议子包 (`packages/zf_academic/`，纯 Dart)
| 文件 | 核心导出 | 职责 |
|---|---|---|
| [`packages/zf_academic/lib/zf_academic.dart`](../../packages/zf_academic/lib/zf_academic.dart) | 43 项公开纯 Dart 导出 | 按 8 个 `show` 子句收窄导出模型/客户端/凭据/Cookie/加密/错误/URL |
| [`packages/zf_academic/lib/zf_academic_io.dart`](../../packages/zf_academic/lib/zf_academic_io.dart) | `FileCookieStorage`, `DartIoTransport`, `vmZhengfangClient()` | `dart:io` 传输、文件 Cookie 存储与客户端工厂 |
| [`packages/zf_academic/lib/src/zhengfang_client.dart`](../../packages/zf_academic/lib/src/zhengfang_client.dart) | `ZhengfangClient`, `SessionInfo` | 正方登录/验证码/会话检查、课表/考试/成绩请求、`close()`/`dispose()` 幂等释放 |
| [`packages/zf_academic/lib/src/http_client.dart`](../../packages/zf_academic/lib/src/http_client.dart) | `AcademicHttpClient`, `AcademicHttpOptions`, `HttpRequestOptions`, `HttpResponse`, `ImageResponse`, `sniffMimeType()` | Cookie 管理、HTTP→HTTPS 升级、重定向审计、主机降频、脱敏日志 |
| [`packages/zf_academic/lib/src/dart_io_transport.dart`](../../packages/zf_academic/lib/src/dart_io_transport.dart) | `DartIoTransport` | `dart:io` `HttpClient`（禁自动重定向） |
| [`packages/zf_academic/lib/src/cookies.dart`](../../packages/zf_academic/lib/src/cookies.dart) | `CookieStore`, `CookieRecord`, `CookieStoreSnapshot`, `parseSetCookie()` | RFC 6265 解析与 Domain/Path 隔离 |
| [`packages/zf_academic/lib/src/cookie_storage.dart`](../../packages/zf_academic/lib/src/cookie_storage.dart) | `CookieStorage`, `File/InMemoryCookieStorage` | Cookie 快照存储 |
| [`packages/zf_academic/lib/src/credential_store.dart`](../../packages/zf_academic/lib/src/credential_store.dart) | `CredentialStore`, `Credentials`, `InMemoryCredentialStore`, `credentialStoreKey()` | 凭据存储抽象 |
| [`packages/zf_academic/lib/src/crypto.dart`](../../packages/zf_academic/lib/src/crypto.dart) | `zfFormEncryptPassword()`, `zfCasEncryptPassword()`, `rsaEncryptPkcs1()` | 正方 RSA PKCS#1 v1.5 加密 |
| [`packages/zf_academic/lib/src/schedule.dart`](../../packages/zf_academic/lib/src/schedule.dart) | `jsonSchedule()`, `termsFromHtml()`, `tryParseWeeks()`, `maxWeeksOf()`, `defaultMaxWeeks` (18) | 课表/周次解析与学期过滤 |
| [`packages/zf_academic/lib/src/academic_query.dart`](../../packages/zf_academic/lib/src/academic_query.dart) | `jsonExams()`, `jsonGrades()`, `parseExamTime()` | 考试与成绩 JSON 解析 |
| [`packages/zf_academic/lib/src/html.dart`](../../packages/zf_academic/lib/src/html.dart) | `loginForm()`, `detectCaptcha()`, `identity()`, `selectOptions()` | 零 DOM 依赖 HTML 提取器 |
| [`packages/zf_academic/lib/src/respond.dart`](../../packages/zf_academic/lib/src/respond.dart) | `inspectResponse()`, `ResponseDiagnosis`, `ResponseKind`, `listRows()`, `listRowsOrEmpty()`, `requireQueryPage()` | 响应分类诊断（5xx/403/过期/未评教/JSON）与 HTTP 状态码透传 |
| [`packages/zf_academic/lib/src/urls.dart`](../../packages/zf_academic/lib/src/urls.dart) | `parseAcademicAddress()`, `normalizeEndpoints()`, `isAllowedUrl()`, `zfTermParams()`, `calendarTerm()`, `parseTerm()` | URL 规范化、同源白名单、`xnm`/`xqm` 映射 |
| [`packages/zf_academic/lib/src/errors.dart`](../../packages/zf_academic/lib/src/errors.dart) | `AcademicError`, `ErrorCode`, `asAcademicError()` | 23 项标准错误码 |
| [`packages/zf_academic/lib/src/types.dart`](../../packages/zf_academic/lib/src/types.dart) | `Schedule`, `ScheduleEntry`, `Term`, `Terms`, `ExamItem`, `GradeItem`, `CaptchaState`, `RequestLog`, `qustZfEndpoints` | 不可变数据结构与 `N2151` 端点 |
| [`packages/zf_academic/lib/src/util.dart`](../../packages/zf_academic/lib/src/util.dart) | `str()`, `number()`, `field()`, `firstOf()`, `rowKey()` | JSON 提取与 FNV-1a 去重 |
| [`packages/zf_academic/example/secure_storage_flutter.dart`](../../packages/zf_academic/example/secure_storage_flutter.dart) | `FlutterSecureStorageCredentialStore` | `flutter_secure_storage` v11 示例适配器 |

---

## 三、Android 原生 (`android/app/src/main/kotlin/com/fangzi/qustschedule/`，30 文件)
| 模块 | 文件 | 职责 / 专题 |
|---|---|---|
| 入口与更新 (2) | `android/app/src/main/kotlin/com/fangzi/qustschedule/MainActivity.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/updater/AppUpdaterBridge.kt` | 3 条 MethodChannel；`RenderMode.surface` + `setZOrderOnTop(true)` + `popSystemNavigator` 热驻留；`UpdaterWorker` 校验 APK + `FileProvider` 安装 |
| 课前提醒 (13) | `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderBridge.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderDailyResyncReceiver.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderFluidRenderer.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderFluidService.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderNotifier.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderPayload.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderPermissions.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderReceiver.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderRestoreReceiver.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderSamples.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderScheduler.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderStore.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/reminder/ReminderWorker.kt` | 见 [`REMINDER.md`](REMINDER.md) |
| 桌面小组件 (15) | `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/NextClassWidgetProvider.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/TodayItemViewBinder.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/TodayWidgetProvider.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/TodayWidgetService.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WeekGridRemoteViewsBuilder.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WeekGridWidgetProvider.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetBackgroundRenderer.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetBridge.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetContentResolver.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetCoordinator.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetRefreshReceiver.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetRefreshScheduler.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetStore.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetThemeResolver.kt`, `android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetWorker.kt` | 见 [`WIDGET.md`](WIDGET.md) |

---

## 四、Windows 桌面壳 (`windows/`)
| 文件 | 职责 |
|---|---|
| [`windows/runner/main.cpp`](../../windows/runner/main.cpp) | `SingleInstance` 互斥锁 + 旧窗口唤醒置顶（纯 ASCII，标题 `\uXXXX`） |
| [`windows/runner/flutter_window.cpp`](../../windows/runner/flutter_window.cpp), [`windows/runner/flutter_window.h`](../../windows/runner/flutter_window.h), [`windows/runner/win32_window.cpp`](../../windows/runner/win32_window.cpp), [`windows/runner/win32_window.h`](../../windows/runner/win32_window.h) | Flutter 宿主、DPI 感知、最小 `360×520`、深色标题栏（纯 ASCII） |
| [`windows/runner/utils.cpp`](../../windows/runner/utils.cpp), [`windows/runner/utils.h`](../../windows/runner/utils.h), [`windows/runner/resource.h`](../../windows/runner/resource.h) | UTF-16/UTF-8 转换、控制台重定向与 Win32 资源 ID（纯 ASCII） |
| [`windows/runner/Runner.rc`](../../windows/runner/Runner.rc) | 版本与图标资源（**无 BOM UTF-8 + `#pragma code_page(65001)`**） |
| [`windows/runner/CMakeLists.txt`](../../windows/runner/CMakeLists.txt), [`windows/runner/runner.exe.manifest`](../../windows/runner/runner.exe.manifest), [`windows/runner/resources/app_icon.ico`](../../windows/runner/resources/app_icon.ico) | CMake 构建、DPI/OS 清单与图标 |
| [`windows/packaging/setup.iss`](../../windows/packaging/setup.iss) | Inno Setup 6 脚本（**UTF-8 + BOM**，`/AUTOSTART=1`） |

---

## 五、测试与工程校验 (`test/`, `packages/zf_academic/test/`, `tool/`)
| 目录 | 文件清单 | 详情 |
|---|---|---|
| 主工程 `test/` (30 + 5 替身/辅助) | `test/academic_cache_test.dart`, `test/academic_page_test.dart`, `test/academic_service_test.dart`, `test/app_model_test.dart`, `test/app_version_test.dart`, `test/architecture_guard_test.dart`, `test/auth_and_shell_widget_test.dart`, `test/boost_idle_optimization_test.dart`, `test/credentials_repository_test.dart`, `test/dock_transition_test.dart`, `test/formatted_text_span_test.dart`, `test/page_transition_test.dart`, `test/rebuild_scope_test.dart`, `test/reminder_planner_test.dart`, `test/reminder_service_test.dart`, `test/safe_json_file_test.dart`, `test/schedule_grid_widget_test.dart`, `test/schedule_menu_and_appearance_widget_test.dart`, `test/schedule_service_test.dart`, `test/settings_and_features_widget_test.dart`, `test/stable_hash_test.dart`, `test/term_calendar_test.dart`, `test/term_selector_helper_test.dart`, `test/timetable_test.dart`, `test/ui_components_widget_test.dart`, `test/updater_test.dart`, `test/widget_planner_test.dart`, `test/widget_service_test.dart`, `test/widget_settings_page_test.dart`, `test/widget_style_test.dart`, `test/support/fake_backend.dart`, `test/support/fake_reminder_gateway.dart`, `test/support/fake_updater_gateway.dart`, `test/support/fake_widget_gateway.dart`, `test/support/widget_test_helpers.dart` | [`UI_AND_TESTING.md`](UI_AND_TESTING.md) §6 |
| 协议包 `packages/zf_academic/test/` (9 + 1 替身) | `packages/zf_academic/test/cookie_isolate_test.dart`, `packages/zf_academic/test/cookies_test.dart`, `packages/zf_academic/test/credential_store_test.dart`, `packages/zf_academic/test/crypto_test.dart`, `packages/zf_academic/test/exams_test.dart`, `packages/zf_academic/test/grades_test.dart`, `packages/zf_academic/test/html_test.dart`, `packages/zf_academic/test/http_client_test.dart`, `packages/zf_academic/test/login_test.dart`, `packages/zf_academic/test/support/synthetic_zf.dart` | [`CORE_AND_STATE.md`](CORE_AND_STATE.md) §8 |
| 工程脚本与配置 | [`tool/verify.dart`](../../tool/verify.dart), [`.gitattributes`](../../.gitattributes), [`.github/workflows/build-release.yml`](../../.github/workflows/build-release.yml) | 本地与 CI 共用统一验证入口、跨平台换行策略与发布流水线 |
