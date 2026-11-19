package com.fangzi.qustschedule.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * 接收小组件节点刷新闹钟、一键添加回调、重启、覆盖安装与系统时间/时区变化，
 * 异步按需重绘活跃小组件并续约下一个事件节点。
 */
class WidgetRefreshReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent?) {
        val appContext = context.applicationContext
        val action = intent?.action
        val includeWeek = intent?.getBooleanExtra(WidgetRefreshScheduler.EXTRA_INCLUDE_WEEK, false) ?: false
        WidgetWorker.runBroadcastAsync(this, TAG) {
            when (action) {
                WidgetRefreshScheduler.ACTION_REFRESH_WIDGETS -> {
                    WidgetCoordinator.refreshForScheduledAlarm(appContext, includeWeekRequested = includeWeek)
                }
                WidgetRefreshScheduler.ACTION_WIDGET_PINNED -> {
                    WidgetCoordinator.notifyPinnedCountsChanged(appContext)
                    WidgetCoordinator.syncAlarmState(appContext)
                }
                else -> {
                    WidgetCoordinator.refreshAllWidgets(appContext)
                }
            }
        }
    }

    companion object {
        private const val TAG = "WidgetRefreshReceiver"
    }
}
