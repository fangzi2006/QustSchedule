package com.fangzi.qustschedule.widget

import android.content.Context
import android.content.Intent
import android.os.Build
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.fangzi.qustschedule.R
import kotlin.math.roundToInt

/**
 * 今日课表条目共享渲染器（双栏时间轴风格）：
 * 左侧固定宽度的上下堆叠等宽起止时间 + 定高一致圆角竖条，右侧课名/状态角标/地点·教师；
 * 4×2 宽卡与 2×2 窄卡统一展示完整起止时间，绝不在窄卡静默截断下课时间。
 */
internal object TodayItemViewBinder {

    fun isNarrowWidth(widthDp: Int): Boolean = widthDp < 200

    fun buildItemView(
        context: Context,
        item: TimelineItemData,
        style: WidgetStyleData,
        theme: ResolvedWidgetTheme,
        nowMs: Long,
        isNarrow: Boolean,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.widget_today_item)
        val finished = item.endMs <= nowMs
        val ongoing = item.startMs <= nowMs && item.endMs > nowMs
        val dimmed = finished && style.finishedCourseMode == "dim"
        val chip = theme.courseColor(item.colorIndex)

        val compact = style.density == "compact"
        val density = context.resources.displayMetrics.density
        fun dpPx(v: Float): Int = (v * density).roundToInt()

        val outerVPadPx = dpPx(if (compact) 0.75f else 1.25f)
        views.setViewPadding(R.id.widget_today_item_outer, 0, outerVPadPx, 0, outerVPadPx)

        // 进行中课程/考试使用柔和低饱和整行底色高亮；普通行保持透明极简时间轴。
        if (ongoing) {
            val rowBg = if (item.isExam) theme.examRowBgColor else theme.ongoingRowBgColor
            val fallback = if (item.isExam) {
                if (theme.isDark) R.drawable.widget_row_highlight_exam_dark else R.drawable.widget_row_highlight_exam_light
            } else {
                if (theme.isDark) R.drawable.widget_row_highlight_ongoing_dark else R.drawable.widget_row_highlight_ongoing_light
            }
            WidgetThemeResolver.applyRoundedBackground(
                views = views,
                viewId = R.id.widget_today_item_root,
                bgColor = rowBg,
                baseDrawableRes = R.drawable.widget_row_highlight_bg,
                fallbackDrawableRes = fallback,
            )
        } else {
            WidgetThemeResolver.clearBackground(views, R.id.widget_today_item_root)
        }

        val rowHPadPx = dpPx(if (isNarrow) 2.5f else 4.0f)
        val rowVPadPx = dpPx(
            when {
                isNarrow && compact -> 1.5f
                isNarrow -> 2.5f
                compact -> 2.0f
                else -> 3.0f
            },
        )
        views.setViewPadding(R.id.widget_today_item_root, rowHPadPx, rowVPadPx, rowHPadPx, rowVPadPx)

        val barLeftGapDp = if (isNarrow) 3.5f else 4.0f
        val barRightGapDp = if (isNarrow) 4.0f else 4.5f
        val timeColWidthDp = (if (isNarrow) 34.0f else 37.0f) * style.fontScale + barLeftGapDp
        views.setViewPadding(R.id.widget_today_item_time_col, 0, 0, dpPx(barLeftGapDp), 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setViewLayoutWidth(
                R.id.widget_today_item_time_col,
                timeColWidthDp,
                TypedValue.COMPLEX_UNIT_DIP,
            )
        }
        views.setViewPadding(R.id.widget_today_item_body, dpPx(barRightGapDp), 0, dpPx(1f), 0)

