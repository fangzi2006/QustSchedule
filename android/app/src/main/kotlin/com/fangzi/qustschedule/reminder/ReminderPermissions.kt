package com.fangzi.qustschedule.reminder

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import java.util.Locale

/**
 * 权限判断与系统设置跳转：正式排程与调试探针共用同一套判断，
 * 避免"探针显示已授权、正式排程却按未授权处理"这种自相矛盾。
 */
object ReminderPermissions {

    const val TAG = "ReminderPermissions"

    /** Android 13+ 的通知权限（12 及以下只需渠道未被关闭）。 */
    fun hasNotificationPermission(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
        return context.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
    }

    /** 通知总开关（用户可能在系统设置里关掉整个 App 的通知）。 */
    fun notificationsEnabled(context: Context): Boolean =
        context.getSystemService(NotificationManager::class.java)
            .areNotificationsEnabled()

    /** Android 12+ 的精确闹钟特殊权限；更低版本恒为 true。 */
    fun canScheduleExactAlarms(context: Context): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return true
        return context.getSystemService(AlarmManager::class.java)
            .canScheduleExactAlarms()
    }

    /** 是否已忽略电池优化（加入白名单）。 */
    fun isIgnoringBatteryOptimizations(context: Context): Boolean =
        context.getSystemService(PowerManager::class.java)
            .isIgnoringBatteryOptimizations(context.packageName)

    fun openExactAlarmSettings(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) return
        val intent = Intent(
            Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM,
            Uri.parse("package:${context.packageName}"),
        )
        startSafely(context, intent)
    }

    /**
     * 电池 / 耗电管理。
     *
     * 落点必须是**应用详情页**：ColorOS、HyperOS 都把「耗电管理」「后台运行」
     * 挂在那里；而 `ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS` 只打开一个
     * 上百个 App 的电池优化总列表，用户还得自己翻。
     *
     * 顺序：应用详情 → （万一 OEM 剪掉了）电池优化列表 → 应用详情兜底。
     */
    fun openBatterySettings(context: Context) {
        if (tryStart(context, appDetailsIntent(context))) return
        val batteryList = Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
        if (tryStart(context, batteryList)) return
        startSafely(context, appDetailsIntent(context))
    }

    fun openAppDetails(context: Context) {
        startSafely(context, appDetailsIntent(context))
    }

    // -------------------------------------------------------------------------
    // 自启动（厂商私有权限）
    // -------------------------------------------------------------------------

    /**
     * 开机广播权限是否还在。
     *
     * 这是"自启动"里**唯一读得到的确定事实**：真正的自启动开关是厂商私有的，
     * AOSP 既没有 API 也没有读取途径。`RECEIVE_BOOT_COMPLETED` 是普通权限，
     * 正常恒为 granted，只有被特殊手段收回才会变 false。
     */
    fun hasBootBroadcastPermission(context: Context): Boolean =
        context.checkSelfPermission(Manifest.permission.RECEIVE_BOOT_COMPLETED) ==
            PackageManager.PERMISSION_GRANTED

    /**
     * 厂商自启动管理页的候选入口。
     *
     * 各家都是私有 Activity，且从 ColorOS 12 起这些页面**不导出**：
     * `startActivity` 会直接抛 SecurityException。所以这里只当作"万一能跳"
     * 的尝试，失败一律退到应用详情页。
     */
    private fun autostartCandidates(): List<Intent> {
        val manufacturer = Build.MANUFACTURER.lowercase(Locale.ROOT)
        return when {
            manufacturer.contains("xiaomi") || manufacturer.contains("redmi") -> listOf(
                Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT),
            )
            manufacturer.contains("oppo") || manufacturer.contains("realme") || manufacturer.contains("oneplus") -> listOf(
                Intent("com.coloros.safecenter.permission.startup.StartupAppListActivity"),
                Intent("com.oppo.safe.permission.startup.StartupAppListActivity"),
            )
            manufacturer.contains("vivo") || manufacturer.contains("iqoo") -> listOf(
                Intent("com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
            )
            manufacturer.contains("huawei") || manufacturer.contains("honor") -> listOf(
                Intent("huawei.intent.action.HSM_BOOTAPP_MANAGER"),
            )
            manufacturer.contains("meizu") -> listOf(
                Intent("com.meizu.safe.permission.SmartBGActivity"),
            )
            else -> listOf(
                Intent("miui.intent.action.OP_AUTO_START").addCategory(Intent.CATEGORY_DEFAULT),
                Intent("com.coloros.safecenter.permission.startup.StartupAppListActivity"),
                Intent("com.oppo.safe.permission.startup.StartupAppListActivity"),
                Intent("com.vivo.permissionmanager.activity.BgStartUpManagerActivity"),
                Intent("huawei.intent.action.HSM_BOOTAPP_MANAGER"),
                Intent("com.meizu.safe.permission.SmartBGActivity"),
            )
        }
    }

    /** 本机是否存在可解析的自启动管理页（纯查询，不跳转）。 */
    fun hasAutostartSettings(context: Context): Boolean {
        val cached = autostartPageFound
        if (cached != null) return cached
        val manager = context.packageManager
        val found = autostartCandidates().any { candidate ->
            runCatching { manager.resolveActivity(candidate, 0) != null }
                .getOrDefault(false)
        }
        autostartPageFound = found
        return found
    }

    /**
     * 打开自启动设置。
     *
     * @return true = 真的跳到了厂商自启动页；false = 只能退到应用详情页。
     */
    fun openAutostartSettings(context: Context): Boolean {
        for (candidate in autostartCandidates()) {
            val resolvable = runCatching {
                context.packageManager.resolveActivity(candidate, 0) != null
            }.getOrDefault(false)
            if (!resolvable) continue
            if (tryStart(context, Intent(candidate))) {
                Log.i(TAG, "autostart page opened: ${candidate.action}")
                return true
            }
        }
        Log.i(TAG, "no usable autostart page, fall back to app details")
        tryStart(context, appDetailsIntent(context))
        return false
    }

    /** 设备能力不会变，查一次就够；避免每次 status() 都做 6 次 resolve。 */
    @Volatile
    private var autostartPageFound: Boolean? = null

    private fun appDetailsIntent(context: Context) = Intent(
        Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
        Uri.parse("package:${context.packageName}"),
    )

    /**
     * 非 Activity 的 Context 起 Activity 必须带 NEW_TASK，
     * 否则会抛 AndroidRuntimeException——那是最容易被忽略的崩溃点。
     */
    private fun startSafely(context: Context, intent: Intent) {
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }.onFailure {
            Log.w(TAG, "startActivity failed: ${intent.action}", it)
            openAppDetailsFallback(context)
        }
    }

    /** 试跳一次，成功返回 true（供 [openBatterySettings] 挑落点用）。 */
    private fun tryStart(context: Context, intent: Intent): Boolean {
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return runCatching { context.startActivity(intent) }.isSuccess
    }

    private fun openAppDetailsFallback(context: Context) {
        val intent = Intent(
            Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
            Uri.parse("package:${context.packageName}"),
        )
        if (context !is Activity) intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        runCatching { context.startActivity(intent) }
    }
}
