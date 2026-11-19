package com.fangzi.qustschedule.widget

import java.util.Calendar
import java.util.Locale
import kotlin.math.roundToInt

internal enum class NextStatusKind {
    ONGOING,
    TODAY,
    TOMORROW,
    EXAM_ONGOING,
    EXAM_UPCOMING,
    EMPTY,
    SIGNED_OUT,
    STALE,
}

internal data class TodayWidgetViewModel(
    val signedIn: Boolean,
    val isStale: Boolean,
    val isTomorrow: Boolean,
    val badgeText: String,
    val badgeTone: WidgetPillTone,
    val headerTitle: String,
    val headerRight: String,
    val compactCue: String,
    val items: List<TimelineItemData>,
    val examBanner: UpcomingExamData?,
    val emptyMessage: String,
    val nowMs: Long,
)

internal data class NextWidgetViewModel(
    val signedIn: Boolean,
    val statusKind: NextStatusKind,
    val badge: String,
    val shortBadge: String,
    val title: String,
    val timeText: String,
    val dateHint: String,
    val subtitle: String,
    val colorIndex: Int,
) {
    val isExam: Boolean
        get() = statusKind == NextStatusKind.EXAM_ONGOING || statusKind == NextStatusKind.EXAM_UPCOMING

    val hasCourseAccent: Boolean
        get() = colorIndex >= 0 &&
            statusKind != NextStatusKind.EMPTY &&
            statusKind != NextStatusKind.SIGNED_OUT &&
            statusKind != NextStatusKind.STALE
}

internal data class WeekWidgetViewModel(
    val signedIn: Boolean,
    val isStale: Boolean,
    val isTermEnded: Boolean,
    val weekPlan: WeekPlanData?,
    val isCurrentWeek: Boolean,
    val todayWeekday: Int,
    val showWeekend: Boolean,
    val dateRange: String,
)

internal data class WidgetRefreshPlan(
    val triggerAtMs: Long,
    val includeWeek: Boolean,
)

/**
 * 纯逻辑视图解析器：从 [WidgetSnapshotModel] 按当前时刻计算三类小组件的展示内容与精准刷新计划。
 */
internal object WidgetContentResolver {

    private const val UPCOMING_EXAM_WINDOW_DAYS = 7

    fun formatTimeRange(startLabel: String, endLabel: String): String {
        val s = startLabel.trim()
        val e = endLabel.trim()
        if (s.isEmpty()) return ""
        return if (e.isEmpty()) s else "$s-$e"
    }

