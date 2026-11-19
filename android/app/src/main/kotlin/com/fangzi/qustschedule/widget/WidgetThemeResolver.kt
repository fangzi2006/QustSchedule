package com.fangzi.qustschedule.widget

import android.content.Context
import android.content.res.ColorStateList
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import android.widget.RemoteViews
import com.fangzi.qustschedule.R
import kotlin.math.roundToInt

internal data class CourseChipColor(
    val background: Int,
    val foreground: Int,
)

internal enum class WidgetPillTone {
    ACCENT,
    ONGOING,
    TOMORROW,
    EXAM,
    RESCHEDULE,
    NEUTRAL,
}

internal data class ResolvedWidgetTheme(
    val isDark: Boolean,
    val surfaceColor: Int,
    val borderColor: Int,
    val primaryTextColor: Int,
    val secondaryTextColor: Int,
    val tertiaryTextColor: Int,
    val accentColor: Int,
    val accentBgColor: Int,
    val ongoingFgColor: Int,
    val ongoingBgColor: Int,
    val ongoingRowBgColor: Int,
    val tomorrowFgColor: Int,
    val tomorrowBgColor: Int,
    val examBgColor: Int,
    val examFgColor: Int,
    val examCardBgColor: Int,
    val examRowBgColor: Int,
    val rescheduleFgColor: Int,
    val rescheduleBgColor: Int,
    val rescheduleDotColor: Int,
    val neutralFgColor: Int,
    val neutralBgColor: Int,
    val neutralBarColor: Int,
    val gridLineColor: Int,
    val todayColumnHighlightColor: Int,
) {
    fun courseColor(index: Int): CourseChipColor {
        val palette = if (isDark) DARK_COURSE_COLORS else LIGHT_COURSE_COLORS
        val safe = ((index % palette.size) + palette.size) % palette.size
        return palette[safe]
    }

    fun pillFgColor(tone: WidgetPillTone): Int = when (tone) {
        WidgetPillTone.ACCENT -> accentColor
        WidgetPillTone.ONGOING -> ongoingFgColor
        WidgetPillTone.TOMORROW -> tomorrowFgColor
        WidgetPillTone.EXAM -> examFgColor
        WidgetPillTone.RESCHEDULE -> rescheduleFgColor
        WidgetPillTone.NEUTRAL -> neutralFgColor
    }

    fun pillBgColor(tone: WidgetPillTone): Int = when (tone) {
        WidgetPillTone.ACCENT -> accentBgColor
        WidgetPillTone.ONGOING -> ongoingBgColor
        WidgetPillTone.TOMORROW -> tomorrowBgColor
        WidgetPillTone.EXAM -> examBgColor
        WidgetPillTone.RESCHEDULE -> rescheduleBgColor
        WidgetPillTone.NEUTRAL -> neutralBgColor
    }

    fun pillFallbackDrawable(tone: WidgetPillTone, dimmed: Boolean = false): Int = when (tone) {
        WidgetPillTone.ACCENT -> if (isDark) R.drawable.widget_pill_accent_dark else R.drawable.widget_pill_accent_light
        WidgetPillTone.ONGOING -> if (isDark) R.drawable.widget_pill_ongoing_dark else R.drawable.widget_pill_ongoing_light
        WidgetPillTone.TOMORROW -> if (isDark) R.drawable.widget_pill_tomorrow_dark else R.drawable.widget_pill_tomorrow_light
        WidgetPillTone.EXAM -> when {
            dimmed && isDark -> R.drawable.widget_pill_exam_dark_dim
            dimmed -> R.drawable.widget_pill_exam_light_dim
            isDark -> R.drawable.widget_pill_exam_dark
            else -> R.drawable.widget_pill_exam_light
        }
        WidgetPillTone.RESCHEDULE -> when {
            dimmed && isDark -> R.drawable.widget_pill_reschedule_dark_dim
            dimmed -> R.drawable.widget_pill_reschedule_light_dim
            isDark -> R.drawable.widget_pill_reschedule_dark
            else -> R.drawable.widget_pill_reschedule_light
        }
        WidgetPillTone.NEUTRAL -> if (isDark) R.drawable.widget_pill_neutral_dark else R.drawable.widget_pill_neutral_light
    }

    companion object {
        // 与 Dart 侧 lib/theme/course_palette.dart 保持 100% 像素同色。
        private val LIGHT_COURSE_COLORS = listOf(
            CourseChipColor(0xFFE6F1FB.toInt(), 0xFF0C447C.toInt()), // 蓝
            CourseChipColor(0xFFE1F5EE.toInt(), 0xFF085041.toInt()), // 青
            CourseChipColor(0xFFEAF3DE.toInt(), 0xFF27500A.toInt()), // 绿
            CourseChipColor(0xFFFAEEDA.toInt(), 0xFF633806.toInt()), // 琥珀
            CourseChipColor(0xFFFAECE7.toInt(), 0xFF712B13.toInt()), // 珊瑚
            CourseChipColor(0xFFFBEAF0.toInt(), 0xFF72243E.toInt()), // 粉
            CourseChipColor(0xFFEEEDFE.toInt(), 0xFF3C3489.toInt()), // 紫
            CourseChipColor(0xFFFCEBEB.toInt(), 0xFF791F1F.toInt()), // 红
            CourseChipColor(0xFFF1EFE8.toInt(), 0xFF444441.toInt()), // 灰
        )

        private val DARK_COURSE_COLORS = listOf(
            CourseChipColor(0xFF15293E.toInt(), 0xFF9ECAFF.toInt()), // 蓝
            CourseChipColor(0xFF122C26.toInt(), 0xFF8BE2CC.toInt()), // 青
            CourseChipColor(0xFF1B2E17.toInt(), 0xFFA9DF9A.toInt()), // 绿
            CourseChipColor(0xFF332613.toInt(), 0xFFF3C87D.toInt()), // 琥珀
            CourseChipColor(0xFF352019.toInt(), 0xFFF5B7A3.toInt()), // 珊瑚
            CourseChipColor(0xFF361D29.toInt(), 0xFFF6B2CE.toInt()), // 粉
            CourseChipColor(0xFF25203E.toInt(), 0xFFC5BFFF.toInt()), // 紫
            CourseChipColor(0xFF381C1E.toInt(), 0xFFF6B0B0.toInt()), // 红
            CourseChipColor(0xFF272624.toInt(), 0xFFD0CEC6.toInt()), // 灰
        )
    }
}

