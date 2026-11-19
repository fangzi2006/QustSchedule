package com.fangzi.qustschedule.widget

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

internal data class WidgetStyleData(
    val preset: String = "minimal_white",
    val themeMode: String = "light",
    val backgroundOpacity: Float = 1.0f,
    val cornerRadius: Float = 20.0f,
    val fontScale: Float = 1.0f,
    val density: String = "comfortable",
    val showHeader: Boolean = true,
    val showLocation: Boolean = true,
    val showTeacher: Boolean = true,
    val showTime: Boolean = true,
    val showExams: Boolean = true,
    val autoSwitchTomorrow: Boolean = true,
    val finishedCourseMode: String = "dim",
    val weekendMode: String = "auto",
) {
    companion object {
        fun defaultFor(kind: String): WidgetStyleData = WidgetStyleData(
            showTeacher = kind != KIND_WEEK,
        )

        fun fromJson(obj: JSONObject?, kind: String): WidgetStyleData {
            val base = defaultFor(kind)
            if (obj == null) return base
            return WidgetStyleData(
                preset = obj.optString("preset", base.preset),
                themeMode = obj.optString("themeMode", base.themeMode),
                backgroundOpacity = obj.optDouble("backgroundOpacity", base.backgroundOpacity.toDouble())
                    .toFloat().coerceIn(0f, 1f),
                cornerRadius = obj.optDouble("cornerRadius", base.cornerRadius.toDouble())
                    .toFloat().coerceIn(8f, 28f),
                fontScale = obj.optDouble("fontScale", base.fontScale.toDouble())
                    .toFloat().coerceIn(0.75f, 1.20f),
                density = obj.optString("density", base.density),
                showHeader = if (obj.has("showHeader")) obj.optBoolean("showHeader", base.showHeader) else base.showHeader,
                showLocation = if (obj.has("showLocation")) obj.optBoolean("showLocation", base.showLocation) else base.showLocation,
                showTeacher = if (obj.has("showTeacher")) obj.optBoolean("showTeacher", base.showTeacher) else base.showTeacher,
                showTime = if (obj.has("showTime")) obj.optBoolean("showTime", base.showTime) else base.showTime,
                showExams = if (obj.has("showExams")) obj.optBoolean("showExams", base.showExams) else base.showExams,
                autoSwitchTomorrow = if (obj.has("autoSwitchTomorrow")) {
                    obj.optBoolean("autoSwitchTomorrow", base.autoSwitchTomorrow)
                } else {
                    base.autoSwitchTomorrow
                },
                finishedCourseMode = obj.optString("finishedCourseMode", base.finishedCourseMode),
                weekendMode = obj.optString("weekendMode", base.weekendMode),
            )
        }
    }
}

internal data class TimelineItemData(
    val kind: String,
    val id: String,
    val title: String,
    val location: String,
    val teacher: String,
    val seatNumber: String,
    val examForm: String,
    val startPeriod: Int,
    val endPeriod: Int,
    val startLabel: String,
    val endLabel: String,
    val startMs: Long,
    val endMs: Long,
    val colorIndex: Int,
    val rescheduled: Boolean,
) {
    val isExam: Boolean get() = kind == "exam"

    companion object {
        fun fromJson(obj: JSONObject): TimelineItemData = TimelineItemData(
            kind = obj.optString("kind", "course"),
            id = obj.optString("id", ""),
            title = obj.optString("title", ""),
            location = obj.optString("location", ""),
            teacher = obj.optString("teacher", ""),
            seatNumber = obj.optString("seatNumber", ""),
            examForm = obj.optString("examForm", ""),
            startPeriod = obj.optInt("startPeriod", 0),
            endPeriod = obj.optInt("endPeriod", 0),
            startLabel = obj.optString("startLabel", ""),
            endLabel = obj.optString("endLabel", ""),
            startMs = obj.optLong("startMs", 0L),
            endMs = obj.optLong("endMs", 0L),
            colorIndex = obj.optInt("colorIndex", 0),
            rescheduled = obj.optBoolean("rescheduled", false),
        )
    }
}

internal data class DayPlanData(
    val dateIso: String,
    val week: Int,
    val weekday: Int,
    val items: List<TimelineItemData>,
) {
    companion object {
        fun fromJson(obj: JSONObject): DayPlanData {
            val rawItems = obj.optJSONArray("items") ?: JSONArray()
            val items = ArrayList<TimelineItemData>(rawItems.length())
            for (i in 0 until rawItems.length()) {
                val itemObj = rawItems.optJSONObject(i) ?: continue
                items.add(TimelineItemData.fromJson(itemObj))
            }
            return DayPlanData(
                dateIso = obj.optString("dateIso", ""),
                week = obj.optInt("week", 0),
                weekday = obj.optInt("weekday", 1),
                items = items,
            )
        }
    }
}

