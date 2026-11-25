# Android 桌面小组件技术参考手册 (`WIDGET.md`)

> 「青科课表通」Android 桌面小组件（`today` 今日课表 / `week` 本周课表 / `next` 下一节课）唯一真源技术契约。所有相对路径以 `qustschedule/` 为根。

## 1. 文件与符号索引

### 1.1 Dart 层 (`lib/`)

| 文件 | 核心符号 | 职责与关键常量/方法 |
|---|---|---|
| [`lib/src/widget_style.dart`](../../lib/src/widget_style.dart) | `DesktopWidgetKind`, `WidgetThemeMode`, `WidgetDensity`, `FinishedCourseMode`, `WeekendColumnMode`, `WidgetStylePreset`, `WidgetStylePresetSpec`, `DesktopWidgetStyle`, `DesktopWidgetConfigSet` | 样式模型、5 套预设 `widgetStylePresets`、夹取量化（`widgetMinOpacity`/`Max` `0.0..1.0`, `widgetMinCornerRadius`/`Max` `8.0..28.0`, `widgetMinFontScale`/`Max` `0.75..1.20`）、`clampWidget*()`, `applyPreset()`, `copyWith()`, `defaultsFor()` |
| [`lib/src/widget_planner.dart`](../../lib/src/widget_planner.dart) | `WidgetTimelineItem`, `WidgetDayPlan`, `WidgetUpcomingExam`, `WidgetWeekBlock`, `WidgetWeekPlan`, `WidgetSnapshot`, `buildWidgetSnapshot()`, `buildSignedOutWidgetSnapshot()` | 纯函数离线规划：14 天日程+考试、30 天未结束考试、2~3 周网格、FNV-1a 指纹；`widgetSnapshotVersion=1`, `widgetHorizonDays=14`, `widgetUpcomingExamWindowDays=7`, `widgetExamSnapshotMaxDays=30`, `_computeSnapshotFingerprint()`, `_fnv1a()`, `_stableCourseId` (`c_<hex8>`), `_stableExamId` (`x_<hex8>`) |
| [`lib/src/widget_gateway.dart`](../../lib/src/widget_gateway.dart) | `DesktopWidgetGateway`, `MethodChannelDesktopWidgetGateway` | `qustschedule/widget` 通道封装：`syncSnapshot()`, `clearSnapshot()`, `requestPinWidget()`, `getPinnedCounts()`, `livePinnedCounts` (`ValueNotifier`), `ensurePushHandlerInstalled()` |
| [`lib/src/widget_service.dart`](../../lib/src/widget_service.dart) | `WidgetSnapshotInput`, `DesktopWidgetService` | 监听 `AppModel`/`academicNotifier`/`prefsNotifier`；`preferencesLoaded` 守卫、300ms 防抖、单飞队列、指纹去重与同指纹 `_lastPayloadJson` 复用、跨学期考试隔离；`syncNow({force})`, `captureSnapshotInput()`, `buildSnapshot()`, `clearAll()`, `requestPinWidget()`, `getPinnedCounts()`, `ensureLivePinnedUpdates()`, `_syncEpoch` |
| [`lib/pages/widget_settings_page.dart`](../../lib/pages/widget_settings_page.dart) | `WidgetSettingsPage`, `computeWidgetSettingsSnapshots()`, `_PreviewStageHeaderDelegate`, `_KindSegmentedHeader`, `_PresetStrip`, `_ZOrderedRow`, `_LabeledSliderTile`, `_WidgetTickedTrackShape` | 吸顶折叠预览、后台 Isolate 预计算、滑块草稿 (`_opacityDraft`/`_radiusDraft`/`_fontScaleDraft`)、`_useSampleData`, `_todayNarrow`, `_nextWide`, `_wallpaper`, `_pinnedCounts`, `_commitStyle()`, `_resetCurrentKind()`, `_pinSelectedWidget()` |
| [`lib/widgets/desktop_widget_preview.dart`](../../lib/widgets/desktop_widget_preview.dart) | `DesktopWidgetPreview`, `PreviewWallpaper`, `samplePreviewClock()`, `buildSampleWidgetSnapshot()`, `_PreviewColors`, `_TodayPreviewCard`, `_WeekPreviewCard`, `_NextPreviewCard` | 像素级同构预览、10:40 示例快照、`_resolveTodayForPreview()`, `_resolveNextForPreview()`, `_resolveWeekForPreview()`, `_solvePreviewBlockPlan()`, `_cornerClearance()` |

### 1.2 Android 原生层 (`android/app/src/main/kotlin/com/fangzi/qustschedule/widget/`)

