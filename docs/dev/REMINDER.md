# 课前提醒与流体云（Android）技术契约

> **定位**：Android 课前提醒与流体云（Fluid Cloud）子系统唯一真源（SSOT）。
> **边界**：支持课前 `1~60` 分钟（默认 `10`）提醒一次；形态二选一：**横幅（`banner`）** / **流体云常驻卡片（`fluid`）**（系统 `Chronometer` 倒计时，开课时刻三重收起）。**日期/周次/单双周/调课/作息计算 100% 留在 Dart 纯函数层（`reminder_planner.dart`）**，原生仅消费绝对毫秒时间戳。未纳入：下课提醒、课中常驻、每日摘要、上课勿扰、节假日在线拉取、厂商私有 UPK/幼苗 SDK。

## 1. 文件与符号索引

### 1.1 Dart 侧（`qustschedule/`）

| 文件 | 核心类 / 函数 | 职责与关键符号 |
| --- | --- | --- |
| `lib/src/reminder_planner.dart` | `ReminderStyle`, `CourseReminderEvent`, `ReminderPlan`, `planCourseReminders` | 纯函数规划（未来 14 天毫秒事件，FNV-1a 委托 `stable_hash.dart`）：`reminderPayloadVersion=1`, `reminderHorizonDays=14`, `reminderMaxEvents=120`, `reminderMinLeadMinutes=1`, `reminderMaxLeadMinutes=60`, `defaultReminderLeadMinutes=10`, `reminderLeadOptions=[5,10,15,20,30]`, `clampReminderLead()`, `reminderEventId()`, `reminderFingerprint()` |
| `lib/src/reminder_gateway.dart` | `ReminderGateway`, `MethodChannelReminderGateway`, `ReminderSyncResult`, `ReminderRuntimeStatus` | `MethodChannel('qustschedule/reminder')` 抽象（桌面静默吞 `MissingPluginException`）：`sync`, `cancel`, `status`（含 `dirty`、`unavailable()`、`==`/`hashCode`）, `requestNotificationPermission`, `openNotificationSettings`, `openExactAlarmSettings`, `openBatterySettings`, `openAutostartSettings`, `sendTestReminder`, `previewReminder`（`untilEnd` 保留兼容）, `stopFluid`, `showToast` |
| `lib/src/reminder_service.dart` | `ReminderService` | 监听 `AppModel` + `prefsNotifier`（冷启动保护/300ms 防抖/指纹去重/单飞队列）：`syncNow({force})`, `buildPlan()`, `cancelAll()`（串行等待 `_syncInFlight`）, `refreshStatus()`, `lastPlan`, `lastResult`, `lastStatus`, `_syncInFlight`, `_cancelInFlight`, `_queuedSyncCompleter`, `_postCancelSyncCompleter`, `_syncEpoch`, `_cancelled` |
| `lib/pages/reminder_page.dart` | `ReminderPage`, `_ReminderSettingsCard`, `_PermissionsCard`, `_DiagnosticsCard`, `_LeadOptionPill` | 三卡隔离、`RouteSettledStateMixin` 并行状态查询、`_leadDraft` & `_queuedLeadMinutes`：`_statusNotifier`, `_statusEpoch`, `_pendingStatus`, `_toggleReminder()`, `_commitLead()`, `_toggleFluid()`, `_stopFluid()`, `_resync()`, `_preview()`, `_testIn5s()`, `_testInOneMinute()` |
| `lib/pages/settings_page.dart` | `SettingsPage`, `_ReminderAndWidgetCard` | 「提醒与小组件」入口及电池优化/精确闹钟/自启动三项权限：`_openBattery()`, `_openExactAlarm()`, `_openAutostart()`, `_confirmSignOut()`（登出调 `reminders?.cancelAll()`） |
| `lib/widgets/reminder_permission_tile.dart` | `ReminderPermissionTile`, `showReminderGuideToast` | 三态权限行（`ok: true/false/null`）与跨进程系统 Toast 引导 |
| `lib/src/preferences_repository.dart` | `Preferences` | 偏好持久化（`preferencesSchema = 15`）：`reminderEnabled`(`false`), `reminderLeadMinutes`(`10`, `1..60`), `reminderStyle`(`banner`), `reminderFluidUntilEnd`(`false`) |
| `lib/main.dart` | `_AppShellState` | `boot()` 前挂 `ReminderService`；`AppLifecycleListener(onShow)` 经 60s 同日冷却 + 600ms 延迟调 `syncNow(force: true)`：`_reminders`, `_foregroundSyncTimer`, `_onShown()` |

### 1.2 Android 原生侧（`android/app/src/main/`）

