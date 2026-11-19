/// 桌面小组件预览渲染与配置页交互测试。
///
/// 覆盖：
/// - 今日课表双栏时间轴（2×2 窄卡与 4×2 宽卡均展示完整起止时间）、课后自动切明日预告开关、
///   已结束课程置灰/隐藏、正在考试/调课标签、座位号随地点隐藏、关闭标题栏明日精简提示；
/// - 下一节课配置项精简（移除已结束课程/信息密度/标题栏）、状态胶囊常驻、4×1/2×2 排版、考试时间不截断；
/// - 本周课表日期范围、有课显示严格判断周末课、仅当前周高亮今日、空周提示、大字号两位数节次；
/// - 0% 透明隐藏圆角滑块、吸顶预览滚动缩放无溢出、快照缓存防滑块拖动重建、恢复默认撤销、
///   系统超大字体免疫（TextScaler 2.0 无溢出）以及 14 天过期快照提示。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/widget_settings_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/reschedule.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/timetable.dart';
import 'package:qustschedule/src/widget_gateway.dart';
import 'package:qustschedule/src/widget_planner.dart';
import 'package:qustschedule/src/widget_service.dart';
import 'package:qustschedule/src/widget_style.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/desktop_widget_preview.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/fake_backend.dart';

const String _baseUrl = 'https://jw.example.edu.cn/jwglxt';

class _FakeGateway implements DesktopWidgetGateway {
  int syncCount = 0;

  @override
  Future<bool> syncSnapshot(String payloadJson) async {
    syncCount++;
    return true;
  }

  @override
  Future<void> clearSnapshot() async {}

  @override
  Future<bool> requestPinWidget(DesktopWidgetKind kind) async => true;

  @override
  Future<Map<DesktopWidgetKind, int>> getPinnedCounts() async =>
      const <DesktopWidgetKind, int>{};
}

class _CountingWidgetService extends DesktopWidgetService {
  _CountingWidgetService({
    required super.model,
    required super.gateway,
    super.now,
  }) : super(debounce: const Duration(milliseconds: 5));

  int buildSnapshotCalls = 0;

  @override
  WidgetSnapshot? buildSnapshot() {
    buildSnapshotCalls++;
    return super.buildSnapshot();
  }
}

AppModel _createModel() {
  final model = AppModel(
    service: ScheduleService(
      credentials: InMemoryCredentialStore(),
      cookieStorage: FakeSessionRepository(),
      backendFactory: (_) => FakeBackend(),
      baseUrl: _baseUrl,
    ),
    preferences: Preferences.inMemory(),
    schoolBaseUrl: _baseUrl,
  );
  model.hydrateForTest(
    schedule: sampleSchedule(),
    termStart: DateTime(2026, 9, 7),
    week: 1,
  );
  return model;
}

Widget _wrapApp(Widget child, {double systemTextScale = 1.0}) {
  return MaterialApp(
    theme: buildLightTheme(),
    builder: (context, inner) => MediaQuery(
      data: MediaQuery.of(context)
          .copyWith(textScaler: TextScaler.linear(systemTextScale)),
      child: inner!,
    ),
    home: child,
  );
}

