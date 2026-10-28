package com.fangzi.qustschedule.reminder

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 每天 00:05 的自愈重排。
 *
 * 它**不重新规划课表**（原生没有校历），只把已保存的 payload 重新挂一遍：
 * 系统或 OEM 在某些清理/休眠后会把闹钟改晚或丢掉，靠这次幂等重排拉回正轨。
 * 重排成功后 [ReminderScheduler.armDailyResync] 会再挂次日的闹钟，形成一条
 * 一次性闹钟链——比 `setRepeating` 更抗 Doze 漂移。
 */
class ReminderDailyResyncReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != ACTION_RESYNC) return
        val pending = goAsync()
        try {
            val outcome = ReminderScheduler(context).rescheduleFromStore()
            Log.i(TAG, "daily resync scheduled=${outcome?.scheduled}")
        } catch (error: Exception) {
            Log.e(TAG, "daily resync failed", error)
        } finally {
            pending.finish()
        }
    }

    companion object {
        const val TAG = "ReminderDailyResync"
        const val ACTION_RESYNC = "com.fangzi.qustschedule.action.DAILY_RESYNC"
    }
}
