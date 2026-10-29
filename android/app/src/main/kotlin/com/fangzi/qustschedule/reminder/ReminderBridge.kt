package com.fangzi.qustschedule.reminder

import android.Manifest
import android.app.Activity
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.widget.Toast
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.util.concurrent.Executors

/**
 * `qustschedule/reminder` 通道的唯一入口。
 *
 * `sync` 会落盘并批量挂闹钟，放到后台单线程执行，结果回到主线程回复。
 * 排程本身在 [ReminderScheduler] 里加进程级锁，所以这里单线程只是为了让
 * 主线程不被一批 `setExact` 拖住。
 */
class ReminderBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val scheduler = ReminderScheduler(activity)
    private val worker = Executors.newSingleThreadExecutor()
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingNotificationResult: MethodChannel.Result? = null

    fun attach() {
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        channel.setMethodCallHandler(null)
        pendingNotificationResult = null
        worker.shutdownNow()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sync" -> handleSync(call, result)

            "cancel" -> {
                worker.execute {
                    scheduler.cancelAll()
                    mainHandler.post { result.success(null) }
                }
            }

            "status" -> {
                worker.execute {
                    try {
                        val status = scheduler.status()
                        mainHandler.post { result.success(status) }
                    } catch (e: Exception) {
                        Log.e(TAG, "failed to get status", e)
                        mainHandler.post { result.error("STATUS_FAILED", e.message, null) }
                    }
                }
            }

            "requestNotificationPermission" ->
                requestNotificationPermission(result)

            "openExactAlarmSettings" -> {
                ReminderPermissions.openExactAlarmSettings(activity)
                result.success(ReminderPermissions.canScheduleExactAlarms(activity))
            }

            "openBatterySettings" -> {
                ReminderPermissions.openBatterySettings(activity)
                result.success(null)
            }

            // 返回 true = 跳到了厂商自启动页；false = 退到应用详情页。
            "openAutostartSettings" -> {
                result.success(ReminderPermissions.openAutostartSettings(activity))
            }

            "testReminder" -> {
                val delay = call.argument<Int>("delaySeconds") ?: 60
                val style = call.argument<String>("style")
                    ?: ReminderPayload.STYLE_BANNER
                val epoch = scheduler.scheduleTest(delay, style)
                if (epoch == null) {
                    result.error("TEST_FAILED", "cannot schedule test alarm", null)
                } else {
                    result.success(epoch)
                }
            }

            // 诊断页「立即显示通知」：只发一条示例，不挂闹钟、不碰账本。
            "previewReminder" -> {
                val style = call.argument<String>("style")
                    ?: ReminderPayload.STYLE_BANNER
                val lead = call.argument<Int>("leadMinutes") ?: 10
                val event = ReminderSamples.event(lead)
                val shown = if (style == ReminderPayload.STYLE_FLUID) {
                    ReminderFluidService.start(activity, event)
                } else {
                    ReminderNotifier.show(activity, event, lead)
                }
                result.success(shown)
            }

            "stopFluid" -> {
                ReminderFluidService.stop(activity)
                result.success(null)
            }

            "toast" -> {
                val message = call.argument<String>("message") ?: ""
                val isLong = call.argument<Boolean>("long") ?: false
                if (message.isNotEmpty()) {
                    mainHandler.post {
                        val duration = if (isLong) Toast.LENGTH_LONG else Toast.LENGTH_SHORT
                        Toast.makeText(activity.applicationContext, message, duration).show()
                    }
                }
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    /** 通知权限：Android 13+ 走运行时申请，更低版本直接看渠道开关。 */
    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (ReminderPermissions.hasNotificationPermission(activity)) {
            result.success(true)
            return
        }
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (pendingNotificationResult != null) {
            result.error("BUSY", "notification permission request running", null)
            return
        }
        pendingNotificationResult = result
        activity.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_NOTIFICATION,
        )
    }

    /** @return true = 这次结果归提醒通道处理，不要再交给 super。 */
    fun onRequestPermissionsResult(
        requestCode: Int,
        grantResults: IntArray,
    ): Boolean {
        if (requestCode != REQUEST_NOTIFICATION) return false
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingNotificationResult?.success(granted)
        pendingNotificationResult = null
        return true
    }

    private fun handleSync(call: MethodCall, result: MethodChannel.Result) {
        val json = call.arguments as? String
        if (json.isNullOrEmpty()) {
            result.error("BAD_ARGS", "payload json is required", null)
            return
        }
        worker.execute {
            var outcome: ReminderSyncOutcome? = null
            var error: String? = null
            try {
                val payload = ReminderPayload.parse(json)
                outcome = scheduler.sync(payload, json, fromFlutter = true)
            } catch (failure: ReminderPayloadException) {
                // 解析失败绝不动已保存的 payload：旧闹钟继续有效。
                error = failure.message
                Log.w(TAG, "payload rejected: $error")
            } catch (failure: Exception) {
                error = failure.message ?: failure.javaClass.simpleName
                Log.e(TAG, "sync failed", failure)
            }
            mainHandler.post {
                val done = outcome
                if (done == null) {
                    result.error("SYNC_FAILED", error ?: "unknown", null)
                    return@post
                }
                result.success(
                    mapOf(
                        "scheduled" to done.scheduled,
                        "nextTriggerMs" to done.nextTriggerMs,
                        "coverageEndMs" to done.coverageEndMs,
                        "style" to done.style,
                        "exactAlarmAllowed" to done.exactAllowed,
                    ),
                )
            }
        }
    }

    companion object {
        const val CHANNEL = "qustschedule/reminder"
        const val TAG = "ReminderBridge"
        private const val REQUEST_NOTIFICATION = 4501
    }
}
