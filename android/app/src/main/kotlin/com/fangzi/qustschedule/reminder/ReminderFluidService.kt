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
 * 流体云常驻卡片：一节课前 [FluidCardState.notifyEpoch] 到下课之间，
 * 用前台服务维持一条带倒计时进度环的常驻通知。
 *
 * 为什么必须每 15 秒重发一次：胶囊上的倒计时/进度是由**通知本身携带的
 * 进度值**渲染的，系统不会替你走秒。重发即"刷新一帧"。
 *
 * 为什么还要额外挂一条"到点收起"的闹钟：`Handler.postDelayed` 只在本进程
 * 被调度时才跑，灭屏进 Doze / App Standby 冻结后 tick 会停摆，卡片就带着
 * 最后一帧一直挂在通知栏。前台服务通知又不能靠 `setTimeoutAfter` 撤销
 * （ongoing 通知的存活由服务生命周期决定），所以必须有一个"进程冻着也会响"
 * 的触发器——精确闹钟。[RC_FLUID_STOP] 独立于账本，[stop] / [onDestroy]
 * 会主动撤掉它。
 *
 * 生命周期出口：下课时间到（tick 或兜底闹钟）、用户关提醒、切回横幅、
 * 或系统回收。force-stop 后无法恢复，与提醒本身一致。
 */
class ReminderFluidService : Service() {

    private val handler = Handler(Looper.getMainLooper())
    private var card: FluidCardState? = null
    private val ticker = Runnable { tick() }

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
                // 进程被冻结时 tick 会停摆，必须再挂一条"到点收起"的闹钟兜底。
                armStopAlarm(this, state.stopAtMs)
                handler.removeCallbacks(ticker)
                handler.postDelayed(ticker, TICK_MS)
                Log.i(
                    TAG,
                    "fluid card started name=${state.name} " +
                        "left=${state.minutesLeft(System.currentTimeMillis())}min",
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
        handler.removeCallbacks(ticker)
        disarmStopAlarm(this)
        card = null
        casting = false
        super.onDestroy()
    }

    private fun tick() {
        val state = card ?: return
        val now = System.currentTimeMillis()
        if (now >= state.stopAtMs) {
            Log.i(
                TAG,
                "reached ${if (state.untilEnd) "end" else "start"}, stop fluid card",
            )
            stopSelf()
            return
        }
        val notification = ReminderFluidRenderer.build(this, state)
        val manager = getSystemService(NotificationManager::class.java)
        manager?.notify(ReminderNotifier.NOTIFY_ID, notification)
        // 上课后进度环已经停在满圈、文案也不再变，没必要每 15 秒唤醒一次。
        val interval = if (now >= state.startMs) TICK_SLOW_MS else TICK_MS
        handler.postDelayed(ticker, interval)
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
            untilEnd = intent.getBooleanExtra(EXTRA_UNTIL_END, false),
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
        private const val EXTRA_UNTIL_END = "until_end"

        private const val TICK_MS = 15_000L

        /** 上课后进度不再变化，刷新间隔放宽到 1 分钟，省电。 */
        private const val TICK_SLOW_MS = 60_000L

        /** 「到点收起」闹钟的槽位：独立于课表账本（2001 自愈 / 2002 测试）。 */
        private const val RC_FLUID_STOP = 2003

        /** 诊断页读它判断"卡片是否正在显示"（同进程静态值足够）。 */
        @Volatile
        var casting: Boolean = false
            private set

        /**
         * @param untilEnd true = 显示到下课；false = 上课即收起。
         * @return 是否成功把启动请求交给了系统（诊断页预览要用它）。
         */
        fun start(
            context: Context,
            event: ReminderEvent,
            untilEnd: Boolean = false,
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
                putExtra(EXTRA_UNTIL_END, untilEnd)
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
         * 挂一条"到点收起"的一次性精确闹钟。
         *
         * 精确权限缺失时降级成 `setAndAllowWhileIdle`（与提醒本身同一套规则），
         * 最差是晚几分钟收，但不会不收。
         */
        private fun armStopAlarm(context: Context, endMs: Long) {
            val manager = context.getSystemService(AlarmManager::class.java) ?: return
            if (endMs <= System.currentTimeMillis()) return
            val operation = stopAlarmPending(context, create = true) ?: return
            val exact = ReminderPermissions.canScheduleExactAlarms(context)
            try {
                if (exact) {
                    manager.setExactAndAllowWhileIdle(
                        AlarmManager.RTC_WAKEUP,
                        endMs,
                        operation,
                    )
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
