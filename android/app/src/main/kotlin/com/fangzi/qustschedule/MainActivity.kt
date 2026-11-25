package com.fangzi.qustschedule

import com.fangzi.qustschedule.reminder.ReminderBridge
import com.fangzi.qustschedule.updater.AppUpdaterBridge
import com.fangzi.qustschedule.widget.WidgetBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var reminderBridge: ReminderBridge? = null
    private var updaterBridge: AppUpdaterBridge? = null
    private var widgetBridge: WidgetBridge? = null

    /**
     * 保持默认 RenderMode.surface（硬件直通 SurfaceView），避免 RenderMode.texture 在
     * Impeller Vulkan 下经多次前后台切换触发 SurfaceTexture 交换链阻塞与逐次掉帧；
     * 进出场防黑闪由浅色 LaunchTheme/NormalTheme、Launcher 同源启动 Intent 与根栈热驻留共同保障。
     *
     * 根页面触发系统返回时将任务退回后台而非销毁 Activity：
     * 1) 避免缩回桌面小组件动画期间在主线程销毁 FlutterEngine / Vulkan 上下文引发掉帧；
     * 2) 走系统桌面平滑的 Task-to-Widget 退场过渡，并保持引擎热驻留实现下次秒开。
     */
    override fun popSystemNavigator(): Boolean {
        if (isTaskRoot) {
            return moveTaskToBack(true)
        }
        return false
    }

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

        widgetBridge = WidgetBridge(
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
        widgetBridge?.dispose()
        widgetBridge = null
        updaterBridge?.dispose()
        updaterBridge = null
        reminderBridge?.dispose()
        reminderBridge = null
        super.onDestroy()
    }
}
