package com.fangzi.qustschedule.reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 闹钟到点：先核对"这条闹钟还属于当前课表吗"，再按形态发通知/起卡片。
 *
 * 校验三件套（指纹 + 事件 id + 时刻）缺一不可：闹钟是按绝对毫秒挂的，改课表、
 * 改提前量、改时区之后旧闹钟仍可能在系统里。对不上的直接丢弃并按当前 payload
 * 重排——宁可少响一条，也不要按旧课表误响。
 *
 * 耗时部分用 `goAsync()` 包住：广播默认只有 10 秒，起前台服务/重排都可能超时，
 * 一旦被系统判定超时，进程会被直接冻结，后面的闹钟全丢。
 */
class ReminderReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        when (intent.action) {
            ACTION_TEST -> {
                handleTest(context, intent)
                return
            }

            // 开课准时消失闹钟、或流体云到点收起的兜底闹钟
            ACTION_DISMISS,
            ACTION_FLUID_STOP -> {
                context.getSystemService(android.app.NotificationManager::class.java)
                    ?.cancel(ReminderNotifier.NOTIFY_ID)
                ReminderFluidService.stop(context)
                Log.i(TAG, "reminder dismissed by alarm action=${intent.action}")
                return
            }

            ACTION_REMIND -> Unit

            else -> return
        }

        val pending = goAsync()
        try {
            handleRemind(context, intent)
        } catch (error: Exception) {
            Log.e(TAG, "fire failed", error)
        } finally {
            pending.finish()
        }
    }

    private fun handleRemind(context: Context, intent: Intent) {
        val eventId = intent.getStringExtra(EXTRA_EVENT_ID)
        val expected = intent.getLongExtra(EXTRA_REMIND_AT_MS, 0L)
        val code = intent.getIntExtra(EXTRA_REQUEST_CODE, 0)
        if (eventId.isNullOrEmpty() || expected <= 0L) {
            Log.w(TAG, "malformed alarm, ignored")
            return
        }

        val store = ReminderStore(context)
        val payload = store.loadPayload()
        if (payload == null) {
            Log.w(TAG, "payload missing while firing id=$eventId")
            return
        }
        val event = payload.events.firstOrNull { it.id == eventId }
        if (event == null) {
            Log.w(TAG, "event $eventId no longer in payload, ignored")
            return
        }
        if (kotlin.math.abs(event.remindAtMs - expected) > 1000L) {
            Log.w(TAG, "alarm time $expected does not match current event time ${event.remindAtMs}")
            return
        }

        val actual = System.currentTimeMillis()
        val fluid = payload.style == ReminderPayload.STYLE_FLUID
        var posted = false
        if (fluid) {
            val started = ReminderFluidService.start(
                context,
                event,
            )
            if (!started) {
                Log.w(TAG, "fluid service start rejected, falling back to banner notification")
                posted = ReminderNotifier.show(context, event, payload.leadMinutes)
            } else {
                posted = true
            }
        } else {
            posted = ReminderNotifier.show(context, event, payload.leadMinutes)
        }
        if (code != 0) store.removeAlarmCode(code)
        Log.i(
            TAG,
            "fired id=$eventId style=${payload.style} expected=$expected " +
                "actual=$actual deltaMs=${actual - expected} " +
                "fluid=$fluid posted=$posted",
        )
    }

    /** 诊断页"测试提醒"：不读 payload，直接发一条示例。 */
    private fun handleTest(context: Context, intent: Intent) {
        val style = intent.getStringExtra(EXTRA_TEST_STYLE)
            ?: ReminderPayload.STYLE_BANNER
        val event = ReminderSamples.event(TEST_LEAD_MINUTES)
        if (style == ReminderPayload.STYLE_FLUID) {
            val started = ReminderFluidService.start(context, event)
            if (!started) {
                ReminderNotifier.show(context, event, TEST_LEAD_MINUTES)
            }
        } else if (!ReminderNotifier.show(context, event, TEST_LEAD_MINUTES)) {
            Log.w(TAG, "test reminder not posted: notification unavailable")
        }
        Log.i(TAG, "test reminder fired style=$style")
    }

    companion object {
        const val TAG = "ReminderReceiver"
        const val ACTION_REMIND = "com.fangzi.qustschedule.action.REMIND"
        const val ACTION_TEST = "com.fangzi.qustschedule.action.TEST_REMIND"
        const val ACTION_DISMISS = "com.fangzi.qustschedule.action.DISMISS"
        const val ACTION_FLUID_STOP = "com.fangzi.qustschedule.action.FLUID_STOP"
        const val EXTRA_EVENT_ID = "event_id"
        const val EXTRA_FINGERPRINT = "fingerprint"
        const val EXTRA_REMIND_AT_MS = "remind_at_ms"
        const val EXTRA_REQUEST_CODE = "request_code"
        const val EXTRA_TEST_STYLE = "test_style"

        /** 测试提醒的展示用提前量：与正式排程无关，只影响文案。 */
        private const val TEST_LEAD_MINUTES = 10
    }
}
