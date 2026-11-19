package com.fangzi.qustschedule.widget

import android.content.BroadcastReceiver
import android.util.Log
import java.util.concurrent.ExecutorService
import java.util.concurrent.Executors

/**
 * 桌面小组件模块共用的后台单线程执行器。
 *
 * 所有广播接收（刷新、配置尺寸变化、开机/时区恢复）与 MethodChannel 快照写入都在此单线程
 * 串行执行：避免主线程读取 SharedPreferences 或绘制 Canvas/Bitmap 引发掉帧与 ANR，
 * 同时消除并发写快照与读取之间的竞态。
 */
internal object WidgetWorker {

    private const val TAG = "WidgetWorker"

    private val executor: ExecutorService = Executors.newSingleThreadExecutor { runnable ->
        Thread(runnable, "qust-widget-worker")
    }

    fun execute(task: Runnable) {
        executor.execute(task)
    }

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
                    Log.e(tag, "async widget broadcast failed", error)
                } finally {
                    pending.finish()
                }
            }
        } catch (error: Throwable) {
            Log.e(TAG, "failed to enqueue widget broadcast task for $tag", error)
            pending.finish()
        }
    }
}
