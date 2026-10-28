package com.fangzi.qustschedule.reminder

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.util.Log
import java.util.Calendar

/** `sync` 的结果，直接映射给 Dart 的诊断页。 */
data class ReminderSyncOutcome(
    val scheduled: Int,
    val nextTriggerMs: Long?,
    val coverageEndMs: Long?,
    val style: String,
    val exactAllowed: Boolean,
)

/**
 * 排程器：把 payload 里的绝对毫秒挂成系统闹钟。
 *
 * 与参考实现（sleepy）保持同一套约定：
 *  - **只有两级 API**：`setExactAndAllowWhileIdle`，无精确闹钟权限时降到
 *    `setAndAllowWhileIdle`（不精确但能穿透 Doze）。不用 `setAlarmClock`
 *    （状态栏常驻闹钟图标），也不用 `setWindow`（10 分钟窗口对 5 分钟提前量
 *    毫无意义）。
 *  - **账本差分撤销**：只撤"上次排过但现在不需要"的 code，仍需要的槽位原地
 *    覆盖，不制造"先撤再排"的空窗。
 *  - **每日 00:05 自愈重排**：一次性闹钟链，每次触发后重挂次日，用于修复被
 *    系统/OEM 悄悄丢掉或改晚的闹钟（不新增计划，只重放 payload）。
 *  - 同一事件 requestCode 稳定（由事件 id 派生），重复排程即覆盖。
 */
class ReminderScheduler(context: Context) {

    private val appContext = context.applicationContext
    private val store = ReminderStore(appContext)

    /**
     * 重排全部提醒。
     *
     * @param fromFlutter true = Dart 按当前时钟重新规划的结果，可清 dirty；
     *   false = 开机/每日自愈恢复旧 payload，用户的时钟可能已变，dirty 留给
     *   下次 App 打开处理。
     */
    fun sync(
        payload: ReminderPayload,
        rawJson: String,
        fromFlutter: Boolean,
    ): ReminderSyncOutcome = synchronized(LOCK) {
        ReminderNotifier.ensureChannel(appContext)
        ReminderFluidRenderer.ensureChannel(appContext)
        store.savePayload(rawJson, payload)
        if (fromFlutter) store.clearDirty()

        // 形态切回横幅，或 payload 里已没有正在上的课：流体云立刻收摊。
        if (payload.style != ReminderPayload.STYLE_FLUID) {
            ReminderFluidService.stop(appContext)
        }

        val now = System.currentTimeMillis()
        val previous = store.alarmCodes().toSet()
        val desired = LinkedHashMap<Int, ReminderEvent>()
        val windowCodes = HashSet<Int>()
        for (event in payload.events) {
            val code = requestCodeFor(event.id)
            windowCodes.add(code)
            if (event.remindAtMs > now + MIN_LEAD_MS) desired[code] = event
        }

        // 账本差分：上次排过但这次不需要的（含换表/删课/窗口外残留）全部撤掉。
        for (code in (previous + windowCodes) - desired.keys) cancel(code)

        val armed = LinkedHashSet<Int>()
        var scheduled = 0
        var nextTriggerMs: Long? = null
        var coverageEndMs: Long? = null
        for ((code, event) in desired) {
            if (!arm(code, event, payload.fingerprint)) {
                Log.e(TAG, "drop event ${event.id}: cannot schedule")
                continue
            }
            armed.add(code)
            scheduled++
            if (nextTriggerMs == null) nextTriggerMs = event.remindAtMs
            coverageEndMs = event.startMs
        }
        store.setAlarmCodes(armed)
        armDailyResync()

        val exactAllowed = ReminderPermissions.canScheduleExactAlarms(appContext)
        Log.i(
            TAG,
            "sync scheduled=$scheduled/${payload.events.size} " +
                "style=${payload.style} exact=$exactAllowed " +
                "lead=${payload.leadMinutes} fp=${payload.fingerprint}",
        )
        ReminderSyncOutcome(
            scheduled = scheduled,
            nextTriggerMs = nextTriggerMs,
            coverageEndMs = coverageEndMs,
            style = payload.style,
            exactAllowed = exactAllowed,
        )
    }