internal data class UpcomingExamData(
    val id: String,
    val courseName: String,
    val startMs: Long,
    val endMs: Long,
    val dateIso: String,
    val timeLabel: String,
    val week: Int,
    val weekday: Int,
    val location: String,
    val seatNumber: String,
    val examForm: String,
    val colorIndex: Int,
) {
    companion object {
        fun fromJson(obj: JSONObject): UpcomingExamData = UpcomingExamData(
            id = obj.optString("id", ""),
            courseName = obj.optString("courseName", ""),
            startMs = obj.optLong("startMs", 0L),
            endMs = obj.optLong("endMs", 0L),
            dateIso = obj.optString("dateIso", ""),
            timeLabel = obj.optString("timeLabel", ""),
            week = obj.optInt("week", 0),
            weekday = obj.optInt("weekday", 1),
            location = obj.optString("location", ""),
            seatNumber = obj.optString("seatNumber", ""),
            examForm = obj.optString("examForm", ""),
            colorIndex = obj.optInt("colorIndex", 0),
        )
    }
}

internal data class WeekBlockData(
    val id: String,
    val name: String,
    val location: String,
    val teacher: String,
    val day: Int,
    val startPeriod: Int,
    val endPeriod: Int,
    val conflictIndex: Int,
    val conflictTotal: Int,
    val colorIndex: Int,
    val rescheduled: Boolean,
) {
    companion object {
        fun fromJson(obj: JSONObject): WeekBlockData = WeekBlockData(
            id = obj.optString("id", ""),
            name = obj.optString("name", ""),
            location = obj.optString("location", ""),
            teacher = obj.optString("teacher", ""),
            day = obj.optInt("day", 1),
            startPeriod = obj.optInt("startPeriod", 1),
            endPeriod = obj.optInt("endPeriod", 1),
            conflictIndex = obj.optInt("conflictIndex", 0),
            conflictTotal = obj.optInt("conflictTotal", 1).coerceAtLeast(1),
            colorIndex = obj.optInt("colorIndex", 0),
            rescheduled = obj.optBoolean("rescheduled", false),
        )
    }
}

internal data class WeekPlanData(
    val week: Int,
    val startDateIso: String,
    val dayLabels: List<String>,
    val maxSection: Int,
    val sectionStarts: List<String>,
    val sectionEnds: List<String>,
    val blocks: List<WeekBlockData>,
) {
    companion object {
        fun fromJson(obj: JSONObject): WeekPlanData {
            val labelsArr = obj.optJSONArray("dayLabels") ?: JSONArray()
            val labels = ArrayList<String>(labelsArr.length())
            for (i in 0 until labelsArr.length()) {
                labels.add(labelsArr.optString(i, ""))
            }
            val startsArr = obj.optJSONArray("sectionStarts") ?: JSONArray()
            val starts = ArrayList<String>(startsArr.length())
            for (i in 0 until startsArr.length()) {
                starts.add(startsArr.optString(i, ""))
            }
            val endsArr = obj.optJSONArray("sectionEnds") ?: JSONArray()
            val ends = ArrayList<String>(endsArr.length())
            for (i in 0 until endsArr.length()) {
                ends.add(endsArr.optString(i, ""))
            }
            val blocksArr = obj.optJSONArray("blocks") ?: JSONArray()
            val blocks = ArrayList<WeekBlockData>(blocksArr.length())
            for (i in 0 until blocksArr.length()) {
                val b = blocksArr.optJSONObject(i) ?: continue
                blocks.add(WeekBlockData.fromJson(b))
            }
            return WeekPlanData(
                week = obj.optInt("week", 1),
                startDateIso = obj.optString("startDateIso", ""),
                dayLabels = labels,
                maxSection = obj.optInt("maxSection", 12).coerceAtLeast(1),
                sectionStarts = starts,
                sectionEnds = ends,
                blocks = blocks,
            )
        }
    }
}

