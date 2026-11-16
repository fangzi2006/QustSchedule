import 'dart:io';

import 'package:test/test.dart';
import 'package:zf_academic/zf_academic_io.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('cookie_isolate_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('FileCookieStorage 超过阈值时通过后台 Isolate 完整往返大数据快照', () async {
    final file = File('${tempDir.path}/cookies_large.json');
    final storage = FileCookieStorage(file.path);

    final bigSnapshot = CookieStoreSnapshot(
      version: 1,
      baseUrl: 'https://jw.example.edu.cn/jwglxt',
      savedAt: 1700000000000,
      cookies: <CookieRecord>[
        for (var i = 0; i < 120; i++)
          CookieRecord(
            name: 'SESSION_$i',
            value: 'val_${'a' * 200}_$i',
            domain: 'jw.example.edu.cn',
            path: '/',
            hostOnly: true,
            secure: true,
            httpOnly: true,
            expiresAt: null,
            createdAt: 1700000000000 + i,
            setByHost: 'jw.example.edu.cn',
            setByPort: 443,
          ),
      ],
    );

    await storage.save(bigSnapshot);
    expect(file.lengthSync(), greaterThan(16 * 1024));

    final loaded = await storage.load();
    expect(loaded, isNotNull);
    expect(loaded!.baseUrl, bigSnapshot.baseUrl);
    expect(loaded.cookies.length, 120);
    expect(loaded.cookies.first.name, 'SESSION_0');
    expect(loaded.cookies.last.value, bigSnapshot.cookies.last.value);
  });

  test('ExamItem effectiveEndTime 兼容纯日期与起止时间段解析', () {
    final rangeExam = ExamItem(
      courseName: '高等数学',
      examType: '期末',
      startTime: DateTime(2026, 12, 20, 9, 0),
      endTime: null,
      campus: '崂山校区',
      classroom: '201',
      seatNumber: '12',
      examForm: '闭卷',
      rawTimeStr: '2026-12-20 09:00-11:00',
      status: '正常',
    );
    expect(rangeExam.effectiveEndTime, DateTime(2026, 12, 20, 11, 0));

    final dateOnlyExam = ExamItem(
      courseName: '大学英语',
      examType: '期末',
      startTime: DateTime(2026, 12, 21),
      endTime: null,
      campus: '崂山校区',
      classroom: '202',
      seatNumber: '15',
      examForm: '闭卷',
      rawTimeStr: '2026-12-21',
      status: '正常',
    );
    expect(
      dateOnlyExam.effectiveEndTime,
      DateTime(2026, 12, 21, 23, 59, 59, 999),
    );
  });
}