| 文件 | 核心类 / 单例 | 职责与关键方法 / 常量 |
|---|---|---|
| [`WidgetWorker.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetWorker.kt) | `WidgetWorker` (`object`) | 全局单线程执行器 `qust-widget-worker`：`execute()`, `runBroadcastAsync(receiver, tag, block)` |
| [`WidgetBridge.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetBridge.kt) | `WidgetBridge` | `CHANNEL = "qustschedule/widget"` `MethodCallHandler`：`attach()`, `dispose()`, `onMethodCall()`, `dispatchPinnedCountsChanged(counts)` |
| [`WidgetStore.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetStore.kt) | `WidgetStore`, `WidgetSnapshotModel`, `WidgetStyleData`, `TimelineItemData`, `DayPlanData`, `UpcomingExamData`, `WeekBlockData`, `WeekPlanData` | `SharedPreferences` (`qust_desktop_widget_v1`) + 内存缓存；`KIND_TODAY`/`KIND_WEEK`/`KIND_NEXT`, `kindSignature()`, `saveSnapshot()`, `loadSnapshot()`, `saveTodayHeaderSig()`, `saveTodayWidthDp()`, `bumpTodayRevision()`, `saveLastWeekRenderDateIso()`, `clear()` |
| [`WidgetContentResolver.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetContentResolver.kt) | `WidgetContentResolver`, `TodayWidgetViewModel`, `NextWidgetViewModel`, `WeekWidgetViewModel`, `NextStatusKind`, `WidgetRefreshPlan` | `UPCOMING_EXAM_WINDOW_DAYS = 7`, `resolveToday()`, `resolveNext()`, `resolveWeek()`, `computeNextRefreshPlan()`, `formatTimeRange()`, `calendarDayDiff()` |
| [`WidgetThemeResolver.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetThemeResolver.kt) | `WidgetThemeResolver`, `ResolvedWidgetTheme`, `CourseChipColor`, `WidgetPillTone` | 主题/动态取色/`<35%` 提对比/9 色板/API 24–30 兼容：`LIGHT_COURSE_COLORS`, `DARK_COURSE_COLORS`, `resolve()`, `applyPill()`, `applyRoundedBackground()`, `clearBackground()`, `applyVerticalBar()` |
| [`WidgetBackgroundRenderer.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetBackgroundRenderer.kt) | `WidgetBackgroundRenderer` | `MAX_BG_DIMENSION_PX = 1080`, `resolveSizeDp()`, `cornerClearanceDp()`, `render()`, `toImmutableAshmemFriendly()` (`asShared()` + `prepareToDraw()`) |
| [`WidgetCoordinator.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetCoordinator.kt) | `WidgetCoordinator`, `ActiveWidgetFlags` | 差量重绘、实例统计、`PendingIntent` 工厂：`RC_LAUNCH_IMMUTABLE=3101`, `RC_LAUNCH_TEMPLATE=3102`, `RC_PIN_CALLBACK=3103`, `refreshChangedWidgets()`, `refreshAllWidgets()`, `refreshForScheduledAlarm()`, `syncAlarmState()`, `getPinnedCounts()` |
| [`WidgetRefreshScheduler.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetRefreshScheduler.kt) | `WidgetRefreshScheduler` | 单条 `RTC_WAKEUP` 闹钟：`ACTION_REFRESH_WIDGETS`, `ACTION_WIDGET_PINNED`, `EXTRA_INCLUDE_WEEK="include_week"`, `RC_WIDGET_REFRESH=3001`, `scheduleNext()`, `cancel()` |
| [`WidgetRefreshReceiver.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetRefreshReceiver.kt) | `WidgetRefreshReceiver` | `onReceive()` 处理闹钟、Pin 回调、开机、覆盖安装、时间/时区/日期与精确闹钟权限广播 |
| [`TodayWidgetProvider.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/TodayWidgetProvider.kt) | `TodayWidgetProvider` | `headerSignature()`, `updateAll()`, `updateWidgetById()`, `bindListItems()`, `bindExamBanner()` |
| [`TodayWidgetService.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/TodayWidgetService.kt) | `TodayWidgetService`, `TodayRemoteViewsFactory` | API 24–30 `ListView` 适配器 + 顶栏自愈：`onGetViewFactory()`, `onDataSetChanged()`, `getViewAt()` |
| [`TodayItemViewBinder.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/TodayItemViewBinder.kt) | `TodayItemViewBinder` | `isNarrowWidth(widthDp)` (`< 200`), `buildItemView()` |
| [`NextClassWidgetProvider.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/NextClassWidgetProvider.kt) | `NextClassWidgetProvider` | `updateAll()`, `isStrip` (`hDp < 100`), `isUltraCompactStrip` (`isStrip && wDp < 195`), `isSpaciousTall` (`!isStrip && wDp >= 220`) |
| [`WeekGridWidgetProvider.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WeekGridWidgetProvider.kt) | `WeekGridWidgetProvider` | `WeekRenderKey` + `onAppWidgetOptionsChanged` 无变化跳过：`updateAll()`, `clearRenderCache()`, `updateWidgetWithSnapshot()`（写入 `last_week_render_date_iso`） |
| [`WeekGridCanvasRenderer.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WeekGridCanvasRenderer.kt) | `WeekGridCanvasRenderer` | `MIN_PIXELS_CEILING=640_000f`, `MAX_PIXELS_CEILING=1_050_000f`, `render()`, `solveCourseBlockLayouts()`, `buildBlockLayout()` |

---

## 2. 常见改动定位速查

| 场景 | 目标文件 | 同步约束 |
|---|---|---|
| 新增/修改预设 | [`widget_style.dart`](../../lib/src/widget_style.dart) (`WidgetStylePreset`, `widgetStylePresets`) | 仅绑定 `themeMode`/`backgroundOpacity`(5%步进)/`cornerRadius`，禁改 `density`/`fontScale`/内容开关；跑 `widget_style_test.dart` |
| 调透明度/圆角/字号范围 | [`widget_style.dart`](../../lib/src/widget_style.dart) + [`WidgetStore.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetStore.kt) (`optFiniteFloat`) + [`widget_settings_page.dart`](../../lib/pages/widget_settings_page.dart) (`_LabeledSliderTile`) | Dart/Kotlin clamp 上下限与滑块 `divisions` 一致（`0..1`/20、`8..28`/20、`0.75..1.20`/9） |
| 新增样式字段 | [`widget_style.dart`](../../lib/src/widget_style.dart) + [`WidgetStore.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetStore.kt) + [`widget_settings_page.dart`](../../lib/pages/widget_settings_page.dart) + [`desktop_widget_preview.dart`](../../lib/widgets/desktop_widget_preview.dart) + 原生解析/渲染 | `fromJson` 缺失回退 `base.<field>`，无需升 `Preferences` schema(15)；视觉属性需评估 `-> custom` |
| 修改 9 色板 | [`lib/theme/course_palette.dart`](../../lib/theme/course_palette.dart) + [`WidgetThemeResolver.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetThemeResolver.kt) | 浅/深 9 组 ARGB 与顺序 100% 一致 |
| 修改主题/胶囊对比度 | [`WidgetThemeResolver.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetThemeResolver.kt) + [`desktop_widget_preview.dart`](../../lib/widgets/desktop_widget_preview.dart) (`_PreviewColors`) + `res/drawable/widget_pill_*.xml` / `widget_row_highlight_*.xml` | 纯色提对比、无文字阴影；两端同构 |
| 修改展示文案/筛选 | [`WidgetContentResolver.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WidgetContentResolver.kt) + [`desktop_widget_preview.dart`](../../lib/widgets/desktop_widget_preview.dart) (`_resolve*ForPreview`) | Kotlin 与 Dart 逻辑/文案 100% 同构 |
| 修改周网格行数求解 | [`WeekGridCanvasRenderer.kt`](../../android/app/src/main/kotlin/com/fangzi/qustschedule/widget/WeekGridCanvasRenderer.kt) (`solveCourseBlockLayouts`) + [`desktop_widget_preview.dart`](../../lib/widgets/desktop_widget_preview.dart) (`_solvePreviewBlockPlan`) | 与主课表 `CourseBlock._BlockPlan` 优先级一致 |
| 新增第 4 种形态 | `DesktopWidgetKind` + `*WidgetProvider.kt` + `res/xml` + `res/layout` + `AndroidManifest.xml` + `WidgetStore` (`KIND_*`/`kindSignature`) + `WidgetCoordinator` (`ActiveWidgetFlags`/`componentForKind`) | `computeNextRefreshPlan` 按是否依赖上下课节点设闹钟 |

---

## 3. 分层与数据流

- **Flutter 层**：`WidgetSettingsPage` ↔ `DesktopWidgetPreview`；`WidgetSettingsPage` 调 `AppModel.setWidgetStyle/resetWidgetStyle` + `syncNow()`；`AppModel` (`model`/`academicNotifier`/`prefsNotifier`) → `DesktopWidgetService`（`preferencesLoaded` 守卫 → 300ms 防抖 → 单飞队列 → 跨学期隔离 → `widget_planner.dart` → FNV-1a 去重）→ `MethodChannelDesktopWidgetGateway` (`qustschedule/widget`)。
- **Android 原生层（全量跑在单线程 `WidgetWorker: qust-widget-worker`）**：`WidgetBridge` ↔ `WidgetStore` (`qust_desktop_widget_v1`) → `WidgetCoordinator`（`kindSignature` 差量刷新 + `PendingIntent`）→ `TodayWidgetProvider`/`NextClassWidgetProvider`/`WeekGridWidgetProvider`（均消费 `WidgetContentResolver` + `WidgetThemeResolver` + `WidgetBackgroundRenderer`）+ `WidgetRefreshScheduler`/`WidgetRefreshReceiver`（单条 `RTC_WAKEUP` `RC=3001`）。

---

## 4. 样式系统与预设 (`widget_style.dart` / `WidgetStore.kt`)

### 4.1 枚举与 Wire 值

| 枚举 | 项 (`wireName` · `label`) | 默认回退 |
|---|---|---|
| `DesktopWidgetKind` | `today` (`'today'` · `'今日课表'` · `sizeHint: '4×2 / 2×2 · 时间轴'`)、`week` (`'week'` · `'本周课表'` · `'4×4 · 整周网格'`)、`next` (`'next'` · `'下一节课'` · `'2×2 / 4×1 · 精简卡'`) | `today` |
| `WidgetThemeMode` | `light` (`'light'`·`'浅色'`)、`dark` (`'dark'`·`'深色'`)、`system` (`'system'`·`'跟随系统'`)、`dynamic` (`'dynamic'`·`'壁纸取色'`) | `light` |
| `WidgetDensity` | `compact` (`'compact'`·`'紧凑'`)、`comfortable` (`'comfortable'`·`'舒适'`) | `comfortable` |
| `FinishedCourseMode` | `dim` (`'dim'`·`'置灰'`)、`hide` (`'hide'`·`'自动隐藏'`)、`normal` (`'normal'`·`'正常显示'`) | `dim` |
| `WeekendColumnMode` | `auto` (`'auto'`·`'有课显示'`)、`show` (`'show'`·`'始终显示'`)、`hide` (`'hide'`·`'始终隐藏'`) | `auto` |
| `WidgetStylePreset` | `minimalWhite` (`'minimal_white'`·`'极简纯白'`)、`frostedGlass` (`'frosted_glass'`·`'通透磨砂'`)、`darkNight` (`'dark_night'`·`'暗夜模式'`)、`pureTransparent` (`'pure_transparent'`·`'纯净透明'`)、`materialYou` (`'material_you'`·`'莫奈取色'`)、`custom` (`'custom'`·`'自定义'`) | `minimalWhite` |

