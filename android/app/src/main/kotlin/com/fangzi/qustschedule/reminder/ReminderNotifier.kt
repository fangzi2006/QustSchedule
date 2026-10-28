package com.fangzi.qustschedule.reminder

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

/**
 * 横幅通知：一条提醒 = 一条通知，点一下回 App。
 *
 * 通知 id 固定为 [NOTIFY_ID]（与参考实现一致）：同一时刻只保留最新一条，
 * 连堂课不会在通知栏堆成两行"同一门课的两个阶段"。
 */
object ReminderNotifier {

    const val CHANNEL_ID = "course_reminder_v1"
    const val CHANNEL_NAME = "上课提醒"

    /** 固定通知 id：新课覆盖旧卡，不按事件各发一条。 */
    const val NOTIFY_ID = 2000

    private const val REQUEST_CONTENT = 4402

    fun show(
        context: Context,
        event: ReminderEvent,
        leadMinutes: Int,
    ): Boolean {
        if (!canPost(context)) return false
        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java)
            ?: return false

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_lesson)
            .setContentTitle(event.name.ifEmpty { "上课提醒" })
            .setContentText(bodyText(event))
            .setSubText(subtitleText(event, leadMinutes))
            .setContentIntent(contentIntent(context))
            .setAutoCancel(true)
            .setOnlyAlertOnce(true)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PRIVATE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setWhen(event.startMs)
            .setShowWhen(true)
            .build()

        manager.notify(NOTIFY_ID, notification)
        return true
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
            ?: return
        if (manager.getNotificationChannel(CHANNEL_ID) != null) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            CHANNEL_NAME,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            description = "上课前按课表提醒"
            enableVibration(true)
        }
        manager.createNotificationChannel(channel)
    }

    fun canPost(context: Context): Boolean {
        if (!ReminderPermissions.hasNotificationPermission(context)) return false
        val manager = context.getSystemService(NotificationManager::class.java)
        return manager?.areNotificationsEnabled() == true
    }

    /** `08:00 上课 · 3教201 · 张三`（空字段直接省略）。 */
    fun bodyText(event: ReminderEvent): String {
        val time = SimpleDateFormat("HH:mm", Locale.CHINA)
            .format(Date(event.startMs))
        val parts = ArrayList<String>(3)
        parts.add("$time 上课")
        if (event.location.isNotEmpty()) parts.add(event.location)
        if (event.teacher.isNotEmpty()) parts.add(event.teacher)
        return parts.joinToString(" · ")
    }

    /** `第 3-4 节 · 还有 10 分钟`。 */
    fun subtitleText(event: ReminderEvent, leadMinutes: Int): String {
        val periods = if (event.startPeriod == event.endPeriod) {
            "第 ${event.startPeriod} 节"
        } else {
            "第 ${event.startPeriod}-${event.endPeriod} 节"
        }
        return "$periods · 还有 $leadMinutes 分钟"
    }

    fun contentIntent(context: Context): PendingIntent {
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