void main() {
  group('DesktopWidgetPreview 渲染与逻辑边界', () {
    testWidgets('今日课表在 4×2 宽卡与 2×2 窄卡均展示完整起止时间，且展示进行中/调课/考试', (tester) async {
      final ref = DateTime(2026, 9, 9); // 周三
      final sample = buildSampleWidgetSnapshot(reference: ref);
      final clock = samplePreviewClock(ref); // 10:40

      for (final narrow in <bool>[false, true]) {
        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Center(
                child: DesktopWidgetPreview(
                  kind: DesktopWidgetKind.today,
                  style: DesktopWidgetStyle.defaultsFor(
                    DesktopWidgetKind.today,
                  ),
                  snapshot: sample,
                  useSampleData: true,
                  todayNarrow: narrow,
                  now: clock,
                ),
              ),
            ),
          ),
        );

        // 周次优先顶栏 + 剩余计数（进行中 + 待上调课 + 当天考试 = 3）
        expect(find.text('第2周 周三'), findsOneWidget);
        expect(find.text('剩3节'), findsOneWidget);
        // 无论宽窄，均完整显示开始和结束时间，绝不截断下课时间。
        expect(find.text('08:30'), findsOneWidget);
        expect(find.text('10:05'), findsOneWidget);
        expect(find.text('10:25'), findsOneWidget);
        expect(find.text('12:00'), findsOneWidget);
        expect(find.text('进行中'), findsOneWidget);
        expect(find.text('调课'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      // 校验周一至周日任意一天生成的黄金示例均同时包含：已结束、进行中、待上调课、当天考试与非空明日。
      for (var offset = 0; offset < 7; offset++) {
        final day = DateTime(2026, 9, 7 + offset);
        final snap = buildSampleWidgetSnapshot(reference: day);
        final clockMs = samplePreviewClock(day).millisecondsSinceEpoch;
        final todayItems = snap.days.first.items;
        expect(todayItems.any((i) => i.endMs <= clockMs), isTrue);
        expect(
          todayItems.any((i) => i.startMs <= clockMs && i.endMs > clockMs),
          isTrue,
        );
        expect(
          todayItems.any((i) => i.startMs > clockMs && i.rescheduled),
          isTrue,
        );
        expect(todayItems.any((i) => i.isExam), isTrue);
        expect(snap.days[1].items, isNotEmpty);
      }

      // 开启「自动隐藏」后，已结束的 08:30 课程被隐藏。
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.today)
                    .copyWith(finishedCourseMode: FinishedCourseMode.hide),
                snapshot: sample,
                useSampleData: true,
                now: clock,
              ),
            ),
          ),
        ),
      );
      expect(find.text('08:30'), findsNothing);
      expect(find.text('10:25'), findsOneWidget);
    });

    testWidgets('周日生成示例课表时，明日（下周一）仍有课程，不出现周日 nextD 错位', (tester) async {
      final sunday = DateTime(2026, 9, 13); // 周日
      final sample = buildSampleWidgetSnapshot(reference: sunday);
      expect(sample.days[1].weekday, DateTime.monday);
      expect(sample.days[1].items, isNotEmpty);

      // 晚间 21:00：今日课程与考试均结束 → 切到明日预告（下周一）
      final lateSunday = DateTime(2026, 9, 13, 21, 0);
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.today),
                snapshot: sample,
                useSampleData: false,
                now: lateSunday,
              ),
            ),
          ),
        ),
      );
      expect(find.text('明日'), findsOneWidget);
      expect(find.text('第3周 周一'), findsOneWidget);
    });

    testWidgets('课后自动切明日预告开关与关闭标题栏精简明日提示行为准确', (tester) async {
      final termStart = DateTime(2026, 9, 7);
      final afterClass = DateTime(2026, 9, 7, 21, 0);
      final snapshot = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 'mon',
            name: '大学物理',
            teacher: '王老师',
            location: 'M1-101',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1],
          ),
          ScheduleEntry(
            id: 'tue',
            name: '高等数学',
            teacher: '李老师',
            location: 'M1-202',
            day: 2,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: afterClass,
      );

      // 1) autoSwitchTomorrow=true 且 showHeader=false → 仍保留「明日 · 周二」精简提示
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: const DesktopWidgetStyle(
                  autoSwitchTomorrow: true,
                  showHeader: false,
                ),
                snapshot: snapshot,
                useSampleData: false,
                now: afterClass,
              ),
            ),
          ),
        ),
      );
      expect(find.text('明日 · 周二'), findsOneWidget);
      expect(find.text('高等数学'), findsOneWidget);

      // 2) autoSwitchTomorrow=false + finishedCourseMode=hide → 留在今日并显示「今日课程已全部结束」
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: const DesktopWidgetStyle(
                  autoSwitchTomorrow: false,
                  finishedCourseMode: FinishedCourseMode.hide,
                ),
                snapshot: snapshot,
                useSampleData: false,
                now: afterClass,
              ),
            ),
          ),
        ),
      );
      expect(find.text('明日'), findsNothing);
      expect(find.text('已结束'), findsOneWidget);
      expect(find.text('今日课程已全部结束'), findsOneWidget);

      // 3) autoSwitchTomorrow=false + finishedCourseMode=dim → 留在今日并展示已结束的大学物理
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: const DesktopWidgetStyle(
                  autoSwitchTomorrow: false,
                  finishedCourseMode: FinishedCourseMode.dim,
                ),
                snapshot: snapshot,
                useSampleData: false,
                now: afterClass,
              ),
            ),
          ),
        ),
      );
      expect(find.text('大学物理'), findsOneWidget);
      expect(find.text('高等数学'), findsNothing);
    });

    testWidgets('正在考试标签、关闭地点隐藏座位号、已结束考试不幽灵残留、14天过期提示', (tester) async {
      final termStart = DateTime(2026, 9, 7);
      final examTime = DateTime(2026, 9, 7, 15, 0);
      final snapshot = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: DateTime(2026, 9, 7, 8, 0),
        exams: <ExamItem>[
          ExamItem(
            courseName: '电路原理',
            startTime: DateTime(2026, 9, 7, 14, 0),
            endTime: DateTime(2026, 9, 7, 16, 0),
            classroom: 'M1-301',
            seatNumber: '25',
            examForm: '闭卷',
          ),
        ],
      );

      // 15:00 正在考试 + showLocation=false 不显示座位号
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: const DesktopWidgetStyle(showLocation: false),
                snapshot: snapshot,
                useSampleData: false,
                now: examTime,
              ),
            ),
          ),
        ),
      );
      expect(find.text('正在考试'), findsOneWidget);
      expect(find.textContaining('25座'), findsNothing);

      // 18:00 考试结束后，不再作为幽灵近期考试展示
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: const DesktopWidgetStyle(
                  finishedCourseMode: FinishedCourseMode.hide,
                ),
                snapshot: snapshot,
                useSampleData: false,
                now: DateTime(2026, 9, 7, 18, 0),
              ),
            ),
          ),
        ),
      );
      expect(find.text('近期考试'), findsNothing);

      // 20 天后快照过期，三类小组件均显示友好刷新提示
      final staleNow = DateTime(2026, 9, 28, 9, 0);
      for (final kind in DesktopWidgetKind.values) {
        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Center(
                child: DesktopWidgetPreview(
                  kind: kind,
                  style: DesktopWidgetStyle.defaultsFor(kind),
                  snapshot: snapshot,
                  useSampleData: false,
                  now: staleNow,
                ),
              ),
            ),
          ),
        );
        expect(find.textContaining('课表数据已过期'), findsOneWidget);
      }
    });

    testWidgets('本周课表：有课显示严格检查周末课、日期范围、空周提示、非当前周不高亮今日', (tester) async {
      final termStart = DateTime(2026, 9, 7); // 周一
      // 周六（无任何周末课）
      final saturday = DateTime(2026, 9, 12, 10, 0);
      final weekdayOnlySnap = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 'c1',
            name: '高等数学',
            location: 'M1-101',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: saturday,
      );

      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.week,
                style: const DesktopWidgetStyle(
                  weekendMode: WeekendColumnMode.auto,
                ),
                snapshot: weekdayOnlySnap,
                useSampleData: false,
                now: saturday,
              ),
            ),
          ),
        ),
      );
      expect(find.text('第 1 周'), findsOneWidget);
      expect(find.text('9/7–9/13'), findsOneWidget);
      // 即便是周六，本周无周末课时「有课显示」必须隐藏六/日列。
      expect(find.text('六'), findsNothing);
      expect(find.text('日'), findsNothing);

      // 空周提示（第 1 周无任何课）
      final emptyWeekSnap = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: DateTime(2026, 9, 8, 10, 0),
      );
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.week,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.week),
                snapshot: emptyWeekSnap,
                useSampleData: false,
                now: DateTime(2026, 9, 8, 10, 0),
              ),
            ),
          ),
        ),
      );
      expect(find.text('本周无课，好好休息'), findsOneWidget);

      // 开学前一周（非当前真实周）：不得渲染今日高亮胶囊或今日整列竖条。
      final preTermNow = DateTime(2026, 9, 2, 10, 0); // 开学前周三
      final preTermSnap = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 'c1',
            name: '高等数学',
            location: 'M1-101',
            day: 3,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: preTermNow,
      );
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.week,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.week),
                snapshot: preTermSnap,
                useSampleData: false,
                now: preTermNow,
              ),
            ),
          ),
        ),
      );
      expect(find.text('第 1 周'), findsOneWidget);
      final wedText = tester.widget<Text>(find.text('三'));
      expect(wedText.style?.fontWeight, FontWeight.w500);
    });

    testWidgets('下一节课：状态胶囊始终可见且免疫系统 2.0× 超大字体无溢出', (tester) async {
      final ref = DateTime(2026, 9, 9);
      final sample = buildSampleWidgetSnapshot(reference: ref);
      final clock = samplePreviewClock(ref);

      for (final wide in <bool>[false, true]) {
        await tester.pumpWidget(
          _wrapApp(
            Scaffold(
              body: Center(
                child: DesktopWidgetPreview(
                  kind: DesktopWidgetKind.next,
                  style: const DesktopWidgetStyle(
                    showHeader: false, // 即使旧配置为 false，下一节课仍须展示状态胶囊
                    fontScale: 1.20,
                  ),
                  snapshot: sample,
                  useSampleData: true,
                  nextWide: wide,
                  now: clock,
                ),
              ),
            ),
            systemTextScale: 2.0,
          ),
        );
        expect(find.text('正在上课'), findsOneWidget);
        expect(find.text('单片机原理及应用A'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      // 2×2 近期考试倒计时拆分日期提示与考试时间不截断，且关闭地点时隐藏座位号；空态不复用课程色 0。
      final futureExamSnap = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[],
        reschedules: const <RescheduleRule>[],
        termStart: DateTime(2026, 9, 7),
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: DateTime(2026, 9, 9, 10, 0),
        exams: <ExamItem>[
          ExamItem(
            courseName: '信号与系统',
            startTime: DateTime(2026, 9, 12, 14, 0),
            endTime: DateTime(2026, 9, 12, 16, 0),
            classroom: 'M1-308',
            seatNumber: '19',
            examForm: '闭卷',
          ),
        ],
      );
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.next,
                style: const DesktopWidgetStyle(showLocation: false),
                snapshot: futureExamSnap,
                useSampleData: false,
                nextWide: false,
                now: DateTime(2026, 9, 9, 10, 0),
              ),
            ),
          ),
        ),
      );
      expect(find.text('考试倒计时 3天'), findsOneWidget);
      expect(find.text('9/12 周六'), findsOneWidget);
      expect(find.text('14:00-16:00'), findsOneWidget);
      expect(find.textContaining('19座'), findsNothing);
      expect(tester.takeException(), isNull);

      // 空 endLabel 守卫：绝不拼接出 "08:00-" 尾横线。
      final startOnlySnap = WidgetSnapshot(
        signedIn: true,
        termId: 't1',
        termStartIso: '2026-09-07',
        maxWeek: 18,
        generatedAtMs: DateTime(2026, 9, 7, 7, 0).millisecondsSinceEpoch,
        fingerprint: 'fp',
        days: <WidgetDayPlan>[
          WidgetDayPlan(
            dateIso: '2026-09-07',
            week: 1,
            weekday: 1,
            items: <WidgetTimelineItem>[
              WidgetTimelineItem(
                kind: 'course',
                id: 'c1',
                title: '形势与政策',
                location: 'M1-102',
                teacher: '周老师',
                seatNumber: '',
                examForm: '',
                startPeriod: 1,
                endPeriod: 2,
                startLabel: '08:00',
                endLabel: '',
                startMs: DateTime(2026, 9, 7, 8, 0).millisecondsSinceEpoch,
                endMs: DateTime(2026, 9, 7, 9, 40).millisecondsSinceEpoch,
                colorIndex: 0,
              ),
            ],
          ),
        ],
        upcomingExams: const <WidgetUpcomingExam>[],
        weeks: const <WidgetWeekPlan>[],
        styles: DesktopWidgetConfigSet.defaults(),
      );
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.next,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.next),
                snapshot: startOnlySnap,
                useSampleData: false,
                now: DateTime(2026, 9, 7, 7, 30),
              ),
            ),
          ),
        ),
      );
      expect(find.text('08:00'), findsOneWidget);
      expect(find.text('08:00-'), findsNothing);
    });

    testWidgets('本周课表：12 节两位数节次在 120% 字号与 2.0× 系统字体下无溢出', (tester) async {
      final termStart = DateTime(2026, 9, 7);
      final twelveCounts = <PeriodGroup, int>{
        PeriodGroup.morning: 4,
        PeriodGroup.afternoon: 4,
        PeriodGroup.evening: 4,
      };
      final snap = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 'late',
            name: '大学体育',
            location: '操场',
            day: 3,
            startPeriod: 11,
            endPeriod: 12,
            weeks: <int>[1],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: twelveCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: DateTime(2026, 9, 9, 10, 0),
      );
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.week,
                style: const DesktopWidgetStyle(
                  fontScale: 1.20,
                  backgroundOpacity: 0.0,
                ),
                snapshot: snap,
                useSampleData: false,
                now: DateTime(2026, 9, 9, 10, 0),
              ),
            ),
          ),
          systemTextScale: 2.0,
        ),
      );
      expect(find.text('10'), findsOneWidget);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('12'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('WidgetSettingsPage 配置逻辑、缓存与交互', () {
    testWidgets('各小组件配置项精准按需显示、0%透明隐藏圆角、恢复默认支持撤销', (tester) async {
      final model = _createModel();
      final gateway = _FakeGateway();
      final service = _CountingWidgetService(
        model: model,
        gateway: gateway,
        now: () => DateTime(2026, 9, 9, 10, 40),
      );
      addTearDown(() {
        service.dispose();
        model.dispose();
      });

      await tester.pumpWidget(
        _wrapApp(WidgetSettingsPage(model: model, widgetService: service)),
      );
      await tester.pumpAndSettle();

      // 初始仅构建 1 次真实快照缓存，并展示「仅供参考 + 小窗/分屏」简短引导。
      final initialBuilds = service.buildSnapshotCalls;
      expect(initialBuilds, 1);
      expect(find.textContaining('预览仅供参考'), findsOneWidget);
      expect(find.textContaining('小窗或分屏'), findsOneWidget);

      final mainScrollable = find.byType(Scrollable).first;

      // 有真实课表数据时默认进入「实时课表」，并可自由切换「示例课表」。
      expect(find.text('实时课表'), findsOneWidget);
      await tester.tap(find.text('实时课表'));
      await tester.pumpAndSettle();
      expect(find.text('示例课表'), findsOneWidget);
      await tester.tap(find.text('示例课表'));
      await tester.pumpAndSettle();
      expect(find.text('实时课表'), findsOneWidget);

      // 尺寸切换按钮仅显示尺寸（4×2 / 2×2），不含「宽卡 / 窄卡」等冗余字样。
      expect(find.text('4×2'), findsOneWidget);
      expect(find.textContaining('宽卡'), findsNothing);
      expect(find.textContaining('窄卡'), findsNothing);
      await tester.tap(find.text('4×2'));
      await tester.pumpAndSettle();
      expect(find.text('2×2'), findsOneWidget);
      await tester.tap(find.text('2×2'));
      await tester.pumpAndSettle();
      expect(find.text('4×2'), findsOneWidget);

      // 精选预设横向滚动条关闭裁剪（Clip.none），确保按住放大时四周不被截断。
      final presetScrollView = tester.widget<SingleChildScrollView>(
        find.ancestor(
          of: find.text('极简纯白'),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      expect(presetScrollView.clipBehavior, Clip.none);

      // 今日课表：可见「课后自动切明日预告」「已结束课程」「显示上课时间」「卡片圆角」。
      await tester.scrollUntilVisible(
        find.text('课后自动切明日预告'),
        200,
        scrollable: mainScrollable,
      );
      expect(find.text('课后自动切明日预告'), findsOneWidget);
      expect(find.text('已结束课程'), findsOneWidget);
      expect(find.text('显示上课时间'), findsOneWidget);

      // 切换密度为紧凑后再套用预设：预设不得覆盖用户的密度选择。
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('紧凑'),
        200,
        scrollable: mainScrollable,
      );
      await tester.tap(find.text('紧凑'));
      await tester.pumpAndSettle();
      expect(
        model.widgetStyleOf(DesktopWidgetKind.today).density,
        WidgetDensity.compact,
      );

      // 切到「纯净透明」预设（0% 透明）→ 保留紧凑密度并隐藏「卡片圆角」滑块。
      await tester.drag(find.byType(CustomScrollView), const Offset(0, 600));
      await tester.pumpAndSettle();
      await tester.tap(find.text('纯净透明'));
      await tester.pumpAndSettle();
      expect(find.text('卡片圆角'), findsNothing);
      expect(model.widgetStyleOf(DesktopWidgetKind.today).backgroundOpacity, 0);
      expect(
        model.widgetStyleOf(DesktopWidgetKind.today).density,
        WidgetDensity.compact,
      );

      // 选中「壁纸取色」主题 → 展示 Android 12+ 说明。
      await tester.tap(find.text('壁纸取色'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Android 12+'), findsWidgets);

      // 持续拖动透明度滑块 10 帧期间，绝不触发 buildSnapshot 重建（仅松手抬指后同步 1 次）。
      final buildsBeforeDrag = service.buildSnapshotCalls;
      final opacitySlider = find.byType(Slider).first;
      final gesture = await tester.startGesture(
        tester.getCenter(opacitySlider),
      );
      for (var step = 0; step < 10; step++) {
        await gesture.moveBy(const Offset(12, 0));
        await tester.pump();
      }
      expect(service.buildSnapshotCalls, buildsBeforeDrag);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(service.buildSnapshotCalls, buildsBeforeDrag + 1);

      // 恢复默认样式 → 弹 SnackBar 并支持一键撤销。
      final styleBeforeReset = model.widgetStyleOf(DesktopWidgetKind.today);
      await tester.scrollUntilVisible(
        find.text('恢复「今日课表」默认样式'),
        200,
        scrollable: mainScrollable,
      );
      await tester.tap(find.text('恢复「今日课表」默认样式'));
      await tester.pumpAndSettle();
      expect(
        model.widgetStyleOf(DesktopWidgetKind.today),
        DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.today),
      );
      expect(find.text('撤销'), findsOneWidget);
      await tester.tap(find.text('撤销'));
      await tester.pumpAndSettle();
      expect(model.widgetStyleOf(DesktopWidgetKind.today), styleBeforeReset);

      // 切换到「下一节课」：验证不合理的「已结束课程」「信息密度」「显示顶部标题栏」均已移除。
      final buildsBeforeTabSwitch = service.buildSnapshotCalls;
      await tester.scrollUntilVisible(
        find.text('下一节课'),
        -300,
        scrollable: mainScrollable,
      );
      await tester.tap(find.text('下一节课'));
      await tester.pumpAndSettle();
      expect(find.text('2×2'), findsOneWidget);
      expect(find.textContaining('宽条'), findsNothing);
      await tester.tap(find.text('2×2'));
      await tester.pumpAndSettle();
      expect(find.text('4×1'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('融合考试安排'),
        200,
        scrollable: mainScrollable,
      );
      expect(find.text('优先展示当天考试，近期无课时展示 7 天内倒计时'), findsOneWidget);
      expect(find.text('已结束课程'), findsNothing);
      expect(find.text('信息密度'), findsNothing);
      expect(find.text('显示顶部标题栏'), findsNothing);

      // 切换到「本周课表」：长卡片吸顶滚动无溢出，且切页与滚动均不重建真实快照。
      await tester.scrollUntilVisible(
        find.text('本周课表'),
        -300,
        scrollable: mainScrollable,
      );
      await tester.tap(find.text('本周课表'));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('周末列显示'),
        200,
        scrollable: mainScrollable,
      );
      expect(find.text('始终隐藏'), findsOneWidget);
      expect(service.buildSnapshotCalls, buildsBeforeTabSwitch);
      expect(tester.takeException(), isNull);
    });

    testWidgets('360x640 窄屏 + 2.0x 系统超大字体下配置页三类切换与滚动零溢出', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final model = _createModel();
      final gateway = _FakeGateway();
      final service = _CountingWidgetService(
        model: model,
        gateway: gateway,
        now: () => DateTime(2026, 9, 9, 10, 40),
      );
      addTearDown(() {
        service.dispose();
        model.dispose();
      });

      await tester.pumpWidget(
        _wrapApp(
          WidgetSettingsPage(model: model, widgetService: service),
          systemTextScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      for (final label in const <String>['本周课表', '下一节课', '今日课表']) {
        await tester.tap(find.text(label).first);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('边界回归：假期不误报过期、周日同步跨周覆盖、隐藏周末空白兜底与示例全可见', () {
    testWidgets('学期结束后新鲜快照不误报已过期，且周日同步支持完整 14 天周视图', (tester) async {
      final termStart = DateTime(2026, 3, 2); // 第 1 周周一，18 周末为 2026-07-05
      final vacationNow = DateTime(2026, 7, 8, 10, 0); // 第 19 周（暑假）
      final vacationSnap = buildWidgetSnapshot(
        termId: '2025-2026-2',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 'c1',
            name: '大学物理',
            location: 'M1-101',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[18],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: vacationNow,
      );

      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.week,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.week),
                snapshot: vacationSnap,
                useSampleData: false,
                now: vacationNow,
              ),
            ),
          ),
        ),
      );
      // 刚刷新的假期快照绝不能误报「课表数据已过期」。
      expect(find.textContaining('课表数据已过期'), findsNothing);
      expect(find.textContaining('本学期课程已结束'), findsOneWidget);

      // 周日（第 1 周）生成的快照，第 8 天（第 3 周周一）仍应正常展示第 3 周，不提前过期。
      final fallStart = DateTime(2026, 9, 7);
      final sundayW1 = DateTime(2026, 9, 13, 10, 0);
      final mondayW3 = DateTime(2026, 9, 21, 10, 0);
      final sundaySnap = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 'w3',
            name: '自动控制原理',
            location: 'M1-204',
            day: 1,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[3],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: fallStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: sundayW1,
      );
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.week,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.week),
                snapshot: sundaySnap,
                useSampleData: false,
                now: mondayW3,
              ),
            ),
          ),
        ),
      );
      expect(find.text('第 3 周'), findsOneWidget);
      expect(find.textContaining('课表数据已过期'), findsNothing);
    });

    testWidgets('本周仅有周末课且选择始终隐藏周末列时，展示友好提示不留空白网格', (tester) async {
      final termStart = DateTime(2026, 9, 7);
      final wed = DateTime(2026, 9, 9, 10, 0);
      final weekendOnlySnap = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 'sat',
            name: '科技创新实践',
            location: '实验楼 201',
            day: 6,
            startPeriod: 3,
            endPeriod: 4,
            weeks: <int>[1],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: wed,
      );
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.week,
                style: const DesktopWidgetStyle(
                  weekendMode: WeekendColumnMode.hide,
                ),
                snapshot: weekendOnlySnap,
                useSampleData: false,
                now: wed,
              ),
            ),
          ),
        ),
      );
      expect(find.text('工作日无课，周末有安排'), findsOneWidget);
    });

    testWidgets('今日黄金示例预览第 4 条当天考试完整可见，且关闭融合考试后即时消失', (tester) async {
      final ref = DateTime(2026, 9, 9);
      final sample = buildSampleWidgetSnapshot(reference: ref);
      final clock = samplePreviewClock(ref);

      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.today),
                snapshot: sample,
                useSampleData: true,
                now: clock,
              ),
            ),
          ),
        ),
      );
      final cardRect = tester.getRect(find.byType(DesktopWidgetPreview));
      final examFinder = find.text('电力系统稳态分析');
      expect(examFinder, findsOneWidget);
      final examRect = tester.getRect(examFinder);
      // 考试条目必须完整落在预览卡片可视边界之内，而非被截断在列表外。
      expect(examRect.bottom, lessThanOrEqualTo(cardRect.bottom));

      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.today)
                    .copyWith(showExams: false),
                snapshot: sample,
                useSampleData: true,
                now: clock,
              ),
            ),
          ),
        ),
      );
      expect(find.text('电力系统稳态分析'), findsNothing);
    });

    testWidgets('2×2 与 4×4 预览卡片为 1:1 正方形，明日三节相同课程严格对齐，本周顶栏左合并展示', (
      tester,
    ) async {
      final termStart = DateTime(2026, 9, 7);
      final lateMon = DateTime(2026, 9, 7, 21, 0);
      final snap = buildWidgetSnapshot(
        termId: '2026-2027-1',
        entries: const <ScheduleEntry>[
          ScheduleEntry(
            id: 't1',
            name: '机械制造实习',
            teacher: '赵老师',
            location: '工程训练中心101',
            day: 2,
            startPeriod: 1,
            endPeriod: 2,
            weeks: <int>[1],
          ),
          ScheduleEntry(
            id: 't2',
            name: '机械制造实习 ',
            teacher: '赵老师',
            location: '工程训练中心101',
            day: 2,
            startPeriod: 3,
            endPeriod: 4,
            weeks: <int>[1],
          ),
          ScheduleEntry(
            id: 't3',
            name: '机械制造实习',
            teacher: '赵老师',
            location: '工程训练中心101',
            day: 2,
            startPeriod: 5,
            endPeriod: 6,
            weeks: <int>[1],
          ),
        ],
        reschedules: const <RescheduleRule>[],
        termStart: termStart,
        timetables: <Timetable>[defaultTimetable()],
        sectionCounts: defaultSectionCounts,
        maxWeek: 18,
        styles: DesktopWidgetConfigSet.defaults(),
        now: lateMon,
      );

      // 1) 今日 2×2 窄卡：正方形且三节相同课程标题左边缘严格垂直对齐、显示「明日」徽章
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.today,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.today),
                snapshot: snap,
                useSampleData: false,
                todayNarrow: true,
                now: lateMon,
              ),
            ),
          ),
        ),
      );
      final today2x2Size = tester.getSize(find.byType(DesktopWidgetPreview));
      expect(today2x2Size.width, today2x2Size.height);
      expect(find.text('明日'), findsOneWidget);
      final titles = find.text('机械制造实习');
      expect(titles, findsNWidgets(3));
      final r0 = tester.getRect(titles.at(0));
      final r1 = tester.getRect(titles.at(1));
      final r2 = tester.getRect(titles.at(2));
      expect(r0.left, closeTo(r1.left, 0.01));
      expect(r1.left, closeTo(r2.left, 0.01));
      expect(r0.width, closeTo(r1.width, 0.01));
      expect(r1.width, closeTo(r2.width, 0.01));

      // 2) 下一节课 2×2 卡片：正方形
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.next,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.next),
                snapshot: snap,
                useSampleData: false,
                nextWide: false,
                now: lateMon,
              ),
            ),
          ),
        ),
      );
      final next2x2Size = tester.getSize(find.byType(DesktopWidgetPreview));
      expect(next2x2Size.width, next2x2Size.height);

      // 3) 本周课表 4×4：正方形，且周次与日期范围并排靠左展示（紧邻）
      await tester.pumpWidget(
        _wrapApp(
          Scaffold(
            body: Center(
              child: DesktopWidgetPreview(
                kind: DesktopWidgetKind.week,
                style: DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.week),
                snapshot: snap,
                useSampleData: false,
                now: lateMon,
              ),
            ),
          ),
        ),
      );
      final weekSize = tester.getSize(find.byType(DesktopWidgetPreview));
      expect(weekSize.width, weekSize.height);
      final weekRect = tester.getRect(find.text('第 1 周'));
      final rangeRect = tester.getRect(find.text('9/7–9/13'));
      expect(rangeRect.left - weekRect.right, lessThanOrEqualTo(12.0));
      expect(rangeRect.left, greaterThan(weekRect.right));
    });
  });
}