internal data class WidgetSnapshotModel(
    val version: Int,
    val signedIn: Boolean,
    val termId: String,
    val termStartIso: String,
    val maxWeek: Int,
    val fingerprint: String,
    val days: List<DayPlanData>,
    val upcomingExams: List<UpcomingExamData>,
    val weeks: List<WeekPlanData>,
    val styles: Map<String, WidgetStyleData>,
) {
    fun styleOf(kind: String): WidgetStyleData =
        styles[kind] ?: WidgetStyleData.defaultFor(kind)

    fun kindSignature(kind: String): Int = when (kind) {
        KIND_WEEK -> java.util.Objects.hash(
            version,
            signedIn,
            termId,
            termStartIso,
            maxWeek,
            weeks,
            styleOf(KIND_WEEK),
        )
        else -> java.util.Objects.hash(
            version,
            signedIn,
            termId,
            termStartIso,
            maxWeek,
            days,
            upcomingExams,
            styleOf(kind),
        )
    }

    companion object {
        fun parse(rawJson: String): WidgetSnapshotModel? {
            if (rawJson.isBlank()) return null
            return try {
                val root = JSONObject(rawJson)
                val daysArr = root.optJSONArray("days") ?: JSONArray()
                val days = ArrayList<DayPlanData>(daysArr.length())
                for (i in 0 until daysArr.length()) {
                    val d = daysArr.optJSONObject(i) ?: continue
                    days.add(DayPlanData.fromJson(d))
                }
                val examsArr = root.optJSONArray("upcomingExams") ?: JSONArray()
                val exams = ArrayList<UpcomingExamData>(examsArr.length())
                for (i in 0 until examsArr.length()) {
                    val e = examsArr.optJSONObject(i) ?: continue
                    exams.add(UpcomingExamData.fromJson(e))
                }
                val weeksArr = root.optJSONArray("weeks") ?: JSONArray()
                val weeks = ArrayList<WeekPlanData>(weeksArr.length())
                for (i in 0 until weeksArr.length()) {
                    val w = weeksArr.optJSONObject(i) ?: continue
                    weeks.add(WeekPlanData.fromJson(w))
                }
                val stylesObj = root.optJSONObject("styles")
                val styles = hashMapOf(
                    KIND_TODAY to WidgetStyleData.fromJson(stylesObj?.optJSONObject(KIND_TODAY), KIND_TODAY),
                    KIND_WEEK to WidgetStyleData.fromJson(stylesObj?.optJSONObject(KIND_WEEK), KIND_WEEK),
                    KIND_NEXT to WidgetStyleData.fromJson(stylesObj?.optJSONObject(KIND_NEXT), KIND_NEXT),
                )
                WidgetSnapshotModel(
                    version = root.optInt("v", 1),
                    signedIn = root.optBoolean("signedIn", false),
                    termId = root.optString("termId", ""),
                    termStartIso = root.optString("termStartIso", ""),
                    maxWeek = root.optInt("maxWeek", 18),
                    fingerprint = root.optString("fingerprint", ""),
                    days = days,
                    upcomingExams = exams,
                    weeks = weeks,
                    styles = styles,
                )
            } catch (_: Throwable) {
                null
            }
        }
    }
}

internal const val KIND_TODAY = "today"
internal const val KIND_WEEK = "week"
internal const val KIND_NEXT = "next"

internal object WidgetStore {

    private const val PREF_NAME = "qust_desktop_widget_v1"
    private const val KEY_SNAPSHOT = "snapshot_json"
    private const val KEY_TODAY_SIG_PREFIX = "today_header_sig_"
    private const val KEY_TODAY_WIDTH_PREFIX = "today_width_dp_"
    private const val KEY_TODAY_REV = "today_list_rev"
    private const val KEY_LAST_WEEK_RENDER_DATE = "last_week_render_date_iso"

    fun saveSnapshot(context: Context, payloadJson: String): WidgetSnapshotModel? {
        val parsed = WidgetSnapshotModel.parse(payloadJson) ?: return null
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_SNAPSHOT, payloadJson)
            .commit()
        return parsed
    }

    fun loadSnapshot(context: Context): WidgetSnapshotModel? {
        val raw = context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getString(KEY_SNAPSHOT, null) ?: return null
        return WidgetSnapshotModel.parse(raw)
    }

    fun saveTodayHeaderSig(context: Context, appWidgetId: Int, sig: String) {
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString("$KEY_TODAY_SIG_PREFIX$appWidgetId", sig)
            .commit()
    }

    fun loadTodayHeaderSig(context: Context, appWidgetId: Int): String? =
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getString("$KEY_TODAY_SIG_PREFIX$appWidgetId", null)

    fun saveTodayWidthDp(context: Context, appWidgetId: Int, widthDp: Int) {
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putInt("$KEY_TODAY_WIDTH_PREFIX$appWidgetId", widthDp)
            .commit()
    }

    fun loadTodayWidthDp(context: Context, appWidgetId: Int, fallback: Int = 260): Int =
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getInt("$KEY_TODAY_WIDTH_PREFIX$appWidgetId", fallback)

    fun bumpTodayRevision(context: Context): Int {
        val prefs = context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
        val next = prefs.getInt(KEY_TODAY_REV, 0) + 1
        prefs.edit().putInt(KEY_TODAY_REV, next).commit()
        return next
    }

    fun loadTodayRevision(context: Context): Int =
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getInt(KEY_TODAY_REV, 0)

    fun removeTodayWidgetMeta(context: Context, appWidgetId: Int) {
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove("$KEY_TODAY_SIG_PREFIX$appWidgetId")
            .remove("$KEY_TODAY_WIDTH_PREFIX$appWidgetId")
            .commit()
    }

    fun saveLastWeekRenderDateIso(context: Context, dateIso: String) {
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .putString(KEY_LAST_WEEK_RENDER_DATE, dateIso)
            .commit()
    }

    fun loadLastWeekRenderDateIso(context: Context): String? =
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .getString(KEY_LAST_WEEK_RENDER_DATE, null)

    fun clear(context: Context) {
        context.applicationContext
            .getSharedPreferences(PREF_NAME, Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_SNAPSHOT)
            .remove(KEY_LAST_WEEK_RENDER_DATE)
            .commit()
    }
}
