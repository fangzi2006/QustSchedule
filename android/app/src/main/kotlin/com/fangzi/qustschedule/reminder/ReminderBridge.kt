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

/**
 * `qustschedule/reminder` 通道的唯一入口。
 *
 * `sync` / `cancel` / `status` / `testReminder` 会读写偏好或操作 AlarmManager，
 * 全部放到共用后台单线程执行，结果回到主线程回复，避免阻塞 UI 线程。
 */
class ReminderBridge(
    private val activity: Activity,
    messenger: BinaryMessenger,
) : MethodChannel.MethodCallHandler {

    private val channel = MethodChannel(messenger, CHANNEL)
    private val scheduler = ReminderScheduler(activity)
    private val mainHandler = Handler(Looper.getMainLooper())
    private var pendingNotificationResult: MethodChannel.Result? = null
    @Volatile
    private var disposed = false

    fun attach() {
        disposed = false
        channel.setMethodCallHandler(this)
    }

    fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        pendingNotificationResult = null
    }

    private fun postReply(block: () -> Unit) {
        mainHandler.post {
            if (!disposed) block()
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "sync" -> handleSync(call, result)

            "cancel" -> {
                ReminderWorker.execute {
                    scheduler.cancelAll()
                    postReply { result.success(null) }
                }
            }

            "status" -> {
                ReminderWorker.execute {
                    try {
                        val status = scheduler.status()
                        postReply { result.success(status) }
                    } catch (e: Exception) {
                        Log.e(TAG, "failed to get status", e)
                        postReply { result.error("STATUS_FAILED", e.message, null) }
                    }
                }
            }

            "requestNotificationPermission" ->
                requestNotificationPermission(result)

            "openNotificationSettings" -> {
                ReminderPermissions.openNotificationSettings(activity)
                result.success(null)
            }

            "openExactAlarmSettings" -> {
                ReminderPermissions.openExactAlarmSettings(activity)
                result.success(ReminderPermissions.canScheduleExactAlarms(activity))
            }

            "openBatterySettings" -> {
                ReminderPermissions.openBatterySettings(activity)
                result.success(null)
            }

            // 返回 true = 跳到了厂商自启动页；false = 退到系统设置主页。
            "openAutostartSettings" -> {
                result.success(ReminderPermissions.openAutostartSettings(activity))
            }

            "testReminder" -> {
                val delay = call.argument<Int>("delaySeconds") ?: 60
                val style = call.argument<String>("style")
                    ?: ReminderPayload.STYLE_BANNER
                ReminderWorker.execute {
                    val epoch = scheduler.scheduleTest(delay, style)
                    postReply {
                        if (epoch == null) {
                            result.error("TEST_FAILED", "cannot schedule test alarm", null)
                        } else {
                            result.success(epoch)
                        }
                    }
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
        ReminderWorker.execute {
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
            postReply {
                val done = outcome
                if (done == null) {
                    result.error("SYNC_FAILED", error ?: "unknown", null)
                    return@postReply
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