| 文件 | 核心类 / 单例 | 职责与关键符号 |
| --- | --- | --- |
| `kotlin/.../reminder/ReminderWorker.kt` | `ReminderWorker` (`internal object`) | 单线程执行器（`"qust-reminder-worker"`）与 `goAsync()` 封装：`execute()`, `runBroadcastAsync(receiver, tag, block)` |
| `kotlin/.../reminder/ReminderBridge.kt` | `ReminderBridge` | `CHANNEL="qustschedule/reminder"` 唯一 Handler；缓存 `appContext` + `@Volatile disposed` + `postReply`（`toast` 同走 `!disposed`），重 I/O 派发 `ReminderWorker`：`REQUEST_NOTIFICATION=4501`, `attach()`, `dispose()`, `onMethodCall()`, `onRequestPermissionsResult()` |
| `kotlin/.../reminder/ReminderPayload.kt` | `ReminderPayload`, `ReminderEvent`, `ReminderPayloadException` | 严格 JSON 校验（单条违规即整体拒绝）：`VERSION=1`, `STYLE_BANNER="banner"`, `STYLE_FLUID="fluid"`, `MAX_EVENTS=200`, `MAX_LEAD_MINUTES=180`, `MAX_PERIOD=30`, `parse(json)` |
| `kotlin/.../reminder/ReminderStore.kt` | `ReminderStore` | `SharedPreferences("reminder_store")` 同步持久化（全 `.commit()`）：`PREFS="reminder_store"`, `savePayload()`, `loadPayload()`, `alarmCodes()`, `setAlarmCodes()`, `removeAlarmCode()`, `markDirty()`, `clearDirty()`, `clear()` |
| `kotlin/.../reminder/ReminderScheduler.kt` | `ReminderScheduler`, `ReminderSyncOutcome` | 核心排程器：`LOCK`, `SYSTEM_ALARM_WINDOW_DAYS=10L`, `MIN_LEAD_MS=1000L`, `MIN_EVENT_REQUEST_CODE=10_000`, `RC_DAILY_RESYNC=2001`, `RC_TEST=2002`, `sync()`, `cancelAll()`, `rescheduleFromStore()`, `topUpWindowFromStore()`, `scheduleTest()`, `status()` |
| `kotlin/.../reminder/ReminderReceiver.kt` | `ReminderReceiver` | 闹钟入口（三重校验 + 流体云失败降级横幅 + 补齐窗口）：`ACTION_REMIND`, `ACTION_TEST`, `ACTION_DISMISS`, `ACTION_FLUID_STOP`, `TEST_LEAD_MINUTES=10`, `handleRemind()`, `handleTest()` |
| `kotlin/.../reminder/ReminderDailyResyncReceiver.kt` | `ReminderDailyResyncReceiver` | 每日 00:05 自愈：`ACTION_RESYNC="com.fangzi.qustschedule.action.DAILY_RESYNC"` |
| `kotlin/.../reminder/ReminderRestoreReceiver.kt` | `ReminderRestoreReceiver` | 系统事件恢复：`SUPPORTED_ACTIONS`（5 项系统广播） |
| `kotlin/.../reminder/ReminderNotifier.kt` | `ReminderNotifier` (`object`) | 横幅通知（ID `2000`）：`CHANNEL_ID="course_reminder_v1"`, `NOTIFY_ID=2000`, `FLUID_NOTIFY_ID=2001`, `REQUEST_CONTENT=4402`, `show()`, `cancelBanner()`, `ensureAllChannels()`, `ensureHighAlertChannel()`, `bodyText()` |
| `kotlin/.../reminder/ReminderFluidRenderer.kt` | `ReminderFluidRenderer`, `FluidCardState` | 流体云通知构建（读 `state.stopAtMs = startMs`）：`CHANNEL_FLUID="course_fluid_v1"`, `REQUEST_CONTENT=4403`, `build(context, state)`, `FluidCardState.detailText()` |
| `kotlin/.../reminder/ReminderFluidService.kt` | `ReminderFluidService` (`Service`) | `specialUse` 前台服务（ID `2001`，读 `state.stopAtMs = startMs` 三重自停）：`ACTION_START`, `ACTION_STOP`, `RC_FLUID_STOP=2003`, `casting`(`@Volatile`), `start()`, `stop()`, `armStopAlarm()`, `disarmStopAlarm()` |
| `kotlin/.../reminder/ReminderSamples.kt` | `ReminderSamples` (`object`) | 预览/测试示例源：`NAME="高等数学（示例）"`, `TEACHER="张老师"`, `ROOM="3教201"`, `CLASS_MINUTES=95L`, `event(leadMinutes)` |
| `kotlin/.../reminder/ReminderPermissions.kt` | `ReminderPermissions` (`object`) | 权限检测与 15 项 OEM 自启动探测/缓存：`hasNotificationPermission()`, `notificationsEnabled()`, `canScheduleExactAlarms()`, `isIgnoringBatteryOptimizations()`, `hasAutostartSettings()`, `open*Settings()` |
| `kotlin/.../MainActivity.kt` | `MainActivity` | 唯一挂载 `reminderBridge`，转发 `onRequestPermissionsResult`，`onDestroy` 释放 |
| `AndroidManifest.xml` | `<manifest>` | 权限（`POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_PROMOTED_NOTIFICATIONS`）、3 Receiver、1 Service、`<queries>` |

## 2. 常见改动路由

| 任务 | 目标文件 / 符号 | 必守不变量 | 必跑测试 |
| --- | --- | --- | --- |
| 提前量范围/档位 | `reminder_planner.dart` + `ReminderPayload.kt` (`MAX_LEAD_MINUTES`) | `clampReminderLead` 保留区间内任意整数；改提前量不改 `reminderEventId` | `reminder_planner_test.dart`, `timetable_test.dart` |
| 横幅文案/样式 | `ReminderNotifier.kt` + `ReminderSamples.kt` + `reminder_planner.dart` (`roomOnly`) | 固定 `NOTIFY_ID=2000`；发前调 `ReminderFluidService.stop`；保留 `Chronometer` + `setTimeoutAfter` | `reminder_planner_test.dart` + 真机预览 |
| 流体云文案/属性 | `ReminderFluidRenderer.kt` + `ReminderFluidService.kt` | 禁 `ProgressStyle`/`BigTextStyle`；保留 `FOREGROUND_SERVICE_IMMEDIATE` 与 `RC_FLUID_STOP=2003` | `reminder_service_test.dart` + 真机 5s 测试 |
| 课表/调课/作息换算 | `reminder_planner.dart` (`planCourseReminders`) | 纯函数；按**当天**调 `activeTimetableAt`；`remindAtMs <= now` 跳过 | `reminder_planner_test.dart` |
| MethodChannel 变更 | `reminder_gateway.dart` + `reminder_service.dart` + `ReminderBridge.kt` + `ReminderScheduler.kt` + `fake_reminder_gateway.dart` | 涉及 SP/`AlarmManager` 必须进 `ReminderWorker.execute` 并 `postReply` 回主线程；同步更新 `FakeReminderGateway` | `reminder_service_test.dart`, `widget_test.dart` |
| 权限/OEM 跳转 | `ReminderPermissions.kt` + `settings_page.dart` + `reminder_page.dart` + `AndroidManifest.xml` | 通知在 `ReminderPage`，电池/闹钟/自启动在 `SettingsPage`；新增自启动项须同步 `<queries>` | `reminder_service_test.dart`, `widget_test.dart` |
| 切页/滑块卡顿排查 | `reminder_page.dart` + `settings_page.dart` + `route_settled.dart` | 禁顶层 `ListenableBuilder`；滑块 `onChanged` 只改 `_leadDraft`；`initState` 带 `deferUntilSettled: true` | `widget_test.dart` |

## 3. 分层架构与单向数据流

```
SettingsPage(_ReminderAndWidgetCard) -> ReminderPage(_ReminderSettingsCard / _PermissionsCard / _DiagnosticsCard)
  -> AppModel -> ReminderService(冷启动保护/300ms防抖/指纹去重/单飞队列)
       ├── reminder_planner.dart (纯函数：未来14天毫秒事件 + FNV-1a)
       └── ReminderGateway(MethodChannel 'qustschedule/reminder')
             -> ReminderBridge -> ReminderWorker("qust-reminder-worker")
                  ├── ReminderPayload (严格校验) -> ReminderStore (SP commit)
                  ├── ReminderScheduler (LOCK / 10天滚动窗 / 账本差分 / 00:05自愈)
                  │     ├── ReminderReceiver (三重校验 + topUpWindowFromStore)
                  │     │     ├── ReminderNotifier (ID=2000)
                  │     │     └── ReminderFluidService (ID=2001 + RC=2003) -> ReminderFluidRenderer
                  │     └── ReminderDailyResyncReceiver (00:05)
                  └── ReminderRestoreReceiver (5项系统广播)
```

