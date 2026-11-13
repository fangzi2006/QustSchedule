package com.fangzi.qustschedule.reminder

import android.content.BroadcastReceiver
import android.util.Log
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * 提醒模块共用的后台单线程执行器。
 *
 * 广播接收器（触发、开机/时区恢复、每日自检）与 Flutter 桥接的落盘/排程都要读写
 * SharedPreferences 并调用 AlarmManager；统一串行到后台单线程中执行，可彻底避免
 * 主线程阻塞与多余的锁竞争。
 */
internal object ReminderWorker {

    private const val TAG = "ReminderWorker"

    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "qust-reminder-worker")
    }

    fun execute(task: Runnable) {
        executor.execute(task)
    }

    /**
     * 在 [BroadcastReceiver.goAsync] 保护下把广播逻辑投递到后台线程，保证无论成功或
     * 异常都一定会释放 [BroadcastReceiver.PendingResult]。
     */
    fun runBroadcastAsync(
        receiver: BroadcastReceiver,
        tag: String,
        block: () -> Unit,
    ) {
        val pending = receiver.goAsync()
        try {
            executor.execute {
                try {
                    block()
                } catch (error: Throwable) {
                    Log.e(tag, "async broadcast failed", error)
                } finally {
                    pending.finish()
                }
            }
        } catch (error: Throwable) {
            Log.e(TAG, "failed to enqueue broadcast task for $tag", error)
            pending.finish()
        }
    }
}
