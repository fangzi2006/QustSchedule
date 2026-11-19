package com.fangzi.qustschedule.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.fangzi.qustschedule.R
import kotlin.math.roundToInt

class TodayWidgetProvider : AppWidgetProvider() {

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
            for (id in appWidgetIds) {
                WidgetStore.removeTodayWidgetMeta(context, id)
            }
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
        private const val TAG = "TodayWidgetProvider"

        internal fun headerSignature(
            vm: TodayWidgetViewModel,
            style: WidgetStyleData,
        ): String =
            "${vm.badgeText}|${vm.headerTitle}|${vm.headerRight}|${vm.isTomorrow}|${vm.isStale}|${vm.items.isNotEmpty()}|${vm.examBanner?.id ?: ""}|${style.showHeader}|${style.autoSwitchTomorrow}"

        fun updateAll(context: Context, manager: AppWidgetManager): IntArray {
            val ids = manager.getAppWidgetIds(ComponentName(context, TodayWidgetProvider::class.java))
            if (ids.isNotEmpty()) {
                WidgetStore.bumpTodayRevision(context)
                updateWidgets(context, manager, ids)
            }
            return ids
        }

        internal fun updateWidgetById(
            context: Context,
            appWidgetId: Int,
            notifyList: Boolean = true,
        ) {
            val appContext = context.applicationContext
            val manager = AppWidgetManager.getInstance(appContext)
            val snapshot = WidgetStore.loadSnapshot(appContext)
            val options = manager.getAppWidgetOptions(appWidgetId)
            updateWidgetWithSnapshot(
                appContext,
                manager,
                appWidgetId,
                options,
                snapshot,
                notifyList = notifyList,
            )
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
            notifyList: Boolean = true,
        ) {
            val style = snapshot?.styleOf(KIND_TODAY) ?: WidgetStyleData.defaultFor(KIND_TODAY)
            val theme = WidgetThemeResolver.resolve(context, style)
            val nowMs = System.currentTimeMillis()
            val vm = WidgetContentResolver.resolveToday(snapshot, style, nowMs)
            WidgetStore.saveTodayHeaderSig(context, appWidgetId, headerSignature(vm, style))

            val (wDp, hDp) = WidgetBackgroundRenderer.resolveSizeDp(context, options, 260, 140)
            WidgetStore.saveTodayWidthDp(context, appWidgetId, wDp)
            val isNarrow = TodayItemViewBinder.isNarrowWidth(wDp)

            val views = RemoteViews(context.packageName, R.layout.widget_today)
            if (style.backgroundOpacity <= 0.01f) {
                views.setViewVisibility(R.id.widget_today_bg, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_today_bg, View.VISIBLE)
                val bgBitmap = WidgetBackgroundRenderer.render(context, style, theme, wDp, hDp)
                views.setImageViewBitmap(R.id.widget_today_bg, bgBitmap)
            }

            val compact = style.density == "compact"
            val density = context.resources.displayMetrics.density
            fun dpPx(v: Float): Int = (v * density).roundToInt()

            val hasVisibleCard = style.backgroundOpacity > 0.01f
            val clearance = WidgetBackgroundRenderer.cornerClearanceDp(style)
            val baseH = when {
                isNarrow && compact -> 6.5f
                isNarrow -> 8.5f
                compact -> 8.5f
                else -> 11.5f
            }
            val baseV = when {
                isNarrow && compact -> 5.5f
                isNarrow -> 7.5f
                compact -> 7.0f
                else -> 10.0f
            }
            val padH = dpPx(maxOf(baseH, clearance + 1.5f))
            val padTop = dpPx(maxOf(baseV, clearance))
            // 去除下方空白白边：内容直抵 1dp 外描边内缘（0% 透明直接到 0）。
            val padBottom = dpPx(if (hasVisibleCard) 1f else 0f)
            views.setViewPadding(R.id.widget_today_content, padH, padTop, padH, padBottom)

            if (style.showHeader) {
                views.setViewVisibility(R.id.widget_today_header, View.VISIBLE)
                views.setViewVisibility(R.id.widget_today_compact_cue_box, View.GONE)
                views.setViewPadding(
                    R.id.widget_today_header,
                    0,
                    0,
                    0,
                    dpPx(if (compact) 3.5f else 5.5f),
                )

                if (vm.badgeText.isNotEmpty()) {
                    views.setViewVisibility(R.id.widget_today_header_badge, View.VISIBLE)
                    views.setTextViewText(R.id.widget_today_header_badge, vm.badgeText)
                    WidgetThemeResolver.applyPill(views, R.id.widget_today_header_badge, theme, vm.badgeTone)
                    views.setViewPadding(
                        R.id.widget_today_header_badge,
                        dpPx(5.5f),
                        dpPx(1.5f),
                        dpPx(5.5f),
                        dpPx(1.5f),
                    )
                    views.setTextViewTextSize(
                        R.id.widget_today_header_badge,
                        TypedValue.COMPLEX_UNIT_DIP,
                        (if (isNarrow) 8.5f else 9.2f) * style.fontScale,
                    )
                } else {
                    views.setViewVisibility(R.id.widget_today_header_badge, View.GONE)
                }

                views.setTextViewText(R.id.widget_today_title, vm.headerTitle)
                views.setTextColor(
                    R.id.widget_today_title,
                    if (vm.isTomorrow) theme.primaryTextColor else theme.accentColor,
                )
                views.setTextViewTextSize(
                    R.id.widget_today_title,
                    TypedValue.COMPLEX_UNIT_DIP,
                    (if (isNarrow) 10.5f else 11.5f) * style.fontScale,
                )

                if (vm.headerRight.isNotEmpty()) {
                    views.setViewVisibility(R.id.widget_today_subtitle, View.VISIBLE)
                    views.setTextViewText(R.id.widget_today_subtitle, vm.headerRight)
                    views.setTextColor(R.id.widget_today_subtitle, theme.secondaryTextColor)
                    views.setTextViewTextSize(
                        R.id.widget_today_subtitle,
                        TypedValue.COMPLEX_UNIT_DIP,
                        (if (isNarrow) 9.2f else 10.0f) * style.fontScale,
                    )
                } else {
                    views.setViewVisibility(R.id.widget_today_subtitle, View.GONE)
                }
            } else {
                views.setViewVisibility(R.id.widget_today_header, View.GONE)
                // 即使关闭顶部标题栏，展示明日预告时仍保留精简明日提示，防止误把明日当今日。
                if (vm.isTomorrow && vm.compactCue.isNotEmpty()) {
                    views.setViewVisibility(R.id.widget_today_compact_cue_box, View.VISIBLE)
                    views.setTextViewText(R.id.widget_today_compact_cue, vm.compactCue)
                    WidgetThemeResolver.applyPill(views, R.id.widget_today_compact_cue, theme, WidgetPillTone.TOMORROW)
                    views.setViewPadding(
                        R.id.widget_today_compact_cue,
                        dpPx(5f),
                        dpPx(1f),
                        dpPx(5f),
                        dpPx(1f),
                    )
                    views.setTextViewTextSize(
                        R.id.widget_today_compact_cue,
                        TypedValue.COMPLEX_UNIT_DIP,
                        (if (isNarrow) 8.2f else 8.8f) * style.fontScale,
                    )
                } else {
                    views.setViewVisibility(R.id.widget_today_compact_cue_box, View.GONE)
                }
            }

            if (vm.items.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_today_list, View.VISIBLE)
                views.setViewVisibility(R.id.widget_today_empty_box, View.GONE)
                views.setViewVisibility(R.id.widget_today_exam_box, View.GONE)
                bindListItems(context, manager, views, appWidgetId, vm.items, style, theme, nowMs, isNarrow, notifyList)
            } else if (vm.examBanner != null) {
                views.setViewVisibility(R.id.widget_today_list, View.GONE)
                views.setViewVisibility(R.id.widget_today_empty_box, View.GONE)
                views.setViewVisibility(R.id.widget_today_exam_box, View.VISIBLE)
                bindExamBanner(context, views, vm.examBanner, style, theme, nowMs, isNarrow)
            } else {
                views.setViewVisibility(R.id.widget_today_list, View.GONE)
                views.setViewVisibility(R.id.widget_today_exam_box, View.GONE)
                views.setViewVisibility(R.id.widget_today_empty_box, View.VISIBLE)
                views.setTextViewText(R.id.widget_today_empty_text, vm.emptyMessage)
                views.setTextColor(R.id.widget_today_empty_text, theme.secondaryTextColor)
                views.setTextViewTextSize(
                    R.id.widget_today_empty_text,
                    TypedValue.COMPLEX_UNIT_DIP,
                    (if (isNarrow) 10.5f else 11.8f) * style.fontScale,
                )
            }

