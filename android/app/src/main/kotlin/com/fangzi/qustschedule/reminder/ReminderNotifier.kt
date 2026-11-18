package com.fangzi.qustschedule.reminder

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.media.AudioAttributes
import android.media.RingtoneManager
import android.os.Build
import android.os.VibrationEffect
import android.provider.Settings
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
    private val DEFAULT_VIBRATION_PATTERN = longArrayOf(0L, 250L, 150L, 250L)

    fun show(
        context: Context,
        event: ReminderEvent,
        leadMinutes: Int,
    ): Boolean {
        if (!canPost(context)) return false
        ensureChannel(context)
        val manager = context.getSystemService(NotificationManager::class.java)
            ?: return false

        val now = System.currentTimeMillis()
        val timeoutMs = (event.startMs - now).coerceAtLeast(1000L)

        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_stat_lesson)
            .setContentTitle(event.name.ifEmpty { "上课提醒" })
            .setContentText(bodyText(event))
            .setStyle(NotificationCompat.BigTextStyle().bigText(bodyText(event)))
            .setContentIntent(contentIntent(context))
            .setOngoing(true)
            .setAutoCancel(false)
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setDefaults(NotificationCompat.DEFAULT_ALL)
            .setWhen(event.startMs)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setTimeoutAfter(timeoutMs)
            .build()

        manager.notify(NOTIFY_ID, notification)
        return true
    }

    /** 注册全部提醒渠道（仅在已获通知权限后创建，确保默认策略完整生效）。 */
    fun ensureAllChannels(context: Context) {
        ensureChannel(context)
        ReminderFluidRenderer.ensureChannel(context)
    }

    fun ensureChannel(context: Context) {
        ensureHighAlertChannel(
            context = context,
            channelId = CHANNEL_ID,
            channelName = CHANNEL_NAME,
            descriptionText = "上课前按课表提醒",
            showBadge = true,
        )
    }

    internal fun ensureHighAlertChannel(
        context: Context,
        channelId: String,
        channelName: String,
        descriptionText: String,
        showBadge: Boolean,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val manager = context.getSystemService(NotificationManager::class.java)
            ?: return
        // 未授予通知权限前不预先建渠道，防止国产系统在无权状态下将渠道锁定为静默/折叠。
        if (!ReminderPermissions.hasNotificationPermission(context)) return
        if (manager.getNotificationChannel(channelId) != null) return
        val audioAttributes = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .build()
        val channel = NotificationChannel(
            channelId,
            channelName,
            NotificationManager.IMPORTANCE_HIGH,
        ).apply {
            importance = NotificationManager.IMPORTANCE_HIGH
            description = descriptionText
            setShowBadge(showBadge)
            lockscreenVisibility = Notification.VISIBILITY_PUBLIC
            enableVibration(true)
            vibrationPattern = DEFAULT_VIBRATION_PATTERN
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.VANILLA_ICE_CREAM) {
                vibrationEffect = VibrationEffect.createWaveform(DEFAULT_VIBRATION_PATTERN, -1)
            }
            enableLights(true)
            val soundUri =
                RingtoneManager.getDefaultUri(RingtoneManager.TYPE_NOTIFICATION)
                    ?: Settings.System.DEFAULT_NOTIFICATION_URI
            setSound(soundUri, audioAttributes)
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
