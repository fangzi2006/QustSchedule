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
            updateWidgetWithSnapshot(
                context,
                appWidgetManager,
                appWidgetId,
                newOptions,
                snapshot,
                skipIfUnchanged = true,
            )
        }
    }

    override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        WidgetWorker.runBroadcastAsync(this, TAG) {
            removeCachedWidgetIds(appWidgetIds)
            WidgetCoordinator.syncAlarmState(context)
            WidgetCoordinator.notifyPinnedCountsChanged(context)
        }
    }

    override fun onDisabled(context: Context) {
        WidgetWorker.runBroadcastAsync(this, TAG) {
            clearRenderCache()
            WidgetCoordinator.syncAlarmState(context)
            WidgetCoordinator.notifyPinnedCountsChanged(context)
        }
    }

    companion object {
        private const val TAG = "WeekGridWidgetProvider"

        private data class WeekRenderKey(
            val widthDp: Int,
            val heightDp: Int,
            val screenWidthPx: Int,
            val screenHeightPx: Int,
            val densityBits: Int,
            val isDark: Boolean,
            val surfaceColor: Int,
            val accentColor: Int,
            val todayIso: String,
            val snapshotFingerprint: String,
            val weekSignature: Int,
        )

        private val cacheLock = Any()
        private val pushedKeyByWidgetId = HashMap<Int, WeekRenderKey>()

        internal fun clearRenderCache() {
            synchronized(cacheLock) {
                pushedKeyByWidgetId.clear()
            }
        }

        private fun removeCachedWidgetIds(appWidgetIds: IntArray) {
            synchronized(cacheLock) {
                for (id in appWidgetIds) {
                    pushedKeyByWidgetId.remove(id)
                }
            }
        }

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
            skipIfUnchanged: Boolean = false,
        ) {
            val style = snapshot?.styleOf(KIND_WEEK) ?: WidgetStyleData.defaultFor(KIND_WEEK)
            val theme = WidgetThemeResolver.resolve(context, style)
            val nowMs = System.currentTimeMillis()
            val todayIso = WidgetContentResolver.formatIsoDate(nowMs)
            val (wDp, hDp) = WidgetBackgroundRenderer.resolveSizeDp(context, options, 300, 280)
            val dm = context.resources.displayMetrics
            val renderKey = WeekRenderKey(
                widthDp = wDp,
                heightDp = hDp,
                screenWidthPx = dm.widthPixels,
                screenHeightPx = dm.heightPixels,
                densityBits = dm.density.toRawBits(),
                isDark = theme.isDark,
                surfaceColor = theme.surfaceColor,
                accentColor = theme.accentColor,
                todayIso = todayIso,
                snapshotFingerprint = snapshot?.fingerprint ?: "",
                weekSignature = snapshot?.kindSignature(KIND_WEEK) ?: 0,
            )

            if (skipIfUnchanged) {
                synchronized(cacheLock) {
                    if (pushedKeyByWidgetId[appWidgetId] == renderKey) {
                        return
                    }
                }
            }

            val vm = WidgetContentResolver.resolveWeek(snapshot, style, nowMs)
            val views = WeekGridRemoteViewsBuilder.build(context, style, theme, vm, wDp, hDp)
            views.setOnClickPendingIntent(
                R.id.widget_week_root,
                WidgetCoordinator.createLaunchPendingIntent(context),
            )
            manager.updateAppWidget(appWidgetId, views)
            synchronized(cacheLock) {
                pushedKeyByWidgetId[appWidgetId] = renderKey
            }
            WidgetStore.saveLastWeekRenderDateIso(context, todayIso)
        }
    }
}