> **命名隔离**：`WidgetStylePreset.materialYou` = `'莫奈取色'`，`WidgetThemeMode.dynamic` = `'壁纸取色'`（禁止重名）。

### 4.2 5 套精选预设 (`widgetStylePresets`)

`style.applyPreset(target)` **仅更新** `preset`/`themeMode`/`backgroundOpacity`/`cornerRadius`，保留 `fontScale`/`density` 及全部内容开关。

| 预设 (`wireName`) | `label` | `subtitle` | `themeMode` | `backgroundOpacity` | `cornerRadius` |
|---|---|---|---|---|---|
| `minimalWhite` (`minimal_white`) | 极简纯白 | 纯白清爽底色 | `light` | `1.0` | `20.0` |
| `frostedGlass` (`frosted_glass`) | 通透磨砂 | 半透明玻璃质感 | `system` | `0.75` | `22.0` |
| `darkNight` (`dark_night`) | 暗夜模式 | 深邃柔和暗色 | `dark` | `0.90` | `20.0` |
| `pureTransparent` (`pure_transparent`) | 纯净透明 | 无底融入壁纸 | `dark` | `0.0` | `20.0` |
| `materialYou` (`material_you`) | 莫奈取色 | 随壁纸动态配色 · Android 12+ | `dynamic` | `0.90` | `24.0` |

### 4.3 `DesktopWidgetStyle` / `WidgetStyleData` 14 字段规格

| 字段 (JSON Key) | Dart / Kotlin | 默认 (`today`/`next` \| `week`) | 夹取与量化 | UI 暴露规则 |
|---|---|---|---|---|
| `preset` | `WidgetStylePreset` / `String` | `minimalWhite` | `copyWith` 改视觉三项且未传 `preset` -> `custom` | 全部（仅展示 5 具名预设） |
| `themeMode` | `WidgetThemeMode` / `String` | `light` | 4 枚举 | 全部（`dynamic` 显 Android 12+ 说明） |
| `backgroundOpacity` | `double` / `Float` | `1.0` | `[0.0, 1.0]`, 1% 量化 (`0.01`), 滑块 `divisions: 20` (5%), `NaN->1.0` | 全部 |
| `cornerRadius` | `double` / `Float` | `20.0` | `[8.0, 28.0]`, `roundToDouble()`, `divisions: 20` (1dp), `NaN->20.0` | 全部；`opacity <= 0.01` 时隐藏 |
| `fontScale` | `double` / `Float` | `1.0` | `[0.75, 1.20]`, 5% 量化 (`0.05`), `divisions: 9`, `NaN->1.0` | 全部 |
| `density` | `WidgetDensity` / `String` | `comfortable` | `compact` / `comfortable` | `today` / `week`（`next` 隐藏） |
| `showHeader` | `bool` / `Boolean` | `true` | 非 `bool` 回退 `true` | `today` / `week`（`next` 隐藏，胶囊常驻） |
| `showLocation` | `bool` / `Boolean` | `true` | `bool` | 全部（同时控制考试 `${seatNumber}座`） |
| `showTeacher` | `bool` / `Boolean` | **`true`** \| **`false`** | `bool` | 全部 |
| `showTime` | `bool` / `Boolean` | `true` | `bool` | 全部（标签：`today`「显示上课时间」/`week`「显示左侧节次列」/`next`「显示起止时间」） |
| `showExams` | `bool` / `Boolean` | `true` | `bool` | `today` / `next`（`week` 隐藏） |
| `autoSwitchTomorrow` | `bool` / `Boolean` | `true` | 缺失默认 `true` | 仅 `today`（「课后自动切明日预告」） |
| `finishedCourseMode` | `FinishedCourseMode` / `String` | `dim` | `dim` / `hide` / `normal` | 仅 `today`（「已结束课程」） |
| `weekendMode` | `WeekendColumnMode` / `String` | `auto` | `auto` / `show` / `hide` | 仅 `week`（「周末列显示」） |

### 4.4 持久化 (`DesktopWidgetConfigSet`)

- JSON 为 `{"today": {...}, "week": {...}, "next": {...}}`，存于 [`lib/src/preferences_repository.dart`](../../lib/src/preferences_repository.dart) 顶层键 `"widgetConfig"`（Schema 14 引入，当前 `schema: 15`；`<=13` 或缺失回退 `DesktopWidgetConfigSet.defaults()`）。
- `AppModel` 接口：`widgetConfig`、`widgetStyleOf(kind)`、`setWidgetStyle(kind, style)`、`resetWidgetStyle(kind)`（触发 `prefsNotifier`）。

---

## 5. 离线快照规划与指纹 (`widget_planner.dart`)

- **常量**：`widgetSnapshotVersion = 1`（字段 `'v'`）、`widgetHorizonDays = 14`（`today+0..+13`）、`widgetUpcomingExamWindowDays = 7`（无课时考试倒计时窗口）、`widgetExamSnapshotMaxDays = 30`（`upcomingExams` 收集上限）。
- **归一化**：`safeMaxWeek = max(1, maxWeek)`，`mondayStart = mondayOf(termStart)`，`termStartIso = formatIsoDate(mondayStart)`，`today = dayOnly(now)`。
- **14 天逐日 `days`**：
  - `inTerm = !date.isBefore(mondayStart)`，`week = inTerm ? weekOf(termStart, date) : 0`。
  - **课程**（`inTerm && 1 <= week <= safeMaxWeek`）：`rescheduleWeekView(entries, reschedules, termStart, week, maxWeek: safeMaxWeek)` + `activeTimetableAt(timetables, date)` + `reconcileSections(table.sections, sectionCounts)`，滤 `entry.day == date.weekday && occursInWeek(entry, week)`；防御 `rawEndMinutes < startMinutes -> startMinutes`、`endPeriod < startPeriod -> startPeriod`；`rescheduled` 对比 `entriesOfWeek(entries, week)` 无相同 `(id, day, startPeriod, endPeriod)` 为 `true`；地点 `roomOnly(entry.location ?? '')`；ID `c_${_fnv1a('$entryId|$stamp|$startPeriod')}` (8 位十六进制)；色板 `CoursePalette.indexOf(normalizedName)`。
  - **同日考试**：`_isSameDay(exam.startTime, date)`；`_resolveExamEnd`（`null -> start + 2h`，`< start -> start`）；`_examLocationOf`（`classroom.trim()` 优先于 `campus.trim()`）；ID `x_${_fnv1a('${exam.courseName}|$startMs|${exam.classroom}')}`；`startPeriod=0, endPeriod=0, teacher='', rescheduled=false`。
  - **排序**：`startMs` ↑ → `startPeriod` ↑ → `id` ↑。
- **30 天未结束考试 `upcomingExams`**：`exam.startTime != null && endMs > nowMs` 且 UTC 日差 `diffDays <= 30`；`week > safeMaxWeek` 记 `0`；按 `startMs` ↑ → `courseName` ↑。
- **2~3 周网格 `weeks`**：`currentWeek = today.isBefore(mondayStart) ? 1 : weekOf(termStart, today).clamp(1, safeMaxWeek)`，`horizonEnd = today + (daysCount - 1)`，`horizonEndWeek` 同理，`targetEndWeek = min(safeMaxWeek, max(currentWeek + 1, horizonEndWeek))`，生成 `currentWeek..targetEndWeek`（周一同步 2 周，周二至周日跨入第 3 周则 3 周，避免第 8 天提前过期）。每周调用 `conflictLayout(view.entries)` 得 `(conflictIndex, conflictTotal)`，`maxSection = max(sections.length, maxEntryPeriod)`，`dayLabels` 格式 `'M/D'`。
- **FNV-1a 32 位指纹**：对 `_canonicalBody()`（排除 `generatedAtMs`、`fingerprint`）UTF-8 字节算 FNV-1a（初值 `0x811C9DC5`，乘数 `0x01000193`，`& 0xFFFFFFFF`，8 位小写 hex），对 `now` 幂等。

---

## 6. MethodChannel 协议与 JSON Schema (`qustschedule/widget`)

### 6.1 通道方法

