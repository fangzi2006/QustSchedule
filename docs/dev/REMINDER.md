# 课前提醒与流体云（Android）架构与全量技术契约

> **文档定位**：本文件为 Android 课前提醒与流体云（Fluid Cloud）子系统的**单一事实源（Single Source of Truth）**。完整覆盖 Dart 规划/编排/UI 与 Android 原生 Kotlin 13 个核心类的全部常量、JSON 协议、MethodChannel 签名、账本差分算法、通知/胶囊构建参数、权限跳转矩阵与防坑铁律。AI 检索本文件即可直接定位与修改代码，无需重读 Dart/Kotlin 源码。
>
> **功能边界**：
> - **支持**：每节课开始前 `1~60` 分钟（默认 `10` 分钟）提醒一次；形态二选一：**横幅通知（`banner`）** 或 **流体云常驻卡片（`fluid`）**（系统级 `Chronometer` 纳秒级倒计时，开课时刻三重冗余准时收起）。
> - **核心原则**：**日期、周次、单双周、调课、作息表切换计算 100% 留在 Dart 纯函数层（`reminder_planner.dart`）**，原生只消费绝对毫秒时间戳。
> - **不做**：下课提醒、课中常驻、每日摘要、上课勿扰、节假日在线拉取、厂商私有 UPK/幼苗 SDK。

---

## 目录（Quick TOC）

