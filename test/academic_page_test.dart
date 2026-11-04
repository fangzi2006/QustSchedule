import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/academic_page.dart';
import 'package:qustschedule/src/academic_cache.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:zf_academic/zf_academic.dart';

import 'support/fake_backend.dart';

const _baseUrl = 'https://jw.example.edu.cn';

AppModel _buildTestModel({FakeBackend? backend}) {
  final fake = backend ?? FakeBackend();
  final credentials = InMemoryCredentialStore();
  return AppModel(
    service: ScheduleService(
      credentials: credentials,
      cookieStorage: FakeSessionRepository(),
      backendFactory: (_) => fake,
      baseUrl: _baseUrl,
    ),
    preferences: Preferences.inMemory(),
    examCache: InMemoryExamCache(),
    gradesCache: InMemoryGradesCache(),
    schoolBaseUrl: _baseUrl,
  );
}

Widget _wrap(Widget child) {
  return MaterialApp(theme: ThemeData.light(useMaterial3: true), home: child);
}

void main() {
  testWidgets('AcademicPage renders initial empty states before refresh', (
    tester,
  ) async {
    final model = _buildTestModel();
    await tester.pumpWidget(_wrap(AcademicPage(model: model)));

    expect(find.text('学业概览'), findsOneWidget);
    expect(find.text('考试安排'), findsOneWidget);
    expect(find.text('成绩与绩点'), findsOneWidget);
    expect(find.text('暂无考试安排数据'), findsOneWidget);
    expect(find.text('暂无成绩数据'), findsOneWidget);
  });

  testWidgets('AcademicPage loads exams and grades on refresh', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = FakeBackend();
    final model = _buildTestModel(backend: backend);

    await tester.pumpWidget(_wrap(AcademicPage(model: model)));

    // Tap refresh button in AppBar
    final refreshBtn = find.byTooltip('刷新学业数据');
    expect(refreshBtn, findsOneWidget);
    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();

    // Verify exams are displayed (from sampleExams: '大学物理B')
    expect(find.text('大学物理B'), findsWidgets);
    expect(find.text('崂山校区 弘毅楼 201'), findsWidgets);
    expect(find.text('座位号：32'), findsWidgets);
    expect(find.text('闭卷'), findsWidgets);

    // Verify grades are displayed (from sampleGrades: '高等数学A(1)')
    expect(find.text('高等数学A(1)'), findsWidgets);
    expect(find.text('平均学分绩点 (GPA)'), findsWidgets);
    expect(find.text('已获 / 总学分'), findsWidgets);
  });

  testWidgets('AcademicPage shows warning banner when notEvaluated', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = FakeBackend();
    backend.gradesBehavior = (_, _) =>
        throw const AcademicError(ErrorCode.notEvaluated, '评教未完成');

    final model = _buildTestModel(backend: backend);
    await tester.pumpWidget(_wrap(AcademicPage(model: model)));
    await tester.pumpAndSettle();

    expect(find.text('评教尚未完成'), findsOneWidget);
    expect(find.textContaining('本学期教学质量评价未完成'), findsOneWidget);
  });

  testWidgets('AcademicPage opens calendar export bottom sheet', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = FakeBackend();
    final model = _buildTestModel(backend: backend);

    await tester.pumpWidget(_wrap(AcademicPage(model: model)));
    await tester.pumpAndSettle();

    // Tap "导出日历" button
    final exportBtn = find.text('导出日历');
    expect(exportBtn, findsWidgets);
    await tester.tap(exportBtn.first);
    await tester.pumpAndSettle();

    // Verify bottom sheet appears
    expect(find.text('导出考试日程至系统日历'), findsOneWidget);
    expect(find.text('复制日历内容 (.ics)'), findsOneWidget);
  });

  testWidgets(
    'AcademicPage term selector displays human label and opens anchored menu',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backend = FakeBackend();
      backend.termsBehavior = (_) async => const Terms(
        currentId: '2026-2027-1',
        items: <Term>[
          Term(
            id: '2026-2027-1',
            name: '2026-2027 第1学期',
            year: 2026,
            semester: 1,
          ),
          Term(
            id: '2025-2026-2',
            name: '2025-2026 第2学期',
            year: 2025,
            semester: 2,
          ),
          Term(
            id: '2025-2026-1',
            name: '2025-2026 第1学期',
            year: 2025,
            semester: 1,
          ),
          Term(
            id: '2024-2025-2',
            name: '2024-2025 第2学期',
            year: 2024,
            semester: 2,
          ),
          Term(
            id: '2024-2025-1',
            name: '2024-2025 第1学期',
            year: 2024,
            semester: 1,
          ),
          Term(
            id: '2023-2024-2',
            name: '2023-2024 第2学期',
            year: 2023,
            semester: 2,
          ),
        ],
      );

      final model = _buildTestModel(backend: backend);
      await model.signIn('2407720102', 'pw');
      model.setAcademicTerm('2026-2027-1');

      await tester.pumpWidget(_wrap(AcademicPage(model: model)));
      await tester.pumpAndSettle();

      // Button displays human label "大三 上学期"
      expect(find.text('大三 上学期'), findsOneWidget);

      // Tap term selector button
      await tester.tap(find.text('大三 上学期'));
      await tester.pumpAndSettle();

      // Verify popup menu items
      expect(find.text('2026-2027-1'), findsOneWidget);
      expect(find.text('大二 下学期'), findsOneWidget);
      expect(find.text('2025-2026-2'), findsOneWidget);
      expect(find.text('大一 上学期'), findsOneWidget);
      expect(find.text('2024-2025-1'), findsOneWidget);

      // Verify term before enrollment year (2023-2024-2) is filtered out
      expect(find.text('2023-2024-2'), findsNothing);

      // Tap "大二 下学期"
      await tester.tap(find.text('大二 下学期'));
      await tester.pumpAndSettle();

      // Term switched
      expect(model.academicTermId, '2025-2026-2');
      expect(find.text('大二 下学期'), findsOneWidget);
    },
  );

  testWidgets(
    'AcademicPage term selector filters future terms beyond current academic year',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backend = FakeBackend();
      backend.termsBehavior = (_) async => const Terms(
        currentId: '2024-2025-1',
        items: <Term>[
          Term(
            id: '2026-2027-1',
            name: '2026-2027 第1学期',
            year: 2026,
            semester: 1,
          ),
          Term(
            id: '2024-2025-1',
            name: '2024-2025 第1学期',
            year: 2024,
            semester: 1,
          ),
          Term(
            id: '2024-2025-2',
            name: '2024-2025 第2学期',
            year: 2024,
            semester: 2,
          ),
          Term(
            id: '2023-2024-2',
            name: '2023-2024 第2学期',
            year: 2023,
            semester: 2,
          ),
        ],
      );

      final model = _buildTestModel(backend: backend);
      await model.signIn('2407720102', 'pw');
      model.setAcademicTerm('2024-2025-1');

      await tester.pumpWidget(_wrap(AcademicPage(model: model)));
      await tester.pumpAndSettle();

      expect(find.text('大一 上学期'), findsOneWidget);

      await tester.tap(find.text('大一 上学期'));
      await tester.pumpAndSettle();

      // Current term is present
      expect(find.text('2024-2025-1'), findsOneWidget);
      // Future year term is filtered out
      expect(find.text('2026-2027-1'), findsNothing);
      // Future semester of same year (第2学期) is filtered out
      expect(find.text('2024-2025-2'), findsNothing);
      // Pre-enrollment term is filtered out
      expect(find.text('2023-2024-2'), findsNothing);
    },
  );

  testWidgets('AcademicPage sorts exams and sinks finished exams to bottom', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final now = DateTime.now();
    final backend = FakeBackend();
    backend.examsBehavior = (_, _) async => <ExamItem>[
      ExamItem(
        courseName: '已结束科目',
        startTime: now.subtract(const Duration(days: 3)),
        endTime: now.subtract(const Duration(days: 3, hours: -2)),
        rawTimeStr: '3天前考试',
      ),
      ExamItem(
        courseName: '较晚未来科目',
        startTime: now.add(const Duration(days: 7)),
        endTime: now.add(const Duration(days: 7, hours: 2)),
        rawTimeStr: '7天后考试',
      ),
      ExamItem(courseName: '时间未定科目', rawTimeStr: ''),
      ExamItem(
        courseName: '下一门待考科目',
        startTime: now.add(const Duration(days: 1)),
        endTime: now.add(const Duration(days: 1, hours: 2)),
        rawTimeStr: '明天考试',
      ),
    ];

    final model = _buildTestModel(backend: backend);
    await tester.pumpWidget(_wrap(AcademicPage(model: model)));

    // Refresh to load exams
    final refreshBtn = find.byTooltip('刷新学业数据');
    await tester.tap(refreshBtn);
    await tester.pumpAndSettle();

    // Next upcoming exam appears in hero card
    expect(find.text('下一门待考科目'), findsWidgets);
    expect(find.text('明天考试'), findsWidgets);

    // Finished exam has '已结束' badge
    expect(find.text('已结束科目'), findsOneWidget);
    expect(find.text('已结束'), findsOneWidget);

    // Vertical position ordering in list view:
    // 下一门待考科目 (top) -> 较晚未来科目 -> 时间未定科目 -> 已结束科目 (bottom)
    final yNext = tester.getTopLeft(find.text('下一门待考科目').last).dy;
    final yLater = tester.getTopLeft(find.text('较晚未来科目')).dy;
    final yUndated = tester.getTopLeft(find.text('时间未定科目')).dy;
    final yFinished = tester.getTopLeft(find.text('已结束科目')).dy;

    expect(yNext < yLater, isTrue);
    expect(yLater < yUndated, isTrue);
    expect(yUndated < yFinished, isTrue);
  });

  group('sortAcademicExams and isExamPast logic', () {
    final refNow = DateTime(2026, 11, 4, 12, 0);

    test('isExamPast checks endTime first, then startTime with duration window or end-of-day', () {
      // 1. End time is in the past
      expect(
        isExamPast(
          ExamItem(
            courseName: 'A',
            startTime: DateTime(2026, 11, 4, 9, 0),
            endTime: DateTime(2026, 11, 4, 11, 0),
          ),
          refNow,
        ),
        isTrue,
      );

      // 2. Currently ongoing (startTime before now, endTime after now) -> not past
      expect(
        isExamPast(
          ExamItem(
            courseName: 'B',
            startTime: DateTime(2026, 11, 4, 11, 0),
            endTime: DateTime(2026, 11, 4, 13, 0),
          ),
          refNow,
        ),
        isFalse,
      );

      // 3. Ongoing without explicit endTime (started 30 mins ago, within 2h window) -> not past
      expect(
        isExamPast(
          ExamItem(
            courseName: 'B2',
            startTime: DateTime(2026, 11, 4, 11, 30),
            rawTimeStr: '2026-11-04 11:30',
          ),
          refNow,
        ),
        isFalse,
      );

      // 4. Started > 2h ago without explicit endTime -> past
      expect(
        isExamPast(
          ExamItem(
            courseName: 'B3',
            startTime: DateTime(2026, 11, 4, 9, 0),
            rawTimeStr: '2026-11-04 09:00',
          ),
          refNow,
        ),
        isTrue,
      );

      // 5. Date-only exam scheduled for today at 12:00 -> not past (day not over)
      expect(
        isExamPast(
          ExamItem(
            courseName: 'B4',
            startTime: DateTime(2026, 11, 4, 0, 0),
            rawTimeStr: '2026-11-04',
          ),
          refNow,
        ),
        isFalse,
      );

      // 6. Date-only exam scheduled for yesterday -> past
      expect(
        isExamPast(
          ExamItem(
            courseName: 'B5',
            startTime: DateTime(2026, 11, 3, 0, 0),
            rawTimeStr: '2026-11-03',
          ),
          refNow,
        ),
        isTrue,
      );

      // 7. Future exam
      expect(
        isExamPast(
          ExamItem(
            courseName: 'C',
            startTime: DateTime(2026, 11, 5, 9, 0),
            endTime: DateTime(2026, 11, 5, 11, 0),
          ),
          refNow,
        ),
        isFalse,
      );

      // 8. No date
      expect(isExamPast(const ExamItem(courseName: 'D'), refNow), isFalse);
    });

    test('sortAcademicExams places active/future first, unannounced middle, past at bottom', () {
      final exams = <ExamItem>[
        ExamItem(
          courseName: '已结束科目2',
          startTime: DateTime(2026, 11, 2, 9, 0),
          endTime: DateTime(2026, 11, 2, 11, 0),
        ),
        ExamItem(courseName: '未定时间科目', rawTimeStr: ''),
        ExamItem(
          courseName: '已结束科目1',
          startTime: DateTime(2026, 11, 1, 9, 0),
          endTime: DateTime(2026, 11, 1, 11, 0),
        ),
        ExamItem(
          courseName: '进行中科目',
          startTime: DateTime(2026, 11, 4, 11, 0),
          endTime: DateTime(2026, 11, 4, 13, 0),
        ),
        ExamItem(
          courseName: '未来科目2',
          startTime: DateTime(2026, 11, 6, 9, 0),
          endTime: DateTime(2026, 11, 6, 11, 0),
        ),
        ExamItem(
          courseName: '未来科目1',
          startTime: DateTime(2026, 11, 5, 9, 0),
          endTime: DateTime(2026, 11, 5, 11, 0),
        ),
      ];

      final sorted = sortAcademicExams(exams, now: refNow);
      final names = sorted.map((e) => e.courseName).toList();

      expect(names, <String>[
        '进行中科目', // Active/ongoing: startTime earliest among active
        '未来科目1', // Next upcoming future
        '未来科目2', // Later future
        '未定时间科目', // Unscheduled
        '已结束科目1', // Past (11-01)
        '已结束科目2', // Past (11-02)
      ]);
    });

    test('sortAcademicExams prioritizes confirmed time over date-only on same date', () {
      final exams = <ExamItem>[
        ExamItem(
          courseName: '仅定日期科目',
          startTime: DateTime(2026, 11, 5, 0, 0),
          rawTimeStr: '2026-11-05',
        ),
        ExamItem(
          courseName: '已定具体时刻科目',
          startTime: DateTime(2026, 11, 5, 14, 0),
          endTime: DateTime(2026, 11, 5, 16, 0),
          rawTimeStr: '2026-11-05 14:00-16:00',
        ),
      ];

      final sorted = sortAcademicExams(exams, now: refNow);
      expect(sorted.first.courseName, '已定具体时刻科目');
      expect(sorted.last.courseName, '仅定日期科目');
    });

    test('sortAcademicExams handles empty list gracefully', () {
      expect(sortAcademicExams(<ExamItem>[], now: refNow), isEmpty);
    });

    testWidgets('NextExamHeroCard calculates countdown labels correctly', (
      tester,
    ) async {
      final wedNight = DateTime(2026, 11, 4, 23, 0);

      // 1. Exam on Friday 08:00 (后天, 33 hours away) must say "离下一场还剩 2 天", not "明天考试"
      final friExam = ExamItem(
        courseName: 'Friday Exam',
        startTime: DateTime(2026, 11, 6, 8, 0),
        endTime: DateTime(2026, 11, 6, 10, 0),
        rawTimeStr: '2026-11-06 08:00-10:00',
      );
      await tester.pumpWidget(
        _wrap(NextExamHeroCard(exam: friExam, now: wedNight)),
      );
      expect(find.text('离下一场还剩 2 天'), findsOneWidget);

      // 2. Exam tomorrow morning
      final thuExam = ExamItem(
        courseName: 'Thursday Exam',
        startTime: DateTime(2026, 11, 5, 9, 0),
        endTime: DateTime(2026, 11, 5, 11, 0),
        rawTimeStr: '2026-11-05 09:00-11:00',
      );
      await tester.pumpWidget(
        _wrap(NextExamHeroCard(exam: thuExam, now: wedNight)),
      );
      expect(find.text('明天考试'), findsOneWidget);

      // 3. Ongoing exam
      final now11 = DateTime(2026, 11, 4, 11, 30);
      final ongoingExam = ExamItem(
        courseName: 'Ongoing Exam',
        startTime: DateTime(2026, 11, 4, 11, 0),
        endTime: DateTime(2026, 11, 4, 13, 0),
        rawTimeStr: '2026-11-04 11:00-13:00',
      );
      await tester.pumpWidget(
        _wrap(NextExamHeroCard(exam: ongoingExam, now: now11)),
      );
      expect(find.text('正在进行'), findsOneWidget);

      // 4. Date-only exam today at 10 AM must show "今天考试", NOT "正在进行"
      final todayDateOnly = ExamItem(
        courseName: 'Date Only Today',
        startTime: DateTime(2026, 11, 4, 0, 0),
        rawTimeStr: '2026-11-04',
      );
      await tester.pumpWidget(
        _wrap(
          NextExamHeroCard(
            exam: todayDateOnly,
            now: DateTime(2026, 11, 4, 10, 0),
          ),
        ),
      );
      expect(find.text('今天考试'), findsOneWidget);
    });
  });
}
