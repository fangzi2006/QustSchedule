package com.fangzi.qustschedule.reminder

import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject

/** payload 格式不合法（版本未知、字段缺失、时间戳不合理……）。 */
class ReminderPayloadException(message: String) : IllegalArgumentException(message)

/** 一条待提醒的课程实例。时间全部是绝对毫秒，原生不做任何日期计算。 */
data class ReminderEvent(
    val id: String,
    val name: String,
    val teacher: String,
    val location: String,
    val startMs: Long,
    val endMs: Long,
    val remindAtMs: Long,
    val startPeriod: Int,
    val endPeriod: Int,
    val week: Int,
)

/**
 * Dart 侧规划好、原生只负责执行的提醒清单。
 *
 * 解析必须**严格**：任何一条不合法都整体拒绝，让旧 payload 继续生效，
 * 而不是"能排几条排几条"——半份课表的提醒比没有提醒更难排查。
 */
data class ReminderPayload(
    val version: Int,
    val generatedAtMs: Long,
    val leadMinutes: Int,
    val fingerprint: String,
    val style: String,
    /** 流体云是否显示到下课（false = 上课即收起）。缺字段按 false。 */
    val fluidUntilEnd: Boolean,
    val events: List<ReminderEvent>,
) {
    companion object {
        const val VERSION = 1

        /** 横幅通知。 */
        const val STYLE_BANNER = "banner"

        /** 流体云常驻卡片（前台服务 + 进度通知）。 */
        const val STYLE_FLUID = "fluid"

        /** 单次 payload 的事件上限（Dart 侧规划 120 条，这里留余量）。 */
        const val MAX_EVENTS = 200

        /** 一条提醒最多提前多久（分钟），超出视为脏数据。 */
        private const val MAX_LEAD_MINUTES = 180

        /** 节次合理范围。 */
        private const val MAX_PERIOD = 30

        fun parse(json: String): ReminderPayload {
            val root = try {
                JSONObject(json)
            } catch (error: JSONException) {
                throw ReminderPayloadException("payload 不是合法 JSON")
            }

            val version = root.optInt("v", 0)
            if (version < 1 || version > VERSION) {
                throw ReminderPayloadException("未知 payload 版本：$version")
            }
            val generatedAtMs = root.optLong("generatedAtMs", 0L)
            if (generatedAtMs <= 0L) {
                throw ReminderPayloadException("generatedAtMs 不合法")
            }
            val leadMinutes = root.optInt("leadMinutes", -1)
            if (leadMinutes <= 0 || leadMinutes > MAX_LEAD_MINUTES) {
                throw ReminderPayloadException("leadMinutes 不合法：$leadMinutes")
            }
            val fingerprint = root.optString("fingerprint", "")
            if (fingerprint.isEmpty()) {
                throw ReminderPayloadException("fingerprint 为空")
            }
            val style = root.optString("style", STYLE_BANNER)
            if (style != STYLE_BANNER && style != STYLE_FLUID) {
                throw ReminderPayloadException("未知提醒形态：$style")
            }

            val array = root.optJSONArray("events") ?: JSONArray()
            if (array.length() > MAX_EVENTS) {
                throw ReminderPayloadException("事件过多：${array.length()}")
            }
            val events = ArrayList<ReminderEvent>(array.length())
            val seen = HashSet<String>(array.length())
            for (index in 0 until array.length()) {
                val item = array.optJSONObject(index)
                    ?: throw ReminderPayloadException("第 $index 条不是对象")
                val event = parseEvent(item)
                if (!seen.add(event.id)) {
                    throw ReminderPayloadException("事件 id 重复：${event.id}")
                }
                events.add(event)
            }

            return ReminderPayload(
                version = version,
                generatedAtMs = generatedAtMs,
                leadMinutes = leadMinutes,
                fingerprint = fingerprint,
                style = style,
                fluidUntilEnd = root.optBoolean("fluidUntilEnd", false),
                events = events,
            )
        }

        private fun parseEvent(json: JSONObject): ReminderEvent {
            val id = json.optString("id", "")
            if (id.isEmpty() || id.length > 64) {
                throw ReminderPayloadException("事件 id 不合法")
            }
            val startMs = json.optLong("startMs", 0L)
            val endMs = json.optLong("endMs", 0L)
            val remindAtMs = json.optLong("remindAtMs", 0L)
            if (startMs <= 0L || remindAtMs <= 0L) {
                throw ReminderPayloadException("$id 的时间戳不合法")
            }
            if (remindAtMs >= startMs) {
                throw ReminderPayloadException("$id 的提醒时刻不早于上课时刻")
            }
            val startPeriod = json.optInt("startPeriod", 0)
            val endPeriod = json.optInt("endPeriod", 0)
            if (startPeriod < 1 || startPeriod > MAX_PERIOD ||
                endPeriod < startPeriod || endPeriod > MAX_PERIOD
            ) {
                throw ReminderPayloadException("$id 的节次不合法")
            }
            return ReminderEvent(
                id = id,
                name = json.optString("name", ""),
                teacher = json.optString("teacher", ""),
                location = json.optString("location", ""),
                startMs = startMs,
                endMs = if (endMs >= startMs) endMs else startMs,
                remindAtMs = remindAtMs,
                startPeriod = startPeriod,
                endPeriod = endPeriod,
                week = json.optInt("week", 0),
            )
        }
    }
}