    /** 取消全部（关闭提醒 / 退出登录）：闹钟、账本、流体云、payload 一起清。 */
    fun cancelAll() {
        synchronized(LOCK) {
            for (code in store.alarmCodes()) cancel(code)
            store.clearAlarmCodes()
            cancelDailyResync()
            ReminderFluidService.stop(appContext)
            store.clear()
        }
        Log.i(TAG, "cancelAll: alarms, fluid card and payload cleared")
    }

    /** 只用已保存的 payload 重排（开机、覆盖安装、每日 00:05 自愈）。 */
    fun rescheduleFromStore(): ReminderSyncOutcome? {
        val json = store.loadPayloadJson()
        if (json == null) {
            Log.i(TAG, "reschedule skipped: no payload")
            return null
        }
        val payload = store.loadPayload()
        if (payload == null) {
            Log.w(TAG, "reschedule skipped: payload invalid")
            return null
        }
        return sync(payload, json, fromFlutter = false)
    }

    /** 诊断页"一分钟后测试提醒"：走真实闹钟链路，触发时发示例通知。 */
    fun scheduleTest(delaySeconds: Int, style: String): Long? {
        val delay = delaySeconds.coerceIn(MIN_TEST_SECONDS, MAX_TEST_SECONDS)
        val epoch = System.currentTimeMillis() + delay * 1000L
        val intent = Intent(appContext, ReminderReceiver::class.java).apply {
            action = ReminderReceiver.ACTION_TEST
            putExtra(ReminderReceiver.EXTRA_TEST_STYLE, style)
        }
        val operation = PendingIntent.getBroadcast(
            appContext,
            RC_TEST,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val manager = appContext.getSystemService(AlarmManager::class.java)
            ?: return null
        val exact = ReminderPermissions.canScheduleExactAlarms(appContext)
        return try {
            if (exact) {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    epoch,
                    operation,
                )
            } else {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    epoch,
                    operation,
                )
            }
            Log.i(TAG, "test reminder in ${delay}s style=$style")
            epoch
        } catch (error: SecurityException) {
            Log.e(TAG, "test reminder denied", error)
            null
        }
    }

    /** 当前状态（诊断页读它，不进 build 热路径）。 */
    fun status(): Map<String, Any?> {
        val payload = store.loadPayload()
        val now = System.currentTimeMillis()
        val next = payload?.events
            ?.filter { it.remindAtMs > now }
            ?.minOfOrNull { it.remindAtMs }
        val payloadAt = store.payloadAtMs()
        return mapOf(
            "notificationPermission" to
                ReminderPermissions.hasNotificationPermission(appContext),
            "notificationsEnabled" to
                ReminderPermissions.notificationsEnabled(appContext),
            "exactAlarmAllowed" to
                ReminderPermissions.canScheduleExactAlarms(appContext),
            "batteryOptimizationIgnored" to
                ReminderPermissions.isIgnoringBatteryOptimizations(appContext),
            // 自启动：只能给出"开机广播是否在位"＋"本机有没有可跳的厂商页"，
            // 真正的开关状态系统不给读（见 ReminderPermissions）。
            "autoStartDeclared" to
                ReminderPermissions.hasBootBroadcastPermission(appContext),
            "autoStartVendorPage" to
                ReminderPermissions.hasAutostartSettings(appContext),
            "scheduled" to store.alarmCodes().size,
            "nextTriggerMs" to next,
            "payloadAtMs" to if (payloadAt > 0) payloadAt else null,
            "fingerprint" to store.fingerprint(),
            "style" to store.style(),
            "dirty" to store.isDirty(),
            "fluidCasting" to ReminderFluidService.casting,
        )
    }

    // -------------------------------------------------------------------------
    // 内部
    // -------------------------------------------------------------------------

    private fun arm(
        code: Int,
        event: ReminderEvent,
        fingerprint: String,
    ): Boolean {
        val manager = appContext.getSystemService(AlarmManager::class.java)
            ?: return false
        val operation = pendingIntent(code, event, fingerprint)
        var exact = ReminderPermissions.canScheduleExactAlarms(appContext)
        while (true) {
            try {
                if (exact) {
                    manager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        event.remindAtMs,
                        operation,
                    )
                } else {
                    manager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        event.remindAtMs,
                        operation,
                    )
                }
                return true
            } catch (error: SecurityException) {
                if (!exact) {
                    Log.e(TAG, "arm denied code=$code", error)
                    return false
                }
                // 权限刚被收回：降级重试一次，绝不崩溃。
                Log.w(TAG, "exact denied, fallback to allow-while-idle")
                exact = false
            }
        }
    }

    private fun cancel(code: Int) {
        val manager = appContext.getSystemService(AlarmManager::class.java)
            ?: return
        val intent = Intent(appContext, ReminderReceiver::class.java).apply {
            action = ReminderReceiver.ACTION_REMIND
        }
        val operation = PendingIntent.getBroadcast(
            appContext,
            code,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        manager.cancel(operation)
        operation.cancel()
    }

    /** 每天 00:05 重挂一次自愈闹钟（一次性链，触发后再挂次日）。 */
    private fun armDailyResync() {
        val manager = appContext.getSystemService(AlarmManager::class.java)
            ?: return
        cancelDailyResync()
        val target = Calendar.getInstance().apply {
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 5)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
            if (timeInMillis <= System.currentTimeMillis()) {
                add(Calendar.DAY_OF_YEAR, 1)
            }
        }
        val operation = PendingIntent.getBroadcast(
            appContext,
            RC_DAILY_RESYNC,
            dailyResyncIntent(),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val exact = ReminderPermissions.canScheduleExactAlarms(appContext)
        try {
            if (exact) {
                manager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    target.timeInMillis,
                    operation,
                )
            } else {
                manager.setAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    target.timeInMillis,
                    operation,
                )
            }
        } catch (error: SecurityException) {
            Log.w(TAG, "daily resync arm denied", error)
        }
    }

    private fun cancelDailyResync() {
        val manager = appContext.getSystemService(AlarmManager::class.java)
            ?: return
        val operation = PendingIntent.getBroadcast(
            appContext,
            RC_DAILY_RESYNC,
            dailyResyncIntent(),
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        manager.cancel(operation)
        operation.cancel()
    }

    private fun dailyResyncIntent(): Intent =
        Intent(appContext, ReminderDailyResyncReceiver::class.java).apply {
            action = ReminderDailyResyncReceiver.ACTION_RESYNC
        }

    private fun pendingIntent(
        code: Int,
        event: ReminderEvent,
        fingerprint: String,
    ): PendingIntent {
        val intent = Intent(appContext, ReminderReceiver::class.java).apply {
            action = ReminderReceiver.ACTION_REMIND
            putExtra(ReminderReceiver.EXTRA_EVENT_ID, event.id)
            putExtra(ReminderReceiver.EXTRA_FINGERPRINT, fingerprint)
            putExtra(ReminderReceiver.EXTRA_REMIND_AT_MS, event.remindAtMs)
            putExtra(ReminderReceiver.EXTRA_REQUEST_CODE, code)
        }
        return PendingIntent.getBroadcast(
            appContext,
            code,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    /** 稳定 requestCode：同一事件永远落在同一槽位，重排即覆盖。 */
    private fun requestCodeFor(eventId: String): Int {
        val code = eventId.hashCode() and 0x7fffffff
        return if (code == 0) 1 else code
    }

    companion object {
        const val TAG = "ReminderScheduler"

        /** 进程级锁：桥接线程与各 Receiver 是不同实例，必须串行化排程。 */
        private val LOCK = Any()

        /** 剩余不足一秒的事件直接跳过，避免刚排上就触发。 */
        private const val MIN_LEAD_MS = 1000L

        private const val RC_DAILY_RESYNC = 2001
        private const val RC_TEST = 2002
        private const val MIN_TEST_SECONDS = 5
        private const val MAX_TEST_SECONDS = 3600
    }
}
