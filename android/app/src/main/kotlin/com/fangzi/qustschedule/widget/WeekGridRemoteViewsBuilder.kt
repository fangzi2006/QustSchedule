package com.fangzi.qustschedule.widget

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.text.LineBreaker
import android.text.Layout
import android.text.SpannableString
import android.text.Spanned
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import android.text.style.StyleSpan
import android.util.TypedValue
import android.view.View
import android.widget.RemoteViews
import com.fangzi.qustschedule.R
import kotlin.math.roundToInt

/**
 * 纯原生 RemoteViews 整周课表网格构建器（零位图渲染）。
 *
 * 1) 卡片底色使用 6 档纯矢量 `<shape>` + `setColorFilter`/`setImageAlpha`，
 *    在 API 24–36 上零 Bitmap 分配即可支持任意 0–100% 不透明度与深浅/莫奈主题色；
 * 2) 星期表头、左侧节次轴与 5/7 天课程列全量由原生 `LinearLayout` 权重槽位与 `TextView` 构成，
 *    彻底消除 4×4 大位图在桌面退场缩放动画期间的纹理采样卡顿；
 * 3) 课程块内文字行数预算（`solveCourseBlockPlan`）严格沿用原三段式求解算法
 *    （课名 → 教师 → 地点），将求解后的 `maxLines` 直接绑定至原生 `TextView`。
 */
internal object WeekGridRemoteViewsBuilder {

    private val DAY_BOX_IDS = intArrayOf(
        R.id.widget_week_day_box_1,
        R.id.widget_week_day_box_2,
        R.id.widget_week_day_box_3,
        R.id.widget_week_day_box_4,
        R.id.widget_week_day_box_5,
        R.id.widget_week_day_box_6,
        R.id.widget_week_day_box_7,
    )

    private val DAY_TEXT_IDS = intArrayOf(
        R.id.widget_week_day_1,
        R.id.widget_week_day_2,
        R.id.widget_week_day_3,
        R.id.widget_week_day_4,
        R.id.widget_week_day_5,
        R.id.widget_week_day_6,
        R.id.widget_week_day_7,
    )

    private val DAY_COL_IDS = intArrayOf(
        R.id.widget_week_col_1,
        R.id.widget_week_col_2,
        R.id.widget_week_col_3,
        R.id.widget_week_col_4,
        R.id.widget_week_col_5,
        R.id.widget_week_col_6,
        R.id.widget_week_col_7,
    )

    private val DAY_LABELS = arrayOf("一", "二", "三", "四", "五", "六", "日")

