package com.fangzi.qustschedule.widget

import android.content.Context
import android.content.Intent
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import android.widget.RemoteViewsService
import com.fangzi.qustschedule.R

class TodayWidgetService : RemoteViewsService() {
    override fun onGetViewFactory(intent: Intent): RemoteViewsFactory =
        TodayRemoteViewsFactory(applicationContext)
}

private class TodayRemoteViewsFactory(
    private val context: Context,
) : RemoteViewsService.RemoteViewsFactory {

    private var items: List<TimelineItemData> = emptyList()
    private var style: WidgetStyleData = WidgetStyleData.defaultFor(KIND_TODAY)
    private var theme: ResolvedWidgetTheme = WidgetThemeResolver.resolve(context, style)
    private var nowMs: Long = 0L

    override fun onCreate() {}

    override fun onDataSetChanged() {
        val snapshot = WidgetStore.loadSnapshot(context)
        style = snapshot?.styleOf(KIND_TODAY) ?: WidgetStyleData.defaultFor(KIND_TODAY)
        theme = WidgetThemeResolver.resolve(context, style)
        nowMs = System.currentTimeMillis()
        items = WidgetContentResolver.resolveToday(snapshot, style, nowMs).items
    }

    override fun onDestroy() {
        items = emptyList()
    }

    override fun getCount(): Int = items.size

    override fun getViewAt(position: Int): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_item)
        if (position !in items.indices) return views

        val item = items[position]
        val finished = item.endMs <= nowMs
        val ongoing = item.startMs <= nowMs && item.endMs > nowMs
        val dimmed = finished && style.finishedCourseMode == "dim"
        val chip = theme.courseColor(item.colorIndex)

        val compact = style.density == "compact"
        val verticalPadPx = ((if (compact) 3f else 5f) * context.resources.displayMetrics.density).toInt()
        views.setViewPadding(R.id.widget_today_item_root, 0, verticalPadPx, 0, verticalPadPx)

        val rawBarColor = if (item.isExam) theme.examFgColor else chip.foreground
        val barColor = if (dimmed) WidgetThemeResolver.withAlpha(rawBarColor, 115) else rawBarColor
        views.setInt(R.id.widget_today_item_bar, "setBackgroundColor", barColor)

        val titleColor = if (dimmed) {
            WidgetThemeResolver.withAlpha(theme.primaryTextColor, 120)
        } else {
            theme.primaryTextColor
        }
        val metaColor = if (dimmed) {
            WidgetThemeResolver.withAlpha(theme.secondaryTextColor, 115)
        } else {
            theme.secondaryTextColor
        }

        if (item.isExam) {
            views.setViewVisibility(R.id.widget_today_item_tag, View.VISIBLE)
            views.setTextViewText(R.id.widget_today_item_tag, "考试")
            views.setTextColor(R.id.widget_today_item_tag, theme.examFgColor)
            views.setInt(R.id.widget_today_item_tag, "setBackgroundColor", theme.examBgColor)
            views.setTextViewTextSize(R.id.widget_today_item_tag, TypedValue.COMPLEX_UNIT_SP, 9.5f * style.fontScale)
        } else if (ongoing) {
            views.setViewVisibility(R.id.widget_today_item_tag, View.VISIBLE)
            views.setTextViewText(R.id.widget_today_item_tag, "进行中")
            views.setTextColor(R.id.widget_today_item_tag, chip.foreground)
            views.setInt(R.id.widget_today_item_tag, "setBackgroundColor", chip.background)
            views.setTextViewTextSize(R.id.widget_today_item_tag, TypedValue.COMPLEX_UNIT_SP, 9.5f * style.fontScale)
        } else if (item.rescheduled) {
            views.setViewVisibility(R.id.widget_today_item_tag, View.VISIBLE)
            views.setTextViewText(R.id.widget_today_item_tag, "调课")
            views.setTextColor(R.id.widget_today_item_tag, theme.examFgColor)
            views.setInt(R.id.widget_today_item_tag, "setBackgroundColor", theme.examBgColor)
            views.setTextViewTextSize(R.id.widget_today_item_tag, TypedValue.COMPLEX_UNIT_SP, 9.5f * style.fontScale)
        } else {
            views.setViewVisibility(R.id.widget_today_item_tag, View.GONE)
        }

        views.setTextViewText(R.id.widget_today_item_title, item.title)
        views.setTextColor(R.id.widget_today_item_title, titleColor)
        views.setTextViewTextSize(R.id.widget_today_item_title, TypedValue.COMPLEX_UNIT_SP, 13f * style.fontScale)

        val metaParts = listOfNotNull(
            if (style.showTime && item.startLabel.isNotEmpty()) "${item.startLabel}-${item.endLabel}" else null,
            item.location.takeIf { style.showLocation && it.isNotEmpty() },
            item.seatNumber.takeIf { item.isExam && it.isNotEmpty() }?.let { "${it}座" },
            item.teacher.takeIf { !item.isExam && style.showTeacher && it.isNotEmpty() },
        )
        val metaText = metaParts.joinToString(" · ")
        if (metaText.isNotEmpty()) {
            views.setViewVisibility(R.id.widget_today_item_meta, View.VISIBLE)
            views.setTextViewText(R.id.widget_today_item_meta, metaText)
            views.setTextColor(R.id.widget_today_item_meta, metaColor)
            views.setTextViewTextSize(R.id.widget_today_item_meta, TypedValue.COMPLEX_UNIT_SP, 10.5f * style.fontScale)
        } else {
            views.setViewVisibility(R.id.widget_today_item_meta, View.GONE)
        }

        views.setOnClickFillInIntent(R.id.widget_today_item_root, Intent())
        return views
    }

    override fun getLoadingView(): RemoteViews? = null

    override fun getViewTypeCount(): Int = 1

    override fun getItemId(position: Int): Long =
        items.getOrNull(position)?.id?.hashCode()?.toLong() ?: position.toLong()

    override fun hasStableIds(): Boolean = true
}