    fun resolveToday(
        snapshot: WidgetSnapshotModel?,
        style: WidgetStyleData,
        nowMs: Long,
    ): TodayWidgetViewModel {
        if (snapshot == null || !snapshot.signedIn) {
            return TodayWidgetViewModel(
                signedIn = false,
                isStale = false,
                isTomorrow = false,
                badgeText = "",
                badgeTone = WidgetPillTone.NEUTRAL,
                headerTitle = "今日课表",
                headerRight = "未登录",
                compactCue = "",
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

        // 快照超过 14 天范围时提示刷新，避免静默误显空课表。
        if (snapshot.days.isNotEmpty() && todayPlan == null && tomorrowPlan == null) {
            return TodayWidgetViewModel(
                signedIn = true,
                isStale = true,
                isTomorrow = false,
                badgeText = "需刷新",
                badgeTone = WidgetPillTone.NEUTRAL,
                headerTitle = "今日课表",
                headerRight = "",
                compactCue = "",
                items = emptyList(),
                examBanner = null,
                emptyMessage = "课表数据已过期，轻触打开应用刷新",
                nowMs = nowMs,
            )
        }

        fun allowed(item: TimelineItemData): Boolean = style.showExams || !item.isExam

        val todayAll = todayPlan?.items?.filter(::allowed).orEmpty()
        val remainingToday = todayAll.filter { it.endMs > nowMs }
        val hasRemainingToday = remainingToday.isNotEmpty()
        val visibleToday = if (style.finishedCourseMode == "hide") {
            remainingToday
        } else {
            todayAll
        }
        val todayWeekLabel = weekAndWeekday(todayPlan?.week ?: 0, todayPlan?.weekday ?: todayWeekday)

        if (hasRemainingToday) {
            val allExams = remainingToday.all { it.isExam }
            val unit = if (allExams) "场" else "节"
            return TodayWidgetViewModel(
                signedIn = true,
                isStale = false,
                isTomorrow = false,
                badgeText = "",
                badgeTone = WidgetPillTone.ACCENT,
                headerTitle = todayWeekLabel,
                headerRight = "剩${remainingToday.size}$unit",
                compactCue = "",
                items = visibleToday,
                examBanner = null,
                emptyMessage = "",
                nowMs = nowMs,
            )
        }

        // 关闭「课后自动切明日预告」时，始终留在今天视图并严格遵循已结束课程策略。
        if (!style.autoSwitchTomorrow) {
            if (todayAll.isNotEmpty()) {
                return TodayWidgetViewModel(
                    signedIn = true,
                    isStale = false,
                    isTomorrow = false,
                    badgeText = "",
                    badgeTone = WidgetPillTone.ACCENT,
                    headerTitle = todayWeekLabel,
                    headerRight = "已结束",
                    compactCue = "",
                    items = visibleToday,
                    examBanner = null,
                    emptyMessage = "今日课程已全部结束",
                    nowMs = nowMs,
                )
            }
            if (style.showExams) {
                val nearestExam = findNearestExamWithinWindow(snapshot, nowMs)
                if (nearestExam != null) {
                    val remainingCount = snapshot.upcomingExams.count { it.endMs > nowMs }
                    return TodayWidgetViewModel(
                        signedIn = true,
                        isStale = false,
                        isTomorrow = false,
                        badgeText = "近期考试",
                        badgeTone = WidgetPillTone.EXAM,
                        headerTitle = "",
                        headerRight = "${remainingCount}场待考",
                        compactCue = "",
                        items = emptyList(),
                        examBanner = nearestExam,
                        emptyMessage = "",
                        nowMs = nowMs,
                    )
                }
            }
            return TodayWidgetViewModel(
                signedIn = true,
                isStale = false,
                isTomorrow = false,
                badgeText = "",
                badgeTone = WidgetPillTone.ACCENT,
                headerTitle = todayWeekLabel,
                headerRight = "无课",
                compactCue = "",
                items = emptyList(),
                examBanner = null,
                emptyMessage = "今日无课，好好休息",
                nowMs = nowMs,
            )
        }

        val tomorrowItems = tomorrowPlan?.items?.filter(::allowed).orEmpty()
        if (tomorrowItems.isNotEmpty()) {
            val tomorrowWeekday = tomorrowPlan?.weekday ?: weekdayOf(addDays(nowMs, 1))
            val tomorrowWeekLabel = weekAndWeekday(tomorrowPlan?.week ?: 0, tomorrowWeekday)
            val allExams = tomorrowItems.all { it.isExam }
            val unit = if (allExams) "场" else "节"
            return TodayWidgetViewModel(
                signedIn = true,
                isStale = false,
                isTomorrow = true,
                badgeText = "明日",
                badgeTone = WidgetPillTone.TOMORROW,
                headerTitle = tomorrowWeekLabel,
                headerRight = "共${tomorrowItems.size}$unit",
                compactCue = "明日 · ${weekdayName(tomorrowWeekday)}",
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
                    isStale = false,
                    isTomorrow = false,
                    badgeText = "近期考试",
                    badgeTone = WidgetPillTone.EXAM,
                    headerTitle = "",
                    headerRight = "${remainingCount}场待考",
                    compactCue = "",
                    items = emptyList(),
                    examBanner = nearestExam,
                    emptyMessage = "",
                    nowMs = nowMs,
                )
            }
        }

        val fallbackMsg = if (todayAll.isNotEmpty()) {
            "今日课程已全部结束，明日无课"
        } else {
            "今明两日无课，好好休息"
        }
        return TodayWidgetViewModel(
            signedIn = true,
            isStale = false,
            isTomorrow = false,
            badgeText = "",
            badgeTone = WidgetPillTone.ACCENT,
            headerTitle = todayWeekLabel,
            headerRight = if (todayAll.isNotEmpty()) "已结束" else "无课",
            compactCue = "",
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
                statusKind = NextStatusKind.SIGNED_OUT,
                badge = "青科课表通",
                shortBadge = "未登录",
                title = "轻触登录同步课表",
                timeText = "",
                dateHint = "",
                subtitle = "登录后自动显示下一节课",
                colorIndex = -1,
            )
        }

        val todayIso = formatIsoDate(nowMs)
        val tomorrowIso = formatIsoDate(addDays(nowMs, 1))
        val todayPlan = snapshot.days.firstOrNull { it.dateIso == todayIso }
        val tomorrowPlan = snapshot.days.firstOrNull { it.dateIso == tomorrowIso }

        if (snapshot.days.isNotEmpty() && todayPlan == null && tomorrowPlan == null) {
            return NextWidgetViewModel(
                signedIn = true,
                statusKind = NextStatusKind.STALE,
                badge = "需刷新",
                shortBadge = "需刷新",
                title = "课表数据已过期",
                timeText = "",
                dateHint = "",
                subtitle = "轻触打开青科课表通刷新",
                colorIndex = -1,
            )
        }

        fun allowed(item: TimelineItemData): Boolean = style.showExams || !item.isExam

        val todayItems = todayPlan?.items?.filter(::allowed).orEmpty()
        for (item in todayItems) {
            if (item.startMs <= nowMs && item.endMs > nowMs) {
                return NextWidgetViewModel(
                    signedIn = true,
                    statusKind = if (item.isExam) NextStatusKind.EXAM_ONGOING else NextStatusKind.ONGOING,
                    badge = if (item.isExam) "正在考试" else "正在上课",
                    shortBadge = if (item.isExam) "考试中" else "上课中",
                    title = item.title,
                    timeText = formatTimeRange(item.startLabel, item.endLabel),
                    dateHint = "",
                    subtitle = itemSubtitle(item, style),
                    colorIndex = item.colorIndex,
                )
            }
        }

        for (item in todayItems) {
            if (item.startMs > nowMs) {
                return NextWidgetViewModel(
                    signedIn = true,
                    statusKind = if (item.isExam) NextStatusKind.EXAM_UPCOMING else NextStatusKind.TODAY,
                    badge = if (item.isExam) "下一场考试" else "今日下一节",
                    shortBadge = if (item.isExam) "考试" else "下一节",
                    title = item.title,
                    timeText = formatTimeRange(item.startLabel, item.endLabel),
                    dateHint = "",
                    subtitle = itemSubtitle(item, style),
                    colorIndex = item.colorIndex,
                )
            }
        }

        val tomorrowItems = tomorrowPlan?.items?.filter(::allowed).orEmpty()
        if (tomorrowItems.isNotEmpty()) {
            val first = tomorrowItems.first()
            return NextWidgetViewModel(
                signedIn = true,
                statusKind = if (first.isExam) NextStatusKind.EXAM_UPCOMING else NextStatusKind.TOMORROW,
                badge = if (first.isExam) "明日考试" else "明日第一节",
                shortBadge = if (first.isExam) "明考" else "明日",
                title = first.title,
                timeText = formatTimeRange(first.startLabel, first.endLabel),
                dateHint = "",
                subtitle = itemSubtitle(first, style),
                colorIndex = first.colorIndex,
            )
        }

        if (style.showExams) {
            val nearestExam = findNearestExamWithinWindow(snapshot, nowMs)
            if (nearestExam != null) {
                val days = calendarDayDiff(nowMs, nearestExam.startMs)
                val badge = if (days <= 0) "今天考试" else "考试倒计时 ${days}天"
                val shortBadge = if (days <= 0) "今日考" else "${days}天后考"
                val datePart = shortMonthDay(nearestExam.dateIso)
                val hintParts = listOfNotNull(
                    datePart.takeIf { it.isNotEmpty() },
                    weekdayName(nearestExam.weekday).takeIf { it.isNotEmpty() },
                ).joinToString(" ")
                return NextWidgetViewModel(
                    signedIn = true,
                    statusKind = NextStatusKind.EXAM_UPCOMING,
                    badge = badge,
                    shortBadge = shortBadge,
                    title = nearestExam.courseName,
                    timeText = nearestExam.timeLabel,
                    dateHint = hintParts,
                    subtitle = listOfNotEmpty(
                        if (style.showLocation) nearestExam.location else "",
                        if (style.showLocation && nearestExam.seatNumber.isNotEmpty()) "${nearestExam.seatNumber}座" else "",
                    ),
                    colorIndex = nearestExam.colorIndex,
                )
            }
        }

        return NextWidgetViewModel(
            signedIn = true,
            statusKind = NextStatusKind.EMPTY,
            badge = "日程空闲",
            shortBadge = "空闲",
            title = "近期暂无课程",
            timeText = "",
            dateHint = "",
            subtitle = "今明两日无课，好好休息",
            colorIndex = -1,
        )
    }