## 4. 数据契约与 FNV-1a 指纹（`ReminderPayload`）

### 4.1 Payload JSON

```json
{
  "v": 1, "generatedAtMs": 1761600000000, "leadMinutes": 10,
  "style": "banner", "fluidUntilEnd": false, "fingerprint": "8f3a1c2d",
  "events": [{
    "id": "e_5c1a9b7e", "entryId": "ScheduleEntry.id", "name": "高等数学",
    "teacher": "张三", "location": "3教201",
    "startMs": 1761610200000, "endMs": 1761612900000, "remindAtMs": 1761609600000,
    "startPeriod": 3, "endPeriod": 4, "week": 8
  }]
}
```

> Kotlin `ReminderPayload.parseEvent()` 消费除 `entryId` 外的全部字段（忽略未知字段）。

### 4.2 32 位 FNV-1a（UTF-8 字节）

`offset_basis = 0x811C9DC5`，`FNV_prime = 0x01000193`，每步 `& 0xFFFFFFFF`，输出 `toRadixString(16).padLeft(8, '0')`。

| 标识 | 精确公式 | 严禁包含与原因 |
| --- | --- | --- |
| `event.id` | `'e_' + hex32(fnv1a('$entryId\|$yyyyMMdd\|$startPeriod'))` | 禁含 `leadMinutes`/`style`：改设置时保持 `requestCode` 不变以原地覆盖旧闹钟，防双重响铃 |
| `fingerprint` | `hex32(fnv1a('v$v\|lead$leadMinutes\|style${style.wireName}\|untilEnd$fluidUntilEnd' + 按 id 升序 '\|$id:$startMs:$remindAtMs'))` | 禁含 `generatedAtMs`：同课表不同时刻重算必须指纹一致，防冷启动/回前台无效重排 |

### 4.3 Dart 规划 vs Kotlin 校验

| 维度 | Dart（`planCourseReminders`） | Kotlin（`ReminderPayload.parse`） |
| --- | --- | --- |
| 窗口/上限 | `dayOnly(now)` 起 `reminderHorizonDays=14` 天；按 `(remindAtMs, id)` 升序、按 `id` 去重，上限 `reminderMaxEvents=120`（超限 `truncated=true`） | `events.length <= MAX_EVENTS(200)`，超限抛 `ReminderPayloadException` |
| 周次/调课 | `weekOf(termStart, date)` 须在 `1..safeMaxWeek`；每周调 `rescheduleWeekView` + `occursInWeek`（`weeks` 空表示每周） | `week = optInt("week", 0)` 仅元数据 |
| 作息/节次 | 按**事件当天**调 `activeTimetableAt` + `reconcileSections`；缺 `startPeriod` 则 `skipped++`；`endMinutes` 取 `endPeriod` 下课时刻（缺则回退 `startMinutes`） | `startPeriod in 1..30`、`endPeriod in startPeriod..30`（`MAX_PERIOD=30`）；`endMs < startMs` 时取 `startMs` |
| 提前量/过期 | `clampReminderLead(1..60)`；`remindAtMs = startMs - lead*60000`；`remindAtMs <= now` 跳过不补发 | `leadMinutes in 1..180`；`generatedAtMs/startMs/remindAtMs > 0` 且 `remindAtMs < startMs` |
| 文本/标识 | `teacher = entry.teacher ?? ''`；`location = roomOnly(entry.location ?? '')` | `v in 1..1`、`fingerprint` 非空、`style in {"banner","fluid"}`、`id.length in 1..64` 且批次内唯一；任何违规整体拒收，**不覆盖旧 store** |

## 5. MethodChannel 契约（`qustschedule/reminder`）

> 唯一 Handler：`MainActivity.configureFlutterEngine` 仅注册 `ReminderBridge`。

### 5.1 通道方法（12 个）

