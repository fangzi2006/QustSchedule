import 'package:test/test.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'support/synthetic_zf.dart';

void main() {
  group('考试时间解析 (parseExamTime)', () {
    test('覆盖所有有效格式与边界（标准/括号波浪线/中文/斜杠带秒/单点/仅日期/空/待定）', () {
      final cases = [
        (
          '2025-01-08 08:30-10:30',
          DateTime(2025, 1, 8, 8, 30),
          DateTime(2025, 1, 8, 10, 30)
        ),
        (
          '2025-01-08(08:30~10:30)',
          DateTime(2025, 1, 8, 8, 30),
          DateTime(2025, 1, 8, 10, 30)
        ),
        (
          '2025年06月15日 14:00至16:00',
          DateTime(2025, 6, 15, 14, 0),
          DateTime(2025, 6, 15, 16, 0)
        ),
        (
          '2025/02/10 09:00:00-11:00:00',
          DateTime(2025, 2, 10, 9, 0),
          DateTime(2025, 2, 10, 11, 0)
        ),
        ('2025-03-01 10:00', DateTime(2025, 3, 1, 10, 0), null),
        ('2025-03-01', DateTime(2025, 3, 1), null),
        ('', null, null),
        ('待定', null, null),
        ('时间未定', null, null),
      ];
      for (final (raw, start, end) in cases) {
        final parsed = parseExamTime(raw);
        expect(parsed.startTime, start, reason: 'Failed startTime for "$raw"');
        expect(parsed.endTime, end, reason: 'Failed endTime for "$raw"');
      }
    });
  });

  group('考试数据清洗与序列化 (jsonExams & ExamItem)', () {
    test('完整解析考试行字段并兼容青科大/正方别名字段 (cdxqmc/xqmc, cdmc/jxcdmc)', () {
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
        <String, dynamic>{
          'kcmc': '编译原理',
          'ksmc': '期末考试',
          'kssj': '2025-01-10(08:30-10:30)',
          'cdxqmc': '崂山校区',
          'jxcdmc': 'M1-301',
          'zwh': '15',
          'ksfs': '笔试',
          'kszt': '正常',
        },
      ];
      final items = jsonExams(rows);
      expect(items, hasLength(2));

      final exam1 = items[0];
      expect(exam1.courseName, '大学物理B');
      expect(exam1.examType, '2024-2025-1期末考试');
      expect(exam1.campus, '崂山校区');
      expect(exam1.classroom, '弘毅楼 201');
      expect(exam1.seatNumber, '32');
      expect(exam1.examForm, '闭卷');
      expect(exam1.status, '正常');
      expect(exam1.startTime, DateTime(2025, 1, 8, 8, 30));
      expect(exam1.endTime, DateTime(2025, 1, 8, 10, 30));

      final exam2 = items[1];
      expect(exam2.courseName, '编译原理');
      expect(exam2.examType, '期末考试');
      expect(exam2.campus, '崂山校区');
      expect(exam2.classroom, 'M1-301');
      expect(exam2.seatNumber, '15');
      expect(exam2.examForm, '笔试');
      expect(exam2.status, '正常');
      expect(exam2.startTime, DateTime(2025, 1, 10, 8, 30));
      expect(exam2.endTime, DateTime(2025, 1, 10, 10, 30));
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

    test('calendarTerm 在东八区清晨与临界时间点保持本地学年学期正确（防 UTC 跨天回退）', () {
      // 8月1日凌晨 01:00（若转 UTC 为 7月31日 17:00，曾导致年份-1）
      final augEarly = DateTime(2026, 8, 1, 1, 0);
      final termAug = calendarTerm(augEarly);
      expect(termAug.year, 2026);
      expect(termAug.semester, 1);
      expect(termAug.id, '2026-2027-1');

      // 1月15日凌晨 02:00 -> 仍属于当前学年第 1 学期
      final janEarly = DateTime(2027, 1, 15, 2, 0);
      final termJan = calendarTerm(janEarly);
      expect(termJan.year, 2026);
      expect(termJan.semester, 1);
      expect(termJan.id, '2026-2027-1');

      // 2月1日凌晨 00:30 -> 属于第 2 学期
      final febEarly = DateTime(2027, 2, 1, 0, 30);
      final termFeb = calendarTerm(febEarly);
      expect(termFeb.year, 2026);
      expect(termFeb.semester, 2);
      expect(termFeb.id, '2026-2027-2');
    });
  });
}
