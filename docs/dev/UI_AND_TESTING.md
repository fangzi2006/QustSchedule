# UI、自定义物理动效与测试矩阵速查手册（UI & Testing Reference）

> **AI 检索说明**：本文档覆盖 `lib/main.dart`、`lib/theme/*`、`lib/pages/*`、`lib/widgets/*`、`test/*`、`packages/zf_academic/test/*` 及 `.github/workflows/build-release.yml` 的完整技术契约。所有类名、方法签名、常量令牌、弹簧参数、`Listenable` 订阅边界与测试矩阵均与最新源码 1:1 对齐，供后续 AI 会话直接定点检索，无需重复通读 UI 与测试源码。
> **版本铁律**：严禁在任何文档或代码中硬编码应用版本号，唯一版本事实源为 `pubspec.yaml`（运行时通过 `lib/src/app_version.dart` 的 `loadAppVersion()` 异步读取 `appVersion` / `appVersionFull`）。

---

## 目录（Quick TOC）

1. [全局速查路由表（Widget / Page / Test Lookup Table）](#1-全局速查路由表widget--page--test-lookup-table)
2. [应用入口、顶层路由与生命周期契约（`main.dart`）](#2-应用入口顶层路由与生命周期契约maindart)
3. [主题系统、圆角令牌、配色与页面转场（`lib/theme/*`）](#3-主题系统圆角令牌配色与页面转场libtheme)
   - 3.1 [`AppRadius` 圆角令牌规范](#31-appradius-圆角令牌规范)
   - 3.2 [`AppColors` 语义色令牌全表（25 项）](#32-appcolors-语义色令牌全表25-项)
   - 3.3 [`CoursePalette` 课程色板与 FNV-1a 哈希契约](#33-coursepalette-课程色板与-fnv-1a-哈希契约)
   - 3.4 [Material 3 浅色主题与 `AppScrollBehavior`](#34-material-3-浅色主题与-appscrollbehavior)
   - 3.5 [连续双向缓动页面转场（`_SlideTransitionsBuilder`）](#35-连续双向缓动页面转场_slidetransitionsbuilder)
4. [核心自定义物理组件与渲染架构（`lib/widgets/*`）](#4-核心自定义物理组件与渲染架构libwidgets)
   - 4.1 [`HomeShell` + `FloatingDock` 单一运动源与液态透镜物理契约](#41-homeshell--floatingdock-单一运动源与液态透镜物理契约)
   - 4.2 [`TactileButton` 体系、`TactileAppBar` 四层合绘与 `_ZOrderedRow`](#42-tactilebutton-体系tactileappbar-四层合绘与-_zorderedrow)
   - 4.3 [`AppMenu` 与 `AppMenuScope` 双轴形变弹簧、空间绑定与选择性遮罩](#43-appmenu-与-appmenuscope-双轴形变弹簧空间绑定与选择性遮罩)
   - 4.4 [`WeekPager` 锚点单页物理、跨周借位滑入与空闲帧邻近周预热](#44-weekpager-锚点单页物理跨周借位滑入与空闲帧邻近周预热)
   - 4.5 [`CourseBlock` 排版预算求解器、`letterSpacing: 0` 与 `1e-4` 容差契约](#45-courseblock-排版预算求解器letterspacing-0-与-1e-4-容差契约)
   - 4.6 [其余公共组件契约（`StatusPopup` / `AppSnackBar` / `TimeWheelPicker` / `DesktopWidgetPreview` / `PageSkeleton` 等）](#46-其余公共组件契约statuspopup--appsnackbar--timewheelpicker--desktopwidgetpreview--pageskeleton-等)
5. [页面级 `Listenable` 订阅隔离与交互契约（`lib/pages/*` 全量 18 页）](#5-页面级-listenable-订阅隔离与交互契约libpages-全量-18-页)
   - 5.1 [全页面 `Listenable` 订阅边界总表（Rebuild Isolation Contract）](#51-全页面-listenable-订阅边界总表rebuild-isolation-contract)
   - 5.2 [各页面状态交互、核心方法与弹窗/抽屉明细](#52-各页面状态交互核心方法与弹窗抽屉明细)
6. [测试矩阵、测试替身与 CI 门禁（`test/*` & `packages/zf_academic/test/*`）](#6-测试矩阵测试替身与-ci-门禁test--packageszf_academictest)
   - 6.1 [L0–L3 测试分层架构与执行铁律](#61-l0l3-测试分层架构与执行铁律)
   - 6.2 [主工程测试套件全表（`test/*.dart`，23 个测试文件）](#62-主工程测试套件全表testdart23-个测试文件)
   - 6.3 [协议包测试套件全表（`packages/zf_academic/test/*.dart`，9 个测试文件）](#63-协议包测试套件全表packageszf_academictestdart9-个测试文件)
   - 6.4 [测试替身与辅助夹具（`FakeBackend` / `FakeReminderGateway` 等）](#64-测试替身与辅助夹具fakebackend--fakeremindergateway-等)
   - 6.5 [GitHub Actions CI/CD 流水线契约（`.github/workflows/build-release.yml`）](#65-github-actions-cicd-流水线契约githubworkflowsbuild-releaseyml)

---

## 1. 全局速查路由表（Widget / Page / Test Lookup Table）

### 1.1 主题与组件速查表（`lib/main.dart`, `lib/theme/*`, `lib/widgets/*`）

| 文件路径（相对 `qustschedule/`） | 核心导出类 / 函数 | 核心职责与关键检索词 | 守护测试文件 |
| :--- | :--- | :--- | :--- |
| `lib/main.dart` | `main()`, `CourseApp`, `_AppShell`, `pageForStatus()` | 异步读取 `loadAppVersion()`、挂载 `ReminderService` / `DesktopWidgetService`（仅 Android）、前后台 `onShow` 强制同步、顶层状态路由映射 | `widget_test.dart`, `rebuild_scope_test.dart` |
| `lib/theme/app_theme.dart` | `AppRadius`, `AppColors`, `buildLightTheme()`, `AppScrollBehavior`, `_SlideTransitionsBuilder`, `_ContinuousCurveAnimation`, `_EdgeShadowPainter`, `_RouteScrimPainter` | 5 级圆角、25 个语义色令牌、M3 浅色主题、全输入设备拖拽放行、260ms/240ms 全宽水平滑动转场（含路由级 `AppMenuScope` + `RepaintBoundary`） | `page_transition_test.dart`, `widget_test.dart` |
| `lib/theme/course_palette.dart` | `CourseColor`, `CoursePalette` | 9 组浅色/深色配对课程色板、FNV-1a 乘加哈希 `indexOf(courseName)`（客户端与 Android 原生小组件同构） | `widget_test.dart`, `widget_settings_page_test.dart` |
| `lib/widgets/floating_dock.dart` | `FloatingDockItem`, `FloatingDock`, `FloatingDockState` | 58dp 底部悬浮胶囊、液态透镜（`RSuperellipse`）、过阻尼中心弹簧 `_slideSpring`（速度上限 `31.5`）、欠阻尼速度拉伸振子、`_OutsideLensClipper` 掏空裁剪、`hitTestGlobalPosition` | `dock_transition_test.dart`, `widget_test.dart` |
| `lib/widgets/tactile_button.dart` | `TactileSurfaceStyle`, `TactileSurfaceButton`, `TactileIconButton`, `TactileBackButton`, `TactileActionVariant`, `TactileActionButton`, `TactileSurfaceScope`, `TactileAppBar` | 物理按压放大（`1.0 + pressAmplitude * effectiveP`）、橡皮筋微拖拽、190ms 长按 / 下拉直滑入菜单、`TactileSurfaceScope` 四层合绘（静态背景→全部阴影→纯白底面→前景）、`_TactileArenaRecognizer` 手势独占 | `widget_test.dart`, `dock_transition_test.dart` |
| `lib/widgets/app_menu.dart` | `AppMenuItem`, `AppMenuScopeController`, `AppMenuScope`, `showAppMenu()`, `RenderMenuMorphBox`, `activeAppMenuMorph`, `activeTactileDragStart`, `isRouteActiveForAppMenu()` | 双轴容器形变弹簧（宽高独立展开/收起）、`CompositedTransformTarget` 页面空间跟随、`AppMenuScope` 活跃门控与失活自动收起、`_MenuBarrier` 除 Dock 外全拦截、短菜单滑动果冻胶囊 vs 长菜单单条胶囊 | `dock_transition_test.dart`, `rebuild_scope_test.dart`, `widget_test.dart` |
| `lib/widgets/week_pager.dart` | `WeekPagerController`, `_WeekPagerPosition`, `_SkipJumpScrollActivity`, `_IgnoredHold`, `_DeferredDrag` | 以起手页为锚一次滑动只翻一页、慢拖 `1/3` 页阈值、按下不冻结在途动画（`_IgnoredHold`）、零死区延迟拖拽（`_DeferredDrag`）、跨 4 周及以上 `animateToPageWithSkip` 借位滑入 | `widget_test.dart` |
| `lib/widgets/course_tile.dart` | `CourseBlockLayoutSnapshot`, `CourseBlock`, `_BlockPlan` | 课程卡片固定高度与字号、`letterSpacing: 0` + `DefaultTextStyle`/`boldText` 预合并、`TextPainter` 四步预算求解器（砍行→回填→释放富余高度）、`1e-4` 浮点容差、512 容量 LRU 缓存、`prewarmEntry()` | `widget_test.dart`, `boost_idle_optimization_test.dart` |
| `lib/widgets/course_detail_sheet.dart` | `kDayLabels`, `compressWeeks()`, `showEntryDetails()` | 课程详情底部抽屉、周次连续区间压缩、单层 `SelectionArea` + 字段标签 `SelectionContainer.disabled` | `widget_test.dart`, `term_calendar_test.dart` |
| `lib/widgets/app_bottom_sheet.dart` | `showAppModalBottomSheet()`, `ScrollableBottomSheetFrame` | 统一带拖拽句柄（`showDragHandle: true`）底部弹窗封装、80% 屏高上限安全区滚动容器 | `widget_test.dart` |
| `lib/widgets/app_snack_bar.dart` | `AppSnackBarType`, `buildAppSnackBar()`, `showAppSnackBar()` | 居中自适应悬浮纯白胶囊提示、`TextPainter` 单行检测自动切换 `999dp` 胶囊与 `20dp` 圆角卡片、`aboveDock` 避让 Dock、自动清理前一条防排队 | `widget_test.dart` |
| `lib/widgets/status_popup.dart` | `StatusPopup` | 右上角非阻塞进度/成功/错误状态气泡、三作用域（`HintScope.global` / `schedule` / `academic`）优先级退避、失败重试/重新登录/调试操作栏 | `widget_test.dart`, `rebuild_scope_test.dart` |
| `lib/widgets/time_wheel_picker.dart` | `showTimeWheel()`, `showTimeRangeWheel()`, `showDurationWheel()`, `showMonthDayWheel()`, `showBigBreakWheel()`, `showSectionCountWheel()`, `showWeekCalibrationWheel()` | 基于 `CupertinoPicker` 的 7 类底部滚轮弹窗、鼠标滚轮 `pointerSignalResolver` 抢占实现“一次只走一格”、起止时间合法性校验 | `widget_test.dart` |
| `lib/widgets/desktop_widget_preview.dart` | `PreviewWallpaper`, `samplePreviewClock()`, `buildSampleWidgetSnapshot()`, `DesktopWidgetPreview` | 与 Android 原生小组件 100% 像素级同构的 Flutter 实时预览组件、10:40 黄金示例快照生成、强制 `TextScaler.noScaling` 免疫系统超大字体二次放大 | `widget_settings_page_test.dart` |
| `lib/widgets/page_skeleton.dart` | `CardListTransitionPlaceholder`, `DocumentTransitionPlaceholder`, `PreviewSettingsTransitionPlaceholder` | 260ms 路由入场滑行期间的超轻量静态纯色圆角矩形骨架（零 Ticker、零文本排版、`ExcludeSemantics`） | `page_transition_test.dart`, `boost_idle_optimization_test.dart` |
| `lib/widgets/reminder_permission_tile.dart` | `ReminderPermissionTile`, `showReminderGuideToast()` | 权限状态列表项（`ok`: `true` 绿 / `false` 红 / `null` 橙）、跨应用跳转系统设置时的原生 Toast / SnackBar 指路提示 | `widget_test.dart` |
| `lib/widgets/section_title.dart` | `SectionTitle` | 页面分组小标题（12sp、`FontWeight.w500`、`hintColor`、`letterSpacing: 0.3`） | `widget_test.dart` |
| `lib/widgets/changelog_category_badge.dart` | `ChangelogCategoryBadge` | 更新日志与更新弹窗共用的分类徽章（新增/优化/修复/碎碎念 → `AppColors.category*`） | `formatted_text_span_test.dart`, `updater_test.dart` |

### 1.2 页面文件速查表（`lib/pages/*` 全量 18 页）

| 文件路径（相对 `qustschedule/`） | 核心导出类 / 函数 | 监听的 `Listenable` 通道 | 核心功能概要 |
| :--- | :--- | :--- | :--- |
| `lib/pages/home_shell.dart` | `HomeShell`, `_ShellPager` | 外壳：`model.updateFlow`；顶层气泡：`hints + routeNotifier`；轨道：`_positionNotifier` | 三页常驻横向平移轨道（课表/学业/设置）、懒建学业与设置页、跟随 Dock `followPill` 逐帧位移、离场页 `IgnorePointer` + `TickerMode(false)` |
| `lib/pages/schedule_page.dart` | `SchedulePage`, `showWeekPicker()`, `showCalibrateSheet()`, `showDayConflicts()` | 顶栏周次条：`scheduleState + routeNotifier` + `_shownWeek`；刷新键：`routeNotifier + refreshingNotifier`；主体：`routeNotifier + scheduleState + prefsNotifier`；气泡：`hints + routeNotifier + refreshingNotifier` | 周视图课表、顶栏周次选择与更新状态图标、冲突打点与调课冲突抽屉、右下角“今”按钮、底部备注区、空闲帧邻近周预热 |
| `lib/pages/academic_page.dart` | `AcademicPage`, `NextExamHeroCard`, `isExamPast()`, `sortAcademicExams()`, `formatExamTimeLabel()` | 主体：`academicNotifier + scheduleState`；气泡：`hints + routeNotifier + academicNotifier` | 学期切换菜单、下一场考试倒计时 Hero 卡片、三级排序考试列表（`_LazyCardSegment` 懒加载 Sliver）、GPA 统计卡片、评教未完成横幅、成绩列表 |
| `lib/pages/settings_page.dart` | `SettingsPage` | 主体：`model.prefsNotifier`；权限卡内部：`_statusNotifier` | 课表设置（作息表/周次校准/教师/地点/备注/静默更新及步进器）、提醒与小组件入口及权限状态（仅 Android）、账号管理（身份/线路/改密/退登）、关于与自动更新开关 |
| `lib/pages/appearance_sheet.dart` | `showAppearanceSheet()` | `model.prefsNotifier` | 半透明遮罩（`alpha: 0.06`）底部抽屉、课表格子高度（50..120）与文字大小（80%..140%）双滑块、`_TickedTrackShape` 默认值同心圆环靶点与归位震动、关闭时 `flushAppearance()` |
| `lib/pages/reschedule_page.dart` | `ReschedulePage` | `model.prefsNotifier` | 按月日整体挪课规则列表、新增/编辑底部弹窗（`showMonthDayWheel`）、同日校验拦截 |
| `lib/pages/timetable_list_page.dart` | `TimetableListPage` | `model.prefsNotifier` | 全局三段课表节数入口（`showSectionCountWheel`）、多作息表卡片列表（「使用中」徽章、上限 `maxTimetables = 20`）、新建草稿不落盘直进编辑页 |
| `lib/pages/timetable_edit_page.dart` | `TimetableEditPage` | 本地 `_draft` 草稿 `State` | 显式保存（`PopScope` 拦截未保存改动）、重命名、生效月日选择、可折叠快捷生成面板（`buildSections` 预览确认）、三段分组节次时间起止滚轮编辑 |
| `lib/pages/school_address_page.dart` | `SchoolAddressPage` | `model.prefsNotifier` | 教务地址簿增删与切换（内置预设线路 `presetSchoolUrls` 与当前线路均隐藏删除按钮）、预设青科默认线路快捷 Chip（`knownSchools`）、软键盘弹出防挤压（`MediaQuery.removeViewInsets`）、切换地址自动 `popUntil(isFirst)` 并触发 `changeSchool` |
| `lib/pages/login_page.dart` | `LoginPage` | 横幅：`model.routeNotifier`；气泡：`hints + routeNotifier` | 账号密码表单（初始学号经 `model.loginPrefillUsername` 通用预填最近历史账号）、可折叠「教务地址 / 高级」面板、切换地址 `changeSchool(address, relogin: false)` + `signIn` |
| `lib/pages/captcha_page.dart` | `CaptchaPage` | `model.routeNotifier` | 验证码图片展示（`_cachedImageBase64` 记忆化解码防重复 `base64Decode`、固定浅底 `captchaSurface`）、输入框从 `InputDecorationTheme.hintStyle` 派生淡化提示色并重置 `letterSpacing: 0`、点击换一张、提交与取消 |
| `lib/pages/debug_page.dart` | `DebugPage` | 静态读取 `model` + `RouteSettledGate` | 四页签（概览 / 请求 / 原始课表 / 解析结果）、单层 `SelectionArea`、`_RawRowTile` 展开时懒格式化缩进 JSON、清除学业缓存调试按钮 |
| `lib/pages/about_page.dart` | `AboutPage`, `LicenseTextPage`, `reflowLicenseBytes()`, `kProjectHomeUrl` | `widget.model.prefsNotifier` | 版本信息、内联「检查更新」、转场落稳后清理旧安装包（`cleanOldUpdateFiles`）、代理设置/更新日志/源码链接/第三方许可/GPLv3 协议全文（后台 Isolate 重排 + 落稳门控） |
| `lib/pages/changelog_page.dart` | `ChangelogPage`, `ReleaseLog`, `LogSection`, `parseChangelogBytes()`, `parseChangelog()` | 本地 `_releases` + `RouteSettledStateMixin` | 后台 Isolate 解码 `CHANGELOG.md` 并预拆 `FormattedSegment`、260ms 入场滑行期展示 `CardListTransitionPlaceholder`、当前版本高亮描边 |
| `lib/pages/update_dialog.dart` | `showUpdateDialog()`, `showDownloadProgressDialog()` | `UpdateFlowController` | 单弹窗四阶段流转（`available` → `downloading` → `readyToInstall` / `error`）、`barrierDismissible: false`、Android 未知来源安装权限引导与返回自动续装 |
| `lib/pages/update_proxy_page.dart` | `UpdateProxyPage` | `widget.model.prefsNotifier` | 预设与自定义 GitHub 加速代理管理、单节点/全节点并发测速（延迟着色 Chip + API 支持诊断 Chip）、多层自动回退说明 |
| `lib/pages/reminder_page.dart` | `ReminderPage` | 设置卡：`model.prefsNotifier` + `_statusNotifier`；权限/诊断卡：`_statusNotifier` | 三卡片独立构建边界、提前量滑块（`_leadDraft` 局部草稿，松手提交 + `_queuedLeadMinutes` 串行合并）、流体云开关与收起、立即重排/预览/5s/60s 测试提醒 |
| `lib/pages/widget_settings_page.dart` | `WidgetSettingsPage`, `computeWidgetSettingsSnapshots()` | 主体：`model.prefsNotifier` + `model` + `academicNotifier`；已添加计数：`_pinnedCounts` | 三类小组件独立配置、入场后台 Isolate 并行计算真实+黄金快照、吸顶可缩放预览舞台（`SliverPersistentHeader`）、精选预设条（`_ZOrderedRow`）、滑块草稿防抖与一键恢复默认（支持撤销） |

---

## 2. 应用入口、顶层路由与生命周期契约（`main.dart`）

### 2.1 启动流程（`main()` & `CourseApp`）
1. `WidgetsFlutterBinding.ensureInitialized()`。
2. `unawaited(loadAppVersion())`：**严禁在 `runApp` 前 `await`**，避免首帧等待 asset I/O；未读完前 `appVersion` 显示 `'-'`。
3. `CourseApp` 配置：
   - `theme: buildLightTheme()`
   - `scrollBehavior: AppScrollBehavior()`（放行桌面端鼠标/触控板拖拽）
   - `locale: const Locale('zh', 'CN')`，支持 `zh_CN` 与 `en`。

### 2.2 `_AppShellState` 生命周期与存储异常提示
- **`initState()` 初始化顺序**（必须在 `_model.boot()` 之前挂载监听器）：
  1. 仅当 `defaultTargetPlatform == TargetPlatform.android` 时创建 `ReminderService(model: _model)` 与 `DesktopWidgetService(model: _model)`；桌面端二者均为 `null`。
  2. 订阅 `_model.hints.addListener(_onModelChanged)` 与 `_model.routeNotifier.addListener(_onModelChanged)`。
  3. 调用 `_model.boot()`。
  4. 注册 `AppLifecycleListener(onShow: () => unawaited(_onShown()))`。
- **前后台切换 `_onShown()`**：
  - 先等待 `await _model.onAppShown()`（跨天自动推进周次、触发静默刷新判定）。
  - 再并发执行 `_reminders?.syncNow(force: true)` 与 `_desktopWidgets?.syncNow(force: true)`（**必须 `force: true`**，防止系统 force-stop / 一键清理清空闹钟而指纹未变导致漏排）。
- **存储异常通知 `_onModelChanged()`**：
  - 当 `_model.storageNoticeEvent != _lastStorageNoticeEvent` 且非 `booting` 状态时，在 `addPostFrameCallback` 中弹出 `showAppSnackBar(type: AppSnackBarType.error, aboveDock: _model.status == AppStatus.ready, duration: 4s)`。
- **`dispose()` 顺序**：先销毁 `_lifecycle`、移除监听器、调用 `_reminders?.dispose()` 和 `_desktopWidgets?.dispose()`，**最后**调用 `_model.dispose()`。

### 2.3 顶层状态路由映射（`pageForStatus`）
`_AppShell.build` **仅监听 `_model.routeNotifier`**（局部提示、切周、刷新转圈绝不触发顶层路由重建）：

| `AppModel.status` | 附加条件 | 渲染页面 Widget | 设计原因 |
| :--- | :--- | :--- | :--- |
| `AppStatus.booting` | — | `_BootScreen` | 冷启动读盘/连接教务过渡页 |
| `AppStatus.needLogin` | — | `LoginPage(model: model)` | 未登录全屏表单，不显示 Dock |
| `AppStatus.needCaptcha` | — | `CaptchaPage(model: model)` | 验证码挑战全屏页 |
| `AppStatus.signingIn` | `model.captcha != null` | `CaptchaPage(model: model)` | 提交验证码登录中，留在验证码页 |
| `AppStatus.signingIn` | `model.captcha == null` | `LoginPage(model: model)` | 账密登录中，留在登录页 |
| `AppStatus.failed` | `schedule == null` | `LoginPage(model: model)` | 无缓存课表时回登录页（错误由右上角 `StatusPopup` 展示） |
| `AppStatus.failed` | `schedule != null` | `HomeShell(...)` | 已有离线课表时（含 `SESSION_EXPIRED` / 熔断 / 密码错）留在 `HomeShell` 保留离线数据，错误弹窗浮在右上角提供「重试 / 重新登录」，仅用户主动点击「重新登录」进入 `needLogin` 后才跳登录页 |
| `AppStatus.loading` | — | `HomeShell(...)` | 课表页铺开空网格或旧课表，进度由右上角 `StatusPopup` 展示 |
| `AppStatus.ready` | — | `HomeShell(...)` | 正常主界面（三标签页 + `FloatingDock`） |

---

## 3. 主题系统、圆角令牌、配色与页面转场（`lib/theme/*`）

### 3.1 `AppRadius` 圆角令牌规范

| 令牌常量 | 数值 (dp) | 适用场景 |
| :--- | :--- | :--- |
| `AppRadius.card` | `20.0` | 主卡片（`CardTheme`）、底部抽屉顶角（`BottomSheetTheme`）、弹出菜单外框、多行悬浮 SnackBar、Hero 焦点卡 |
| `AppRadius.medium` | `14.0` | 输入框（`InputDecorationTheme`，含淡化 `hintStyle`: `onSurfaceVariant` 40% 透明度、`14sp` 常规字重）、块级按钮（`FilledButton` / `OutlinedButton`）、提示横幅、嵌套子卡片 |
| `AppRadius.small` | `8.0` | 课表课程块（`CourseBlock`）、成绩分数徽章、小色块、内嵌列表块 |
| `AppRadius.micro` | `6.0` | 极小状态标签与徽章（如「使用中」、「未显示」、考试倒计时角标、`ChangelogCategoryBadge`） |
| `AppRadius.pill` | `999.0` | 全圆胶囊（单行 `AppSnackBar`、触控操作按钮默认圆角、分段胶囊头） |

> **特殊同心圆角**：锚定菜单外框 `20dp`，内部边距 `6dp`，因此菜单高亮胶囊采用同心圆角 `_kMenuPillRadius = 14.0`（`20 - 6 = 14`）；顶栏触控圆形按钮尺寸 `36×36`，采用半径 `18.0`。

### 3.2 `AppColors` 语义色令牌全表（25 项）

通过 `AppColors.of(context)` 获取（裸 `MaterialApp` 未挂扩展时自动回退 `AppColors.light`）：

| 令牌字段名 | `AppColors.light` 色值 | 语义与使用位置 |
| :--- | :--- | :--- |
| `success` | `Color(0xFF2E7D32)` | 成功状态图标、已登录绿勾、权限正常绿字、代理低延迟（`<600ms`）前景 |
| `successContainer` | `Color(0xFFE8F5E9)` | 代理低延迟（`<600ms`）背景 Chip |
| `warning` | `Color(0xFFB26A00)` | 未知权限状态（自启动 `ok == null`）、调试页 4xx 请求警告图标 |
| `warningStrong` | `Color(0xFFE65100)` | 代理中等延迟（`600..1499ms`）前景 |
| `warningChipBg` | `Color(0xFFFFF3E0)` | 代理中等延迟（`600..1499ms`）背景 Chip |
| `warningBannerBg` | `Color(0x26FFC107)` | 学业页「评教尚未完成」警告卡片背景 |
| `warningBannerBorder` | `Color(0x66FFA000)` | 学业页「评教尚未完成」警告卡片描边 |
| `onWarningBanner` | `Color(0xFFFF6F00)` | 学业页「评教尚未完成」警告卡片图标与文字 |
| `danger` | `Color(0xFFC62828)` | 代理不可用/高延迟（`>=1500ms`）前景 |
| `dangerContainer` | `Color(0xFFFFEBEE)` | 代理不可用/高延迟（`>=1500ms`）背景 Chip |
| `scoreExcellent` | `Color(0xFF009688)` | 学业页优秀成绩（`>=90` 分或 `'优秀'`）青绿色高亮 |
| `gridLine` | `Color(0xFFE4E6EB)` | 课表周视图网格线（`_GridPainter`） |
| `timeAxisText` | `Color(0xFF8C929B)` | 课表左侧时间轴起止时刻小字颜色 |
| `conflictCardBg` | `Color(0xFFFFE9A8)` | 调课冲突抽屉内被顶掉课程的「未显示」标签背景 |
| `conflictDot` | `Color(0xFFE6A700)` | 课表表头星期几下方的冲突提示黄点（`5×5`）与调课冲突标题警告图标 |
| `conflictBadge` | `Color(0xFFE53935)` | 课程卡片左上角冲突小红点（`6×6`，带 `1dp` 白边，Key 为 `'course-conflict-badge'`） |
| `examOngoingBg` | `Color(0xFFFF9800)` | 学业页 `NextExamHeroCard`「正在进行」徽章背景 |
| `examUrgentBg` | `Color(0xFFFF5252)` | 学业页 `NextExamHeroCard`「今天考试」徽章背景 |
| `examTomorrowBg` | `Color(0xFFFFAB40)` | 学业页 `NextExamHeroCard`「明天考试」徽章背景 |
| `onExamAccentBadge` | `Colors.white` | 上述三种紧急考试徽章上的文字颜色 |
| `categoryAdd` | `Color(0xFF2E7D32)` | `ChangelogCategoryBadge`「新增」分类色 |
| `categoryImprove` | `Color(0xFF1976D2)` | `ChangelogCategoryBadge`「优化」分类色 |
| `categoryFix` | `Color(0xFFE65100)` | `ChangelogCategoryBadge`「修复」分类色 |
| `categoryNote` | `Color(0xFF7B1FA2)` | `ChangelogCategoryBadge`「碎碎念」分类色 |
| `captchaSurface` | `Colors.white` | 验证码图片容器固定浅色画布（确保深色验证码字符在任何主题下可读） |

### 3.3 `CoursePalette` 课程色板与 FNV-1a 哈希契约

- **哈希算法（`CoursePalette.indexOf(String courseName)`）**：
  - 空字符串返回 `0`。
  - 采用 FNV-1a 32 位变体乘加哈希（避免“数学”与“学数”同字异序撞色，且与 Android 原生桌面小组件保持 100% 同构）：
    ```dart
    var hash = 2166136261;
    for (final unit in courseName.codeUnits) {
      hash = (hash ^ unit) * 16777619 & 0x7fffffff;
    }
    return hash % colors.length; // colors.length == 9
    ```
- **9 组浅色 / 深色配对色板**（`CourseColor.border` 恒为 `foreground.withValues(alpha: 0.18)`）：

| 索引 | 色相 | 浅色 `colors[i]` (`background` / `foreground`) | 深色 `darkColors[i]` (`background` / `foreground`) |
| :---: | :---: | :--- | :--- |
| `0` | 蓝 | `0xFFE6F1FB` / `0xFF0C447C` | `0xFF15293E` / `0xFF9ECAFF` |
| `1` | 青 | `0xFFE1F5EE` / `0xFF085041` | `0xFF122C26` / `0xFF8BE2CC` |
| `2` | 绿 | `0xFFEAF3DE` / `0xFF27500A` | `0xFF1B2E17` / `0xFFA9DF9A` |
| `3` | 琥珀 | `0xFFFAEEDA` / `0xFF633806` | `0xFF332613` / `0xFFF3C87D` |
| `4` | 珊瑚 | `0xFFFAECE7` / `0xFF712B13` | `0xFF352019` / `0xFFF5B7A3` |
| `5` | 粉 | `0xFFFBEAF0` / `0xFF72243E` | `0xFF361D29` / `0xFFF6B2CE` |
| `6` | 紫 | `0xFFEEEDFE` / `0xFF3C3489` | `0xFF25203E` / `0xFFC5BFFF` |
| `7` | 红 | `0xFFFCEBEB` / `0xFF791F1F` | `0xFF381C1E` / `0xFFF6B0B0` |
| `8` | 灰 | `0xFFF1EFE8` / `0xFF444441` | `0xFF272624` / `0xFFD0CEC6` |

### 3.4 Material 3 浅色主题与 `AppScrollBehavior`
- **主色与画布**：品牌种子色 `_seed = Color(0xFF3F5AA6)`（靛蓝），页面底色 `_canvas = Color(0xFFF6F7F9)`，`scheme.surfaceContainerLowest` 显式覆盖为 `Colors.white`（纯白卡片浮在浅灰画布上）。
- **全局去水波纹**：`splashFactory: NoSplash.splashFactory`。
- **卡片裁剪**：`CardThemeData.clipBehavior = Clip.antiAlias`（防止内部 `InkWell` hover/点击画出直角阴影；纯展示型列表如 `ChangelogPage` 单卡显式设 `clipBehavior: Clip.none` 省光栅开销）。
- **`AppScrollBehavior`**：重写 `dragDevices` 放行 `touch`、`mouse`、`trackpad`、`stylus`、`invertedStylus` 五类指针，使桌面端 Windows 鼠标可拖动课表翻周与 `CupertinoPicker` 时间轮。

### 3.5 连续双向缓动页面转场（`_SlideTransitionsBuilder`）
- **时长与曲线**：正向 `transitionDuration = 260ms`，反向 `reverseTransitionDuration = 240ms`，基准曲线 `Curves.easeOutCubic`。
- **全宽位移 + 视差联动（零 `Opacity` / 零 `SnapshotWidget`）**：
  - 新页面（非 `fullscreenDialog`）从右侧屏外 `Offset(1.0, 0.0)` 滑入 `Offset.zero`（`fullscreenDialog` 从底部 `Offset(0.0, 1.0)` 滑入）。
  - 旧页面（包括首页 `route.isFirst`）随 `secondaryAnimation` 向左视差平移至 `Offset(-0.24, 0.0)`（`_exitParallaxDistance = 0.24`）。
- **连续双向缓动 `_ContinuousCurveAnimation`**：
  - 正向 `0 -> 1` 与完整反向 `1 -> 0` 均使用 `Curves.easeOutCubic`（起步快、收尾柔和减速，解决 Flutter 默认反向变成 `easeInCubic` 导致末段加速撞停消失的问题）。
  - 当动画在半途反转方向（`forward <-> reverse`）时，以**当前时刻的视觉进度 `_evaluate(raw)`** 作为新起点 `_fromVisual`，无缝重映射到目标端点 `1.0` 或 `0.0`，折返瞬间零跳变。
- **轻量边缘阴影与背层微暗遮罩（无离屏 `saveLayer`）**：
  - `_EdgeShadowPainter`：在新页面左边缘外侧 `-16dp..0` 分 8 条纯色竖带（`_shadowWidth = 16.0, _bandCount = 8`）二次方递增绘制微阴影（峰值 alpha `0.08`，接近终点时 `edgeFade = ((1.0 - p) * 6.0).clamp(0.0, 1.0)` 平滑消隐），不触发渐变 Shader 编译。
  - `_RouteScrimPainter`：在旧页面前景绘制单矩形微暗遮罩（峰值 alpha `0.06 * p`）。
- **图层隔离与路由级 `AppMenuScope`**：
  - 转场子树结构：`SlideTransition(_primaryOffset) -> SlideTransition(_secondaryOffset) -> CustomPaint(_EdgeShadowPainter) -> CustomPaint(foregroundPainter: _RouteScrimPainter) -> RepaintBoundary -> AppMenuScope(child: widget.child)`。
  - `RepaintBoundary` 确保 260ms 转场逐帧重绘阴影和遮罩时，进出双方页面内容 **0 次重绘**（由 `page_transition_test.dart` 守护）。
  - 路由级 `AppMenuScope` 位于 `SlideTransition` 内部：二级页入场途中打开菜单会随页面一同滑入落位；页面退场或被上层路由覆盖时自动收起菜单。

---

## 4. 核心自定义物理组件与渲染架构（`lib/widgets/*`）

### 4.1 `HomeShell` + `FloatingDock` 单一运动源与液态透镜物理契约

#### (1) 单一运动源（Single Motion Source）与横向轨道 `_ShellPager`
- **位置解耦**：`HomeShell` 不使用 `PageView`，而是通过 `_ShellPager`（`Stack` + `Transform.translate`）承载 `[SchedulePage, AcademicPage?, SettingsPage?]` 三页。
- **唯一驱动源**：`_ShellPager` 自身没有任何动画控制器；其轨道位置 `_positionNotifier`（`0.0` = 课表，`1.0` = 学业，`2.0` = 设置）完全由 `FloatingDock.onPillProgress`（归一化进度 `0.0..1.0`）通过 `followPill(progress)` 逐帧写入：`_positionNotifier.value = (progress * maxPage).clamp(0.0, maxPage)`。
- **按需单页懒建与常驻**：
  - 冷启动首帧仅构建 `_schedulePage`（`AcademicPage` 与 `SettingsPage` 槽位为 `SizedBox.shrink()`）。
  - 当指针在 Dock 上按下、拖入某分段（`onTargetIndexHint`）或提交目标页（`onIndexSelected`）时，仅懒建对应的单页（例如从课表 `0` 直达设置 `2` 时，**绝不提前构建中间的学业页 `1`**）。
  - 一旦建好即常驻 Widget 树，切换标签页时保留滚动位置与展开状态。
- **抢跑交互解锁与离场锁死**：
  - 点击松手、拖拽落位或 `animateToIndex` 确定目标页时，立即触发 `onIndexSelected` 更新 `HomeShell._index` 与 `_ShellPager.setActiveIndex(index)`。
  - 每一页包裹结构：`Transform.translate(key: ValueKey('shell-page-$index')) -> AppMenuScope(activeListenable: _pageActiveNotifiers[index]) -> IgnorePointer(ignoring: _interactionBlocked || index != widget.index) -> TickerMode(enabled: index == widget.index) -> RepaintBoundary(child: page)`。
  - 因此**滑行动画尚未停稳前，目标页已立即可点击、可滚动、可推入二级页，而离场页已立即 `IgnorePointer` 锁死**；当手指按住 Dock 预览（`onPointerActiveChanged(true)`）时，`_interactionBlocked = true` 暂锁全部内容区防误触，松手即刻放行。

#### (2) `FloatingDock` 几何与弹簧物理参数
- **尺寸常量**：`FloatingDock.height = 58.0`，`FloatingDock.bottomMargin = 16.0`，底部安全留白 `FloatingDock.contentInset(context) = 58 + 32 + MediaQuery.paddingOf(context).bottom`。
- **窄屏自适应布局**：理想单项宽 `74.0`、间距 `10.0`、左右内边距 `6.0`；窄屏按比例压缩（缩放比下限 `0.58`，间距下限 `2.0`）。
- **分段判定 vs 落点测量**：
  - “松手切到哪一页”按胶囊总宽等分 `1/n` 判定（`_indexAt(x)`，阈值在等分点上）。
  - 指示块静态落点 `_rects` 通过各按钮 `GlobalKey` + `localToGlobal` 实测（差值 `> 0.5px` 才更新）。
- **四大物理通道**：

| 物理通道 | 弹簧 / 振子参数 | 物理行为与数学契约 |
| :--- | :--- | :--- |
| **中心滑动 `_slide`** | `_slideSpring = SpringDescription(mass: 1.0, stiffness: 1150.0, damping: 68.0)`（过阻尼，$\zeta \approx 1.002$）<br>`_slideTolerance = Tolerance(distance: 2e-3, velocity: 4e-2)` | 驱动指示块中心从 `_from` 到 `_to`（`0 -> 1`）。**同向续速上限** `_maxMonotonicSlideVelocity = 31.5`（略低于慢特征根 $|r_1| \approx 31.55$），数学上保证同向打断继承速度时位移严格单调、零过冲；**反向折返**时初速归零立即掉头，无反冲。 |
| **拖动追随 `_followX`** | `_followRate = 28.0`（指数趋近 `k = 1 - exp(-28 * dt)`） | 拖动时透镜中心以轻微滞后追随手指 `_dragX`（一帧追上约 37%，差距 `< 0.05px` 对齐），帧率无关。 |
| **透镜鼓起 `_lift`** | 鼓起 `_liftUpSpring(mass: 1, stiffness: 520, damping: 22)`<br>回落 `_liftDownSpring(mass: 1, stiffness: 420, damping: 36)` | 常态 `0.0`，鼠标悬停 `0.25`，按下/拖动 `1.0`。鼓起时宽 `+16%`、高 `+34%`（从 `46dp` 鼓出至约 `62dp`，超出 `58dp` Dock 上下沿，`Stack` 设 `clipBehavior: Clip.none`），整条 Dock 容器同步微呼吸放大 `1 + 0.015 * t`。 |
| **速度形变振子 `_stretch`** | 二阶欠阻尼振子：刚度 `_stretchK = 340.0`，阻尼 `_stretchC = 15.0`（$\zeta \approx 0.4$），满形变速度 `_fullStretchSpeed = 1500.0 px/s` | 由透镜真实移动速度 `v = (cx - _lastCx) / dt` 驱动目标形变 `target = (v / 1500).clamp(-1.0, 1.0)`。运动中沿水平拉长 `w *= 1 + 0.30 * |s|`、纵向收窄 `h *= 1 - 0.14 * |s|`、前缘领先偏移 `lead = s * base.width * 0.08`；停下时反向过冲挤压再回圆。**纯视觉形变，不影响上报给页面的 `_livePillRect.center.dx`**。 |
| **边缘橡皮筋 `_edge`** | `_edgeSpring(mass: 1, stiffness: 420, damping: 18)` | 手指拖出胶囊两端时，整条 Dock 水平阻尼位移 `_rubber(over, 10.0) = sign * 10 * (1 - exp(-|over| / 60))`。 |

#### (3) 液态透镜三层光学裁剪与后台停帧收敛
- **连续曲率超椭圆轮廓**：`_buildLensPath(rect)` 使用 Flutter `RSuperellipse.fromRectAndRadius(rect, Radius.circular(min(w, h) / 2))` 构建 FlClash 风格连续圆角胶囊。
- **三层 Stack 合成（避免重影与色阶下陷）**：
  1. `_LensBackdropPainter`：静止态 `restColor`（`primary 11%` 预混合 `surfaceContainerLowest`）与鼓起态 `lensColor`（`primary 4%` 预混合白底再取 `92%` 不透明度）按 `Curves.easeOut.transform(lift)` 插值填充。
  2. `_OutsideLensClipper`：以 `PathFillType.evenOdd`（外框 `bounds.expandToInclude(rect).inflate(40)` 减去 `lensPath`）将透镜区域内部的底层灰色图标/文字完全掏空。
  3. `_LensForegroundPainter`：在 `lensPath` 裁剪区内绘制预排版的 `_LensGlyphEntry`（主色 `activeIcon` + `w600` 文字），**每项以自身 `itemRect.center` 为原点原地放大 `zoom = 1.0 + 0.28 * elev`（绝不随透镜横向漂移）**，外缘叠加细描边（线宽 `0.9 + 0.2 * elev`）。
- **停帧后台静默收敛 `_settleImmediatelyForDisabledTickers()`**：
  - 当首页被不透明二级页完全遮挡导致 `TickerMode` 变为 `false` 时，Dock 在 post-frame 回调中立即停止所有动画并收敛到目标页（若遮挡时手指仍按在 Dock 上未松手提交，则回退到已提交的 `widget.index`；若已提交滑行，则直达 `_preview`），确保返回首页时绝不卡在半路。

---

### 4.2 `TactileButton` 体系、`TactileAppBar` 四层合绘与 `_ZOrderedRow`

#### (1) `TactileSurfaceButton` 物理手感与菜单交接
- **表面风格 `TactileSurfaceStyle`**：
  - `elevated`：画布/顶栏上的纯白按钮（`surfaceContainerLowest` + `BoxShadow(rgba(0,0,0,0.045), blur: 8, offset: (0,2))`）。
  - `tinted`：纯白卡片内部的浅灰胶囊按钮（`surfaceContainerHigh` `alpha: 0.56`，禁用 `0.28`，无阴影）。
  - `transparent`：仅保留触控缩放与微拖拽手感，不绘底色与阴影（用于 `TactileActionButton`、彩色 FAB 等）。
- **按压放大（无下沉缩小）**：
  - 按压弹簧 `_pressSpring(mass: 1, stiffness: 1100, damping: 40)`，释放弹簧 `_releaseSpring(mass: 1, stiffness: 760, damping: 46)`。
  - 按下目标 `_press = 1.0`，桌面端鼠标悬停 `_press = 0.22`。
  - 自适应放大振幅：`pressAmplitude = (0.07 + 8.4 / max(24.0, extent)).clamp(0.095, 0.26)`，缩放倍率 `scale = 1.0 + pressAmplitude * effectiveP`（36dp 按钮按下约放大 `26%`）。
- **跟手微拖拽与滚动容器避让**：
  - 拖拽回弹弹簧 `_rubberSpring(mass: 1, stiffness: 740, damping: 45)`。
  - 阻尼公式：`_rubberDelta(delta, maxPull) = sign * maxPull * (1 - exp(-|delta| / 36.0))`，水平最大拉动 `6.0dp`，垂直最大拉动 `7.0dp`。
  - 若按钮位于 `Scrollable` 内部且无自接管 `onTap`/`onMenuOpen`（如内嵌 `IconButton` 的步进器），滑动距离超过 `_touchSlop` 即调用 `_cancelPointer()` 取消按压效果；固定位置按钮（如顶栏）则全程保持微拖拽跟随直至松手。
- **手势竞技场独占 `_TactileArenaRecognizer`**：
  - 自带 `onTap` 或 `onMenuOpen` 的 `TactileSurfaceButton` 内部挂载 `_TactileArenaRecognizer`（继承 `PrimaryPointerGestureRecognizer`），确保嵌套在 `ListTile` / `InkWell` 卡片右侧时（如作息表更多按钮、调课删除按钮）点击或长按**独占手势竞技场，绝不穿透触发外层卡片点击**。
- **三种方式触发锚定菜单（`onMenuOpen`）**：
  1. **短按点击**：手指在 `paintBounds.inflate(6.0)` 或 `_touchSlop` 内抬起，调用 `onMenuOpen(context, null)`。
  2. **按住 190ms 长按**（非鼠标设备）：`_holdTimer` 到期触发 `_openMenuWithDrag(pointer)`，写入全局交接坐标 `activeTactileDragStart = (pointer, _lastPos)` 并调用 `onMenuOpen(context, pointer)`。
  3. **按住直接下拉**：`delta.dy > 14.0 && delta.dy > delta.dx.abs() * 0.9` 时无需等待 190ms，立即触发 `_openMenuWithDrag(pointer)` 无缝交接手指给菜单。
- **原按钮形变隐退 `activeAppMenuMorph`**：
  - 当按钮对应的菜单展开/收起时，监听全局 `activeAppMenuMorph`（`(RenderObject?, double)`）：
  - 在 `morphT` 的前 `14%`（`_kMorphPressEnd = 0.14`）内平滑消退按压放大倍率 `effectiveP`，并在前 `32%`（`_kMorphFadeEnd = 0.32`）内用 Hermite 平滑步进 `u * u * (3 - 2 * u)` 将按钮 `morphOpacity` 从 `1.0` 降至 `0.0`，实现“原轮廓原地融入菜单、无缩小残影”。

#### (2) `TactileAppBar` 与 `TactileSurfaceScope` 四层合绘架构
- **痛点背景**：顶栏相邻的纯白 `elevated` 按钮在按压放大或微拖拽重叠时，若各自独立绘制阴影和白底，后绘制按钮的阴影会脏压在先绘制按钮的白底上，且默认 `AppBar` 56dp 高度会硬裁剪放大后的按钮边缘。
- **解决方案**：`TactileAppBar` 默认设置 `clipBehavior: Clip.none` 解除 56dp 硬裁剪，并用 `TactileSurfaceScope`（底层为 `_RenderTactileSurfaceScope` + `_RenderTactileSurfaceSlot`）包裹 `AppBar`。
- **`_RenderTactileSurfaceScope.paint` 严格按四层顺序合绘**：
  1. **第 1 层（静态背景与标题）**：调用 `super.paint` 绘制 AppBar 背景与标题文字；此时组内所有 `elevated` 状态的 `_RenderTactileSurfaceSlot` 仅向 `coordinator.frameSlots` 登记自身顺序，跳过直接绘制。
  2. **第 2 层（全部按钮阴影）**：遍历所有可见 slot（`morphOpacity > 0.001`），统一绘制 `slot.paintShadows(canvas)`，使所有阴影永远位于所有白底之下。
  3. **第 3 层（全部按钮纯白底面）**：遍历所有 slot 统一绘制 `slot.paintSurface(canvas)`，相邻按钮放大重叠时纯白底面自然无缝融合。
  4. **第 4 层（全部按钮前景图标与文字）**：遍历所有 slot 调用 `slot.paintForeground`（`0 < morphOpacity < 0.999` 时用局部 `saveLayer` 控制透明度，不使用 `FadeTransition` 避免 `RenderAnimatedOpacity` 动态改变 `needsCompositing` 导致图层跳回原点）。

#### (3) 派生触控按钮与 `_ZOrderedRow`
- **`TactileIconButton`**：外层 `TactileSurfaceButton`（默认 `36×36`、圆角 `18`）+ 内层无波纹原生 `IconButton`（保持 `find.widgetWithIcon(IconButton, ...)` 测试句柄与无障碍语义 100% 兼容）。
- **`TactileBackButton`**：左偏 `12dp` 的 `36×36` 圆胶囊 + 内层原生 `BackButton`（兼容 `find.byType(BackButton)` 与 `tester.pageBack()`）。
- **`TactileActionButton`**：4 种变体 `TactileActionVariant { filled, tonal, outlined, text }`，外层 `TactileSurfaceButton(filled: false)` + 内层原生 `FilledButton` / `FilledButton.tonal` / `OutlinedButton` / `TextButton`。
- **`_ZOrderedRow` & `_ZOrderedItem`（位于 `lib/pages/widget_settings_page.dart`）**：
  - 自定义 `_RenderZOrderedFlex`：当子项 `_RenderZOrderedItem` 收到 `PointerDownEvent` 或未按下的 `PointerEnterEvent` / `PointerHoverEvent` 时，将自身设为父容器的 `elevatedChild`。
  - 在 `paint` 时最后绘制 `elevatedChild`，在 `hitTestChildren` 时最先测试 `elevatedChild`，确保水平并排的紧凑胶囊按钮（如小组件类型切换栏、精选预设横条）在按压放大及回弹期间始终完整盖在左右邻居之上，绝不被右侧兄弟裁剪遮挡。

---

### 4.3 `AppMenu` 与 `AppMenuScope` 双轴形变弹簧、空间绑定与选择性遮罩

#### (1) `AppMenuScope` 页面空间绑定与活跃度门控
- **两层挂载位置**：
  1. 路由级：`_SmoothSlidePageTransition.build` 在每个 `PageRoute` 的 `SlideTransition` 内部包裹 `AppMenuScope`。
  2. 标签页级：`HomeShell` 的 `_ShellPager` 在每个标签页的 `Transform.translate` 内部、`TickerMode` 外部包裹 `AppMenuScope(activeListenable: _pageActiveNotifiers[index])`。
- **空间跟随（`CompositedTransformTarget` + `LayerLink`）**：
  - `AppMenuScope` 持有 `LayerLink` 与 `_hostKey`。`showAppMenu` 测量按钮相对于 `scope.hostRenderBox` 的本地锚点坐标 `anchor`，并将菜单卡片挂载在 `CompositedTransformFollower(link: layerLink, offset: targetRect.topLeft)` 下。
  - **效果**：在 Dock 切页滑行中途或二级页推入滑行中途打开菜单，菜单始终锚定在该页面的本地坐标系内，随页面一同平滑滑入最终落点；切走页面时，已打开的菜单也随原页面一同划走并收起，绝不滞留覆盖在新页面上。
- **五重活跃度门控 `_computeEffectiveActive()`**：
  - 当以下任一条件不满足时，`scope.isActive` 立即变为 `false`：
    1. `widget.active == false`
    2. `widget.activeListenable?.value == false`（如在 `HomeShell` 中非当前页，或手指正按在 Dock 上预览 `_interactionBlocked == true`）
    3. 父级 `_parentController?.isActive == false`
    4. `isRouteActiveForAppMenu(_modalRoute) == false`（路由 `!isCurrent`、`!isActive`、`navigator.userGestureInProgress == true`、主动画处于 `reverse`/`dismissed`、或次级动画 `secondaryAnimation` 处于 `forward`/`completed`）
  - **失活联动**：一旦 `isActive` 变 `false`，`TactileSurfaceButton` 立即取消未完成的 190ms 长按定时器与按压态；`AppMenuScope` 立即调用 `_dismissHostedSessions` 收起所有已挂载或尚处于第 0 帧预测量期的菜单（若路由被上层新路由覆盖 `_isRouteCoveredByAnotherRoute` 或 `TickerMode` 已停帧，则 `immediate: true` 立即清理 `OverlayEntry`，绝不浮在新推入的页面/弹窗之上）。

#### (2) `RenderMenuMorphBox` 双轴容器形变与果冻胶囊物理参数
- **两阶段零跳变测量**：
  - 第 0 帧（`_targetRect == null`）：在 `_FallbackMeasureLayout` 中以 `Opacity(opacity: 0.0)` 测出菜单真实宽高与各项 `_itemRects`。
  - 第 1 帧起：计算 `_targetRect`（默认与触发按钮顶边对齐原位覆合生长，右半屏右对齐 `alignX = 1.0`、左半屏左对齐 `alignX = -1.0`、`centerHorizontally: true` 时中轴线对齐，底部空间不足时向上展开 `_openUp = true`），交由自定义渲染对象 `RenderMenuMorphBox` 在渲染层直接做几何插值（**动画全程零 Widget rebuild、零 layout 重算，并复用 `ClipRRectLayer` / `TransformLayer` / `OpacityLayer` 句柄**）。
- **菜单弹簧参数全表**：

| 动画控制器 | 弹簧参数 (`SpringDescription`) | 阻尼比 / 收敛时长 | 作用描述 |
| :--- | :--- | :--- | :--- |
| `_widthMorph`（展开） | `mass: 1.0, stiffness: 960.0, damping: 41.0` | $\zeta \approx 0.66$, `~325ms` | 容器宽度从 `anchor.width` 舒展至 `targetRect.width`（略先于高度打开） |
| `_heightMorph`（展开） | `mass: 1.0, stiffness: 820.0, damping: 37.5` | $\zeta \approx 0.65$, `~345ms` | 容器高度从 `anchor.height` 舒展至 `targetRect.height` |
| `_widthMorph`（收起） | `mass: 1.0, stiffness: 1650.0, damping: 74.0` | $\zeta \approx 0.91$, `~160ms` | 收起时继承当前速度缩回 `anchor.width` |
| `_heightMorph`（收起） | `mass: 1.0, stiffness: 1900.0, damping: 80.0` | $\zeta \approx 0.92$, `~160ms` | 收起时继承当前速度缩回 `anchor.height` |
| `_pillSlide` | `mass: 1.0, stiffness: 1150.0, damping: 46.0` | $\zeta \approx 0.68$ | 短菜单高亮胶囊在菜单项间滑动的果冻弹簧 |
| `_pillPresence` / `_pillStretch` / `_pressLift` | `mass: 1.0, stiffness: 960.0, damping: 42.0` | $\zeta \approx 0.68$ | 高亮胶囊浮现/隐去、跨项纵向拉伸形变，以及整卡按压放大（`liftSpan` `3.2%..4.8%`） |
| `_rubberAnim` | `mass: 1.0, stiffness: 880.0, damping: 50.0` | $\zeta \approx 0.84$ | 手指滑出菜单边界时的整卡橡皮筋跟随（水平上限 `8dp`，垂直上限 `10dp`）与松手回弹 |

- **收起中途同按钮重开无缝接管（`handoffClosingSession`）**：
  - 当菜单正在收起（`existing.closing == true`）且用户再次点击同一触发按钮时，新菜单直接继承旧菜单此刻的 `_widthMorph.value/velocity` 与 `_heightMorph.value/velocity` 连续反向展开，零闪烁、零跳变。
- **短菜单 vs 可滚动长菜单交互区分**：
  - **短菜单（`!_isScrollable`）**：支持一指按住上下滑动选单、跨分割线按中线自动吸附最近可用项（`_nearestSelectable`）、滑出菜单边界取消高亮（松手保持菜单打开并弹性复位，不误选不关闭）。
  - **长菜单（`_isScrollable`，如 18 周选周菜单、多学期选择菜单）**：手势交给 `SingleChildScrollView` 滚动不误选；按住条目时在 `_MenuTile` 内部直接绘制同源圆角胶囊，常态已选中项显示主色文字与右侧对勾。
- **选择性遮罩 `_MenuBarrier` 与 Dock 最高优先级直达**：
  - `_RenderMenuBarrier.hitTest` 调用 `FloatingDock.hitTestGlobalPosition(globalPosition, route: modalRoute)`：
    - 点击/拖拽落在菜单外**非 Dock 区域**（课表卡片、翻周 PageView、其他按钮）：遮罩拦截事件并调用 `onDismiss()` 收起菜单，**绝不向底层穿透**。
    - 点击/拖拽落在**当前路由的 `FloatingDock` 胶囊内**：遮罩返回 `false` 直接放行给 Dock 响应一指切页，同时全局指针路由 `_handleGlobalPointer` 捕获该 `PointerDownEvent` 同步启动菜单收起动画。

---

### 4.4 `WeekPager` 锚点单页物理、跨周借位滑入与空闲帧邻近周预热

#### (1) `WeekPagerController` 与 `_WeekPagerPosition` 四大物理改造（`lib/widgets/week_pager.dart`）
1. **以“起手页 `_gestureOrigin`”为锚（一次滑动只翻一页）**：
   - Flutter 原生 `PageController` 用 `currentPage + 0.5` 四舍五入，当手指横扫拖过 1.0 页再松手时会变成 `1.0 + 0.5 -> 2` 跳页。
   - `_WeekPagerPosition._snapPixels(velocity)` 改为以起手页 `origin` 为锚：
     - 快速滑动（`velocity != 0`）：目标固定为 `origin + (velocity > 0 ? 1 : -1)`（若手指已物理拖过 1 页以上则取 `current.roundToDouble()`，不往回拽）。
     - 慢速松手（`velocity == 0`）：拖行零头达到 `_kFlipFraction = 1 / 3`（三分之一页宽）即翻往下一页，不到 `1/3` 回原页。
2. **按下不冻结在途翻页（`_IgnoredHold`）**：
   - 重写 `hold(VoidCallback holdCancelCallback)` 返回 `_IgnoredHold`：手指按下时不打断正在运行的翻页动画或惯性，解决连续快滑时第二指按下把上一页冻结在半页再退回的吞页问题。
3. **零死区延迟拖拽（`_DeferredDrag`）**：
   - 位置静止时（`threshold: 0`）：手指一动立即接管，配合 `PageView(dragStartBehavior: DragStartBehavior.down)` 消除 `kTouchSlop` 18dp 起拖死区，慢拖 1:1 跟手。
   - 翻页动画或惯性在途时（`threshold: kTouchSlop`）：累计净位移达到 `kTouchSlop` 才接管，并一次性补上已走位移，防止纯按住掐断翻页。
4. **利落的落页弹簧与跨多周借位滑入**：
   - 手势松手落页弹簧：`_kSnapSpring = SpringDescription.withDurationAndBounce(duration: Duration(milliseconds: 170), bounce: 0)`（约 250ms 内完全停稳，零过冲）。
   - 箭头/选周/回本周程序化翻页时长：`_flipDuration = Duration(milliseconds: 180)`，曲线 `Curves.easeOut`。
   - **跨 4 周及以上（`absDelta > 3.0`）**：调用 `animateToPageWithSkip(target, duration: 180ms, curve: Curves.easeOut, frontPages: 2.0, backPages: 1.0)`（底层 `_SkipJumpScrollActivity`）：在单一 180ms 曲线内，前段连续滑出 `2` 页，中段无缝重映射到目标页前 `1` 页继续减速滑入目标页，视觉节奏与相邻周翻页完全一致且不闪现中间十几周。

#### (2) `_shownWeek` 与 `model.week` 双轨分离 + 邻近周空闲预热（`lib/pages/schedule_page.dart`）
- **滑动期顶栏轻量更新，停稳后再写 `model.week`**：
  - `PageView.onPageChanged` 在滑动跨过半页时**只更新 `_shownWeek.value`**（仅触发顶栏 `_WeekBar` 与右下角 `_TodayFab` 两个小组件局部刷新），**绝不在滑动中途调用 `model.goToWeek()`**。
  - 直到 `ScrollEndNotification` 或程序动画结束调用 `_settleToPage()` 时，才通过 `_writeWeek(week)` 写回 `model.goToWeek(week)`（期间置 `_syncingFromPage = true` 忽略自身触发的回环通知）。
- **空闲帧邻近周课程块预热（`_scheduleNeighborPrewarm`）**：
  - 当前周 `_WeekView` 在 `LayoutBuilder` 中采集真实排版快照 `CourseBlockLayoutSnapshot`（含 `DefaultTextStyle`、`boldText`、`textScaler`、`dayWidth`、`rowHeight`、`rows` 等），并在 post-frame 启动预热。
  - 静止 `90ms` 后（`_prewarmDelayTimer`），按 `[currentWeek + 1, currentWeek - 1, currentWeek + 2, currentWeek - 2]` 顺序，每帧 post-frame 切片预热（每片最多 `chunkSize = 3` 门课或耗时达到 `2ms` 即让出帧，调用 `WidgetsBinding.instance.ensureVisualUpdate()` 推进下一帧），调用 `CourseBlock.prewarmEntry` 将邻近周的 `_BlockPlan` 填入 LRU 缓存。一旦用户开始拖拽或翻页，立即调用 `_cancelNeighborPrewarm()` 中止预热让出算力。

---

### 4.5 `CourseBlock` 排版预算求解器、`letterSpacing: 0` 与 `1e-4` 容差契约

`lib/widgets/course_tile.dart` 中的 `CourseBlock` 与 `_BlockPlan` 是课表渲染最核心的不变量区域：

1. **样式完全对齐铁律（`letterSpacing: 0` + 预 Merge）**：
   - Material 3 的 `DefaultTextStyle`（`bodyMedium`）默认带有 `letterSpacing: 0.25`，而 `TextPainter` 不会自动 merge `DefaultTextStyle` 也不会自动响应系统“粗体文字”（`MediaQuery.boldTextOf(context)`）。
   - 因此 `CourseBlock.titleStyle`（`11sp, height: 1.25, w500, letterSpacing: 0`）与 `CourseBlock.detailStyle`（`9sp, height: 1.2, letterSpacing: 0`）**必须显式锁定 `letterSpacing: 0`**，并在 `build` 与 `prewarmEntry` 中提前与 `DefaultTextStyle.of(context).style` 及 `boldText` 合并，将**同一份 `effectiveTitleStyle` / `effectiveDetailStyle`** 同时传给 `_BlockPlan.solve`（`TextPainter`）和 `Text` 组件。
2. **内框尺寸精确扣除**：
   - 外框尺寸：`top = (start - 1) * rowHeight + 2`，`height = (end - start + 1) * rowHeight - 4`（下限 `26dp`）；并排冲突分栏 `gap = 2.5dp`，`width = (dayWidth - 4) / slot.total - (slot.total > 1 ? 2.5 : 0)`（下限 `24dp`）。
   - 内框可用宽高：扣除左右/上下内边距 `_paddingX = 3, _paddingY = 3`（共 `6dp`）及 `1dp` 描边（共 `2dp`），即 `innerWidth = outerWidth - 8.0`，`innerHeight = outerHeight - 8.0`。
3. **`_BlockPlan.solve` 四步预算求解算法**：
   - **Step 0（实测自然行数）**：用 `TextPainter.computeLineMetrics().length` 分别测出 `titleNeeded`、`teacherNeeded`、`locationNeeded`（地点经 `roomOnly()` 剥离校区前缀，只留房间号如 `M1-239`）。
   - **Step 1（装不下时按优先级砍行）**：当 `usedHeight() > height + 1e-4` 时，严格按 **「课程名（先压到保底 1 行）→ 教师（整条清零让位）→ 地点（逐行砍至清零）→ 课程名清零」** 的顺序缩减。
   - **Step 2（富余空间回填）**：按 **「地点 → 教师 → 课程名」** 顺序尝试往回加行，只要 `fits()` 为真即保留。
   - **Step 3（释放纵向富余空间给课程名）**：若 `titleLines >= titleNeeded` 且剩余高度 `remaining = height - usedHeight() > titleMeasure.lineHeight`，将 `(remaining / lineHeight).floor()` 追加给 `titleLines`，彻底兜底亚像素临界换行，防止“下面有空白却出省略号”。
4. **IEEE 754 浮点容差与 512 容量 LRU 缓存**：
   - `fits()` 判定：`usedHeight() <= height + _epsilon`，其中 **`_epsilon = 1e-4`**（仅消除双精度浮点加法尾数误差，严禁放大导致真溢出）。
   - `_BlockPlan._cache`：基于 `LinkedHashMap<_BlockPlanCacheKey, _BlockPlan>` 的 LRU 缓存，容量上限 `_maxCacheEntries = 512`，宽高按毫米级整数 `(width * 1000).round()` 索引，颜色归一化为 `_cacheDummyColor`（使不同颜色但同尺寸同字体的卡片共享排版缓存）。

---

### 4.6 其余公共组件契约（`StatusPopup` / `AppSnackBar` / `TimeWheelPicker` / `DesktopWidgetPreview` / `PageSkeleton` 等）

- **`StatusPopup`（`lib/widgets/status_popup.dart`）**：
  - 三个作用域：`HintScope.global`（挂载在 `HomeShell` 与 `LoginPage` 顶层右上角，切页不跟随平移）、`HintScope.schedule`（挂载在 `SchedulePage` 右上角，随课表页横向平移）、`HintScope.academic`（挂载在 `AcademicPage` 右上角，随学业页横向平移）。
  - **退避规则**：当 `model.isGlobalPopupActive == true` 时，`schedule` 与 `academic` 局部气泡自动返回 `null` 退避隐藏，严防右上角双气泡叠字冲突。
  - **交互规则**：
    - `AppStatus.needLogin` / `needCaptcha` 下 `HintScope.global` 返回 `null`（不挡登录表单）。
    - `AppStatus.failed` 时显示动作栏：当 `canRetry`（学业作用域恒为 `true`，全局作用域绑定 `model.canRetryError`，即 `schedule != null && errorCode != 'WEB_LOGIN_REQUIRED'`）时展示「调试」（`onOpenDebug`）与主动作按钮：文案依据 `model.needsReloginError`（非切校失败且为 `SESSION_EXPIRED` / `INVALID_CREDENTIALS`）显示 `'重新登录'` 或 `'重试'`，点击统一委托 `model.retry()`（优先重走失败的切校目标 `_pendingSchoolSwitchUrl`，其次 `needsReloginError` 调用 `retryAfterSessionLoss()` 跳登录页，其余走前台 `_loadSchedule(forceForeground: true)` 并在成功后保留 1.5s `'已更新'` 提示）；无课表或 `WEB_LOGIN_REQUIRED` 时不展示主动作按钮。
    - 当 `model.isAcademicUpdateHint == true`（后台检测到新成绩/新考试）时，点击全局气泡会清除提示并调用 `onNavigateToAcademic`（驱动 `FloatingDock.animateToIndex(1)` 平滑切到学业页）。
- **`AppSnackBar`（`lib/widgets/app_snack_bar.dart`）**：
  - `showAppSnackBar` 每次弹出前先调用 `messenger.hideCurrentSnackBar()` 防排队积压。
  - 内部 `_AppSnackBarPill`（最大宽 `420dp`）预先通过 `TextPainter(maxLines: 1)` 测量正文是否单行放得下：单行采用 `999.0dp` 全圆胶囊，超出一行自动切换为 `20.0dp` 圆角矩形卡片。
  - `aboveDock: true` 时底部外边距为 `FloatingDock.contentInset(context) + 4`，无 Dock 子页为 `40 + MediaQuery.paddingOf(context).bottom`。
- **`TimeWheelPicker`（`lib/widgets/time_wheel_picker.dart`）**：
  - `_Wheel` 在每个 item 上挂载 `Listener(behavior: HitTestBehavior.opaque, onPointerSignal: _onPointerSignal)`，通过 `GestureBinding.instance.pointerSignalResolver.register` 抢在 `Scrollable` 之前吃掉鼠标滚轮事件，使 Windows 鼠标滚轮在整个可见滚轮区域内统一**一次只走一格（120ms `Curves.easeOut`）**。
  - 7 个导出选择器：
    1. `showTimeWheel`：返回从 `00:00` 起的分钟数（自动 `snapToFiveMinutes`）。
    2. `showTimeRangeWheel`：四列起止时间轮，当 `_end <= _start` 时禁用「确定」按钮并提示 `'结束时间要晚于开始时间'`（不静默篡改另一列滚轮）。
    3. `showDurationWheel`：5 分钟步进时长轮（默认 `5..180` 分钟）。
    4. `showMonthDayWheel`：月日两列轮（换月时用 `ValueKey<int>(_month)` 重建日列并自动夹取大小月/闰年天数）。
    5. `showBigBreakWheel`：第几节后 + 休息时长两列轮。
    6. `showSectionCountWheel`：上午/下午/晚上三列节数轮，确定时校验总节数 `1 <= total <= maxSections (20)`。
    7. `showWeekCalibrationWheel`：周次校准轮（`1..maxWeek`，点击底部额外按钮「恢复默认估算」返回 `0`，取消返回 `null`）。
- **`DesktopWidgetPreview`（`lib/widgets/desktop_widget_preview.dart`）**：
  - 外层强制包裹 `MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling))`，与 Android 原生 `COMPLEX_UNIT_DIP` 保持一致，免疫系统 2.0× 超大字体二次放大。
  - `_PreviewColors.resolve` 与 Android `WidgetThemeResolver.kt` 像素级同构：
    - 边框随 `backgroundOpacity` 平滑淡出（`opacity <= 0.01` 时完全透明无边框，圆角避让 `_cornerClearance` 归零）。
    - 低不透明度（`< 0.35`）通过 `lowOpacityFactor = ((0.35 - opacity) / 0.35).clamp(0.0, 1.0)` 提高文字纯色对比度，**严禁使用文字阴影**。
  - 预览卡片标准逻辑尺寸：
    - 今日课表 `_TodayPreviewCard`：4×2 宽卡 `336×176`，2×2 窄卡 `176×176`（1:1 正方形），底部内边距为 `0`（直抵 1dp 描边内缘）。
    - 本周课表 `_WeekPreviewCard`：4×4 正方形 `316×316`。
    - 下一节课 `_NextPreviewCard`：2×2 方卡 `176×176`，4×1 横条 `336×76`。
  - `buildSampleWidgetSnapshot`：固定黄金参考时刻 `10:40`（第 2 周），确保任意星期几预览均同时包含：已结束课程（1-2 节 `08:30-10:05`）、进行中课程（3-4 节 `10:25-12:00`）、从第 1 周周日调入今天的待上调课（5-6 节 `13:30-15:05`，`rescheduled: true`）、当天下午考试（`16:00-17:40`）以及 3 天后的未来考试。

---

## 5. 页面级 `Listenable` 订阅隔离与交互契约（`lib/pages/*` 全量 18 页）

### 5.1 全页面 `Listenable` 订阅边界总表（Rebuild Isolation Contract）

> **核心铁律**：任何页面或子组件**严禁盲目订阅根 `AppModel`**（除非明确需要响应课表数据与偏好的联合变更）。必须按最小职责订阅对应的细分 `Listenable` 通道，由 `test/rebuild_scope_test.dart` 严格守护。

| 页面 / 组件 | 订阅的 `Listenable` 通道 | 触发重建的事件 | 严格隔离（不触发重建）的事件 |
| :--- | :--- | :--- | :--- |
| `_AppShell` (`main.dart`) | `model.routeNotifier` | `AppStatus` 切换、错误码改变、课表从无到有/从有到无、验证码状态改变 | 提示气泡更新、刷新转圈切换、切周、学业数据更新、外观/提醒设置修改 |
| `HomeShell` (`home_shell.dart`) | `model.updateFlow`（仅 State 监听弹 SnackBar）；顶层 `StatusPopup` 监听 `hints + routeNotifier` | 后台更新下载完成/失败；全局提示或连接状态变化（仅重建右上角 `StatusPopup`） | 切周、课表局部提示、学业局部提示、设置项修改（`HomeShell` 自身 0 重建） |
| `SchedulePage` 顶栏 `_WeekBar` | `scheduleState + routeNotifier`（外层判空）+ `_shownWeek`（内层 `ValueListenableBuilder`） | 手势滑动跨页改 `_shownWeek`、点箭头/选周改 `weekNotifier`、课表加载完成 | 提示气泡、刷新按钮转圈、学业数据加载、设置开关变更 |
| `SchedulePage` 顶栏刷新按钮 | `routeNotifier + refreshingNotifier` | `status == ready` 或 `refreshing` 布尔值变化 | 切周、提示文案变化、外观滑块拖动 |
| `SchedulePage` 顶栏 `_UpdateStatusButton` | `model.updateFlow` | 发现新版本、下载进度百分比变化、下载完成待安装、下载出错 | 课表与学业的一切状态变化 |
| `SchedulePage` 主体 `_WeekPager` | 外层：`routeNotifier + scheduleState + prefsNotifier`；内部翻页监听：`model.weekNotifier` + `_shownWeek` | 课表数据/学期/最大周次变化、外观/作息/调课偏好变化；`weekNotifier` 仅驱动 PageController 滚动而不重建 `_WeekPager` | 手势滑周期间不写 `model.week`（0 整页重建）；提示气泡与 `refreshing` 变化不重建课表网格与 `CourseBlock` |
| `SchedulePage` 右下角 `_TodayFab` | `_shownWeek + routeNotifier + scheduleState` | 当前显示周次与 `currentWeekOfToday` 是否相等变化 | 提示气泡、刷新转圈、学业加载 |
| `SchedulePage` 右上角 `StatusPopup` | `hints + routeNotifier + refreshingNotifier` | `scheduleHint` 变化或全局弹窗激活态退避 | 切周、外观设置变化 |
| `AcademicPage` 主体 | `academicNotifier + scheduleState` | 考试/成绩/评教状态/学业学期变化、当前课表学期 `termStart` 校准变化 | 课表切周（`weekNotifier`）、课表局部提示、外观/提醒偏好变化 |
| `AcademicPage` 右上角 `StatusPopup` | `hints + routeNotifier + academicNotifier` | `academicHint` 变化或全局弹窗激活态退避 | 课表切周、偏好变化 |
| `SettingsPage` | `model.prefsNotifier`（Android 权限区局部监听 `_statusNotifier`） | 偏好设置（开关/作息/调课/校准/更新代理）或账号身份（学号/姓名）变化 | **后台刷新课表（当内容与身份未变时 `hydrate` 不发 `prefsNotifier`）、切周、提示气泡、学业加载** |
| `AppearanceSheet` | `model.prefsNotifier` | `cellHeight` 或 `courseTextScale` 滑块变化 | 提示气泡、切周、后台刷新、学业加载 |
| `ReschedulePage` | `model.prefsNotifier` | `reschedules` 调课规则增删改 | 提示气泡、切周、后台刷新、学业加载 |
| `TimetableListPage` | `model.prefsNotifier` | `timetables` 或 `sectionCounts` 变更 | 提示气泡、切周、后台刷新、学业加载 |
| `SchoolAddressPage` | `model.prefsNotifier` | `schools` 地址簿增删或当前 `schoolBaseUrl` 切换 | 提示气泡、切周、后台刷新、学业加载 |
| `AboutPage` / `UpdateProxyPage` | `model.prefsNotifier` | `selectedUpdateProxy` 或 `customUpdateProxies` 变更 | 课表、周次、学业状态变化 |
| `ReminderPage` | `_ReminderSettingsCard`：`model.prefsNotifier` + `_statusNotifier`；`_PermissionsCard` / `_DiagnosticsCard`：仅 `_statusNotifier` | 拖动提前量滑块仅重建 `_ReminderSettingsCard` 内部草稿；原生状态刷新仅重建权限与诊断卡 | 三张卡片互不波及，不触发整页 `ReminderPage` rebuild |
| `WidgetSettingsPage` | 主体：`model.prefsNotifier`（State 监听 `model` + `academicNotifier` 仅在源数据 key 变化时更新 `_cachedRealSnapshot`）；底部计数：`_pinnedCounts` | 拖动透明度/圆角/字号滑块仅更新局部草稿（**0 次 `buildSnapshot()` 调用**），松手 `onChangeEnd` 才持久化 | 滑块拖动期间绝不重新规划 14 天日程快照 |

---

### 5.2 各页面状态交互、核心方法与弹窗/抽屉明细

1. **`SchedulePage` (`lib/pages/schedule_page.dart`)**：
   - 首帧 `addPostFrameCallback` 调用 `model.checkAutoUpdate(onHasUpdate: ...)`（同一会话只检查一次），页面销毁时 `model.cancelAutoUpdate()`。
   - 右上角三点菜单 `_MoreMenu`：包含 `校准当前周次` (`showCalibrateSheet`)、`作息时间表` (`TimetableListPage`)、`教务地址` (`SchoolAddressPage`)、分隔线、`外观` (`showAppearanceSheet`)、`调课` (`ReschedulePage`)。
   - 顶栏周次按钮点击/下拉：调用 `showWeekPicker(centerHorizontally: true, maxHeight: 340)`。
   - 表头 `_DayHeader`：当天所在列 `primary.withValues(alpha: 0.20)` 高亮；有课表时间冲突或调课冲突的那一天显示 `5×5` 黄色圆点（`AppColors.conflictDot`）；若为**调课冲突**（原课被顶掉隐藏），点击表头弹出 `showDayConflicts`（`_DayConflictSheet`）列出被顶掉的课程与占位的调课。
   - 底部备注区 `_ScheduleRemarks`：当 `model.showScheduleRemarksSection` 为真时跟随周网格滚动展示「实践课程」与「其他课程」（来自教务 `sjkList`）。
2. **`AcademicPage` (`lib/pages/academic_page.dart`)**：
   - 离屏预挂载保护：`isActive` 为 `true` 且 `exams.isEmpty && grades.isEmpty && !academicLoading && !isNotEvaluated` 时才在 post-frame 触发 `model.loadAcademicData()`。
   - 考试三级排序 `sortAcademicExams(exams, now)`：
     - **Tier 0（进行中/未来，`!isExamPast && startTime != null`）**：按日期升序 → 同日有具体时刻（匹配 `\d{1,2}:\d{2}`）排在仅日期前 → `startTime` 升序 → `endTime` 升序 → 课程名升序。**排在最顶端的第 1 门待考科目单独提取为 `NextExamHeroCard`，不再在下方列表重复渲染**。
     - **Tier 1（时间未公布，`startTime == null`）**：居中，按课程名升序。
     - **Tier 2（已结束，`isExamPast == true`）**：自动下沉到底部，标注「已结束」徽章，内部按 `startTime` 升序。
   - 考试时间周次追加 `formatExamTimeLabel(exam, currentTermStart)`：仅当查看的是**当前课表所属学期**（`currentTermId == model.termId && model.loadedAcademicTerm == model.termId`）、`exam.startTime != null`、考试日期不早于开学周周一且原字符串不含周次/星期时，自动追加 `'·第X周 周X'`。
   - 懒加载分段卡片 `_LazyCardSegment` + `_CardSegmentShape`：在 `SliverList.builder` 中按 `isFirst` / `isLast` 动态绘制顶圆角、底圆角或左右竖线描边，使长列表既保持整张圆角卡片的视觉外观，又具备 Sliver 视口级按需懒构建性能。
3. **`SettingsPage` (`lib/pages/settings_page.dart`)**：
   - 「静默更新」开启时展开「最小更新间隔」步进器 `_IntervalStepper`（按小时步进，`minAutoRefreshIntervalMinutes` 60 分钟 .. `maxAutoRefreshIntervalMinutes` 1440 分钟）。
   - 「提醒与小组件」卡片 `_ReminderAndWidgetCard`：仅在 `defaultTargetPlatform == TargetPlatform.android && (reminders != null || desktopWidgets != null)` 时渲染；混入 `RouteSettledStateMixin`，转场落稳后才提交 `_statusNotifier` 更新，并监听 `AppLifecycleState.resumed` 从系统设置返回时自动刷新权限状态。
   - 「修改密码」`_PasswordDialog`：先用新密码向教务发起真实登录验证（`model.changePassword`），验证通过才覆盖本机安全存储密码，失败弹 `AppSnackBarType.error` 胶囊提示。
   - 「退出登录」`_confirmSignOut`：确认后调用 `model.signOut()`，并触发 `reminders?.cancelAll()` 与 `desktopWidgets?.syncNow()` 清空闹钟与桌面小组件数据。
4. **`TimetableListPage` & `TimetableEditPage`**：
   - 新建作息表（上限 `maxTimetables = 20`）时**不落盘**，构造草稿 `Timetable` 通过 `initial` 传入 `TimetableEditPage`，点击右上角对勾（`_dirty == true` 时启用）才调用 `model.upsertTimetable` 持久化。
   - `TimetableEditPage` 使用 `PopScope(canPop: !_dirty)` 拦截返回手势，有未保存改动时弹出「放弃修改？」确认框。
5. **`ChangelogPage` & `LicenseTextPage`（并发 Isolate 解析 + `RouteSettledStateMixin` 门控）**：
   - 进入页面 `initState` 时立即并行启动 asset 读取与 `runInBackground`（后台 Isolate 执行 `parseChangelogBytes` / `reflowLicenseBytes`）。
   - 在 260ms 路由滑入动画完成前（`!isRouteSettled`），`build` 仅返回超轻量静态骨架（`CardListTransitionPlaceholder` / `DocumentTransitionPlaceholder`），且后台加载完成时**不中途调用 `setState`**，待 `onRouteSettled` 落稳瞬间一次性挂载 `SelectionArea` + `ListView`，保证滑入动画 100% 满帧零卡顿。
6. **`UpdateDialog` (`lib/pages/update_dialog.dart`)**：
   - `showUpdateDialog` 全程 `barrierDismissible: false`（严禁点外部空白关闭）。
   - 四阶段单弹窗流转：
     - `available`：展示发布日期、安装包大小、架构名与清洗掉 CI 下载表格后的 Markdown 更新日志（`_ReleaseNotesView`）；Android 点击「立即更新」前先检查 `canInstallPackages()`，未授权时引导跳转系统设置，并在 `didChangeAppLifecycleState(resumed)` 返回时自动触发 `refreshInstallPermissionAndAutoInstall()`。
     - `downloading`：展示实时进度条、百分比、已下载/总大小、实时网速，以及自动回退代理节点提示；点击右上角关闭或「后台下载」仅收起弹窗继续后台下载（课表页顶栏 `_UpdateStatusButton` 显示环形进度），点击「取消下载」才调用 `cancelDownload()`。
     - `readyToInstall`：Android 显示「立即安装」，Windows 显示「立即重启更新」。
     - `error`：展示错误信息，提供「浏览器下载」（`fallbackDownloadUrl`）与「重试下载」。

---

## 6. 测试矩阵、测试替身与 CI 门禁（`test/*` & `packages/zf_academic/test/*`）

### 6.1 L0–L3 测试分层架构与执行铁律

| 层级 | 名称 | 覆盖范围与测试目录 | 运行环境与耗时 |
| :--- | :--- | :--- | :--- |
| **L0** | 静态门禁（Lint & Format） | `dart format` + `flutter analyze --no-fatal-infos`（主工程与 `packages/zf_academic`） | 纯静态分析，`< 15s` |
| **L1** | 协议与纯算法单元测试（Protocol & Pure Unit） | `packages/zf_academic/test/*_test.dart`（9 个文件）+ 主工程纯算法测试（`term_calendar_test`、`term_selector_helper_test`、`timetable_test`、`reminder_planner_test`、`widget_planner_test`、`widget_style_test`、`safe_json_file_test`、`academic_cache_test`） | 纯 Dart / 临时目录文件 I/O，无 Widget 树，极速确定性验证 |
| **L2** | 服务编排与状态机测试（Service & State Machine） | `schedule_service_test.dart`、`academic_service_test.dart`、`reminder_service_test.dart`、`widget_service_test.dart`、`app_model_test.dart`、`updater_test.dart`（纯逻辑部分） | 注入 `FakeBackend` / `FakeReminderGateway` / `FakeDesktopWidgetGateway`，验证单 flight 重登、熔断、世代锁 `_authEpoch`、防抖与指纹去重 |
| **L3** | 界面、物理动效与重建隔离测试（Widget & Physics） | `widget_test.dart`、`dock_transition_test.dart`、`page_transition_test.dart`、`rebuild_scope_test.dart`、`boost_idle_optimization_test.dart`、`academic_page_test.dart`、`widget_settings_page_test.dart`、`formatted_text_span_test.dart`、`app_version_test.dart` | `flutter_test` 虚拟时钟帧进（`tester.pump(Duration)`），精确断言弹簧单调性、图层 `RepaintBoundary` 零重绘、组件 `debugOnRebuildDirtyWidget` 重建集合与跨屏无溢出 |

> **测试执行与去重铁律**：
> 1. 所有命令均在仓库根目录下执行。
> 2. **合并单次进程运行**：运行全量主工程测试时使用 `flutter test`（或 CI 中的 `find test -path test/custom -prune -o -type f -name '*_test.dart' -print | sort` 传入 `flutter test`），使所有测试文件在单次编译与测试进程中并发执行，禁止写循环逐个文件串行启动 `flutter test`。
> 3. **新增测试去重原则**：优先在现有的 23 个主题测试文件中补充用例，避免创建碎片化重复测试文件；临时专项验收可放入 `test/custom/*_test.dart`（CI 会自动检测并单独执行）。

---

### 6.2 主工程测试套件全表（`test/*.dart`，23 个测试文件）

| 测试文件 | 分层 | 核心覆盖模块与守护契约 |
| :--- | :---: | :--- |
| `test/academic_cache_test.dart` | L1 | `CachedTermExams` / `CachedTermGrades` JSON 序列化（含 `isNotEvaluated`）、`InMemoryExamCache` / `FileExamCache` / `FileGradesCache` 并发多学期落盘不互覆、损坏 JSON 容错、`LateExamCache` 占位安全 |
| `test/academic_page_test.dart` | L3 | `AcademicPage` 空态/刷新/未评教横幅/网络错误横幅、定性及免修成绩渲染、学期选择器人性化标签（「大三 上学期」）与未来/入学前学期过滤、`sortAcademicExams` 三级排序与 `isExamPast` 判定、`NextExamHeroCard` 倒计时徽章、`formatExamTimeLabel` 周次追加与历史学期隔离、后台学业差异比对触发全局更新气泡 |
| `test/academic_service_test.dart` | L2 | `GradeStats.calculate` 加权 GPA 与扩展及格词表（通过/优秀/免修/P 等）、`AcademicService` 拉取与写缓存、`notEvaluated` 保留已有缓存条目、`syncCurrentTermAsync` 后台静默同步及并发会话失效共享单次重登 |
| `test/app_model_test.dart` | L2 | 冷启动本地账号/姓名恢复、登录/退登全链路清理、周次/校历校准/分段节数动态托底（`gridSectionCount`）、后台刷新与重登提示流转、修改密码（含 `sessionInfo.username` 为空回退本地账号）、线路切换原地加载与失败回滚、静默更新间隔与串联学业同步、调课 overlay 合并、`_authEpoch` 与 `_academicLoadSeq` 竞态防写脏回归 |
| `test/app_version_test.dart` | L1 | 验证 `loadAppVersion()` 读出的 `appVersionFull` 与 `appVersion` 严格等于 `pubspec.yaml` 中的 `version` 字段，严禁硬编码 |
| `test/boost_idle_optimization_test.dart` | L2/L3 | `scheduleAfterRouteSettled` 转场门控（含 `forward -> reverse -> forward` 取消返回恢复）、`SecureCredentialStore.get` 双 Key 并发读取、`SafeJsonFile` `>16KB` 走 Isolate 解码与 `.bak` 自愈、`AppModel.boot` 单次支持目录查询与空闲帧恢复学业缓存、`ScheduleController` / `AcademicController` 记忆化、课表邻近周空闲帧切片预热（`CourseBlock.debugBlockPlanSolveCountForTest` 零新增求解）、`HomeShell` 按需懒建、`CaptchaPage` Base64 解码缓存、`DebugPage` 折叠态懒格式化 JSON、`ReminderPage` / `WidgetSettingsPage` 入场并行查询与骨架门控 |
| `test/dock_transition_test.dart` | L3 | `HomeShell` + `FloatingDock` 打断与抢跑交互：滑行中途点击目标页开关/滚动列表/推入二级页、零时长不透明路由瞬间遮挡后台静默收敛、离场页立即锁死、按住 Dock 预览期间锁死内容区、跨页直达（`0 <-> 2`）单调不误停学业页、反向折返零反冲、同向续速无跳变、`AppMenuScope` 翻页中途开菜单随页面滑入落位、切页时菜单随原页划走收起、长按 190ms 期间切页绝不跨页误弹菜单 |
| `test/formatted_text_span_test.dart` | L1/L3 | `buildFormattedTextSpan` 行内 `**加粗**` 与 `` `代码` `` 分词及未闭合标记容错、`parseChangelogBytes` 真实后台 Isolate 解析、`ChangelogPage` 首帧零延迟渲染、当前版本卡片主色描边与 `ListView.separated` 视口懒构建 |
| `test/page_transition_test.dart` | L3 | `_SlideTransitionsBuilder` 全宽位移（`1.0 <-> 0.0`）与背层视差（`-0.24`）、`_ContinuousCurveAnimation` 正反向柔和减速及半途往返折返零跳变、入场中途立即可点击/滚动/进三级页、`ChangelogPage` / `LicenseTextPage` 入场滑行期轻量骨架与失败重试、转场期间 `RepaintBoundary` 隔离进出双方页面 **0 次重绘**、路由退场与推入新路由时自动收起 `AppMenu` |
| `test/rebuild_scope_test.dart` | L3 | 验证 `hints`、`refreshingNotifier`、`weekNotifier`、`academicNotifier`、`prefsNotifier`、`routeNotifier` 相互隔离不触发根 `AppModel` 广播；用 `debugOnRebuildDirtyWidget` 证明提示气泡、刷新转圈、切周、开合菜单、滑选菜单项、点外部关菜单时，`HomeShell`、`SchedulePage`、`CourseBlock` 及无关菜单按钮 **0 次重建** |
| `test/reminder_planner_test.dart` | L1 | `planCourseReminders` 纯函数：提前量（1~60 分钟）换算、按事件当天匹配夏冬作息表、超出作息表节次安全跳过、单双周与调课覆盖（被顶掉原课不再提醒）、过期不补发、`reminderMaxEvents` 截断、跨年推进、指纹稳定性与 payload JSON 结构、稳定事件 ID `reminderEventId` |
| `test/reminder_service_test.dart` | L2 | `ReminderService` 编排：指纹去重与 `force: true` 强制重排、改提前量/形态触发重发、原生失败保留重试、在途 `syncNow` 串行跟进最新提前量、关闭开关/无课表幂等取消、`preferencesLoaded == false` 冷启动保护、连续通知防抖合并、预览/测试提醒/权限跳转转发 |
| `test/safe_json_file_test.dart` | L1 | `SafeJsonFile` `.tmp` 原子写入与 `.bak` 轮转备份、主文件损坏自动从 `.bak` 自愈、双坏标记 `hadUnrecoverableCorruption`、高并发 `updateJson` 排队无丢失、连续 `writeJson` 合并中间排队、`Preferences` 与 `FileScheduleCache` 抗损坏与磁盘写失败节流提示 |
| `test/schedule_service_test.dart` | L2 | `ScheduleService` 需求 1（Cookie 优先免密取课表、10s 超时、`bootstrap` 同源校验）与需求 2（`SESSION_EXPIRED` 自动重登、单 flight 跨接口并发共享单次重登、10 分钟 2 次熔断与手动登录解除、重登失败回滚旧 Cookie、自动重登遇验证码回调、重登进行中全局互斥锁阻塞新查询、重登中途 `signOut` 防复活） |
| `test/term_calendar_test.dart` | L1 | `mondayOf`、`estimateTermStart`（秋季 9/1 周一、春季 2/23 周一）、`weekOf` 与 `dateOf` 1..16 周互逆、`termStartFromWeek` 反推开学日、`occursInWeek` / `entriesOfWeek`、`weekRangeLabel`、`compressWeeks`、`formatIsoDate` |
| `test/term_selector_helper_test.dart` | L1 | `parseEnrollmentYear`（严格解析青科大 10 位学号前 2 位入学年，修复 2020 级 21 学院 `2021010101` 误判）、`estimateCurrentAcademicYear`、`filterTerms`（过滤入学前、未来学期及两学期制下的第 3 小学期，保留当前选中学期）、`formatTermPrimaryLabel`（大一至大五上下学期映射） |
| `test/timetable_test.dart` | L1 | `buildSections` 三段累加与大课间替代小课间、生效表按月日自动选择与跨年回绕、`reconcileSections` 逐段对齐、`roomOnly` 房间号提取、`Preferences` schema 1..15 历代迁移、覆盖式地址与边界夹取 |
| `test/updater_test.dart` | L2/L3 | `isVersionNewer` 语义化版本比对、`buildProxiedUrl`、`ReleaseInfo.cleanReleaseBody` 过滤 CI 下载表、`cleanOldUpdateFiles` 清理旧包与 `.part`、Windows 安装版 vs 便携版产物匹配、`UpdateFlowController` 单弹窗流转（后台下载收起/恢复、取消回退、失败重试）、课表顶栏更新图标与完成 SnackBar、`SHA256SUMS` 校验、Windows 便携版 `robocopy /mir` + VBS 隐藏脚本生成、并发分片下载异常/取消即时中止所有挂起分片并清理句柄 |
| `test/widget_planner_test.dart` | L1 | `buildWidgetSnapshot` 14 天日程与双周网格规划：当天课程与考试按时间混排、调课 `rescheduled: true` 标记、近期未结束考试周次/星期计算、指纹仅随有效内容与样式变化、冲突分栏 `conflictIndex/conflictTotal`、未登录空快照与异常节次防御 |
| `test/widget_service_test.dart` | L2 | `DesktopWidgetService`：`preferencesLoaded == false` 守卫、指纹去重与 `force: true`、修改样式防抖重发、跨学期考试隔离（切换历史学业学期不污染当前学期小组件考试）、退出登录下发未登录快照、`clearAll` 等待在途 `syncSnapshot` 完成后再清空防竞态回写 |
| `test/widget_settings_page_test.dart` | L3 | `DesktopWidgetPreview` 与 `WidgetSettingsPage`：今日课表 4×2/2×2 完整起止时间与进行中/调课/考试混排、周日生成示例课表明日（下周一）无缝衔接、课后自动切明日预告、关闭地点同步隐藏座位号、14 天过期提示（学期结束后新鲜快照不误报）、本周课表周末列智能显隐（仅周末有课且隐藏周末列时给友好提示）、下一节课状态胶囊常驻、0% 透明隐藏圆角滑块、恢复默认支持撤销、`360×640` 窄屏 + `2.0×` 超大系统字体零溢出 |
| `test/widget_style_test.dart` | L1 | `DesktopWidgetStyle` 5 套精选预设（只改色彩/透明度/圆角，保留密度/字号/内容开关解耦）、透明度/圆角/字号（`75%..120%`）边界夹取、畸形/旧版 JSON 平稳迁移、`DesktopWidgetConfigSet` 三类小组件独立保存与 `Preferences` schema 14 持久化 |
| `test/widget_test.dart` | L3 | 综合 UI 回归大套件（5000+ 行）：登录页、周视图课表页、调课/时间冲突打点与抽屉、课表备注开关、`WeekPager` 快滑/慢拖/连滑/箭头/跨多周借位滑入、周次与偏好通知分离、`HomeShell` 懒建与 Dock 切换、时间轴 `FittedBox` 防黄黑溢出、`CourseBlock` 排版扫雷（M3 字距与系统粗体临界宽度）、三点菜单与选周菜单形变/滑选/分割线吸附/Dock 直达、外观面板、Dock 液态透镜 `RSuperellipse` 与 `_OutsideLensClipper`、作息表新建草稿与编辑、三段滚轮与时间范围滚轮、状态气泡作用域与平移、教务地址簿、调试页、课程提醒页、悬浮胶囊 `AppSnackBar`、验证码容错、`TactileAppBar` 四层合绘、单层 `SelectionArea` 规范 |

---

### 6.3 协议包测试套件全表（`packages/zf_academic/test/*.dart`，9 个测试文件）

| 测试文件 | 核心覆盖模块与守护契约 |
| :--- | :--- |
| `packages/zf_academic/test/cookies_test.dart` | RFC 6265 `CookieStore`：host-only vs Domain 子域匹配、Path 前缀边界匹配（`/jwglxt` 不泄漏给 `/jwglxtx`）、过期与 `Max-Age<=0` 删除、`Expires` 逗号不误拆、Secure 仅 https 回发、CAS → 教务会话 `adopt` 迁移、快照导入导出往返、`invalidate` 递增世代 |
| `packages/zf_academic/test/cookie_isolate_test.dart` | `FileCookieStorage` 超过阈值时通过后台 Isolate 完整往返大数据快照、`ExamItem.effectiveEndTime` 纯日期与时间段推算 |
| `packages/zf_academic/test/credential_store_test.dart` | `InMemoryCredentialStore` 增删查清、多账号隔离、`credentialStoreKey` 哈希稳定性且不含明文账号 |
| `packages/zf_academic/test/crypto_test.dart` | 正方定制 CAS 加密（无填充裸 RSA + UTF-16 码元逆序分块对拍）、表单登录 PKCS#1 v1.5 RSA 加密（base64 modulus/exponent 解密验证、畸形公钥拒绝） |
| `packages/zf_academic/test/exams_test.dart` | `parseExamTime` 全格式解析、`jsonExams` 字段别名兼容（`cdxqmc`/`xqmc`, `cdmc`/`jxcdmc`）、空课程名过滤、相同考试自动去重、`effectiveEndTime`（显式/单点+2h/当日终点）、`fetchExams` (`showCount=500`)、`calendarTerm` 东八区清晨防 UTC 跨天回退 |
| `packages/zf_academic/test/grades_test.dart` | `jsonGrades` & `GradeItem` 解析与 JSON 往返、`fetchGrades` (`showCount=500`)、未评教拦截识别 `ErrorCode.notEvaluated`（区分课程名含“教学质量评价”但已正常返回成绩列表的场景） |
| `packages/zf_academic/test/html_test.dart` | 手写零依赖 HTML 解析器：`closingIndex` / `innerOf` 多层同名嵌套标签闭合、自闭合与 void 标签、属性引号及 `script`/`style`/注释内假标签抗干扰、提取学生姓名与学号 |
| `packages/zf_academic/test/http_client_test.dart` | `ZfHttpClient`：Cookie 收集与回发、表单空格编码为 `+`、双 `name=mm` 重复键提交、302 跟随与 POST 转 GET、未声明主机 `UNTRUSTED_URL`、跳统一认证域归类 `SESSION_EXPIRED`、同主机 http 降级自动升回 https、`inspectResponse` 区分 HTTP 200 下的网关 502/系统维护（`SERVER_ERROR`）与外网 403 拦截（`ACCESS_FORBIDDEN`）及真改版（`PAGE_CHANGED`）、读请求网络中断自动重试 1 次而写请求不重试报 `RESULT_UNKNOWN`、GBK/latin1 字符集容错、真实 `dart:io` 套接字传输 |
| `packages/zf_academic/test/login_test.dart` | `ZhengfangClient`：URL 推导、`probe()` 探测、表单 RSA 登录（`?time=`、双 `mm`、复用 CAS 探测与公钥、密码错误优先识别）、验证码挑战与重试、Cookie 快照免登查课表与 `0600` 权限收紧、`checkSession` 三态、`fetchTerms` 与 `fetchSchedule`（`kbList` + `sjkList` 备注 + 青科 `cxXsgrkb` 个人课表端点）、`FileCookieStorage` 连续保存合并与损坏容错 |

---

### 6.4 测试替身与辅助夹具（`FakeBackend` / `FakeReminderGateway` 等）

1. **`test/support/fake_backend.dart`**：
   - 预设样本数据：`sampleSchedule([termId])`（含 `'电力电子技术'`）、`snapshotOf(baseUrl, {value})`、`sampleExams([termId])`（2 门考试）、`sampleGrades([termId])`（2 门成绩）。
   - `FakeBackend implements ScheduleBackend`：
     - 可注入行为闭包：`fetchBehavior`、`examsBehavior`、`gradesBehavior`、`loginBehavior`、`submitBehavior`、`termsBehavior`。
     - 调用计数器：`fetchCount`、`examsCount`、`gradesCount`、`termsCount`、`loginCount`、`submitCount`、`refreshCount`、`importCount`、`closeCount`、`checkSessionCount`。
     - 调试字段：`lastScheduleRawBody`、`lastScheduleRows`、`lastTermsRawBody`、`lastImported`。
   - `FakeSessionRepository implements SessionRepository`：内存 Cookie 快照存取，记录 `saveCount` / `clearCount`。
   - `FakeScheduleCache implements ScheduleCache`：内存课表缓存存取，记录 `saveCount` / `clearCount` / `lastSaved`。
   - 快捷异常构造：`expired()` (`ErrorCode.sessionExpired`)、`pageChanged()` (`ErrorCode.pageChanged`)、`badCredentials()` (`ErrorCode.invalidCredentials`)。
2. **`test/support/fake_reminder_gateway.dart`**：
   - `FakeReminderGateway implements ReminderGateway`：
     - 记录 `syncedPayloads`、`testRequests`、`previewRequests`、`toasts` 及各权限设置打开计数。
     - 提供 `Completer<void>? syncGate`：用于挂起 `sync()` 调用，确定性测试“在途同步期间用户继续拖动提前量滑块或操作界面的并发合并与非阻塞行为”。

---

### 6.5 GitHub Actions CI/CD 流水线契约（`.github/workflows/build-release.yml`）

- **触发条件**：`main` / `master` 分支的 `push` 与 `pull_request`（过滤 `lib/**`、`test/**`、`packages/**`、`assets/**`、`android/**`、`windows/**`、`pubspec.*`、`analysis_options.yaml`、`.github/**`，排除 `**.md` 纯文档改动）、`v*` 标签推送、以及手动 `workflow_dispatch`。
- **并发与最小权限**：普通分支提交 `cancel-in-progress: true` 自动中止旧运行；`refs/tags/v*` 发版标签 **`cancel-in-progress: false`** 绝不被打断。顶层仅授予 `contents: read`，写权限按需下放至 `test`（`actions: write`）与 `create-release`（`contents: write`）。
- **三路并行 + Fail-Fast 架构**（Flutter 版本 `3.47.7`，核心 Action 均为 Node 24 运行时：`actions/checkout@v7`、`actions/setup-java@v6`、`gradle/actions/setup-gradle@v6`、`actions/upload-artifact@v7`、`actions/download-artifact@v8`、`softprops/action-gh-release@v3`）：
  1. **`test` Job (`ubuntu-latest`)**：
     - 发版门禁：若为 `refs/tags/v*`，先校验 Tag 名严格等于 `pubspec.yaml` 的 `v${VERSION}`，不匹配直接阻断。
     - 依次执行：`dart format --output=none --set-exit-if-changed lib test`（主工程与 `packages/zf_academic`）→ `flutter analyze --no-fatal-infos lib test`（主工程）与 `dart analyze lib test`（`packages/zf_academic`）→ `(cd packages/zf_academic && dart test)` → `flutter test $(find test -path test/custom -prune -o -type f -name '*_test.dart' -print | sort)`（支持 `test/` 下子目录且排除 `test/custom/`）→ 若 `test/custom/` 下存在 `*_test.dart` 则单独运行 `flutter test test/custom`。
     - **Fail-Fast 机制**：非 PR 场景下（`failure() && github.event_name != 'pull_request'`）若 `test` 失败，立即通过 `gh run cancel ${{ github.run_id }}` 取消整次运行，中止并行中的 Android 与 Windows 打包。
  2. **`build-android` Job (`ubuntu-latest`，非 PR 触发)**：
     - JDK 21 + Gradle（`cache-cleanup: never` 省掉 post 阶段 36~55s 清理耗时）。
     - 签名门禁：`v*` 标签发版强制要求配置 `KEYSTORE_BASE64`、`KEY_STORE_PASSWORD`、`KEY_ALIAS`、`KEY_PASSWORD`，缺失时直接失败阻止发版；非标签构建缺失时退回 debug 签名。
     - 执行 `flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64`，产出 `QustSchedule_v${VERSION}-arm64-v8a.apk` 与 `armeabi-v7a.apk`（`archive: false` 单文件直传 Artifact，`retention-days: 14`）。
  3. **`build-windows` Job (`windows-latest`，非 PR 触发)**：
     - 先关闭 Windows Defender 实时扫描加速 SDK 解压，执行 `flutter build windows --release`。
     - 使用 Inno Setup (`windows\packaging\setup.iss`，校验 `$LASTEXITCODE`) 打包安装版 `QustSchedule_v${VERSION}-windows-x64-setup.exe`，并用 `Compress-Archive` 打包便携版 `QustSchedule_v${VERSION}-windows-x64.zip`（`retention-days: 14`）。
  4. **`create-release` Job (`needs: [test, build-android, build-windows]`，仅 `refs/tags/v*` 触发)**：
     - 从 `pubspec.yaml` 提取版本号，汇总 4 个安装包生成 `SHA256SUMS`（无 `./` 前缀），通过 `git describe --tags --abbrev=0 "${TAG}^"` 定位上一标签生成对比链接，从 `CHANGELOG.md` 提取当前版本更新日志并拼接直连与 `gh-proxy.org` 加速下载徽章表格，通过 `softprops/action-gh-release@v3` 自动发布 GitHub Release。
