package com.fangzi.qustschedule.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.Build
import com.fangzi.qustschedule.MainActivity

internal data class ActiveWidgetFlags(
    val hasToday: Boolean,
    val hasNext: Boolean,
    val hasWeek: Boolean,
) {
    val hasAny: Boolean get() = hasToday || hasNext || hasWeek
}

internal object WidgetCoordinator {

    private const val RC_LAUNCH_IMMUTABLE = 3101
    private const val RC_LAUNCH_TEMPLATE = 3102
    private const val RC_PIN_CALLBACK = 3103

    fun refreshChangedWidgets(
        context: Context,
        previous: WidgetSnapshotModel?,
        current: WidgetSnapshotModel,
    ) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        val todayIso = WidgetContentResolver.formatIsoDate(System.currentTimeMillis())
        val weekDateStale = WidgetStore.loadLastWeekRenderDateIso(appContext) != todayIso
        val todayDirty = previous == null ||
            previous.kindSignature(KIND_TODAY) != current.kindSignature(KIND_TODAY)
        val nextDirty = previous == null ||
            previous.kindSignature(KIND_NEXT) != current.kindSignature(KIND_NEXT)
        val weekDirty = previous == null ||
            weekDateStale ||
            previous.kindSignature(KIND_WEEK) != current.kindSignature(KIND_WEEK)
        // Dart 侧仅在显式 force=true（如回到前台兜底恢复）时才会下发与上次完全一致的快照。
        val forceAll = !todayDirty && !nextDirty && !weekDirty

        if (forceAll || todayDirty) TodayWidgetProvider.updateAll(appContext, manager)
        if (forceAll || nextDirty) NextClassWidgetProvider.updateAll(appContext, manager)
        if (forceAll || weekDirty) WeekGridWidgetProvider.updateAll(appContext, manager)

        scheduleOrCancelAlarm(appContext, manager, current)
    }

    fun refreshAllWidgets(context: Context) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        val todayIds = TodayWidgetProvider.updateAll(appContext, manager)
        val nextIds = NextClassWidgetProvider.updateAll(appContext, manager)
        val weekIds = WeekGridWidgetProvider.updateAll(appContext, manager)
        val flags = ActiveWidgetFlags(
            hasToday = todayIds.isNotEmpty(),
            hasNext = nextIds.isNotEmpty(),
            hasWeek = weekIds.isNotEmpty(),
        )
        if (flags.hasAny) {
            WidgetRefreshScheduler.scheduleNext(appContext, WidgetStore.loadSnapshot(appContext), flags)
        } else {
            WidgetRefreshScheduler.cancel(appContext)
        }
    }

    /**
     * 节点闹钟触发时的靶向刷新：上下课节点仅刷新今日/下一节，跨天 00:01 或检测到日期翻转时再重绘周课表位图。
     */
    fun refreshForScheduledAlarm(context: Context, includeWeekRequested: Boolean) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        val todayIds = TodayWidgetProvider.updateAll(appContext, manager)
        val nextIds = NextClassWidgetProvider.updateAll(appContext, manager)

        val weekComponent = ComponentName(appContext, WeekGridWidgetProvider::class.java)
        val hasWeek = manager.getAppWidgetIds(weekComponent).isNotEmpty()
        val todayIso = WidgetContentResolver.formatIsoDate(System.currentTimeMillis())
        val lastWeekIso = WidgetStore.loadLastWeekRenderDateIso(appContext)
        val needWeekRefresh = hasWeek && (includeWeekRequested || lastWeekIso != todayIso)
        if (needWeekRefresh) {
            WeekGridWidgetProvider.updateAll(appContext, manager)
        }

        val flags = ActiveWidgetFlags(
            hasToday = todayIds.isNotEmpty(),
            hasNext = nextIds.isNotEmpty(),
            hasWeek = hasWeek,
        )
        if (flags.hasAny) {
            WidgetRefreshScheduler.scheduleNext(appContext, WidgetStore.loadSnapshot(appContext), flags)
        } else {
            WidgetRefreshScheduler.cancel(appContext)
        }
    }

    fun syncAlarmState(context: Context) {
        val appContext = context.applicationContext
        val manager = AppWidgetManager.getInstance(appContext)
        scheduleOrCancelAlarm(appContext, manager, WidgetStore.loadSnapshot(appContext))
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

    fun notifyPinnedCountsChanged(context: Context) {
        val appContext = context.applicationContext
        WidgetBridge.dispatchPinnedCountsChanged(getPinnedCounts(appContext))
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

    fun createPinSuccessPendingIntent(context: Context): PendingIntent {
        val intent = Intent(context.applicationContext, WidgetRefreshReceiver::class.java).apply {
            action = WidgetRefreshScheduler.ACTION_WIDGET_PINNED
        }
        return PendingIntent.getBroadcast(
            context.applicationContext,
            RC_PIN_CALLBACK,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun scheduleOrCancelAlarm(
        appContext: Context,
        manager: AppWidgetManager,
        snapshot: WidgetSnapshotModel?,
    ) {
        val flags = activeWidgetFlags(appContext, manager)
        if (flags.hasAny) {
            WidgetRefreshScheduler.scheduleNext(appContext, snapshot, flags)
        } else {
            WidgetRefreshScheduler.cancel(appContext)
        }
    }

    private fun activeWidgetFlags(context: Context, manager: AppWidgetManager): ActiveWidgetFlags {
        val hasToday = manager.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java)).isNotEmpty()
        val hasNext = manager.getAppWidgetIds(ComponentName(context, NextClassWidgetProvider::class.java)).isNotEmpty()
        val hasWeek = manager.getAppWidgetIds(ComponentName(context, WeekGridWidgetProvider::class.java)).isNotEmpty()
        return ActiveWidgetFlags(hasToday = hasToday, hasNext = hasNext, hasWeek = hasWeek)
    }
}
