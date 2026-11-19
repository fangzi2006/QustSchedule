package com.fangzi.qustschedule.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import com.fangzi.qustschedule.MainActivity

internal object WidgetCoordinator {

    private const val RC_LAUNCH_IMMUTABLE = 3101
    private const val RC_LAUNCH_TEMPLATE = 3102

    fun refreshAllWidgets(context: Context) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        val todayIds = TodayWidgetProvider.updateAll(appContext, manager)
        val nextIds = NextClassWidgetProvider.updateAll(appContext, manager)
        val weekIds = WeekGridWidgetProvider.updateAll(appContext, manager)
        val hasActive = todayIds.isNotEmpty() || nextIds.isNotEmpty() || weekIds.isNotEmpty()
        if (hasActive) {
            WidgetRefreshScheduler.scheduleNext(appContext, WidgetStore.loadSnapshot(appContext))
        } else {
            WidgetRefreshScheduler.cancel(appContext)
        }
    }

    fun syncAlarmState(context: Context) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        if (hasAnyActiveWidgets(appContext, manager)) {
            WidgetRefreshScheduler.scheduleNext(appContext, WidgetStore.loadSnapshot(appContext))
        } else {
            WidgetRefreshScheduler.cancel(appContext)
        }
    }

    fun getPinnedCounts(context: Context): Map<String, Int> {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        return mapOf(
            KIND_TODAY to manager.getAppWidgetIds(ComponentName(appContext, TodayWidgetProvider::class.java)).size,
            KIND_WEEK to manager.getAppWidgetIds(ComponentName(appContext, WeekGridWidgetProvider::class.java)).size,
            KIND_NEXT to manager.getAppWidgetIds(ComponentName(appContext, NextClassWidgetProvider::class.java)).size,
        )
    }

    fun componentForKind(context: Context, kind: String): ComponentName? {
        val cls = when (kind) {
            KIND_TODAY -> TodayWidgetProvider::class.java
            KIND_WEEK -> WeekGridWidgetProvider::class.java
            KIND_NEXT -> NextClassWidgetProvider::class.java
            else -> return null
        }
        return ComponentName(context.applicationContext, cls)
    }

    fun createLaunchPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context.applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        return PendingIntent.getActivity(
            context.applicationContext,
            RC_LAUNCH_IMMUTABLE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    fun createLaunchTemplatePendingIntent(context: Context): PendingIntent {
        val intent = Intent(context.applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
        }
        val mutableFlag = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            PendingIntent.FLAG_MUTABLE
        } else {
            0
        }
        return PendingIntent.getActivity(
            context.applicationContext,
            RC_LAUNCH_TEMPLATE,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or mutableFlag,
        )
    }

    private fun hasAnyActiveWidgets(context: Context, manager: AppWidgetManager): Boolean {
        val c1 = manager.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java)).isNotEmpty()
        val c2 = manager.getAppWidgetIds(ComponentName(context, NextClassWidgetProvider::class.java)).isNotEmpty()
        val c3 = manager.getAppWidgetIds(ComponentName(context, WeekGridWidgetProvider::class.java)).isNotEmpty()
        return c1 || c2 || c3
    }
}
