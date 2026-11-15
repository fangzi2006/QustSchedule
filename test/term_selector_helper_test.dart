import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/term_selector_helper.dart';
import 'package:zf_academic/zf_academic.dart';

void main() {
  group('parseEnrollmentYear', () {
    final refDate = DateTime(2025, 9, 1);

    test('解析青科大 10 位学号、4 位年份前缀与纯年份字符', () {
      // 青科大 10 位学号（YY+CC+MM+NN+SS，前 2 位严格为入学年）
      expect(parseEnrollmentYear('2412345678', now: refDate), 2024);
      expect(parseEnrollmentYear('2312345678', now: refDate), 2023);
      expect(parseEnrollmentYear('2112345678', now: refDate), 2021);
      expect(parseEnrollmentYear('2501010101', now: refDate), 2025);
      expect(parseEnrollmentYear('2012345678', now: refDate), 2020);
      expect(
        parseEnrollmentYear('2012345678', now: DateTime(2021, 9, 1)),
        2020,
      );
      // 2020级 21学院学生：此前曾因 mid2 >= 21 被误判为 2021 级，现严格解析为 2020 级
      expect(parseEnrollmentYear('2021010101', now: refDate), 2020);
      expect(parseEnrollmentYear('2015010101', now: refDate), 2020);
      expect(parseEnrollmentYear('2020000001', now: refDate), 2020);

      // 4 位年份前缀学号
      expect(parseEnrollmentYear('20240001', now: refDate), 2024);
      expect(parseEnrollmentYear('20230001', now: refDate), 2023);
      expect(parseEnrollmentYear('20260001', now: DateTime(2026, 9, 1)), 2026);
      expect(parseEnrollmentYear('20221234', now: refDate), 2022);
      expect(parseEnrollmentYear('202400000001', now: refDate), 2024);

      // 纯年份字符
      expect(parseEnrollmentYear('2024', now: refDate), 2024);
      expect(parseEnrollmentYear('24', now: refDate), 2024);
    });

    test('空值、无效格式与超出在校合理年限返回 null', () {
      for (final raw in [
        null,
        '',
        '   ',
        'guest',
        '1',
        '20050001',
        '20991234',
        '00001234',
        '99991234',
      ]) {
        expect(parseEnrollmentYear(raw, now: refDate), isNull, reason: '$raw');
      }
    });
  });

  group('estimateCurrentAcademicYear', () {
    test('根据自然日历推断学年，并被已选/服务端当前学期提升', () {
      expect(estimateCurrentAcademicYear(now: DateTime(2024, 9, 15)), 2024);
      expect(estimateCurrentAcademicYear(now: DateTime(2025, 1, 10)), 2024);
      expect(estimateCurrentAcademicYear(now: DateTime(2025, 4, 15)), 2024);

      expect(
        estimateCurrentAcademicYear(
          now: DateTime(2024, 5, 1),
          activeTermId: '2025-2026-1',
        ),
        2025,
      );
      expect(
        estimateCurrentAcademicYear(
          now: DateTime(2024, 5, 1),
          serverCurrentTermId: '2026-2027-2',
        ),
        2026,
      );
    });
  });

  group('filterTerms', () {
    final terms = <Term>[
      const Term(
        id: '2026-2027-1',
        name: '2026-2027 第1学期',
        year: 2026,
        semester: 1,
      ),
      const Term(
        id: '2025-2026-2',
        name: '2025-2026 第2学期',
        year: 2025,
        semester: 2,
      ),
      const Term(
        id: '2025-2026-1',
        name: '2025-2026 第1学期',
        year: 2025,
        semester: 1,
      ),
      const Term(
        id: '2024-2025-2',
        name: '2024-2025 第2学期',
        year: 2024,
        semester: 2,
      ),
      const Term(
        id: '2024-2025-1',
        name: '2024-2025 第1学期',
        year: 2024,
        semester: 1,
      ),
      const Term(
        id: '2023-2024-2',
        name: '2023-2024 第2学期',
        year: 2023,
        semester: 2,
      ),
      const Term(
        id: '2022-2023-1',
        name: '2022-2023 第1学期',
        year: 2022,
        semester: 1,
      ),
    ];

    test('按入学年份与当前学年过滤，缺失入学年份与空列表兜底', () {
      // 2024 级学生，当前 2025 学年：过滤入学前与超前学期
      expect(
        filterTerms(
          terms: terms,
          enrollmentYear: 2024,
          currentAcademicYear: 2025,
        ).map((t) => t.id),
        ['2025-2026-2', '2025-2026-1', '2024-2025-2', '2024-2025-1'],
      );

      // 无法解析学号时保留历史学期但仍限制未来学年
      final noEnrollmentIds = filterTerms(
        terms: terms,
        enrollmentYear: null,
        currentAcademicYear: 2025,
      ).map((t) => t.id).toList();
      expect(noEnrollmentIds, containsAll(['2022-2023-1', '2023-2024-2']));
      expect(noEnrollmentIds, isNot(contains('2026-2027-1')));

      // 原始 terms 为空时根据在校区间自动推导
      expect(
        filterTerms(
          terms: const <Term>[],
          enrollmentYear: 2024,
          currentAcademicYear: 2025,
        ).map((t) => t.id),
        ['2025-2026-2', '2025-2026-1', '2024-2025-2', '2024-2025-1'],
      );
    });

    test('按 now、serverCurrentTermId 与 currentSemester 精确截断未来学期', () {
      // 秋季第1学期截断当年第2学期
      expect(
        filterTerms(
          terms: terms,
          enrollmentYear: 2024,
          now: DateTime(2024, 10, 1),
        ).map((t) => t.id),
        ['2024-2025-1'],
      );
      // 春季第2学期展示当年第1与第2学期
      expect(
        filterTerms(
          terms: terms,
          enrollmentYear: 2024,
          now: DateTime(2025, 3, 1),
        ).map((t) => t.id),
        ['2024-2025-2', '2024-2025-1'],
      );

      // serverCurrentTermId 精确截断（大三上 2026-2027-1 时不显示 2026-2027-2）
      final withJuniorSpring = <Term>[
        const Term(
          id: '2026-2027-2',
          name: '2026-2027 第2学期',
          year: 2026,
          semester: 2,
        ),
        ...terms,
      ];
      final juniorIds = filterTerms(
        terms: withJuniorSpring,
        enrollmentYear: 2024,
        serverCurrentTermId: '2026-2027-1',
      ).map((t) => t.id).toList();
      expect(juniorIds, isNot(contains('2026-2027-2')));
      expect(
        juniorIds,
        containsAll([
          '2026-2027-1',
          '2025-2026-2',
          '2025-2026-1',
          '2024-2025-2',
          '2024-2025-1',
        ]),
      );

      // 原始 terms 为空且当前为第1学期时不推导当年第2学期
      expect(
        filterTerms(
          terms: const <Term>[],
          enrollmentYear: 2024,
          serverCurrentTermId: '2025-2026-1',
        ).map((t) => t.id),
        ['2025-2026-1', '2024-2025-2', '2024-2025-1'],
      );

      // 显式 currentSemester 截断
      expect(
        filterTerms(
          terms: terms,
          enrollmentYear: 2024,
          currentAcademicYear: 2025,
          currentSemester: 1,
        ).map((t) => t.id),
        ['2025-2026-1', '2024-2025-2', '2024-2025-1'],
      );
    });

    test('两学期制自动过滤第 3 学期（小学期），但始终保留当前选中学期', () {
      final withShortSemester = <Term>[
        const Term(
          id: '2024-2025-3',
          name: '2024-2025 第3学期',
          year: 2024,
          semester: 3,
        ),
        const Term(
          id: '2023-2024-3',
          name: '2023-2024 第3学期',
          year: 2023,
          semester: 3,
        ),
        ...terms,
      ];
      expect(
        filterTerms(
          terms: withShortSemester,
          enrollmentYear: 2024,
          currentAcademicYear: 2025,
        ).map((t) => t.id),
        ['2025-2026-2', '2025-2026-1', '2024-2025-2', '2024-2025-1'],
      );

      // 早于入学年份的当前选中学期
      expect(
        filterTerms(
          terms: terms,
          enrollmentYear: 2024,
          currentAcademicYear: 2025,
          currentTermId: '2023-2024-2',
        ).map((t) => t.id),
        contains('2023-2024-2'),
      );

      // 空 terms 且传入当前选中学期
      expect(
        filterTerms(
          terms: const <Term>[],
          enrollmentYear: 2024,
          serverCurrentTermId: '2025-2026-1',
          currentTermId: '2023-2024-2',
        ).map((t) => t.id),
        containsAll(['2023-2024-2', '2025-2026-1']),
      );

      // 第 3 学期作为当前选中学期时的防御性保留
      expect(
        filterTerms(
          terms: withShortSemester,
          enrollmentYear: 2024,
          currentAcademicYear: 2025,
          currentTermId: '2024-2025-3',
        ).map((t) => t.id),
        contains('2024-2025-3'),
      );
    });
  });

  group('formatTermPrimaryLabel', () {
    const enrollment = 2024;

    test('大一至大五上下学期与小学期名称映射', () {
      final cases = <(int, int, String)>[
        (2024, 1, '大一 上学期'),
        (2024, 2, '大一 下学期'),
        (2024, 3, '大一 第3学期'),
        (2025, 1, '大二 上学期'),
        (2025, 2, '大二 下学期'),
        (2026, 1, '大三 上学期'),
        (2026, 2, '大三 下学期'),
        (2027, 1, '大四 上学期'),
        (2027, 2, '大四 下学期'),
        (2028, 1, '大五 上学期'),
        (2028, 2, '大五 下学期'),
      ];
      for (final (year, semester, expected) in cases) {
        expect(
          formatTermPrimaryLabel(
            term: Term(
              id: '$year-${year + 1}-$semester',
              name: '',
              year: year,
              semester: semester,
            ),
            enrollmentYear: enrollment,
          ),
          expected,
        );
      }
    });

    test('超出大五或无入学年份回退至学年学期名', () {
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2029-2030-1',
            name: '',
            year: 2029,
            semester: 1,
          ),
          enrollmentYear: enrollment,
        ),
        '2029-2030 第1学期',
      );
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2030-2031-2',
            name: '',
            year: 2030,
            semester: 2,
          ),
          enrollmentYear: enrollment,
        ),
        '2030-2031 第2学期',
      );
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2024-2025-1',
            name: '',
            year: 2024,
            semester: 1,
          ),
          enrollmentYear: null,
        ),
        '2024-2025 第1学期',
      );
    });

    test('支持 studentId、xqm 映射与 formatTermPrimaryLabelById', () {
      const baseTerm = Term(
        id: '2024-2025-1',
        name: '',
        year: 2024,
        semester: 1,
      );
      expect(
        formatTermPrimaryLabel(
          term: baseTerm,
          studentId: '2412345678',
          now: DateTime(2025, 9, 1),
        ),
        '大一 上学期',
      );

      for (final (xqm, expected) in [
        ('3', '大一 上学期'),
        ('1', '大一 上学期'),
        ('12', '大一 下学期'),
        ('2', '大一 下学期'),
        ('16', '大一 第3学期'),
      ]) {
        expect(
          formatTermPrimaryLabel(
            term: const Term(id: '2024-2025-1', name: ''),
            enrollmentYear: enrollment,
            xqm: xqm,
          ),
          expected,
        );
      }

      expect(
        formatTermPrimaryLabelById(
          termId: '2024-2025-1',
          studentId: '2412345678',
          now: DateTime(2025, 9, 1),
        ),
        '大一 上学期',
      );
      expect(
        formatTermPrimaryLabelById(
          termId: '2024-2025-12',
          studentId: '2412345678',
          now: DateTime(2025, 9, 1),
        ),
        '大一 下学期',
      );
    });
  });
}
