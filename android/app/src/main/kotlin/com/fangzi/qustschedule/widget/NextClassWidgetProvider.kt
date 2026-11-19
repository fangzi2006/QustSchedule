package com.fangzi.qustschedule.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.fangzi.qustschedule.R

class NextClassWidgetProvider : AppWidgetProvider() {

    override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        WidgetWorker.runBroadcastAsync(this, TAG) {
            updateWidgets(context, appWidgetManager, appWidgetIds)
            WidgetCoordinator.syncAlarmState(context)
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

    override fun onDisabled(context: Context) {
        WidgetWorker.runBroadcastAsync(this, TAG) {
            WidgetCoordinator.syncAlarmState(context)
        }
    }

    companion object {
        private const val TAG = "NextClassWidgetProvider"

        fun updateAll(context: Context, manager: AppWidgetManager): IntArray {
            val ids = manager.getAppWidgetIds(ComponentName(context, NextClassWidgetProvider::class.java))
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
            val style = snapshot?.styleOf(KIND_NEXT) ?: WidgetStyleData.defaultFor(KIND_NEXT)
            val theme = WidgetThemeResolver.resolve(context, style)
            val nowMs = System.currentTimeMillis()
            val vm = WidgetContentResolver.resolveNext(snapshot, style, nowMs)
            val (wDp, hDp) = WidgetBackgroundRenderer.resolveSizeDp(options, 140, 140)
            val isWide = hDp < 105 && wDp >= 180
            val layoutId = if (isWide) R.layout.widget_next_wide else R.layout.widget_next

            val bgBitmap = WidgetBackgroundRenderer.render(context, style, theme, wDp, hDp)
            val views = RemoteViews(context.packageName, layoutId)
            views.setImageViewBitmap(R.id.widget_next_bg, bgBitmap)

            val compact = style.density == "compact"
            val padPx = ((if (compact) 10f else 14f) * context.resources.displayMetrics.density).toInt()
            views.setViewPadding(R.id.widget_next_content, padPx, padPx, padPx, padPx)

            val chip = theme.courseColor(vm.colorIndex)
            val badgeBg = if (vm.isExam) theme.examBgColor else theme.accentBgColor
            val badgeFg = if (vm.isExam) theme.examFgColor else theme.accentColor
            if (isWide) {
                views.setInt(
                    R.id.widget_next_bar,
                    "setBackgroundColor",
                    if (vm.isExam) theme.examFgColor else chip.foreground,
                )
            }

            if (style.showHeader || isWide) {
                views.setViewVisibility(R.id.widget_next_badge, View.VISIBLE)
                views.setTextViewText(R.id.widget_next_badge, vm.badge)
                views.setTextColor(R.id.widget_next_badge, badgeFg)
                views.setInt(R.id.widget_next_badge, "setBackgroundColor", badgeBg)
                views.setTextViewTextSize(R.id.widget_next_badge, TypedValue.COMPLEX_UNIT_SP, 10f * style.fontScale)
            } else {
                views.setViewVisibility(R.id.widget_next_badge, View.GONE)
            }

            views.setTextViewText(R.id.widget_next_title, vm.title)
            views.setTextColor(R.id.widget_next_title, theme.primaryTextColor)
            views.setTextViewTextSize(
                R.id.widget_next_title,
                TypedValue.COMPLEX_UNIT_SP,
                (if (isWide) 13.5f else 14.5f) * style.fontScale,
            )

            if (style.showTime && vm.timeText.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_next_time, View.VISIBLE)
                views.setTextViewText(R.id.widget_next_time, vm.timeText)
                views.setTextColor(
                    R.id.widget_next_time,
                    if (isWide) theme.secondaryTextColor else theme.accentColor,
                )
                views.setTextViewTextSize(R.id.widget_next_time, TypedValue.COMPLEX_UNIT_SP, 11f * style.fontScale)
            } else {
                views.setViewVisibility(R.id.widget_next_time, View.GONE)
            }

            if (vm.subtitle.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_next_subtitle, View.VISIBLE)
                views.setTextViewText(R.id.widget_next_subtitle, vm.subtitle)
                views.setTextColor(R.id.widget_next_subtitle, theme.secondaryTextColor)
                views.setTextViewTextSize(R.id.widget_next_subtitle, TypedValue.COMPLEX_UNIT_SP, 11f * style.fontScale)
            } else {
                views.setViewVisibility(R.id.widget_next_subtitle, View.GONE)
            }

            views.setOnClickPendingIntent(
                R.id.widget_next_root,
                WidgetCoordinator.createLaunchPendingIntent(context),
            )
            manager.updateAppWidget(appWidgetId, views)
        }
    }
}