internal object WidgetThemeResolver {

    fun resolve(context: Context, style: WidgetStyleData): ResolvedWidgetTheme {
        val systemNight = (context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK) ==
            Configuration.UI_MODE_NIGHT_YES
        val isDark = when (style.themeMode) {
            "light" -> false
            "dark" -> true
            "system", "dynamic" -> systemNight
            else -> false
        }

        val (baseBg, accent) = if (style.themeMode == "dynamic") {
            resolveDynamicColors(context, isDark)
        } else {
            val bg = if (isDark) 0xFF1C1F26.toInt() else Color.WHITE
            val ac = if (isDark) 0xFF9AB4FF.toInt() else 0xFF3F5AA6.toInt()
            bg to ac
        }

        val opacity = style.backgroundOpacity.coerceIn(0f, 1f)
        val alphaInt = (opacity * 255f).roundToInt().coerceIn(0, 255)
        val surfaceColor = withAlpha(baseBg, alphaInt)

        // 边框随不透明度线性淡出，消除 0% → 5% 跳变。
        val borderColor = if (opacity <= 0.01f) {
            Color.TRANSPARENT
        } else {
            val maxBorderAlpha = if (isDark) 34f else 20f
            val borderAlpha = (maxBorderAlpha * opacity).roundToInt().coerceIn(0, 255)
            withAlpha(if (isDark) Color.WHITE else Color.BLACK, borderAlpha)
        }

        // 低不透明度（< 35%）仅通过纯色提对比保证壁纸可读性，不添加任何文字阴影。
        val lowOpacityFactor = ((0.35f - opacity) / 0.35f).coerceIn(0f, 1f)

        val primaryTextColor = if (isDark) {
            lerpColor(0xFFF3F5F8.toInt(), 0xFFFFFFFF.toInt(), lowOpacityFactor)
        } else {
            lerpColor(0xFF1A1D24.toInt(), 0xFF101218.toInt(), lowOpacityFactor)
        }
        val secondaryTextColor = if (isDark) {
            lerpColor(0xFFB4BCC8.toInt(), 0xFFDDE3EC.toInt(), lowOpacityFactor)
        } else {
            lerpColor(0xFF5F6775.toInt(), 0xFF3A4150.toInt(), lowOpacityFactor)
        }
        val tertiaryTextColor = if (isDark) {
            lerpColor(0xFF8A93A2.toInt(), 0xFFC2CBD8.toInt(), lowOpacityFactor)
        } else {
            lerpColor(0xFF868E9C.toInt(), 0xFF505868.toInt(), lowOpacityFactor)
        }

        val accentBgAlpha = lerpInt(if (isDark) 0x36 else 0x22, if (isDark) 0x58 else 0x3A, lowOpacityFactor)
        val accentBgColor = withAlpha(accent, accentBgAlpha)

        val ongoingFgColor = if (isDark) 0xFF6EE7B7.toInt() else 0xFF0F766E.toInt()
        val ongoingBgColor = if (isDark) 0xFF16382C.toInt() else 0xFFE0F5EE.toInt()
        val ongoingRowBgColor = withAlpha(
            ongoingFgColor,
            lerpInt(if (isDark) 0x22 else 0x16, if (isDark) 0x36 else 0x28, lowOpacityFactor),
        )

        val tomorrowFgColor = if (isDark) 0xFFC4B8FF.toInt() else 0xFF5B4BC4.toInt()
        val tomorrowBgColor = if (isDark) 0xFF2B2448.toInt() else 0xFFEFEBFD.toInt()

        val examBgColor = if (isDark) 0xFF3E2914.toInt() else 0xFFFFF3E0.toInt()
        val examFgColor = if (isDark) 0xFFFFC175.toInt() else 0xFFE65100.toInt()
        val examCardBgColor = withAlpha(
            examBgColor,
            lerpInt(0xFF, 0xE6, lowOpacityFactor),
        )
        val examRowBgColor = withAlpha(
            examFgColor,
            lerpInt(if (isDark) 0x24 else 0x18, if (isDark) 0x38 else 0x2A, lowOpacityFactor),
        )

        val rescheduleFgColor = if (isDark) 0xFF7DD3FC.toInt() else 0xFF0369A1.toInt()
        val rescheduleBgColor = if (isDark) 0xFF172E42.toInt() else 0xFFE0F2FE.toInt()
        val rescheduleDotColor = if (isDark) 0xFF5EEAD4.toInt() else 0xFF0D9488.toInt()

        val neutralFgColor = if (isDark) 0xFFB8C0CC.toInt() else 0xFF5A6270.toInt()
        val neutralBgColor = if (isDark) 0xFF2C313C.toInt() else 0xFFECEFF4.toInt()
        val neutralBarColor = if (isDark) 0xFF64748B.toInt() else 0xFF94A3B8.toInt()

        val gridLineColor = withAlpha(
            secondaryTextColor,
            lerpInt(if (isDark) 0x24 else 0x20, if (isDark) 0x36 else 0x2C, lowOpacityFactor),
        )
        val todayColumnHighlightColor = withAlpha(accent, if (isDark) 0x10 else 0x0D)

        return ResolvedWidgetTheme(
            isDark = isDark,
            surfaceColor = surfaceColor,
            borderColor = borderColor,
            primaryTextColor = primaryTextColor,
            secondaryTextColor = secondaryTextColor,
            tertiaryTextColor = tertiaryTextColor,
            accentColor = accent,
            accentBgColor = accentBgColor,
            ongoingFgColor = ongoingFgColor,
            ongoingBgColor = ongoingBgColor,
            ongoingRowBgColor = ongoingRowBgColor,
            tomorrowFgColor = tomorrowFgColor,
            tomorrowBgColor = tomorrowBgColor,
            examBgColor = examBgColor,
            examFgColor = examFgColor,
            examCardBgColor = examCardBgColor,
            examRowBgColor = examRowBgColor,
            rescheduleFgColor = rescheduleFgColor,
            rescheduleBgColor = rescheduleBgColor,
            rescheduleDotColor = rescheduleDotColor,
            neutralFgColor = neutralFgColor,
            neutralBgColor = neutralBgColor,
            neutralBarColor = neutralBarColor,
            gridLineColor = gridLineColor,
            todayColumnHighlightColor = todayColumnHighlightColor,
        )
    }