    fun resolveWeek(
        snapshot: WidgetSnapshotModel?,
        style: WidgetStyleData,
        nowMs: Long,
    ): WeekWidgetViewModel {
        val todayWeekday = weekdayOf(nowMs)
        if (snapshot == null || !snapshot.signedIn || snapshot.weeks.isEmpty()) {
            return WeekWidgetViewModel(
                signedIn = snapshot?.signedIn ?: false,
                isStale = false,
                isTermEnded = false,
                weekPlan = null,
                isCurrentWeek = false,
                todayWeekday = todayWeekday,
                showWeekend = style.weekendMode == "show",
                dateRange = "",
            )
        }
        val todayIso = formatIsoDate(nowMs)
        val todayPlan = snapshot.days.firstOrNull { it.dateIso == todayIso }
        val mondayIso = formatIsoDate(mondayOf(nowMs))
        val matched = snapshot.weeks.firstOrNull { it.startDateIso == mondayIso }
        val lastWeekStart = snapshot.weeks.last().startDateIso
        if (matched == null && lastWeekStart.isNotEmpty() && mondayIso > lastWeekStart) {
            val isFreshPostTerm = todayPlan != null && todayPlan.week > snapshot.maxWeek
            return WeekWidgetViewModel(
                signedIn = true,
                isStale = !isFreshPostTerm,
                isTermEnded = isFreshPostTerm,
                weekPlan = null,
                isCurrentWeek = false,
                todayWeekday = todayWeekday,
                showWeekend = style.weekendMode == "show",
                dateRange = "",
            )
        }
        val weekPlan = matched ?: snapshot.weeks.first()
        val isCurrentWeek = weekPlan.startDateIso == mondayIso
        val hasWeekendClass = weekPlan.blocks.any { it.day >= 6 }
        // 「有课显示」严格以本周是否存在周末课程为准。
        val showWeekend = when (style.weekendMode) {
            "show" -> true
            "hide" -> false
            else -> hasWeekendClass
        }
        val dateRange = if (weekPlan.dayLabels.size >= 2) {
            val first = weekPlan.dayLabels.first().trim()
            val last = weekPlan.dayLabels.last().trim()
            if (first.isNotEmpty() && last.isNotEmpty()) "$first–$last" else ""
        } else {
            ""
        }
        return WeekWidgetViewModel(
            signedIn = true,
            isStale = false,
            isTermEnded = false,
            weekPlan = weekPlan,
            isCurrentWeek = isCurrentWeek,
            todayWeekday = todayWeekday,
            showWeekend = showWeekend,
            dateRange = dateRange,
        )
    }