            views.setOnClickPendingIntent(
                R.id.widget_today_root,
                WidgetCoordinator.createLaunchPendingIntent(context),
            )
            manager.updateAppWidget(appWidgetId, views)
        }

        private fun bindListItems(
            context: Context,
            manager: AppWidgetManager,
            views: RemoteViews,
            appWidgetId: Int,
            items: List<TimelineItemData>,
            style: WidgetStyleData,
            theme: ResolvedWidgetTheme,
            nowMs: Long,
            isNarrow: Boolean,
            notifyList: Boolean,
        ) {
            views.setPendingIntentTemplate(
                R.id.widget_today_list,
                WidgetCoordinator.createLaunchTemplatePendingIntent(context),
            )
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                val builder = RemoteViews.RemoteCollectionItems.Builder()
                    .setHasStableIds(false)
                    .setViewTypeCount(1)
                for (i in items.indices) {
                    builder.addItem(
                        i.toLong(),
                        TodayItemViewBinder.buildItemView(context, items[i], style, theme, nowMs, isNarrow),
                    )
                }
                views.setRemoteAdapter(R.id.widget_today_list, builder.build())
            } else {
                val rev = WidgetStore.loadTodayRevision(context)
                val serviceIntent = Intent(context, TodayWidgetService::class.java).apply {
                    putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
                    data = Uri.parse("qust://today_widget/$appWidgetId?rev=$rev")
                }
                @Suppress("DEPRECATION")
                views.setRemoteAdapter(R.id.widget_today_list, serviceIntent)
                if (notifyList) {
                    @Suppress("DEPRECATION")
                    manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.widget_today_list)
                }
            }
        }

        private fun bindExamBanner(
            context: Context,
            views: RemoteViews,
            exam: UpcomingExamData,
            style: WidgetStyleData,
            theme: ResolvedWidgetTheme,
            nowMs: Long,
            isNarrow: Boolean,
        ) {
            val density = context.resources.displayMetrics.density
            val cardPadPx = ((if (isNarrow) 8f else 10f) * density).roundToInt()
            val fallbackCard = if (theme.isDark) R.drawable.widget_exam_card_dark else R.drawable.widget_exam_card_light
            WidgetThemeResolver.applyRoundedBackground(
                views = views,
                viewId = R.id.widget_today_exam_card,
                bgColor = theme.examCardBgColor,
                baseDrawableRes = R.drawable.widget_exam_card_bg,
                fallbackDrawableRes = fallbackCard,
            )
            views.setViewPadding(R.id.widget_today_exam_card, cardPadPx, cardPadPx, cardPadPx, cardPadPx)

            val days = WidgetContentResolver.calendarDayDiff(nowMs, exam.startMs)
            val countdown = if (days <= 0) "今天考试" else "还有 ${days} 天"
            val weekPart = if (exam.week > 0) {
                " · 第${exam.week}周 ${WidgetContentResolver.weekdayName(exam.weekday)}"
            } else {
                ""
            }
            val prefix = if (style.showHeader) "" else "近期考试 · "
            views.setTextViewText(R.id.widget_today_exam_badge, "$prefix$countdown$weekPart")
            views.setTextColor(R.id.widget_today_exam_badge, theme.examFgColor)
            views.setTextViewTextSize(
                R.id.widget_today_exam_badge,
                TypedValue.COMPLEX_UNIT_DIP,
                (if (isNarrow) 9.2f else 10.0f) * style.fontScale,
            )

            views.setTextViewText(R.id.widget_today_exam_title, exam.courseName)
            views.setTextColor(R.id.widget_today_exam_title, theme.primaryTextColor)
            views.setTextViewTextSize(
                R.id.widget_today_exam_title,
                TypedValue.COMPLEX_UNIT_DIP,
                (if (isNarrow) 11.5f else 13.0f) * style.fontScale,
            )

            val datePart = WidgetContentResolver.shortMonthDay(exam.dateIso)
            val timePart = "$datePart ${exam.timeLabel}".trim()
            val meta = listOfNotNull(
                timePart.takeIf { style.showTime && it.isNotEmpty() },
                exam.location.takeIf { style.showLocation && it.isNotEmpty() },
                exam.seatNumber.takeIf { style.showLocation && it.isNotEmpty() }?.let { "${it}座" },
            ).joinToString(" · ")
            if (meta.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_today_exam_meta, View.VISIBLE)
                views.setTextViewText(R.id.widget_today_exam_meta, meta)
                views.setTextColor(R.id.widget_today_exam_meta, theme.secondaryTextColor)
                views.setTextViewTextSize(
                    R.id.widget_today_exam_meta,
                    TypedValue.COMPLEX_UNIT_DIP,
                    (if (isNarrow) 9.2f else 10.2f) * style.fontScale,
                )
            } else {
                views.setViewVisibility(R.id.widget_today_exam_meta, View.GONE)
            }
        }
    }
}