| 方向 | 方法 | 参数 | 返回 | 行为 |
|---|---|---|---|---|
| F → A | `syncSnapshot` | `{'payload': String}` | `Future<bool>` | `WidgetWorker` 写 `WidgetStore` + `WidgetCoordinator.refreshChangedWidgets(prev, saved)` + 重排闹钟 |
| F → A | `clearSnapshot` | `null` | `Future<void>` | `WidgetWorker` 调 `WidgetStore.clear()` + `WidgetCoordinator.refreshAllWidgets()` |
| F → A | `requestPinWidget` | `{'kind': 'today'\|'week'\|'next'}` | `Future<bool>` | 主线程 `AppWidgetManager.requestPinAppWidget(component, null, callback)` (API 26+)，成功触发 `ACTION_WIDGET_PINNED` |
| F → A | `getPinnedCounts` | `null` | `Future<Map<String, int>>` | `WidgetWorker` 查三类 `appWidgetIds.size` → `{"today": n1, "week": n2, "next": n3}` |
| A → F | `onPinnedCountsChanged` | `{"today": n1, "week": n2, "next": n3}` | `void` | `onUpdate`/`onDeleted`/`onDisabled`/`ACTION_WIDGET_PINNED` 时主线程回推更新 `livePinnedCounts` |

### 6.2 快照 JSON Schema (`v = 1`)

```json
{
  "v": 1, "signedIn": true, "termId": "2026-2027-1", "termStartIso": "2026-09-07",
  "maxWeek": 18, "generatedAtMs": 1757210400000, "fingerprint": "a1b2c3d4",
  "days": [{
    "dateIso": "2026-09-07", "week": 1, "weekday": 1,
    "items": [{
      "kind": "course", "id": "c_8f3e12a0", "title": "大学物理", "location": "201",
      "teacher": "王老师", "seatNumber": "", "examForm": "",
      "startPeriod": 1, "endPeriod": 2, "startLabel": "08:00", "endLabel": "09:40",
      "startMs": 1757203200000, "endMs": 1757209200000, "colorIndex": 3, "rescheduled": false
    }]
  }],
  "upcomingExams": [{
    "id": "x_4c91b012", "courseName": "信号与系统", "startMs": 1757656800000, "endMs": 1757664000000,
    "dateIso": "2026-09-12", "timeLabel": "14:00-16:00", "week": 1, "weekday": 6,
    "location": "M1-115", "seatNumber": "06", "examForm": "笔试", "colorIndex": 1
  }],
  "weeks": [{
    "week": 1, "startDateIso": "2026-09-07",
    "dayLabels": ["9/7", "9/8", "9/9", "9/10", "9/11", "9/12", "9/13"],
    "maxSection": 10, "sectionStarts": ["08:00", "..."], "sectionEnds": ["08:45", "..."],
    "blocks": [{
      "id": "entry_1", "name": "大学物理", "location": "201", "teacher": "王老师",
      "day": 1, "startPeriod": 1, "endPeriod": 2,
      "conflictIndex": 0, "conflictTotal": 1, "colorIndex": 3, "rescheduled": false
    }]
  }],
  "styles": {
    "today": { "preset": "minimal_white", "themeMode": "light", "backgroundOpacity": 1.0, "cornerRadius": 20.0, "fontScale": 1.0, "density": "comfortable", "showHeader": true, "showLocation": true, "showTeacher": true, "showTime": true, "showExams": true, "autoSwitchTomorrow": true, "finishedCourseMode": "dim", "weekendMode": "auto" },
    "week": { "showTeacher": false, "...": "..." },
    "next": { "showTeacher": true, "...": "..." }
  }
}
```

---

## 7. Flutter 编排服务 (`DesktopWidgetService`)

- **三路监听**：`model`、`model.academicNotifier`、`model.prefsNotifier` → `_onChanged`。
- **`preferencesLoaded` 守卫**：`false` 时 `captureSnapshotInput()` 返回 `null`，`_syncOnce()` 返回 `false`，防冷启动默认样式覆盖磁盘样式。
- **300ms 防抖 + 单飞队列 (`_runSyncLoop`) + 同指纹载荷复用**：变更触发 300ms `_timer`；`_syncInFlight` 在途时不并发，置 `_resyncQueued = true`、`force` 累积到 `_resyncForceQueued`，本轮结束后 `while (!_disposed)` 续跑；`force == true` 且指纹与 `_lastFingerprint` 一致时直接复用 `_lastPayloadJson`，省去重复 `jsonEncode` 并使原生 `WidgetStore` O(1) 命中缓存。
- **跨学期考试隔离**：仅当 `model.loadedAcademicTerm == schedule.termId` 时传入 `model.exams`。
- **退出空态 vs `clearAll()`**：`schedule == null || termStart == null` 下发 `WidgetSnapshotInput.signedOut(styles, now)`（清空隐私、保留样式）；`clearAll()` 递增 `_syncEpoch++`、取消定时器、清空 `_lastFingerprint`/`_lastPayloadJson`/`_lastSnapshot`，`await` 在途 `_syncInFlight` 后再调 `_gateway.clearSnapshot()`。

---

## 8. Android 原生线程、存储与差量协调

### 8.1 `WidgetWorker.kt`

- 唯一单线程池 `Executors.newSingleThreadExecutor { Thread(it, "qust-widget-worker") }`。
- `WidgetBridge` (`syncSnapshot`/`clearSnapshot`/`getPinnedCounts`) 走 `execute` + `mainHandler.post`；所有 `AppWidgetProvider` 与 `WidgetRefreshReceiver` 走 `runBroadcastAsync` (`goAsync()` + `finally { pending.finish() }`)。
- `minSdk = 24`：**禁 `java.time.*`**，统一用 `java.util.Calendar`。

### 8.2 `WidgetStore.kt`

- `PREF_NAME = "qust_desktop_widget_v1"`，写盘同步 `.commit()`。
- **内存缓存与零冗余写盘**：`@Volatile cachedRawJson` / `cachedModel`；`loadSnapshot()` 命中缓存 O(1) 返回；`saveSnapshot()` 在原文一致或解析模型 `(fingerprint, data)` 与已存一致时直接跳过 `.commit()`，`saveLastWeekRenderDateIso()` 同值跳过 `.commit()`；`clear()` 同步清缓存并调 `WeekGridWidgetProvider.clearRenderCache()`。

| Key | 类型 | 用途 |
|---|---|---|
| `"snapshot_json"` | `String` | 完整快照 JSON；`clear()` 移除 |
| `"last_week_render_date_iso"` | `String` | 周课表最近渲染日期 `"yyyy-MM-dd"`（检测跨天未重绘）；`clear()` 移除 |
| `"today_header_sig_<appWidgetId>"` | `String` | 今日顶栏 `headerSignature(vm, style)`，供 API 24–30 `TodayWidgetService` 自愈；`onDeleted` 移除 |
| `"today_width_dp_<appWidgetId>"` | `Int` | 今日实例宽度 `wDp`（默认 `260`），供 `TodayWidgetService` 判 `isNarrowWidth`；`onDeleted` 移除 |
| `"today_list_rev"` | `Int` | 列表递增版本号，拼入 `qust://today_widget/$appWidgetId?rev=$rev` 防旧系统缓存 Intent |

### 8.3 `WidgetCoordinator.kt`

- **`kindSignature(kind)` 差量**：`KIND_WEEK` 仅哈希 `(version, signedIn, termId, termStartIso, maxWeek, weeks, styleOf(KIND_WEEK))`；`KIND_TODAY`/`KIND_NEXT` 哈希 `(version, signedIn, termId, termStartIso, maxWeek, days, upcomingExams, styleOf(kind))`。改单类样式仅重绘该类。
- **`forceTimeWidgets` 兜底**：三类签名均未变且 `weekDateStale == false`（如回前台 600ms 后的 `syncNow(force: true)`）时，仅置 `forceTimeWidgets = true` 重绘今日/下一节，**不重绘周位图**。
- **启动与返回衔接**：显式指向 `MainActivity`，`ACTION_MAIN` + `CATEGORY_LAUNCHER` + `FLAG_ACTIVITY_NEW_TASK | FLAG_ACTIVITY_RESET_TASK_IF_NEEDED`；保持默认 `RenderMode.surface`（避免 `RenderMode.texture` 在 Impeller Vulkan 下多次前后台切换引发交换链阻塞）配合浅色 `LaunchTheme`/`NormalTheme` 与 `MainActivity.popSystemNavigator()` 根栈 `moveTaskToBack(true)`，兼顾零黑闪与反复切换流畅度。
- **RequestCode 分配（严禁与 `reminder/` 的 `2000~2003` 冲突）**：