| 方法 | 参数 | 原生线程 | 返回值 | 错误码 | Dart 网关行为 |
| --- | --- | --- | --- | --- | --- |
| `sync` | `String` (JSON) | `ReminderWorker` | `Map{scheduled, nextTriggerMs?, coverageEndMs?, style, exactAlarmAllowed}` | `BAD_ARGS`, `SYNC_FAILED` | 返回 `ReminderSyncResult`；异常/桌面返回 `failure(msg)` |
| `cancel` | `null` | `ReminderWorker` | `null`（撤闹钟/账本/00:05 自愈/横幅 `2000`/流体云 `2001`,`2003` + `store.clear()`） | — | 异常静默吞 |
| `status` | `null` | `ReminderWorker` | `Map<String, Any?>`（见 5.2） | `STATUS_FAILED` | 返回 `ReminderRuntimeStatus`；异常/桌面返回 `unavailable()` |
| `requestNotificationPermission` | `null` | 主线程（`REQUEST_NOTIFICATION=4501`） | `Boolean`（已授权/Android 12- 建渠道返 `true`；授权后建渠道） | `BUSY` | 异常返 `false` |
| `openNotificationSettings` | `null` | 主线程 | `null`（先 `ensureAllChannels` → `ACTION_APP_NOTIFICATION_SETTINGS`，退应用详情） | — | `Future<void>` |
| `openExactAlarmSettings` | `null` | 主线程 | `Boolean`（跳转前瞬间 `canScheduleExactAlarms` 快照） | — | 后由 `ReminderService` 调 `refreshStatus()` |
| `openBatterySettings` | `null` | 主线程 | `null`（优先 `ACTION_APPLICATION_DETAILS_SETTINGS`，退 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`） | — | `Future<void>` |
| `openAutostartSettings` | `null` | 主线程 | `Boolean`（`true`=打开厂商页，`false`=退 `ACTION_SETTINGS`/应用详情） | — | `Future<bool>` |
| `testReminder` | `Map{style, delaySeconds}` | `ReminderWorker` | `Long`（触发毫秒 `epoch`；`delaySeconds` 夹取 `5..3600`） | `TEST_FAILED` | `epoch != null && epoch > 0` 返 `bool` |
| `previewReminder` | `Map{style, leadMinutes, untilEnd}` | 主线程 | `Boolean`（`untilEnd` 保留兼容；用 `ReminderSamples.event(lead)` 立即展示，不挂闹钟/不进账本） | — | `Future<bool>` |
| `stopFluid` | `null` | 主线程 | `null`（`ReminderFluidService.stop`：停服务 + 撤 `2001`/`2003`） | — | `Future<void>` |
| `toast` | `Map{message, long}` | 主线程 `postReply` | `null`（`!disposed` 校验后用 `appContext` 弹系统 `Toast.makeText`，不捕获 `Activity`） | — | `showToast(message, {longDuration})` |

### 5.2 `status` 字段映射（`ReminderRuntimeStatus`）

| 原生 Key | 类型 | 来源 | Dart 属性 / 派生 Getter |
| --- | --- | --- | --- |
| — | `bool` | Dart 默认 `true`；通道报错/桌面 `false` | `available` |
| `notificationPermission` | `Boolean` | Android 13+ (`TIRAMISU`) 查 `POST_NOTIFICATIONS`；12- 恒 `true` | `notificationPermission` |
| `notificationsEnabled` | `Boolean` | `NotificationManager.areNotificationsEnabled()` | `notificationsEnabled`；**`canNotify => notificationPermission && notificationsEnabled`** |
| `exactAlarmAllowed` | `Boolean` | Android 12+ (`S`) 查 `canScheduleExactAlarms()`；11- 恒 `true` | `exactAlarmAllowed` |
| `batteryOptimizationIgnored` | `Boolean` | `PowerManager.isIgnoringBatteryOptimizations(pkg)` | `batteryOptimizationIgnored`；**`batteryOptOut => batteryOptimizationIgnored`** |
| `autoStartVendorPage` | `Boolean` | `ReminderPermissions.hasAutostartSettings()`（`@Volatile` 缓存一次） | `autoStartVendorPage` |
| `scheduled` | `Int` | `store.alarmCodes().size`（不含 `RC_TEST=2002`） | `scheduled` |
| `nextTriggerMs` | `Long?` | `payload.events.filter { remindAtMs > now }.minOfOrNull { remindAtMs }` | `nextTriggerMs` |
| `payloadAtMs` | `Long?` | `store.payloadAtMs()`（`>0` 否则 `null`） | `payloadAtMs` |
| `fingerprint` | `String` | `store.fingerprint()` | `fingerprint` |
| `style` | `String` | `store.style()`（`"banner"`/`"fluid"`） | `style` |
| `dirty` | `Boolean` | `store.isDirty()`（时间/时区变更置 `true`，Flutter 同步清 `false`） | 回前台 `syncNow(force: true)` 直接覆盖并清除 |
| `fluidCasting` | `Boolean` | `ReminderFluidService.casting`（`@Volatile`） | `fluidCasting`（控制「立即收起卡片」显隐与诊断状态） |

## 6. 原生持久化与排程算法

### 6.1 `ReminderStore`（`SharedPreferences("reminder_store")`）

> **同步落盘铁律**：所有写操作（`savePayload`/`setAlarmCodes`/`clearAlarmCodes`/`markDirty`/`clearDirty`/`clear`）一律 `.commit()`，禁 `.apply()`（防 `goAsync()` 结束或进程冻结导致 payload 与账本失一致）。

- `KEY_PAYLOAD_JSON` (`"payload_json"`, `String?`)：完整 14 天 JSON 原文
- `KEY_FINGERPRINT` (`"fingerprint"`, `String`, 默认 `""`)：8 位 FNV-1a 指纹
- `KEY_PAYLOAD_AT_MS` (`"payload_at_ms"`, `Long`)：保存时的 `System.currentTimeMillis()`
- `KEY_LEAD_MINUTES` (`"lead_minutes"`, `Int`)、`KEY_STYLE` (`"style"`, `String`)
- `KEY_ALARM_CODES` (`"alarm_codes"`, `String`)：逗号分隔的已挂 `requestCode` 账本
- `KEY_DIRTY` (`"dirty"`, `Boolean`)：时间/时区变更置 `true`，仅 `sync(..., fromFlutter = true)` 调 `clearDirty()` 清除

### 6.2 两级闹钟 API 与降级

| 用途 | 有精确闹钟权限 | 无权限 / `SecurityException` 降级 | 原因 |
| --- | --- | --- | --- |
| 课程提醒 (`ACTION_REMIND`) | `setAlarmClock(AlarmClockInfo(remindAtMs, contentIntent), op)` | `setAndAllowWhileIdle(RTC_WAKEUP, ...)` | 国产 ROM（如 ColorOS 16）将 `setExactAndAllowWhileIdle` 拉长至 `+1h`；`setAlarmClock` 享最高豁免，Doze 误差 `<5s` |
| 测试提醒 (`ACTION_TEST`, `RC_TEST=2002`) | `setAlarmClock(...)` | `setAndAllowWhileIdle(...)` | 与正式提醒同链路验收 |
| 流体云收起 (`ACTION_FLUID_STOP`, `RC_FLUID_STOP=2003`) | `setAlarmClock(AlarmClockInfo(startMs, ...), op)` | `setAndAllowWhileIdle(...)` | FGS 通知带 `FOREGROUND_SERVICE \| NO_CLEAR`，系统忽略 `setTimeoutAfter`，须靠精确闹钟唤醒 `stopSelf()` |
| 每日 00:05 自愈 (`ACTION_RESYNC`, `RC_DAILY_RESYNC=2001`) | `setExactAndAllowWhileIdle(RTC_WAKEUP, targetMs, op)` | `setAndAllowWhileIdle(...)` | 允许几分钟偏差，避免状态栏常驻闹钟图标 |

### 6.3 14 天存储 + 10 天滚动窗口 + 账本差分

1. **双窗口**：`ReminderStore` 存 14 天（最多 120 条）；`ReminderScheduler` 仅向 `AlarmManager` 挂 `remindAtMs in (now + 1000ms, now + 10d]`（`SYSTEM_ALARM_WINDOW_DAYS=10L`, `MIN_LEAD_MS=1000L`）。
2. **账本差分（`ReminderScheduler.sync`）**：
   - 取 `previous = store.alarmCodes().toSet()`；遍历 `payload.events` 算 `code = requestCodeFor(event.id)` 记入 `windowCodes`，在 10 天窗口内者放入 `desired[code] = event`。
   - **差分撤销**：对 `code in (previous + windowCodes) - desired.keys` 调 `cancel(code)`（含遗留 `dismissCode`）。
   - **原地先撤后挂（`arm`）**：对 `desired` 每项先调 `cancelReminderOperation(manager, code)`（`FLAG_NO_CREATE | FLAG_IMMUTABLE` 取旧 `PendingIntent` → `manager.cancel(op)` + `op.cancel()`），再建新 `PendingIntent` 挂钟并 `cancelLegacyDismiss`（防部分 ROM 同 `requestCode` 缓存旧触发时刻，且无全局清空空窗）。
3. **双轨续挂**：
   - **每日 00:05（`ReminderDailyResyncReceiver`）**：调 `rescheduleFromStore()` 全量重放 14 天 payload 并续挂次日 00:05 闹钟。
   - **每次响铃后（`topUpWindowFromStore`）**：`ReminderReceiver.handleRemind` 调 `store.removeAlarmCode(code)` + `scheduler.topUpWindowFromStore()`，增量挂上新入 10 天窗且不在账本的事件（防 00:05 被冻结导致第 11~14 天断档）。

## 7. 全局 ID、RequestCode、Intent Action 与 Extras

### 7.1 通知 ID、渠道 ID 与 RequestCode

| 常量 | 所属类 | 值 | 语义 |
| --- | --- | --- | --- |
| `CHANNEL_ID` | `ReminderNotifier` | `"course_reminder_v1"` | 横幅渠道（「上课提醒」，`IMPORTANCE_HIGH`，开角标） |
| `CHANNEL_FLUID` | `ReminderFluidRenderer` | `"course_fluid_v1"` | 流体云渠道（「上课进度」，`IMPORTANCE_HIGH`，关角标） |
| `NOTIFY_ID` | `ReminderNotifier` | `2000` | 横幅通知固定 ID（新覆盖旧） |
| `FLUID_NOTIFY_ID` | `ReminderNotifier` | `2001` | 流体云 FGS 通知固定 ID（与 `2000` 物理隔离，防回前台 `sync` 误撤展示中横幅） |
| `RC_DAILY_RESYNC` | `ReminderScheduler` | `2001` | 每日 00:05 自愈广播 requestCode（`ReminderDailyResyncReceiver`） |
| `RC_TEST` | `ReminderScheduler` | `2002` | 测试提醒广播 requestCode（**不进 `alarm_codes` 账本**，不受 `sync`/`cancelAll` 影响） |
| `RC_FLUID_STOP` | `ReminderFluidService` | `2003` | 流体云开课时刻 `startMs` 收起兜底闹钟 requestCode |
| `REQUEST_CONTENT` | `ReminderNotifier` / `ReminderFluidRenderer` | `4402` / `4403` | 点通知回 `MainActivity`（`FLAG_ACTIVITY_SINGLE_TOP`） |
| `REQUEST_NOTIFICATION` | `ReminderBridge` | `4501` | Android 13+ `POST_NOTIFICATIONS` 请求码 |
| `requestCodeFor(id)` | `ReminderScheduler` | `raw = id.hashCode() and 0x3fffffff; if (raw < 10_000) raw + 10_000 else raw` | 课程闹钟槽位（`10_000..0x3FFFFFFF`，保留 `0..9999` 给固定槽位，高两位 `00`） |
| `dismissCodeFor(id)` | `ReminderScheduler` | `requestCodeFor(id) or 0x40000000` | 旧版开课撤销槽位（次高位 `1`），仅 `arm()`/`cancel()` 清理兼容 |

### 7.2 Intent Action 与 Extras

| 组件 | Action | Extras | 逻辑 |
| --- | --- | --- | --- |
| `ReminderReceiver` | `ACTION_REMIND` (`com.fangzi.qustschedule.action.REMIND`) | `event_id`, `fingerprint`, `remind_at_ms`, `request_code` | 三重校验 → 横幅/流体云 → `removeAlarmCode` → `topUpWindowFromStore()` |
| `ReminderReceiver` | `ACTION_TEST` (`com.fangzi.qustschedule.action.TEST_REMIND`) | `test_style` (`"banner"`/`"fluid"`) | 用 `ReminderSamples.event(10)` 立即展示（不读 payload） |
| `ReminderReceiver` | `ACTION_FLUID_STOP` (`com.fangzi.qustschedule.action.FLUID_STOP`) | 无 | `RC_FLUID_STOP(2003)` 到点 → `ReminderFluidService.stop(context)` |
| `ReminderReceiver` | `ACTION_DISMISS` (`com.fangzi.qustschedule.action.DISMISS`) | 无 | 历史兼容：同时 `cancelBanner` + `ReminderFluidService.stop` |
| `ReminderDailyResyncReceiver` | `ACTION_RESYNC` (`com.fangzi.qustschedule.action.DAILY_RESYNC`) | 无 | `rescheduleFromStore()` |
| `ReminderFluidService` | `ACTION_START` (`com.fangzi.qustschedule.action.FLUID_START`) | `name`, `room`, `teacher`, `start_ms`, `end_ms`, `notify_epoch`, `start_period`, `end_period` | 校验 `now < startMs` → 撤横幅 `2000` → `startForeground(2001)` → 挂 `2003` + `postDelayed` |
| `ReminderFluidService` | `ACTION_STOP` (`com.fangzi.qustschedule.action.FLUID_STOP`) | 无 | `stopSelf()` → `onDestroy` 清 `stopRunnable`、撤 `2003`、`casting=false` |

## 8. 闹钟三重校验与通知/流体云渲染契约

### 8.1 `ReminderReceiver.handleRemind` 三重校验

在 `ReminderWorker.runBroadcastAsync`（`goAsync()`）内连续校验：
1. `intent.getStringExtra("fingerprint") == payload.fingerprint`
2. `payload.events.firstOrNull { it.id == eventId } != null`
3. `kotlin.math.abs(event.remindAtMs - expected) <= 1000L`

任一失败即丢弃本次触发并调 `scheduler.rescheduleFromStore()` 自愈，绝不误响。

### 8.2 横幅（`ReminderNotifier`）vs 流体云（`ReminderFluidRenderer` + `ReminderFluidService`）

| 维度 | 横幅（`banner`） | 流体云（`fluid`） |
| --- | --- | --- |
| 渠道与延迟建道 | `course_reminder_v1`（`showBadge=true`）；**须 `hasNotificationPermission()==true` 后才建道**（`ensureHighAlertChannel`，防国产 ROM 永久锁静默）：`IMPORTANCE_HIGH`、`VISIBILITY_PUBLIC`、默认铃声、呼吸灯、震动 `longArrayOf(0L,250L,150L,250L)`（Android 15/`VANILLA_ICE_CREAM`+ 同步 `VibrationEffect.createWaveform(..., -1)`） | `course_fluid_v1`（`showBadge=false`），共用 `ensureHighAlertChannel` |
| ID 与互斥 | `NOTIFY_ID=2000`；发前调 `ReminderFluidService.stop(context)` | `FLUID_NOTIFY_ID=2001`；`startForeground` 前调 `ReminderNotifier.cancelBanner(this)` |
| 排版 | `ContentTitle`: `name.ifEmpty{"上课提醒"}`；`ContentText` & `BigTextStyle`: `bodyText` → `"HH:mm 上课 · 地点 · 教师"`（空省，无 `SubText`） | `ContentTitle`: `name.ifEmpty{"上课提醒"}`；`SubText`: `detailText()` → `"HH:mm - HH:mm · 教室 · 老师"`；`ShortCriticalText`: `room.ifEmpty{name}.ifEmpty{"上课提醒"}.take(7)`；**无 `ContentText`/`BigTextStyle`/`ProgressStyle`** |
| 倒计时与标志 | `setWhen(startMs)` + `setShowWhen(true)` + `setUsesChronometer(true)` + `setChronometerCountDown(true)`（SystemUI 原生走秒，0 轮询）；`setOngoing(true)` + `setAutoCancel(false)` + `CATEGORY_REMINDER` + `PRIORITY_HIGH` + `DEFAULT_ALL` + `VISIBILITY_PUBLIC` | 同左 + `setRequestPromotedOngoing(true)`（Android 16+/ColorOS 胶囊提升）+ `setForegroundServiceBehavior(FOREGROUND_SERVICE_IMMEDIATE)`（豁免 Android 12+ 10s 延迟） |
| 开课 (`startMs`) 收起 | `setTimeoutAfter((startMs - now).coerceAtLeast(1000L))`（普通 `ongoing` 通知系统会准点销毁） | **三重冗余**（`state.stopAtMs = startMs`）：1) `setTimeoutAfter((state.stopAtMs - now).coerceAtLeast(1000L))`；2) `RC_FLUID_STOP=2003`（`armStopAlarm(state.stopAtMs)` → `ACTION_FLUID_STOP` → `stop`）；3) `handler.postDelayed(stopRunnable, (state.stopAtMs - now).coerceAtLeast(0L))` |
| 失败降级 | `canPost()==false` 返回 `false` | `ReminderFluidService.start()` 返 `false`（如后台起 FGS 被拦）时自动降级 `ReminderNotifier.show(...)` |

## 9. 系统恢复矩阵与 `dirty` 语义

| 场景 | 组件 | Action / 回调 | 动作 |
| --- | --- | --- | --- |
| 重启 / 覆盖安装 | `ReminderRestoreReceiver` | `ACTION_BOOT_COMPLETED` / `ACTION_MY_PACKAGE_REPLACED` | `rescheduleFromStore()`（不改 `dirty`；覆盖安装须同签名） |
| 改时间 / 时区 | `ReminderRestoreReceiver` | `ACTION_TIME_SET` / `ACTION_TIMEZONE_CHANGED` | **先 `store.markDirty()`**，再 `rescheduleFromStore()` |
| 精确闹钟权限变更 | `ReminderRestoreReceiver` | `ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` | `rescheduleFromStore()`（原地升级为 `setAlarmClock`） |
| 每日 00:05 自愈 | `ReminderDailyResyncReceiver` | `ACTION_RESYNC` (`RC_DAILY_RESYNC=2001`) | `rescheduleFromStore()` + 续挂次日 00:05 + 推进 10 天窗 |
| 提醒响铃后 | `ReminderReceiver` | `ACTION_REMIND` | 移除账本 `code` + `topUpWindowFromStore()` |
| App 回前台 | `_AppShellState` (`lib/main.dart`) | `AppLifecycleListener(onShow: _onShown)` | 60s 同日冷却（或跨天）+ 600ms 延迟 → `_reminders.syncNow(force: true)`（强制下发并清 `dirty`） |
| `force-stop` / 14 天未开 | 系统限制 | 无广播 | `force-stop` 清闹钟/FGS（SP 仍在），下次打开恢复；第 15 天起需打开 App 重算 |

## 10. 权限诊断状态机与厂商跳转矩阵

### 10.1 页面分布与交互（共用 `ReminderPermissionTile`）

- `ReminderPage` → `_PermissionsCard`：仅放**通知权限**。
- `SettingsPage` → `_ReminderAndWidgetCard`：收拢**忽略电池优化 / 精确闹钟 / 自启动**（同时影响提醒与小组件）。

| 权限项 | `ok` 判定 | 副标题（`null` / `true` / `false`） | 按钮 | 点击动作与落点 |
| --- | --- | --- | --- | --- |
| **通知权限** | `status.canNotify` | `'查询中…'` / `'已允许 · 横幅与锁屏需手动开启'` / `'已禁止 · 无法收到任何提醒'` | `canNotify ? '去设置' : '去授权'` | 未授权调 `requestNotificationPermission()`；已授权调 `openNotificationSettings()`（`ACTION_APP_NOTIFICATION_SETTINGS`，退应用详情） |
| **忽略电池优化** | `status?.batteryOptOut ?? false` | `'查询中…'` / `'已忽略'` / `'受省电策略限制 · 后台可能被清理'` | `'去设置'` | Toast `'请在「耗电管理」或「省电策略」中允许后台运行'` → `openBatterySettings()`（优先 `ACTION_APPLICATION_DETAILS_SETTINGS`，退 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`） |
| **精确闹钟** | `status?.exactAlarmAllowed ?? false` | `'查询中…'` / `'已允许'` / `'未允许 · 息屏时可能推迟数分钟'` | `'去设置'` | Toast `'请开启「允许设置闹钟和提醒」以确保准时响铃'` → `openExactAlarmSettings()`（`ACTION_REQUEST_SCHEDULE_EXACT_ALARM` + `package:...`） |
| **自启动** | 恒 `null`（`AppColors.warning`，不给假绿灯） | 恒 `'该权限不可检测，需自行确认'` | `'去设置'` | `openAutostartSettings()` 探测 15 项 OEM 页：`true` 弹 `'请在列表中找到本应用并允许自启动'`；`false` 退 `ACTION_SETTINGS` 弹 `'请在设置顶部搜索「自启动」，开启本应用开关'` |

