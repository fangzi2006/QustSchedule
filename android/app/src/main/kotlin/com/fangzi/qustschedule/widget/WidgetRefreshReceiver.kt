package com.fangzi.qustschedule.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 接收小组件节点刷新闹钟、重启、覆盖安装与系统时间/时区变化，
 * 异步重绘桌面全部活跃小组件并续约下一个事件节点。
 */
class WidgetRefreshReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val appContext = context.applicationContext
        WidgetWorker.runBroadcastAsync(this, TAG) {
            WidgetCoordinator.refreshAllWidgets(appContext)
        }
    }

    companion object {
        private const val TAG = "WidgetRefreshReceiver"
    }
}