    /**
     * 按当前活跃小组件形态与考试开关过滤计算下一次刷新计划：
     * - 仅挂载「本周课表」时只在次日 00:01 唤醒；
     * - 上下课节点闹钟仅刷新「今日课表 / 下一节课」，不触发高开销的周课表位图重绘。
     */
    fun computeNextRefreshPlan(
        snapshot: WidgetSnapshotModel?,
        nowMs: Long,
        hasToday: Boolean,
        hasNext: Boolean,
        hasWeek: Boolean,
    ): WidgetRefreshPlan {
        val midnightMs = nextMidnightPlusOneMinute(nowMs)
        if (snapshot == null || !snapshot.signedIn || (!hasToday && !hasNext)) {
            return WidgetRefreshPlan(
                triggerAtMs = midnightMs.coerceAtLeast(nowMs + 5_000L),
                includeWeek = hasWeek,
            )
        }

        val trackExams = (hasToday && snapshot.styleOf(KIND_TODAY).showExams) ||
            (hasNext && snapshot.styleOf(KIND_NEXT).showExams)
        var earliestBell = Long.MAX_VALUE
        val threshold = nowMs + 500L

        for (day in snapshot.days) {
            for (item in day.items) {
                if (item.isExam && !trackExams) continue
                if (item.startMs > threshold && item.startMs + 1000L < earliestBell) {
                    earliestBell = item.startMs + 1000L
                }
                if (item.endMs > threshold && item.endMs + 1000L < earliestBell) {
                    earliestBell = item.endMs + 1000L
                }
            }
        }
        if (trackExams) {
            for (exam in snapshot.upcomingExams) {
                if (exam.startMs > threshold && exam.startMs + 1000L < earliestBell) {
                    earliestBell = exam.startMs + 1000L
                }
                if (exam.endMs > threshold && exam.endMs + 1000L < earliestBell) {
                    earliestBell = exam.endMs + 1000L
                }
            }
        }

        return if (earliestBell < midnightMs) {
            WidgetRefreshPlan(
                triggerAtMs = earliestBell.coerceAtLeast(nowMs + 5_000L),
                includeWeek = false,
            )
        } else {
            WidgetRefreshPlan(
                triggerAtMs = midnightMs.coerceAtLeast(nowMs + 5_000L),
                includeWeek = hasWeek,
            )
        }
    }

