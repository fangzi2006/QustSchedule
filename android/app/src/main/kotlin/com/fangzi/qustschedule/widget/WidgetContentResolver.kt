package com.fangzi.qustschedule.widget

import java.util.Calendar
import java.util.Locale

internal data class TodayWidgetViewModel(
    val signedIn: Boolean,
    val headerTitle: String,
    val headerRight: String,
    val items: List<TimelineItemData>,
    val examBanner: UpcomingExamData?,
    val emptyMessage: String,
    val nowMs: Long,
)

internal data class NextWidgetViewModel(
    val signedIn: Boolean,
    val badge: String,
    val title: String,
    val timeText: String,
    val subtitle: String,
    val isExam: Boolean,
    val isOngoing: Boolean,
    val colorIndex: Int,
)

internal data class WeekWidgetViewModel(
    val signedIn: Boolean,
    val weekPlan: WeekPlanData?,
    val todayWeekday: Int,
    val showWeekend: Boolean,
)

/**
 * 纯逻辑视图解析器：从 [WidgetSnapshotModel] 按当前时刻计算三类小组件的展示内容与下一次刷新节点。
 */
internal object WidgetContentResolver {

    private const val UPCOMING_EXAM_WINDOW_DAYS = 7

    fun resolveToday(
        snapshot: WidgetSnapshotModel?,
        style: WidgetStyleData,
        nowMs: Long,
    ): TodayWidgetViewModel {
        if (snapshot == null || !snapshot.signedIn) {
            return TodayWidgetViewModel(
                signedIn = false,
                headerTitle = "今日课表",
                headerRight = "未登录",
                items = emptyList(),
                examBanner = null,
                emptyMessage = "打开青科课表通登录后自动同步课表",
                nowMs = nowMs,
            )
        }

        val todayIso = formatIsoDate(nowMs)
        val tomorrowIso = formatIsoDate(addDays(nowMs, 1))
        val todayPlan = snapshot.days.firstOrNull { it.dateIso == todayIso }
        val tomorrowPlan = snapshot.days.firstOrNull { it.dateIso == tomorrowIso }
        val todayWeekday = weekdayOf(nowMs)

        fun allowed(item: TimelineItemData): Boolean = style.showExams || !item.isExam

        val todayAll = todayPlan?.items?.filter(::allowed).orEmpty()
        val hasRemainingToday = todayAll.any { it.endMs > nowMs }
        val visibleToday = if (style.finishedCourseMode == "hide") {
            todayAll.filter { it.endMs > nowMs }
        } else {
            todayAll
        }

        if (visibleToday.isNotEmpty() && hasRemainingToday) {
            val weekPrefix = if ((todayPlan?.week ?: 0) > 0) "第${todayPlan!!.week}周 " else ""
            return TodayWidgetViewModel(
                signedIn = true,
                headerTitle = "今日课表",
                headerRight = "$weekPrefix${weekdayName(todayPlan?.weekday ?: todayWeekday)}",
                items = visibleToday,
                examBanner = null,
                emptyMessage = "",
                nowMs = nowMs,
            )
        }

        val tomorrowItems = tomorrowPlan?.items?.filter(::allowed).orEmpty()
        if (tomorrowItems.isNotEmpty()) {
            val weekPrefix = if ((tomorrowPlan?.week ?: 0) > 0) "第${tomorrowPlan!!.week}周 " else ""
            return TodayWidgetViewModel(
                signedIn = true,
                headerTitle = "明日预告",
                headerRight = "$weekPrefix${weekdayName(tomorrowPlan?.weekday ?: weekdayOf(addDays(nowMs, 1)))}",
                items = tomorrowItems,
                examBanner = null,
                emptyMessage = "",
                nowMs = nowMs,
            )
        }

        if (style.showExams) {
            val nearestExam = findNearestExamWithinWindow(snapshot, nowMs)
            if (nearestExam != null) {
                val remainingCount = snapshot.upcomingExams.count { it.endMs > nowMs }
                return TodayWidgetViewModel(
                    signedIn = true,
                    headerTitle = "近期考试",
                    headerRight = "${remainingCount}场待考",
                    items = emptyList(),
                    examBanner = nearestExam,
                    emptyMessage = "",
                    nowMs = nowMs,
                )
            }
        }

        val fallbackMsg = if (todayPlan != null && todayAll.isNotEmpty()) {
            "今日课程已全部结束，好好休息"
        } else {
            "今明两日无课，好好休息"
        }
        val weekPrefix = if ((todayPlan?.week ?: 0) > 0) "第${todayPlan!!.week}周 " else ""
        return TodayWidgetViewModel(
            signedIn = true,
            headerTitle = "今日课表",
            headerRight = "$weekPrefix${weekdayName(todayWeekday)}",
            items = visibleToday,
            examBanner = null,
            emptyMessage = fallbackMsg,
            nowMs = nowMs,
        )
    }