### 10.2 国产 ROM 自启动 15 项候选（`ReminderPermissions.autostartCandidates`）

经 `isCandidateLaunchable` 校验 `activityInfo.exported == true` 与权限（防 ColorOS 12+ `SecurityException`），所有包名/Action 须同步写入 `AndroidManifest.xml` `<queries>`：

| 厂商 | 候选 Action / Component（`package` / `class`） | `<queries>` 声明 |
| --- | --- | --- |
| 小米 (MIUI/HyperOS) | 1. `Intent("miui.intent.action.OP_AUTO_START")` + `CATEGORY_DEFAULT`<br>2. `com.miui.securitycenter` / `com.miui.permcenter.autostart.AutoStartManagementActivity` | `<intent>` `miui.intent.action.OP_AUTO_START` + `<package>` `com.miui.securitycenter` |
| OPPO/realme/一加 (ColorOS) | 3. `com.coloros.safecenter` / `com.coloros.safecenter.permission.startup.StartupAppListActivity`<br>4. `com.coloros.safecenter` / `com.coloros.safecenter.startupapp.StartupAppListActivity`<br>5. `com.oppo.safe` / `com.oppo.safe.permission.startup.StartupAppListActivity`<br>6. `com.oneplus.security` / `com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity` | `<package>` `com.coloros.safecenter`, `com.oppo.safe`, `com.oneplus.security` |
| vivo/iQOO (OriginOS) | 7. `com.vivo.permissionmanager` / `com.vivo.permissionmanager.activity.BgStartUpManagerActivity`<br>8. `com.iqoo.secure` / `com.iqoo.secure.ui.phoneoptimize.BgStartUpManagerActivity` | `<package>` `com.vivo.permissionmanager`, `com.iqoo.secure` |
| 华为/荣耀 (EMUI/Harmony/MagicOS) | 9. `Intent("huawei.intent.action.HSM_BOOTAPP_MANAGER")`<br>10. `com.huawei.systemmanager` / `com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity`<br>11. `com.huawei.systemmanager` / `com.huawei.systemmanager.optimize.process.ProtectActivity`<br>12. `com.hihonor.systemmanager` / `com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity` | `<intent>` `huawei.intent.action.HSM_BOOTAPP_MANAGER` + `<package>` `com.huawei.systemmanager`, `com.hihonor.systemmanager` |
| 魅族 (Flyme) | 13. `com.meizu.safe` / `com.meizu.safe.permission.SmartBGActivity`<br>14. `Intent("com.meizu.safe.permission.SHOW_APPSEC")` + `CATEGORY_DEFAULT` + extra `"packageName"` | `<intent>` `com.meizu.safe.permission.SHOW_APPSEC` + `<package>` `com.meizu.safe` |
| 三星 (国行 OneUI) | 15. `com.samsung.android.sm_cn` / `com.samsung.android.sm.autorun.ui.AutoRunActivity` | `<package>` `com.samsung.android.sm_cn` |

