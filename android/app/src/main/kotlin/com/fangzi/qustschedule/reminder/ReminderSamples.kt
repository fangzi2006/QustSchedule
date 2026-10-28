package com.fangzi.qustschedule.reminder

import java.util.Calendar

/**
 * 示例事件：诊断页「立即显示通知」与「5 秒后测试提醒」共用一份。
 *
 * 两边以前各写一套文案，改文案时总会漏掉一处；这里集中定义后，
 * 横幅和流体云卡片看到的就是同一节课。
 */
object ReminderSamples {

    const val NAME = "高等数学（示例）"
    const val TEACHER = "张老师"
    const val ROOM = "3教201"
    const val START_PERIOD = 3
    const val END_PERIOD = 4
    const val WEEK = 1

    /** 一节课按 95 分钟估，够流体云把倒计时跑完。 */
    private const val CLASS_MINUTES = 95L

    /**
     * @param leadMinutes 距离上课还有几分钟。
     *
     * 目标时间最低分度直到分钟（秒和毫秒清零，不需要特别处理）；
     * 在计算剩余时间 (startMs - now) 时，当前时间的秒自然算入倒计时与关闭超时中，
     * 确保手机时间、倒计时与通知关闭时刻严格对齐。
     */
    fun event(leadMinutes: Int): ReminderEvent {
        val now = System.currentTimeMillis()
        val safeLead = leadMinutes.coerceIn(1, 60)
        val cal = Calendar.getInstance().apply {
            timeInMillis = now
            add(Calendar.MINUTE, safeLead)
            set(Calendar.SECOND, 0)
            set(Calendar.MILLISECOND, 0)
        }
        if (cal.timeInMillis <= now) {
            cal.add(Calendar.MINUTE, 1)
        }
        val startMs = cal.timeInMillis
        return ReminderEvent(
            id = "test",
            name = NAME,
            teacher = TEACHER,
            location = ROOM,
            startMs = startMs,
            endMs = startMs + CLASS_MINUTES * 60_000L,
            remindAtMs = now,
            startPeriod = START_PERIOD,
            endPeriod = END_PERIOD,
            week = WEEK,
        )
    }
}