- [1. AI 极速文件与符号索引（Quick AI Index）](#1-ai-极速文件与符号索引quick-ai-index)
- [2. 常见开发任务速查路由（Where to Edit for Common Tasks）](#2-常见开发任务速查路由where-to-edit-for-common-tasks)
- [3. 分层架构与单向数据流](#3-分层架构与单向数据流)
- [4. 数据契约与 FNV-1a 指纹算法（`ReminderPayload`）](#4-数据契约与-fnv-1a-指纹算法reminderpayload)
- [5. MethodChannel 通信契约（`qustschedule/reminder`）](#5-methodchannel-通信契约qustschedulereminder)
- [6. 原生持久化与排程算法（14 天存储 + 10 天滚动窗口 + 账本差分）](#6-原生持久化与排程算法14-天存储--10-天滚动窗口--账本差分)
- [7. 全局 ID、RequestCode、Intent Action 与 Extra 常量速查表](#7-全局-idrequestcodeintent-action-与-extra-常量速查表)
- [8. 闹钟触发三重校验与通知/流体云渲染契约](#8-闹钟触发三重校验与通知流体云渲染契约)
- [9. 系统恢复矩阵与 `dirty` 语义](#9-系统恢复矩阵与-dirty-语义)
- [10. 权限诊断状态机与厂商设置跳转策略](#10-权限诊断状态机与厂商设置跳转策略)
- [11. 线程模型、单飞防抖与 UI 零卡顿架构](#11-线程模型单飞防抖与-ui-零卡顿架构)
- [12. 历史踩坑与严禁模式速查表（Pitfalls & Forbidden Patterns）](#12-历史踩坑与严禁模式速查表pitfalls--forbidden-patterns)
- [13. 自动化测试矩阵与真机实测手册](#13-自动化测试矩阵与真机实测手册)

---

## 1. AI 极速文件与符号索引（Quick AI Index）

### 1.1 Dart 侧文件索引（`qustschedule/`）

| 文件路径 | 核心类 / 函数 | 核心职责 | 关键方法 / 常量 / 字段 |
| --- | --- | --- | --- |
| `lib/src/reminder_planner.dart` | `ReminderStyle`, `CourseReminderEvent`, `ReminderPlan`, `planCourseReminders` | 纯函数规划层：将课表、调课、作息、周次换算为未来 14 天内的绝对毫秒提醒事件与 FNV-1a 指纹 | `reminderPayloadVersion = 1`, `reminderHorizonDays = 14`, `reminderMaxEvents = 120`, `reminderMinLeadMinutes = 1`, `reminderMaxLeadMinutes = 60`, `defaultReminderLeadMinutes = 10`, `reminderLeadOptions = [5,10,15,20,30]`, `clampReminderLead()`, `reminderEventId()`, `reminderFingerprint()` |
| `lib/src/reminder_gateway.dart` | `ReminderGateway`, `MethodChannelReminderGateway`, `ReminderSyncResult`, `ReminderRuntimeStatus` | `MethodChannel('qustschedule/reminder')` 窄接口抽象与平台异常兜底（桌面端静默吞掉 `MissingPluginException`） | `sync()`, `cancel()`, `status()`, `requestNotificationPermission()`, `openNotificationSettings()`, `openExactAlarmSettings()`, `openBatterySettings()`, `openAutostartSettings()`, `sendTestReminder()`, `previewReminder()`, `stopFluid()`, `showToast()` |
| `lib/src/reminder_service.dart` | `ReminderService` | 编排层：监听 `AppModel`，负责冷启动保护、300ms 防抖、指纹去重、单飞串行队列（`_syncInFlight`）与 `_syncEpoch` 取消隔离 | `syncNow({bool force = false})`, `buildPlan()`, `cancelAll()`, `refreshStatus()`, `lastPlan`, `lastResult`, `lastStatus`, `_syncInFlight`, `_resyncQueued`, `_resyncForceQueued`, `_syncEpoch`, `_cancelled` |
| `lib/pages/reminder_page.dart` | `ReminderPage`, `_ReminderSettingsCard`, `_PermissionsCard`, `_DiagnosticsCard`, `_LeadOptionPill` | 课程提醒子页面：三卡子树重建隔离、`RouteSettledStateMixin` 并行状态查询、滑块本地草稿 `_leadDraft` 与 `_queuedLeadMinutes` 串行合并 | `_statusNotifier`, `_statusEpoch`, `_pendingStatus`, `_toggleReminder()`, `_commitLead()`, `_toggleFluid()`, `_stopFluid()`, `_resync()`, `_preview()`, `_testIn5s()`, `_testInOneMinute()` |
| `lib/pages/settings_page.dart` | `SettingsPage`, `_ReminderAndWidgetCard` | 设置页「提醒与小组件」分区：托管课程提醒入口、桌面小组件入口，以及**忽略电池优化、精确闹钟、自启动**三项系统级可靠性权限 | `_openBattery()`, `_openExactAlarm()`, `_openAutostart()`, `_confirmSignOut()`（退出时调用 `reminders?.cancelAll()`） |
| `lib/widgets/reminder_permission_tile.dart` | `ReminderPermissionTile`, `showReminderGuideToast` | 权限状态行组件（`ok: true/false/null` 三态着色）与跨进程系统级 Toast 引导辅助函数 | `ReminderPermissionTile(icon, title, value, ok, actionLabel, onAction)`, `showReminderGuideToast()` |
| `lib/src/preferences_repository.dart` | `Preferences` | 偏好持久化（当前 `preferencesSchema = 14`）：存储提醒开关、提前量、形态与兼容字段 | `reminderEnabled`（默认 `false`）、`reminderLeadMinutes`（默认 `10`，夹取 `1..60`）、`reminderStyle`（默认 `banner`）、`reminderFluidUntilEnd`（默认 `false`） |
| `lib/main.dart` | `_AppShellState` | Android 宿主生命周期接线：`boot()` 前挂载 `ReminderService`，`AppLifecycleListener(onShow)` 回到前台调用 `syncNow(force: true)` | `_reminders`, `_onShown()` |

### 1.2 Android 原生侧文件索引（`qustschedule/android/app/src/main/`）

| 文件路径 | 核心类 / 单例 | 核心职责 | 关键方法 / 常量 |
| --- | --- | --- | --- |
| `kotlin/.../reminder/ReminderWorker.kt` | `ReminderWorker` (`internal object`) | 提醒模块共用后台单线程执行器（线程名 `qust-reminder-worker`），统一封装 `BroadcastReceiver.goAsync()` | `execute(Runnable)`, `runBroadcastAsync(receiver, tag, block)` |
| `kotlin/.../reminder/ReminderBridge.kt` | `ReminderBridge` | `qustschedule/reminder` 通道唯一 `MethodCallHandler`；重 I/O 任务派发 `ReminderWorker`，主线程 `Handler` 回调 `Result` | `CHANNEL = "qustschedule/reminder"`, `REQUEST_NOTIFICATION = 4501`, `attach()`, `dispose()`, `onMethodCall()`, `onRequestPermissionsResult()` |
| `kotlin/.../reminder/ReminderPayload.kt` | `ReminderPayload`, `ReminderEvent`, `ReminderPayloadException` | 原生严格 JSON 解析与校验（任何单条违规即整体抛 `ReminderPayloadException` 拒绝，保护旧 payload） | `VERSION = 1`, `STYLE_BANNER = "banner"`, `STYLE_FLUID = "fluid"`, `MAX_EVENTS = 200`, `MAX_LEAD_MINUTES = 180`, `MAX_PERIOD = 30`, `parse(json)` |
| `kotlin/.../reminder/ReminderStore.kt` | `ReminderStore` | `SharedPreferences("reminder_store")` 同步持久化（一律使用 `.commit()`）：存 payload 原文、指纹、闹钟账本、`dirty` 标记 | `PREFS = "reminder_store"`, `savePayload()`, `loadPayload()`, `alarmCodes()`, `setAlarmCodes()`, `removeAlarmCode()`, `markDirty()`, `clearDirty()`, `clear()` |
| `kotlin/.../reminder/ReminderScheduler.kt` | `ReminderScheduler`, `ReminderSyncOutcome` | 核心排程器：进程级 `LOCK`、10 天滚动窗口过滤、账本差分撤销、两级闹钟 API 降级、每日 00:05 自愈链与触发后 `topUpWindowFromStore` | `LOCK`, `SYSTEM_ALARM_WINDOW_DAYS = 10L`, `MIN_LEAD_MS = 1000L`, `RC_DAILY_RESYNC = 2001`, `RC_TEST = 2002`, `sync()`, `cancelAll()`, `rescheduleFromStore()`, `topUpWindowFromStore()`, `scheduleTest()`, `status()` |
| `kotlin/.../reminder/ReminderReceiver.kt` | `ReminderReceiver` | 闹钟广播入口：三重校验（`fingerprint` + `eventId` + `remindAtMs ± 1000ms`），派发横幅或流体云（流体云失败自动降级横幅），触发后滚动补齐窗口 | `ACTION_REMIND`, `ACTION_TEST`, `ACTION_DISMISS`, `ACTION_FLUID_STOP`, `TEST_LEAD_MINUTES = 10`, `handleRemind()`, `handleTest()` |
| `kotlin/.../reminder/ReminderDailyResyncReceiver.kt` | `ReminderDailyResyncReceiver` | 每日 00:05 自愈广播接收器：重放本地 payload 并续挂次日 00:05 一次性闹钟 | `ACTION_RESYNC = "com.fangzi.qustschedule.action.DAILY_RESYNC"` |
| `kotlin/.../reminder/ReminderRestoreReceiver.kt` | `ReminderRestoreReceiver` | 系统事件恢复接收器：处理开机、覆盖安装、改时间/时区（打 `dirty` 标记）、精确闹钟权限变更 | `SUPPORTED_ACTIONS`（5 项系统广播 Action） |
| `kotlin/.../reminder/ReminderNotifier.kt` | `ReminderNotifier` (`object`) | 横幅通知构建与发送：固定 ID `2000`、系统 `Chronometer` 倒计时、`setTimeoutAfter` 到点销毁、高优通知渠道延迟注册 | `CHANNEL_ID = "course_reminder_v1"`, `NOTIFY_ID = 2000`, `FLUID_NOTIFY_ID = 2001`, `REQUEST_CONTENT = 4402`, `show()`, `cancelBanner()`, `ensureAllChannels()`, `ensureHighAlertChannel()`, `bodyText()` |
| `kotlin/.../reminder/ReminderFluidRenderer.kt` | `ReminderFluidRenderer` (`object`), `FluidCardState` | 流体云常驻通知构建器：申请胶囊提升（`setRequestPromotedOngoing(true)`）、7 字临界短文本、立即展示前台服务标记 | `CHANNEL_FLUID = "course_fluid_v1"`, `REQUEST_CONTENT = 4403`, `build(context, state)`, `FluidCardState.detailText()` |
| `kotlin/.../reminder/ReminderFluidService.kt` | `ReminderFluidService` (`Service`) | 流体云 `specialUse` 前台服务：维持通知 `2001`，通过 `setTimeoutAfter` + `RC_FLUID_STOP(2003)` 精确闹钟 + `Handler.postDelayed` 三重机制在 `startMs` 准时自停 | `ACTION_START`, `ACTION_STOP`, `RC_FLUID_STOP = 2003`, `casting` (`@Volatile`), `start()`, `stop()`, `armStopAlarm()`, `disarmStopAlarm()` |
| `kotlin/.../reminder/ReminderSamples.kt` | `ReminderSamples` (`object`) | 诊断页「立即显示通知」与「测试提醒」唯一示例事件源 | `NAME = "高等数学（示例）"`, `TEACHER = "张老师"`, `ROOM = "3教201"`, `CLASS_MINUTES = 95L`, `event(leadMinutes)` |
| `kotlin/.../reminder/ReminderPermissions.kt` | `ReminderPermissions` (`object`) | 权限状态检测与 OEM 设置页安全跳转（含 15 个国产 ROM 自启动候选 Activity 探测与缓存） | `hasNotificationPermission()`, `notificationsEnabled()`, `canScheduleExactAlarms()`, `isIgnoringBatteryOptimizations()`, `hasAutostartSettings()`, `openNotificationSettings()`, `openExactAlarmSettings()`, `openBatterySettings()`, `openAutostartSettings()` |
| `kotlin/.../MainActivity.kt` | `MainActivity` | 宿主 Activity：唯一挂载 `ReminderBridge`，转发 `onRequestPermissionsResult`，在 `onDestroy` 释放 | `reminderBridge` |
| `AndroidManifest.xml` | `<manifest>` | 权限声明、3 个提醒 Receiver、1 个 `specialUse` 前台 Service 及 Android 11+ `<queries>` 包可见性白名单 | `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`, `FOREGROUND_SERVICE_SPECIAL_USE`, `POST_PROMOTED_NOTIFICATIONS` |

---

## 2. 常见开发任务速查路由（Where to Edit for Common Tasks）

| 常见开发 / 维护任务 | 目标文件与类 / 方法 | 必守架构约束（Invariants） | 必跑验证测试 |
| --- | --- | --- | --- |
| **修改提醒提前量范围或预设档位** | `lib/src/reminder_planner.dart` (`reminderMinLeadMinutes`, `reminderMaxLeadMinutes`, `reminderLeadOptions`, `clampReminderLead`) + `ReminderPayload.kt` (`MAX_LEAD_MINUTES`) | `clampReminderLead` 必须对区间内任意整数原样保留（滑块支持连续整数），严禁"非预设档位回落默认值"；改提前量严禁改变 `reminderEventId` | `flutter test test/reminder_planner_test.dart test/timetable_test.dart` |
| **修改横幅通知文案或样式** | `ReminderNotifier.kt` (`show`, `bodyText`) + `ReminderSamples.kt` + `reminder_planner.dart` (`roomOnly(entry.location)`) | 通知 ID 必须固定为 `NOTIFY_ID = 2000`；发横幅前必须调 `ReminderFluidService.stop(context)`；保持 `setUsesChronometer(true)` + `setChronometerCountDown(true)` + `setTimeoutAfter` | `flutter test test/reminder_planner_test.dart` + 真机点「立即显示通知」 |
| **修改流体云卡片文案或胶囊属性** | `ReminderFluidRenderer.kt` (`FluidCardState.detailText`, `build`) + `ReminderFluidService.kt` | 严禁加回 `ProgressStyle`（与系统胶囊环重叠）或 `BigTextStyle`（流体云模板不识别）；必须保留 `setForegroundServiceBehavior(FOREGROUND_SERVICE_IMMEDIATE)` 与 `RC_FLUID_STOP = 2003` 闹钟兜底 | `flutter test test/reminder_service_test.dart` + 真机流体云预览/5s 测试 |
| **修改课表事件过滤 / 调课 / 作息换算** | `lib/src/reminder_planner.dart` (`planCourseReminders`) | 保持纯函数（不读 `DateTime.now()`、不碰通道）；按**事件当天**调 `activeTimetableAt` 选作息表；`remindAtMs <= now` 一律跳过不补发 | `flutter test test/reminder_planner_test.dart` |
| **新增/修改 MethodChannel 方法或状态字段** | `lib/src/reminder_gateway.dart` + `lib/src/reminder_service.dart` + `ReminderBridge.kt` + `ReminderScheduler.kt` + `test/support/fake_reminder_gateway.dart` | 涉及 `SharedPreferences` 或 `AlarmManager` 的通道调用必须投递到 `ReminderWorker.execute`，再用 `postReply` 回主线程；`FakeReminderGateway` 必须同步实现新接口 | `flutter test test/reminder_service_test.dart test/widget_test.dart` |
| **调整权限检测或国产 ROM 设置页跳转** | `ReminderPermissions.kt` + `lib/pages/settings_page.dart` (`_ReminderAndWidgetCard`) + `lib/pages/reminder_page.dart` (`_PermissionsCard`) | 通知权限在 `ReminderPage`；电池优化、精确闹钟、自启动三项在 `SettingsPage` 的 `_ReminderAndWidgetCard`；新增自启动包名/Action 必须同步写入 `AndroidManifest.xml` 的 `<queries>` | `flutter test test/reminder_service_test.dart test/widget_test.dart` |
| **排查提醒页面切换或滑块拖动卡顿** | `lib/pages/reminder_page.dart` + `lib/pages/settings_page.dart` + `lib/src/route_settled.dart` | 严禁在 `ReminderPage` 顶层套 `ListenableBuilder`；滑块 `onChanged` 只改 `_ReminderSettingsCardState._leadDraft`；`initState` 刷新状态必须带 `deferUntilSettled: true` | `flutter test test/widget_test.dart` |

---

## 3. 分层架构与单向数据流

```
SettingsPage（_ReminderAndWidgetCard：入口 + 电池优化/精确闹钟/自启动权限）
  └── ReminderPage（_ReminderSettingsCard + _PermissionsCard[通知权限] + _DiagnosticsCard）
        ↓ 读写偏好 / 触发动作
      AppModel（PreferencesController + ScheduleController：课表 + 调课 + 作息 + 节数 + 周次）
        ↓ Listenable 变更通知
      ReminderService（冷启动保护、300ms 防抖、指纹去重、_syncInFlight 单飞队列、_syncEpoch）
        ├── reminder_planner.dart（纯函数：课表 → 未来 14 天绝对毫秒事件列表 + FNV-1a 指纹）
        └── ReminderGateway（MethodChannel('qustschedule/reminder') 抽象，测试可换 FakeReminderGateway）
              ↓
            ReminderBridge（Kotlin，MainActivity 挂载的通道唯一 handler）
              ↓ 投递至 ReminderWorker（"qust-reminder-worker" 单线程）
              ├── ReminderPayload（严格 JSON 校验，非法整体拒绝）
              ├── ReminderStore（SharedPreferences("reminder_store")，commit() 同步落盘）
              ├── ReminderScheduler（进程级 LOCK、10 天滚动挂钟窗口、账本差分、00:05 自愈链）
              │     ├── ReminderReceiver（到点三重校验 → 横幅 or 起流体云 + topUpWindowFromStore）
              │     │     ├── ReminderNotifier（横幅通知 ID=2000，Chronometer 倒计时 + setTimeoutAfter）
              │     │     └── ReminderFluidService（specialUse 前台服务 ID=2001 + RC_FLUID_STOP=2003 准时自停）
              │     │           └── ReminderFluidRenderer（公开 Promoted Ongoing 胶囊通知构建）
              │     └── ReminderDailyResyncReceiver（每日 00:05 幂等重放本地 payload）
              └── ReminderRestoreReceiver（BOOT_COMPLETED / MY_PACKAGE_REPLACED / TIME_SET / TIMEZONE_CHANGED / EXACT_ALARM）
```

- **单向职责边界**：UI → `ReminderService` → `ReminderGateway` → 原生。**原生绝不计算"今天是第几周 / 哪张作息表生效 / 是否单双周或调课"**。

---

## 4. 数据契约与 FNV-1a 指纹算法（`ReminderPayload`）

### 4.1 Payload JSON 完整结构（Dart 生成，原生只读消费）

```json
{
  "v": 1,
  "generatedAtMs": 1761600000000,
  "leadMinutes": 10,
  "style": "banner",
  "fluidUntilEnd": false,
  "fingerprint": "8f3a1c2d",
  "events": [
    {
      "id": "e_5c1a9b7e",
      "entryId": "原始课表条目 ScheduleEntry.id",
      "name": "高等数学",
      "teacher": "张三",
      "location": "3教201",
      "startMs": 1761610200000,
      "endMs": 1761612900000,
      "remindAtMs": 1761609600000,
      "startPeriod": 3,
      "endPeriod": 4,
      "week": 8
    }
  ]
}
```

> **注意**：Dart `CourseReminderEvent.toJson()` 包含 `entryId` 字段供 Dart 侧测试与追踪；Kotlin `ReminderPayload.parseEvent()` 解析 `id`, `name`, `teacher`, `location`, `startMs`, `endMs`, `remindAtMs`, `startPeriod`, `endPeriod`, `week`（忽略未知字段）。

### 4.2 FNV-1a 32 位哈希算法与字段包含/排除铁律

`reminder_planner.dart` 使用标准 32 位 FNV-1a（对 UTF-8 字节序列计算，跨平台确定性一致）：
- 初始值 `offset_basis = 0x811C9DC5`
- 质数乘数 `FNV_prime = 0x01000193`，每步掩码 `& 0xFFFFFFFF`
- 输出格式：`toRadixString(16).padLeft(8, '0')`（8 位小写十六进制）

| 标识符 | 精确种子拼接公式（Seed Format） | 必须包含（Included） | 严禁包含（Excluded）及原因 |
| --- | --- | --- | --- |
| **事件 ID (`event.id`)** | `'e_' + hex32(fnv1a('$entryId|$yyyyMMdd|$startPeriod'))` | `entryId`、课程当天日期 `yyyyMMdd`、起始节次 `startPeriod` | **严禁包含 `leadMinutes` 和 `style`**：用户修改提前量或切换横幅/流体云时，同一节课的 `event.id` 必须保持不变，从而派生相同的 `requestCode` 原地覆盖旧闹钟，避免旧槽位残留导致双重响铃。 |
| **全局指纹 (`fingerprint`)** | `hex32(fnv1a('v$v\|lead$leadMinutes\|style${style.wireName}\|untilEnd$fluidUntilEnd' + 按 id 升序拼接的 '\|$id:$startMs:$remindAtMs'))` | 版本 `v`、提前量 `leadMinutes`、形态 `style`、`fluidUntilEnd`、所有事件的 `id:startMs:remindAtMs` | **严禁包含 `generatedAtMs`**：相同的课表与设置在不同时刻重算必须得出完全相同的 `fingerprint`，否则每次冷启动或回到前台都会误判课表变更并重复触发原生 I/O。 |

### 4.3 Dart 规划规则（`planCourseReminders`）与 Kotlin 严格校验规则（`ReminderPayload.parse`）

| 维度 | Dart 规划层（`reminder_planner.dart`） | Kotlin 解析校验层（`ReminderPayload.kt`） |
| --- | --- | --- |
| **时间窗口与条数上限** | 从 `dayOnly(now)` 起逐日推进 `reminderHorizonDays = 14` 天；按 `remindAtMs` 升序（同刻按 `id` 升序）、按 `id` 去重后最多保留 `reminderMaxEvents = 120` 条（超出时 `truncated = true`）。 | 单次 `events.length <= MAX_EVENTS (200)`；超出抛 `ReminderPayloadException("事件过多：...")`。 |
| **周次与调课** | `week = weekOf(termStart, date)`，不在 `1..safeMaxWeek` 内的日期跳过；每周调用一次 `rescheduleWeekView(...)` 获取叠加调课后的有效课程列表，并用 `occursInWeek(entry, week)` 二次确认（兼容 `weeks` 为空表示每周都上）。 | `week = json.optInt("week", 0)`，仅作元数据保存，原生不做周次运算。 |
| **作息表与节次时间** | 按**事件当天 `date`** 调用 `activeTimetableAt(timetables, date)` 匹配生效作息表，并通过 `reconcileSections(table.sections, sectionCounts)` 对齐全局节数；找不到 `startPeriod` 时 `skipped++` 并跳过；`endMinutes` 取 `endPeriod` 的**下课时刻**（取不到回退 `startMinutes`）。 | `startPeriod in 1..30` 且 `endPeriod in startPeriod..30`（`MAX_PERIOD = 30`）；`endMs = if (endMs >= startMs) endMs else startMs`。 |
| **提前量与过期过滤** | `lead = clampReminderLead(leadMinutes)`（夹取 `1..60`）；`remindAtMs = startMs - lead * 60000`；凡是 `remindAtMs <= now.millisecondsSinceEpoch` 的已过点事件**一律跳过不补发**。 | `leadMinutes in 1..180`（`MAX_LEAD_MINUTES = 180`）；`generatedAtMs > 0`、`startMs > 0`、`remindAtMs > 0` 且 **`remindAtMs < startMs`**。 |
| **文本派生与标识** | `teacher = entry.teacher ?? ''`；`location = roomOnly(entry.location ?? '')`（与课表格子一致，剔除校区/教学楼前缀只留房间号）。 | `v in 1..VERSION(1)`、`fingerprint.isNotEmpty()`、`style in {"banner", "fluid"}`、`id.length in 1..64` 且**批次内 `id` 不重复**。任何一项不合法整体抛 `ReminderPayloadException`，**绝不覆盖 `ReminderStore` 中已保存的旧 payload**。 |

---

## 5. MethodChannel 通信契约（`qustschedule/reminder`）

> **单一 Handler 铁律**：`MainActivity.configureFlutterEngine` 中仅由 `ReminderBridge` 注册 `qustschedule/reminder` 通道。严禁注册第二个 Handler。

### 5.1 通道方法全表（12 个方法）

| 方法名 | 参数类型与结构 | 原生执行线程 | 成功返回值 | 原生错误码 (`PlatformException`) | Dart `MethodChannelReminderGateway` 行为 |
| --- | --- | --- | --- | --- | --- |
| `sync` | `String`（Payload JSON 原文） | `ReminderWorker` 后台单线程 | `Map`: `{"scheduled": Int, "nextTriggerMs": Long?, "coverageEndMs": Long?, "style": String, "exactAlarmAllowed": Boolean}` | `BAD_ARGS`（json 为空）、`SYNC_FAILED`（解析或排程异常） | 返回 `ReminderSyncResult`；异常或桌面端无通道时返回 `ReminderSyncResult.failure(msg)`（`ok == false`） |
| `cancel` | `null` | `ReminderWorker` 后台单线程 | `null`（撤闹钟 + 清账本 + 撤 00:05 自愈 + 撤横幅 `2000` + 停流体云 `2001`/`2003` + `store.clear()`） | — | `Future<void>`，异常静默吞掉 |
| `status` | `null` | `ReminderWorker` 后台单线程 | `Map<String, Any?>`（11 个字段，见 5.2 节） | `STATUS_FAILED` | 返回 `ReminderRuntimeStatus`；异常或桌面端返回 `ReminderRuntimeStatus.unavailable()`（`available: false`） |
| `requestNotificationPermission` | `null` | 主线程（必要时调 `Activity.requestPermissions` 弹窗，`REQUEST_NOTIFICATION = 4501`） | `Boolean`（已授权或 Android 12- 直接建渠道并返回 `true`；弹窗授权成功后建渠道） | `BUSY`（已有并发权限弹窗未结束） | 返回 `Future<bool>`，异常返回 `false` |
| `openNotificationSettings` | `null` | 主线程 | `null`（先 `ensureAllChannels`，再跳 `ACTION_APP_NOTIFICATION_SETTINGS`，失败退应用详情页） | — | `Future<void>` |
| `openExactAlarmSettings` | `null` | 主线程 | `Boolean`（**跳转前瞬间**的 `canScheduleExactAlarms` 快照，仅作提示） | — | 返回 `Future<bool>`，调用后由 `ReminderService` 跟进 `refreshStatus()` |
| `openBatterySettings` | `null` | 主线程 | `null`（优先跳 `ACTION_APPLICATION_DETAILS_SETTINGS` 应用详情页，失败退 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`） | — | `Future<void>` |
| `openAutostartSettings` | `null` | 主线程 | `Boolean`（`true` = 成功打开厂商自启动管理页；`false` = 退回系统设置主页 `ACTION_SETTINGS` 或应用详情） | — | 返回 `Future<bool>` |
| `testReminder` | `Map`: `{"style": String, "delaySeconds": Int}` | `ReminderWorker` 后台单线程 | `Long`（计划触发的绝对毫秒时间戳 `epoch`；`delaySeconds` 原生夹取 `5..3600` 秒） | `TEST_FAILED`（无法获取 `AlarmManager` 或 `SecurityException`） | `sendTestReminder` 判断 `epoch != null && epoch > 0` 返回 `bool` |
| `previewReminder` | `Map`: `{"style": String, "leadMinutes": Int, "untilEnd": Boolean}` | 主线程 | `Boolean`（用 `ReminderSamples.event(lead)` 立即发横幅或起流体云服务，**不挂闹钟、不进账本**） | — | 返回 `Future<bool>` |
| `stopFluid` | `null` | 主线程 | `null`（调 `ReminderFluidService.stop(activity)`：停服务 + 撤 `2001` 通知 + 撤 `2003` 闹钟） | — | `Future<void>` |
| `toast` | `Map`: `{"message": String, "long": Boolean}` | 主线程 `mainHandler.post` | `null`（调用系统 `Toast.makeText(appContext, ...)`，跨进程浮在系统设置页上方） | — | `showToast(message, {longDuration})` |

### 5.2 `status` 返回字段与 `ReminderRuntimeStatus` 映射表

| 原生 `status()` Map Key | 类型 | 原生计算来源 | Dart `ReminderRuntimeStatus` 属性与派生 Getter |
| --- | --- | --- | --- |
| — | `bool` | Dart 侧默认 `true`；通道报错或桌面端为 `false` | `available` |
| `notificationPermission` | `Boolean` | Android 13+ (`TIRAMISU`) 查 `POST_NOTIFICATIONS == GRANTED`；Android 12- 恒为 `true` | `notificationPermission` |
| `notificationsEnabled` | `Boolean` | `NotificationManager.areNotificationsEnabled()` | `notificationsEnabled`；派生 **`canNotify => notificationPermission && notificationsEnabled`** |
| `exactAlarmAllowed` | `Boolean` | Android 12+ (`S`) 查 `AlarmManager.canScheduleExactAlarms()`；Android 11- 恒为 `true` | `exactAlarmAllowed` |
| `batteryOptimizationIgnored` | `Boolean` | `PowerManager.isIgnoringBatteryOptimizations(packageName)` | `batteryOptimizationIgnored`；派生 **`batteryOptOut => batteryOptimizationIgnored`** |
| `autoStartVendorPage` | `Boolean` | `ReminderPermissions.hasAutostartSettings(context)`（进程内 `@Volatile` 缓存一次探测结果） | `autoStartVendorPage` |
| `scheduled` | `Int` | `store.alarmCodes().size`（当前已挂入系统的 10 天窗口内闹钟账本大小，不含测试闹钟 `2002`） | `scheduled` |
| `nextTriggerMs` | `Long?` | `payload.events.filter { it.remindAtMs > now }.minOfOrNull { it.remindAtMs }` | `nextTriggerMs` |
| `payloadAtMs` | `Long?` | `store.payloadAtMs()`（`> 0` 时返回，否则 `null`） | `payloadAtMs` |
| `fingerprint` | `String` | `store.fingerprint()` | `fingerprint` |
| `style` | `String` | `store.style()`（`"banner"` 或 `"fluid"`） | `style` |
| `dirty` | `Boolean` | `store.isDirty()`（系统时间/时区变更后置 `true`，Flutter 同步后清 `false`） | 原生返回，Dart 侧由 `onAppShown -> syncNow(force: true)` 直接覆盖并清除 |
| `fluidCasting` | `Boolean` | `ReminderFluidService.casting`（`@Volatile` 静态布尔值） | `fluidCasting`（控制设置卡「立即收起卡片」按钮显隐与诊断行状态） |

---

## 6. 原生持久化与排程算法（14 天存储 + 10 天滚动窗口 + 账本差分）

### 6.1 `ReminderStore` 本地持久化契约（`SharedPreferences("reminder_store")`）

> **同步落盘铁律**：所有写操作（`savePayload`, `setAlarmCodes`, `clearAlarmCodes`, `markDirty`, `clearDirty`, `clear`）**一律使用 `.commit()`**，严禁使用 `.apply()`。原因：广播 `goAsync()` 结束或进程被系统冻结时，异步 `apply()` 会导致 payload 与 `alarm_codes` 账本落盘不一致，引发重启后漏响或幽灵重复响。

| Key 常量 | Key 字符串 | 类型 | 说明 |
| --- | --- | --- | --- |
| `KEY_PAYLOAD_JSON` | `"payload_json"` | `String?` | Dart 下发的完整 14 天 Payload JSON 原文 |
| `KEY_FINGERPRINT` | `"fingerprint"` | `String` | 当前生效的 8 位十六进制 FNV-1a 指纹（默认 `""`） |
| `KEY_PAYLOAD_AT_MS` | `"payload_at_ms"` | `Long` | 原生收到并保存该 payload 的本地时刻 `System.currentTimeMillis()` |
| `KEY_LEAD_MINUTES` | `"lead_minutes"` | `Int` | 提前分钟数 |
| `KEY_STYLE` | `"style"` | `String` | `"banner"` 或 `"fluid"` |
| `KEY_ALARM_CODES` | `"alarm_codes"` | `String` | 已挂载到 `AlarmManager` 的课程事件 `requestCode` 集合，逗号分隔（如 `"1048291,8923741"`） |
| `KEY_DIRTY` | `"dirty"` | `Boolean` | 系统时间或时区被修改后置为 `true`；仅当 `sync(..., fromFlutter = true)` 时调 `clearDirty()` 置回 `false` |

### 6.2 两级闹钟 API 选型与降级策略

| 闹钟用途 | 有精确闹钟权限 (`canScheduleExactAlarms() == true`) | 无权限或捕获 `SecurityException` 降级 | 选型原因 |
| --- | --- | --- | --- |
| **课程提醒到点 (`ACTION_REMIND`)** | `setAlarmClock(AlarmClockInfo(remindAtMs, contentIntent), operation)` | `setAndAllowWhileIdle(RTC_WAKEUP, remindAtMs, operation)` | ColorOS 16 等国产 ROM 会将 `setExactAndAllowWhileIdle` 的投递窗口强行拉长至 `+1h`；唯有 `setAlarmClock` 享受系统最高闹钟豁免，灭屏/Doze 下误差 `< 5s`。 |
| **测试提醒 (`ACTION_TEST`, `RC_TEST=2002`)** | `setAlarmClock(AlarmClockInfo(epoch, contentIntent), operation)` | `setAndAllowWhileIdle(RTC_WAKEUP, epoch, operation)` | 与正式课程提醒走完全相同的系统闹钟通道以供端到端验收。 |
| **流体云开课收起兜底 (`ACTION_FLUID_STOP`, `RC_FLUID_STOP=2003`)** | `setAlarmClock(AlarmClockInfo(startMs, contentIntent), operation)` | `setAndAllowWhileIdle(RTC_WAKEUP, startMs, operation)` | 前台服务通知被系统附加 `FOREGROUND_SERVICE \| NO_CLEAR`，系统忽略 `setTimeoutAfter`；必须靠精确闹钟在 Doze 下唤醒进程执行 `stopSelf()`。 |
| **每日 00:05 自愈链 (`ACTION_RESYNC`, `RC_DAILY_RESYNC=2001`)** | `setExactAndAllowWhileIdle(RTC_WAKEUP, targetMs, operation)` | `setAndAllowWhileIdle(RTC_WAKEUP, targetMs, operation)` | 夜间后台自愈允许几分钟偏差，不必使用 `setAlarmClock` 避免常驻状态栏闹钟图标。 |

### 6.3 14 天持久化 vs 10 天系统闹钟滚动窗口 & 账本差分算法

1. **为什么双窗口（14 天存盘 / 10 天挂钟）**：
   - `ReminderStore` 保存 Dart 规划好的完整 **14 天**（`reminderHorizonDays = 14`，最多 120 条）payload。
   - `ReminderScheduler` 仅向系统 `AlarmManager` 注册 `remindAtMs in (now + 1000ms, now + 10d]`（`SYSTEM_ALARM_WINDOW_DAYS = 10L`，`MIN_LEAD_MS = 1000L`）内的事件，减少系统闹钟槽位占用。
2. **账本差分算法（`ReminderScheduler.sync`）**：
   - 设 `previous = store.alarmCodes().toSet()`（上次实际挂入系统的 requestCode 集合）。
   - 遍历 `payload.events`：计算 `code = requestCodeFor(event.id)`，加入 `windowCodes`；若 `event.remindAtMs > now + 1000L && event.remindAtMs <= now + 10d`，放入 `desired[code] = event`。
   - **差分撤销**：对 `code in (previous + windowCodes) - desired.keys`，调用 `cancel(code)` 撤销不再需要的旧闹钟（含换课表、删课、移出窗口的事件）及历史遗留的 `dismissCode`。
   - **原地先撤后挂（`arm`）**：对 `desired` 中的每个 `(code, event)`，在 `arm()` 内部**先调用 `cancelReminderOperation(manager, code)`**（以 `FLAG_NO_CREATE | FLAG_IMMUTABLE` 取出旧 `PendingIntent`，执行 `manager.cancel(op)` + `op.cancel()`），再创建携带最新 extras 的新 `PendingIntent` 并调用 `setAlarmClock` / `setAndAllowWhileIdle`，最后清理旧版遗留的 `cancelLegacyDismiss`。
   - **原因**：既避免了"全局先全撤再全排"导致的中间无闹钟空窗，又防止部分国产 ROM 在同 `requestCode` 原地覆盖 `setAlarmClock` 时缓存旧触发时间戳。
3. **双轨滚动续挂（00:05 自愈 + 触发顺延补齐）**：
   - **每日 00:05 自愈（`ReminderDailyResyncReceiver`）**：触发时调用 `rescheduleFromStore()` 全量重放本地 14 天 payload 并重挂次日 00:05 一次性闹钟，修复被 OEM 清理的闹钟并将第 11 天推进 10 天窗口。
   - **每次提醒触发后补齐（`topUpWindowFromStore`）**：`ReminderReceiver.handleRemind` 每次响铃后调用 `store.removeAlarmCode(code)` 并执行 `scheduler.topUpWindowFromStore()`，仅将刚进入 10 天窗口且不在 `armed` 账本中的新事件增量挂上闹钟，防止夜间 00:05 自愈被 OEM 冻结时第 11~14 天断档。

---

## 7. 全局 ID、RequestCode、Intent Action 与 Extra 常量速查表

### 7.1 通知 ID、渠道 ID 与 PendingIntent RequestCode 分配表

| 常量名 | 所属类 | 精确值 | 用途与隔离语义 |
| --- | --- | --- | --- |
| `CHANNEL_ID` | `ReminderNotifier` | `"course_reminder_v1"` | 普通横幅通知渠道（「上课提醒」，`IMPORTANCE_HIGH`，开启角标） |
| `CHANNEL_FLUID` | `ReminderFluidRenderer` | `"course_fluid_v1"` | 流体云常驻卡片通知渠道（「上课进度」，`IMPORTANCE_HIGH`，关闭角标） |
| `NOTIFY_ID` | `ReminderNotifier` | `2000` | 普通横幅通知固定 ID（新课提醒覆盖旧横幅，不堆叠） |
| `FLUID_NOTIFY_ID` | `ReminderNotifier` | `2001` | 流体云前台服务通知固定 ID（与横幅 `2000` 物理隔离，防止横幅模式下回到前台 `sync` 时误撤正在展示的横幅） |
| `RC_DAILY_RESYNC` | `ReminderScheduler` | `2001` | 每日 00:05 自愈闹钟 `PendingIntent.getBroadcast` 的 requestCode（目标 Receiver 为 `ReminderDailyResyncReceiver`） |
| `RC_TEST` | `ReminderScheduler` | `2002` | 诊断页测试提醒闹钟 `PendingIntent.getBroadcast` 的 requestCode（**不进 `alarm_codes` 账本**，不受 `sync`/`cancelAll` 影响） |
| `RC_FLUID_STOP` | `ReminderFluidService` | `2003` | 流体云开课时刻（`startMs`）准时收起兜底闹钟 requestCode |
| `REQUEST_CONTENT` | `ReminderNotifier` | `4402` | 点击横幅通知回 `MainActivity` (`FLAG_ACTIVITY_SINGLE_TOP`) 的 `PendingIntent.getActivity` requestCode |
| `REQUEST_CONTENT` | `ReminderFluidRenderer` | `4403` | 点击流体云卡片回 `MainActivity` (`FLAG_ACTIVITY_SINGLE_TOP`) 的 `PendingIntent.getActivity` requestCode |
| `REQUEST_NOTIFICATION` | `ReminderBridge` | `4501` | Android 13+ `Activity.requestPermissions(POST_NOTIFICATIONS)` 的权限请求码 |
| `requestCodeFor(id)` | `ReminderScheduler` | `val c = id.hashCode() and 0x3fffffff; if (c == 0) 1 else c` | 课程提醒闹钟槽位（正整数 `1..0x3FFFFFFF`，最高两位恒为 `00`） |
| `dismissCodeFor(id)` | `ReminderScheduler` | `requestCodeFor(id) or 0x40000000` | 旧版本遗留开课撤销闹钟槽位（次高位为 `1`），仅在 `arm()` / `cancel()` 时做清理兼容 |

### 7.2 广播与服务 Intent Action 及 Extras 契约

| 组件 | Action 常量与值 | 携带 Extras | 触发源与处理逻辑 |
| --- | --- | --- | --- |
| `ReminderReceiver` | `ACTION_REMIND = "com.fangzi.qustschedule.action.REMIND"` | `event_id` (`String`), `fingerprint` (`String`), `remind_at_ms` (`Long`), `request_code` (`Int`) | 正式课程闹钟到点 → 三重校验 → 发横幅或起流体云 → 从账本移除 `request_code` → `topUpWindowFromStore()` |
| `ReminderReceiver` | `ACTION_TEST = "com.fangzi.qustschedule.action.TEST_REMIND"` | `test_style` (`String`: `"banner"` / `"fluid"`) | 诊断页 5s / 60s 测试闹钟到点 → 用 `ReminderSamples.event(10)` 发通知或起流体云（不读 payload） |
| `ReminderReceiver` | `ACTION_FLUID_STOP = "com.fangzi.qustschedule.action.FLUID_STOP"` | 无 | `RC_FLUID_STOP(2003)` 到点 → 调 `ReminderFluidService.stop(context)` 收起流体云 |
| `ReminderReceiver` | `ACTION_DISMISS = "com.fangzi.qustschedule.action.DISMISS"` | 无 | 历史遗留兼容：同时调用 `ReminderNotifier.cancelBanner` 与 `ReminderFluidService.stop` |
| `ReminderDailyResyncReceiver` | `ACTION_RESYNC = "com.fangzi.qustschedule.action.DAILY_RESYNC"` | 无 | 每日 00:05 自愈闹钟 → `ReminderScheduler(context).rescheduleFromStore()` |
| `ReminderFluidService` | `ACTION_START = "com.fangzi.qustschedule.action.FLUID_START"` | `name`, `room`, `teacher` (`String`), `start_ms`, `end_ms`, `notify_epoch` (`Long`), `start_period`, `end_period` (`Int`) | 闹钟到点或预览触发 → 校验 `now < startMs` → 撤横幅 `2000` → `startForeground(2001)` → 挂 `2003` 闹钟 + `postDelayed` |
| `ReminderFluidService` | `ACTION_STOP = "com.fangzi.qustschedule.action.FLUID_STOP"` | 无 | 显式停止服务 → `stopSelf()` → `onDestroy` 清理 `stopRunnable`、撤 `2003` 闹钟、`casting = false` |

---

## 8. 闹钟触发三重校验与通知/流体云渲染契约

### 8.1 `ReminderReceiver.handleRemind` 三重校验（防旧课表误响）

闹钟在 `ReminderWorker.runBroadcastAsync`（`goAsync()` 保护）下执行，必须连续通过以下 3 项校验才允许发通知：
1. **指纹一致**：`intent.getStringExtra("fingerprint") == payload.fingerprint`
2. **事件存在**：`payload.events.firstOrNull { it.id == eventId } != null`
3. **触发时刻一致（1 秒容差）**：`kotlin.math.abs(event.remindAtMs - expected) <= 1000L`

> **自愈机制**：以上任意一条不匹配（例如改了课表、调了提前量、换了形态但旧闹钟残留在系统内），立即丢弃本次触发并调用 **`scheduler.rescheduleFromStore()`** 按当前存储的 payload 重排一次，绝不按过期数据误响。

### 8.2 横幅通知 (`ReminderNotifier`) vs 流体云卡片 (`ReminderFluidRenderer` + `ReminderFluidService`) 对比规格

| 维度 | 横幅通知（`style = "banner"`） | 流体云常驻卡片（`style = "fluid"`） |
| --- | --- | --- |
| **通知渠道与延迟建道** | `course_reminder_v1`（「上课提醒」），`IMPORTANCE_HIGH`，`showBadge = true` | `course_fluid_v1`（「上课进度」），`IMPORTANCE_HIGH`，`showBadge = false` |
| **渠道创建前置条件** | **必须在 `ReminderPermissions.hasNotificationPermission(context) == true` 后才创建渠道**（`ensureHighAlertChannel`），防止国产 ROM 在未授权状态下将新渠道永久锁定为静默/折叠。统一配置：`VISIBILITY_PUBLIC`、默认提示音、呼吸灯、震动波形 `longArrayOf(0L, 250L, 150L, 250L)`（Android 15 / `VANILLA_ICE_CREAM` 起同步设置 `VibrationEffect.createWaveform(..., -1)`）。 | 同左（共用 `ReminderNotifier.ensureHighAlertChannel`）。 |
| **通知 ID 与互斥清理** | `NOTIFY_ID = 2000`；发送前先调 `ReminderFluidService.stop(context)` | `FLUID_NOTIFY_ID = 2001`；`startForeground` 前先调 `ReminderNotifier.cancelBanner(this)` |
| **标题与正文排版** | - `ContentTitle`: `event.name.ifEmpty { "上课提醒" }`<br>- `ContentText` & `BigTextStyle`: `bodyText(event)` → `"HH:mm 上课 · 地点 · 教师"`（空字段省略，不设 `SubText`） | - `ContentTitle`: `state.name.ifEmpty { "上课提醒" }`<br>- `SubText`: `state.detailText()` → `"HH:mm - HH:mm · 教室 · 老师"`（空字段省略）<br>- `ShortCriticalText`: `primary.take(7)`（`primary = room.ifEmpty { name }.ifEmpty { "上课提醒" }`，供状态栏胶囊展示）<br>- **不设 `ContentText`、不设 `BigTextStyle`、不设 `ProgressStyle`** |
| **系统级倒计时** | `setWhen(event.startMs)` + `setShowWhen(true)` + `setUsesChronometer(true)` + `setChronometerCountDown(true)`（由 SystemUI 原生走秒，0 CPU 唤醒） | 同左（由 SystemUI 原生走秒，服务内**无任何轮询 Timer**） |
| **常驻与胶囊提升标志** | `setOngoing(true)` + `setAutoCancel(false)` + `CATEGORY_REMINDER` + `PRIORITY_HIGH` + `DEFAULT_ALL` + `VISIBILITY_PUBLIC` | 同左，额外增加：<br>- `setRequestPromotedOngoing(true)`（Android 16+ / ColorOS 流体云胶囊提升公开 API）<br>- `setForegroundServiceBehavior(FOREGROUND_SERVICE_IMMEDIATE)`（豁免 Android 12+ 前台服务 10 秒延迟展示） |
| **开课时刻 (`startMs`) 自动收起机制** | 单靠系统内核 `setTimeoutAfter((event.startMs - now).coerceAtLeast(1000L))`（普通通知设 `setOngoing(true)` 后 `setTimeoutAfter` 依然生效，即使进程被杀 System Server 也会准点销毁） | **三重冗余收起保障**：<br>1. 通知 `setTimeoutAfter((state.startMs - now).coerceAtLeast(1000L))`<br>2. 精确闹钟 `RC_FLUID_STOP = 2003`（`armStopAlarm(state.startMs)` → `ACTION_FLUID_STOP` → `stop(context)`，突破前台服务通知忽略 `setTimeoutAfter` 及 Doze 冻结限制）<br>3. 服务内 `handler.postDelayed(stopRunnable, (state.startMs - now).coerceAtLeast(0L))` |
| **启动失败 OEM 降级** | `canPost(context)` 为 `false` 时返回 `false` | `ReminderReceiver` 调用 `ReminderFluidService.start(context, event)` 若返回 `false`（如后台起 FGS 被 ROM 拦截），**自动降级调用 `ReminderNotifier.show(...)` 发普通横幅通知** |

---

## 9. 系统恢复矩阵与 `dirty` 语义

| 触发场景 | 监听组件 / 入口 | 广播 Action / 生命周期回调 | 原生 / Dart 恢复动作 |
| --- | --- | --- | --- |
| **手机重启** | `ReminderRestoreReceiver` | `Intent.ACTION_BOOT_COMPLETED` | `ReminderScheduler(context).rescheduleFromStore()`（从 `ReminderStore` 重放 14 天 payload，不改 `dirty`） |
| **应用覆盖安装** | `ReminderRestoreReceiver` | `Intent.ACTION_MY_PACKAGE_REPLACED` | 同上（要求覆盖安装前后签名一致） |
| **手动修改系统时间 / 时区** | `ReminderRestoreReceiver` | `Intent.ACTION_TIME_SET` / `Intent.ACTION_TIMEZONE_CHANGED` | **先调 `store.markDirty()`**，再调 `rescheduleFromStore()` 让未过期闹钟落在新时间轴上 |
| **授予/变更精确闹钟权限** | `ReminderRestoreReceiver` | `AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED` | `rescheduleFromStore()`（将此前降级为 `setAndAllowWhileIdle` 的闹钟整体原地升级为 `setAlarmClock`） |
| **每日凌晨 00:05 自愈** | `ReminderDailyResyncReceiver` | `com.fangzi.qustschedule.action.DAILY_RESYNC` (`RC_DAILY_RESYNC = 2001`) | `rescheduleFromStore()` 幂等重排 + 续挂次日 00:05 一次性闹钟 + 滚动推进 10 天挂钟窗口 |
| **每次课程提醒响铃后** | `ReminderReceiver` | `com.fangzi.qustschedule.action.REMIND` | 从账本移除已响 `code`，并调用 `scheduler.topUpWindowFromStore()` 增量补齐新进入 10 天窗口的事件 |
| **App 回到前台** | `lib/main.dart` (`_AppShellState`) | `AppLifecycleListener(onShow: _onShown)` | 调用 `_reminders.syncNow(force: true)`，忽略 Dart 内存指纹强制下发最新 payload 并清除原生 `dirty` 标记 |
| **系统强制停止 (`force-stop`) / 一键清理** | 系统限制（无广播） | 所有闹钟与前台服务被系统内核强行清空，但 `SharedPreferences` 文件仍在 | 无法后台自愈；用户下次打开 App 时由冷启动或 `_onShown` 触发 `syncNow` 恢复 |
| **连续超过 14 天不打开 App** | 规划窗口自然耗尽 | 原生无校历与调课引擎，不能自行生成第 15 天以后的事件 | 第 11~14 天靠 00:05 自愈与触发补齐续命；第 15 天起无提醒，打开一次 App 即可重算未来 14 天 |

---

## 10. 权限诊断状态机与厂商设置跳转策略

### 10.1 权限卡片在两个页面中的分布（重要 UI 结构）

> **架构演进说明**：由于「忽略电池优化」「精确闹钟」「自启动」三项后台可靠性权限同时影响**课程提醒**与**桌面小组件**，它们已统一收拢到 **`SettingsPage` 的 `_ReminderAndWidgetCard`（「提醒与小组件」分区）**；而 **`ReminderPage` 的 `_PermissionsCard`** 仅保留提醒专属的 **「通知权限」**。两处均复用 `lib/widgets/reminder_permission_tile.dart` 的 `ReminderPermissionTile`。

| 所在页面与组件 | 权限项标题 | 状态判定 (`ok`) | 副标题文案 (`value`) | 按钮文案 (`actionLabel`) | 点击动作与原生跳转落点 |
| --- | --- | --- | --- | --- | --- |
| `ReminderPage` → `_PermissionsCard` | **通知权限** | `status.canNotify` (`notificationPermission && notificationsEnabled`) | `null`: `'查询中…'`<br>`true`: `'已允许 · 横幅与锁屏需手动开启'`<br>`false`: `'已禁止 · 无法收到任何提醒'` | `canNotify ? '去设置' : '去授权'` | - 未授权：`requestNotificationPermission()`（Android 13+ 弹窗）<br>- 已授权：`openNotificationSettings()` → `ACTION_APP_NOTIFICATION_SETTINGS`（失败退应用详情页） |
| `SettingsPage` → `_ReminderAndWidgetCard` | **忽略电池优化** | `status?.batteryOptOut ?? false` | `null`: `'查询中…'`<br>`true`: `'已忽略'`<br>`false`: `'受省电策略限制 · 后台可能被清理'` | `'去设置'` | 先弹 `showReminderGuideToast('请在「耗电管理」或「省电策略」中允许后台运行')`，再调 `openBatterySettings()` → **优先跳 `ACTION_APPLICATION_DETAILS_SETTINGS`（应用详情页）**，失败退 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` |
| `SettingsPage` → `_ReminderAndWidgetCard` | **精确闹钟** | `status?.exactAlarmAllowed ?? false` | `null`: `'查询中…'`<br>`true`: `'已允许'`<br>`false`: `'未允许 · 息屏时可能推迟数分钟'` | `'去设置'` | 先弹 `showReminderGuideToast('请开启「允许设置闹钟和提醒」以确保准时响铃')`，再调 `openExactAlarmSettings()` → `ACTION_REQUEST_SCHEDULE_EXACT_ALARM` (`package:...`) |
| `SettingsPage` → `_ReminderAndWidgetCard` | **自启动** | **恒为 `null`**（使用 `AppColors.warning` 提示色，绝不给假绿灯） | 恒为 `'该权限不可检测，需自行确认'` | `'去设置'` | 调 `openAutostartSettings()` 逐个探测 15 个厂商候选 Activity（见 10.2 节）：<br>- 返回 `true`：弹 Toast `'请在列表中找到本应用并允许自启动'`<br>- 返回 `false`：退回 `ACTION_SETTINGS` 系统设置主页，弹 Toast `'请在设置顶部搜索「自启动」，开启本应用开关'` |

### 10.2 国产 ROM 自启动候选 Activity 探测与 Android 11+ `<queries>` 契约

AOSP 无自启动查询或申请 API。`ReminderPermissions.autostartCandidates(context)` 按顺序探测以下 15 个厂商入口，并通过 `isCandidateLaunchable` 检查 `resolveInfo.activityInfo.exported == true` 及所需权限是否满足（防止 ColorOS 12+ 未导出页面抛 `SecurityException`）：

| 厂商 / 系统 | 候选 Action 或 Component (`packageName` / `className`) | `AndroidManifest.xml` `<queries>` 声明 |
| --- | --- | --- |
| **小米 / 红米 (MIUI / HyperOS)** | 1. `Intent("miui.intent.action.OP_AUTO_START")` + `CATEGORY_DEFAULT`<br>2. `com.miui.securitycenter` / `com.miui.permcenter.autostart.AutoStartManagementActivity` | `<intent>` `miui.intent.action.OP_AUTO_START` + `<package android:name="com.miui.securitycenter"/>` |
| **OPPO / realme / 一加 (ColorOS)** | 3. `com.coloros.safecenter` / `com.coloros.safecenter.permission.startup.StartupAppListActivity`<br>4. `com.coloros.safecenter` / `com.coloros.safecenter.startupapp.StartupAppListActivity`<br>5. `com.oppo.safe` / `com.oppo.safe.permission.startup.StartupAppListActivity`<br>6. `com.oneplus.security` / `com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity` | `<package>` 声明 `com.coloros.safecenter`, `com.oppo.safe`, `com.oneplus.security` |
| **vivo / iQOO (OriginOS)** | 7. `com.vivo.permissionmanager` / `com.vivo.permissionmanager.activity.BgStartUpManagerActivity`<br>8. `com.iqoo.secure` / `com.iqoo.secure.ui.phoneoptimize.BgStartUpManagerActivity` | `<package>` 声明 `com.vivo.permissionmanager`, `com.iqoo.secure` |
| **华为 / 荣耀 (EMUI / HarmonyOS / MagicOS)** | 9. `Intent("huawei.intent.action.HSM_BOOTAPP_MANAGER")`<br>10. `com.huawei.systemmanager` / `com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity`<br>11. `com.huawei.systemmanager` / `com.huawei.systemmanager.optimize.process.ProtectActivity`<br>12. `com.hihonor.systemmanager` / `com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity` | `<intent>` `huawei.intent.action.HSM_BOOTAPP_MANAGER` + `<package>` 声明 `com.huawei.systemmanager`, `com.hihonor.systemmanager` |
| **魅族 (Flyme)** | 13. `com.meizu.safe` / `com.meizu.safe.permission.SmartBGActivity`<br>14. `Intent("com.meizu.safe.permission.SHOW_APPSEC")` + `CATEGORY_DEFAULT` + extra `"packageName"` | `<intent>` `com.meizu.safe.permission.SHOW_APPSEC` + `<package android:name="com.meizu.safe"/>` |
| **三星 (国行 OneUI)** | 15. `com.samsung.android.sm_cn` / `com.samsung.android.sm.autorun.ui.AutoRunActivity` | `<package android:name="com.samsung.android.sm_cn"/>` |

---

## 11. 线程模型、单飞防抖与 UI 零卡顿架构

### 11.1 原生 `ReminderWorker` 与 `ReminderScheduler.LOCK`（适配 Flutter 3.29+ 主线程合并）

1. **为什么必须后台单线程**：Flutter 3.29+ 在 Android 平台合并了 UI 线程与 Platform 线程，MethodChannel 的 `onMethodCall` 直接运行在主渲染线程上。若在 `onMethodCall` 内同步读写 `SharedPreferences` 或批量调用 `AlarmManager.setAlarmClock` / `cancel`，每次 IPC 耗时数毫秒至数十毫秒，会直接造成切页与滑块松手掉帧。
2. **`ReminderWorker` 机制**：
   - 内部持有单线程线程池 `Executors.newSingleThreadExecutor`（线程名 `"qust-reminder-worker"`）。
   - `ReminderBridge` 的 `sync`、`cancel`、`status`、`testReminder` 全部通过 `ReminderWorker.execute { ... }` 异步执行，完成后通过 `mainHandler.post`（检查 `!disposed`）切回主线程调用 `result.success(...)` / `result.error(...)`。
   - `ReminderReceiver`、`ReminderDailyResyncReceiver`、`ReminderRestoreReceiver` 全部通过 `ReminderWorker.runBroadcastAsync(this, TAG) { ... }` 执行：在 `receiver.goAsync()` 保护下入队 `ReminderWorker`，并在 `finally` 块中100% 保证调用 `pending.finish()`，既防广播 10 秒 ANR 超时，又避免与 Flutter 桥接并发冲突。
3. **进程级锁 `ReminderScheduler.LOCK`**：`ReminderScheduler` 的 `sync()`、`cancelAll()`、`topUpWindowFromStore()`、`status()` 均用 `synchronized(LOCK)` 包裹，作为双重安全网保证账本与系统闹钟状态严格一致。

### 11.2 `ReminderService` 编排状态机（冷启动保护 + 300ms 防抖 + 单飞串行队列 + `_syncEpoch`）

```
AppModel 变更 (_onModelChanged)
  └── 重置 300ms _timer ──(到期)──► syncNow(force: false)
                                      │
                    ┌─────────────────┴─────────────────┐
                    ▼ (_syncInFlight != null)           ▼ (_syncInFlight == null)
           标记 _resyncQueued = true            启动 _runSyncLoop(initialForce)
           _resyncForceQueued |= force          循环执行 _syncOnce(force) 直到 !_resyncQueued
           直接返回当前在途 Future
```

- **冷启动保护**：`if (!model.preferencesLoaded) return null;`。在 `Preferences.open()` 完成前，`model.reminderEnabled` 为默认值 `false`；此时严禁向原生下发 `cancel()`，否则每次冷启动都会把用户已开启的闹钟全部清空。
- **取消幂等（`_cancelled`）**：当 `!model.reminderEnabled || model.schedule == null || model.termStart == null` 时，`buildPlan()` 返回 `null`，`_cancelIfNeeded()` 仅在 `!_cancelled` 时调用一次 `_gateway.cancel()` 并置 `_cancelled = true`，后续模型通知不再重复跨通道调用 `cancel`。
- **`_syncEpoch` 取消隔离**：`cancelAll()`（退出登录/切换账号时调用）立即递增 `_syncEpoch++` 并清空 `_resyncQueued`。正在 `_gateway.sync(...)` 等待原生返回的在途协程醒来后，检查到 `epoch != _syncEpoch` 直接丢弃结果返回，绝不回写 `_lastFingerprint` 或把 `_cancelled` 改回 `false`。
- **失败不记指纹**：只有 `result.ok == true` 时才写入 `_lastFingerprint = plan.fingerprint`；原生返回错误时保留 `_lastFingerprint` 不变，确保下次同步继续重试。

### 11.3 `ReminderPage` 三卡子树隔离与 `RouteSettledStateMixin` 切页零卡顿

1. **三棵自治组件子树（严禁整页 `setState` 或顶层 `ListenableBuilder`）**：
   - `_ReminderSettingsCard`（`StatefulWidget`）：内部仅监听 `widget.model.prefsNotifier`（流体云收起按钮局部监听 `statusNotifier`）。滑块拖动时 `onChanged` 仅更新自身 `_leadDraft` 局部 State（每帧仅重建约 30 个 Element），`onChangeEnd` 才清空 `_leadDraft` 并调用 `onCommitLead`。
   - `_PermissionsCard`（`StatelessWidget`）：仅通过 `ValueListenableBuilder` 监听 `_statusNotifier`。
   - `_DiagnosticsCard`（`StatelessWidget`）：仅通过 `ValueListenableBuilder` 监听 `_statusNotifier`（提醒形态行局部监听 `model.prefsNotifier`）；所有诊断条目一律使用轻量 `Text`（严禁使用 `SelectableText`）。
2. **`_queuedLeadMinutes` 串行合并**：
   - `ReminderPageState._run` 使用 `_running` 布尔锁（不进 `setState`）串行化原生操作。
   - 用户在 `_running == true` 期间再次拖动滑块松手或点击预设胶囊时，`_commitLead(minutes)` 将目标值写入 `_queuedLeadMinutes`，由当前 `_run` 的 `while (_queuedLeadMinutes != null && mounted)` 循环在收尾时自动合并落盘并执行 `syncNow(force: true)`，确保最后一次操作 100% 生效。
3. **`RouteSettledStateMixin` 并行状态查询与延迟提交**：
   - `ReminderPage` 与 `SettingsPage._ReminderAndWidgetCard` 均混入 `RouteSettledStateMixin`。
   - 首帧直接用 `widget.service.lastStatus` 初始化 `_statusNotifier`，实现首帧 0 等待同步渲染。
   - `initState()` 中立即调用 `unawaited(_refreshStatus(deferUntilSettled: true))`，让 Android `ReminderWorker` 后台查询与 260ms 路由推入动画**并行执行**。
   - 若查询在路由入场动画完成前返回（`!isRouteSettled`），结果暂存入 `_pendingStatus`（附带 `_pendingStatusEpoch`），**不在转场动画中途触发 `_statusNotifier` 重绘**；待入场动画达到 `completed` 触发 `onRouteSettled()` 时，立即调用 `_flushPendingStatus()` 提交局部更新。

---

## 12. 历史踩坑与严禁模式速查表（Pitfalls & Forbidden Patterns）

| 场景 / 模块 | 严禁写法（Don't） | 正确契约（Do） | 根因分析与守护测试 |
| --- | --- | --- | --- |
| **事件 ID 生成 (`reminderEventId`)** | 将 `leadMinutes` 或 `style` 拼入 `reminderEventId` 的哈希种子 | `reminderEventId` 只能由 `entryId\|yyyyMMdd\|startPeriod` 计算 | 改设置若导致 `event.id` 改变，派生的 `requestCode` 也会改变，极端情况下旧槽位闹钟残留会导致同一节课响两次。<br>守护：`test/reminder_planner_test.dart` |
| **全局指纹 (`reminderFingerprint`)** | 将 `generatedAtMs` 拼入 `reminderFingerprint`，或漏掉 `style` | 指纹必须排除 `generatedAtMs`，且必须包含 `v`、`leadMinutes`、`style`、`fluidUntilEnd` 及排序后的 `id:startMs:remindAtMs` | 含 `generatedAtMs` 会导致每次重算指纹都变；漏掉 `style` 会导致切换流体云/横幅时不触发原生重排。<br>守护：`test/reminder_planner_test.dart` |
| **提前量夹取 (`clampReminderLead`)** | 检查值不在 `[5, 10, 15, 20, 30]` 预设列表中就回退到默认 `10` 分钟 | 使用 `value.clamp(1, 60)` 保留 `1~60` 之间的任意整数 | 滑块允许用户拖出 `17` 分钟等任意整数，回退预设值会静默篡改用户设置。<br>守护：`test/reminder_planner_test.dart`, `test/timetable_test.dart` |
| **冷启动同步 (`ReminderService`)** | `AppModel` 初始化后立即根据默认 `reminderEnabled == false` 调用 `_gateway.cancel()` | 必须在 `_syncOnce` 与 `buildPlan` 开头检查 `if (!model.preferencesLoaded) return null;` | `Preferences.open()` 是异步文件读取，完成前 `reminderEnabled` 恒为 `false`，不拦住会在每次冷启动时清空用户已排好的全部闹钟。<br>守护：`test/reminder_service_test.dart` |
| **原生持久化 (`ReminderStore`)** | 使用 `SharedPreferences.Editor.apply()` 异步保存 payload 或 `alarm_codes` | 所有关键写操作一律使用 `.commit()` 同步落盘 | 广播 `goAsync()` `finish()` 后进程可能立即被系统冻结，`apply()` 未来得及写盘会导致账本与实际系统闹钟脱节。 |
| **同槽位闹钟更新 (`ReminderScheduler.arm`)** | 直接调用 `setAlarmClock` 覆盖同 `requestCode` 的旧闹钟而不先 `cancel` | 在 `arm()` 与 `scheduleTest()` 内必须先 `cancelPendingAlarm`（`manager.cancel(op)` + `op.cancel()`），再重新构建 `PendingIntent` 并 `setAlarmClock` | 部分国产 ROM 对同 `requestCode` 的 `setAlarmClock` 原地覆盖会缓存旧触发时刻，导致改了提前量后仍在旧时刻响铃。 |
| **通知渠道创建时机 (`ReminderNotifier`)** | App 启动时无条件调用 `createNotificationChannel` | 必须在 `ReminderPermissions.hasNotificationPermission(context) == true` 之后才注册渠道（`ensureHighAlertChannel`） | ColorOS / HyperOS 在未授予通知权限时预建渠道，系统会将该渠道的横幅/声音权限永久锁定为关闭，用户后续点允许通知也弹不出横幅。 |
| **横幅与流体云通知 ID** | 横幅通知与流体云前台服务共用同一个通知 ID `2000` | 横幅固定用 `NOTIFY_ID = 2000`，流体云固定用 `FLUID_NOTIFY_ID = 2001`，且启动一方时显式关闭另一方 | 若共用 `2000`，当用户在横幅通知展示期间打开 App 触发 `sync`（`style != fluid` 调用 `ReminderFluidService.stop`）时，会误把正在展示的横幅通知一并撤掉。 |
| **流体云到点收起 (`ReminderFluidService`)** | 仅依赖通知的 `setTimeoutAfter` 来自动关闭流体云前台服务通知 | 必须保留 `RC_FLUID_STOP = 2003` 精确闹钟 + `handler.postDelayed(stopRunnable)` + `setTimeoutAfter` 三重保障 | 实测 Android 17 / ColorOS 下，`startForeground()` 提交的通知被系统打上 `FOREGROUND_SERVICE \| NO_CLEAR` 标记，`setTimeoutAfter` 被系统完全忽略（+45s 仍不消失），必须由闹钟唤醒停服务。 |
| **流体云通知样式 (`ReminderFluidRenderer`)** | 给流体云通知设置 `ProgressStyle` 或 `BigTextStyle`，或用 15s Timer 轮询更新通知 | 只设 `ContentTitle` + `SubText` + `ShortCriticalText` + 系统 `Chronometer` + `FOREGROUND_SERVICE_IMMEDIATE` | `ProgressStyle` 进度条与 ColorOS 胶囊自绘圆环重叠混色；`BigTextStyle` 不被流体云卡片模板识别；轮询重发通知浪费 CPU 且导致胶囊闪烁。 |
| **电池优化设置跳转 (`ReminderPermissions`)** | 跳 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS`（数百个 App 的总列表）或直接弹 `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` | 优先跳 `ACTION_APPLICATION_DETAILS_SETTINGS`（本应用详情页） | ColorOS Athena / HyperOS PowerKeeper 等私有后台查杀开关均挂在「应用详情 → 耗电管理」中；用户在应用详情页开启「完全允许后台行为」会自动同步放行 AOSP 电池优化白名单。 |
| **测试提醒闹钟 (`RC_TEST = 2002`)** | 将测试提醒写入 `ReminderStore.alarmCodes()` 账本 | `RC_TEST = 2002` 独立于账本之外 | 若写入账本，用户点「立即重排」或回到前台触发 `sync` 时会把还没响的测试提醒当成多余闹钟撤掉。<br>守护：`test/reminder_service_test.dart` |
| **提醒页渲染性能 (`ReminderPage`)** | 在 `Scaffold` 顶层套 `ListenableBuilder(listenable: model)`，或诊断项用 `SelectableText`，或滑块 `onChanged` 直接调 `setReminderLeadMinutes` | 三卡独立监听（`prefsNotifier` / `_statusNotifier`）、滑块拖动只改 `_leadDraft`、`onChangeEnd` 才落盘、诊断项用普通 `Text`、入场状态查询带 `deferUntilSettled: true` | 顶层监听或 `onChanged` 落盘会在拖动滑块时每帧重建全页 1500+ Widget 并触发数十次原生账本差分；7 个 `SelectableText` 会造成约 14ms 首帧膨胀。<br>守护：`test/widget_test.dart` |

---

## 13. 自动化测试矩阵与真机实测手册

### 13.1 自动化测试覆盖矩阵（`qustschedule/test/`）

> 执行命令（必须在 `qustschedule/` 内层仓库目录下执行）：
> `flutter test test/reminder_planner_test.dart test/reminder_service_test.dart test/timetable_test.dart test/widget_test.dart`

| 测试文件 | 核心被测对象 | 覆盖的不变量与边界用例 |
| --- | --- | --- |
| `test/reminder_planner_test.dart` | `planCourseReminders`, `clampReminderLead`, `reminderEventId`, `reminderFingerprint`, `ReminderPlan.toPayloadJson` | 1. 提前量（1/10/30 分钟）换算、`endMs` 取末节下课时刻、`roomOnly` 裁剪校区前缀只留房间号<br>2. `clampReminderLead` 夹取 `1..60` 且保留任意中间整数（如 `7`, `43`）<br>3. 按事件当天切换春夏/秋冬作息表；节次超出作息表时 `skipped++` 不抛异常<br>4. 单双周过滤、`weeks` 为空默认每周、超出 `maxWeek` 跳过、调课挪动与被顶掉的原课不再提醒<br>5. 已过点或提前量推到过去的事件不补发；超 `maxEvents` 截断并标记 `truncated = true`；跨月跨年推进<br>6. 相同课表不同 `generatedAtMs` 指纹一致；改提前量/改形态/改课表指纹必变；`event.id` 跨设置稳定 |
| `test/reminder_service_test.dart` | `ReminderService` + `FakeReminderGateway` | 1. 开启且有课表时下发一次；指纹未变不重复下发；`syncNow(force: true)` 强制重排<br>2. 改提前量或切换 `ReminderStyle.fluid` 更新指纹并重新下发<br>3. 原生返回 `ReminderSyncResult.failure` 时不记指纹，下次调用继续重试<br>4. 在途 `syncNow` 期间（`syncGate` 挂起）修改提前量，串行跟进重排确保最新提前量与指纹落盘<br>5. 关闭开关或无课表时取消提醒，且重复同步只调一次原生 `cancel()`（`_cancelled` 幂等）；`cancelAll()` 后再同步可重新下发<br>6. 冷启动保护：`model.preferencesLoaded == false` 时不动作（不误调 `cancel`）<br>7. 300ms 防抖合并连续模型通知；`previewReminder`、`sendTestReminder`、`stopFluid` 及 4 项权限跳转转发并刷新 `lastStatus` |
| `test/support/fake_reminder_gateway.dart` | `FakeReminderGateway` | 离线测试桩：记录 `syncedPayloads`, `testRequests`, `previewRequests`, `toasts` 及各方法调用计数，支持 `syncGate` 模拟在途异步挂起与 `syncResult` 失败注入 |
| `test/timetable_test.dart` | `Preferences` 提醒字段持久化 | 默认值（`reminderEnabled: false`, `reminderLeadMinutes: 10`, `reminderStyle: banner`）、旧 schema 缺字段向前兼容、未知形态（如 `"capsule"`）回退 `banner`、提前量 `1..60` 夹取与文件落盘往返 |
| `test/widget_test.dart` | `SettingsPage` + `ReminderPage` | Android 平台入口显隐、滑块拖动只改草稿不落盘、预设胶囊点击、流体云开关双向切换与自动 `stopFluid`、诊断卡片展示、预览与 5s/60s 测试提醒按钮、生命周期 `resumed` 状态刷新、自启动项恒显示需手动确认 |

### 13.2 真机实测与 Logcat / Dumpsys 诊断命令（PLG110 / ColorOS / Android 17 基准）

```powershell
$adb = 'D:\sdks\android-sdk\platform-tools\adb.exe'
# 1. 实时监控提醒全链路日志
& $adb logcat -s ReminderWorker:V ReminderBridge:V ReminderScheduler:V ReminderReceiver:V ReminderFluid:V ReminderDailyResync:V ReminderRestore:V

# 2. 核查系统 AlarmManager 中本应用的闹钟槽位、触发时刻与精确标志
& $adb shell dumpsys alarm | Select-String -Pattern "com.fangzi.qustschedule|FLUID_STOP|DAILY_RESYNC|TEST_REMIND" -Context 2,4

# 3. 模拟进入/退出深度 Doze 模式验证 setAlarmClock 穿透能力
& $adb shell dumpsys deviceidle force-idle
& $adb shell dumpsys deviceidle unforce
```

**真机验收关键指标**：
1. **准点性**：提醒页点「5 秒后测试提醒」或「1 分钟后测试提醒」后立即灭屏并 `force-idle`，Logcat 输出 `ReminderReceiver: fired ... deltaMs=...`，要求连续 3 次 `|deltaMs| <= 5000ms`。
2. **流体云生命周期**：开启「流体云卡片」→ 点「立即显示通知」应立即出现常驻胶囊且秒级倒计时；`dumpsys alarm` 可见 `RC=2003` (`ACTION_FLUID_STOP`) 挂在 `startMs`；到达 `startMs` 或点「立即收起卡片」或切回横幅时，卡片立刻消失且 `2003` 闹钟被撤销无残留。
3. **跨进程状态刷新**：在设置页或提醒页点击「去设置 / 去授权」跳转到系统设置修改权限后返回 App，`WidgetsBindingObserver.didChangeAppLifecycleState(resumed)` 自动触发 `_refreshStatus()`，权限状态立即变绿，无需重进页面。
