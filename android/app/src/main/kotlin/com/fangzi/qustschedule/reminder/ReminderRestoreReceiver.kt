package com.fangzi.qustschedule.reminder

import android.app.AlarmManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * 闹钟"续命"：重启、覆盖安装、时间/时区变化、精确闹钟权限刚被授予。
 *
 * 这些场景下 Flutter 进程根本不存在，所以只能靠原生按已保存的 payload 重排：
 *  - 重启 / 覆盖安装：系统清空了全部闹钟，payload 还在，直接重排；
 *  - 时间或时区被改：绝对毫秒已与"第几周"错位，先重排让闹钟落在新时间上，
 *    同时打 dirty 标记，等下次 App 打开由 Dart 用真实校历重算一遍；
 *  - force-stop / 一键清理：系统连 payload 一起保留但闹钟没了，且不会再
 *    发任何广播——只能等用户下次打开 App（那时 Dart 会强制同步）。
 */
class ReminderRestoreReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        val store = ReminderStore(context)
        when (action) {
            Intent.ACTION_BOOT_COMPLETED,
            Intent.ACTION_MY_PACKAGE_REPLACED -> {
                val outcome = ReminderScheduler(context).rescheduleFromStore()
                Log.i(TAG, "restore($action) scheduled=${outcome?.scheduled}")
            }

            Intent.ACTION_TIME_CHANGED,
            Intent.ACTION_TIMEZONE_CHANGED -> {
                store.markDirty()
                val outcome = ReminderScheduler(context).rescheduleFromStore()
                Log.i(TAG, "restore($action) scheduled=${outcome?.scheduled}")
            }

            AlarmManager.ACTION_SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED -> {
                // 用户刚把精确闹钟权限打开：把降级过的排程整体升回精确。
                val outcome = ReminderScheduler(context).rescheduleFromStore()
                Log.i(TAG, "exact alarm granted, rescheduled=${outcome?.scheduled}")
            }
        }
    }

    companion object {
        const val TAG = "ReminderRestore"
    }
}