| RC | 常量 | 类型 | Flag | 用途 |
|---|---|---|---|---|
| `3001` | `WidgetRefreshScheduler.RC_WIDGET_REFRESH` | Broadcast | `UPDATE_CURRENT \| IMMUTABLE` | 单条 `RTC_WAKEUP` 节点闹钟 |
| `3101` | `WidgetCoordinator.RC_LAUNCH_IMMUTABLE` | Activity | `UPDATE_CURRENT \| IMMUTABLE` | 根布局与空白区启动 `MainActivity` |
| `3102` | `WidgetCoordinator.RC_LAUNCH_TEMPLATE` | Activity | `UPDATE_CURRENT \| MUTABLE` (API 31+) | `TodayWidgetProvider` 列表 `setPendingIntentTemplate` + 子项空 `Intent()` |
| `3103` | `WidgetCoordinator.RC_PIN_CALLBACK` | Broadcast | `UPDATE_CURRENT \| IMMUTABLE` | `requestPinAppWidget` 回调 (`ACTION_WIDGET_PINNED`) |

---

## 9. 视图解析与刷新计划 (`WidgetContentResolver`)

### 9.1 今日课表 (`resolveToday`)

| 优先级 | 条件 | `isStale`/`isTomorrow` | `badgeText` (`badgeTone`) | `headerTitle` | `headerRight` | 主体 (`items`/`examBanner`/`emptyMessage`) |
|---|---|---|---|---|---|---|
| 1. 未登录 | `snapshot == null \|\| !signedIn` | `F`/`F` | `""` (`NEUTRAL`) | `"今日课表"` | `"未登录"` | `emptyMessage="打开青科课表通登录后自动同步课表"` |
| 2. 超期 | `days.isNotEmpty() && todayPlan==null && tomorrowPlan==null` | `T`/`F` | `"需刷新"` (`NEUTRAL`) | `"今日课表"` | `""` | `emptyMessage="课表数据已过期，轻触打开应用刷新"` |
| 3. 今日有剩余 | `remainingToday.isNotEmpty()` (`endMs > nowMs`, 按 `showExams` 过滤) | `F`/`F` | `""` (`ACCENT`) | `"第X周 周Y"` | `"剩N节"` (全考试 `"剩N场"`) | `items=visibleToday` (`hide`->`remainingToday`, 否则 `todayAll`) |
| 4a. 关切明日·今日已完 | `!autoSwitchTomorrow && todayAll.isNotEmpty()` | `F`/`F` | `""` (`ACCENT`) | `"第X周 周Y"` | `"已结束"` | `items=visibleToday`；空则 `"今日课程已全部结束"` |
| 4b. 关切明日·无课有考 | `!autoSwitchTomorrow && todayAll.isEmpty() && showExams && nearestExam!=null` | `F`/`F` | `"近期考试"` (`EXAM`) | `""` | `"${remainingCount}场待考"` | `examBanner=nearestExam` (7 天内最近) |
| 4c. 关切明日·无课无考 | `!autoSwitchTomorrow` 兜底 | `F`/`F` | `""` (`ACCENT`) | `"第X周 周Y"` | `"无课"` | `emptyMessage="今日无课，好好休息"` |
| 5. 开切明日·明日有课 | `autoSwitchTomorrow && tomorrowItems.isNotEmpty()` | `F`/`T` | `"明日"` (`TOMORROW`) | `"第X周 周Y"` (明) | `"共N节"` (全考试 `"共N场"`) | `items=tomorrowItems`, `compactCue="明日 · 周Y"` (`showHeader==false` 用) |
| 6. 今明无课·7天内有考 | `showExams && nearestExam!=null` | `F`/`F` | `"近期考试"` (`EXAM`) | `""` | `"${remainingCount}场待考"` | `examBanner=nearestExam` |
| 7. 兜底 | 今明无剩余且无近期考 | `F`/`F` | `""` (`ACCENT`) | `"第X周 周Y"` (今) | `todayAll.isNotEmpty()`?`"已结束"`:`"无课"` | `items=visibleToday`；空则 `"今日课程已全部结束，明日无课"` 或 `"今明两日无课，好好休息"` |

### 9.2 下一节课 (`resolveNext`)

| 优先级 | 条件 | `NextStatusKind` | `badge` | `shortBadge` (`wDp<195`) | `title` | `timeText` / `dateHint` | `subtitle` / `colorIndex` |
|---|---|---|---|---|---|---|---|
| 1. 未登录 | `snapshot==null \|\| !signedIn` | `SIGNED_OUT` | `"青科课表通"` | `"未登录"` | `"轻触登录同步课表"` | `""` / `""` | `"登录后自动显示下一节课"` / `-1` |
| 2. 超期 | `days.isNotEmpty() && todayPlan==null && tomorrowPlan==null` | `STALE` | `"需刷新"` | `"需刷新"` | `"课表数据已过期"` | `""` / `""` | `"轻触打开青科课表通刷新"` / `-1` |
| 3. 进行中 | `todayItems` 含 `startMs<=nowMs<endMs` | `EXAM_ONGOING` / `ONGOING` | `"正在考试"` / `"正在上课"` | `"考试中"` / `"上课中"` | `item.title` | `formatTimeRange` / `""` | `itemSubtitle` / `item.colorIndex` |
| 4. 今日下节 | `todayItems` 首个 `startMs>nowMs` | `EXAM_UPCOMING` / `TODAY` | `"下一场考试"` / `"今日下一节"` | `"考试"` / `"下一节"` | `item.title` | `formatTimeRange` / `""` | `itemSubtitle` / `item.colorIndex` |
| 5. 明日首节 | `tomorrowItems.first()` | `EXAM_UPCOMING` / `TOMORROW` | `"明日考试"` / `"明日第一节"` | `"明考"` / `"明日"` | `first.title` | `formatTimeRange` / `""` | `itemSubtitle` / `first.colorIndex` |
| 6. 7天内考 | `showExams && nearestExam!=null` (`days=calendarDayDiff<=7`) | `EXAM_UPCOMING` | `days<=0`?`"今天考试"`:`"考试倒计时 ${days}天"` | `days<=0`?`"今日考"`:`"${days}天后考"` | `nearestExam.courseName` | `timeLabel` / `"M/D 周X"` | 地点+`${seatNumber}座`(受 `showLocation`) / `colorIndex` |
| 7. 空闲 | 兜底 | `EMPTY` | `"日程空闲"` | `"空闲"` | `"近期暂无课程"` | `""` / `""` | `"今明两日无课，好好休息"` / `-1` |

> `formatTimeRange`：`endLabel.trim()` 为空时仅返回 `startLabel.trim()`，不拼尾横线。

### 9.3 本周课表 (`resolveWeek`)

1. 未登录或 `weeks.isEmpty()` → `weekPlan=null, isStale=false, isTermEnded=false`。
2. 按 `mondayIso = formatIsoDate(mondayOf(nowMs))` 匹配 `startDateIso == mondayIso`。
3. **假期结束 vs 超期**：`matched == null && lastWeekStart.isNotEmpty() && mondayIso > lastWeekStart` 时，若 `todayPlan != null && todayPlan.week > snapshot.maxWeek` → `isTermEnded = true, isStale = false`（「本学期课程已结束 / 切换新学期课表后自动展示」）；否则 `isStale = true`（「课表数据已过期 / 轻触打开青科课表通自动刷新」）。
4. **开学前预热**：`mondayIso < weeks.first().startDateIso` 回退 `weeks.first()`，且 `isCurrentWeek = (weekPlan.startDateIso == mondayIso)` 为 `false`（不高亮今日）。
5. **周末列 (`showWeekend`)**：`"show"->true`、`"hide"->false`、`"auto"` 严格判 `weekPlan.blocks.any { it.day >= 6 }`。