    fun build(
        context: Context,
        style: WidgetStyleData,
        theme: ResolvedWidgetTheme,
        viewModel: WeekWidgetViewModel,
        widthDp: Int,
        heightDp: Int,
    ): RemoteViews {
        val pkg = context.packageName
        val views = RemoteViews(pkg, R.layout.widget_week)
        val density = context.resources.displayMetrics.density.coerceAtLeast(1f)
        fun dpPx(v: Float): Int = (v * density).roundToInt()

        val hasVisibleCard = style.backgroundOpacity > 0.01f
        if (hasVisibleCard) {
            views.setViewVisibility(android.R.id.background, View.VISIBLE)
            views.setImageViewResource(android.R.id.background, cardShapeDrawableRes(style.cornerRadius))
            views.setInt(android.R.id.background, "setColorFilter", theme.surfaceColor or 0xFF000000.toInt())
            views.setInt(android.R.id.background, "setImageAlpha", Color.alpha(theme.surfaceColor))
        } else {
            views.setViewVisibility(android.R.id.background, View.GONE)
            views.setImageViewResource(android.R.id.background, 0)
        }

        val compact = style.density == "compact"
        val clearance = WidgetBackgroundRenderer.cornerClearanceDp(style)
        val padHDp = maxOf(if (compact) 6.0f else 9.0f, clearance)
        val padTopDp = maxOf(if (compact) 5.5f else 8.5f, clearance)
        val padBottomDp = if (hasVisibleCard) maxOf(4.0f, clearance * 0.55f) else 0f
        views.setViewPadding(
            R.id.widget_week_content,
            dpPx(padHDp),
            dpPx(padTopDp),
            dpPx(padHDp),
            dpPx(padBottomDp),
        )

        // 未登录 / 过期 / 学期已结束 / 无课表占位
        val weekPlan = viewModel.weekPlan
        if (!viewModel.signedIn || viewModel.isStale || viewModel.isTermEnded || weekPlan == null) {
            views.setViewVisibility(R.id.widget_week_header, View.GONE)
            views.setViewVisibility(R.id.widget_week_weekdays, View.GONE)
            views.setViewVisibility(R.id.widget_week_grid_body, View.GONE)
            views.setViewVisibility(R.id.widget_week_empty_box, View.VISIBLE)

            val titleText = when {
                !viewModel.signedIn -> "轻触打开青科课表通登录"
                viewModel.isStale -> "课表数据已过期"
                viewModel.isTermEnded -> "本学期课程已结束"
                else -> "当前周暂无课表"
            }
            val subText = when {
                viewModel.isStale -> "轻触打开青科课表通自动刷新"
                viewModel.isTermEnded -> "切换新学期课表后自动展示"
                else -> "课表同步后自动展示整周网格"
            }
            views.setTextViewText(R.id.widget_week_empty_title, titleText)
            views.setTextColor(R.id.widget_week_empty_title, theme.primaryTextColor)
            views.setTextViewTextSize(
                R.id.widget_week_empty_title,
                TypedValue.COMPLEX_UNIT_DIP,
                12f * style.fontScale,
            )
            views.setViewVisibility(R.id.widget_week_empty_sub, View.VISIBLE)
            views.setTextViewText(R.id.widget_week_empty_sub, subText)
            views.setTextColor(R.id.widget_week_empty_sub, theme.secondaryTextColor)
            views.setTextViewTextSize(
                R.id.widget_week_empty_sub,
                TypedValue.COMPLEX_UNIT_DIP,
                10.5f * style.fontScale,
            )
            return views
        }

        val dayCount = if (viewModel.showWeekend) 7 else 5
        val maxSection = weekPlan.maxSection.coerceIn(6, 14)

        // 1. 顶部标题栏
        if (style.showHeader) {
            views.setViewVisibility(R.id.widget_week_header, View.VISIBLE)
            views.setViewPadding(
                R.id.widget_week_header,
                dpPx(if (hasVisibleCard) 2.5f else 0f),
                0,
                0,
                dpPx(if (compact) 2.5f else 4.5f),
            )
            views.setTextViewText(R.id.widget_week_title, "第 ${weekPlan.week} 周")
            views.setTextColor(R.id.widget_week_title, theme.accentColor)
            views.setTextViewTextSize(
                R.id.widget_week_title,
                TypedValue.COMPLEX_UNIT_DIP,
                11f * style.fontScale,
            )
            if (viewModel.dateRange.isNotEmpty()) {
                views.setViewVisibility(R.id.widget_week_range, View.VISIBLE)
                views.setTextViewText(R.id.widget_week_range, viewModel.dateRange)
                views.setTextColor(R.id.widget_week_range, theme.secondaryTextColor)
                views.setTextViewTextSize(
                    R.id.widget_week_range,
                    TypedValue.COMPLEX_UNIT_DIP,
                    9.2f * style.fontScale,
                )
            } else {
                views.setViewVisibility(R.id.widget_week_range, View.GONE)
            }
        } else {
            views.setViewVisibility(R.id.widget_week_header, View.GONE)
        }

        // 2. 单行星期表头（仅在真实当前周高亮今日胶囊）
        views.setViewVisibility(R.id.widget_week_weekdays, View.VISIBLE)
        if (style.showTime) {
            views.setViewVisibility(R.id.widget_week_axis_spacer, View.INVISIBLE)
            views.setTextViewText(R.id.widget_week_axis_spacer, maxSection.toString())
            views.setTextViewTextSize(
                R.id.widget_week_axis_spacer,
                TypedValue.COMPLEX_UNIT_DIP,
                8.0f * style.fontScale,
            )
        } else {
            views.setViewVisibility(R.id.widget_week_axis_spacer, View.GONE)
        }

        for (d in 1..7) {
            val boxId = DAY_BOX_IDS[d - 1]
            val textId = DAY_TEXT_IDS[d - 1]
            if (d > dayCount) {
                views.setViewVisibility(boxId, View.GONE)
                continue
            }
            views.setViewVisibility(boxId, View.VISIBLE)
            val isToday = viewModel.isCurrentWeek && d == viewModel.todayWeekday
            val label = DAY_LABELS[d - 1]
            views.setTextViewTextSize(
                textId,
                TypedValue.COMPLEX_UNIT_DIP,
                8.8f * style.fontScale,
            )
            if (isToday) {
                val boldLabel = SpannableString(label).apply {
                    setSpan(StyleSpan(Typeface.BOLD), 0, length, Spanned.SPAN_EXCLUSIVE_EXCLUSIVE)
                }
                views.setTextViewText(textId, boldLabel)
                WidgetThemeResolver.applyPill(views, textId, theme, WidgetPillTone.ACCENT)
            } else {
                views.setTextViewText(textId, label)
                views.setTextColor(textId, theme.secondaryTextColor)
                WidgetThemeResolver.clearBackground(views, textId)
            }
        }

        // 空周 / 仅周末有课但隐藏周末列时的友好提示
        val hasVisibleBlock = weekPlan.blocks.any {
            it.day in 1..dayCount && it.startPeriod in 1..maxSection
        }
        if (!hasVisibleBlock) {
            views.setViewVisibility(R.id.widget_week_grid_body, View.GONE)
            views.setViewVisibility(R.id.widget_week_empty_box, View.VISIBLE)
            val emptyMsg = if (weekPlan.blocks.isEmpty()) "本周无课，好好休息" else "工作日无课，周末有安排"
            views.setTextViewText(R.id.widget_week_empty_title, emptyMsg)
            views.setTextColor(R.id.widget_week_empty_title, theme.secondaryTextColor)
            views.setTextViewTextSize(
                R.id.widget_week_empty_title,
                TypedValue.COMPLEX_UNIT_DIP,
                11.5f * style.fontScale,
            )
            views.setViewVisibility(R.id.widget_week_empty_sub, View.GONE)
            return views
        }

        views.setViewVisibility(R.id.widget_week_empty_box, View.GONE)
        views.setViewVisibility(R.id.widget_week_grid_body, View.VISIBLE)

        // 3. 左侧节次列
        views.removeAllViews(R.id.widget_week_axis_col)
        if (style.showTime) {
            views.setViewVisibility(R.id.widget_week_axis_col, View.VISIBLE)
            for (p in 1..maxSection) {
                val axisCell = RemoteViews(pkg, R.layout.widget_week_axis_cell)
                axisCell.setTextViewText(R.id.widget_week_axis_text, p.toString())
                axisCell.setTextColor(R.id.widget_week_axis_text, theme.secondaryTextColor)
                axisCell.setTextViewTextSize(
                    R.id.widget_week_axis_text,
                    TypedValue.COMPLEX_UNIT_DIP,
                    8.0f * style.fontScale,
                )
                views.addView(R.id.widget_week_axis_col, axisCell)
            }
        } else {
            views.setViewVisibility(R.id.widget_week_axis_col, View.GONE)
        }

        // 4. 估算单格可用像素尺寸，用于沿用原三段式课程块行数求解器
        val safeWDp = widthDp.coerceAtLeast(160).toFloat()
        val safeHDp = heightDp.coerceAtLeast(140).toFloat()
        val axisWidthDp = if (style.showTime) maxOf(18f, 12f * style.fontScale + 4f) else 0f
        val headerHeightDp = if (style.showHeader) {
            11f * style.fontScale * 1.25f + (if (compact) 2.5f else 4.5f)
        } else {
            0f
        }
        val weekdayHeightDp = 8.8f * style.fontScale * 1.25f + 5.5f
        val gridWidthDp = (safeWDp - padHDp * 2f - axisWidthDp).coerceAtLeast(60f)
        val gridHeightDp = (safeHDp - padTopDp - padBottomDp - headerHeightDp - weekdayHeightDp).coerceAtLeast(60f)
        val colWidthDp = gridWidthDp / dayCount.toFloat()
        val rowHeightDp = gridHeightDp / maxSection.toFloat()

        val titleSizeDp = (if (compact) 8.0f else 8.8f) * style.fontScale
        val detailSizeDp = (if (compact) 6.8f else 7.4f) * style.fontScale
        val titlePaint = newTextPaint(titleSizeDp * density, bold = true)
        val detailPaint = newTextPaint(detailSizeDp * density, bold = false)
        val fieldGapPx = 1.0f * density
        val titleLineMult = 1.12f
        val detailLineMult = 1.10f

        val blocksByDay = Array(8) { ArrayList<WeekBlockData>() }
        for (block in weekPlan.blocks) {
            if (block.day in 1..dayCount && block.startPeriod in 1..maxSection) {
                blocksByDay[block.day].add(block)
            }
        }

        // 5. 逐列构建 5/7 天课程槽位（支持冲突分栏与精准节次权重对齐）
        val todayColFallback = if (theme.isDark) {
            R.drawable.widget_week_today_col_dark
        } else {
            R.drawable.widget_week_today_col_light
        }
        for (d in 1..7) {
            val colId = DAY_COL_IDS[d - 1]
            views.removeAllViews(colId)
            if (d > dayCount) {
                views.setViewVisibility(colId, View.GONE)
                continue
            }
            views.setViewVisibility(colId, View.VISIBLE)
            val isToday = viewModel.isCurrentWeek && d == viewModel.todayWeekday
            if (isToday) {
                WidgetThemeResolver.applyRoundedBackground(
                    views = views,
                    viewId = colId,
                    bgColor = theme.todayColumnHighlightColor,
                    baseDrawableRes = R.drawable.widget_week_today_col_bg,
                    fallbackDrawableRes = todayColFallback,
                )
            } else {
                WidgetThemeResolver.clearBackground(views, colId)
            }

            val dayBlocks = blocksByDay[d]
            if (dayBlocks.isEmpty()) {
                addSpacers(views, colId, pkg, maxSection)
                continue
            }

            dayBlocks.sortWith(
                compareBy<WeekBlockData>(
                    { it.startPeriod },
                    { it.conflictIndex },
                    { it.endPeriod },
                ),
            )

            // 合并存在节次重叠的课程簇
            val clusters = ArrayList<BlockCluster>()
            for (b in dayBlocks) {
                val bEnd = b.endPeriod.coerceIn(b.startPeriod, maxSection)
                val last = clusters.lastOrNull()
                if (last != null && b.startPeriod <= last.endPeriod) {
                    if (bEnd > last.endPeriod) last.endPeriod = bEnd
                    last.blocks.add(b)
                } else {
                    val list = ArrayList<WeekBlockData>(2)
                    list.add(b)
                    clusters.add(BlockCluster(b.startPeriod, bEnd, list))
                }
            }

            var cursor = 1
            for (cluster in clusters) {
                if (cluster.startPeriod > cursor) {
                    addSpacers(views, colId, pkg, cluster.startPeriod - cursor)
                }
                val clusterSpan = cluster.endPeriod - cluster.startPeriod + 1
                if (cluster.blocks.size == 1) {
                    val b = cluster.blocks[0]
                    addSingleBlockWithWeight(
                        parentViews = views,
                        parentId = colId,
                        pkg = pkg,
                        block = b,
                        span = clusterSpan,
                        colWidthDp = colWidthDp,
                        rowHeightDp = rowHeightDp,
                        density = density,
                        style = style,
                        theme = theme,
                        titleSizeDp = titleSizeDp,
                        detailSizeDp = detailSizeDp,
                        titlePaint = titlePaint,
                        detailPaint = detailPaint,
                        fieldGapPx = fieldGapPx,
                        titleLineMult = titleLineMult,
                        detailLineMult = detailLineMult,
                    )
                } else if (clusterSpan <= 6) {
                    val clusterViews = RemoteViews(pkg, clusterLayoutForSpan(clusterSpan))
                    val lanes = buildConflictLanes(cluster.blocks, maxSection)
                    val laneCount = lanes.size.coerceAtLeast(1)
                    val laneWidthDp = colWidthDp / laneCount.toFloat()
                    for (lane in lanes) {
                        val subCol = RemoteViews(pkg, R.layout.widget_week_subcol)
                        var laneCursor = cluster.startPeriod
                        for (b in lane) {
                            val bStart = b.startPeriod.coerceIn(laneCursor, cluster.endPeriod)
                            val bEnd = b.endPeriod.coerceIn(bStart, cluster.endPeriod)
                            if (bStart > laneCursor) {
                                addSpacers(subCol, R.id.widget_week_subcol, pkg, bStart - laneCursor)
                            }
                            val bSpan = bEnd - bStart + 1
                            addSingleBlockWithWeight(
                                parentViews = subCol,
                                parentId = R.id.widget_week_subcol,
                                pkg = pkg,
                                block = b,
                                span = bSpan,
                                colWidthDp = laneWidthDp,
                                rowHeightDp = rowHeightDp,
                                density = density,
                                style = style,
                                theme = theme,
                                titleSizeDp = titleSizeDp,
                                detailSizeDp = detailSizeDp,
                                titlePaint = titlePaint,
                                detailPaint = detailPaint,
                                fieldGapPx = fieldGapPx,
                                titleLineMult = titleLineMult,
                                detailLineMult = detailLineMult,
                            )
                            laneCursor = bEnd + 1
                        }
                        if (laneCursor <= cluster.endPeriod) {
                            addSpacers(subCol, R.id.widget_week_subcol, pkg, cluster.endPeriod - laneCursor + 1)
                        }
                        clusterViews.addView(R.id.widget_week_cluster, subCol)
                    }
                    views.addView(colId, clusterViews)
                } else {
                    // 极罕见的超长（>6 节）重叠簇：渲染第一条非重叠主泳道以保证总权重严格对齐。
                    val primaryLane = buildConflictLanes(cluster.blocks, maxSection).firstOrNull().orEmpty()
                    var laneCursor = cluster.startPeriod
                    for (b in primaryLane) {
                        val bStart = b.startPeriod.coerceIn(laneCursor, cluster.endPeriod)
                        val bEnd = b.endPeriod.coerceIn(bStart, cluster.endPeriod)
                        if (bStart > laneCursor) {
                            addSpacers(views, colId, pkg, bStart - laneCursor)
                        }
                        addSingleBlockWithWeight(
                            parentViews = views,
                            parentId = colId,
                            pkg = pkg,
                            block = b,
                            span = bEnd - bStart + 1,
                            colWidthDp = colWidthDp,
                            rowHeightDp = rowHeightDp,
                            density = density,
                            style = style,
                            theme = theme,
                            titleSizeDp = titleSizeDp,
                            detailSizeDp = detailSizeDp,
                            titlePaint = titlePaint,
                            detailPaint = detailPaint,
                            fieldGapPx = fieldGapPx,
                            titleLineMult = titleLineMult,
                            detailLineMult = detailLineMult,
                        )
                        laneCursor = bEnd + 1
                    }
                    if (laneCursor <= cluster.endPeriod) {
                        addSpacers(views, colId, pkg, cluster.endPeriod - laneCursor + 1)
                    }
                }
                cursor = cluster.endPeriod + 1
            }
            if (cursor <= maxSection) {
                addSpacers(views, colId, pkg, maxSection - cursor + 1)
            }
        }

        return views
    }

