package com.fangzi.qustschedule.reminder

import android.Manifest
import android.app.Activity
import android.app.AlarmManager
import android.app.NotificationManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.util.Log

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

    /**
     * 应用通知管理页。
     *
     * 直接打开本应用在系统中的通知管理页（ACTION_APP_NOTIFICATION_SETTINGS）。
     * ColorOS、HyperOS 等系统的横幅与锁屏总开关位于应用通知管理总页，总开关未开时
     * 单个渠道页无法单独修改，因此直接进入应用通知管理页。
     *
     * 顺序：应用通知管理总页 → （万一系统剪掉）应用详情页。
     */
    fun openNotificationSettings(context: Context) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val appNotifyIntent = Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).apply {
                putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
            }
            if (tryStart(context, appNotifyIntent)) return
        }
        startSafely(context, appDetailsIntent(context))
    }

    fun openAppDetails(context: Context) {
        startSafely(context, appDetailsIntent(context))
    }

    // -------------------------------------------------------------------------
    // 自启动（厂商私有权限）
    // -------------------------------------------------------------------------

    /**
     * 厂商自启动管理页的候选入口。
     *
     * 各家都是私有页面：有的是自定义 Action，有的是明确包名+类名；且从 ColorOS 12
     * 等新系统起部分页面不导出（`exported=false`），`startActivity` 会抛
     * `SecurityException`。跳不动时一律退到手机系统设置主页，引导用户搜索"自启动"。
     */
    private fun autostartCandidates(context: Context): List<Intent> = listOf(
        // 小米 / 红米（MIUI / HyperOS）
        Intent("miui.intent.action.OP_AUTO_START")
            .addCategory(Intent.CATEGORY_DEFAULT),
        componentIntent(
            "com.miui.securitycenter",
            "com.miui.permcenter.autostart.AutoStartManagementActivity",
        ),
        // OPPO / realme / 一加（ColorOS）
        componentIntent(
            "com.coloros.safecenter",
            "com.coloros.safecenter.permission.startup.StartupAppListActivity",
        ),
        componentIntent(
            "com.coloros.safecenter",
            "com.coloros.safecenter.startupapp.StartupAppListActivity",
        ),
        componentIntent(
            "com.oppo.safe",
            "com.oppo.safe.permission.startup.StartupAppListActivity",
        ),
        componentIntent(
            "com.oneplus.security",
            "com.oneplus.security.chainlaunch.view.ChainLaunchAppListActivity",
        ),
        // vivo / iQOO
        componentIntent(
            "com.vivo.permissionmanager",
            "com.vivo.permissionmanager.activity.BgStartUpManagerActivity",
        ),
        componentIntent(
            "com.iqoo.secure",
            "com.iqoo.secure.ui.phoneoptimize.BgStartUpManagerActivity",
        ),
        // 华为 / 荣耀（EMUI / HarmonyOS / MagicOS）
        Intent("huawei.intent.action.HSM_BOOTAPP_MANAGER"),
        componentIntent(
            "com.huawei.systemmanager",
            "com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        ),
        componentIntent(
            "com.huawei.systemmanager",
            "com.huawei.systemmanager.optimize.process.ProtectActivity",
        ),
        componentIntent(
            "com.hihonor.systemmanager",
            "com.hihonor.systemmanager.startupmgr.ui.StartupNormalAppListActivity",
        ),
        // 魅族（Flyme）
        componentIntent(
            "com.meizu.safe",
            "com.meizu.safe.permission.SmartBGActivity",
        ),
        Intent("com.meizu.safe.permission.SHOW_APPSEC")
            .addCategory(Intent.CATEGORY_DEFAULT)
            .putExtra("packageName", context.packageName),
        // 三星（国行 OneUI）
        componentIntent(
            "com.samsung.android.sm_cn",
            "com.samsung.android.sm.autorun.ui.AutoRunActivity",
        ),
    )

    private fun componentIntent(packageName: String, className: String): Intent =
        Intent().setComponent(ComponentName(packageName, className))

    private fun isCandidateLaunchable(context: Context, candidate: Intent): Boolean {
        val resolveInfo = runCatching {
            context.packageManager.resolveActivity(candidate, 0)
        }.getOrNull() ?: return false
        val activityInfo = resolveInfo.activityInfo ?: return false
        if (!activityInfo.exported) return false
        val requiredPerm = activityInfo.permission
        if (!requiredPerm.isNullOrEmpty() &&
            context.checkSelfPermission(requiredPerm) != PackageManager.PERMISSION_GRANTED
        ) {
            return false
        }
        return true
    }

    /** 本机是否存在可实际打开的自启动管理页（纯查询，不跳转）。 */
    fun hasAutostartSettings(context: Context): Boolean {
        val cached = autostartPageFound
        if (cached != null) return cached
        val found = autostartCandidates(context).any { candidate ->
            isCandidateLaunchable(context, candidate)
        }
        autostartPageFound = found
        return found
    }

    /**
     * 打开自启动设置。
     *
     * @return true = 真的跳到了厂商自启动页；false = 无法直达，已退回系统设置主页。
     */
    fun openAutostartSettings(context: Context): Boolean {
        for (candidate in autostartCandidates(context)) {
            if (!isCandidateLaunchable(context, candidate)) continue
            if (tryStart(context, Intent(candidate))) {
                Log.i(
                    TAG,
                    "autostart page opened: ${candidate.component?.flattenToShortString() ?: candidate.action}",
                )
                return true
            }
        }
        Log.i(TAG, "no usable autostart page, fall back to system settings")
        if (!tryStart(context, Intent(Settings.ACTION_SETTINGS))) {
            openAppDetailsFallback(context)
        }
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
