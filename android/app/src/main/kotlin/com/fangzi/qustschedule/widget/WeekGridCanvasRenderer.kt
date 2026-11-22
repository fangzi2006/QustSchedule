package com.fangzi.qustschedule.widget

import android.annotation.SuppressLint
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import android.graphics.Typeface
import android.graphics.text.LineBreaker
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import android.text.TextUtils
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * 原生 Canvas 高清绘制整周课表网格小组件。
 *
 * 1) 严格基于屏幕 `density`（不受系统超大字体 `scaledDensity` 影响）并输出不可变 Bitmap（走 Ashmem 传输）；
 * 2) 0% 纯透明模式跳过圆角裁切与圆角避让，课程色块保持 100% 实色；
 * 3) 单行星期表头 + 右上角周日期范围 + 仅在当前真实周高亮今日整列（4–6% 淡色列）；
 * 4) 格子内部三段排版（课名 → 教师 → 地点）严格对齐软件内 `CourseBlock._BlockPlan`。
 */
internal object WeekGridCanvasRenderer {

    private const val MIN_PIXELS_CEILING = 800_000f
    private const val MAX_PIXELS_CEILING = 2_400_000f

    fun render(
        context: Context,
        style: WidgetStyleData,
        theme: ResolvedWidgetTheme,
        viewModel: WeekWidgetViewModel,
        widthDp: Int,
        heightDp: Int,
    ): Bitmap {
        val dm = context.resources.displayMetrics
        val density = dm.density.coerceAtLeast(1f)
        val rawW = (widthDp.coerceAtLeast(160) * density)
        val rawH = (heightDp.coerceAtLeast(140) * density)
        val screenPixels = (dm.widthPixels.toFloat() * dm.heightPixels.toFloat())
            .coerceAtLeast(MIN_PIXELS_CEILING)
        val maxPixels = min(screenPixels * 0.90f, MAX_PIXELS_CEILING)
            .coerceAtLeast(MIN_PIXELS_CEILING)
        val rawPixels = rawW * rawH
        val pixelScale = if (rawPixels > maxPixels) {
            sqrt(maxPixels / rawPixels)
        } else {
            1f
        }
        val scale = density * pixelScale
        val widthPx = (rawW * pixelScale).roundToInt().coerceAtLeast(240)
        val heightPx = (rawH * pixelScale).roundToInt().coerceAtLeast(220)

        val mutable = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(mutable)

        fun dp(v: Float): Float = v * scale
        // 统一走 density * style.fontScale，彻底免疫系统超大字体二次放大。
        fun textPx(v: Float): Float = v * style.fontScale * scale

        val hasVisibleCard = style.backgroundOpacity > 0.01f
        val cornerPx = min(dp(style.cornerRadius), min(widthPx, heightPx) * 0.5f)
        val stroke = dp(1f).coerceAtLeast(1f)
        val half = stroke * 0.5f
        val bgRect = RectF(half, half, widthPx - half, heightPx - half)

        if (hasVisibleCard) {
            val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.style = Paint.Style.FILL
                color = theme.surfaceColor
            }
            canvas.drawRoundRect(bgRect, cornerPx, cornerPx, bgPaint)
            if (theme.borderColor != 0) {
                val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    this.style = Paint.Style.STROKE
                    strokeWidth = stroke
                    color = theme.borderColor
                }
                canvas.drawRoundRect(bgRect, cornerPx, cornerPx, borderPaint)
            }
        }

        // 仅在存在可见底色卡片时按圆角裁剪内部内容，0% 透明模式跳过圆角裁切。
        canvas.save()
        if (hasVisibleCard) {
            val clipInset = dp(1f)
            val clipRect = RectF(clipInset, clipInset, widthPx - clipInset, heightPx - clipInset)
            val clipRadius = (cornerPx - clipInset).coerceAtLeast(0f)
            val clipPath = Path().apply {
                addRoundRect(clipRect, clipRadius, clipRadius, Path.Direction.CW)
            }
            canvas.clipPath(clipPath)
        }

        val compact = style.density == "compact"
        val clearance = WidgetBackgroundRenderer.cornerClearanceDp(style)
        val padX = dp(maxOf(if (compact) 6.0f else 9.0f, clearance))
        val padTop = dp(maxOf(if (compact) 5.5f else 8.5f, clearance))
        // 底部直抵 1dp 外描边内缘（0% 透明直到底边），彻底消除下方白边并由内层圆角 clipPath 顺边裁圆。
        val padBottom = if (hasVisibleCard) stroke else 0f
        val contentLeft = padX
        val contentRight = widthPx - padX
        var cursorTop = padTop

        // 未登录 / 过期 / 学期已结束 / 无课表占位
        val weekPlan = viewModel.weekPlan
        if (!viewModel.signedIn || viewModel.isStale || viewModel.isTermEnded || weekPlan == null) {
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
            val titlePaint = newTextPaint(theme.primaryTextColor, textPx(12f), bold = true).apply {
                textAlign = Paint.Align.CENTER
            }
            val subPaint = newTextPaint(theme.secondaryTextColor, textPx(10.5f), bold = false).apply {
                textAlign = Paint.Align.CENTER
            }
            val cx = widthPx * 0.5f
            val cy = heightPx * 0.5f
            canvas.drawText(titleText, cx, cy - dp(4f), titlePaint)
            canvas.drawText(subText, cx, cy + dp(13f), subPaint)
            canvas.restore()
            return WidgetBackgroundRenderer.toImmutableAshmemFriendly(mutable)
        }

        val dayCount = if (viewModel.showWeekend) 7 else 5
        val maxSection = weekPlan.maxSection.coerceIn(6, 14)

        // 节次轴宽度随字号动态适配，确保 120% 字号下两位数节次（10–12）完整清晰不裁切。
        val axisPaint = newTextPaint(theme.secondaryTextColor, textPx(8.0f), bold = false).apply {
            textAlign = Paint.Align.CENTER
        }
        val axisWidth = if (style.showTime) {
            maxOf(
                dp(if (compact) 16f else 19f),
                axisPaint.measureText(maxSection.toString()) + dp(6f),
            )
        } else {
            0f
        }
        val gridLeft = contentLeft + axisWidth

        // 2. 顶部标题栏：「第 X 周」与日期范围合并左对齐展示，位置更靠左贴近节次列上方
        if (style.showHeader) {
            val titlePaint = newTextPaint(theme.accentColor, textPx(11f), bold = true)
            val rangePaint = newTextPaint(theme.secondaryTextColor, textPx(9.2f), bold = false)
            val weekText = "第 ${weekPlan.week} 周"
            val baseline = cursorTop - titlePaint.fontMetrics.ascent
            val weekTitleX = contentLeft + dp(if (hasVisibleCard) 2.5f else 0f)
            canvas.drawText(weekText, weekTitleX, baseline, titlePaint)

            if (viewModel.dateRange.isNotEmpty()) {
                val rangeX = weekTitleX + titlePaint.measureText(weekText) + dp(6f)
                canvas.drawText(viewModel.dateRange, rangeX, baseline, rangePaint)
            }
            cursorTop += titlePaint.fontSpacing + dp(if (compact) 2.5f else 4.5f)
        }

        val gridWidth = (contentRight - gridLeft).coerceAtLeast(dp(60f))
        val colWidth = gridWidth / dayCount.toFloat()

        // 3. 单行星期表头（仅在当前真实周高亮今日胶囊）
        val weekdayPaint = newTextPaint(theme.secondaryTextColor, textPx(8.8f), bold = false).apply {
            textAlign = Paint.Align.CENTER
        }
        val pillBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.FILL
            color = theme.accentBgColor
        }
        val headerHeight = weekdayPaint.fontSpacing + dp(3.5f)
        for (d in 1..dayCount) {
            val isToday = viewModel.isCurrentWeek && d == viewModel.todayWeekday
            val centerX = gridLeft + (d - 0.5f) * colWidth
            if (isToday) {
                val pillW = min(colWidth - dp(4f), dp(26f))
                val pillRect = RectF(
                    centerX - pillW * 0.5f,
                    cursorTop,
                    centerX + pillW * 0.5f,
                    cursorTop + headerHeight - dp(1f),
                )
                canvas.drawRoundRect(pillRect, dp(4.5f), dp(4.5f), pillBgPaint)
            }
            weekdayPaint.color = if (isToday) theme.accentColor else theme.secondaryTextColor
            weekdayPaint.typeface = if (isToday) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            val textY = cursorTop + (
                headerHeight - dp(1f) - weekdayPaint.fontMetrics.ascent - weekdayPaint.fontMetrics.descent
            ) * 0.5f
            canvas.drawText(shortWeekdayLabel(d), centerX, textY, weekdayPaint)
        }
        cursorTop += headerHeight + dp(2.5f)

        val gridBottom = heightPx - padBottom
        val gridHeight = (gridBottom - cursorTop).coerceAtLeast(dp(40f))
        val rowHeight = gridHeight / maxSection.toFloat()

        // 4. 仅在真实当前周为今日列绘制柔和全列垂直淡色背景（4–6% alpha）
        if (viewModel.isCurrentWeek && viewModel.todayWeekday in 1..dayCount) {
            val colLeft = gridLeft + (viewModel.todayWeekday - 1) * colWidth
            val todayColPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.style = Paint.Style.FILL
                color = theme.todayColumnHighlightColor
            }
            canvas.drawRoundRect(
                RectF(colLeft + dp(0.5f), cursorTop, colLeft + colWidth - dp(0.5f), gridBottom),
                dp(4f),
                dp(4f),
                todayColPaint,
            )
        }

        // 5. 淡横网格线与左侧节次轴
        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = theme.gridLineColor
            strokeWidth = dp(0.6f).coerceAtLeast(1f)
        }
        for (p in 1..maxSection) {
            val y = cursorTop + (p - 1) * rowHeight
            canvas.drawLine(gridLeft, y, contentRight, y, linePaint)
            if (style.showTime) {
                val labelY = y + rowHeight * 0.5f - (axisPaint.fontMetrics.ascent + axisPaint.fontMetrics.descent) * 0.5f
                canvas.drawText(p.toString(), contentLeft + axisWidth * 0.48f, labelY, axisPaint)
            }
        }

        // 空周 / 仅周末有课但隐藏周末列时的友好提示：避免整张网格只有空横线看起来像加载失败。
        val hasVisibleBlock = weekPlan.blocks.any {
            it.day in 1..dayCount && it.startPeriod in 1..maxSection
        }
        if (!hasVisibleBlock) {
            val emptyPaint = newTextPaint(theme.secondaryTextColor, textPx(11.5f), bold = false).apply {
                textAlign = Paint.Align.CENTER
            }
            val cx = gridLeft + gridWidth * 0.5f
            val cy = cursorTop + gridHeight * 0.5f - (emptyPaint.fontMetrics.ascent + emptyPaint.fontMetrics.descent) * 0.5f
            val emptyMsg = if (weekPlan.blocks.isEmpty()) "本周无课，好好休息" else "工作日无课，周末有安排"
            canvas.drawText(emptyMsg, cx, cy, emptyPaint)
            canvas.restore()
            return WidgetBackgroundRenderer.toImmutableAshmemFriendly(mutable)
        }

        // 6. 课程圆角实色格子（0% 透明模式下仍保持 100% 实色清晰可读）
        val cardRadius = dp(5.5f)
        val blockGap = dp(if (compact) 0.9f else 1.2f)
        val blockPadX = dp(if (compact) 1.6f else 2.2f)
        val blockPadY = dp(if (compact) 1.6f else 2.2f)
        val fieldGap = dp(if (compact) 0.8f else 1.2f)
        val titleLineMult = 1.14f
        val detailLineMult = 1.12f

        val blockBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.style = Paint.Style.FILL }
        val blockBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.STROKE
            strokeWidth = dp(0.7f).coerceAtLeast(1f)
        }
        val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.style = Paint.Style.FILL }
        val titlePaint = newTextPaint(0, textPx(if (compact) 8.0f else 8.8f), bold = true)
        val teacherPaint = newTextPaint(0, textPx(if (compact) 6.8f else 7.4f), bold = false)
        val locationPaint = newTextPaint(0, textPx(if (compact) 6.8f else 7.4f), bold = false)

        for (block in weekPlan.blocks) {
            if (block.day < 1 || block.day > dayCount) continue
            if (block.startPeriod < 1 || block.startPeriod > maxSection) continue
            val endPeriod = block.endPeriod.coerceIn(block.startPeriod, maxSection)
            val totalCols = block.conflictTotal.coerceAtLeast(1)
            val colSlotW = colWidth / totalCols.toFloat()

            val left = gridLeft + (block.day - 1) * colWidth + block.conflictIndex * colSlotW + blockGap
            val right = left + colSlotW - blockGap * 2f
            val top = cursorTop + (block.startPeriod - 1) * rowHeight + blockGap
            val bottom = cursorTop + endPeriod * rowHeight - blockGap
            if (right <= left + dp(4f) || bottom <= top + dp(4f)) continue

            val chip = theme.courseColor(block.colorIndex)
            val rect = RectF(left, top, right, bottom)
            blockBgPaint.color = chip.background
            canvas.drawRoundRect(rect, cardRadius, cardRadius, blockBgPaint)

            blockBorderPaint.color = WidgetThemeResolver.withAlpha(chip.foreground, 0x2E)
            canvas.drawRoundRect(rect, cardRadius, cardRadius, blockBorderPaint)

            val availW = (rect.width() - blockPadX * 2f).roundToInt().coerceAtLeast(4)
            val availH = rect.height() - blockPadY * 2f
            if (availH > 0f) {
                val titleText = block.name.trim()
                val teacherText = if (style.showTeacher) block.teacher.trim() else ""
                val locationText = if (style.showLocation) block.location.trim() else ""

                val plan = solveCourseBlockPlan(
                    titleText = titleText,
                    teacherText = teacherText,
                    locationText = locationText,
                    widthPx = availW,
                    availH = availH,
                    fieldGap = fieldGap,
                    titlePaint = titlePaint,
                    detailPaint = locationPaint,
                    titleLineMult = titleLineMult,
                    detailLineMult = detailLineMult,
                )

                titlePaint.color = chip.foreground
                teacherPaint.color = WidgetThemeResolver.withAlpha(chip.foreground, 0xBD)
                locationPaint.color = WidgetThemeResolver.withAlpha(chip.foreground, 0xCB)

                val layouts = ArrayList<StaticLayout>(3)
                if (plan.titleLines > 0 && titleText.isNotEmpty()) {
                    layouts.add(
                        buildBlockLayout(titleText, titlePaint, availW, plan.titleLines, titleLineMult),
                    )
                }
                if (plan.teacherLines > 0 && teacherText.isNotEmpty()) {
                    layouts.add(
                        buildBlockLayout(teacherText, teacherPaint, availW, plan.teacherLines, detailLineMult),
                    )
                }
                if (plan.locationLines > 0 && locationText.isNotEmpty()) {
                    layouts.add(
                        buildBlockLayout(locationText, locationPaint, availW, plan.locationLines, detailLineMult),
                    )
                }

                if (layouts.isNotEmpty()) {
                    var totalH = 0f
                    for (idx in layouts.indices) {
                        if (idx > 0) totalH += fieldGap
                        totalH += layouts[idx].height.toFloat()
                    }
                    var drawY = rect.top + blockPadY + ((availH - totalH) * 0.5f).coerceAtLeast(0f)
                    val drawX = rect.left + blockPadX
                    canvas.save()
                    canvas.clipRect(
                        rect.left + blockPadX,
                        rect.top + blockPadY,
                        rect.right - blockPadX,
                        rect.bottom - blockPadY,
                    )
                    for (idx in layouts.indices) {
                        if (idx > 0) drawY += fieldGap
                        val layout = layouts[idx]
                        canvas.save()
                        canvas.translate(drawX, drawY)
                        layout.draw(canvas)
                        canvas.restore()
                        drawY += layout.height.toFloat()
                    }
                    canvas.restore()
                }
            }

            // 调课角标采用青蓝色圆点，与主应用红/橙冲突圆点语义彻底区分。
            if (block.rescheduled) {
                dotPaint.color = theme.rescheduleDotColor
                canvas.drawCircle(right - dp(4f), top + dp(4f), dp(2.1f), dotPaint)
            }
        }

        canvas.restore()
        return WidgetBackgroundRenderer.toImmutableAshmemFriendly(mutable)
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
        val teacherNeeded = if (teacherText.isNotEmpty()) {
            buildBlockLayout(teacherText, detailPaint, widthPx, null, detailLineMult).lineCount
        } else {
            0
        }
        val locationNeeded = if (locationText.isNotEmpty()) {
            buildBlockLayout(locationText, detailPaint, widthPx, null, detailLineMult).lineCount
        } else {
            0
        }

        var titleLines = titleNeeded
        var teacherLines = teacherNeeded
        var locationLines = locationNeeded

        val heightCache = HashMap<String, Float>()
        fun fieldHeight(text: String, paint: TextPaint, maxLines: Int, mult: Float): Float {
            if (text.isEmpty() || maxLines <= 0) return 0f
            val key = "$text\u0000$maxLines\u0000$mult"
            return heightCache.getOrPut(key) {
                buildBlockLayout(text, paint, widthPx, maxLines, mult).height.toFloat()
            }
        }

        fun usedHeight(): Float {
            var activeFields = 0
            if (titleLines > 0) activeFields++
            if (teacherLines > 0) activeFields++
            if (locationLines > 0) activeFields++
            val gaps = if (activeFields > 1) activeFields - 1 else 0
            return fieldHeight(titleText, titlePaint, titleLines, titleLineMult) +
                fieldHeight(teacherText, detailPaint, teacherLines, detailLineMult) +
                fieldHeight(locationText, detailPaint, locationLines, detailLineMult) +
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
                titleLines += (remaining / titleSingleLineH).toInt()
            }
        }

        return BlockPlan(
            titleLines = titleLines,
            teacherLines = teacherLines,
            locationLines = locationLines,
        )
    }

    // LineBreaker.BREAK_STRATEGY_SIMPLE 为编译期内联常量 0，在 API 24+ 与
    // Layout.BREAK_STRATEGY_SIMPLE 等价，同时满足 @BreakStrategy Lint 校验。
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

    private fun newTextPaint(color: Int, textSizePx: Float, bold: Boolean): TextPaint =
        TextPaint(Paint.ANTI_ALIAS_FLAG or Paint.SUBPIXEL_TEXT_FLAG).apply {
            this.color = color
            this.textSize = textSizePx
            this.letterSpacing = 0f
            this.typeface = if (bold) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
        }

    private fun shortWeekdayLabel(day: Int): String = when (day) {
        1 -> "一"
        2 -> "二"
        3 -> "三"
        4 -> "四"
        5 -> "五"
        6 -> "六"
        7 -> "日"
        else -> ""
    }
}
