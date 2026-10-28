package com.fangzi.qustschedule.reminder

import android.content.Context
import android.content.SharedPreferences
import android.util.Log

/**
 * 提醒的本地持久化：payload 原文 + 指纹 + 已排闹钟账本 + 形态。
 *
 * 账本（`alarm_codes`）是这套实现的关键：取消闹钟必须拿到**完全相同**的
 * PendingIntent，而它的等价性只看 action/class/requestCode（extras 不参与）。
 * 记下"上次真正排下去的那些 code"，才能做到"只撤该撤的、其余原地覆盖"，
 * 避免"先全撤再全排"造成的空窗。
 *
 * 关键写入一律 `commit()`：`apply()` 异步落盘，进程恰好被杀时 payload 与账本
 * 会不一致——那正是"开机后重复响/该响不响"的来源。
 */
class ReminderStore(context: Context) {

    private val appContext = context.applicationContext
    @Volatile
    private var cachedPayload: ReminderPayload? = null

    private val prefs: SharedPreferences =
        appContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    // -------------------------------------------------------------------------
    // payload
    // -------------------------------------------------------------------------

    fun savePayload(json: String, payload: ReminderPayload) {
        cachedPayload = payload
        prefs.edit()
            .putString(KEY_PAYLOAD_JSON, json)
            .putString(KEY_FINGERPRINT, payload.fingerprint)
            .putLong(KEY_PAYLOAD_AT_MS, System.currentTimeMillis())
            .putInt(KEY_LEAD_MINUTES, payload.leadMinutes)
            .putString(KEY_STYLE, payload.style)
            .commit()
    }

    fun loadPayloadJson(): String? = prefs.getString(KEY_PAYLOAD_JSON, null)

    /** 解析失败返回 null（保留原文，避免脏数据把旧 payload 覆盖掉）。 */
    fun loadPayload(): ReminderPayload? {
        cachedPayload?.let { return it }
        val json = loadPayloadJson() ?: return null
        return try {
            ReminderPayload.parse(json)
        } catch (error: ReminderPayloadException) {
            Log.w(TAG, "stored payload invalid: ${error.message}")
            null
        }
    }

    fun fingerprint(): String = prefs.getString(KEY_FINGERPRINT, "") ?: ""

    fun payloadAtMs(): Long = prefs.getLong(KEY_PAYLOAD_AT_MS, 0L)

    fun leadMinutes(): Int = prefs.getInt(KEY_LEAD_MINUTES, 0)

    fun style(): String =
        prefs.getString(KEY_STYLE, ReminderPayload.STYLE_BANNER)
            ?: ReminderPayload.STYLE_BANNER

    // -------------------------------------------------------------------------
    // 闹钟账本
    // -------------------------------------------------------------------------

    fun alarmCodes(): List<Int> {
        val raw = prefs.getString(KEY_ALARM_CODES, "") ?: ""
        if (raw.isEmpty()) return emptyList()
        return raw.split(',')
            .mapNotNull { it.toIntOrNull() }
            .distinct()
    }

    fun setAlarmCodes(codes: Collection<Int>) {
        prefs.edit()
            .putString(KEY_ALARM_CODES, codes.distinct().joinToString(","))
            .commit()
    }

    fun removeAlarmCode(code: Int) {
        setAlarmCodes(alarmCodes().filter { it != code })
    }

    fun clearAlarmCodes() {
        prefs.edit().remove(KEY_ALARM_CODES).commit()
    }

    // -------------------------------------------------------------------------
    // 脏标记
    // -------------------------------------------------------------------------

    /**
     * 时间/时区被改过：当前 payload 的绝对毫秒可能已与"第几周"错位，
     * 下次 App 打开时由 Dart 重新规划（原生只知道自己排了什么）。
     */
    fun markDirty() {
        prefs.edit().putBoolean(KEY_DIRTY, true).commit()
    }

    fun isDirty(): Boolean = prefs.getBoolean(KEY_DIRTY, false)

    fun clearDirty() {
        prefs.edit().putBoolean(KEY_DIRTY, false).commit()
    }

    /** 关闭提醒 / 退出登录：连 payload 一起清，避免旧课表继续响。 */
    fun clear() {
        cachedPayload = null
        prefs.edit()
            .remove(KEY_PAYLOAD_JSON)
            .remove(KEY_FINGERPRINT)
            .remove(KEY_PAYLOAD_AT_MS)
            .remove(KEY_LEAD_MINUTES)
            .remove(KEY_STYLE)
            .remove(KEY_ALARM_CODES)
            .remove(KEY_DIRTY)
            .commit()
    }

    companion object {
        const val TAG = "ReminderStore"
        const val PREFS = "reminder_store"

        const val KEY_PAYLOAD_JSON = "payload_json"
        const val KEY_FINGERPRINT = "fingerprint"
        const val KEY_PAYLOAD_AT_MS = "payload_at_ms"
        const val KEY_LEAD_MINUTES = "lead_minutes"
        const val KEY_STYLE = "style"
        const val KEY_ALARM_CODES = "alarm_codes"
        const val KEY_DIRTY = "dirty"
    }
}
