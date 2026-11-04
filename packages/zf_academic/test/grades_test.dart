import 'package:test/test.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/synthetic_zf.dart';

void main() {
  group('成绩数据清洗与模型 (jsonGrades & GradeItem)', () {
    test('完整解析成绩行各字段', () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{
          'kcmc': '高等数学A(1)',
          'kch': 'MATH101',
          'xf': '4.5',
          'jd': '4.0',
          'cj': '90',
          'bfzcj': '90.0',
          'kcxzmc': '必修',
          'kclbmc': '通识核心',
          'ksxz': '正常考试',
          'xnm': '2024',
          'xqm': '3',
        },
      ];
      final items = jsonGrades(rows);
      expect(items, hasLength(1));
      final grade = items.first;
      expect(grade.courseName, '高等数学A(1)');
      expect(grade.courseCode, 'MATH101');
      expect(grade.credit, 4.5);
      expect(grade.gradePoint, 4.0);
      expect(grade.rawScore, '90');
      expect(grade.numericScore, 90.0);
      expect(grade.courseNature, '必修');
      expect(grade.courseCategory, '通识核心');
      expect(grade.examNature, '正常考试');
      expect(grade.termId, '2024-2025-1');
    });

    test('过滤掉课程名为空的无效数据', () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{'kcmc': '', 'xf': '2.0'},
        <String, dynamic>{'kcmc': '大学体育', 'xf': '1.0', 'cj': '80'},
      ];
      final items = jsonGrades(rows);
      expect(items, hasLength(1));
      expect(items.first.courseName, '大学体育');
    });

    test('GradeItem JSON 往返序列化保真', () {
      const original = GradeItem(
        courseName: '软件工程',
        courseCode: 'CS301',
        credit: 3.0,
        gradePoint: 4.2,
        rawScore: '92',
        numericScore: 92.0,
        courseNature: '专业必修',
        courseCategory: '专业课',
        examNature: '正常考试',
        termId: '2024-2025-2',
      );
      final json = original.toJson();
      final restored = GradeItem.fromJson(json);
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
      expect(restored.toString(), contains('软件工程'));
    });
  });

  group('客户端网络查询 (fetchGrades)', () {
    test('登录后成功拉取成绩并验证 showCount=500 参数', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));

        final grades = await client.fetchGrades('2026-2027-1');
        expect(grades, hasLength(2));
        expect(grades[0].courseName, '高等数学A(1)');
        expect(grades[0].gradePoint, 4.0);
        expect(grades[1].courseName, '大学英语(1)');

        // 核对请求参数带 showCount=500
        final req = server.requests.lastWhere(
          (r) => r.path.endsWith('/cjcx/cjcx_cxDgXscj.html'),
        );
        expect(req.form['queryModel.showCount'], '500');
        expect(req.form['xnm'], '2026');
        expect(req.form['xqm'], '3');
        client.dispose();
      });
    });

    test('遇到教务未评教拦截抛出 notEvaluated 错误', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));

        await expectLater(
          client.fetchGrades('2026-2027-1'),
          throwsA(
            isA<AcademicError>().having(
              (e) => e.code,
              'code',
              ErrorCode.notEvaluated,
            ),
          ),
        );
        client.dispose();
      },
          const SyntheticZfOptions(
            gradesBody: '{"message": "请先完成本学期教学质量评价后再查询成绩", "flag": "-1"}',
          ));
    });

    test('课程名称包含"教学质量评价"关键词但返回了成绩列表时正常出分不被误拦截', () async {
      const bodyWithEvaluationCourse = '''
      {
        "items": [
          {
            "kcmc": "教育学前沿：教学质量评价与监控专题",
            "kch": "EDU501",
            "xf": "2.0",
            "jd": "4.5",
            "cj": "95",
            "bfzcj": "95.0",
            "kcxzmc": "选修",
            "kclbmc": "专业选修",
            "ksxz": "正常考试",
            "xnm": "2026",
            "xqm": "3"
          }
        ]
      }
      ''';
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));

        final grades = await client.fetchGrades('2026-2027-1');
        expect(grades, hasLength(1));
        expect(grades.first.courseName, '教育学前沿：教学质量评价与监控专题');
        expect(grades.first.numericScore, 95.0);
        client.dispose();
      }, const SyntheticZfOptions(gradesBody: bodyWithEvaluationCourse));
    });

    test('未登录时拉取成绩抛出 SESSION_EXPIRED', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await expectLater(
          client.fetchGrades('2026-2027-1'),
          throwsA(
            isA<AcademicError>().having(
              (e) => e.code,
              'code',
              ErrorCode.sessionExpired,
            ),
          ),
        );
        client.dispose();
      });
    });
  });
}