    private class BlockCluster(
        val startPeriod: Int,
        var endPeriod: Int,
        val blocks: ArrayList<WeekBlockData>,
    )

    private fun buildConflictLanes(
        blocks: List<WeekBlockData>,
        maxSection: Int,
    ): List<List<WeekBlockData>> {
        val lanes = ArrayList<ArrayList<WeekBlockData>>()
        val laneEnds = ArrayList<Int>()
        for (b in blocks) {
            val bEnd = b.endPeriod.coerceIn(b.startPeriod, maxSection)
            var placed = false
            for (i in lanes.indices) {
                if (b.startPeriod > laneEnds[i]) {
                    lanes[i].add(b)
                    laneEnds[i] = bEnd
                    placed = true
                    break
                }
            }
            if (!placed) {
                val newLane = ArrayList<WeekBlockData>(2)
                newLane.add(b)
                lanes.add(newLane)
                laneEnds.add(bEnd)
            }
        }
        return lanes
    }

    private fun addSingleBlockWithWeight(
        parentViews: RemoteViews,
        parentId: Int,
        pkg: String,
        block: WeekBlockData,
        span: Int,
        colWidthDp: Float,
        rowHeightDp: Float,
        density: Float,
        style: WidgetStyleData,
        theme: ResolvedWidgetTheme,
        titleSizeDp: Float,
        detailSizeDp: Float,
        titlePaint: TextPaint,
        detailPaint: TextPaint,
        fieldGapPx: Float,
        titleLineMult: Float,
        detailLineMult: Float,
    ) {
        val clampedSpan = span.coerceIn(1, 6)
        val blockViews = RemoteViews(pkg, blockLayoutForSpan(clampedSpan))
        val chip = theme.courseColor(block.colorIndex)

        blockViews.setInt(
            R.id.widget_week_block_bg,
            "setColorFilter",
            chip.background or 0xFF000000.toInt(),
        )

        val titleText = block.name.trim()
        val teacherText = if (style.showTeacher) block.teacher.trim() else ""
        val locationText = if (style.showLocation) block.location.trim() else ""

        // 扣除外层 1dp 间距与内层 2dp×1.5dp 内边距，严格按真实可用像素执行三段式行数预算求解
        val availWPx = ((colWidthDp - 6.0f).coerceAtLeast(8.0f) * density).roundToInt().coerceAtLeast(4)
        val availHPx = ((rowHeightDp * clampedSpan - 5.0f).coerceAtLeast(6.0f) * density)

        val plan = solveCourseBlockPlan(
            titleText = titleText,
            teacherText = teacherText,
            locationText = locationText,
            widthPx = availWPx,
            availH = availHPx,
            fieldGap = fieldGapPx,
            titlePaint = titlePaint,
            detailPaint = detailPaint,
            titleLineMult = titleLineMult,
            detailLineMult = detailLineMult,
        )

        if (plan.titleLines > 0 && titleText.isNotEmpty()) {
            blockViews.setViewVisibility(R.id.widget_week_block_title, View.VISIBLE)
            blockViews.setTextViewText(R.id.widget_week_block_title, titleText)
            blockViews.setTextColor(R.id.widget_week_block_title, chip.foreground)
            blockViews.setTextViewTextSize(
                R.id.widget_week_block_title,
                TypedValue.COMPLEX_UNIT_DIP,
                titleSizeDp,
            )
            blockViews.setInt(R.id.widget_week_block_title, "setMaxLines", plan.titleLines)
        } else {
            blockViews.setViewVisibility(R.id.widget_week_block_title, View.GONE)
        }

        if (plan.teacherLines > 0 && teacherText.isNotEmpty()) {
            blockViews.setViewVisibility(R.id.widget_week_block_teacher, View.VISIBLE)
            blockViews.setTextViewText(R.id.widget_week_block_teacher, teacherText)
            blockViews.setTextColor(
                R.id.widget_week_block_teacher,
                WidgetThemeResolver.withAlpha(chip.foreground, 0xBD),
            )
            blockViews.setTextViewTextSize(
                R.id.widget_week_block_teacher,
                TypedValue.COMPLEX_UNIT_DIP,
                detailSizeDp,
            )
            blockViews.setInt(R.id.widget_week_block_teacher, "setMaxLines", plan.teacherLines)
        } else {
            blockViews.setViewVisibility(R.id.widget_week_block_teacher, View.GONE)
        }

        if (plan.locationLines > 0 && locationText.isNotEmpty()) {
            blockViews.setViewVisibility(R.id.widget_week_block_location, View.VISIBLE)
            blockViews.setTextViewText(R.id.widget_week_block_location, locationText)
            blockViews.setTextColor(
                R.id.widget_week_block_location,
                WidgetThemeResolver.withAlpha(chip.foreground, 0xCB),
            )
            blockViews.setTextViewTextSize(
                R.id.widget_week_block_location,
                TypedValue.COMPLEX_UNIT_DIP,
                detailSizeDp,
            )
            blockViews.setInt(R.id.widget_week_block_location, "setMaxLines", plan.locationLines)
        } else {
            blockViews.setViewVisibility(R.id.widget_week_block_location, View.GONE)
        }

        if (block.rescheduled) {
            blockViews.setViewVisibility(R.id.widget_week_block_dot, View.VISIBLE)
            blockViews.setInt(
                R.id.widget_week_block_dot,
                "setColorFilter",
                theme.rescheduleDotColor or 0xFF000000.toInt(),
            )
        } else {
            blockViews.setViewVisibility(R.id.widget_week_block_dot, View.GONE)
        }

        parentViews.addView(parentId, blockViews)
        if (span > clampedSpan) {
            addSpacers(parentViews, parentId, pkg, span - clampedSpan)
        }
    }

