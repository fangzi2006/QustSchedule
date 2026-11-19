package com.fangzi.qustschedule.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.widget.RemoteViews
import com.fangzi.qustschedule.R

class WeekGridWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        WidgetWorker.runBroadcastAsync(this, TAG) {
            updateWidgets(context, appWidgetManager, appWidgetIds)
            WidgetCoordinator.syncAlarmState(context)
            WidgetCoordinator.notifyPinnedCountsChanged(context)
        }
    }

    override fun onAppWidgetOptionsChanged(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetId: Int,
        newOptions: Bundle,
    ) {
        WidgetWorker.runBroadcastAsync(this, TAG) {
            val snapshot = WidgetStore.loadSnapshot(context)
            updateWidgetWithSnapshot(context, appWidgetManager, appWidgetId, newOptions, snapshot)
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        WidgetWorker.runBroadcastAsync(this, TAG) {
            WidgetCoordinator.syncAlarmState(context)
            WidgetCoordinator.notifyPinnedCountsChanged(context)
        }
    }

    override fun onDisabled(context: Context) {
        WidgetWorker.runBroadcastAsync(this, TAG) {
            WidgetCoordinator.syncAlarmState(context)
            WidgetCoordinator.notifyPinnedCountsChanged(context)
        }
    }

    companion object {
        private const val TAG = "WeekGridWidgetProvider"

        fun updateAll(context: Context, manager: AppWidgetManager): IntArray {
            val ids = manager.getAppWidgetIds(ComponentName(context, WeekGridWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                updateWidgets(context, manager, ids)
            }
            return ids
        }

        private fun updateWidgets(
            context: Context,
            manager: AppWidgetManager,
            appWidgetIds: IntArray,
        ) {
            val snapshot = WidgetStore.loadSnapshot(context)
            for (id in appWidgetIds) {
                val options = manager.getAppWidgetOptions(id)
                updateWidgetWithSnapshot(context, manager, id, options, snapshot)
            }
        }

        private fun updateWidgetWithSnapshot(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            options: Bundle?,
            snapshot: WidgetSnapshotModel?,
        ) {
            val style = snapshot?.styleOf(KIND_WEEK) ?: WidgetStyleData.defaultFor(KIND_WEEK)
            val theme = WidgetThemeResolver.resolve(context, style)
            val nowMs = System.currentTimeMillis()
            val vm = WidgetContentResolver.resolveWeek(snapshot, style, nowMs)
            val (wDp, hDp) = WidgetBackgroundRenderer.resolveSizeDp(context, options, 300, 280)
            val bitmap = WeekGridCanvasRenderer.render(context, style, theme, vm, wDp, hDp)

            val views = RemoteViews(context.packageName, R.layout.widget_week)
            views.setImageViewBitmap(R.id.widget_week_image, bitmap)
            views.setOnClickPendingIntent(
                R.id.widget_week_root,
                WidgetCoordinator.createLaunchPendingIntent(context),
            )
            manager.updateAppWidget(appWidgetId, views)
            WidgetStore.saveLastWeekRenderDateIso(context, WidgetContentResolver.formatIsoDate(nowMs))
        }
    }
}