## 11. 线程模型、单飞防抖与 UI 零卡顿

### 11.1 原生线程与锁（适配 Flutter 3.29+ 主线程合并）

- `ReminderWorker`：`Executors.newSingleThreadExecutor`（`"qust-reminder-worker"`）。`ReminderBridge` 的 `sync`/`cancel`/`status`/`testReminder` 全部投递此线程，完成后 `mainHandler.post`（检 `!disposed`）回主线程；三大 Receiver 全走 `runBroadcastAsync`（`goAsync()` + `finally { pending.finish() }`）。
- `ReminderScheduler.LOCK`：`sync()`/`cancelAll()`/`topUpWindowFromStore()`/`status()` 均 `synchronized(LOCK)`。

### 11.2 `ReminderService` 状态机

```
_onModelChanged (监听 model 与 model.prefsNotifier) -> 重置 300ms _timer -> syncNow(force: false)
  ├── _cancelInFlight != null: 合并至 _postCancelSyncCompleter / _postCancelForce，取消完成后串行续跑
  ├── _syncInFlight != null: 合并至 _queuedSyncCompleter / _queuedForce，返回其 Future
  └── 空闲: _runSyncLoop 循环执行 _syncOnce 直到 !_queuedSyncCompleter（epoch/disposed/cancel 变更即中止）
```

