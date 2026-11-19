package com.fangzi.qustschedule.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.fangzi.qustschedule.R

class TodayWidgetProvider : AppWidgetProvider() {

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
            updateWidget(context, appWidgetManager, appWidgetId, newOptions)
        }
    }

    override fun onDisabled(context: Context) {
        WidgetWorker.runBroadcastAsync(this, TAG) {
            WidgetCoordinator.syncAlarmState(context)
        }
    }

    companion object {
        private const val TAG = "TodayWidgetProvider"

        fun updateAll(context: Context, manager: AppWidgetManager): IntArray {
            val ids = manager.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java))
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

        private fun updateWidget(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            options: Bundle,
        ) {
            val snapshot = WidgetStore.loadSnapshot(context)
            updateWidgetWithSnapshot(context, manager, appWidgetId, options, snapshot)
        }

        private fun updateWidgetWithSnapshot(
            context: Context,
            manager: AppWidgetManager,
            appWidgetId: Int,
            options: Bundle?,
            snapshot: WidgetSnapshotModel?,
        ) {
            val style = snapshot?.styleOf(KIND_TODAY) ?: WidgetStyleData.defaultFor(KIND_TODAY)
            val theme = WidgetThemeResolver.resolve(context, style)
            val nowMs = System.currentTimeMillis()
            val vm = WidgetContentResolver.resolveToday(snapshot, style, nowMs)
            val (wDp, hDp) = WidgetBackgroundRenderer.resolveSizeDp(options, 260, 140)
            val bgBitmap = WidgetBackgroundRenderer.render(context, style, theme, wDp, hDp)

            val views = RemoteViews(context.packageName, R.layout.widget_today)
            views.setImageViewBitmap(R.id.widget_today_bg, bgBitmap)

            val compact = style.density == "compact"
            val padPx = ((if (compact) 10f else 14f) * context.resources.displayMetrics.density).toInt()
            views.setViewPadding(R.id.widget_today_content, padPx, padPx, padPx, padPx)

            if (style.showHeader) {
                views.setViewVisibility(R.id.widget_today_header, View.VISIBLE)
                views.setTextViewText(R.id.widget_today_title, vm.headerTitle)
                views.setTextColor(R.id.widget_today_title, theme.accentColor)
                views.setTextViewTextSize(R.id.widget_today_title, TypedValue.COMPLEX_UNIT_SP, 12.5f * style.fontScale)
                views.setTextViewText(R.id.widget_today_subtitle, vm.headerRight)
                views.setTextColor(R.id.widget_today_subtitle, theme.secondaryTextColor)
                views.setTextViewTextSize(R.id.widget_today_subtitle, TypedValue.COMPLEX_UNIT_SP, 11f * style.fontScale)
            } else {
                views.setViewVisibility(R.id.widget_today_header, View.GONE)
            }

            if (vm.items.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_today_list, View.VISIBLE)
                views.setViewVisibility(R.id.widget_today_empty_box, View.GONE)
                val serviceIntent = Intent(context, TodayWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    data = Uri.parse("qust://today_widget/$appWidgetId")
                }
                views.setRemoteAdapter(R.id.widget_today_list, serviceIntent)
                views.setPendingIntentTemplate(
                    R.id.widget_today_list,
                    WidgetCoordinator.createLaunchTemplatePendingIntent(context),
                )
            } else {
                views.setViewVisibility(R.id.widget_today_list, View.GONE)
                views.setViewVisibility(R.id.widget_today_empty_box, View.VISIBLE)

                val exam = vm.examBanner
                if (exam != null) {
                    val days = WidgetContentResolver.calendarDayDiff(nowMs, exam.startMs)
                    val countdown = if (days <= 0) "今天考试" else "还有 ${days} 天"
                    val weekPart = if (exam.week > 0) " · 第${exam.week}周 ${WidgetContentResolver.weekdayName(exam.weekday)}" else ""
                    views.setViewVisibility(R.id.widget_today_empty_badge, View.VISIBLE)
                    views.setTextViewText(R.id.widget_today_empty_badge, "近期考试 · $countdown$weekPart")
                    views.setTextColor(R.id.widget_today_empty_badge, theme.examFgColor)
                    views.setTextViewTextSize(R.id.widget_today_empty_badge, TypedValue.COMPLEX_UNIT_SP, 10.5f * style.fontScale)

                    views.setTextViewText(R.id.widget_today_empty_title, exam.courseName)
                    views.setTextColor(R.id.widget_today_empty_title, theme.primaryTextColor)
                    views.setTextViewTextSize(R.id.widget_today_empty_title, TypedValue.COMPLEX_UNIT_SP, 14f * style.fontScale)

                    val datePart = if (exam.dateIso.length >= 10) exam.dateIso.substring(5) else exam.dateIso
                    val meta = listOfNotNull(
                        if (style.showTime) "$datePart ${exam.timeLabel}" else null,
                        exam.location.takeIf { style.showLocation && it.isNotEmpty() },
                        exam.seatNumber.takeIf { it.isNotEmpty() }?.let { "${it}座" },
                    ).joinToString(" · ")
                    if (meta.isNotEmpty()) {
                        views.setViewVisibility(R.id.widget_today_empty_meta, View.VISIBLE)
                        views.setTextViewText(R.id.widget_today_empty_meta, meta)
                        views.setTextColor(R.id.widget_today_empty_meta, theme.secondaryTextColor)
                        views.setTextViewTextSize(R.id.widget_today_empty_meta, TypedValue.COMPLEX_UNIT_SP, 11f * style.fontScale)
                    } else {
                        views.setViewVisibility(R.id.widget_today_empty_meta, View.GONE)
                    }
                } else {
                    views.setViewVisibility(R.id.widget_today_empty_badge, View.GONE)
                    views.setTextViewText(R.id.widget_today_empty_title, vm.emptyMessage)
                    views.setTextColor(R.id.widget_today_empty_title, theme.secondaryTextColor)
                    views.setTextViewTextSize(R.id.widget_today_empty_title, TypedValue.COMPLEX_UNIT_SP, 12.5f * style.fontScale)
                    views.setViewVisibility(R.id.widget_today_empty_meta, View.GONE)
                }
            }

            views.setOnClickPendingIntent(
                R.id.widget_today_root,
                WidgetCoordinator.createLaunchPendingIntent(context),
            )
            manager.updateAppWidget(appWidgetId, views)
            if (vm.items.isNotEmpty()) {
                manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_today_list)
            }
        }
    }
}
