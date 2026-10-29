package com.fangzi.qustschedule.reminder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.fangzi.qustschedule.MainActivity
import com.fangzi.qustschedule.R
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import kotlin.math.ceil

/** 流体云卡片的数据：全部来自闹钟 extras，不读库、不读时钟以外的状态。 */
data class FluidCardState(
    val name: String,
    val room: String,
    val teacher: String,
    val startMs: Long,
    val endMs: Long,
    val startPeriod: Int,
    val endPeriod: Int,
    val notifyEpoch: Long,
) {
    /** 卡片上课时刻即收起。 */
    val stopAtMs: Long
        get() = startMs

    /** 距离上课还有几分钟（不足一分钟按 1 算；已上课为 0）。 */
    fun minutesLeft(now: Long): Int {
        if (now >= startMs) return 0
        return ceil((startMs - now) / 60_000.0).toInt()
    }



    fun detailText(): String {
        val fmt = SimpleDateFormat("HH:mm", Locale.CHINA)
        val span = "${fmt.format(Date(startMs))} - ${fmt.format(Date(endMs))}"
        val parts = ArrayList<String>(3)
        parts.add(span)
        if (room.isNotEmpty()) parts.add(room)
        if (teacher.isNotEmpty()) parts.add(teacher)
        return parts.joinToString(" · ")
    }

}

/**
 * 流体云（ColorOS / HyperOS 等把常驻通知渲染成胶囊卡片）的构建器。
 *
 * 走的是公开 API：setRequestPromotedOngoing(true) + 高优先级常驻通知。
 * 倒计时使用系统原生 Chronometer（setUsesChronometer(true) + setChronometerCountDown(true)），
 * 由 SystemUI 纳秒精度自递减，极低功耗，并在课程开始时刻通过 setTimeoutAfter 准时收起。
 */
object ReminderFluidRenderer {

    const val CHANNEL_FLUID = "course_fluid_v1"
    const val CHANNEL_FLUID_NAME = "上课进度"

    private const val REQUEST_CONTENT = 4403

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
            ?: return
        if (manager.getNotificationChannel(CHANNEL_FLUID) != null) return
        val channel = NotificationChannel(
            CHANNEL_FLUID,
            CHANNEL_FLUID_NAME,
            // 参考实现要求 IMPORTANCE_HIGH 才可能被提成胶囊。
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "上课倒计时常驻卡片"
            setShowBadge(false)
        }
        manager.createNotificationChannel(channel)
    }

    fun build(context: Context, state: FluidCardState): Notification {
        ensureChannel(context)
        val now = System.currentTimeMillis()
        val primary = state.room.ifEmpty { state.name }.ifEmpty { "上课提醒" }

        val builder = NotificationCompat.Builder(context, CHANNEL_FLUID)
            .setSmallIcon(R.drawable.ic_stat_lesson)
            .setContentTitle(state.name.ifEmpty { "上课提醒" })
            .setSubText(state.detailText())
            .setWhen(state.startMs)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setTimeoutAfter((state.startMs - now).coerceAtLeast(1000L))
            .setShortCriticalText(primary.take(7))
            .setRequestPromotedOngoing(true)
            .setOngoing(true)
            .setSilent(true)
            .setOnlyAlertOnce(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .setContentIntent(contentIntent(context))
        return builder.build()
    }

    private fun contentIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP)
        }
        return PendingIntent.getActivity(
            context,
            REQUEST_CONTENT,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }
}