    private fun resolveDynamicColors(context: Context, isDark: Boolean): Pair<Int, Int> {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            try {
                val bgRes = if (isDark) {
                    android.R.color.system_neutral1_900
                } else {
                    android.R.color.system_neutral1_10
                }
                val accentRes = if (isDark) {
                    android.R.color.system_accent1_200
                } else {
                    android.R.color.system_accent1_600
                }
                return context.getColor(bgRes) to context.getColor(accentRes)
            } catch (_: Throwable) {
                // 部分定制 ROM 若裁剪系统动态色资源，平稳回落应用默认莫奈系配色。
            }
        }
        val fallbackBg = if (isDark) 0xFF1C2330.toInt() else 0xFFF3F6FC.toInt()
        val fallbackAccent = if (isDark) 0xFFAEC6FF.toInt() else 0xFF3B66A8.toInt()
        return fallbackBg to fallbackAccent
    }

    fun withAlpha(color: Int, alpha: Int): Int =
        (color and 0x00FFFFFF) or ((alpha.coerceIn(0, 255)) shl 24)

    fun applyPill(
        views: RemoteViews,
        viewId: Int,
        theme: ResolvedWidgetTheme,
        tone: WidgetPillTone,
        dimmed: Boolean = false,
    ) {
        val rawFg = theme.pillFgColor(tone)
        val rawBg = theme.pillBgColor(tone)
        val fg = if (dimmed) withAlpha(rawFg, 115) else rawFg
        val bg = if (dimmed) withAlpha(rawBg, (Color.alpha(rawBg) * 0.45f).roundToInt()) else rawBg
        views.setTextColor(viewId, fg)
        applyRoundedBackground(
            views = views,
            viewId = viewId,
            bgColor = bg,
            baseDrawableRes = R.drawable.widget_pill_bg,
            fallbackDrawableRes = theme.pillFallbackDrawable(tone, dimmed),
        )
    }

    fun applyRoundedBackground(
        views: RemoteViews,
        viewId: Int,
        bgColor: Int,
        baseDrawableRes: Int,
        fallbackDrawableRes: Int,
    ) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setInt(viewId, "setBackgroundResource", baseDrawableRes)
            views.setColorStateList(
                viewId,
                "setBackgroundTintList",
                ColorStateList.valueOf(bgColor),
            )
        } else {
            views.setInt(viewId, "setBackgroundResource", fallbackDrawableRes)
        }
    }

    fun clearBackground(views: RemoteViews, viewId: Int) {
        views.setInt(viewId, "setBackgroundResource", 0)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            views.setColorStateList(viewId, "setBackgroundTintList", null)
        }
    }

    /**
     * 安全着色竖条：传不透明 RGB 给 SRC_ATOP `setColorFilter`，透明度统一走 `setImageAlpha`，
     * 避免半透明颜色叠在白色底图上泛白。
     */
    fun applyVerticalBar(
        views: RemoteViews,
        viewId: Int,
        color: Int,
        alpha: Int = 255,
    ) {
        views.setImageViewResource(viewId, R.drawable.widget_bar_pill)
        views.setInt(viewId, "setColorFilter", color or 0xFF000000.toInt())
        views.setInt(viewId, "setImageAlpha", alpha.coerceIn(0, 255))
    }

    private fun lerpInt(a: Int, b: Int, t: Float): Int =
        (a + (b - a) * t).roundToInt().coerceIn(0, 255)

    private fun lerpColor(a: Int, b: Int, t: Float): Int {
        val clamped = t.coerceIn(0f, 1f)
        val ca = lerpInt(Color.alpha(a), Color.alpha(b), clamped)
        val cr = lerpInt(Color.red(a), Color.red(b), clamped)
        val cg = lerpInt(Color.green(a), Color.green(b), clamped)
        val cb = lerpInt(Color.blue(a), Color.blue(b), clamped)
        return Color.argb(ca, cr, cg, cb)
    }
}