### 9.4 刷新计划 (`computeNextRefreshPlan`)

- `midnightMs = nextMidnightPlusOneMinute(nowMs)`（次日 `00:01:00.000`）。
- 未登录或仅挂载周课表 (`!hasToday && !hasNext`) → `WidgetRefreshPlan(max(midnightMs, nowMs + 5000L), includeWeek = hasWeek)`（全天零唤醒）。
- 挂载了今日/下一节：`trackExams = (hasToday && todayStyle.showExams) || (hasNext && nextStyle.showExams)`；扫描 `days`（含考试若 `trackExams`）与 `upcomingExams`（若 `trackExams`）找 `> nowMs + 500L` 的最小 `startMs`/`endMs`，`earliestBell = min + 1000L`；若 `earliestBell < midnightMs` 返回 `(max(earliestBell, nowMs + 5000L), includeWeek = false)`，否则返回 `(max(midnightMs, nowMs + 5000L), includeWeek = hasWeek)`。

---

## 10. 主题配色与背景渲染 (`WidgetThemeResolver` / `WidgetBackgroundRenderer`)

### 10.1 主题色、边框淡出与低透明提对比

- `isDark`：`light->false`、`dark->true`、`system`/`dynamic` 取系统 `UI_MODE_NIGHT_YES`（预览取 `PreviewWallpaper.brightness == Brightness.dark`）。
- **基底背景与强调色**：
  - `light`/`dark`/`system`：浅 `baseBg=#FFFFFFFF, accent=#FF3F5AA6`；深 `baseBg=#FF1C1F26, accent=#FF9AB4FF`。
  - `dynamic` (API 31+)：浅 `system_neutral1_10` / `system_accent1_600`；深 `system_neutral1_900` / `system_accent1_200`。
  - `dynamic` (API < 31 回退 / 预览)：浅 `#FFF3F6FC` / `#FF3B66A8`；深 `#FF1C2330` / `#FFAEC6FF`。
- **`borderColor`**：`opacity <= 0.01f` → `TRANSPARENT`；否则 `borderAlpha = ((isDark ? 34f : 20f) * opacity).roundToInt()`（浅黑 `#000000` / 深白 `#FFFFFF`）。
- **低透明 (`< 35%`) 纯色插值（无文字阴影）**：`lowOpacityFactor = ((0.35f - opacity) / 0.35f).coerceIn(0f, 1f)`：
  - `primaryTextColor`：浅 `#FF1A1D24 → #FF101218`；深 `#FFF3F5F8 → #FFFFFFFF`
  - `secondaryTextColor`：浅 `#FF5F6775 → #FF3A4150`；深 `#FFB4BCC8 → #FFDDE3EC`
  - `tertiaryTextColor`：浅 `#FF868E9C → #FF505868`；深 `#FF8A93A2 → #FFC2CBD8`
- **语义胶囊 (`WidgetPillTone`)**：

| 枚举 | 浅 fg / bg | 深 fg / bg | 附加色 |
|---|---|---|---|
| `ACCENT` | `accent` / `accent` @ `0x22→0x3A` | `accent` / `accent` @ `0x36→0x58` | `todayColumnHighlightColor` alpha 浅 `0x0D` / 深 `0x10` |
| `ONGOING` | `#FF0F766E` / `#FFE0F5EE` | `#FF6EE7B7` / `#FF16382C` | `ongoingRowBgColor` fg @ 浅 `0x16→0x28` / 深 `0x22→0x36` |
| `TOMORROW` | `#FF5B4BC4` / `#FFEFEBFD` | `#FFC4B8FF` / `#FF2B2448` | 明日预告 / 明日首节 |
| `EXAM` | `#FFE65100` / `#FFFFF3E0` | `#FFFFC175` / `#FF3E2914` | `examRowBgColor` fg @ 浅 `0x18→0x2A` / 深 `0x24→0x38`；`examCardBgColor` bg @ `0xFF→0xE6` |
| `RESCHEDULE` | `#FF0369A1` / `#FFE0F2FE` | `#FF7DD3FC` / `#FF172E42` | `rescheduleDotColor` 浅 `#FF0D9488` / 深 `#FF5EEAD4` |
| `NEUTRAL` | `#FF5A6270` / `#FFECEFF4` | `#FFB8C0CC` / `#FF2C313C` | `neutralBarColor` 浅 `#FF94A3B8` / 深 `#FF64748B` |

### 10.2 9 组课程色板 (`course_palette.dart` ⇄ `WidgetThemeResolver.kt`)

- `WidgetThemeResolver.LIGHT_COURSE_COLORS` / `DARK_COURSE_COLORS` 与 `CoursePalette.colors` / `darkColors`（含 FNV-1a 哈希算法）保持 1:1 同步；完整 9 组色值与公式见唯一真源 [`UI_AND_TESTING.md`](UI_AND_TESTING.md) §3.3。

### 10.3 API 24–30 兼容与背景位图 (`WidgetBackgroundRenderer.kt`)

- `applyRoundedBackground`：API 31+ 用 `setBackgroundResource(base)` + `setColorStateList(..., "setBackgroundTintList", ...)`；API 24–30 用 `setBackgroundResource(fallbackDrawableRes)`（含 `widget_pill_exam_*_dim` / `widget_pill_reschedule_*_dim`），严禁 `setBackgroundColor`。
- `applyVerticalBar`：对 `widget_bar_pill` 传不透明 `setColorFilter(color or 0xFF000000.toInt())` + `setImageAlpha(105 | 255)`，防 `SRC_ATOP` 叠白泛白。
- `resolveSizeDp`：竖屏 `(MIN_WIDTH, MAX_HEIGHT)`、横屏 `(MAX_WIDTH, MIN_HEIGHT)`，0 互退，默认今日 `260×140` / 下一节 `150×140` / 本周 `300×280`。
- `cornerClearanceDp`：`opacity <= 0.01f ? 0f : cornerRadius * 0.30f`。
- `render` / `toImmutableAshmemFriendly`：`MAX_BG_DIMENSION_PX = 1080`；API 31+ 调 `mutable.asShared()`、API 24–30 调 `mutable.copy(ARGB_8888, false)` 转不可变 Ashmem Bitmap，回收 `mutable` 并调 `prepareToDraw()`。

---

## 11. 三类小组件渲染规范

### 11.1 今日课表 (`TodayWidgetProvider` / `TodayWidgetService` / `TodayItemViewBinder`)

- **容器与边距**：`isNarrowWidth(wDp) = wDp < 200`；`sideClearance = hasVisibleCard ? cornerRadius * 0.16f : 0f`；`padHDp = max(baseH, sideClearance)` (`baseH`: 窄紧 `4.0` / 窄舒 `4.8` / 宽紧 `5.0` / 宽舒 `6.0`)；`padTop = dpPx(max(baseV, clearance))` (`baseV`: `5.5`/`7.5`/`7.0`/`10.0`)；`padBottom = dpPx(hasVisibleCard ? 1f : 0f)`。
- **顶栏右移对齐周课表 (`headerCornerInset`)**：`weekAlignedHeaderStartDp = max(compact ? 6.0f : 9.0f, clearance) + (hasVisibleCard ? 2.5f : 0f)`，`headerCornerInset = dpPx(max(0f, weekAlignedHeaderStartDp - padHDp))`，应用于 `widget_today_header` 与 `widget_today_compact_cue_box`。
- **双栏时间轴 (`buildItemView`)**：
  - 左栏：`monospace` + `tnum`；`showTime == true` 时宽/窄卡均展示两行 `startLabel`/`endLabel`；列宽 `timeColWidthDp = (isNarrow ? 34.0f : 37.0f) * fontScale + barLeftGapDp (3.5f/4.0f)`（API 31+ `setViewLayoutWidth`）；无时间时 `INVISIBLE` 填 `"00:00"` 保对齐。
  - 中栏：宽 `3dp`，`barRightGapDp = 4.0f/4.5f`，高 `barHeightDp = (hasTwoLines ? (22.0f/24.0f) : (12.5f/14.0f)) * fontScale`（API 31+ `setViewLayoutHeight`）。
  - 右栏：角标优先级 `isExam && ongoing` (`"正在考试"`, `EXAM`) > `isExam` (`"考试"`, `EXAM`, 随行置灰) > `ongoing` (`"进行中"`, `ONGOING`) > `rescheduled` (`"调课"`, `RESCHEDULE`, 随行置灰)；`metaParts` = `[location (showLocation), "${seatNumber}座" (isExam && showLocation), teacher (!isExam && showTeacher)]` 以 `" · "` 连接。
  - 高亮与置灰：`ongoing` 整行 `widget_row_highlight_bg` + 开始时间染 `examFgColor`/`ongoingFgColor`；`dimmed` (`endMs <= nowMs && finishedCourseMode == "dim"`) alpha：开始 `110`、结束 `100`、竖条 `105`、标题 `120`、副标题 `110`、胶囊 fg `115` / bg `×0.45`。
