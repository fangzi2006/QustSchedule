import 'package:test/test.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/synthetic_zf.dart';

void main() {
  group('考试时间解析 (parseExamTime)', () {
    test('标准连字符格式 2025-01-08 08:30-10:30', () {
      final parsed = parseExamTime('2025-01-08 08:30-10:30');
      expect(parsed.startTime, DateTime(2025, 1, 8, 8, 30));
      expect(parsed.endTime, DateTime(2025, 1, 8, 10, 30));
    });

    test('括号波浪线格式 2025-01-08(08:30~10:30)', () {
      final parsed = parseExamTime('2025-01-08(08:30~10:30)');
      expect(parsed.startTime, DateTime(2025, 1, 8, 8, 30));
      expect(parsed.endTime, DateTime(2025, 1, 8, 10, 30));
    });

    test('中文年月日与「至」连接 2025年06月15日 14:00至16:00', () {
      final parsed = parseExamTime('2025年06月15日 14:00至16:00');
      expect(parsed.startTime, DateTime(2025, 6, 15, 14, 0));
      expect(parsed.endTime, DateTime(2025, 6, 15, 16, 0));
    });

    test('斜杠日期与带秒时间 2025/02/10 09:00:00-11:00:00', () {
      final parsed = parseExamTime('2025/02/10 09:00:00-11:00:00');
      expect(parsed.startTime, DateTime(2025, 2, 10, 9, 0));
      expect(parsed.endTime, DateTime(2025, 2, 10, 11, 0));
    });

    test('单点时间 2025-03-01 10:00', () {
      final parsed = parseExamTime('2025-03-01 10:00');
      expect(parsed.startTime, DateTime(2025, 3, 1, 10, 0));
      expect(parsed.endTime, isNull);
    });

    test('仅日期 2025-03-01', () {
      final parsed = parseExamTime('2025-03-01');
      expect(parsed.startTime, DateTime(2025, 3, 1));
      expect(parsed.endTime, isNull);
    });

    test('无效或待定文本返回 null', () {
      expect(parseExamTime('').startTime, isNull);
      expect(parseExamTime('待定').startTime, isNull);
      expect(parseExamTime('时间未定').endTime, isNull);
    });
  });

  group('考试数据清洗与序列化 (jsonExams & ExamItem)', () {
    test('完整解析考试行字段', () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{
          'kcmc': '大学物理B',
          'ksmc': '2024-2025-1期末考试',
          'kssj': '2025-01-08 08:30-10:30',
          'xqmc': '崂山校区',
          'cdmc': '弘毅楼 201',
          'zwh': '32',
          'ksfs': '闭卷',
          'kszt': '正常',
        },
      ];
      final items = jsonExams(rows);
      expect(items, hasLength(1));
      final exam = items.first;
      expect(exam.courseName, '大学物理B');
      expect(exam.examType, '2024-2025-1期末考试');
      expect(exam.campus, '崂山校区');
      expect(exam.classroom, '弘毅楼 201');
      expect(exam.seatNumber, '32');
      expect(exam.examForm, '闭卷');
      expect(exam.status, '正常');
      expect(exam.startTime, DateTime(2025, 1, 8, 8, 30));
      expect(exam.endTime, DateTime(2025, 1, 8, 10, 30));
    });

    test('过滤掉课程名为空的脏数据', () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{'kcmc': '', 'cdmc': '教室'},
        <String, dynamic>{'kcmc': '高等数学', 'cdmc': '教室A'},
      ];
      final items = jsonExams(rows);
      expect(items, hasLength(1));
      expect(items.first.courseName, '高等数学');
    });

    test('ExamItem JSON 往返序列化保真', () {
      const original = ExamItem(
        courseName: '操作系统',
        examType: '期末考试',
        campus: '四方校区',
        classroom: '一教101',
        seatNumber: '05',
        examForm: '笔试',
        rawTimeStr: '2025-01-10 14:00-16:00',
        status: '正常',
      );
      final json = original.toJson();
      final restored = ExamItem.fromJson(json);
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
      expect(restored.toString(), contains('操作系统'));
    });

    test('jsonExams 自动去重相同考试条目', () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{
          'kcmc': '大学物理B',
          'cdmc': '教室A',
          'kssj': '2025-01-08 08:30-10:30'
        },
        <String, dynamic>{
          'kcmc': '大学物理B',
          'cdmc': '教室A',
          'kssj': '2025-01-08 08:30-10:30'
        },
      ];
      final items = jsonExams(rows);
      expect(items, hasLength(1));
    });

    test(
        'jsonExams 解析青科大真实教务返回字段 (kcmc, kssj括号格式, cdmc, cdxqmc, ksmc, ksfs, zwh)',
        () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{
          'kcmc': '编译原理',
          'kssj': '2025-01-10(08:30-10:30)',
          'cdmc': 'M1-301',
          'cdxqmc': '崂山校区',
          'ksmc': '期末考试',
          'ksfs': '笔试',
          'zwh': '15',
          'kszt': '正常',
        },
      ];
      final items = jsonExams(rows);
      expect(items, hasLength(1));
      final item = items.first;
      expect(item.courseName, '编译原理');
      expect(item.startTime, DateTime(2025, 1, 10, 8, 30));
      expect(item.endTime, DateTime(2025, 1, 10, 10, 30));
      expect(item.classroom, 'M1-301');
      expect(item.campus, '崂山校区');
      expect(item.examType, '期末考试');
      expect(item.examForm, '笔试');
      expect(item.seatNumber, '15');
      expect(item.status, '正常');
    });
  });

  group('客户端网络查询 (fetchExams)', () {
    test('登录后成功拉取考试安排并验证 showCount=500 参数', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));

        final exams = await client.fetchExams('2026-2027-1');
        expect(exams, hasLength(2));
        expect(exams[0].courseName, '大学物理B');
        expect(exams[0].classroom, '弘毅楼 201');
        expect(exams[0].seatNumber, '32');
        expect(exams[1].courseName, '离散数学');

        // 核对请求参数带 showCount=500 且端点为真实的 kscx_cxXsksxxIndex.html
        final req = server.requests.lastWhere(
          (r) => r.path.endsWith('/kwgl/kscx_cxXsksxxIndex.html'),
        );
        expect(req.form['queryModel.showCount'], '500');
        expect(req.form['xnm'], '2026');
        expect(req.form['xqm'], '3');
        client.dispose();
      });
    });

    test('ZfEndpoints 默认考试端点指向 kscx_cxXsksxxIndex.html', () {
      expect(const ZfEndpoints().examsPath, '/kwgl/kscx_cxXsksxxIndex.html');
      expect(const ZfEndpoints().examGnmkdm, 'N358105');
    });

    test('未登录时拉取考试抛出 SESSION_EXPIRED', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await expectLater(
          client.fetchExams('2026-2027-1'),
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

    test('parseTerm 与 zfTermParams 兼容正方 xqm 编码 (12, 16)', () {
      final term12 = parseTerm('2024-2025-12');
      expect(term12, isNotNull);
      expect(term12!.year, 2024);
      expect(term12.semester, 2);
      expect(term12.id, '2024-2025-2');

      final params12 = zfTermParams('2024-2025-12');
      expect(params12.xnm, '2024');
      expect(params12.xqm, '12');

      final term16 = parseTerm('2024-2025-16');
      expect(term16, isNotNull);
      expect(term16!.semester, 3);
    });
  });
}
