import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/academic_cache.dart';
import 'package:zf_academic/zf_academic.dart';

void main() {
  group('CachedTermExams serialization', () {
    test('toJson and fromJson preserves data', () {
      final exam = ExamItem(
        courseName: '高等数学A',
        rawTimeStr: '2026-06-20 09:00-11:00',
        campus: '四方校区',
        classroom: '一教201',
        seatNumber: '25',
        examForm: '闭卷',
        startTime: DateTime(2026, 6, 20, 9, 0),
        endTime: DateTime(2026, 6, 20, 11, 0),
      );
      final cache = CachedTermExams(
        termId: '2025-2026-2',
        items: [exam],
        fetchedAt: DateTime(2026, 6, 1, 12, 0),
      );

      final json = cache.toJson();
      final decoded = CachedTermExams.fromJson(json);

      expect(decoded.termId, equals('2025-2026-2'));
      expect(decoded.fetchedAt, equals(DateTime(2026, 6, 1, 12, 0)));
      expect(decoded.items.length, equals(1));
      expect(decoded.items.first.courseName, equals('高等数学A'));
      expect(decoded.items.first.campus, equals('四方校区'));
      expect(decoded.items.first.classroom, equals('一教201'));
      expect(decoded.items.first.seatNumber, equals('25'));
      expect(
        decoded.items.first.startTime,
        equals(DateTime(2026, 6, 20, 9, 0)),
      );
    });

    test('fromJson handles empty or malformed fields gracefully', () {
      final decoded = CachedTermExams.fromJson(<String, dynamic>{});
      expect(decoded.termId, isEmpty);
      expect(decoded.items, isEmpty);
      expect(decoded.fetchedAt, equals(DateTime.fromMillisecondsSinceEpoch(0)));
    });
  });

  group('CachedTermGrades serialization', () {
    test('toJson and fromJson preserves data including isNotEvaluated', () {
      final grade = const GradeItem(
        courseName: '大学物理B',
        rawScore: '88',
        numericScore: 88.0,
        credit: 3.5,
        gradePoint: 3.8,
        courseNature: '必修',
        examNature: '正常考试',
      );
      final cache = CachedTermGrades(
        termId: '2025-2026-1',
        items: [grade],
        fetchedAt: DateTime(2026, 1, 15, 8, 30),
        isNotEvaluated: true,
      );

      final json = cache.toJson();
      final decoded = CachedTermGrades.fromJson(json);

      expect(decoded.termId, equals('2025-2026-1'));
      expect(decoded.isNotEvaluated, isTrue);
      expect(decoded.items.length, equals(1));
      expect(decoded.items.first.courseName, equals('大学物理B'));
      expect(decoded.items.first.credit, equals(3.5));
      expect(decoded.items.first.gradePoint, equals(3.8));
    });
  });

  group('InMemoryExamCache and InMemoryGradesCache', () {
    test('ExamCache read / write / clear operations', () async {
      final cache = InMemoryExamCache();
      expect(await cache.load('2025-2026-1'), isNull);

      final items = [
        const ExamItem(
          courseName: '线性代数',
          rawTimeStr: '2026-01-10 14:00-16:00',
        ),
      ];
      await cache.save('2025-2026-1', items);

      final loaded = await cache.load('2025-2026-1');
      expect(loaded, isNotNull);
      expect(loaded!.items.length, equals(1));
      expect(loaded.items.first.courseName, equals('线性代数'));

      final all = await cache.loadAll();
      expect(all.length, equals(1));

      await cache.clear();
      expect(await cache.load('2025-2026-1'), isNull);
    });

    test('GradesCache read / write / clear operations', () async {
      final cache = InMemoryGradesCache();
      expect(await cache.load('2025-2026-1'), isNull);

      final items = [
        const GradeItem(
          courseName: 'C语言程序设计',
          rawScore: '92',
          credit: 3.0,
          gradePoint: 4.0,
        ),
      ];
      await cache.save('2025-2026-1', items, isNotEvaluated: false);

      final loaded = await cache.load('2025-2026-1');
      expect(loaded, isNotNull);
      expect(loaded!.items.length, equals(1));
      expect(loaded.items.first.courseName, equals('C语言程序设计'));
      expect(loaded.isNotEvaluated, isFalse);

      await cache.clear();
      expect(await cache.load('2025-2026-1'), isNull);
    });
  });

  group('FileExamCache and FileGradesCache', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('zf_academic_cache_test_');
    });

    tearDown(() {
      try {
        tempDir.deleteSync(recursive: true);
      } catch (_) {}
    });

    test('FileExamCache persists to disk and recovers', () async {
      final file = File('${tempDir.path}/exam_cache.json');
      final cache = FileExamCache.fromFile(file);

      expect(await cache.load('2025-2026-2'), isNull);

      await cache.save('2025-2026-2', [
        const ExamItem(
          courseName: '数据结构',
          rawTimeStr: '2026-06-18 09:00-11:00',
        ),
      ]);

      expect(file.existsSync(), isTrue);

      final reloadedCache = FileExamCache.fromFile(file);
      final loaded = await reloadedCache.load('2025-2026-2');
      expect(loaded, isNotNull);
      expect(loaded!.items.first.courseName, equals('数据结构'));

      await reloadedCache.clear();
      expect(file.existsSync(), isFalse);
    });

    test('FileExamCache handles corrupted json gracefully', () async {
      final file = File('${tempDir.path}/corrupt_exam_cache.json');
      file.writeAsStringSync('{ this is not json ...');
      final cache = FileExamCache.fromFile(file);

      final loaded = await cache.load('any');
      expect(loaded, isNull);
      final all = await cache.loadAll();
      expect(all, isEmpty);
    });

    test('FileGradesCache persists to disk and recovers', () async {
      final file = File('${tempDir.path}/grades_cache.json');
      final cache = FileGradesCache.fromFile(file);

      await cache.save('2025-2026-1', [
        const GradeItem(
          courseName: '大学英语',
          rawScore: '85',
          credit: 4.0,
          gradePoint: 3.5,
        ),
      ], isNotEvaluated: true);

      final reloadedCache = FileGradesCache.fromFile(file);
      final loaded = await reloadedCache.load('2025-2026-1');
      expect(loaded, isNotNull);
      expect(loaded!.isNotEvaluated, isTrue);
      expect(loaded.items.first.courseName, equals('大学英语'));
    });

    test('并发保存多个学期的考试与成绩缓存时不互相覆盖', () async {
      final examFile = File('${tempDir.path}/concurrent_exams.json');
      final gradesFile = File('${tempDir.path}/concurrent_grades.json');
      final examCache = FileExamCache.fromFile(examFile);
      final gradesCache = FileGradesCache.fromFile(gradesFile);

      await Future.wait(<Future<void>>[
        examCache.save('2025-2026-1', const [ExamItem(courseName: '大一高数')]),
        examCache.save('2025-2026-2', const [ExamItem(courseName: '大一物理')]),
        examCache.save('2026-2027-1', const [ExamItem(courseName: '大二离散')]),
        gradesCache.save('2025-2026-1', const [
          GradeItem(courseName: '大一高数', rawScore: '91', credit: 4.0),
        ]),
        gradesCache.save('2025-2026-2', const [
          GradeItem(courseName: '大一物理', rawScore: '88', credit: 3.5),
        ]),
      ]);

      expect(
        (await examCache.load('2025-2026-1'))?.items.single.courseName,
        '大一高数',
      );
      expect(
        (await examCache.load('2025-2026-2'))?.items.single.courseName,
        '大一物理',
      );
      expect(
        (await examCache.load('2026-2027-1'))?.items.single.courseName,
        '大二离散',
      );
      expect(
        (await gradesCache.load('2025-2026-1'))?.items.single.courseName,
        '大一高数',
      );
      expect(
        (await gradesCache.load('2025-2026-2'))?.items.single.courseName,
        '大一物理',
      );
    });
  });

  group('LateExamCache and LateGradesCache', () {
    test('placeholders return null/empty and do not throw', () async {
      final examCache = LateExamCache();
      expect(await examCache.load('any'), isNull);
      expect(await examCache.loadAll(), isEmpty);
      await examCache.save('any', const []);
      await examCache.clear();

      final gradesCache = LateGradesCache();
      expect(await gradesCache.load('any'), isNull);
      expect(await gradesCache.loadAll(), isEmpty);
      await gradesCache.save('any', const []);
      await gradesCache.clear();
    });
  });
}
