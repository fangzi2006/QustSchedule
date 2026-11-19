package com.fangzi.qustschedule.widget

import android.app.Activity
import android.appwidget.AppWidgetManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * `qustschedule/widget` 通道桥接：将快照写入与小组件重绘放到 [WidgetWorker] 后台单线程。
 */
class WidgetBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val mainHandler = Handler(Looper.getMainLooper())
    @Volatile
    private var disposed = false

    fun attach() {
        disposed = false
        channel.setMethodCallHandler(this)
        activeBridge = this
    }

    fun dispose() {
        disposed = true
        if (activeBridge === this) {
            activeBridge = null
        }
        channel.setMethodCallHandler(null)
    }

    private fun postReply(block: () -> Unit) {
        mainHandler.post {
            if (!disposed) block()
        }
    }

    private fun sendPinnedCountsChanged(counts: Map<String, Int>) {
        postReply {
            try {
                channel.invokeMethod("onPinnedCountsChanged", counts)
            } catch (_: Throwable) {
                // 通道已关闭时静默忽略。
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "syncSnapshot" -> {
                val payload = call.argument<String>("payload") ?: ""
                val appContext = activity.applicationContext
                WidgetWorker.execute {
                    val previous = WidgetStore.loadSnapshot(appContext)
                    val saved = WidgetStore.saveSnapshot(appContext, payload)
                    if (saved != null) {
                        WidgetCoordinator.refreshChangedWidgets(appContext, previous, saved)
                    }
                    postReply { result.success(saved != null) }
                }
            }

            "clearSnapshot" -> {
                val appContext = activity.applicationContext
                WidgetWorker.execute {
                    WidgetStore.clear(appContext)
                    WidgetCoordinator.refreshAllWidgets(appContext)
                    postReply { result.success(null) }
                }
            }

            "requestPinWidget" -> {
                val kind = call.argument<String>("kind") ?: ""
                result.success(requestPin(kind))
            }

            "getPinnedCounts" -> {
                val appContext = activity.applicationContext
                WidgetWorker.execute {
                    val counts = WidgetCoordinator.getPinnedCounts(appContext)
                    postReply { result.success(counts) }
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun requestPin(kind: String): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val manager = AppWidgetManager.getInstance(activity) ?: return false
        if (!manager.isRequestPinAppWidgetSupported) return false
        val component = WidgetCoordinator.componentForKind(activity, kind) ?: return false
        val callback = WidgetCoordinator.createPinSuccessPendingIntent(activity)
        return try {
            manager.requestPinAppWidget(component, null, callback)
        } catch (_: Throwable) {
            false
        }
    }

    companion object {
        private const val CHANNEL = "qustschedule/widget"

        @Volatile
        private var activeBridge: WidgetBridge? = null

        internal fun dispatchPinnedCountsChanged(counts: Map<String, Int>) {
            activeBridge?.sendPinnedCountsChanged(counts)
        }
    }
}