- **列表绑定与点击**：API 31+ 用 `RemoteCollectionItems` (`hasStableIds=false, viewTypeCount=1`)；API 24–30 绑 `TodayWidgetService` (`qust://today_widget/$id?rev=$rev`) + `notifyAppWidgetViewDataChanged`，`onDataSetChanged()` 校验 `headerSignature` 漂移则调 `updateWidgetById(notifyList = false)` 自愈。`ListView` 为 `wrap_content` 包于 `widget_today_list_container` (`weight=1`)，根与容器均绑启动 Intent。

### 11.2 下一节课 (`NextClassWidgetProvider`)

- **断点**：`isStrip = hDp < 100` → `widget_next_wide` (~48dp 双栏 2 行)，否则 `widget_next`；`isUltraCompactStrip = isStrip && wDp < 195`（用 `shortBadge`）；`isStrip && wDp < 170` 且含 `'-'` 时时间缩为 `substringBefore('-')`；`isSpaciousTall = !isStrip && wDp >= 220`（课名 `15.0dp*scale`、时间 `12.5dp*scale`）。
- **考试日期拆分**：`!isStrip` 时 `widget_next_date_hint` 显 `"M/D 周X"`、`widget_next_time` 显时间段；`isStrip` 时右栏下合显 `"$md $startHm"`（`isUltraCompactStrip` 仅 `"$md"`）。
- **常驻胶囊与色条**：`widget_next_badge` 恒 `VISIBLE`（不受 `showHeader` 控）；`!vm.hasCourseAccent` 或 `colorIndex < 0` 竖条用 `theme.neutralBarColor`。

### 11.3 本周课表 (`WeekGridWidgetProvider` / `WeekGridCanvasRenderer`)

- **位图像素上限与选项去重**：`screenPixels = max(dm.widthPixels * dm.heightPixels, 640_000f)`，`maxPixels = min(screenPixels * 0.55f, 1_050_000f).coerceAtLeast(640_000f)`（`MIN_PIXELS_CEILING=640_000f`, `MAX_PIXELS_CEILING=1_050_000f`），超限按 `sqrt(maxPixels / rawPixels)` 缩放并转 `toImmutableAshmemFriendly`；`WeekGridWidgetProvider` 按 `WeekRenderKey` 记录各实例已推签名，`onAppWidgetOptionsChanged` 未变化时跳过重绘与 `updateAppWidget`。
- **透明与底边**：`hasVisibleCard = opacity > 0.01f`；为真时绘圆角底/1dp 边框 + `clipPath` 内缩 1dp、`padBottom = stroke`；为假（0% 透明）时跳过底/裁切/`clearance=0`，课程块保持 100% 实色 `chip.background`。
- **表头与轴**：顶栏（`showHeader`）左起点 `contentLeft + (hasVisibleCard ? 2.5dp : 0)`，「第 X 周」(`11dp*scale` 粗 `accentColor`) + 间距 `6dp` + `dateRange` (`9.2dp*scale` `secondaryTextColor`)；单行星期 `"一".."五/七"`，仅 `isCurrentWeek && d == todayWeekday` 绘 `4.5dp` 胶囊 + `4dp` 整列高亮；`axisWidth = max(dp(compact?16f:19f), axisPaint.measureText(maxSection) + dp(6f))`（预览 `max(16/19, 14.5*scale+5.5)`）。
- **空周提示**：无可见块时，`blocks.isEmpty()` 绘 `"本周无课，好好休息"`，否则绘 `"工作日无课，周末有安排"`。
- **三段式排版求解 (`solveCourseBlockLayouts` / `_solvePreviewBlockPlan`)**：居中 `ALIGN_CENTER`、`letterSpacing=0f`，顺序：课名 → 教师 (`showTeacher`) → 地点 (`showLocation`)，缓存并直接复用求解期生成的 `StaticLayout` 实例。(1) 无限制测 `(titleNeeded, teacherNeeded, locationNeeded)`；(2) 溢出按 `title->1` → `teacher->0` → `location->1` → `location->0` → `title->0` 递减；(3) 余量按 `location++` → `teacher=teacherNeeded` → `title++` 回填，全显后仍有 >1 行课名空间则加 `titleLines`。`block.rescheduled` 右上角 `(right-4dp, top+4dp)` 绘 `r=2.1dp` `rescheduleDotColor` 圆点。

---

## 12. 闹钟与广播恢复 (`WidgetRefreshScheduler` / `WidgetRefreshReceiver`)

- **单闹钟**：仅 1 个 `RTC_WAKEUP` (`RC_WIDGET_REFRESH=3001`, `ACTION_REFRESH_WIDGETS`, `EXTRA_INCLUDE_WEEK`)；`!activeFlags.hasAny` 时 `cancel()`；经 `ReminderPermissions.canScheduleExactAlarms` 选 `setExactAndAllowWhileIdle`（捕获 `SecurityException`）或降级 `setAndAllowWhileIdle`。
- **广播路由**：
  - `ACTION_REFRESH_WIDGETS` → `refreshForScheduledAlarm(includeWeekRequested)`：必刷今日/下一节；仅当 `hasWeek && (includeWeekRequested || loadLastWeekRenderDateIso != todayIso)` 时刷周课表（跨天自愈），随后续约。
  - `ACTION_WIDGET_PINNED` → `notifyPinnedCountsChanged` + `syncAlarmState`。
  - `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` → `syncAlarmState`。
  - `BOOT_COMPLETED` / `MY_PACKAGE_REPLACED` / `TIME_SET` / `TIMEZONE_CHANGED` / `DATE_CHANGED` → `refreshAllWidgets`。

---

## 13. 配置页与同构预览 (`WidgetSettingsPage` / `DesktopWidgetPreview`)

- **路由过渡与 Isolate 预计算**：混入 `RouteSettledStateMixin`，260ms 动画未落稳或 `!_snapshotsInitialized` 时显 `PreviewSettingsTransitionPlaceholder`；`didChangeDependencies` 调 `runInBackground(() => computeWidgetSettingsSnapshots(clock, realInput))`；动画中变更暂存 `_pendingRealSnapshotRefresh`/`_pendingPinnedCounts`，落稳后挂载。`_applyInitialSampleToggle`：已登录且今日/本周非空默认「实时课表」，否则「示例课表」。
- **缓存与 60s 冷却**：`_cachedRealSnapshot` 仅在 `_computeSourceDataKey` (`preferencesLoaded, schedule, termStart, maxWeek, loadedAcademicTerm, reschedules, timetables, exams, sectionCounts`) 变化，或 `AppLifecycleState.resumed` 跨天 / 距上次已满 **60 秒** (`_resumeSnapshotCooldown`) 时重建；切 Tab/尺寸/数据源、滚动、拖滑块时 `buildSnapshot()` 调用严格为 0。
- **滑块交互**：`onChanged` 仅改 `_opacityDraft`/`_radiusDraft`/`_fontScaleDraft`（过默认值触 `HapticFeedback.selectionClick()`），`onChangeEnd` 调 `_commitStyle` 落盘并 `syncNow()`。`_WidgetTickedTrackShape` 轨道高 `10dp`，默认值绘空心圆环 (`r=3.0dp`, 线宽 `1.6dp`)，其余实心点 (`r=1.4dp`)。
- **`_ZOrderedRow`**：`_KindSegmentedHeader` 与 `_PresetStrip` (`Clip.none`) 用 `_RenderZOrderedFlex`/`_RenderZOrderedItem`，`PointerDown/Enter/Hover` 置 `elevatedChild` 最后绘制、最先命中，防 `TactileSurfaceButton` 缩放被裁剪。
- **预览尺寸与壁纸**：
  - 今日：`4×2` **`336×176`** / `2×2` **`176×176`**；本周：`4×4` **`316×316`**；下一节：`2×2` **`176×176`** / `4×1` **`336×76`**（按钮仅显 `4×2`/`2×2`/`4×1`）。
  - `PreviewWallpaper`：`softLight` (`#EBF0F7→#D6E2F0`, light)、`colorfulGradient` (`#4C6EF5→#E64980`, dark)、`darkNight` (`#151922→#252D3D`, dark)。