- **冷启动保护**：`if (!model.preferencesLoaded) return null;`（防 `Preferences.open()` 前以默认 `false` 误调 `cancel()`）。
- **取消幂等与串行化**：无计划时仅 `!_cancelled` 调一次 `_gateway.cancel()` 并置 `_cancelled = true`。`cancelAll()` 递增 `_syncEpoch++`、清空 `_queuedSyncCompleter` 并在 `_runCancelAll()` 内先 `await _syncInFlight` 再调 `_gateway.cancel()`（避免在途同步覆盖已取消状态）。
- **失败不记指纹**：仅 `result.ok == true` 写入 `_lastFingerprint`。

### 11.3 `ReminderPage` 三卡隔离与 `RouteSettledStateMixin`

- **三卡自治**（禁顶层 `ListenableBuilder` / 整页 `setState`）：`_ReminderSettingsCard` 仅听 `model.prefsNotifier`（收起按钮局部听 `_statusNotifier`），滑块 `onChanged` 只改 `_leadDraft`，`onChangeEnd` 才落盘；`_PermissionsCard` 与 `_DiagnosticsCard` 仅听 `_statusNotifier`（形态行局部听 `prefsNotifier`），诊断条目一律用 `Text`（禁 `SelectableText`）。
- **`_queuedLeadMinutes` 合并**：`_run` 用 `_running` 锁串行原生操作；在途期间新提前量写入 `_queuedLeadMinutes`，由 `while (_queuedLeadMinutes != null && mounted)` 循环合并落盘并 `syncNow(force: true)`。
- **`RouteSettledStateMixin`**：`ReminderPage` 与 `_ReminderAndWidgetCard` 首帧用 `service.lastStatus` 同步渲染，`initState` 调 `unawaited(_refreshStatus(deferUntilSettled: true))` 与入场动画并行；若动画未完（`!isRouteSettled`）暂存 `_pendingStatus`/`_pendingStatusEpoch`，待 `onRouteSettled()` 调 `_flushPendingStatus()` 提交。

## 12. 严禁模式速查表（Pitfalls & Forbidden Patterns）

