import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/academic_cache.dart';
import 'package:qustschedule/src/academic_service.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:zf_academic/zf_academic.dart';

import 'support/fake_backend.dart';

void main() {
  group('GradeStats.calculate', () {
    test('returns zeroed stats when list is empty', () {
      final stats = GradeStats.calculate(const []);
      expect(stats.averageGpa, equals(0.0));
      expect(stats.totalCredits, equals(0.0));
      expect(stats.passedCredits, equals(0.0));
      expect(stats.totalCourses, equals(0));
      expect(stats.passedCourses, equals(0));
    });

    test('calculates weighted GPA and passed credits accurately', () {
      final grades = [
        const GradeItem(
          courseName: '高等数学A',
          credit: 4.0,
          gradePoint: 4.0,
          rawScore: '90',
        ),
        const GradeItem(
          courseName: '大学英语',
          credit: 2.0,
          gradePoint: 2.0,
          rawScore: '70',
        ),
        const GradeItem(
          courseName: '大学物理B',
          credit: 3.0,
          gradePoint: 0.0,
          rawScore: '45',
        ),
      ];

      final stats = GradeStats.calculate(grades);
      expect(stats.totalCourses, equals(3));
      expect(stats.passedCourses, equals(2));
      expect(stats.totalCredits, equals(9.0));
      expect(stats.passedCredits, equals(6.0));
      // GPA = (4.0 * 4.0 + 2.0 * 2.0 + 3.0 * 0.0) / (4.0 + 2.0 + 3.0) = 20 / 9 = 2.2222...
      expect(stats.averageGpa, closeTo(20.0 / 9.0, 0.0001));
    });

    test('recognizes qualitative passing scores (通过, 良好, etc.)', () {
      final grades = [
        const GradeItem(courseName: '形势与政策', credit: 1.0, rawScore: '通过'),
        const GradeItem(courseName: '军事理论', credit: 1.5, rawScore: '优秀'),
        const GradeItem(courseName: '毕业设计', credit: 4.0, rawScore: '中等'),
      ];

      final stats = GradeStats.calculate(grades);
      expect(stats.totalCourses, equals(3));
      expect(stats.passedCourses, equals(3));
      expect(stats.passedCredits, equals(6.5));
    });

    test('recognizes extended passing scores (免修, 免考, 合格, P, p)', () {
      final grades = [
        const GradeItem(courseName: '大学英语免修', credit: 2.0, rawScore: '免修'),
        const GradeItem(courseName: '体育免考', credit: 1.0, rawScore: '免考'),
        const GradeItem(courseName: '金工实习', credit: 1.5, rawScore: '合格'),
        const GradeItem(courseName: '通识选修1', credit: 1.0, rawScore: 'P'),
        const GradeItem(courseName: '通识选修2', credit: 0.5, rawScore: 'p'),
        const GradeItem(courseName: '高等数学挂科', credit: 4.0, rawScore: '不及格'),
        const GradeItem(courseName: '未通过科目', credit: 1.0, rawScore: '不通过'),
      ];

      final stats = GradeStats.calculate(grades);
      expect(stats.totalCourses, equals(7));
      expect(stats.passedCourses, equals(5));
      expect(stats.passedCredits, equals(6.0));
    });
  });

  group('AcademicService operations', () {
    late FakeBackend backend;
    late ScheduleService scheduleService;
    late InMemoryExamCache examCache;
    late InMemoryGradesCache gradesCache;
    late AcademicService academicService;

    setUp(() {
      backend = FakeBackend();
      scheduleService = ScheduleService(
        credentials: InMemoryCredentialStore(),
        cookieStorage: FakeSessionRepository(),
        captchaHandler: (_) async => null,
        backendFactory: (_) => backend,
      );
      examCache = InMemoryExamCache();
      gradesCache = InMemoryGradesCache();
      academicService = AcademicService(
        service: scheduleService,
        examCache: examCache,
        gradesCache: gradesCache,
      );
    });

    test('fetchExams queries service and caches result', () async {
      expect(await examCache.load('2026-2027-1'), isNull);

      final exams = await academicService.fetchExams('2026-2027-1');
      expect(exams, isNotEmpty);
      expect(backend.examsCount, equals(1));

      final cached = await examCache.load('2026-2027-1');
      expect(cached, isNotNull);
      expect(cached!.items.length, equals(exams.length));
    });

    test('fetchGrades queries service and caches result', () async {
      expect(await gradesCache.load('2026-2027-1'), isNull);

      final grades = await academicService.fetchGrades('2026-2027-1');
      expect(grades, isNotEmpty);
      expect(backend.gradesCount, equals(1));

      final cached = await gradesCache.load('2026-2027-1');
      expect(cached, isNotNull);
      expect(cached!.items.length, equals(grades.length));
      expect(cached.isNotEvaluated, isFalse);
    });

    test(
      'fetchGrades records isNotEvaluated on notEvaluated AcademicError',
      () async {
        backend.gradesBehavior = (_, _) =>
            throw const AcademicError(ErrorCode.notEvaluated, '未评教');

        await expectLater(
          () => academicService.fetchGrades('2026-2027-1'),
          throwsA(isA<AcademicError>()),
        );

        final cached = await gradesCache.load('2026-2027-1');
        expect(cached, isNotNull);
        expect(cached!.isNotEvaluated, isTrue);
        expect(cached.items, isEmpty);
      },
    );

    test(
      'fetchGrades preserves existing cached items when notEvaluated occurs',
      () async {
        const existingGrade = GradeItem(
          courseName: '离散数学',
          credit: 3.0,
          gradePoint: 4.0,
          rawScore: '92',
        );
        await gradesCache.save('2026-2027-1', const [existingGrade]);

        backend.gradesBehavior = (_, _) =>
            throw const AcademicError(ErrorCode.notEvaluated, '未评教');

        await expectLater(
          () => academicService.fetchGrades('2026-2027-1'),
          throwsA(isA<AcademicError>()),
        );

        final cached = await gradesCache.load('2026-2027-1');
        expect(cached, isNotNull);
        expect(cached!.isNotEvaluated, isTrue);
        expect(cached.items, hasLength(1));
        expect(cached.items.first.courseName, equals('离散数学'));
      },
    );

    test(
      'syncCurrentTermAsync updates in background and invokes callback',
      () async {
        var callbackCalled = false;

        await academicService.syncCurrentTermAsync(
          termId: '2026-2027-1',
          onDataUpdated: () {
            callbackCalled = true;
          },
        );

        expect(callbackCalled, isTrue);
        expect(backend.examsCount, equals(1));
        expect(backend.gradesCount, equals(1));
      },
    );

    test('syncCurrentTermAsync handles backend failures gracefully and calls callback', () async {
      backend.examsBehavior = (_, _) =>
          throw const AcademicError(ErrorCode.networkRetryable, 'net err');
      backend.gradesBehavior = (_, _) =>
          throw const AcademicError(ErrorCode.networkRetryable, 'net err');

      var callbackCalled = false;
      await academicService.syncCurrentTermAsync(
        termId: '2026-2027-1',
        onDataUpdated: () {
          callbackCalled = true;
        },
      );

      expect(callbackCalled, isTrue);
    });

    test(
      'syncCurrentTermAsync with empty termId does not query backend',
      () async {
        var callbackCalled = false;
        await academicService.syncCurrentTermAsync(
          termId: '',
          onDataUpdated: () {
            callbackCalled = true;
          },
        );

        expect(callbackCalled, isFalse);
        expect(backend.examsCount, equals(0));
        expect(backend.gradesCount, equals(0));
      },
    );

    test('syncCurrentTermAsync handles session expired by auto relogin and updates cache', () async {
      final creds = scheduleService.credentials;
      await creds.save(
        '${scheduleService.baseUrl.toLowerCase()}|20240001',
        const Credentials('20240001', 'pw'),
      );
      scheduleService.accountHint = '20240001';

      var examsCall = 0;
      backend.examsBehavior = (call, termId) async {
        examsCall++;
        if (examsCall == 1) throw expired();
        return sampleExams();
      };
      var gradesCall = 0;
      backend.gradesBehavior = (call, termId) async {
        gradesCall++;
        if (gradesCall == 1) throw expired();
        return sampleGrades();
      };

      var callbackCalled = false;
      await academicService.syncCurrentTermAsync(
        termId: '2026-2027-1',
        onDataUpdated: () {
          callbackCalled = true;
        },
      );

      expect(callbackCalled, isTrue);
      expect(backend.loginCount, equals(1), reason: '并发查询失效合并为 1 次重登');
      expect(backend.examsCount, equals(2));
      expect(backend.gradesCount, equals(2));

      final cachedExams = await examCache.load('2026-2027-1');
      final cachedGrades = await gradesCache.load('2026-2027-1');
      expect(cachedExams?.items, isNotEmpty);
      expect(cachedGrades?.items, isNotEmpty);
    });
  });
}