    private fun findNearestExamWithinWindow(
        snapshot: WidgetSnapshotModel,
        nowMs: Long,
    ): UpcomingExamData? {
        for (exam in snapshot.upcomingExams) {
            if (exam.startMs <= 0L || exam.endMs <= nowMs) continue
            val days = calendarDayDiff(nowMs, exam.startMs)
            if (days <= UPCOMING_EXAM_WINDOW_DAYS) return exam
        }
        return null
    }

    private fun itemSubtitle(item: TimelineItemData, style: WidgetStyleData): String =
        listOfNotEmpty(
            if (style.showLocation) item.location else "",
            if (item.isExam && style.showLocation && item.seatNumber.isNotEmpty()) "${item.seatNumber}座" else "",
            if (!item.isExam && style.showTeacher) item.teacher else "",
        )

    private fun listOfNotEmpty(vararg parts: String): String =
        parts.filter { it.isNotEmpty() }.joinToString(" · ")

    private fun weekAndWeekday(week: Int, weekday: Int): String {
        val wd = weekdayName(weekday)
        return if (week > 0) "第${week}周 $wd" else wd
    }

    fun shortMonthDay(isoDate: String): String {
        val parts = isoDate.split('-')
        if (parts.size != 3) return isoDate
        val month = parts[1].toIntOrNull() ?: return isoDate
        val day = parts[2].toIntOrNull() ?: return isoDate
        return "$month/$day"
    }

    fun calendarDayDiff(fromMs: Long, toMs: Long): Int {
        val c1 = dayStartCal(fromMs)
        val c2 = dayStartCal(toMs)
        return ((c2.timeInMillis - c1.timeInMillis).toDouble() / 86_400_000.0).roundToInt()
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

    fun formatIsoDate(ms: Long): String {
        val cal = Calendar.getInstance().apply { timeInMillis = ms }
        return String.format(
            Locale.US,
            "%04d-%02d-%02d",
            cal.get(Calendar.YEAR),
            cal.get(Calendar.MONTH) + 1,
            cal.get(Calendar.DAY_OF_MONTH),
        )
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
}