    fun resolveNext(
        snapshot: WidgetSnapshotModel?,
        style: WidgetStyleData,
        nowMs: Long,
    ): NextWidgetViewModel {
        if (snapshot == null || !snapshot.signedIn) {
            return NextWidgetViewModel(
                signedIn = false,
                badge = "青科课表通",
                title = "轻触登录同步课表",
                timeText = "",
                subtitle = "登录后自动显示下一节课",
                isExam = false,
                isOngoing = false,
                colorIndex = 0,
            )
        }

        val todayIso = formatIsoDate(nowMs)
        val tomorrowIso = formatIsoDate(addDays(nowMs, 1))
        val todayPlan = snapshot.days.firstOrNull { it.dateIso == todayIso }
        val tomorrowPlan = snapshot.days.firstOrNull { it.dateIso == tomorrowIso }
        fun allowed(item: TimelineItemData): Boolean = style.showExams || !item.isExam

        val todayItems = todayPlan?.items?.filter(::allowed).orEmpty()
        for (item in todayItems) {
            if (item.startMs <= nowMs && item.endMs > nowMs) {
                return NextWidgetViewModel(
                    signedIn = true,
                    badge = if (item.isExam) "正在考试" else "正在上课",
                    title = item.title,
                    timeText = if (item.startLabel.isNotEmpty()) "${item.startLabel}-${item.endLabel}" else "",
                    subtitle = itemSubtitle(item, style),
                    isExam = item.isExam,
                    isOngoing = true,
                    colorIndex = item.colorIndex,
                )
            }
        }

        for (item in todayItems) {
            if (item.startMs > nowMs) {
                return NextWidgetViewModel(
                    signedIn = true,
                    badge = if (item.isExam) "下一场考试" else "今日下一节",
                    title = item.title,
                    timeText = if (item.startLabel.isNotEmpty()) "${item.startLabel}-${item.endLabel}" else "",
                    subtitle = itemSubtitle(item, style),
                    isExam = item.isExam,
                    isOngoing = false,
                    colorIndex = item.colorIndex,
                )
            }
        }

        val tomorrowItems = tomorrowPlan?.items?.filter(::allowed).orEmpty()
        if (tomorrowItems.isNotEmpty()) {
            val first = tomorrowItems.first()
            return NextWidgetViewModel(
                signedIn = true,
                badge = if (first.isExam) "明日考试" else "明日第一节",
                title = first.title,
                timeText = if (first.startLabel.isNotEmpty()) "${first.startLabel}-${first.endLabel}" else "",
                subtitle = itemSubtitle(first, style),
                isExam = first.isExam,
                isOngoing = false,
                colorIndex = first.colorIndex,
            )
        }

        if (style.showExams) {
            val nearestExam = findNearestExamWithinWindow(snapshot, nowMs)
            if (nearestExam != null) {
                val days = calendarDayDiff(nowMs, nearestExam.startMs)
                val badge = if (days <= 0) "今天考试" else "考试倒计时 ${days}天"
                val weekPart = if (nearestExam.week > 0) {
                    "第${nearestExam.week}周 ${weekdayName(nearestExam.weekday)} · "
                } else {
                    ""
                }
                val datePart = if (nearestExam.dateIso.length >= 10) {
                    nearestExam.dateIso.substring(5)
                } else {
                    nearestExam.dateIso
                }
                return NextWidgetViewModel(
                    signedIn = true,
                    badge = badge,
                    title = nearestExam.courseName,
                    timeText = "$weekPart$datePart ${nearestExam.timeLabel}",
                    subtitle = listOfNotEmpty(
                        if (style.showLocation) nearestExam.location else "",
                        if (nearestExam.seatNumber.isNotEmpty()) "${nearestExam.seatNumber}座" else "",
                    ),
                    isExam = true,
                    isOngoing = false,
                    colorIndex = nearestExam.colorIndex,
                )
            }
        }

        return NextWidgetViewModel(
            signedIn = true,
            badge = "日程空闲",
            title = "近期暂无课程",
            timeText = "",
            subtitle = "今明两日无课，好好休息",
            isExam = false,
            isOngoing = false,
            colorIndex = 0,
        )
    }

    fun resolveWeek(
        snapshot: WidgetSnapshotModel?,
        style: WidgetStyleData,
        nowMs: Long,
    ): WeekWidgetViewModel {
        if (snapshot == null || !snapshot.signedIn || snapshot.weeks.isEmpty()) {
            return WeekWidgetViewModel(
                signedIn = snapshot?.signedIn ?: false,
                weekPlan = null,
                todayWeekday = weekdayOf(nowMs),
                showWeekend = style.weekendMode == "show",
            )
        }
        val mondayIso = formatIsoDate(mondayOf(nowMs))
        val weekPlan = snapshot.weeks.firstOrNull { it.startDateIso == mondayIso }
            ?: snapshot.weeks.first()
        val todayWeekday = weekdayOf(nowMs)
        val hasWeekendClass = weekPlan.blocks.any { it.day >= 6 }
        val showWeekend = when (style.weekendMode) {
            "show" -> true
            "hide" -> false
            else -> hasWeekendClass || todayWeekday >= 6
        }
        return WeekWidgetViewModel(
            signedIn = true,
            weekPlan = weekPlan,
            todayWeekday = todayWeekday,
            showWeekend = showWeekend,
        )
    }

