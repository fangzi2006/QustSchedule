package com.fangzi.qustschedule.widget

import android.content.Context
import android.content.res.Configuration
import android.graphics.Color
import android.os.Build
import kotlin.math.roundToInt

internal data class CourseChipColor(
    val background: Int,
    val foreground: Int,
)

internal data class ResolvedWidgetTheme(
    val isDark: Boolean,
    val surfaceColor: Int,
    val borderColor: Int,
    val primaryTextColor: Int,
    val secondaryTextColor: Int,
    val accentColor: Int,
    val accentBgColor: Int,
    val examBgColor: Int,
    val examFgColor: Int,
    val gridLineColor: Int,
    val useTextShadow: Boolean,
    val textShadowColor: Int,
) {
    fun courseColor(index: Int): CourseChipColor {
        val palette = if (isDark) DARK_COURSE_COLORS else LIGHT_COURSE_COLORS
        val safe = ((index % palette.size) + palette.size) % palette.size
        return palette[safe]
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

        val borderColor = if (opacity <= 0.02f) {
            Color.TRANSPARENT
        } else if (isDark) {
            0x22FFFFFF
        } else {
            0x14000000
        }

        val primaryTextColor = if (isDark) 0xFFF3F5F8.toInt() else 0xFF1A1D24.toInt()
        val secondaryTextColor = if (isDark) 0xFFB8C0CC.toInt() else 0xFF646C7A.toInt()
        val accentBgColor = withAlpha(accent, if (isDark) 0x33 else 0x22)
        val examBgColor = if (isDark) 0xFF3E2914.toInt() else 0xFFFFF3E0.toInt()
        val examFgColor = if (isDark) 0xFFFFC175.toInt() else 0xFFE65100.toInt()
        val gridLineColor = withAlpha(secondaryTextColor, if (isDark) 0x24 else 0x22)
        val useTextShadow = opacity < 0.25f
        val textShadowColor = if (isDark) 0x99000000.toInt() else 0x88FFFFFF.toInt()

        return ResolvedWidgetTheme(
            isDark = isDark,
            surfaceColor = surfaceColor,
            borderColor = borderColor,
            primaryTextColor = primaryTextColor,
            secondaryTextColor = secondaryTextColor,
            accentColor = accent,
            accentBgColor = accentBgColor,
            examBgColor = examBgColor,
            examFgColor = examFgColor,
            gridLineColor = gridLineColor,
            useTextShadow = useTextShadow,
            textShadowColor = textShadowColor,
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
}
