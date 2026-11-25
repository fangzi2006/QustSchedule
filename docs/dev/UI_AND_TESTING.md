# UI、物理动效与测试矩阵速查 (`UI_AND_TESTING.md`)

> 覆盖 `lib/main.dart`、`lib/theme/*`、`lib/widgets/*`、`lib/pages/*`、`test/*`、`packages/zf_academic/test/*` 及 `.github/workflows/build-release.yml`。

## 目录
1. [文件速查路由](#1-文件速查路由)
2. [应用入口与顶层路由（`main.dart`）](#2-应用入口与顶层路由maindart)
3. [主题、圆角、配色与转场（`lib/theme/*`）](#3-主题圆角配色与转场libtheme)
4. [核心自定义物理组件与渲染契约（`lib/widgets/*`）](#4-核心自定义物理组件与渲染契约libwidgets)
5. [页面级 `Listenable` 订阅隔离与交互契约（`lib/pages/*` 18 页）](#5-页面级-listenable-订阅隔离与交互契约libpages-18-页)
6. [L0–L3 测试矩阵、替身与 CI 门禁](#6-l0l3-测试矩阵替身与-ci-门禁)

---

## 1. 文件速查路由

### 1.1 入口、主题与组件（相对 `qustschedule/`）

| 路径 | 核心导出 | 职责关键字 | 守护测试 |
| :--- | :--- | :--- | :--- |
| `lib/main.dart` | `main()`, `CourseApp`, `_AppShell`, `pageForStatus()` | 异步版本、Android 提醒/小组件挂载、`onShow` 强制同步、顶层状态路由 | `widget_test`, `rebuild_scope_test` |
| `lib/theme/app_theme.dart` | `AppRadius`, `AppColors`, `buildLightTheme()`, `AppScrollBehavior`, `_SlideTransitionsBuilder`, `_ContinuousCurveAnimation`, `_EdgeShadowPainter`, `_RouteScrimPainter` | 5 级圆角、25 语义色、M3 浅色、全指针拖拽、260/240ms 全宽滑动转场 | `page_transition_test`, `widget_test` |
| `lib/theme/course_palette.dart` | `CourseColor`, `CoursePalette` | 9 组浅/深色板、FNV-1a `indexOf(courseName)`（与原生小组件同构） | `widget_test`, `widget_settings_page_test` |
| `lib/widgets/floating_dock.dart` | `FloatingDockItem`, `FloatingDock`, `FloatingDockState` | 58dp 胶囊、`RSuperellipse` 液态透镜、过阻尼中心弹簧、速度拉伸振子、`_OutsideLensClipper`、`hitTestGlobalPosition` | `dock_transition_test`, `widget_test` |
| `lib/widgets/tactile_button.dart` | `TactileSurfaceStyle`, `TactileSurfaceButton`, `TactileIconButton`, `TactileBackButton`, `TactileActionVariant`, `TactileActionButton`, `TactileSurfaceScope`, `TactileAppBar` | 按压放大、橡皮筋微拖、190ms 长按/下拉开菜单、四层合绘、`_TactileArenaRecognizer` | `widget_test`, `dock_transition_test` |
| `lib/widgets/app_menu.dart` | `AppMenuItem`, `AppMenuScopeController`, `AppMenuScope`, `showAppMenu()`, `RenderMenuMorphBox`, `activeAppMenuMorph`, `activeTactileDragStart`, `isRouteActiveForAppMenu()` | 双轴形变弹簧、`CompositedTransformTarget` 跟随、五重活跃门控、`_MenuBarrier` | `dock_transition_test`, `rebuild_scope_test`, `widget_test` |
| `lib/widgets/week_pager.dart` | `WeekPagerController`, `_WeekPagerPosition`, `_SkipJumpScrollActivity`, `_IgnoredHold`, `_DeferredDrag` | 锚点单页翻页、`1/3` 阈值、不冻结在途、零死区延迟拖、跨 4 周借位滑入 | `widget_test` |
| `lib/widgets/course_tile.dart` | `CourseBlockLayoutSnapshot`, `CourseBlock`, `_BlockPlan` | `letterSpacing: 0` + 预合并、4 步预算求解、`1e-4` 容差、512 LRU、`prewarmEntry()` | `widget_test`, `boost_idle_optimization_test` |
| `lib/widgets/course_detail_sheet.dart` | `kDayLabels`, `compressWeeks()`, `showEntryDetails()` | 课程详情抽屉、周次压缩、单层 `SelectionArea` + `SelectionContainer.disabled` | `widget_test`, `term_calendar_test` |
| `lib/widgets/app_bottom_sheet.dart` | `showAppModalBottomSheet()`, `ScrollableBottomSheetFrame` | `showDragHandle: true` 底部弹窗、80% 屏高上限安全区滚动容器 | `widget_test` |
| `lib/widgets/app_snack_bar.dart` | `AppSnackBarType`, `buildAppSnackBar()`, `showAppSnackBar()` | 单行 `999dp`/多行 `20dp` 悬浮胶囊、`aboveDock` 避让、清前条防排队 | `widget_test` |
| `lib/widgets/status_popup.dart` | `StatusPopup` | 右上角非阻塞气泡、三作用域退避、重试/重登/调试栏 | `widget_test`, `rebuild_scope_test` |
| `lib/widgets/time_wheel_picker.dart` | `showTimeWheel()`, `showTimeRangeWheel()`, `showDurationWheel()`, `showMonthDayWheel()`, `showBigBreakWheel()`, `showSectionCountWheel()`, `showWeekCalibrationWheel()` | 7 类 `CupertinoPicker`、鼠标滚轮单格抢占、起止校验 | `widget_test` |
| `lib/widgets/desktop_widget_preview.dart` | `PreviewWallpaper`, `samplePreviewClock()`, `buildSampleWidgetSnapshot()`, `DesktopWidgetPreview` | 与原生小组件像素同构预览、10:40 黄金快照、`TextScaler.noScaling` | `widget_settings_page_test` |
| `lib/widgets/page_skeleton.dart` | `CardListTransitionPlaceholder`, `DocumentTransitionPlaceholder`, `PreviewSettingsTransitionPlaceholder` | 260ms 转场纯色骨架（零 Ticker/排版、`ExcludeSemantics`） | `page_transition_test`, `boost_idle_optimization_test` |
| `lib/widgets/reminder_permission_tile.dart` | `ReminderPermissionTile`, `showReminderGuideToast()` | 权限项（`ok`: `true` 绿/`false` 红/`null` 橙）、跳系统设置 Toast/SnackBar 指路 | `widget_test` |
| `lib/widgets/section_title.dart` | `SectionTitle` | 分组标题（`12sp`、`w500`、`hintColor`、`letterSpacing: 0.3`） | `widget_test` |
| `lib/widgets/changelog_category_badge.dart` | `ChangelogCategoryBadge` | 新增/优化/修复/碎碎念徽章（`AppColors.category*`） | `formatted_text_span_test`, `updater_test` |

### 1.2 页面索引（`lib/pages/*` 18 页）
> 全量文件与导出见 [`FILE_MAP.md`](FILE_MAP.md) §1.5；各页 `Listenable` 订阅与交互契约见下方 §5。

---

## 2. 应用入口与顶层路由（`main.dart`）

- **启动**：`WidgetsFlutterBinding.ensureInitialized()` → `unawaited(loadAppVersion())`（禁 `await` 阻塞首帧，未就绪前 `appVersion == '-'`）→ `CourseApp`（`theme: buildLightTheme()`、`scrollBehavior: AppScrollBehavior()`、`locale: Locale('zh', 'CN')`，支持 `zh_CN`/`en`）。
- **`_AppShellState` 生命周期**：
  - `initState`（先挂监听再 `boot`）：① 仅 `TargetPlatform.android` 创建 `ReminderService` 与 `DesktopWidgetService`（桌面为 `null`）；② 订阅 `_model.hints` 与 `_model.routeNotifier` (`_onModelChanged`)；③ `_model.boot()`；④ `AppLifecycleListener(onShow: _onShown)`。
  - `_onShown()`：`await _model.onAppShown()`；满足 60s 同日冷却（`_foregroundForceSyncCooldown`）或跨天后，经 `_foregroundSyncTimer` 延迟 `600ms` 再触发 `_reminders?.syncNow(force: true)` 与 `_desktopWidgets?.syncNow(force: true)`（避开桌面小组件进场缩放动画）。
  - 存储异常：`_model.storageNoticeEvent != _lastStorageNoticeEvent` 且非 `booting` 时，post-frame 弹 `showAppSnackBar(type: error, aboveDock: status == ready, duration: 4s)`。
  - `dispose` 顺序：`_foregroundSyncTimer?.cancel()` → `_lifecycle` → 移除监听器 → `_reminders?.dispose()` / `_desktopWidgets?.dispose()` → 最后 `_model.dispose()`。
- **顶层状态路由 `pageForStatus`**（`_AppShell.build` **仅**监听 `model.routeNotifier`）：

| `AppModel.status` | 条件 | 目标页面 | 说明 |
| :--- | :--- | :--- | :--- |
| `booting` | — | `_BootScreen` | 冷启动过渡 |
| `needLogin` | — | `LoginPage` | 无 Dock 全屏登录 |
| `needCaptcha` | — | `CaptchaPage` | 验证码挑战 |
| `signingIn` | `captcha != null` / `== null` | `CaptchaPage` / `LoginPage` | 留在对应提交页 |
| `failed` | `schedule == null` | `LoginPage` | 无缓存回登录页，错误由右上角 `StatusPopup` 展示 |
| `failed` | `schedule != null` | `HomeShell` | 保留离线课表，`StatusPopup` 提供「重试 / 重新登录」，仅主动进 `needLogin` 才跳登录 |
| `loading` / `ready` | — | `HomeShell` | 铺开网格/主界面 |

---

## 3. 主题、圆角、配色与转场（`lib/theme/*`）

### 3.1 `AppRadius` 圆角令牌

| 令牌 | 值 (dp) | 适用场景 |
| :--- | :---: | :--- |
| `AppRadius.card` | `20.0` | 主卡片、BottomSheet 顶角、菜单外框、多行 SnackBar、Hero 卡 |
| `AppRadius.medium` | `14.0` | 输入框（`hintStyle`: `onSurfaceVariant` 40% alpha、`14sp` 常规）、块级按钮、横幅、子卡片 |
| `AppRadius.small` | `8.0` | `CourseBlock`、成绩徽章、小色块、内嵌列表块 |
| `AppRadius.micro` | `6.0` | 极小状态徽章（「使用中」「未显示」、考试倒计时、`ChangelogCategoryBadge`） |
| `AppRadius.pill` | `999.0` | 单行 `AppSnackBar`、触控操作按钮默认圆角、分段胶囊 |

> 同心圆角：菜单外框 `20dp` - 内边距 `6dp` = `_kMenuPillRadius = 14.0`；顶栏 `36×36` 圆按钮半径 `18.0`。

### 3.2 `AppColors` 语义色令牌全表（25 项，`AppColors.of(context)` 无扩展回退 `AppColors.light`）

| 令牌 | 色值 | 语义 | 令牌 | 色值 | 语义 |
| :--- | :--- | :--- | :--- | :--- | :--- |
| `success` | `0xFF2E7D32` | 成功/已登录/正常权限/代理 `<600ms` 前景 | `conflictCardBg` | `0xFFFFE9A8` | 调课抽屉「未显示」标签底 |
| `successContainer` | `0xFFE8F5E9` | 代理 `<600ms` 背景 Chip | `conflictDot` | `0xFFE6A700` | 表头冲突黄点 `5×5` / 警告图标 |
| `warning` | `0xFFB26A00` | 未知权限 (`ok==null`) / 调试 4xx 警告 | `conflictBadge` | `0xFFE53935` | 课块左上冲突红点 `6×6`+`1dp`白边 (`'course-conflict-badge'`) |
| `warningStrong` | `0xFFE65100` | 代理 `600..1499ms` 前景 | `examOngoingBg` | `0xFFFF9800` | `NextExamHeroCard`「正在进行」底 |
| `warningChipBg` | `0xFFFFF3E0` | 代理 `600..1499ms` 背景 Chip | `examUrgentBg` | `0xFFFF5252` | `NextExamHeroCard`「今天考试」底 |
| `warningBannerBg` | `0x26FFC107` | 学业「评教尚未完成」卡底 | `examTomorrowBg` | `0xFFFFAB40` | `NextExamHeroCard`「明天考试」底 |
| `warningBannerBorder` | `0x66FFA000` | 学业「评教尚未完成」卡描边 | `onExamAccentBadge` | `Colors.white` | 上述三紧急考试徽章文字 |
| `onWarningBanner` | `0xFFFF6F00` | 学业「评教尚未完成」图标/文字 | `categoryAdd` | `0xFF2E7D32` | `ChangelogCategoryBadge`「新增」 |
| `danger` | `0xFFC62828` | 代理不可用/`>=1500ms` 前景 | `categoryImprove` | `0xFF1976D2` | `ChangelogCategoryBadge`「优化」 |
| `dangerContainer` | `0xFFFFEBEE` | 代理不可用/`>=1500ms` 背景 Chip | `categoryFix` | `0xFFE65100` | `ChangelogCategoryBadge`「修复」 |
| `scoreExcellent` | `0xFF009688` | 学业优秀成绩 (`>=90` 或 `'优秀'`) | `categoryNote` | `0xFF7B1FA2` | `ChangelogCategoryBadge`「碎碎念」 |
| `gridLine` | `0xFFE4E6EB` | 课表网格线 (`_GridPainter`) | `captchaSurface` | `Colors.white` | 验证码固定浅底画布 |
| `timeAxisText` | `0xFF8C929B` | 课表左侧时间轴起止时刻小字 | | | |

### 3.3 `CoursePalette` 色板与 FNV-1a 哈希
- `indexOf(courseName)`：空串返 `0`；否则 `hash = 2166136261`，遍历 `codeUnits` 执行 `hash = (hash ^ unit) * 16777619 & 0x7fffffff`，返回 `hash % 9`（与 Android 原生小组件同构）。
- `CourseColor.border` 恒为 `foreground.withValues(alpha: 0.18)`。

| # | 色相 | `colors[i]` (`bg` / `fg`) | `darkColors[i]` (`bg` / `fg`) | # | 色相 | `colors[i]` (`bg` / `fg`) | `darkColors[i]` (`bg` / `fg`) |
| :---: | :---: | :--- | :--- | :---: | :---: | :--- | :--- |
| `0` | 蓝 | `0xFFE6F1FB` / `0xFF0C447C` | `0xFF15293E` / `0xFF9ECAFF` | `5` | 粉 | `0xFFFBEAF0` / `0xFF72243E` | `0xFF361D29` / `0xFFF6B2CE` |
| `1` | 青 | `0xFFE1F5EE` / `0xFF085041` | `0xFF122C26` / `0xFF8BE2CC` | `6` | 紫 | `0xFFEEEDFE` / `0xFF3C3489` | `0xFF25203E` / `0xFFC5BFFF` |
| `2` | 绿 | `0xFFEAF3DE` / `0xFF27500A` | `0xFF1B2E17` / `0xFFA9DF9A` | `7` | 红 | `0xFFFCEBEB` / `0xFF791F1F` | `0xFF381C1E` / `0xFFF6B0B0` |
| `3` | 琥珀 | `0xFFFAEEDA` / `0xFF633806` | `0xFF332613` / `0xFFF3C87D` | `8` | 灰 | `0xFFF1EFE8` / `0xFF444441` | `0xFF272624` / `0xFFD0CEC6` |
| `4` | 珊瑚 | `0xFFFAECE7` / `0xFF712B13` | `0xFF352019` / `0xFFF5B7A3` | | | | |

### 3.4 M3 浅色主题、`AppScrollBehavior` 与 `_SlideTransitionsBuilder`
- **基础主题**：`_seed = 0xFF3F5AA6`、`_canvas = 0xFFF6F7F9`、`surfaceContainerLowest = Colors.white`、`splashFactory = NoSplash.splashFactory`、`CardThemeData.clipBehavior = Clip.antiAlias`（纯展示长列表如 `ChangelogPage` 单卡显式 `Clip.none`）。
- **`AppScrollBehavior`**：放行 `touch`/`mouse`/`trackpad`/`stylus`/`invertedStylus`。
- **`_SlideTransitionsBuilder`**（零 `Opacity`/零 `SnapshotWidget`/无离屏 `saveLayer`）：
  - 时长：正向 `260ms`、反向 `240ms`，曲线 `Curves.easeOutCubic`。
  - 位移：新页 `Offset(1,0) -> zero`（`fullscreenDialog` 为 `(0,1) -> zero`）；旧页（含 `route.isFirst`）视差 `Offset(-0.24, 0)`（`_exitParallaxDistance = 0.24`）。
  - `_ContinuousCurveAnimation`：正反向均 `easeOutCubic`；半途折返以 `_evaluate(raw)` 为 `_fromVisual` 重映射至 `1.0`/`0.0` 零跳变。
  - `_EdgeShadowPainter`：左缘 `-16dp..0` 分 8 条竖带（`_shadowWidth = 16.0, _bandCount = 8`）二次递增，峰值 alpha `0.08`，末尾 `edgeFade = ((1 - p) * 6).clamp(0, 1)` 消隐。
  - `_RouteScrimPainter`：旧页前景单矩形暗遮罩，峰值 alpha `0.06 * p`。
  - 子树：`SlideTransition(_primaryOffset) -> SlideTransition(_secondaryOffset) -> CustomPaint(_EdgeShadowPainter) -> CustomPaint(fg: _RouteScrimPainter) -> RepaintBoundary -> AppMenuScope(child)`（转场期页面内容 0 重绘；路由级 `AppMenuScope` 使菜单随页滑入/退场自动收起）。

---

## 4. 核心自定义物理组件与渲染契约（`lib/widgets/*`）

### 4.1 `HomeShell` + `FloatingDock` 单一运动源与液态透镜

- **单一运动源 `_ShellPager`**（`Stack` + `Transform.translate`，无自身控制器）：
  - `_positionNotifier`（`0.0` 课表 / `1.0` 学业 / `2.0` 设置）仅由 `FloatingDock.onPillProgress` 经 `followPill(progress)` 写入：`(progress * maxPage).clamp(0, maxPage)`。
  - **按需单页懒建常驻**：首帧仅建 `_schedulePage`，其余为 `SizedBox.shrink()`；`onTargetIndexHint` / `onIndexSelected` 仅懒建目标单页（`0 <-> 2` 绝不建 `1`），建后常驻保留滚动与状态。
  - **抢跑解锁与离场锁死**：每页包裹 `Transform.translate(key: ValueKey('shell-page-$index')) -> AppMenuScope(activeListenable: _pageActiveNotifiers[index]) -> IgnorePointer(ignoring: _interactionBlocked || index != widget.index) -> TickerMode(enabled: index == widget.index) -> RepaintBoundary`。目标确定即切 `index` 解锁目标页、锁死离场页；按住 Dock 预览（`onPointerActiveChanged(true)`）时 `_interactionBlocked = true` 暂锁全内容区。
- **`FloatingDock` 几何**：`height = 58.0`、`bottomMargin = 16.0`、`contentInset(context) = 58 + 32 + padding.bottom`；理想项宽 `74.0`、间距 `10.0`、左右内边距 `6.0`，窄屏压缩下限缩放 `0.58` / 间距 `2.0`。切页目标按等分 `1/n`（`_indexAt(x)`）判定，静态落点 `_rects` 由 `GlobalKey` + `localToGlobal` 实测（差 `>0.5px` 更新）。
- **五大物理通道**：

| 通道 | 参数 | 契约 |
| :--- | :--- | :--- |
| `_slide`（中心滑动） | `SpringDescription(1, 1150, 68)`（过阻尼 $\zeta\approx 1.002$），`_slideTolerance(2e-3, 4e-2)` | 同向续速上限 `_maxMonotonicSlideVelocity = 31.5`（$< |r_1| \approx 31.55$）保证严格单调零过冲；反向折返初速归零无反冲 |
| `_followX`（拖随） | `_followRate = 28.0`（`k = 1 - exp(-28*dt)`） | 帧率无关指数追随 `_dragX`，差 `<0.05px` 对齐 |
| `_lift`（鼓起） | 上 `(1, 520, 22)` / 下 `(1, 420, 36)` | 常态 `0`、悬停 `0.25`、按下/拖动 `1.0`；宽 `+16%`、高 `+34%`（`46 -> ~62dp`，`Stack` `Clip.none`），整条 Dock 微放大 `1 + 0.015*t` |
| `_stretch`（速度拉伸） | 二阶欠阻尼 `_stretchK = 340, _stretchC = 15`（$\zeta\approx 0.4$），`_fullStretchSpeed = 1500 px/s` | `target = (v/1500).clamp(-1,1)`；`w *= 1+0.30*|s|`、`h *= 1-0.14*|s|`、前缘偏移 `s*w*0.08`；纯视觉不影响 `_livePillRect.center.dx` |
| `_edge`（橡皮筋） | `(1, 420, 18)` | 拖出边界位移 `_rubber(over, 10) = sign * 10 * (1 - exp(-|over|/60))` |

- **三层液态透镜合成**（`RSuperellipse.fromRectAndRadius(rect, min(w,h)/2)`）：
  1. `_LensBackdropPainter`：`restColor`（`primary 11%` 混 `surfaceContainerLowest`）与 `lensColor`（`primary 4%` 混白取 `92%` alpha）按 `easeOut(lift)` 插值。
  2. `_OutsideLensClipper`：`PathFillType.evenOdd`（`bounds.expandToInclude(rect).inflate(40)` 减 `lensPath`）掏空底层灰图标/字。
  3. `_LensForegroundPainter`：`lensPath` 内绘制预排版 `_LensGlyphEntry`（主色 `activeIcon` + `w600`），每项绕自身 `itemRect.center` 原地放大 `zoom = 1 + 0.28*elev`，外描边 `0.9 + 0.2*elev`。
- **后台停帧收敛**：`TickerMode` 变 `false` 时 post-frame 调用 `_settleImmediatelyForDisabledTickers()` 停动画并收敛（未松手回 `widget.index`，已提交直达 `_preview`）。

### 4.2 `TactileButton`、`TactileAppBar` 四层合绘与 `_ZOrderedRow`

- **`TactileSurfaceStyle`**：`elevated`（`surfaceContainerLowest` + `BoxShadow(rgba(0,0,0,0.045), blur:8, offset:(0,2))`）、`tinted`（`surfaceContainerHigh` alpha `0.56`/禁用 `0.28`，无阴影）、`transparent`（无底无阴影）。
- **物理按压与微拖**：
  - 按压 `_pressSpring(1, 1100, 40)`、释放 `_releaseSpring(1, 760, 46)`；按下 `1.0`、悬停 `0.22`；`pressAmplitude = (0.07 + 8.4 / max(24, extent)).clamp(0.095, 0.26)`，`scale = 1 + pressAmplitude * effectiveP`（36dp 约 `+26%`）。
  - 拖拽回弹 `_rubberSpring(1, 740, 45)`；`_rubberDelta(delta, maxPull) = sign * maxPull * (1 - exp(-|delta|/36))`，横上限 `6dp` / 纵 `7dp`。滚动容器内无自接管 `onTap`/`onMenuOpen` 时超 `_touchSlop` 调 `_cancelPointer()`。
  - `_TactileArenaRecognizer`（继承 `PrimaryPointerGestureRecognizer`）：自带 `onTap`/`onMenuOpen` 时独占竞技场，不穿透外层 `ListTile`/`InkWell`。
- **`onMenuOpen` 三触发**：① 短按抬起（`paintBounds.inflate(6)` 或 `_touchSlop` 内）→ `onMenuOpen(ctx, null)`；② 非鼠标长按 `190ms`（`_holdTimer`）；③ 下拉 `delta.dy > 14 && delta.dy > |delta.dx| * 0.9` → 写 `activeTactileDragStart = (pointer, _lastPos)` 并调 `onMenuOpen(ctx, pointer)`。
- **形变隐退 `activeAppMenuMorph`**（`(RenderObject?, double)`）：前 `14%`（`_kMorphPressEnd`）退按压放大，前 `32%`（`_kMorphFadeEnd`）用 Hermite `u*u*(3-2*u)` 降 `morphOpacity` 至 `0`。
- **`TactileAppBar` + `TactileSurfaceScope` 四层合绘**：`AppBar(clipBehavior: Clip.none)` 包裹 `_RenderTactileSurfaceScope` + `_RenderTactileSurfaceSlot`，绘制严格四层：① `super.paint`（背景/标题，elevated slot 仅登记 `frameSlots`）；② 全部 `slot.paintShadows`（`morphOpacity > 0.001`）；③ 全部 `slot.paintSurface`；④ 全部 `slot.paintForeground`（半透明用局部 `saveLayer`，禁 `FadeTransition` 防 `needsCompositing` 跳层）。
- **派生按钮**：`TactileIconButton`（`36×36`/r`18` + 内层原生 `IconButton`）、`TactileBackButton`（左偏 `12dp` `36×36` + 原生 `BackButton`）、`TactileActionButton`（`TactileActionVariant { filled, tonal, outlined, text }`）。
- **`_ZOrderedRow` / `_ZOrderedItem`**（`widget_settings_page.dart`，`_RenderZOrderedFlex`）：`PointerDown`/`Enter`/`Hover` 置 `elevatedChild`，`paint` 最后绘、`hitTestChildren` 最先测，防紧凑横排胶囊放大被右侧兄弟遮挡。

### 4.3 `AppMenu` 与 `AppMenuScope`

- **两层挂载**：路由级（`_SmoothSlidePageTransition` `SlideTransition` 内）+ 标签页级（`_ShellPager` `Transform.translate` 内、`TickerMode` 外）。
- **空间跟随**：`AppMenuScope` 持 `LayerLink` + `_hostKey`，`showAppMenu` 测相对 `scope.hostRenderBox` 的 `anchor`，菜单挂 `CompositedTransformFollower(link, offset: targetRect.topLeft)`。
- **五重活跃门控 `_computeEffectiveActive()`**：任一为假即 `isActive = false`：① `widget.active`；② `activeListenable?.value`；③ `_parentController?.isActive`；④ `isRouteActiveForAppMenu(_modalRoute)`（需 `isCurrent && isActive && !userGestureInProgress`、主动画非 `reverse`/`dismissed`、次动画非 `forward`/`completed`）。失活时取消按钮 190ms 定时器并 `_dismissHostedSessions`（含第 0 帧预测量；路由被覆盖 `_isRouteCoveredByAnotherRoute` 或 `TickerMode` 停帧时 `immediate: true` 立即清 `OverlayEntry`）。
- **两阶段渲染**：第 0 帧 `_FallbackMeasureLayout`（`Opacity(0)`）测宽高与 `_itemRects`；第 1 帧起计算 `_targetRect`（右半屏 `alignX=1`、左半屏 `-1`、`centerHorizontally` 居中、底不足 `_openUp=true`），交 `RenderMenuMorphBox` 渲染层直接插值（零 rebuild/layout，复用 `ClipRRectLayer`/`TransformLayer`/`OpacityLayer`）。
- **弹簧表**：

| 控制器 | `SpringDescription(m, k, c)` | 特征 / 作用 |
| :--- | :--- | :--- |
| `_widthMorph` 展开 / 收起 | `(1, 960, 41)` / `(1, 1650, 74)` | $\zeta\approx 0.66$ `~325ms` / $\zeta\approx 0.91$ `~160ms`（收起继承速度） |
| `_heightMorph` 展开 / 收起 | `(1, 820, 37.5)` / `(1, 1900, 80)` | $\zeta\approx 0.65$ `~345ms` / $\zeta\approx 0.92$ `~160ms` |
| `_pillSlide` | `(1, 1150, 46)` | $\zeta\approx 0.68$，短菜单高亮胶囊滑动 |
| `_pillPresence`/`_pillStretch`/`_pressLift` | `(1, 960, 42)` | $\zeta\approx 0.68$，浮现/拉伸/整卡按压放大（`liftSpan 3.2%..4.8%`） |
| `_rubberAnim` | `(1, 880, 50)` | $\zeta\approx 0.84$，出界整卡橡皮筋（横 `8dp`/纵 `10dp`）回弹 |

- **交互契约**：
  - `handoffClosingSession`：收起中途重点同按钮，直接继承 `_widthMorph`/`_heightMorph` 当前值与速度反向展开。
  - 短菜单（`!_isScrollable`）：一指滑选、跨分割线按中线吸附 `_nearestSelectable`、滑出边界取消高亮（松手保持打开并复位）；长菜单（`_isScrollable`）：交给 `SingleChildScrollView`，按住 `_MenuTile` 内部绘同源胶囊。
  - `_MenuBarrier`：`_RenderMenuBarrier.hitTest` 调 `FloatingDock.hitTestGlobalPosition(pos, route: modalRoute)`——落在 Dock 内返回 `false` 放行切页，同时 `_handleGlobalPointer` 同步收起菜单；其余菜单外区域全部拦截并 `onDismiss()`。

### 4.4 `WeekPager` 与邻近周预热

- **`WeekPagerController` / `_WeekPagerPosition`**（`lib/widgets/week_pager.dart`）：
  1. **锚点单页**：`_snapPixels(v)` 以起手页 `_gestureOrigin` 为锚；快滑（`v != 0`）目标 `origin ± 1`（已拖超 1 页则 `current.roundToDouble()`）；慢松（`v == 0`）超 `_kFlipFraction = 1/3` 翻页。
  2. **`_IgnoredHold`**：重写 `hold()` 不冻结在途翻页动画/惯性，防连滑吞页。
  3. **`_DeferredDrag`**：静止时 `threshold = 0`（配 `DragStartBehavior.down` 零起拖死区）；在途时 `threshold = kTouchSlop`，达阈值一次性补回位移。
  4. **落页与借位**：手势落页 `_kSnapSpring = SpringDescription.withDurationAndBounce(170ms, bounce: 0)`；程序翻页 `_flipDuration = 180ms`（`Curves.easeOut`）；跨 4 周及以上（`absDelta > 3.0`）走 `animateToPageWithSkip(180ms, easeOut, frontPages: 2.0, backPages: 1.0)`（`_SkipJumpScrollActivity`）。
- **双轨周次 + 空闲预热**（`schedule_page.dart`）：
  - `onPageChanged` 仅改 `_shownWeek`（局部刷新 `_WeekBar` & `_TodayFab`），停稳 `_settleToPage()` 才置 `_syncingFromPage = true` 写 `model.goToWeek(week)`。
  - `_scheduleNeighborPrewarm`：`_WeekView` 采集 `CourseBlockLayoutSnapshot`，静止 `90ms`（`_prewarmDelayTimer`）后按 `[+1, -1, +2, -2]` 每帧 post-frame 切片预热（`chunkSize = 3` 门或 `2ms` 即让出帧并 `ensureVisualUpdate()`），调 `CourseBlock.prewarmEntry`；拖拽/翻页立即 `_cancelNeighborPrewarm()`。

### 4.5 `CourseBlock` 排版预算求解器（`lib/widgets/course_tile.dart`）

1. **样式对齐**：`titleStyle`（`11sp, h:1.25, w500, letterSpacing: 0`）与 `detailStyle`（`9sp, h:1.2, letterSpacing: 0`）显式锁 `letterSpacing: 0`，在 `build` 与 `prewarmEntry` 预合并 `DefaultTextStyle` 与 `boldText`，同一份 `effective*Style` 喂给 `_BlockPlan.solve` 与 `Text`。
2. **几何扣除**：外框 `top = (start-1)*rowHeight + 2`、`height = max(26, (end-start+1)*rowHeight - 4)`；冲突分栏 `gap = 2.5`、`width = max(24, (dayWidth-4)/slot.total - (slot.total>1 ? 2.5 : 0))`；内框扣 `_paddingX=3`/`_paddingY=3`（6dp）+ `1dp` 描边（2dp）→ `inner = outer - 8.0`。
3. **`_BlockPlan.solve` 四步**：
   - Step 0：`TextPainter.computeLineMetrics().length` 测自然行数（地点经 `roomOnly()` 剥校区）。
   - Step 1（超 `height + 1e-4` 砍行）：课程名压至 1 行 → 教师清零 → 地点逐行清零 → 课程名清零。
   - Step 2（回填）：地点 → 教师 → 课程名，满足 `fits()` 即保留。
   - Step 3（释余）：`titleLines >= titleNeeded` 且 `remaining > lineHeight` 时追加 `(remaining / lineHeight).floor()` 行兜底亚像素换行。
4. **容差与 LRU**：`fits()` 用 `_epsilon = 1e-4`；`_BlockPlan._cache` 为 `LinkedHashMap` LRU，容量 `_maxCacheEntries = 512`，宽高按 `(v * 1000).round()` 索引，颜色归一化为 `_cacheDummyColor`。

### 4.6 其余公共组件契约

- **`StatusPopup`**（`status_popup.dart`）：三作用域 `HintScope.global`（`HomeShell`/`LoginPage` 顶层不动）、`schedule`/`academic`（随页平移）。`isGlobalPopupActive == true` 时局部气泡返 `null` 退避；`needLogin`/`needCaptcha` 下 `global` 返 `null`。`failed` 时 `canRetry`（`academic` 恒 `true`；`global` 绑 `model.canRetryError`，即 `schedule != null && errorCode != 'WEB_LOGIN_REQUIRED'`）显示「调试」（`onOpenDebug`）与主按钮（`model.needsReloginError` 显 `'重新登录'` 否则 `'重试'`，统一调 `model.retry()`：先重试 `_pendingSchoolSwitchUrl` → `retryAfterSessionLoss()` → `_loadSchedule(forceForeground: true)` 成功保 1.5s `'已更新'`）。`isAcademicUpdateHint` 点击清提示并 `onNavigateToAcademic`（`FloatingDock.animateToIndex(1)`）。
- **`AppSnackBar`**（`app_snack_bar.dart`）：弹前 `hideCurrentSnackBar()`；`_AppSnackBarPill`（最大宽 `420dp`）用 `TextPainter(maxLines: 1)` 测宽，单行 `999dp` 胶囊、多行 `20dp` 圆角卡；`aboveDock: true` 底距 `FloatingDock.contentInset(ctx) + 4`，否则 `40 + padding.bottom`。
- **`TimeWheelPicker`**（`time_wheel_picker.dart`）：`_Wheel` 每项 `Listener` 经 `pointerSignalResolver.register` 抢占鼠标滚轮实现单格滚动（`120ms easeOut`）。7 选择器：`showTimeWheel`（分钟数 `snapToFiveMinutes`）、`showTimeRangeWheel`（`_end <= _start` 禁确定并提示 `'结束时间要晚于开始时间'`）、`showDurationWheel`（5 分步进默认 `5..180`）、`showMonthDayWheel`（`ValueKey<int>(_month)` 换月夹取天数）、`showBigBreakWheel`、`showSectionCountWheel`（校验 `1 <= total <= maxSections(20)`）、`showWeekCalibrationWheel`（`1..maxWeek`，恢复默认返 `0`，取消返 `null`）。
- **`DesktopWidgetPreview`**（`desktop_widget_preview.dart`）：外包 `TextScaler.noScaling` 免疫系统大字；`_PreviewColors.resolve` 与 Android `WidgetThemeResolver.kt` 同构（`opacity <= 0.01` 透明无框 `_cornerClearance = 0`；`< 0.35` 用 `lowOpacityFactor = ((0.35 - opacity)/0.35).clamp(0,1)` 提纯色对比度，无文字阴影）。标准尺寸：今日 4×2 `336×176` / 2×2 `176×176`（底内边距 `0`）；本周 4×4 `316×316`；下一节 2×2 `176×176` / 4×1 `336×76`。`buildSampleWidgetSnapshot` 固定 `10:40` 第 2 周，含已结束（1-2 节 `08:30-10:05`）、进行中（3-4 节 `10:25-12:00`）、第 1 周周日调入待上（5-6 节 `13:30-15:05`, `rescheduled: true`）、当天下午考（`16:00-17:40`）与 3 天后未来考。

---

## 5. 页面级 `Listenable` 订阅隔离与交互契约（`lib/pages/*` 18 页）

> **铁律**：严禁盲目订阅根 `AppModel`，必须按最小职责订阅细分通道（`test/rebuild_scope_test.dart` 守护）。

### 5.1 全量 18 页订阅隔离总表

| 页面 / 区域 | 订阅的 `Listenable` | 触发重建事件 | 严格隔离（0 重建） |
| :--- | :--- | :--- | :--- |
| `_AppShell` (`main.dart`) | `routeNotifier` | `AppStatus`/错误码/课表有无/验证码切换 | 提示气泡、刷新转圈、切周、学业、偏好 |
| `HomeShell` | State 听 `updateFlow`；顶层气泡 `hints + routeNotifier` | 下载完成/失败（弹 SnackBar）；全局提示（仅气泡） | 切周、局部提示、偏好（`HomeShell` 自身 0 重建） |
| `SchedulePage` `_WeekBar` | `scheduleState + routeNotifier` + `_shownWeek` | 手势跨页、切周、课表加载完成 | 气泡、刷新转圈、学业、设置 |
| `SchedulePage` 刷新键 | `routeNotifier + refreshingNotifier` | `status == ready`、`refreshing` 切换 | 切周、气泡、外观滑块 |
| `SchedulePage` `_UpdateStatusButton` | `updateFlow` | 发现更新、下载进度/完成/失败 | 课表与学业一切变化 |
| `SchedulePage` `_WeekPager` | 外：`routeNotifier + scheduleState + prefsNotifier`；内：`weekNotifier + _shownWeek` | 课表/学期/偏好变化；`weekNotifier` 仅滚 PageController 不重建网格 | 滑周中不写 `model.week`；气泡/`refreshing` 不重建网格 |
| `SchedulePage` `_TodayFab` | `_shownWeek + routeNotifier + scheduleState` | 显示周是否等于 `currentWeekOfToday` | 气泡、刷新转圈、学业 |
| `SchedulePage` `StatusPopup` | `hints + routeNotifier + refreshingNotifier` | `scheduleHint` / 全局退避 | 切周、偏好 |
| `AcademicPage` 主体 / 气泡 | 主体：`academicNotifier + scheduleState`；气泡：`hints + routeNotifier + academicNotifier` | 考试/成绩/评教/学业学期/`termStart`；`academicHint` | 课表切周、课表提示、偏好 |
| `SettingsPage` | 主体：`prefsNotifier`；权限卡：`_statusNotifier` | 偏好开关/作息/调课/校准/代理、账号身份 | 后台刷新无内容与身份变更（`hydrate` 不发 `prefsNotifier`）、切周、气泡、学业 |
| `AppearanceSheet` / `ReschedulePage` / `TimetableListPage` / `SchoolAddressPage` | `prefsNotifier` | 对应偏好项（外观/调课/作息与节数/地址簿与线路） | 气泡、切周、后台刷新、学业 |
| `AboutPage` / `UpdateProxyPage` | `prefsNotifier` | `selectedUpdateProxy` / `customUpdateProxies` | 课表、周次、学业 |
| `LoginPage` / `CaptchaPage` | `LoginPage` 横幅 `routeNotifier`、气泡 `hints + routeNotifier`；`CaptchaPage` `routeNotifier` | 登录态/验证码/全局错误提示 | 偏好、切周、学业 |
| `TimetableEditPage` / `ChangelogPage` / `DebugPage` | `TimetableEditPage` 本地 `_draft`；`ChangelogPage` 本地 `_releases` + `RouteSettledStateMixin`；`DebugPage` 静态读 `model` + `RouteSettledGate` | 仅局部交互 / 路由落稳 | 不订阅 `AppModel` 通道 |
| `ReminderPage` | 设置卡：`prefsNotifier + _statusNotifier`；权限/诊断卡：仅 `_statusNotifier` | 提前量拖动仅局部 `_leadDraft`；原生状态仅刷权限/诊断卡 | 三卡互不波及，不整页 rebuild |
| `WidgetSettingsPage` | 主体：`prefsNotifier`（State 听 `model + academicNotifier` 仅源 key 变才刷新 `_cachedRealSnapshot`）；计数：`_pinnedCounts` | 滑块拖动仅改局部草稿（**0 次 `buildSnapshot()`**），`onChangeEnd` 持久化 | 滑块拖动不重算 14 天快照 |

### 5.2 各页面核心交互与特例明细

- **`SchedulePage`**：首帧 `model.checkAutoUpdate`（同会话一次），`dispose` 调 `cancelAutoUpdate()`；三点 `_MoreMenu` 含校准周次/作息表/教务地址/分隔线/外观/调课；周次条 `showWeekPicker(centerHorizontally: true, maxHeight: 340)`；表头 `_DayHeader` 当天 `primary 20%` 高亮、冲突 `5×5` 黄点，调课冲突点击弹 `showDayConflicts`（`_DayConflictSheet`）；`showScheduleRemarksSection` 控制底部 `_ScheduleRemarks`（`sjkList`）。
- **`AcademicPage`**：`isActive && exams.isEmpty && grades.isEmpty && !academicLoading && !isNotEvaluated` 才 post-frame 调 `loadAcademicData()`。`sortAcademicExams(exams, now)` 三级排序：Tier 0（`!isExamPast && startTime != null`：日期 → 有 `\d{1,2}:\d{2}` 优先 → `startTime` → `endTime` → 课名，**首条提取为 `NextExamHeroCard` 不在列表重复**）、Tier 1（`startTime == null`，课名升序）、Tier 2（`isExamPast`，沉底标「已结束」，`startTime` 升序）。`formatExamTimeLabel(exam, currentTermStart)` 仅当前学期（`currentTermId == model.termId && loadedAcademicTerm == model.termId`）且不早于开学周一且原串无周次/星期时追加 `'·第X周 周X'`。`_LazyCardSegment` + `_CardSegmentShape` 在 `SliverList.builder` 实现整卡外观 + Sliver 懒建。
- **`SettingsPage`**：静默更新展开 `_IntervalStepper`（按小时 `minAutoRefreshIntervalMinutes` 60 .. `maxAutoRefreshIntervalMinutes` 1440）；`_ReminderAndWidgetCard` 仅 Android 渲染，混入 `RouteSettledStateMixin` 落稳提交 `_statusNotifier` 且 `AppLifecycleState.resumed` 刷新；`_PasswordDialog` 先 `model.changePassword` 真登录验证通过再覆盖存储；`_confirmSignOut` 调 `signOut()` + `reminders?.cancelAll()` + `desktopWidgets?.syncNow()`。
- **`AppearanceSheet`**：半透明遮罩 `alpha: 0.06`、格子高度 `50..120` 与字号 `80%..140%`、`_TickedTrackShape` 默认值靶点与归位震动、关闭 `flushAppearance()`。
- **`ReschedulePage`**：月日整体挪课列表、`showMonthDayWheel` 弹窗、同日拦截。
- **`TimetableListPage` & `TimetableEditPage`**：三段节数入口 `showSectionCountWheel`；多作息表上限 `maxTimetables = 20`，新建草稿不落盘直传 `initial`；编辑页 `PopScope(canPop: !_dirty)` 拦未保存改动、快捷生成 `buildSections` 预览确认、点对勾 `upsertTimetable`。
- **`SchoolAddressPage`**：内置 `presetSchoolUrls` 与当前线路隐藏删除；`knownSchools` 快捷 Chip；`MediaQuery.removeViewInsets` 防软键盘挤压；切换地址 `popUntil(isFirst)` + `changeSchool`。
- **`LoginPage` & `CaptchaPage`**：`LoginPage` 学号经 `model.loginPrefillUsername` 预填最近历史账号、可折叠高级教务地址面板（`changeSchool(address, relogin: false)` + `signIn`）；`CaptchaPage` `_cachedImageBase64` 记忆化防重复 `base64Decode`、固定 `captchaSurface`、输入框派生淡化提示色并锁 `letterSpacing: 0`。
- **`DebugPage`**：四页签（概览/请求/原始课表/解析结果）、单层 `SelectionArea`、`_RawRowTile` 展开懒格式化 JSON、清学业缓存按钮。
- **`AboutPage` / `ChangelogPage` / `LicenseTextPage`**：`AboutPage` 落稳清旧包 `cleanOldUpdateFiles`；`ChangelogPage` / `LicenseTextPage` `initState` 并行读 asset + `runInBackground`（`parseChangelogBytes` / `reflowLicenseBytes`），260ms 滑行期（`!isRouteSettled`）仅显 `CardListTransitionPlaceholder` / `DocumentTransitionPlaceholder` 且不 `setState`，`onRouteSettled` 一次性挂载 `SelectionArea` + `ListView`。
- **`UpdateDialog`**：`barrierDismissible: false`；四阶段：`available`（清洗 CI 表 `_ReleaseNotesView`，Android 先检 `canInstallPackages()` 并在 `resumed` 调 `refreshInstallPermissionAndAutoInstall()`）→ `downloading`（后台下载仅收起、顶栏 `_UpdateStatusButton` 显进度；「取消下载」调 `cancelDownload()`）→ `readyToInstall`（Android「立即安装」/ Windows「立即重启更新」）→ `error`（`fallbackDownloadUrl` 浏览器下载 / 重试）。
- **`UpdateProxyPage`**：预设/自定义代理、单/全节点并发测速（延迟着色 + API 诊断 Chip）。
- **`ReminderPage`**：提前量滑块 `_leadDraft` 松手提交 + `_queuedLeadMinutes` 串行合并、流体云开关、立即重排/预览/5s/60s 测试提醒。
- **`WidgetSettingsPage`**：入场后台 Isolate `computeWidgetSettingsSnapshots` 并行算真实+黄金快照、吸顶 `SliverPersistentHeader` 预览舞台、`_ZOrderedRow` 精选预设条、恢复默认支持撤销。

---

## 6. L0–L3 测试矩阵、替身与 CI 门禁

### 6.1 L0–L3 分层与执行铁律

| 层级 | 内容 | 目录 / 命令 |
| :---: | :--- | :--- |
| **L0** | 静态门禁（`<15s`） | `dart format --output=none --set-exit-if-changed lib test` + `flutter analyze --no-fatal-infos lib test`（主工程）/ `dart analyze lib test`（`packages/zf_academic`） |
| **L1** | 协议与纯算法单测 | `packages/zf_academic/test/*_test.dart`（9 文件）+ 主工程纯算法 9 文件 |
| **L2** | 服务编排与状态机 | 注入 `FakeBackend` / `FakeReminderGateway` / `FakeDesktopWidgetGateway` 测单 flight 重登、熔断、`_authEpoch`、防抖与指纹去重 |
| **L3** | UI、物理动效与重建隔离 | `flutter_test` 虚拟时钟帧进，断言弹簧单调、`RepaintBoundary` 0 重绘、`debugOnRebuildDirtyWidget` 0 重建、跨屏 0 溢出 |

> 铁律：① 均在 `qustschedule/` 根目录执行；② 单次进程并发跑全量 `flutter test`（禁循环逐文件启动）；③ 优先向现有 23 文件补用例，临时专项放 `test/custom/*_test.dart`。

### 6.2 主工程测试套件（`test/*.dart`，23 文件）

| 测试文件 | 层 | 守护契约 |
| :--- | :---: | :--- |
| `test/academic_cache_test.dart` | L1 | `CachedTermExams`/`CachedTermGrades` JSON（含 `isNotEvaluated`）、`InMemoryExamCache`/`FileExamCache`/`FileGradesCache` 多学期并发不互覆、损坏容错、`LateExamCache` |
| `test/academic_page_test.dart` | L3 | 空态/刷新/未评教/错误横幅、定性及免修成绩、学期人性化标签与过滤、`sortAcademicExams`/`isExamPast`、`NextExamHeroCard`、`formatExamTimeLabel` 隔离、后台学业差异触发全局气泡 |
| `test/academic_service_test.dart` | L2 | `GradeStats.calculate` 加权 GPA 与扩展及格词表、`AcademicService` 拉取/缓存、`notEvaluated` 保留旧缓存、`syncCurrentTermAsync` 后台同步与并发共享单次重登 |
| `test/app_model_test.dart` | L2 | 冷启动恢复、登录/退登清理、周次/校历/`gridSectionCount` 动态托底、后台刷新与重登流转、改密（`sessionInfo.username` 空回退本地）、切校原地加载与回滚、静默间隔与串联学业、调课 overlay、`_authEpoch`/`_academicLoadSeq` 防写脏 |
| `test/app_version_test.dart` | L1 | `loadAppVersion()` 的 `appVersionFull`/`appVersion` 严格等于 `pubspec.yaml` `version` |
| `test/boost_idle_optimization_test.dart` | L2/L3 | `scheduleAfterRouteSettled`（含 `forward->reverse->forward` 恢复）、`SecureCredentialStore.get` 双 Key 并发、`SafeJsonFile` `>16KB` Isolate + `.bak` 自愈、`boot` 单次目录查询与空闲恢复学业、`ScheduleController`/`AcademicController` 记忆化、邻近周切片预热（`CourseBlock.debugBlockPlanSolveCountForTest` 0 新增）、`HomeShell` 懒建、`CaptchaPage` Base64 缓存、`DebugPage` 懒格式化、`ReminderPage`/`WidgetSettingsPage` 入场并行查询与骨架门控 |
| `test/dock_transition_test.dart` | L3 | 滑行中途抢跑交互、零时长不透明路由静默收敛、离场锁死、按住 Dock 锁内容、`0<->2` 单调不误停、反向零反冲、同向续速无跳变、`AppMenuScope` 随页滑入/划走收起、190ms 长按切页不误弹 |
| `test/formatted_text_span_test.dart` | L1/L3 | `buildFormattedTextSpan` `**加粗**`/`` `代码` `` 及未闭合容错、`parseChangelogBytes` 真实 Isolate、`ChangelogPage` 渲染、当前版描边、`ListView.separated` 懒建 |
| `test/page_transition_test.dart` | L3 | `_SlideTransitionsBuilder` 全宽位移 + `-0.24` 视差、`_ContinuousCurveAnimation` 正反减速与折返零跳变、入场抢跑交互、`ChangelogPage`/`LicenseTextPage` 骨架与重试、`RepaintBoundary` 0 重绘、路由切走自动收 `AppMenu` |
| `test/rebuild_scope_test.dart` | L3 | 6 细分通道互不触发根 `AppModel`；`debugOnRebuildDirtyWidget` 证气泡/转圈/切周/菜单操作时 `HomeShell`/`SchedulePage`/`CourseBlock`/无关按钮 0 重建 |
| `test/reminder_planner_test.dart` | L1 | `planCourseReminders`：1~60 分提前量、按日匹配夏冬表、超节跳过、单双周与调课覆盖、过期不补、`reminderMaxEvents` 截断、跨年、指纹与 payload、`reminderEventId` |
| `test/reminder_service_test.dart` | L2 | `ReminderService`：指纹去重与 `force: true`、改提前量/形态重发、失败重试、在途 `syncNow` 串行跟进、关开关/无课表幂等取消、`preferencesLoaded==false` 守卫、防抖、预览/测试/权限转发 |
| `test/safe_json_file_test.dart` | L1 | `.tmp` 原子写 + `.bak` 轮转、损坏自愈、双坏 `hadUnrecoverableCorruption`、高并发 `updateJson` 排队、连续 `writeJson` 合并、`Preferences`/`FileScheduleCache` 抗损与写失败节流 |
| `test/schedule_service_test.dart` | L2 | Cookie 优先免密/10s 超时/`bootstrap` 同源、`SESSION_EXPIRED` 自动重登、跨接口单 flight、10 分钟 2 次熔断与手动解除、失败回滚旧 Cookie、重登遇验证码、重登互斥阻塞新查询、中途 `signOut` 防复活 |
| `test/term_calendar_test.dart` | L1 | `mondayOf`、`estimateTermStart`（秋 9/1、春 2/23 周一）、`weekOf`/`dateOf` 互逆、`termStartFromWeek`、`occursInWeek`/`entriesOfWeek`、`weekRangeLabel`、`compressWeeks`、`formatIsoDate` |
| `test/term_selector_helper_test.dart` | L1 | `parseEnrollmentYear`（10 位学号前 2 位，修 `2021010101` 误判）、`estimateCurrentAcademicYear`、`filterTerms`（滤入学前/未来/第 3 小学期，保当前）、`formatTermPrimaryLabel` |
| `test/timetable_test.dart` | L1 | `buildSections` 三段累加+大课间、月日生效与跨年回绕、`reconcileSections`、`roomOnly`、`Preferences` schema 1..15 迁移、边界夹取 |
| `test/updater_test.dart` | L2/L3 | `isVersionNewer`、`buildProxiedUrl`、`ReleaseInfo.cleanReleaseBody`、`cleanOldUpdateFiles`、Win 安装/便携匹配、`UpdateFlowController` 单弹窗流转、顶栏更新图标与 SnackBar、`SHA256SUMS`、Win 便携 `robocopy /mir` + VBS、分片下载异常/取消即时中止清句柄 |
| `test/widget_planner_test.dart` | L1 | `buildWidgetSnapshot` 14 天日程+双周网格、课/考混排、`rescheduled: true`、近期考试周次、指纹稳定、`conflictIndex/conflictTotal`、未登录空快照与异常节次防御 |
| `test/widget_service_test.dart` | L2 | `DesktopWidgetService`：`preferencesLoaded==false` 守卫、指纹去重/`force: true`、改样式防抖、跨学期考试隔离、退登下发空快照、`clearAll` 等在途 `syncSnapshot` 防竞态回写 |
| `test/widget_settings_page_test.dart` | L3 | 今日 4×2/2×2 混排、周日衔接下周一、课后切明日、关地点隐座位、14 天过期不误报、本周周末列智能显隐、下一节状态胶囊、0% 透明隐圆角滑块、恢复默认撤销、`360×640` + `2.0×` 字体 0 溢出 |
| `test/widget_style_test.dart` | L1 | `DesktopWidgetStyle` 5 预设（解耦密度/字号/开关）、透明度/圆角/字号(`75%..120%`)夹取、畸形/旧 JSON 迁移、`DesktopWidgetConfigSet` 三类独立持久化（schema 14） |
| `test/widget_test.dart` | L3 | 综合 UI 回归（5000+ 行）：登录、周课表、冲突打点/抽屉、备注开关、`WeekPager` 全手势与借位、通知分离、`HomeShell` 懒建/Dock、时间轴 `FittedBox`、`CourseBlock` M3/粗体扫雷、菜单形变/滑选/Dock 直达、外观面板、液态透镜、作息表草稿编辑、7 滚轮、气泡、地址簿、调试、提醒、`AppSnackBar`、验证码、`TactileAppBar` 四层合绘、单层 `SelectionArea` |

### 6.3 协议包测试套件（`packages/zf_academic/test/*.dart`，9 文件）

| 测试文件 | 守护契约 |
| :--- | :--- |
| `cookies_test.dart` | RFC 6265 `CookieStore`：host-only/Domain、Path 边界（`/jwglxt` 不泄 `/jwglxtx`）、过期/`Max-Age<=0`、`Expires` 逗号、Secure、CAS `adopt`、快照往返、`invalidate` 世代 |
| `cookie_isolate_test.dart` | `FileCookieStorage` 超阈值 Isolate 往返、`ExamItem.effectiveEndTime` 推算 |
| `credential_store_test.dart` | `InMemoryCredentialStore` CRUD、多账号隔离、`credentialStoreKey` 哈希稳定不含明文 |
| `crypto_test.dart` | 正方 CAS 无填充裸 RSA + UTF-16 逆序分块、表单 PKCS#1 v1.5 RSA（base64 公钥校验、畸形拒绝） |
| `exams_test.dart` | `parseExamTime`、`jsonExams` 别名（`cdxqmc`/`xqmc`, `cdmc`/`jxcdmc`）、空课过滤与去重、`effectiveEndTime`（显式/+2h/当日终）、`fetchExams`(`showCount=500`)、`calendarTerm` 东八区防回退 |
| `grades_test.dart` | `jsonGrades`/`GradeItem` 往返、`fetchGrades`(`showCount=500`)、`ErrorCode.notEvaluated` 识别（不误伤含“教学质量评价”的正常列表） |
| `html_test.dart` | 零依赖 HTML 解析器：`closingIndex`/`innerOf` 同名嵌套、自闭合/void、属性引号及 `script`/`style`/注释抗干扰、姓名学号提取 |
| `http_client_test.dart` | `ZfHttpClient`：Cookie、表单空格 `+`、双 `name=mm`、302 POST→GET、`UNTRUSTED_URL`、统一认证归 `SESSION_EXPIRED`、同主机 http 升 https、`inspectResponse` 区分 200 下 `SERVER_ERROR`/`ACCESS_FORBIDDEN`/`PAGE_CHANGED`、读重试 1 次/写不重试 `RESULT_UNKNOWN`、GBK/latin1、真实 `dart:io` |
| `login_test.dart` | `ZhengfangClient`：URL 推导、`probe()`、表单 RSA 登录（`?time=`/双 `mm`/复用公钥/密码错优先）、验证码、Cookie 免登与 `0600`、`checkSession` 三态、`fetchTerms`/`fetchSchedule`（`kbList`+`sjkList`+`cxXsgrkb`）、`FileCookieStorage` 合并与容错 |

### 6.4 测试替身（`test/support/*`）

- **`test/support/fake_backend.dart`**：样本 `sampleSchedule([termId])`（含 `'电力电子技术'`）、`snapshotOf(baseUrl, {value})`、`sampleExams([termId])`（2 门）、`sampleGrades([termId])`（2 门）；`FakeBackend implements ScheduleBackend`（闭包 `fetchBehavior`/`examsBehavior`/`gradesBehavior`/`loginBehavior`/`submitBehavior`/`termsBehavior`，计数 `fetchCount`/`examsCount`/`gradesCount`/`termsCount`/`loginCount`/`submitCount`/`refreshCount`/`importCount`/`closeCount`/`checkSessionCount`，调试字段 `lastScheduleRawBody`/`lastScheduleRows`/`lastTermsRawBody`/`lastImported`）；`FakeSessionRepository` & `FakeScheduleCache`（`saveCount`/`clearCount`/`lastSaved`）；快捷异常 `expired()`、`pageChanged()`、`badCredentials()`。
- **`test/support/fake_reminder_gateway.dart`**：`FakeReminderGateway implements ReminderGateway`（记录 `syncedPayloads`/`testRequests`/`previewRequests`/`toasts`/权限打开计数；`Completer<void>? syncGate` 挂起 `sync()` 测在途并发合并）。

### 6.5 CI/CD 流水线（`.github/workflows/build-release.yml`）

- **触发**：`main`/`master` `push`/`pull_request`（路径过滤 `lib/**`, `test/**`, `packages/**`, `assets/**`, `android/**`, `windows/**`, `pubspec.*`, `analysis_options.yaml`, `.github/**`，排除 `**.md`）、`v*` Tag、`workflow_dispatch`。
- **并发与权限**：分支 `cancel-in-progress: true`，`refs/tags/v*` `false`；顶层 `contents: read`，按需下放 `test` (`actions: write`) 与 `create-release` (`contents: write`)。
- **环境**：Flutter `3.47.7`；Node 24 Actions（`actions/checkout@v7`、`actions/setup-java@v6`、`gradle/actions/setup-gradle@v6`、`actions/upload-artifact@v7`、`actions/download-artifact@v8`、`softprops/action-gh-release@v3`）。
- **四 Job**：
  1. **`test` (`ubuntu-latest`)**：`v*` 校验 Tag == `pubspec.yaml` `v${VERSION}` → 双目录 `dart format` → `flutter analyze --no-fatal-infos` + `dart analyze` → `(cd packages/zf_academic && dart test)` → `flutter test $(find test -path test/custom -prune -o -type f -name '*_test.dart' -print | sort)` → 若有 `test/custom/*_test.dart` 单独运行；非 PR 失败时 `gh run cancel ${{ github.run_id }}` Fail-Fast 中止双端打包。
  2. **`build-android` (`ubuntu-latest`，非 PR)**：JDK 21 + Gradle (`cache-cleanup: never`)；`v*` 强校验 `KEYSTORE_BASE64`/`KEY_STORE_PASSWORD`/`KEY_ALIAS`/`KEY_PASSWORD`（非 Tag 缺则退 debug）；`flutter build apk --release --split-per-abi --target-platform android-arm,android-arm64` → 产出 `QustSchedule_v${VERSION}-arm64-v8a.apk` & `armeabi-v7a.apk`（`archive: false`, `retention-days: 14`）。
  3. **`build-windows` (`windows-latest`，非 PR)**：关 Defender 实时扫描 → `flutter build windows --release` → Inno Setup (`windows\packaging\setup.iss`，检 `$LASTEXITCODE`) 产 `QustSchedule_v${VERSION}-windows-x64-setup.exe` + `Compress-Archive` 产 `QustSchedule_v${VERSION}-windows-x64.zip`（`retention-days: 14`）。
  4. **`create-release` (`needs: [test, build-android, build-windows]`，仅 `v*`)**：提 `pubspec.yaml` 版本、生成 4 包 `SHA256SUMS`（无 `./`）、`git describe --tags --abbrev=0 "${TAG}^"` 生成对比链、提 `CHANGELOG.md` 当前节并拼直连与 `gh-proxy.org` 表格，经 `softprops/action-gh-release@v3` 发布。