- **10:40 示例快照 (`samplePreviewClock`/`buildSampleWidgetSnapshot`)**：参考时钟当日 `10:40`，学期起点上周周一（今日第 2 周），第 1 周周日 `RescheduleRule` 调入今日 5-6 节，确保周一至周日均含已结束（1-2 节 `08:30-10:05` 传感器与检测技术）、进行中（3-4 节 `10:25-12:00` 单片机原理及应用A）、调课（5-6 节 `13:30-15:05` 电力电子技术）、当天考试（`16:00-17:40` 电力系统稳态分析）及明日课程。
- **超大字体免疫**：`DesktopWidgetPreview` 包裹 `TextScaler.noScaling`；`_PreviewStageHeaderDelegate.chromeHeight` 随 `textScaleFactor.clamp(1.0, 2.2)` 扩容，保 `360×640` + `2.0×` 零溢出。

---

## 14. XML 资源索引

### 14.1 AppWidgetProvider 元数据 (`android/app/src/main/res/xml/`)

> 三者均 `updatePeriodMillis="0"`、`resizeMode="horizontal|vertical"`。

| 文件 | Provider | `targetCell` | `minW×H` | `minResizeW×H` | `initialLayout` | `previewLayout` |
|---|---|---|---|---|---|---|
| [`widget_today_info.xml`](../../android/app/src/main/res/xml/widget_today_info.xml) | `.widget.TodayWidgetProvider` | `4×2` | `180×110dp` | `110×80dp` | `@layout/widget_today` | `@layout/widget_today_preview` |
| [`widget_week_info.xml`](../../android/app/src/main/res/xml/widget_week_info.xml) | `.widget.WeekGridWidgetProvider` | `4×4` | `250×220dp` | `180×160dp` | `@layout/widget_week` | `@layout/widget_week_preview` |
| [`widget_next_info.xml`](../../android/app/src/main/res/xml/widget_next_info.xml) | `.widget.NextClassWidgetProvider` | `2×2` | `110×110dp` | `110×44dp` | `@layout/widget_next` | `@layout/widget_next_preview` |

### 14.2 布局资源 (`android/app/src/main/res/layout/`)

| 文件 | 关键 View ID / 说明 |
|---|---|
| [`widget_today.xml`](../../android/app/src/main/res/layout/widget_today.xml) | `widget_today_root`, `widget_today_bg`, `widget_today_content`, `widget_today_header` (`_badge`, `_title`, `_subtitle`), `widget_today_compact_cue_box` (`widget_today_compact_cue`), `widget_today_list_container` (`widget_today_list`), `widget_today_empty_box` (`_text`), `widget_today_exam_box` (`_card`, `_badge`, `_title`, `_meta`) |
| [`widget_today_item.xml`](../../android/app/src/main/res/layout/widget_today_item.xml) | `widget_today_item_outer`, `_root`, `_time_col` (`_time_start`, `_time_end`), `_bar`, `_body` (`_tag`, `_title`, `_meta`) |
| [`widget_week.xml`](../../android/app/src/main/res/layout/widget_week.xml) | `widget_week_root` (`FrameLayout`), `widget_week_image` (`ImageView`, `fitXY`) |
| [`widget_next.xml`](../../android/app/src/main/res/layout/widget_next.xml) | `widget_next_root`, `_bg`, `_content`, `_badge`, `_date_hint`, `_bar`, `_title`, `_time`, `_subtitle` |
| [`widget_next_wide.xml`](../../android/app/src/main/res/layout/widget_next_wide.xml) | 同 `widget_next.xml` ID（无 `widget_next_date_hint`），`hDp < 100dp` 用 |
| [`widget_today_preview.xml`](../../android/app/src/main/res/layout/widget_today_preview.xml) / [`widget_week_preview.xml`](../../android/app/src/main/res/layout/widget_week_preview.xml) / [`widget_next_preview.xml`](../../android/app/src/main/res/layout/widget_next_preview.xml) | Android 12+ 选择器静态预览（全用 `dp`，内联示例防空白） |

---

## 15. 守护测试与防雷铁律

### 15.1 4 个测试套件（在 `qustschedule/` 运行）

```bash
flutter test test/widget_style_test.dart test/widget_planner_test.dart test/widget_service_test.dart test/widget_settings_page_test.dart
```

| 文件 | 守护断言 |
|---|---|
| [`test/widget_style_test.dart`](../../test/widget_style_test.dart) | 5 预设解耦（不改密度/字号/内容开关）、5% 步进、`copyWith` 切 `custom`、「莫奈取色」≠「壁纸取色」、夹取与畸形 JSON / `schema 13->14` 容错 |
| [`test/widget_planner_test.dart`](../../test/widget_planner_test.dart) | 14 天混排、调课标记、`roomOnly`、7/30 天考试、FNV-1a 对 `now` 幂等、同槽冲突分栏、节次倒挂与空白防御 |
| [`test/widget_service_test.dart`](../../test/widget_service_test.dart) | `preferencesLoaded==false` 拦截、同指纹跳过/`force:true` 载荷复用、样式防抖重发、跨学期考试隔离、登出 `signedIn:false`、`clearAll()` 等待在途同步 |
| [`test/widget_settings_page_test.dart`](../../test/widget_settings_page_test.dart) | `4×2`/`2×2` 全起止时间、周一至周日示例完整、`autoSwitchTomorrow`/`compactCue`、`showLocation` 控座位号、14 天超期 vs 假期结束、第 8 天显第 3 周、周末 `"auto"`/真实周高亮/空周与周末提示/12 节 `120%`+`2.0×` 零溢出、拖滑块 10 帧 `buildSnapshotCalls==0` 抬手仅同步 1 次、恢复默认 SnackBar 撤销、`360×640`+`2.0×` 零溢出 |

### 15.2 防雷铁律

- **线程与时间 API**：主线程禁读盘/绘图，一律走 `WidgetWorker`；`widget/*.kt` 禁 `java.time.*`，统一 `java.util.Calendar`。
- **字体单位**：RemoteViews 用 `COMPLEX_UNIT_DIP`（XML 用 `dp`），Canvas 用 `density * fontScale`，Flutter 预览包 `TextScaler.noScaling`。
- **透明与对比**：`<35%` 用 `lowOpacityFactor` 纯色插值（无文字阴影），两端同构；`0%` 隐背景、跳 `clipPath` 与 `cornerClearanceDp`。
- **API 24–30 兼容**：圆角背景用 `applyRoundedBackground` 切 drawable（禁 `setBackgroundColor`）；竖条用 `applyVerticalBar` 不透明 RGB + `setImageAlpha`。
- **周位图性能**：上下课闹钟 `includeWeek=false`；像素上限 `min(screenPixels*0.55, 1_050_000)`，转不可变 Ashmem Bitmap（API 31+ `asShared()`）并 `prepareToDraw()`；严禁 `Bitmap.Config.HARDWARE`（防 `AppWidgetHostView` 软件绘制崩溃）。
- **滑块与预设**：`onChanged` 仅改草稿，`onChangeEnd` 才持久化并 `syncNow()`；预设不覆盖 `density`/`fontScale`/内容开关。
