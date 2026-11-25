package com.fangzi.qustschedule.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.RectF
import android.os.Build
import android.os.Bundle
import kotlin.math.roundToInt

/**
 * 为 RemoteViews 类小组件绘制支持任意圆角与任意不透明度的动态背景图，
 * 同时提供与当前屏幕方向一致的真实尺寸解析（竖屏高取 MAX_HEIGHT、横屏宽取 MAX_WIDTH）。
 */
internal object WidgetBackgroundRenderer {

    private const val MAX_BG_DIMENSION_PX = 1080

    fun resolveSizeDp(
        context: Context,
        options: Bundle?,
        defaultWidthDp: Int,
        defaultHeightDp: Int,
    ): Pair<Int, Int> {
        if (options == null) return defaultWidthDp to defaultHeightDp
        val isLandscape =
            context.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
        val minW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_WIDTH, 0)
        val maxW = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_WIDTH, 0)
        val minH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MIN_HEIGHT, 0)
        val maxH = options.getInt(AppWidgetManager.OPTION_APPWIDGET_MAX_HEIGHT, 0)

        val w = if (isLandscape) {
            if (maxW > 0) maxW else if (minW > 0) minW else defaultWidthDp
        } else {
            if (minW > 0) minW else if (maxW > 0) maxW else defaultWidthDp
        }
        val h = if (isLandscape) {
            if (minH > 0) minH else if (maxH > 0) maxH else defaultHeightDp
        } else {
            if (maxH > 0) maxH else if (minH > 0) minH else defaultHeightDp
        }
        return w to h
    }

    /**
     * 当存在可见圆角卡片底色时，内容边缘需至少避开圆角弦高（约 0.30 × R）以免角落文字/列表戳出边框；
     * 0% 纯透明模式无圆角裁切，直接归零。
     */
    fun cornerClearanceDp(style: WidgetStyleData): Float =
        if (style.backgroundOpacity <= 0.01f) 0f else style.cornerRadius * 0.30f

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

        val mutable = Bitmap.createBitmap(pxW, pxH, Bitmap.Config.ARGB_8888)
        val canvas = Canvas(mutable)
        if (style.backgroundOpacity > 0.01f) {
            val radiusPx = minOf(style.cornerRadius * effectiveDensity, minOf(pxW, pxH) * 0.5f)
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
        }
        return toImmutableAshmemFriendly(mutable)
    }

    internal fun toImmutableAshmemFriendly(mutable: Bitmap): Bitmap {
        val immutable = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            mutable.asShared()
        } else {
            mutable.copy(Bitmap.Config.ARGB_8888, false)
        }
        if (immutable != null && immutable !== mutable) {
            mutable.recycle()
            immutable.prepareToDraw()
            return immutable
        }
        mutable.prepareToDraw()
        return mutable
    }
}
