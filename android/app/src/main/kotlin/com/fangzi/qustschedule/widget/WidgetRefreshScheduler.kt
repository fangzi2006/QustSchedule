package com.fangzi.qustschedule.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import com.fangzi.qustschedule.reminder.ReminderPermissions

/**
 * 桌面小组件单节点精准闹钟调度器：
 * 仅在活跃小组件关心的下一课程/考试节点或次日 00:01 挂载唯一轻量闹钟（RequestCode 3001），
 * 桌面上无活跃小组件时主动取消，保持近零后台功耗。
 */
internal object WidgetRefreshScheduler {

    const val ACTION_REFRESH_WIDGETS = "com.fangzi.qustschedule.widget.ACTION_REFRESH_WIDGETS"
    const val ACTION_WIDGET_PINNED = "com.fangzi.qustschedule.widget.ACTION_WIDGET_PINNED"
    const val EXTRA_INCLUDE_WEEK = "include_week"
    private const val RC_WIDGET_REFRESH = 3001

    fun scheduleNext(
        context: Context,
        snapshot: WidgetSnapshotModel?,
        activeFlags: ActiveWidgetFlags,
    ) {
        if (!activeFlags.hasAny) {
            cancel(context)
            return
        }
        val appContext = context.applicationContext
        val alarmManager = appContext.getSystemService(AlarmManager::class.java) ?: return
        val nowMs = System.currentTimeMillis()
        val plan = WidgetContentResolver.computeNextRefreshPlan(
            snapshot = snapshot,
            nowMs = nowMs,
            hasToday = activeFlags.hasToday,
            hasNext = activeFlags.hasNext,
            hasWeek = activeFlags.hasWeek,
        )
        val pending = buildPendingIntent(appContext, includeWeek = plan.includeWeek)

        alarmManager.cancel(pending)
        if (ReminderPermissions.canScheduleExactAlarms(appContext)) {
            try {
                alarmManager.setExactAndAllowWhileIdle(
                    AlarmManager.RTC_WAKEUP,
                    plan.triggerAtMs,
                    pending,
                )
                return
            } catch (_: SecurityException) {
                // 极端时序下权限被撤，平稳降级到非精确唤醒。
            }
        }
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, plan.triggerAtMs, pending)
    }

    fun cancel(context: Context) {
        val appContext = context.applicationContext
        val alarmManager = appContext.getSystemService(AlarmManager::class.java) ?: return
        val intent = Intent(appContext, WidgetRefreshReceiver::class.java).apply {
            action = ACTION_REFRESH_WIDGETS
        }
        val existing = PendingIntent.getBroadcast(
            appContext,
            RC_WIDGET_REFRESH,
            intent,
            PendingIntent.FLAG_NO_CREATE or PendingIntent.FLAG_IMMUTABLE,
        ) ?: return
        alarmManager.cancel(existing)
        existing.cancel()
    }

    private fun buildPendingIntent(context: Context, includeWeek: Boolean): PendingIntent {
        val intent = Intent(context, WidgetRefreshReceiver::class.java).apply {
            action = ACTION_REFRESH_WIDGETS
            putExtra(EXTRA_INCLUDE_WEEK, includeWeek)
        }
        return PendingIntent.getBroadcast(
            context,
            RC_WIDGET_REFRESH,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
