package com.fangzi.qustschedule.widget

import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.Typeface
import android.text.Layout
import android.text.StaticLayout
import android.text.TextPaint
import kotlin.math.min
import kotlin.math.roundToInt
import kotlin.math.sqrt

/**
 * 原生 Canvas 高清绘制整周课表网格小组件。
 *
 * 将总像素控制在安全上限内，既保证桌面显示清晰锐利，又彻底避免 RemoteViews
 * 传输大图时触发 Binder 1MB 限制（TransactionTooLargeException）。
 */
internal object WeekGridCanvasRenderer {

    private const val MAX_PIXELS = 240_000f

    fun render(
        context: Context,
        style: WidgetStyleData,
        theme: ResolvedWidgetTheme,
        viewModel: WeekWidgetViewModel,
        widthDp: Int,
        heightDp: Int,
    ): Bitmap {
        val density = context.resources.displayMetrics.density.coerceAtLeast(1f)
        val rawW = (widthDp.coerceAtLeast(160) * density)
        val rawH = (heightDp.coerceAtLeast(140) * density)
        val rawPixels = rawW * rawH
        val pixelScale = if (rawPixels > MAX_PIXELS) {
            sqrt(MAX_PIXELS / rawPixels)
        } else {
            1f
        }
        val scale = density * pixelScale
        val widthPx = (rawW * pixelScale).roundToInt().coerceAtLeast(220)
        val heightPx = (rawH * pixelScale).roundToInt().coerceAtLeast(200)

        val bitmap = Bitmap.createBitmap(widthPx, heightPx, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)

        fun dp(v: Float): Float = v * scale
        fun sp(v: Float): Float = v * style.fontScale * scale

        // 1. 卡片背景与边框
        if (style.backgroundOpacity > 0.01f) {
            val stroke = dp(1f).coerceAtLeast(1f)
            val half = stroke * 0.5f
            val bgRect = RectF(half, half, widthPx - half, heightPx - half)
            val radius = dp(style.cornerRadius)
            val bgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.style = Paint.Style.FILL
                color = theme.surfaceColor
            }
            canvas.drawRoundRect(bgRect, radius, radius, bgPaint)
            if (theme.borderColor != 0) {
                val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                    this.style = Paint.Style.STROKE
                    strokeWidth = stroke
                    color = theme.borderColor
                }
                canvas.drawRoundRect(bgRect, radius, radius, borderPaint)
            }
        }

        val compact = style.density == "compact"
        val pad = dp(if (compact) 8f else 12f)
        val contentLeft = pad
        val contentRight = widthPx - pad
        var cursorTop = pad

        // 未登录 / 无课表占位
        val weekPlan = viewModel.weekPlan
        if (!viewModel.signedIn || weekPlan == null) {
            val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = theme.primaryTextColor
                textSize = sp(13f)
                typeface = Typeface.DEFAULT_BOLD
                textAlign = Paint.Align.CENTER
                if (theme.useTextShadow) setShadowLayer(dp(2f), 0f, dp(1f), theme.textShadowColor)
            }
            val subPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = theme.secondaryTextColor
                textSize = sp(11f)
                textAlign = Paint.Align.CENTER
            }
            val cx = widthPx * 0.5f
            val cy = heightPx * 0.5f
            canvas.drawText(
                if (viewModel.signedIn) "当前周暂无课表" else "轻触打开青科课表通登录",
                cx,
                cy - dp(4f),
                titlePaint,
            )
            canvas.drawText("课表同步后自动展示整周网格", cx, cy + dp(14f), subPaint)
            return bitmap
        }

        // 2. 顶部标题栏
        if (style.showHeader) {
            val titlePaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = theme.accentColor
                textSize = sp(12f)
                typeface = Typeface.DEFAULT_BOLD
                if (theme.useTextShadow) setShadowLayer(dp(2f), 0f, dp(1f), theme.textShadowColor)
            }
            val subPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
                color = theme.secondaryTextColor
                textSize = sp(10.5f)
                textAlign = Paint.Align.RIGHT
                if (theme.useTextShadow) setShadowLayer(dp(2f), 0f, dp(1f), theme.textShadowColor)
            }
            val weekText = "第 ${weekPlan.week} 周"
            val baseline = cursorTop - titlePaint.fontMetrics.ascent
            canvas.drawText(weekText, contentLeft, baseline, titlePaint)
            canvas.drawText("本周课表", contentRight, baseline, subPaint)
            cursorTop += titlePaint.fontSpacing + dp(if (compact) 3f else 5f)
        }

        val dayCount = if (viewModel.showWeekend) 7 else 5
        val axisWidth = if (style.showTime) dp(if (compact) 18f else 22f) else 0f
        val gridLeft = contentLeft + axisWidth
        val gridWidth = (contentRight - gridLeft).coerceAtLeast(dp(60f))
        val colWidth = gridWidth / dayCount.toFloat()

        // 3. 星期表头
        val headerFont = sp(9.5f)
        val weekdayPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            textSize = headerFont
            textAlign = Paint.Align.CENTER
        }
        val pillBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.FILL
            color = theme.accentBgColor
        }
        val headerHeight = weekdayPaint.fontSpacing + dp(4f)
        for (d in 1..dayCount) {
            val isToday = d == viewModel.todayWeekday
            val centerX = gridLeft + (d - 0.5f) * colWidth
            if (isToday) {
                val pillW = min(colWidth - dp(4f), dp(28f))
                val pillRect = RectF(
                    centerX - pillW * 0.5f,
                    cursorTop,
                    centerX + pillW * 0.5f,
                    cursorTop + headerHeight - dp(1f),
                )
                canvas.drawRoundRect(pillRect, dp(5f), dp(5f), pillBgPaint)
            }
            weekdayPaint.color = if (isToday) theme.accentColor else theme.secondaryTextColor
            weekdayPaint.typeface = if (isToday) Typeface.DEFAULT_BOLD else Typeface.DEFAULT
            if (theme.useTextShadow && !isToday) {
                weekdayPaint.setShadowLayer(dp(1.5f), 0f, dp(1f), theme.textShadowColor)
            } else {
                weekdayPaint.clearShadowLayer()
            }
            val textY = cursorTop + (headerHeight - dp(1f) - weekdayPaint.fontMetrics.ascent - weekdayPaint.fontMetrics.descent) * 0.5f
            canvas.drawText(shortWeekdayLabel(d), centerX, textY, weekdayPaint)
        }
        cursorTop += headerHeight + dp(3f)

        val gridBottom = heightPx - pad
        val gridHeight = (gridBottom - cursorTop).coerceAtLeast(dp(40f))
        val maxSection = weekPlan.maxSection.coerceIn(6, 14)
        val rowHeight = gridHeight / maxSection.toFloat()

        // 4. 淡横网格线与左侧节次轴
        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            color = theme.gridLineColor
            strokeWidth = dp(0.6f).coerceAtLeast(1f)
        }
        val axisPaint = TextPaint(Paint.ANTI_ALIAS_FLAG).apply {
            color = theme.secondaryTextColor
            textSize = sp(8.5f)
            textAlign = Paint.Align.CENTER
            if (theme.useTextShadow) setShadowLayer(dp(1.5f), 0f, dp(1f), theme.textShadowColor)
        }
        for (p in 1..maxSection) {
            val y = cursorTop + (p - 1) * rowHeight
            canvas.drawLine(gridLeft, y, contentRight, y, linePaint)
            if (style.showTime) {
                val labelY = y + rowHeight * 0.5f - (axisPaint.fontMetrics.ascent + axisPaint.fontMetrics.descent) * 0.5f
                canvas.drawText(p.toString(), contentLeft + axisWidth * 0.45f, labelY, axisPaint)
            }
        }

        // 5. 课程圆角格子
        val cardRadius = dp(5.5f)
        val blockGap = dp(if (compact) 1.0f else 1.4f)
        val blockPad = dp(if (compact) 2.2f else 3.0f)
        val blockBgPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.style = Paint.Style.FILL }
        val blockBorderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.STROKE
            strokeWidth = dp(0.7f).coerceAtLeast(1f)
        }
        val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply { this.style = Paint.Style.FILL }
        val blockTextPaint = TextPaint(Paint.ANTI_ALIAS_FLAG)

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

            if (block.rescheduled) {
                dotPaint.color = theme.examFgColor
                canvas.drawCircle(right - dp(4f), top + dp(4f), dp(2f), dotPaint)
            }

            val textAvailW = (rect.width() - blockPad * 2f).roundToInt().coerceAtLeast(4)
            val textAvailH = rect.height() - blockPad * 2f
            if (textAvailH < sp(7f)) continue

            val labelParts = buildString {
                append(block.name)
                if (style.showLocation && block.location.isNotEmpty()) {
                    append('\n')
                    append(block.location)
                }
                if (style.showTeacher && block.teacher.isNotEmpty()) {
                    append('\n')
                    append(block.teacher)
                }
            }

            blockTextPaint.color = chip.foreground
            blockTextPaint.textSize = sp(if (compact) 7.5f else 8.2f)
            val maxLines = (textAvailH / blockTextPaint.fontSpacing).toInt().coerceIn(1, 5)
            val layout = StaticLayout.Builder
                .obtain(labelParts, 0, labelParts.length, blockTextPaint, textAvailW)
                .setAlignment(Layout.Alignment.ALIGN_NORMAL)
                .setLineSpacing(0f, 1.05f)
                .setIncludePad(false)
                .setMaxLines(maxLines)
                .setEllipsize(android.text.TextUtils.TruncateAt.END)
                .build()

            canvas.save()
            canvas.clipRect(rect.left + blockPad, rect.top + blockPad, rect.right - blockPad, rect.bottom - blockPad)
            canvas.translate(rect.left + blockPad, rect.top + blockPad)
            layout.draw(canvas)
            canvas.restore()
        }

        return bitmap
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