    private fun addSpacers(
        parentViews: RemoteViews,
        parentId: Int,
        pkg: String,
        totalPeriods: Int,
    ) {
        var remaining = totalPeriods
        while (remaining > 0) {
            val step = when {
                remaining >= 4 -> 4
                else -> remaining
            }
            val layoutId = when (step) {
                4 -> R.layout.widget_week_spacer_w4
                3 -> R.layout.widget_week_spacer_w3
                2 -> R.layout.widget_week_spacer_w2
                else -> R.layout.widget_week_spacer_w1
            }
            parentViews.addView(parentId, RemoteViews(pkg, layoutId))
            remaining -= step
        }
    }

    private fun blockLayoutForSpan(span: Int): Int = when (span) {
        1 -> R.layout.widget_week_block_w1
        2 -> R.layout.widget_week_block_w2
        3 -> R.layout.widget_week_block_w3
        4 -> R.layout.widget_week_block_w4
        5 -> R.layout.widget_week_block_w5
        else -> R.layout.widget_week_block_w6
    }

    private fun clusterLayoutForSpan(span: Int): Int = when (span) {
        1 -> R.layout.widget_week_cluster_w1
        2 -> R.layout.widget_week_cluster_w2
        3 -> R.layout.widget_week_cluster_w3
        4 -> R.layout.widget_week_cluster_w4
        5 -> R.layout.widget_week_cluster_w5
        else -> R.layout.widget_week_cluster_w6
    }

