package com.fangzi.qustschedule

import com.fangzi.qustschedule.reminder.ReminderBridge
import com.fangzi.qustschedule.updater.AppUpdaterBridge
import com.fangzi.qustschedule.widget.WidgetBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterSurfaceView
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {

    private var reminderBridge: ReminderBridge? = null
    private var updaterBridge: AppUpdaterBridge? = null
    private var widgetBridge: WidgetBridge? = null

    /**
     * 保持默认 RenderMode.surface（硬件直通 SurfaceView），同时将其置于 DecorView 之上，
     * 避免默认 z=-2 在 DecorView 上打透明洞（Punch-Hole），导致从桌面小组件点开做交叉淡入时
     * 浅色窗口底色被挖空、呈现内容「从暗变亮」的闪变。本应用无原生 PlatformView 浮层，安全可用。
     */
    override fun onFlutterSurfaceViewCreated(flutterSurfaceView: FlutterSurfaceView) {
        super.onFlutterSurfaceViewCreated(flutterSurfaceView)
        flutterSurfaceView.setZOrderOnTop(true)
    }

    /**
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
