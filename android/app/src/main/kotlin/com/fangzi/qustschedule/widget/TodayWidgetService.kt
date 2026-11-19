package com.fangzi.qustschedule.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.Intent
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.fangzi.qustschedule.R

/**
 * Android 11 及以下系统的 ListView 适配器；Android 12+ 由 `TodayWidgetProvider` 使用
 * `RemoteCollectionItems` 原子内嵌列表直接驱动。
 */
class TodayWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory {
        val appWidgetId = intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
        )
        return TodayRemoteViewsFactory(applicationContext, appWidgetId)
    }
}

private class TodayRemoteViewsFactory(
    private val context: Context,
    private val appWidgetId: Int,
) : RemoteViewsService.RemoteViewsFactory {

    private var items: List<TimelineItemData> = emptyList()
    private var style: WidgetStyleData = WidgetStyleData.defaultFor(KIND_TODAY)
    private var theme: ResolvedWidgetTheme = WidgetThemeResolver.resolve(context, style)
    private var nowMs: Long = 0L
    private var isNarrow: Boolean = false

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val snapshot = WidgetStore.loadSnapshot(context)
        style = snapshot?.styleOf(KIND_TODAY) ?: WidgetStyleData.defaultFor(KIND_TODAY)
        theme = WidgetThemeResolver.resolve(context, style)
        nowMs = System.currentTimeMillis()
        val widthDp = WidgetStore.loadTodayWidthDp(context, appWidgetId)
        isNarrow = TodayItemViewBinder.isNarrowWidth(widthDp)
        val vm = WidgetContentResolver.resolveToday(snapshot, style, nowMs)
        items = vm.items

        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
            val expectedSig = TodayWidgetProvider.headerSignature(vm, style)
            val renderedSig = WidgetStore.loadTodayHeaderSig(context, appWidgetId)
            if (expectedSig != renderedSig) {
                WidgetWorker.execute {
                    TodayWidgetProvider.updateWidgetById(
                        context,
                        appWidgetId,
                        notifyList = false,
                    )
                    WidgetCoordinator.syncAlarmState(context)
                }
            }
        }
    }

    override fun onDestroy() {
        items = emptyList()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        if (position !in items.indices) {
            return RemoteViews(context.packageName, R.layout.widget_today_item)
        }
        return TodayItemViewBinder.buildItemView(
            context = context,
            item = items[position],
            style = style,
            theme = theme,
            nowMs = nowMs,
            isNarrow = isNarrow,
        )
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long = position.toLong()

    override fun hasStableIds(): Boolean = false
}
