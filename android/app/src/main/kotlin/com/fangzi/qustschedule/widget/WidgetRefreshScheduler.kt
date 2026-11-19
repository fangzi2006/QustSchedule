package com.fangzi.qustschedule.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.fangzi.qustschedule.reminder.ReminderPermissions

/**
 * 桌面小组件单节点精准闹钟调度器：
 * 仅在下一节课/考试的开始或结束时刻、及次日 00:01 挂载唯一轻量闹钟（RequestCode 3001），
 * 桌面上无活跃小组件时主动取消，保持近零后台功耗。
 */
internal object WidgetRefreshScheduler {

    const val ACTION_REFRESH_WIDGETS = "com.fangzi.qustschedule.widget.ACTION_REFRESH_WIDGETS"
    private const val RC_WIDGET_REFRESH = 3001

    fun scheduleNext(context: Context, snapshot: WidgetSnapshotModel?) {
        val appContext = context.applicationContext
        val alarmManager = appContext.getSystemService(AlarmManager::class.java) ?: return
        val nowMs = System.currentTimeMillis()
        val nextAtMs = WidgetContentResolver.computeNextRefreshAtMs(snapshot, nowMs)
        val pending = buildPendingIntent(appContext)

        alarmManager.cancel(pending)
        if (ReminderPermissions.canScheduleExactAlarms(appContext)) {
            try {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    nextAtMs,
                    pending,
                )
                return
            } catch (_: SecurityException) {
                // 极端时序下权限被撤，平稳降级到非精确唤醒。
            }
        }
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, nextAtMs, pending)
    }

    fun cancel(context: Context) {
        val appContext = context.applicationContext
        val alarmManager = appContext.getSystemService(AlarmManager::class.java) ?: return
        alarmManager.cancel(buildPendingIntent(appContext))
    }

    private fun buildPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, WidgetRefreshReceiver::class.java).apply {
            action = ACTION_REFRESH_WIDGETS
        }
        return PendingIntent.getBroadcast(
            context,
            RC_WIDGET_REFRESH,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
