package com.fangzi.qustschedule.reminder

import android.app.AlarmManager
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat

/**
 * 流体云常驻卡片：一节课前 [FluidCardState.notifyEpoch] 到开课时刻之间，
 * 用前台服务维持一条带系统原生倒计时的常驻通知。
 *
 * 倒计时由系统 SystemUI Chronometer 原生走秒，无需应用进程频繁 postDelayed 重发通知。
 * 开课时刻准时收起：由前台服务延迟回调、精确闹钟（[RC_FLUID_STOP] / ACTION_DISMISS）
 * 以及通知自带的 `setTimeoutAfter` 共同保障，上课准时撤销。
 */
class ReminderFluidService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var card: FluidCardState? = null
    private val stopRunnable = Runnable {
        Log.i(TAG, "reached start time, stop fluid card")
        stopSelf()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_START -> {
                val state = parse(intent)
                if (state == null) {
                    Log.w(TAG, "start without valid extras")
                    stopSelf()
                    return START_NOT_STICKY
                }
                val now = System.currentTimeMillis()
                if (now >= state.startMs) {
                    Log.i(TAG, "already reached class start time, skipping fluid card")
                    stopSelf()
                    return START_NOT_STICKY
                }
                card = state
                casting = true
                // 必须在 5 秒内进前台，否则系统会抛 ANR 级异常。
                try {
                    startForeground(
                        ReminderNotifier.NOTIFY_ID,
                        ReminderFluidRenderer.build(this, state),
                    )
                } catch (error: Exception) {
                    Log.e(TAG, "startForeground failed", error)
                    casting = false
                    stopSelf()
                    return START_NOT_STICKY
                }
                // 挂一条"开课准时收起"的闹钟兜底（防止进程被冻结时 Handler 延迟失效）。
                armStopAlarm(this, state.startMs)
                handler.removeCallbacks(stopRunnable)
                handler.postDelayed(stopRunnable, (state.startMs - now).coerceAtLeast(0L))
                Log.i(
                    TAG,
                    "fluid card started name=${state.name} " +
                        "left=${state.minutesLeft(now)}min",
                )
            }

            ACTION_STOP -> {
                Log.i(TAG, "fluid card stopped by caller")
                stopSelf()
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(stopRunnable)
        disarmStopAlarm(this)
        card = null
        casting = false
        super.onDestroy()
    }

    private fun parse(intent: Intent): FluidCardState? {
        val name = intent.getStringExtra(EXTRA_NAME) ?: return null
        val startMs = intent.getLongExtra(EXTRA_START_MS, 0L)
        val endMs = intent.getLongExtra(EXTRA_END_MS, 0L)
        if (startMs <= 0L || endMs <= startMs) return null
        return FluidCardState(
            name = name,
            room = intent.getStringExtra(EXTRA_ROOM).orEmpty(),
            teacher = intent.getStringExtra(EXTRA_TEACHER).orEmpty(),
            startMs = startMs,
            endMs = endMs,
            startPeriod = intent.getIntExtra(EXTRA_START_PERIOD, 1),
            endPeriod = intent.getIntExtra(EXTRA_END_PERIOD, 1),
            notifyEpoch = intent.getLongExtra(EXTRA_NOTIFY_EPOCH, startMs),
        )
    }

    companion object {
        const val TAG = "ReminderFluid"
        const val ACTION_START = "com.fangzi.qustschedule.action.FLUID_START"
        const val ACTION_STOP = "com.fangzi.qustschedule.action.FLUID_STOP"

        private const val EXTRA_NAME = "name"
        private const val EXTRA_ROOM = "room"
        private const val EXTRA_TEACHER = "teacher"
        private const val EXTRA_START_MS = "start_ms"
        private const val EXTRA_END_MS = "end_ms"
        private const val EXTRA_START_PERIOD = "start_period"
        private const val EXTRA_END_PERIOD = "end_period"
        private const val EXTRA_NOTIFY_EPOCH = "notify_epoch"

        /** 「到点收起」闹钟的槽位：独立于课表账本（2001 自愈 / 2002 测试）。 */
        private const val RC_FLUID_STOP = 2003

        /** 诊断页读它判断"卡片是否正在显示"（同进程静态值足够）。 */
        @Volatile
        var casting: Boolean = false
            private set

        /**
         * @return 是否成功把启动请求交给了系统（诊断页预览要用它）。
         */
        fun start(
            context: Context,
            event: ReminderEvent,
        ): Boolean {
            val intent = Intent(context, ReminderFluidService::class.java).apply {
                action = ACTION_START
                putExtra(EXTRA_NAME, event.name)
                putExtra(EXTRA_ROOM, event.location)
                putExtra(EXTRA_TEACHER, event.teacher)
                putExtra(EXTRA_START_MS, event.startMs)
                putExtra(EXTRA_END_MS, event.endMs)
                putExtra(EXTRA_START_PERIOD, event.startPeriod)
                putExtra(EXTRA_END_PERIOD, event.endPeriod)
                putExtra(EXTRA_NOTIFY_EPOCH, event.remindAtMs)
            }
            return try {
                ContextCompat.startForegroundService(context, intent)
                true
            } catch (error: Exception) {
                Log.e(TAG, "startForegroundService rejected", error)
                casting = false
                false
            }
        }

        fun stop(context: Context) {
            casting = false
            runCatching {
                context.stopService(Intent(context, ReminderFluidService::class.java))
            }
            runCatching {
                context.getSystemService(NotificationManager::class.java)
                    ?.cancel(ReminderNotifier.NOTIFY_ID)
            }
            runCatching { disarmStopAlarm(context) }
        }

        /**
         * 挂一条"开课准时收起"的一次性闹钟。
         */
        private fun armStopAlarm(context: Context, endMs: Long) {
            val manager = context.getSystemService(AlarmManager::class.java) ?: return
            if (endMs <= System.currentTimeMillis()) return
            val operation = stopAlarmPending(context, create = true) ?: return
            val exact = ReminderPermissions.canScheduleExactAlarms(context)
            try {
                if (exact) {
                    val info = AlarmManager.AlarmClockInfo(
                        endMs,
                        ReminderNotifier.contentIntent(context),
                    )
                    manager.setAlarmClock(info, operation)
                } else {
                    manager.setAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        endMs,
                        operation,
                    )
                }
                Log.i(TAG, "stop alarm armed at $endMs exact=$exact")
            } catch (error: SecurityException) {
                Log.w(TAG, "stop alarm denied", error)
            }
        }

        private fun disarmStopAlarm(context: Context) {
            val manager = context.getSystemService(AlarmManager::class.java) ?: return
            val operation = stopAlarmPending(context, create = false) ?: return
            manager.cancel(operation)
            operation.cancel()
        }

        private fun stopAlarmPending(
            context: Context,
            create: Boolean,
        ): PendingIntent? {
            val intent = Intent(context, ReminderReceiver::class.java).apply {
                action = ReminderReceiver.ACTION_FLUID_STOP
            }
            val flags = PendingIntent.FLAG_IMMUTABLE or if (create) {
                PendingIntent.FLAG_UPDATE_CURRENT
            } else {
                PendingIntent.FLAG_NO_CREATE
            }
            return PendingIntent.getBroadcast(context, RC_FLUID_STOP, intent, flags)
        }

    }
}