        // 1. 左栏：严格固定宽度的堆叠起止时间（避免不同时刻数字不等宽导致竖条错位与同类课截断不一致；
        //    缺时间条目占位 INVISIBLE，保证同屏各行竖条严格对齐）
        val startDp = (if (isNarrow) 9.6f else 10.5f) * style.fontScale
        val endDp = (if (isNarrow) 8.4f else 9.0f) * style.fontScale
        if (style.showTime && item.startLabel.isNotEmpty()) {
            views.setViewVisibility(R.id.widget_today_item_time_col, View.VISIBLE)
            val startColor = when {
                dimmed -> WidgetThemeResolver.withAlpha(theme.primaryTextColor, 110)
                ongoing && item.isExam -> theme.examFgColor
                ongoing -> theme.ongoingFgColor
                else -> theme.primaryTextColor
            }
            val endColor = if (dimmed) {
                WidgetThemeResolver.withAlpha(theme.tertiaryTextColor, 100)
            } else {
                theme.tertiaryTextColor
            }

            views.setTextViewText(R.id.widget_today_item_time_start, item.startLabel)
            views.setTextColor(R.id.widget_today_item_time_start, startColor)
            views.setTextViewTextSize(R.id.widget_today_item_time_start, TypedValue.COMPLEX_UNIT_DIP, startDp)

            if (item.endLabel.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_today_item_time_end, View.VISIBLE)
                views.setTextViewText(R.id.widget_today_item_time_end, item.endLabel)
                views.setTextColor(R.id.widget_today_item_time_end, endColor)
                views.setTextViewTextSize(R.id.widget_today_item_time_end, TypedValue.COMPLEX_UNIT_DIP, endDp)
            } else {
                views.setViewVisibility(R.id.widget_today_item_time_end, View.GONE)
            }
        } else if (style.showTime) {
            views.setViewVisibility(R.id.widget_today_item_time_col, View.INVISIBLE)
            views.setTextViewText(R.id.widget_today_item_time_start, "00:00")
            views.setTextViewTextSize(R.id.widget_today_item_time_start, TypedValue.COMPLEX_UNIT_DIP, startDp)
            views.setViewVisibility(R.id.widget_today_item_time_end, View.GONE)
        } else {
            views.setViewVisibility(R.id.widget_today_item_time_col, View.GONE)
        }

        val metaParts = listOfNotNull(
            item.location.takeIf { style.showLocation && it.isNotEmpty() },
            item.seatNumber.takeIf { item.isExam && style.showLocation && it.isNotEmpty() }?.let { "${it}座" },
            item.teacher.takeIf { !item.isExam && style.showTeacher && it.isNotEmpty() },
        )
        val metaText = metaParts.joinToString(" · ")

        // 2. 确定性高度圆角竖条（不透明色滤镜 + setImageAlpha，并按行数显式设高避免 ListView match_parent 参差）
        val rawBarColor = if (item.isExam) theme.examFgColor else chip.foreground
        WidgetThemeResolver.applyVerticalBar(
            views = views,
            viewId = R.id.widget_today_item_bar,
            color = rawBarColor,
            alpha = if (dimmed) 105 else 255,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val hasTwoLines = (style.showTime && item.startLabel.isNotEmpty() && item.endLabel.isNotEmpty()) ||
                metaText.isNotEmpty()
            val barHeightDp = (
                if (hasTwoLines) {
                    if (isNarrow) 22.0f else 24.0f
                } else {
                    if (isNarrow) 12.5f else 14.0f
                }
            ) * style.fontScale
            views.setViewLayoutHeight(
                R.id.widget_today_item_bar,
                barHeightDp,
                TypedValue.COMPLEX_UNIT_DIP,
            )
        }

        // 3. 右栏：状态角标 + 课程名 + 地点/教师（考试座位号受 showLocation 控制）
        val titleColor = if (dimmed) {
            WidgetThemeResolver.withAlpha(theme.primaryTextColor, 120)
        } else {
            theme.primaryTextColor
        }
        val metaColor = if (dimmed) {
            WidgetThemeResolver.withAlpha(theme.secondaryTextColor, 110)
        } else {
            theme.secondaryTextColor
        }

        val tagDp = (if (isNarrow) 7.5f else 8.5f) * style.fontScale
        val tagHPad = dpPx(4f)
        val tagVPad = dpPx(1f)
        when {
            item.isExam && ongoing -> {
                views.setViewVisibility(R.id.widget_today_item_tag, View.VISIBLE)
                views.setTextViewText(R.id.widget_today_item_tag, "正在考试")
                WidgetThemeResolver.applyPill(views, R.id.widget_today_item_tag, theme, WidgetPillTone.EXAM, dimmed = false)
                views.setViewPadding(R.id.widget_today_item_tag, tagHPad, tagVPad, tagHPad, tagVPad)
                views.setTextViewTextSize(R.id.widget_today_item_tag, TypedValue.COMPLEX_UNIT_DIP, tagDp)
            }
            item.isExam -> {
                views.setViewVisibility(R.id.widget_today_item_tag, View.VISIBLE)
                views.setTextViewText(R.id.widget_today_item_tag, "考试")
                WidgetThemeResolver.applyPill(views, R.id.widget_today_item_tag, theme, WidgetPillTone.EXAM, dimmed = dimmed)
                views.setViewPadding(R.id.widget_today_item_tag, tagHPad, tagVPad, tagHPad, tagVPad)
                views.setTextViewTextSize(R.id.widget_today_item_tag, TypedValue.COMPLEX_UNIT_DIP, tagDp)
            }
            ongoing -> {
                views.setViewVisibility(R.id.widget_today_item_tag, View.VISIBLE)
                views.setTextViewText(R.id.widget_today_item_tag, "进行中")
                WidgetThemeResolver.applyPill(views, R.id.widget_today_item_tag, theme, WidgetPillTone.ONGOING, dimmed = false)
                views.setViewPadding(R.id.widget_today_item_tag, tagHPad, tagVPad, tagHPad, tagVPad)
                views.setTextViewTextSize(R.id.widget_today_item_tag, TypedValue.COMPLEX_UNIT_DIP, tagDp)
            }
            item.rescheduled -> {
                views.setViewVisibility(R.id.widget_today_item_tag, View.VISIBLE)
                views.setTextViewText(R.id.widget_today_item_tag, "调课")
                WidgetThemeResolver.applyPill(views, R.id.widget_today_item_tag, theme, WidgetPillTone.RESCHEDULE, dimmed = dimmed)
                views.setViewPadding(R.id.widget_today_item_tag, tagHPad, tagVPad, tagHPad, tagVPad)
                views.setTextViewTextSize(R.id.widget_today_item_tag, TypedValue.COMPLEX_UNIT_DIP, tagDp)
            }
            else -> {
                views.setViewVisibility(R.id.widget_today_item_tag, View.GONE)
            }
        }

        val titleDp = (if (isNarrow) 10.8f else 12.0f) * style.fontScale
        views.setTextViewText(R.id.widget_today_item_title, item.title)
        views.setTextColor(R.id.widget_today_item_title, titleColor)
        views.setTextViewTextSize(R.id.widget_today_item_title, TypedValue.COMPLEX_UNIT_DIP, titleDp)

        if (metaText.isNotEmpty()) {
            val metaDp = (if (isNarrow) 9.0f else 10.0f) * style.fontScale
            views.setViewVisibility(R.id.widget_today_item_meta, View.VISIBLE)
            views.setTextViewText(R.id.widget_today_item_meta, metaText)
            views.setTextColor(R.id.widget_today_item_meta, metaColor)
            views.setTextViewTextSize(R.id.widget_today_item_meta, TypedValue.COMPLEX_UNIT_DIP, metaDp)
        } else {
            views.setViewVisibility(R.id.widget_today_item_meta, View.GONE)
        }

        views.setOnClickFillInIntent(R.id.widget_today_item_outer, Intent())
        return views
    }
}