    /**
     * 计算下一次必须刷新小组件的精确时间戳：
     * 下一节课/考试的开始或结束时刻，与次日 00:01 取最小值（附加 +1000ms 余量）。
     */
    fun computeNextRefreshAtMs(snapshot: WidgetSnapshotModel?, nowMs: Long): Long {
        var earliest = nextMidnightPlusOneMinute(nowMs)
        if (snapshot == null || !snapshot.signedIn) return earliest

        val threshold = nowMs + 500L
        for (day in snapshot.days) {
            for (item in day.items) {
                if (item.startMs > threshold && item.startMs + 1000L < earliest) {
                    earliest = item.startMs + 1000L
                }
                if (item.endMs > threshold && item.endMs + 1000L < earliest) {
                    earliest = item.endMs + 1000L
                }
            }
        }
        for (exam in snapshot.upcomingExams) {
            if (exam.startMs > threshold && exam.startMs + 1000L < earliest) {
                earliest = exam.startMs + 1000L
            }
            if (exam.endMs > threshold && exam.endMs + 1000L < earliest) {
                earliest = exam.endMs + 1000L
            }
        }
        return earliest.coerceAtLeast(nowMs + 5_000L)
    }

    private fun findNearestExamWithinWindow(
        snapshot: WidgetSnapshotModel,
        nowMs: Long,
    ): UpcomingExamData? {
        for (exam in snapshot.upcomingExams) {
            if (exam.endMs <= nowMs) continue
            val days = calendarDayDiff(nowMs, exam.startMs)
            if (days <= UPCOMING_EXAM_WINDOW_DAYS) return exam
        }
        return null
    }

    private fun itemSubtitle(item: TimelineItemData, style: WidgetStyleData): String =
        listOfNotEmpty(
            if (style.showLocation) item.location else "",
            if (item.isExam && item.seatNumber.isNotEmpty()) "${item.seatNumber}座" else "",
            if (!item.isExam && style.showTeacher) item.teacher else "",
        )

    private fun listOfNotEmpty(vararg parts: String): String =
        parts.filter { it.isNotEmpty() }.joinToString(" · ")

    fun calendarDayDiff(fromMs: Long, toMs: Long): Int {
        val c1 = dayStartCal(fromMs)
        val c2 = dayStartCal(toMs)
        val diffMs = c2.timeInMillis - c1.timeInMillis + 12 * 3600_000L
        return (diffMs / 86_400_000L).toInt()
    }

    fun weekdayName(weekday: Int): String = when (weekday) {
        1 -> "周一"
        2 -> "周二"
        3 -> "周三"
        4 -> "周四"
        5 -> "周五"
        6 -> "周六"
        7 -> "周日"
        else -> ""
    }

    private fun weekdayOf(ms: Long): Int {
        val cal = Calendar.getInstance().apply { timeInMillis = ms }
        return when (cal.get(Calendar.DAY_OF_WEEK)) {
            Calendar.MONDAY -> 1
            Calendar.TUESDAY -> 2
            Calendar.WEDNESDAY -> 3
            Calendar.THURSDAY -> 4
            Calendar.FRIDAY -> 5
            Calendar.SATURDAY -> 6
            Calendar.SUNDAY -> 7
            else -> 1
        }
    }

    private fun mondayOf(ms: Long): Long {
        val wd = weekdayOf(ms)
        return addDays(ms, -(wd - 1))
    }

    private fun addDays(ms: Long, days: Int): Long {
        val cal = Calendar.getInstance().apply {
            timeInMillis = ms
            add(Calendar.DAY_OF_YEAR, days)
        }
        return cal.timeInMillis
    }

    private fun dayStartCal(ms: Long): Calendar = Calendar.getInstance().apply {
        timeInMillis = ms
        set(Calendar.HOUR_OF_DAY, 0)
        set(Calendar.MINUTE, 0)
        set(Calendar.SECOND, 0)
        set(Calendar.MILLISECOND, 0)
    }

    private fun nextMidnightPlusOneMinute(nowMs: Long): Long =
        Calendar.getInstance().apply {
            timeInMillis = nowMs
            add(Calendar.DAY_OF_YEAR, 1)
            set(Calendar.HOUR_OF_DAY, 0)
            set(Calendar.MINUTE, 1)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }.timeInMillis

    private fun formatIsoDate(ms: Long): String {
        val cal = Calendar.getInstance().apply { timeInMillis = ms }
        return String.format(
            Locale.US,
            "%04d-%02d-%02d",
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
        )
    }
}
