import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/term_selector_helper.dart';
import 'package:zf_academic/zf_academic.dart';

void main() {
  group('parseEnrollmentYear', () {
    final refDate = DateTime(2025, 9, 1);

    test('解析青科大真实10位学号 (如 2407720102 -> 2024)', () {
      expect(parseEnrollmentYear('2407720102', now: refDate), 2024);
      expect(parseEnrollmentYear('2307720102', now: refDate), 2023);
      expect(parseEnrollmentYear('2107720102', now: refDate), 2021);
      expect(parseEnrollmentYear('2501010101', now: refDate), 2025);
    });

    test('解析4位年份前缀学号 (如 20240001 -> 2024, 20260001 -> 2026)', () {
      expect(parseEnrollmentYear('20240001', now: refDate), 2024);
      expect(parseEnrollmentYear('20230001', now: refDate), 2023);
      expect(parseEnrollmentYear('20260001', now: DateTime(2026, 9, 1)), 2026);
      expect(parseEnrollmentYear('20221234', now: refDate), 2022);
      expect(parseEnrollmentYear('202400000001', now: refDate), 2024);
    });

    test('解析青科大标准10位学号 (YY+CC+MM+NN+SS，前2位严格为入学年)', () {
      expect(parseEnrollmentYear('2007720102', now: refDate), 2020);
      expect(
        parseEnrollmentYear('2007720102', now: DateTime(2021, 9, 1)),
        2020,
      );
      // 2020级 21学院学生：此前曾因 mid2 >= 21 被误判为 2021 级，现严格解析为 2020 级
      expect(parseEnrollmentYear('2021010101', now: refDate), 2020);
      expect(parseEnrollmentYear('2015010101', now: refDate), 2020);
      expect(parseEnrollmentYear('2020000001', now: refDate), 2020);
      expect(parseEnrollmentYear('2407720102', now: refDate), 2024);
    });

    test('纯年份字符 (2024 -> 2024, 24 -> 2024)', () {
      expect(parseEnrollmentYear('2024', now: refDate), 2024);
      expect(parseEnrollmentYear('24', now: refDate), 2024);
    });

    test('空或无效学号返回 null 优雅回退', () {
      expect(parseEnrollmentYear(null, now: refDate), isNull);
      expect(parseEnrollmentYear('', now: refDate), isNull);
      expect(parseEnrollmentYear('   ', now: refDate), isNull);
      expect(parseEnrollmentYear('guest', now: refDate), isNull);
      expect(parseEnrollmentYear('1', now: refDate), isNull);
    });

    test('超出在校合理年限的异常值返回 null', () {
      expect(parseEnrollmentYear('20050001', now: refDate), isNull);
      expect(parseEnrollmentYear('20991234', now: refDate), isNull);
      expect(parseEnrollmentYear('00001234', now: refDate), isNull);
      expect(parseEnrollmentYear('99991234', now: refDate), isNull);
    });
  });

  group('estimateCurrentAcademicYear', () {
    test('根据自然日历推断学年', () {
      // 9月开学进入新学年
      expect(estimateCurrentAcademicYear(now: DateTime(2024, 9, 15)), 2024);
      // 次年1月仍属于上一年的秋季学期
      expect(estimateCurrentAcademicYear(now: DateTime(2025, 1, 10)), 2024);
      // 次年4月属于上一年的春季学期
      expect(estimateCurrentAcademicYear(now: DateTime(2025, 4, 15)), 2024);
    });

    test('已选学期或服务端当前学期更大时提升当前学年', () {
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

    test('过滤早于入学年份的历史学期，且将未来学期限制在当前学年以内', () {
      // 2024级学生，当前处于2025学年
      final filtered = filterTerms(
        terms: terms,
        enrollmentYear: 2024,
        currentAcademicYear: 2025,
      );

      final ids = filtered.map((t) => t.id).toList();
      // 2026-2027-1 (超前) 和 2023-2024 / 2022-2023 (入学前) 必须被过滤
      expect(ids, <String>[
        '2025-2026-2',
        '2025-2026-1',
        '2024-2025-2',
        '2024-2025-1',
      ]);
    });

    test('当前选中学期始终被保留，即使早于入学年份', () {
      final filtered = filterTerms(
        terms: terms,
        enrollmentYear: 2024,
        currentAcademicYear: 2025,
        currentTermId: '2023-2024-2',
      );
      final ids = filtered.map((t) => t.id).toList();
      expect(ids, contains('2023-2024-2'));
    });

    test('无法解析学号时不过滤历史学期，但限制未来学期', () {
      final filtered = filterTerms(
        terms: terms,
        enrollmentYear: null,
        currentAcademicYear: 2025,
      );
      final ids = filtered.map((t) => t.id).toList();
      expect(ids, contains('2022-2023-1'));
      expect(ids, contains('2023-2024-2'));
      expect(ids, isNot(contains('2026-2027-1')));
    });

    test('原始 terms 为空时根据在校区间自动推导', () {
      final filtered = filterTerms(
        terms: const <Term>[],
        enrollmentYear: 2024,
        currentAcademicYear: 2025,
      );
      final ids = filtered.map((t) => t.id).toList();
      expect(ids, <String>[
        '2025-2026-2',
        '2025-2026-1',
        '2024-2025-2',
        '2024-2025-1',
      ]);
    });

    test('未显式传入 currentAcademicYear 时通过 now 自然过滤未来学期 (秋季第1学期截断第2学期)', () {
      final filtered = filterTerms(
        terms: terms,
        enrollmentYear: 2024,
        now: DateTime(2024, 10, 1),
      );
      final ids = filtered.map((t) => t.id).toList();
      // 2024年10月为2024-2025秋季学期（第1学期），未来学年以及当年的第2学期均被过滤
      expect(ids, <String>['2024-2025-1']);
    });

    test('春季第2学期时展示当年第1与第2学期', () {
      final filtered = filterTerms(
        terms: terms,
        enrollmentYear: 2024,
        now: DateTime(2025, 3, 1),
      );
      final ids = filtered.map((t) => t.id).toList();
      expect(ids, <String>['2024-2025-2', '2024-2025-1']);
    });

    test('基于 serverCurrentTermId 精确截断未来学期 (如当前为大三上 2026-2027-1 时不显示大三下 2026-2027-2)', () {
      final termsWithJuniorSpring = <Term>[
        const Term(
          id: '2026-2027-2',
          name: '2026-2027 第2学期',
          year: 2026,
          semester: 2,
        ),
        ...terms,
      ];
      final filtered = filterTerms(
        terms: termsWithJuniorSpring,
        enrollmentYear: 2024,
        serverCurrentTermId: '2026-2027-1',
      );
      final ids = filtered.map((t) => t.id).toList();
      expect(ids, isNot(contains('2026-2027-2')));
      expect(ids, contains('2026-2027-1'));
      expect(ids, contains('2025-2026-2'));
      expect(ids, contains('2025-2026-1'));
      expect(ids, contains('2024-2025-2'));
      expect(ids, contains('2024-2025-1'));
    });

    test('原始 terms 为空且当前为第1学期时，不推导当前学年第2学期', () {
      final filtered = filterTerms(
        terms: const <Term>[],
        enrollmentYear: 2024,
        serverCurrentTermId: '2025-2026-1',
      );
      final ids = filtered.map((t) => t.id).toList();
      expect(ids, isNot(contains('2025-2026-2')));
      expect(ids, <String>['2025-2026-1', '2024-2025-2', '2024-2025-1']);
    });

    test('原始 terms 为空且传入了当前选中学期时，确保该学期被保留', () {
      final filtered = filterTerms(
        terms: const <Term>[],
        enrollmentYear: 2024,
        serverCurrentTermId: '2025-2026-1',
        currentTermId: '2023-2024-2',
      );
      final ids = filtered.map((t) => t.id).toList();
      expect(ids, contains('2023-2024-2'));
      expect(ids, contains('2025-2026-1'));
    });

    test('currentSemester 显式指定时按学期截断', () {
      final filtered = filterTerms(
        terms: terms,
        enrollmentYear: 2024,
        currentAcademicYear: 2025,
        currentSemester: 1,
      );
      final ids = filtered.map((t) => t.id).toList();
      expect(ids, <String>['2025-2026-1', '2024-2025-2', '2024-2025-1']);
    });
  });

  group('formatTermPrimaryLabel', () {
    const enrollment = 2024;

    test('Year 0: 大一 上学期 与 大一 下学期', () {
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2024-2025-1',
            name: '',
            year: 2024,
            semester: 1,
          ),
          enrollmentYear: enrollment,
        ),
        '大一 上学期',
      );
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2024-2025-2',
            name: '',
            year: 2024,
            semester: 2,
          ),
          enrollmentYear: enrollment,
        ),
        '大一 下学期',
      );
    });

    test('Year 1: 大二 上学期 与 大二 下学期', () {
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2025-2026-1',
            name: '',
            year: 2025,
            semester: 1,
          ),
          enrollmentYear: enrollment,
        ),
        '大二 上学期',
      );
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2025-2026-2',
            name: '',
            year: 2025,
            semester: 2,
          ),
          enrollmentYear: enrollment,
        ),
        '大二 下学期',
      );
    });

    test('Year 2: 大三 上学期 与 大三 下学期', () {
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2026-2027-1',
            name: '',
            year: 2026,
            semester: 1,
          ),
          enrollmentYear: enrollment,
        ),
        '大三 上学期',
      );
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2026-2027-2',
            name: '',
            year: 2026,
            semester: 2,
          ),
          enrollmentYear: enrollment,
        ),
        '大三 下学期',
      );
    });

    test('Year 3: 大四 上学期 与 大四 下学期', () {
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2027-2028-1',
            name: '',
            year: 2027,
            semester: 1,
          ),
          enrollmentYear: enrollment,
        ),
        '大四 上学期',
      );
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2027-2028-2',
            name: '',
            year: 2027,
            semester: 2,
          ),
          enrollmentYear: enrollment,
        ),
        '大四 下学期',
      );
    });

    test('Year 4: 大五 上学期 与 大五 下学期 (支持五年制专业)', () {
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2028-2029-1',
            name: '',
            year: 2028,
            semester: 1,
          ),
          enrollmentYear: enrollment,
        ),
        '大五 上学期',
      );
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2028-2029-2',
            name: '',
            year: 2028,
            semester: 2,
          ),
          enrollmentYear: enrollment,
        ),
        '大五 下学期',
      );
    });

    test('Beyond Year 4 (大五以后) 回退至学年学期名称', () {
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
    });

    test('无入学年份时回退至学年学期名', () {
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

    test('支持小学期 (第3学期)', () {
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2024-2025-3',
            name: '',
            year: 2024,
            semester: 3,
          ),
          enrollmentYear: enrollment,
        ),
        '大一 第3学期',
      );
    });

    test('支持从 studentId 字符串直接换算', () {
      expect(
        formatTermPrimaryLabel(
          term: const Term(
            id: '2024-2025-1',
            name: '',
            year: 2024,
            semester: 1,
          ),
          studentId: '2407720102',
          now: DateTime(2025, 9, 1),
        ),
        '大一 上学期',
      );
    });

    test('formatTermPrimaryLabel 支持正方 xqm 映射 (1/3 -> 上学期, 2/12 -> 下学期, 16 -> 第3学期)', () {
      final t = const Term(id: '2024-2025-1', name: '');
      expect(
        formatTermPrimaryLabel(term: t, enrollmentYear: enrollment, xqm: '3'),
        '大一 上学期',
      );
      expect(
        formatTermPrimaryLabel(term: t, enrollmentYear: enrollment, xqm: '1'),
        '大一 上学期',
      );
      expect(
        formatTermPrimaryLabel(term: t, enrollmentYear: enrollment, xqm: '12'),
        '大一 下学期',
      );
      expect(
        formatTermPrimaryLabel(term: t, enrollmentYear: enrollment, xqm: '2'),
        '大一 下学期',
      );
      expect(
        formatTermPrimaryLabel(term: t, enrollmentYear: enrollment, xqm: '16'),
        '大一 第3学期',
      );
    });

    test('formatTermPrimaryLabelById 快捷转换 (含 2024-2025-12)', () {
      expect(
        formatTermPrimaryLabelById(
          termId: '2024-2025-1',
          studentId: '2407720102',
          now: DateTime(2025, 9, 1),
        ),
        '大一 上学期',
      );
      expect(
        formatTermPrimaryLabelById(
          termId: '2024-2025-12',
          studentId: '2407720102',
          now: DateTime(2025, 9, 1),
        ),
        '大一 下学期',
      );
    });
  });
}