| 模块 | Don't（严禁） | Do（契约） | 根因 / 守护测试 |
| --- | --- | --- | --- |
| `reminderEventId` | 拼入 `leadMinutes` 或 `style` | 仅用 `entryId\|yyyyMMdd\|startPeriod` | 改设置若变 `requestCode` 会残留旧闹钟双重响铃 / `reminder_planner_test.dart` |
| `reminderFingerprint` | 含 `generatedAtMs` 或漏 `style` | 排除 `generatedAtMs`，含 `v`/`leadMinutes`/`style`/`fluidUntilEnd` + 排序事件 | 含时间则每次重排；漏 `style` 切换不重排 / `reminder_planner_test.dart` |
| `clampReminderLead` | 非预设档位回退默认 `10` | `value.clamp(1, 60)` 保留任意整数 | 滑块支持任意整数 / `reminder_planner_test.dart`, `timetable_test.dart` |
| 冷启动 `ReminderService` | 初始化未读盘就 `cancel()` | 先检 `model.preferencesLoaded` | 异步读盘前 `reminderEnabled==false` 会误清闹钟 / `reminder_service_test.dart` |
| `ReminderStore` | 用 `.apply()` | 全用 `.commit()` | 广播结束/进程冻结时 `apply()` 丢写盘致账本失一致 |
| `ReminderScheduler.arm` | 直接 `setAlarmClock` 覆盖同 `requestCode` | 先 `cancelPendingAlarm`（`manager.cancel` + `op.cancel`）再重挂 | 部分国产 ROM 原地覆盖缓存旧触发时刻 |
| 渠道注册 `ReminderNotifier` | 启动时无条件建渠道 | 须 `hasNotificationPermission()==true` 后建道 | ColorOS/HyperOS 未授权预建道会永久锁静默 |
| 通知 ID | 横幅与流体云共用 `2000` | 横幅 `2000`、流体云 `2001`，启动一方关闭另一方 | 共用 ID 会使回前台 `sync` 调 `stop` 时误撤横幅 |
| 流体云收起 | 仅靠 `setTimeoutAfter` | `RC_FLUID_STOP=2003` + `postDelayed` + `setTimeoutAfter` 三重 | FGS 通知带 `NO_CLEAR`，系统忽略 `setTimeoutAfter` |
| 流体云样式 | 设 `ProgressStyle`/`BigTextStyle` 或 Timer 轮询 | `ContentTitle` + `SubText` + `ShortCriticalText` + `Chronometer` + `FOREGROUND_SERVICE_IMMEDIATE` | `ProgressStyle` 与胶囊环重叠；`BigTextStyle` 不识别；轮询耗电闪烁 |
| 电池优化跳转 | 优先跳总列表或直弹白名单弹窗 | 优先 `ACTION_APPLICATION_DETAILS_SETTINGS` | 国产 ROM 私有耗电管理在应用详情页，放行后台会同步放行白名单 |
| `RC_TEST=2002` | 写入 `alarm_codes` 账本 | 独立于账本之外 | 进账本会被 `sync` 当多余闹钟撤掉 / `reminder_service_test.dart` |
| `ReminderPage` 性能 | 顶层 `ListenableBuilder` / `SelectableText` / `onChanged` 落盘 | 三卡隔离 / `Text` / `_leadDraft` / `deferUntilSettled: true` | 避免滑块拖动每帧重建 1500+ Widget 与首帧膨胀 / `widget_test.dart` |

## 13. 自动化测试与真机验收

### 13.1 自动化测试

```powershell
flutter test test/reminder_planner_test.dart test/reminder_service_test.dart test/timetable_test.dart test/widget_test.dart
```

- `test/reminder_planner_test.dart`：提前量（1/10/30）、`endMs` 末节下课、`roomOnly`、`clampReminderLead` 任意整数（7/43）、按当天切作息表、超节次 `skipped++`、单双周/空 `weeks`/超 `maxWeek`/调课、过点不补发、`maxEvents` 截断、`generatedAtMs` 不变指纹与 `event.id` 稳定。
- `test/reminder_service_test.dart`：指纹去重、`syncNow(force: true)`、`prefsNotifier` 变更重同步、改提前量/切流体云重排、失败不记指纹、`syncGate` 在途串行合并、`cancelAll()` 等在途同步并串行续跑、`_cancelled` 幂等、冷启动保护、300ms 防抖、`ReminderRuntimeStatus.fromMap`/`unavailable()`/`==`/`hashCode`、`MethodChannelReminderGateway` 往返与异常降级、预览/测试/`stopFluid`/4 项权限跳转。
- `test/support/fake_reminder_gateway.dart`：`FakeReminderGateway` 记录 `syncedPayloads`/`testRequests`/`previewRequests`/`toasts`，支持 `syncGate` 与 `syncResult` 注入。
- `test/timetable_test.dart`：`Preferences` 默认值、旧 schema 兼容、未知形态（`"capsule"`）回退 `banner`、`1..60` 夹取往返。
- `test/widget_test.dart`：入口显隐、`_leadDraft` 拖动不落盘、预设胶囊、流体云双向切换 + `stopFluid`、诊断卡、预览/5s/60s 测试、`resumed` 刷新、自启动恒显示手动确认。

### 13.2 真机诊断与验收（PLG110 / ColorOS / Android 17 基准）

```powershell
# 1. 全链路 Logcat
adb logcat -s ReminderWorker:V ReminderBridge:V ReminderScheduler:V ReminderReceiver:V ReminderFluid:V ReminderDailyResync:V ReminderRestore:V
# 2. 核查 AlarmManager 槽位
adb shell dumpsys alarm | Select-String -Pattern "com.fangzi.qustschedule|FLUID_STOP|DAILY_RESYNC|TEST_REMIND" -Context 2,4
# 3. 深度 Doze 穿透测试
adb shell dumpsys deviceidle force-idle
adb shell dumpsys deviceidle unforce
```

- **准点性**：点「5 秒后 / 1 分钟后测试提醒」后灭屏 + `force-idle`，Logcat `ReminderReceiver: fired ... deltaMs=...` 连续 3 次 `|deltaMs| <= 5000ms`。
- **流体云生命周期**：开流体云 → 「立即显示通知」立现胶囊与秒级倒计时；`dumpsys alarm` 见 `RC=2003` 挂于 `startMs`；到 `startMs` / 点「立即收起卡片」/ 切横幅后卡片消失且 `2003` 无残留。
- **跨进程状态刷新**：跳系统设置改权限返回 App，`didChangeAppLifecycleState(resumed)` 自动 `_refreshStatus()`，状态立即变绿。
