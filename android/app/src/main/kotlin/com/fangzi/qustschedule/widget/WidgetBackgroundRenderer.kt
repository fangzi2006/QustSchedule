package com.fangzi.qustschedule.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.os.Bundle
import kotlin.math.roundToInt

/**
 * 为 RemoteViews 类小组件绘制支持任意圆角与任意不透明度的动态背景图，
 * 同时提供与 RemoteViews / Canvas 共用的尺寸读取逻辑（防 Binder 超过 1MB 上限）。
 */
internal object WidgetBackgroundRenderer {

    private const val MAX_BG_DIMENSION_PX = 640

    fun resolveSizeDp(
        options: Bundle?,
        defaultWidthDp: Int,
        defaultHeightDp: Int,
    ): Pair<Int, Int> {
        if (options == null) return defaultWidthDp to defaultHeightDp
        val minW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val w = if (minW > 0) minW else defaultWidthDp
        val h = if (minH > 0) minH else defaultHeightDp
        return w to h
    }

    fun render(
        context: Context,
        style: WidgetStyleData,
        theme: ResolvedWidgetTheme,
        widthDp: Int,
        heightDp: Int,
    ): Bitmap {
        val density = context.resources.displayMetrics.density.coerceAtLeast(1f)
        val rawW = (widthDp.coerceAtLeast(60) * density).roundToInt()
        val rawH = (heightDp.coerceAtLeast(48) * density).roundToInt()
        val maxEdge = maxOf(rawW, rawH)
        val scale = if (maxEdge > MAX_BG_DIMENSION_PX) {
            MAX_BG_DIMENSION_PX.toFloat() / maxEdge.toFloat()
        } else {
            1f
        }
        val pxW = (rawW * scale).roundToInt().coerceAtLeast(48)
        val pxH = (rawH * scale).roundToInt().coerceAtLeast(40)
        val effectiveDensity = density * scale

        val bitmap = Bitmap.createBitmap(pxW, pxH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(bitmap)
        if (style.backgroundOpacity <= 0.01f) {
            return bitmap
        }

        val radiusPx = style.cornerRadius * effectiveDensity
        val strokePx = (1f * effectiveDensity).coerceAtLeast(1f)
        val halfStroke = strokePx * 0.5f
        val rect = RectF(halfStroke, halfStroke, pxW - halfStroke, pxH - halfStroke)

        val fillPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.style = Paint.Style.FILL
            color = theme.surfaceColor
        }
        canvas.drawRoundRect(rect, radiusPx, radiusPx, fillPaint)

        if (theme.borderColor != 0) {
            val borderPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                this.style = Paint.Style.STROKE
                strokeWidth = strokePx
                color = theme.borderColor
            }
            canvas.drawRoundRect(rect, radiusPx, radiusPx, borderPaint)
        }
        return bitmap
    }
}
