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

            // 流体云"到点收起"的兜底闹钟：进程被冻结过也会被这条唤醒。
            ACTION_FLUID_STOP -> {
                ReminderFluidService.stop(context)
                Log.i(TAG, "fluid card stopped by end alarm")
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
        val fingerprint = intent.getStringExtra(EXTRA_FINGERPRINT)
        val expected = intent.getLongExtra(EXTRA_REMIND_AT_MS, 0L)
        val code = intent.getIntExtra(EXTRA_REQUEST_CODE, 0)
        if (eventId.isNullOrEmpty() || fingerprint.isNullOrEmpty() ||
            expected <= 0L
        ) {
            Log.w(TAG, "malformed alarm, ignored")
            return
        }

        val store = ReminderStore(context)
        val currentFingerprint = store.fingerprint()
        if (currentFingerprint.isEmpty() || currentFingerprint != fingerprint) {
            Log.w(TAG, "stale alarm id=$eventId, reschedule current payload")
            runCatching { ReminderScheduler(context).rescheduleFromStore() }
            return
        }

        val payload = store.loadPayload()
        if (payload == null) {
            Log.w(TAG, "payload missing while firing id=$eventId")
            return
        }
        val event = payload.events.firstOrNull { it.id == eventId }
        if (event == null || event.remindAtMs != expected) {
            Log.w(TAG, "alarm does not match payload id=$eventId")
            return
        }

        val actual = System.currentTimeMillis()
        val fluid = payload.style == ReminderPayload.STYLE_FLUID
        if (fluid) {
            ReminderFluidService.start(
                context,
                event,
                untilEnd = payload.fluidUntilEnd,
            )
        } else {
            ReminderNotifier.show(context, event, payload.leadMinutes)
        }
        if (code != 0) store.removeAlarmCode(code)
        Log.i(
            TAG,
            "fired id=$eventId style=${payload.style} expected=$expected " +
                "actual=$actual deltaMs=${actual - expected} " +
                "fluid=$fluid posted=${!fluid}",
        )
    }

    /** 诊断页"测试提醒"：不读 payload，直接发一条示例。 */
    private fun handleTest(context: Context, intent: Intent) {
        val style = intent.getStringExtra(EXTRA_TEST_STYLE)
            ?: ReminderPayload.STYLE_BANNER
        val event = ReminderSamples.event(TEST_LEAD_MINUTES)
        if (style == ReminderPayload.STYLE_FLUID) {
            // 测试卡片也跟随用户的"显示到下课"设置，否则预览语义和正式不一致。
            val untilEnd = runCatching {
                ReminderStore(context).loadPayload()?.fluidUntilEnd
            }.getOrNull() ?: false
            ReminderFluidService.start(context, event, untilEnd = untilEnd)
        } else if (!ReminderNotifier.show(context, event, TEST_LEAD_MINUTES)) {
            Log.w(TAG, "test reminder not posted: notification unavailable")
        }
        Log.i(TAG, "test reminder fired style=$style")
    }

    companion object {
        const val TAG = "ReminderReceiver"
        const val ACTION_REMIND = "com.fangzi.qustschedule.action.REMIND"
        const val ACTION_TEST = "com.fangzi.qustschedule.action.TEST_REMIND"
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
