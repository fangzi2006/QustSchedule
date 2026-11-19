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
import kotlin.math.roundToInt

class NextClassWidgetProvider : AppWidgetProvider() {

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

            val (wDp, hDp) = WidgetBackgroundRenderer.resolveSizeDp(context, options, 150, 140)
            val views = buildRemoteViews(context, style, theme, vm, wDp, hDp)
            views.setOnClickPendingIntent(
                R.id.widget_next_root,
                WidgetCoordinator.createLaunchPendingIntent(context),
            )
            manager.updateAppWidget(appWidgetId, views)
        }

        internal fun buildRemoteViews(
            context: Context,
            style: WidgetStyleData,
            theme: ResolvedWidgetTheme,
            vm: NextWidgetViewModel,
            wDp: Int,
            hDp: Int,
        ): RemoteViews {
            // 覆盖 2×1 / 3×1 / 4×1 / 2×2 / 4×2 全部桌面栅格尺寸：
            // hDp < 100 统一走双栏 2 行条形布局，杜绝 4×1 / 2×1 纵向截断。
            val isStrip = hDp < 100
            val isUltraCompactStrip = isStrip && wDp < 195
            val isSpaciousTall = !isStrip && wDp >= 220

            val layoutId = if (isStrip) R.layout.widget_next_wide else R.layout.widget_next
            val views = RemoteViews(context.packageName, layoutId)
            if (style.backgroundOpacity <= 0.01f) {
                views.setViewVisibility(R.id.widget_next_bg, View.GONE)
            } else {
                views.setViewVisibility(R.id.widget_next_bg, View.VISIBLE)
                val bgBitmap = WidgetBackgroundRenderer.render(context, style, theme, wDp, hDp)
                views.setImageViewBitmap(R.id.widget_next_bg, bgBitmap)
            }

            val density = context.resources.displayMetrics.density
            fun dpPx(v: Float): Int = (v * density).roundToInt()

            val clearance = WidgetBackgroundRenderer.cornerClearanceDp(style)
            val padH: Int
            val padV: Int
            if (isStrip) {
                val stripCornerH = if (style.backgroundOpacity <= 0.01f) 0f else style.cornerRadius * 0.45f
                padH = dpPx(maxOf(if (isUltraCompactStrip) 9f else 12f, stripCornerH))
                padV = dpPx(if (hDp < 60) 4.0f else 6.0f)
            } else {
                padH = dpPx(maxOf(if (isSpaciousTall) 14f else 12f, clearance + 2f))
                padV = dpPx(maxOf(if (hDp < 130) 8.5f else 11f, clearance + 1f))
            }
            views.setViewPadding(R.id.widget_next_content, padH, padV, padH, padV)

            // 左侧自适应圆角竖条：空态/未登录/过期使用中性灰，课程用课表色板，考试用琥珀橙。
            val barColor = when {
                !vm.hasCourseAccent -> theme.neutralBarColor
                vm.isExam -> theme.examFgColor
                else -> theme.courseColor(vm.colorIndex).foreground
            }
            WidgetThemeResolver.applyVerticalBar(views, R.id.widget_next_bar, barColor, 255)

            // 状态胶囊始终显示，按不同场景区分语义色，杜绝把进行中/今日/明日/考试混淆。
            val pillTone = when (vm.statusKind) {
                NextStatusKind.ONGOING -> WidgetPillTone.ONGOING
                NextStatusKind.TODAY -> WidgetPillTone.ACCENT
                NextStatusKind.TOMORROW -> WidgetPillTone.TOMORROW
                NextStatusKind.EXAM_ONGOING,
                NextStatusKind.EXAM_UPCOMING,
                -> WidgetPillTone.EXAM
                NextStatusKind.EMPTY,
                NextStatusKind.SIGNED_OUT,
                NextStatusKind.STALE,
                -> WidgetPillTone.NEUTRAL
            }
            views.setViewVisibility(R.id.widget_next_badge, View.VISIBLE)
            views.setTextViewText(
                R.id.widget_next_badge,
                if (isUltraCompactStrip) vm.shortBadge else vm.badge,
            )
            WidgetThemeResolver.applyPill(views, R.id.widget_next_badge, theme, pillTone)
            val pillHPad = dpPx(if (isUltraCompactStrip) 5f else if (isStrip) 6f else 7f)
            val pillVPad = dpPx(if (isStrip) 1.5f else 2f)
            views.setViewPadding(R.id.widget_next_badge, pillHPad, pillVPad, pillHPad, pillVPad)
            views.setTextViewTextSize(
                R.id.widget_next_badge,
                TypedValue.COMPLEX_UNIT_DIP,
                (if (isUltraCompactStrip) 8.5f else if (isStrip) 9.0f else 9.5f) * style.fontScale,
            )

            // 标题
            val titleDp = when {
                isUltraCompactStrip -> 11.5f
                isStrip -> 13.0f
                isSpaciousTall -> 15.0f
                else -> 13.8f
            } * style.fontScale
            views.setTextViewText(R.id.widget_next_title, vm.title)
            views.setTextColor(R.id.widget_next_title, theme.primaryTextColor)
            views.setTextViewTextSize(R.id.widget_next_title, TypedValue.COMPLEX_UNIT_DIP, titleDp)

            // 时间与日期提示
            val timeColor = when (vm.statusKind) {
                NextStatusKind.ONGOING -> theme.ongoingFgColor
                NextStatusKind.EXAM_ONGOING,
                NextStatusKind.EXAM_UPCOMING,
                -> theme.examFgColor
                NextStatusKind.TOMORROW -> theme.tomorrowFgColor
                else -> theme.accentColor
            }
            if (!isStrip) {
                if (vm.dateHint.isNotEmpty()) {
                    views.setViewVisibility(R.id.widget_next_date_hint, View.VISIBLE)
                    views.setTextViewText(R.id.widget_next_date_hint, vm.dateHint)
                    views.setTextColor(R.id.widget_next_date_hint, theme.secondaryTextColor)
                    views.setTextViewTextSize(
                        R.id.widget_next_date_hint,
                        TypedValue.COMPLEX_UNIT_DIP,
                        9.5f * style.fontScale,
                    )
                } else {
                    views.setViewVisibility(R.id.widget_next_date_hint, View.GONE)
                }

                if (style.showTime && vm.timeText.isNotEmpty()) {
                    views.setViewVisibility(R.id.widget_next_time, View.VISIBLE)
                    views.setTextViewText(R.id.widget_next_time, vm.timeText)
                    views.setTextColor(R.id.widget_next_time, timeColor)
                    views.setTextViewTextSize(
                        R.id.widget_next_time,
                        TypedValue.COMPLEX_UNIT_DIP,
                        (if (isSpaciousTall) 12.5f else 11.8f) * style.fontScale,
                    )
                } else {
                    views.setViewVisibility(R.id.widget_next_time, View.GONE)
                }
            } else {
                val stripTime = when {
                    !style.showTime -> ""
                    vm.dateHint.isNotEmpty() && vm.timeText.isNotEmpty() -> {
                        val md = vm.dateHint.substringBefore(' ')
                        val startHm = vm.timeText.substringBefore('-')
                        if (isUltraCompactStrip) md else "$md $startHm"
                    }
                    // 极窄 2×1 条形（< 170dp）右栏放 11 字符起止时间会挤压课名至几乎不可读，仅此档缩至开始时间；
                    // 3×1 / 4×1 / 2×2 / 4×2 一律完整展示起止时间。
                    wDp < 170 && vm.timeText.contains('-') -> vm.timeText.substringBefore('-')
                    else -> vm.timeText
                }
                if (stripTime.isNotEmpty()) {
                    views.setViewVisibility(R.id.widget_next_time, View.VISIBLE)
                    views.setTextViewText(R.id.widget_next_time, stripTime)
                    views.setTextColor(R.id.widget_next_time, timeColor)
                    views.setTextViewTextSize(
                        R.id.widget_next_time,
                        TypedValue.COMPLEX_UNIT_DIP,
                        (if (isUltraCompactStrip) 9.5f else 11.0f) * style.fontScale,
                    )
                } else {
                    views.setViewVisibility(R.id.widget_next_time, View.GONE)
                }
            }

            // 副标题（地点 · 教师）
            if (vm.subtitle.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_next_subtitle, View.VISIBLE)
                views.setTextViewText(R.id.widget_next_subtitle, vm.subtitle)
                views.setTextColor(R.id.widget_next_subtitle, theme.secondaryTextColor)
                views.setTextViewTextSize(
                    R.id.widget_next_subtitle,
                    TypedValue.COMPLEX_UNIT_DIP,
                    (if (isUltraCompactStrip) 9.5f else 10.5f) * style.fontScale,
                )
            } else {
                views.setViewVisibility(R.id.widget_next_subtitle, View.GONE)
            }

            return views
        }
    }
}
