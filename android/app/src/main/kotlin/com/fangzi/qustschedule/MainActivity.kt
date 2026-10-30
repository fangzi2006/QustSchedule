package com.fangzi.qustschedule

import com.fangzi.qustschedule.reminder.ReminderBridge
import com.fangzi.qustschedule.updater.AppUpdaterBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var reminderBridge: ReminderBridge? = null
    private var updaterBridge: AppUpdaterBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // 一个通道只能有一个 handler：正式排程与调试探针都由
        // ReminderBridge 统一分发，不要在这里再注册第二个通道。
        reminderBridge = ReminderBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.attach() }

        updaterBridge = AppUpdaterBridge(
            this,
            flutterEngine.dartExecutor.binaryMessenger,
        ).also { it.attach() }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        if (reminderBridge?.onRequestPermissionsResult(requestCode, grantResults) == true) {
            return
        }
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
    }

    override fun onDestroy() {
        updaterBridge?.dispose()
        updaterBridge = null
        reminderBridge?.dispose()
        reminderBridge = null
        super.onDestroy()
    }
}