    private fun cardShapeDrawableRes(cornerRadiusDp: Float): Int {
        val bucket = ((cornerRadiusDp - 8f) / 4f).roundToInt().coerceIn(0, 5)
        return when (bucket) {
            0 -> R.drawable.widget_week_card_r8
            1 -> R.drawable.widget_week_card_r12
            2 -> R.drawable.widget_week_card_r16
            3 -> R.drawable.widget_week_card_r20
            4 -> R.drawable.widget_week_card_r24
            else -> R.drawable.widget_week_card_r28
        }
    }

    private data class BlockPlan(
        val titleLines: Int,
        val teacherLines: Int,
        val locationLines: Int,
    )

    private fun solveCourseBlockPlan(
        titleText: String,
        teacherText: String,
        locationText: String,
        widthPx: Int,
        availH: Float,
        fieldGap: Float,
        titlePaint: TextPaint,
        detailPaint: TextPaint,
        titleLineMult: Float,
        detailLineMult: Float,
    ): BlockPlan {
        val titleUnbounded = if (titleText.isNotEmpty()) {
            buildBlockLayout(titleText, titlePaint, widthPx, null, titleLineMult)
        } else {
            null
        }
        val titleNeeded = titleUnbounded?.lineCount ?: 0
        val titleSingleLineH = if (titleUnbounded != null && titleNeeded > 0) {
            titleUnbounded.height.toFloat() / titleNeeded.toFloat()
        } else {
            0f
        }
        val teacherUnbounded = if (teacherText.isNotEmpty()) {
            buildBlockLayout(teacherText, detailPaint, widthPx, null, detailLineMult)
        } else {
            null
        }
        val teacherNeeded = teacherUnbounded?.lineCount ?: 0
        val locationUnbounded = if (locationText.isNotEmpty()) {
            buildBlockLayout(locationText, detailPaint, widthPx, null, detailLineMult)
        } else {
            null
        }
        val locationNeeded = locationUnbounded?.lineCount ?: 0

        var titleLines = titleNeeded
        var teacherLines = teacherNeeded
        var locationLines = locationNeeded

        val titleHeightCache = HashMap<Int, Float>()
        val teacherHeightCache = HashMap<Int, Float>()
        val locationHeightCache = HashMap<Int, Float>()

        fun titleHeight(maxLines: Int): Float {
            if (titleUnbounded == null || maxLines <= 0) return 0f
            if (maxLines >= titleNeeded) return titleUnbounded.height.toFloat()
            return titleHeightCache.getOrPut(maxLines) {
                buildBlockLayout(titleText, titlePaint, widthPx, maxLines, titleLineMult).height.toFloat()
            }
        }

        fun teacherHeight(maxLines: Int): Float {
            if (teacherUnbounded == null || maxLines <= 0) return 0f
            if (maxLines >= teacherNeeded) return teacherUnbounded.height.toFloat()
            return teacherHeightCache.getOrPut(maxLines) {
                buildBlockLayout(teacherText, detailPaint, widthPx, maxLines, detailLineMult).height.toFloat()
            }
        }

        fun locationHeight(maxLines: Int): Float {
            if (locationUnbounded == null || maxLines <= 0) return 0f
            if (maxLines >= locationNeeded) return locationUnbounded.height.toFloat()
            return locationHeightCache.getOrPut(maxLines) {
                buildBlockLayout(locationText, detailPaint, widthPx, maxLines, detailLineMult).height.toFloat()
            }
        }

        fun usedHeight(): Float {
            var activeFields = 0
            if (titleLines > 0) activeFields++
            if (teacherLines > 0) activeFields++
            if (locationLines > 0) activeFields++
            val gaps = if (activeFields > 1) activeFields - 1 else 0
            return titleHeight(titleLines) +
                teacherHeight(teacherLines) +
                locationHeight(locationLines) +
                gaps * fieldGap
        }

        fun fits(): Boolean = usedHeight() <= availH + 0.5f

        while (!fits()) {
            when {
                titleLines > 1 -> titleLines--
                teacherLines > 0 -> teacherLines = 0
                locationLines > 1 -> locationLines--
                locationLines > 0 -> locationLines = 0
                titleLines > 0 -> titleLines = 0
                else -> break
            }
        }

        var changed = true
        while (changed) {
            changed = false
            if (locationLines < locationNeeded) {
                locationLines++
                if (fits()) {
                    changed = true
                    continue
                }
                locationLines--
            }
            if (teacherLines < teacherNeeded) {
                val saved = teacherLines
                teacherLines = teacherNeeded
                if (fits()) {
                    changed = true
                    continue
                }
                teacherLines = saved
            }
            if (titleLines < titleNeeded) {
                titleLines++
                if (fits()) {
                    changed = true
                    continue
                }
                titleLines--
            }
        }

        if (titleLines in titleNeeded until 12 && titleLines > 0 && titleSingleLineH > 0f) {
            val remaining = availH - usedHeight()
            if (remaining > titleSingleLineH) {
                titleLines = (titleLines + (remaining / titleSingleLineH).toInt()).coerceAtMost(12)
            }
        }

        return BlockPlan(
            titleLines = titleLines,
            teacherLines = teacherLines,
            locationLines = locationLines,
        )
    }

    @SuppressLint("InlinedApi")
    private fun buildBlockLayout(
        text: String,
        paint: TextPaint,
        widthPx: Int,
        maxLines: Int?,
        lineMult: Float,
    ): StaticLayout {
        val builder = StaticLayout.Builder
            .obtain(text, 0, text.length, paint, widthPx.coerceAtLeast(1))
            .setAlignment(Layout.Alignment.ALIGN_CENTER)
            .setLineSpacing(0f, lineMult)
            .setIncludePad(false)
            .setBreakStrategy(LineBreaker.BREAK_STRATEGY_SIMPLE)
            .setHyphenationFrequency(Layout.HYPHENATION_FREQUENCY_NONE)
        if (maxLines != null) {
            builder.setMaxLines(maxLines)
            builder.setEllipsize(TextUtils.TruncateAt.END)
        }
        return builder.build()
    }

    private fun newTextPaint(textSizePx: Float, bold: Boolean): TextPaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            this.textSize = textSizePx
            this.letterSpacing = 0f
            this.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }
}
