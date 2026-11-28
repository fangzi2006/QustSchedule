import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/academic_page.dart';
import 'package:qustschedule/src/academic_cache.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:qustschedule/src/term_calendar.dart';
import 'package:zf_academic/zf_academic.dart';

import 'support/fake_backend.dart';

const _baseUrl = 'https://jw.example.edu.cn';

class _GatedExamCache extends InMemoryExamCache {
  _GatedExamCache({required String gateForTerm, required this._gate})
    : _gateTerm = gateForTerm;

  String _gateTerm;
  Completer<void> _gate;

  void setGate(String termId, Completer<void> gate) {
    _gateTerm = termId;
    _gate = gate;
  }

  @override
  Future<CachedTermExams?> load(String termId) async {
    if (termId == _gateTerm && !_gate.isCompleted) {
      await _gate.future;
    }
    return super.load(termId);
  }
}

AppModel _buildTestModel({
  FakeBackend? backend,
  ExamCache? examCache,
  GradesCache? gradesCache,
}) {
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
    examCache: examCache ?? InMemoryExamCache(),
    gradesCache: gradesCache ?? InMemoryGradesCache(),
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
    await tester.pump(const Duration(seconds: 5));

    // Verify exams are displayed (from sampleExams: '大学物理B')
    expect(find.text('大学物理B'), findsWidgets);
    expect(find.text('崂山校区 弘毅楼 201'), findsWidgets);
    expect(find.text('座位号：32'), findsWidgets);
    expect(find.text('闭卷'), findsWidgets);

    // Verify grades are displayed (from sampleGrades: '高等数学A(1)')
    expect(find.text('高等数学A(1)'), findsWidgets);
    expect(find.text('学期平均学分绩点 (GPA)'), findsWidgets);
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

  testWidgets(
    'AcademicPage shows friendly error banners and retry button on network errors',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      for (final (Object error, String expectedBanner) in [
        (const SocketException('Connection refused'), '无法连接教务网，请检查网络或连接校园网后重试'),
        (TimeoutException('request timeout'), '网络请求超时，请检查网络后重试'),
      ]) {
        final backend = FakeBackend();
        backend.gradesBehavior = (_, _) => throw error;
        final model = _buildTestModel(backend: backend);

        await tester.pumpWidget(_wrap(AcademicPage(model: model)));
        await tester.tap(find.byTooltip('刷新学业数据'));
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));
        await tester.pump(const Duration(seconds: 5));

        expect(find.text(expectedBanner), findsOneWidget);
        expect(find.text('重试'), findsOneWidget);
      }
    },
  );

  testWidgets(
    'AcademicPage properly renders qualitative, extended passing, and null-GPA grades',
    (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final backend = FakeBackend();
      backend.gradesBehavior = (_, _) async => const <GradeItem>[
        GradeItem(
          courseName: '形势与政策',
          credit: 1.0,
          rawScore: '通过',
          termId: '2026-2027-1',
        ),
        GradeItem(
          courseName: '实训科目',
          credit: 2.0,
          rawScore: '合格',
          termId: '2026-2027-1',
        ),
        GradeItem(
          courseName: '免修英语',
          credit: 3.0,
          rawScore: '免修',
          termId: '2026-2027-1',
        ),
        GradeItem(
          courseName: '体育(1)',
          credit: 1.0,
          gradePoint: null,
          rawScore: '92',
          numericScore: 92.0,
          termId: '2026-2027-1',
        ),
      ];
      final model = _buildTestModel(backend: backend);

      await tester.pumpWidget(_wrap(AcademicPage(model: model)));
      await tester.tap(find.byTooltip('刷新学业数据'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      expect(find.text('形势与政策'), findsOneWidget);
      expect(find.text('通过'), findsOneWidget);
      expect(find.text('实训科目'), findsOneWidget);
      expect(find.text('合格'), findsOneWidget);
      expect(find.text('免修英语'), findsOneWidget);
      expect(find.text('免修'), findsOneWidget);
      expect(find.text('体育(1)'), findsOneWidget);
      expect(find.text('1.0 学分'), findsWidgets);
      expect(find.textContaining('null'), findsNothing);
    },
  );

  testWidgets(
    'AcademicPage term selector displays human label, filters pre-enrollment and future terms, and switches term',
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
            id: '2027-2028-1',
            name: '2027-2028 第1学期',
            year: 2027,
            semester: 1,
          ),
          Term(
            id: '2026-2027-2',
            name: '2026-2027 第2学期',
            year: 2026,
            semester: 2,
          ),
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
      await model.signIn('2412345678', 'pw');
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

      // Verify pre-enrollment term (2023-2024-2) and future terms (2027-2028-1, 2026-2027-2) are filtered out
      expect(find.text('2023-2024-2'), findsNothing);
      expect(find.text('2027-2028-1'), findsNothing);
      expect(find.text('2026-2027-2'), findsNothing);

      // Tap "大二 下学期"
      await tester.tap(find.text('大二 下学期'));
      await tester.pumpAndSettle();

      // Term switched
      expect(model.academicTermId, '2025-2026-2');
      expect(find.text('大二 下学期'), findsOneWidget);
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
    await tester.pump(const Duration(seconds: 5));

    // Next upcoming exam appears in hero card and is NOT duplicated in bottom list
    expect(find.text('下一门待考科目'), findsOneWidget);
    expect(
      find.text('明天考试'),
      findsNWidgets(2),
    ); // countdown badge + rawTimeStr in hero card
    expect(find.byKey(const Key('academic-exam-list-card')), findsOneWidget);

    // Finished exam has '已结束' badge
    expect(find.text('已结束科目'), findsOneWidget);
    expect(find.text('已结束'), findsOneWidget);

    // Vertical position ordering:
    // 下一门待考科目 (top Hero card) -> 较晚未来科目 (list) -> 时间未定科目 (list) -> 已结束科目 (list bottom)
    final yNext = tester.getTopLeft(find.text('下一门待考科目')).dy;
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

    test('sortAcademicExams handles ordering, time-over-date priority and empty list', () {
      expect(sortAcademicExams(<ExamItem>[], now: refNow), isEmpty);

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

      expect(sortAcademicExams(exams, now: refNow).map((e) => e.courseName), [
        '进行中科目',
        '未来科目1',
        '未来科目2',
        '未定时间科目',
        '已结束科目1',
        '已结束科目2',
      ]);

      final sameDate = <ExamItem>[
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
      final sortedSameDate = sortAcademicExams(sameDate, now: refNow);
      expect(sortedSameDate.first.courseName, '已定具体时刻科目');
      expect(sortedSameDate.last.courseName, '仅定日期科目');
    });

    testWidgets(
      'NextExamHeroCard calculates countdown labels, renders seatNumber and hides examType',
      (tester) async {
        final wedNight = DateTime(2026, 11, 4, 23, 0);

        // 1. 33 小时后的周五考试（后天）必须显示 2 天，而非明天；同时验证座位号与隐藏 examType
        final friExam = ExamItem(
          courseName: 'Friday Exam',
          examType: '2024-2025-1期末考试',
          startTime: DateTime(2026, 11, 6, 8, 0),
          endTime: DateTime(2026, 11, 6, 10, 0),
          rawTimeStr: '2026-11-06 08:00-10:00',
          seatNumber: '42',
        );
        await tester.pumpWidget(
          _wrap(NextExamHeroCard(exam: friExam, now: wedNight)),
        );
        expect(find.text('离下一场还剩 2 天'), findsOneWidget);
        expect(find.text('座位号：42'), findsOneWidget);
        expect(find.text('2024-2025-1期末考试'), findsNothing);

        // 2. 明天上午
        await tester.pumpWidget(
          _wrap(
            NextExamHeroCard(
              exam: ExamItem(
                courseName: 'Thursday Exam',
                startTime: DateTime(2026, 11, 5, 9, 0),
                endTime: DateTime(2026, 11, 5, 11, 0),
                rawTimeStr: '2026-11-05 09:00-11:00',
              ),
              now: wedNight,
            ),
          ),
        );
        expect(find.text('明天考试'), findsOneWidget);

        // 3. 正在进行
        await tester.pumpWidget(
          _wrap(
            NextExamHeroCard(
              exam: ExamItem(
                courseName: 'Ongoing Exam',
                startTime: DateTime(2026, 11, 4, 11, 0),
                endTime: DateTime(2026, 11, 4, 13, 0),
                rawTimeStr: '2026-11-04 11:00-13:00',
              ),
              now: DateTime(2026, 11, 4, 11, 30),
            ),
          ),
        );
        expect(find.text('正在进行'), findsOneWidget);

        // 4. 仅定日期在当天上午显示 "今天考试"
        await tester.pumpWidget(
          _wrap(
            NextExamHeroCard(
              exam: ExamItem(
                courseName: 'Date Only Today',
                startTime: DateTime(2026, 11, 4, 0, 0),
                rawTimeStr: '2026-11-04',
              ),
              now: DateTime(2026, 11, 4, 10, 0),
            ),
          ),
        );
        expect(find.text('今天考试'), findsOneWidget);
      },
    );

    testWidgets(
      'AcademicPage with single upcoming exam renders Hero card only and hides bottom list card',
      (tester) async {
        final now = DateTime.now();
        final backend = FakeBackend();
        backend.examsBehavior = (_, _) async => <ExamItem>[
          ExamItem(
            courseName: '唯一考试科目',
            startTime: now.add(const Duration(days: 2)),
            endTime: now.add(const Duration(days: 2, hours: 2)),
            rawTimeStr: '后天考试',
            seatNumber: '15',
          ),
        ];

        final model = _buildTestModel(backend: backend);
        await tester.pumpWidget(_wrap(AcademicPage(model: model)));

        final refreshBtn = find.byTooltip('刷新学业数据');
        await tester.tap(refreshBtn);
        await tester.pumpAndSettle();
        await tester.pump(const Duration(seconds: 5));

        // 唯一考试只在顶部 Hero 卡片中展示 1 次，不重复出现在下方列表中
        expect(find.text('唯一考试科目'), findsOneWidget);
        expect(find.text('座位号：15'), findsOneWidget);
        expect(find.byType(NextExamHeroCard), findsOneWidget);

        // 下方没有剩余考试，不渲染下方的列表卡片
        expect(find.byKey(const Key('academic-exam-list-card')), findsNothing);
      },
    );

    test('formatExamTimeLabel 仅在提供 currentTermStart 且考试含日期时追加第X周 周X', () {
      final exam = ExamItem(
        courseName: '毛概',
        startTime: DateTime(2026, 12, 8, 13, 30),
        endTime: DateTime(2026, 12, 8, 15, 5),
        rawTimeStr: '2026-12-08(13:30-15:05)',
      );
      expect(
        formatExamTimeLabel(exam, currentTermStart: DateTime(2026, 8, 31)),
        '2026-12-08(13:30-15:05)·第15周 周二',
      );
      expect(formatExamTimeLabel(exam), '2026-12-08(13:30-15:05)');
      expect(
        formatExamTimeLabel(
          const ExamItem(courseName: '无时间'),
          currentTermStart: DateTime(2026, 8, 31),
        ),
        '时间未公布',
      );
      expect(
        formatExamTimeLabel(
          const ExamItem(courseName: '待定', rawTimeStr: '待定'),
          currentTermStart: DateTime(2026, 8, 31),
        ),
        '待定',
      );
      // 早于开学周周一的考前补考/未校准偏差日期：不误标为第1周
      expect(
        formatExamTimeLabel(
          ExamItem(
            courseName: '开学前补考',
            startTime: DateTime(2026, 8, 28, 9, 0),
            rawTimeStr: '2026-08-28(09:00-11:00)',
          ),
          currentTermStart: DateTime(2026, 8, 31),
        ),
        '2026-08-28(09:00-11:00)',
      );
      // 原文已含周次或星期时：不重复拼接
      expect(
        formatExamTimeLabel(
          ExamItem(
            courseName: '已带周次',
            startTime: DateTime(2026, 12, 8, 13, 30),
            rawTimeStr: '2026-12-08 第15周 13:30',
          ),
          currentTermStart: DateTime(2026, 8, 31),
        ),
        '2026-12-08 第15周 13:30',
      );
      expect(
        formatExamTimeLabel(
          ExamItem(
            courseName: '已带星期',
            startTime: DateTime(2026, 12, 8, 13, 30),
            rawTimeStr: '2026-12-08 周二 13:30',
          ),
          currentTermStart: DateTime(2026, 8, 31),
        ),
        '2026-12-08 周二 13:30',
      );
    });

    testWidgets('AcademicPage 当前课表学期考试追加 ·第X周 周X 并在校准周次后刷新，切换历史学期不追加', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final nextExamDate = today.add(const Duration(days: 14));
      final laterExamDate = today.add(const Duration(days: 21));
      final initTermStart = mondayOf(today).subtract(const Duration(days: 14));
      const weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];

      String fmtDate(DateTime d) =>
          '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

      final nextRaw = '${fmtDate(nextExamDate)}(13:30-15:05)';
      final laterRaw = '${fmtDate(laterExamDate)}(09:00-11:00)';
      const pastRaw = '2025-12-01(09:00-11:00)';

      final currentExams = <ExamItem>[
        ExamItem(
          courseName: '置顶考试科目',
          startTime: DateTime(
            nextExamDate.year,
            nextExamDate.month,
            nextExamDate.day,
            13,
            30,
          ),
          endTime: DateTime(
            nextExamDate.year,
            nextExamDate.month,
            nextExamDate.day,
            15,
            5,
          ),
          rawTimeStr: nextRaw,
        ),
        ExamItem(
          courseName: '后续考试科目',
          startTime: DateTime(
            laterExamDate.year,
            laterExamDate.month,
            laterExamDate.day,
            9,
            0,
          ),
          endTime: DateTime(
            laterExamDate.year,
            laterExamDate.month,
            laterExamDate.day,
            11,
            0,
          ),
          rawTimeStr: laterRaw,
        ),
        const ExamItem(courseName: '未公布科目', rawTimeStr: ''),
      ];
      final historyExams = <ExamItem>[
        ExamItem(
          courseName: '历史学期科目',
          startTime: DateTime(2025, 12, 1, 9, 0),
          endTime: DateTime(2025, 12, 1, 11, 0),
          rawTimeStr: pastRaw,
        ),
      ];

      final backend = FakeBackend();
      backend.examsBehavior = (_, termId) async =>
          termId == '2025-2026-2' ? historyExams : currentExams;

      final model = _buildTestModel(backend: backend);
      addTearDown(model.dispose);
      model.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 18,
          entries: <ScheduleEntry>[],
        ),
        terms: const Terms(
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
          ],
        ),
        termStart: initTermStart,
      );
      model.setAcademicTerm('2026-2027-1');

      await tester.pumpWidget(_wrap(AcademicPage(model: model)));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));

      final wNextBefore = weekOf(initTermStart, nextExamDate);
      final wLaterBefore = weekOf(initTermStart, laterExamDate);
      expect(
        find.text(
          '$nextRaw·第$wNextBefore周 ${weekdays[nextExamDate.weekday - 1]}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '$laterRaw·第$wLaterBefore周 ${weekdays[laterExamDate.weekday - 1]}',
        ),
        findsOneWidget,
      );
      expect(find.text('时间未公布'), findsOneWidget);

      // 校准周次后，学业页自动刷新并展示最新周次
      await model.calibrateCurrentWeek(6);
      await tester.pump();
      final calibratedStart = model.termStart!;
      final wNextAfter = weekOf(calibratedStart, nextExamDate);
      final wLaterAfter = weekOf(calibratedStart, laterExamDate);
      expect(wNextAfter, isNot(wNextBefore));
      expect(
        find.text(
          '$nextRaw·第$wNextAfter周 ${weekdays[nextExamDate.weekday - 1]}',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          '$laterRaw·第$wLaterAfter周 ${weekdays[laterExamDate.weekday - 1]}',
        ),
        findsOneWidget,
      );

      // 切换到历史学期时，仅展示原始时间文本，不追加周次与星期
      model.setAcademicTerm('2025-2026-2');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(find.text(pastRaw), findsOneWidget);
      expect(find.textContaining('·第'), findsNothing);

      // 重置校历（恢复默认估算）同样触发已挂载学业页刷新周次
      model.setAcademicTerm('2026-2027-1');
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 5));
      expect(
        find.text(
          '$nextRaw·第$wNextAfter周 ${weekdays[nextExamDate.weekday - 1]}',
        ),
        findsOneWidget,
      );
      await model.resetCalendar();
      await tester.pump();
      final resetStart = model.termStart!;
      final wNextReset = weekOf(resetStart, nextExamDate);
      expect(wNextReset, isNot(wNextAfter));
      expect(
        find.text(
          '$nextRaw·第$wNextReset周 ${weekdays[nextExamDate.weekday - 1]}',
        ),
        findsOneWidget,
      );
    });

    testWidgets('先挂载 AcademicPage 后才加载课表、以及 setAcademicTerm 异步切回窗口均保证周次同步与归属隔离', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      final nextExamDate = today.add(const Duration(days: 14));
      final initTermStart = mondayOf(today).subtract(const Duration(days: 14));
      const weekdays = <String>['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
      final dateStr =
          '${nextExamDate.year}-${nextExamDate.month.toString().padLeft(2, '0')}-${nextExamDate.day.toString().padLeft(2, '0')}';
      final currentRaw = '$dateStr(13:30-15:05)';
      const historyRaw = '2025-12-01(09:00-11:00)';

      final gate = Completer<void>();
      final examCache = _GatedExamCache(gateForTerm: '2026-2027-1', gate: gate);
      await examCache.save('2026-2027-1', <ExamItem>[
        ExamItem(
          courseName: '当前学期课程',
          startTime: DateTime(
            nextExamDate.year,
            nextExamDate.month,
            nextExamDate.day,
            13,
            30,
          ),
          endTime: DateTime(
            nextExamDate.year,
            nextExamDate.month,
            nextExamDate.day,
            15,
            5,
          ),
          rawTimeStr: currentRaw,
        ),
      ]);
      await examCache.save('2025-2026-2', <ExamItem>[
        ExamItem(
          courseName: '历史学期课程',
          startTime: DateTime(2025, 12, 1, 9, 0),
          endTime: DateTime(2025, 12, 1, 11, 0),
          rawTimeStr: historyRaw,
        ),
      ]);

      final backend = FakeBackend();
      backend.examsBehavior = (_, termId) async => termId == '2025-2026-2'
          ? <ExamItem>[
              ExamItem(
                courseName: '历史学期课程',
                startTime: DateTime(2025, 12, 1, 9, 0),
                endTime: DateTime(2025, 12, 1, 11, 0),
                rawTimeStr: historyRaw,
              ),
            ]
          : const <ExamItem>[];

      final model = _buildTestModel(backend: backend, examCache: examCache);
      addTearDown(model.dispose);

      // 1. 课表尚未加载时先挂载学业页并加载当前学期缓存（不依赖阻塞门）
      gate.complete();
      await model.loadAcademicData(termId: '2026-2027-1');
      model.setAcademicTerm('2026-2027-1');
      await tester.pumpWidget(_wrap(AcademicPage(model: model)));
      await tester.pumpAndSettle();
      expect(find.text(currentRaw), findsOneWidget);
      expect(find.textContaining('·第'), findsNothing);

      // 2. 随后课表加载完成写入 termId 与 termStart，已挂载学业页应自动补全 ·第X周 周X
      model.hydrateForTest(
        schedule: const Schedule(
          termId: '2026-2027-1',
          maxWeeks: 18,
          entries: <ScheduleEntry>[],
        ),
        termStart: initTermStart,
      );
      await tester.pump();
      final expectedWeek = weekOf(initTermStart, nextExamDate);
      expect(
        find.text(
          '$currentRaw·第$expectedWeek周 ${weekdays[nextExamDate.weekday - 1]}',
        ),
        findsOneWidget,
      );

      // 3. 切到历史学期后再切回当前学期，读盘门未放行期间历史考试绝不被错拼当前学期周次
      model.setAcademicTerm('2025-2026-2');
      await tester.pumpAndSettle();
      expect(find.text(historyRaw), findsOneWidget);

      final secondGate = Completer<void>();
      examCache.setGate('2026-2027-1', secondGate);
      model.setAcademicTerm('2026-2027-1');
      await tester.pump();
      expect(find.text(historyRaw), findsOneWidget);
      expect(find.textContaining('·第'), findsNothing);

      secondGate.complete();
      await tester.pumpAndSettle();
      expect(
        find.text(
          '$currentRaw·第$expectedWeek周 ${weekdays[nextExamDate.weekday - 1]}',
        ),
        findsOneWidget,
      );
    });
  });

  group('学业更新差异比对与全局气泡通知', () {
    test('考试、成绩或双项变动时分别触发对应全局提示', () async {
      // 仅考试变动
      final examOnlyCache = InMemoryExamCache();
      await examOnlyCache.save('2026-2027-1', const [
        ExamItem(courseName: '旧高数'),
      ]);
      final examBackend = FakeBackend()
        ..examsBehavior = (_, _) async => const [ExamItem(courseName: '新高数')];
      final examModel = _buildTestModel(
        backend: examBackend,
        examCache: examOnlyCache,
      );
      await examModel.signIn('2412345678', 'pw');
      examModel.setAcademicTerm('2026-2027-1');
      await examModel.refreshAcademicData();
      expect(examModel.globalHint, '考试安排有更新');
      expect(examModel.isAcademicUpdateHint, isTrue);

      // 仅成绩变动
      final gradesOnlyCache = InMemoryGradesCache();
      await gradesOnlyCache.save('2026-2027-1', const [
        GradeItem(courseName: '高等数学', credit: 4.0, rawScore: '85'),
      ]);
      final gradesBackend = FakeBackend()
        ..gradesBehavior = (_, _) async => const [
          GradeItem(courseName: '高等数学', credit: 4.0, rawScore: '90'),
        ];
      final gradesModel = _buildTestModel(
        backend: gradesBackend,
        gradesCache: gradesOnlyCache,
      );
      await gradesModel.signIn('2412345678', 'pw');
      gradesModel.setAcademicTerm('2026-2027-1');
      await gradesModel.refreshAcademicData();
      expect(gradesModel.globalHint, '成绩有更新');
      expect(gradesModel.isAcademicUpdateHint, isTrue);

      // 双项变动
      final bothExamCache = InMemoryExamCache();
      await bothExamCache.save('2026-2027-1', const [
        ExamItem(courseName: '旧高数'),
      ]);
      final bothGradesCache = InMemoryGradesCache();
      await bothGradesCache.save('2026-2027-1', const [
        GradeItem(courseName: '旧英语', credit: 2.0, rawScore: '80'),
      ]);
      final bothBackend = FakeBackend()
        ..examsBehavior = ((_, _) async => const [ExamItem(courseName: '新高数')])
        ..gradesBehavior = (_, _) async => const [
          GradeItem(courseName: '新英语', credit: 2.0, rawScore: '95'),
        ];
      final bothModel = _buildTestModel(
        backend: bothBackend,
        examCache: bothExamCache,
        gradesCache: bothGradesCache,
      );
      await bothModel.signIn('2412345678', 'pw');
      bothModel.setAcademicTerm('2026-2027-1');
      await bothModel.refreshAcademicData();
      expect(bothModel.globalHint, '学业数据有更新');
      expect(bothModel.isAcademicUpdateHint, isTrue);
      expect(bothModel.academicHint, isEmpty);
    });

    test('无变动或初次加载时均不触发全局更新气泡', () async {
      // 数据与缓存一致 -> 仅局部「已更新」
      const sameExams = <ExamItem>[ExamItem(courseName: '高等数学')];
      final examCache = InMemoryExamCache();
      await examCache.save('2026-2027-1', sameExams);
      final sameModel = _buildTestModel(
        backend: FakeBackend()..examsBehavior = (_, _) async => sameExams,
        examCache: examCache,
      );
      await sameModel.signIn('2412345678', 'pw');
      sameModel.setAcademicTerm('2026-2027-1');
      await sameModel.refreshAcademicData();
      expect(sameModel.globalHint, isEmpty);
      expect(sameModel.isAcademicUpdateHint, isFalse);
      expect(sameModel.academicHint, '已更新');

      // 无初始缓存 -> 不触发全局更新气泡
      final coldModel = _buildTestModel(
        backend: FakeBackend()
          ..examsBehavior = (_, _) async => const [
            ExamItem(courseName: '初次拉取的科目'),
          ],
      );
      await coldModel.signIn('2412345678', 'pw');
      coldModel.setAcademicTerm('2026-2027-1');
      await coldModel.refreshAcademicData();
      expect(coldModel.globalHint, isEmpty);
      expect(coldModel.isAcademicUpdateHint, isFalse);
    });

    test('调试清除学业数据后刷新，可触发全局更新提示', () async {
      final examCache = InMemoryExamCache();
      await examCache.save('2026-2027-1', <ExamItem>[
        const ExamItem(courseName: '现有高数'),
      ]);

      final backend = FakeBackend();
      backend.examsBehavior = (_, _) async => <ExamItem>[
        const ExamItem(courseName: '现有高数'),
      ];

      final model = _buildTestModel(backend: backend, examCache: examCache);
      await model.signIn('2412345678', 'pw');
      await model.loadAcademicData(termId: '2026-2027-1');

      // 清除学业缓存与内存数据
      await model.clearAcademicDataForDebug();
      expect(model.exams, isEmpty);
      expect(await examCache.load('2026-2027-1'), isNull);

      // 刷新学业数据：因为处于调试清除状态，重新拉取后与基准对比发生更新，触发全局通知
      await model.refreshAcademicData();

      expect(model.globalHint, '学业数据有更新');
      expect(model.isAcademicUpdateHint, isTrue);
      expect(model.academicHint, isEmpty);
    });
  });

  testWidgets('学业页遇自动登录熔断时横幅展示统一提示与「重新登录」按钮，点击进入登录页', (tester) async {
    tester.view.physicalSize = const Size(800, 1800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final backend = FakeBackend();
    final model = _buildTestModel(backend: backend);
    addTearDown(model.dispose);
    await model.signIn('20240001', 'pw');

    backend.examsBehavior = (_, _) async => throw expired();
    backend.gradesBehavior = (_, _) async => throw expired();
    backend.loginBehavior = (_, _) async => throw badCredentials();

    // 首次失败触发密码错并立刻熔断
    await model.refreshAcademicData(showHint: false);
    // 二次刷新命中熔断
    await model.refreshAcademicData(showHint: false);

    await tester.pumpWidget(_wrap(AcademicPage(model: model)));
    await tester.pumpAndSettle();

    expect(find.text('自动登录已暂停（多次失败或密码已变更），请重新登录。'), findsOneWidget);
    final reloginBtn = find.widgetWithText(TextButton, '重新登录');
    expect(reloginBtn, findsOneWidget);
    expect(find.widgetWithText(TextButton, '重试'), findsNothing);

    await tester.tap(reloginBtn);
    await tester.pump();
    expect(model.status, AppStatus.needLogin);
  });

  testWidgets('学业页刷新按钮保持静态禁用且气泡统一「更新中...」，失败仅展顶部红底横幅不重复弹红气泡', (tester) async {
    final examsGate = Completer<List<ExamItem>>();
    final gradesGate = Completer<List<GradeItem>>();
    final backend = FakeBackend()
      ..examsBehavior = ((_, _) => examsGate.future)
      ..gradesBehavior = ((_, _) => gradesGate.future);
    final model = _buildTestModel(backend: backend);
    addTearDown(model.dispose);
    model.hydrateForTest(
      schedule: sampleSchedule('2026-2027-1'),
      exams: sampleExams('2026-2027-1'),
      grades: sampleGrades('2026-2027-1'),
    );

    await tester.pumpWidget(_wrap(AcademicPage(model: model)));
    await tester.pumpAndSettle();

    final refreshBtnFinder = find.widgetWithIcon(
      IconButton,
      Icons.refresh_rounded,
    );
    expect(refreshBtnFinder, findsOneWidget);

    await tester.tap(refreshBtnFinder);
    await tester.pump();

    // 1. 方案 B：顶栏刷新按钮保持静态刷新图标（仅禁用），不替换为转圈；右上角气泡统一显示「更新中...」
    expect(refreshBtnFinder, findsOneWidget);
    expect(tester.widget<IconButton>(refreshBtnFinder).onPressed, isNull);
    expect(
      find.descendant(
        of: find.byType(AppBar),
        matching: find.byType(CircularProgressIndicator),
      ),
      findsNothing,
    );
    expect(model.academicHint, '更新中...');
    expect(find.text('更新中...'), findsOneWidget);

    // 2. 失败时仅由顶部红底横幅承载错误，右上角气泡收起不重复弹红气泡
    examsGate.completeError(
      const AcademicError(ErrorCode.networkRetryable, '网络不稳定'),
    );
    gradesGate.completeError(
      const AcademicError(ErrorCode.networkRetryable, '网络不稳定'),
    );
    await tester.pumpAndSettle();

    expect(model.academicError, isNotNull);
    expect(model.academicHint, isEmpty);
    expect(find.textContaining('更新失败：'), findsNothing);
    expect(find.widgetWithText(TextButton, '重试'), findsOneWidget);
    expect(tester.widget<IconButton>(refreshBtnFinder).onPressed, isNotNull);
  });
}
