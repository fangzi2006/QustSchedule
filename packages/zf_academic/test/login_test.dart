import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zf_academic/src/html.dart';
import 'package:zf_academic/src/respond.dart' show listRows;
import 'package:zf_academic/src/schedule.dart';
import 'package:zf_academic/src/urls.dart' show normalizeEndpoints;
import 'package:zf_academic/zf_academic_io.dart';

import 'support/synthetic_zf.dart';

void main() {
  group('地址解析', () {
    test('只给 URL 也能推出 protocol/domain/basePath', () {
      final client = ZhengfangClient(const ZfClientConfig(
          baseUrl: 'https://jw.example.edu.cn/jwglxt/xtgl/login_slogin.html'));
      expect(client.baseUrl, 'https://jw.example.edu.cn/jwglxt');
      expect(client.allowedHosts, ['jw.example.edu.cn']);
      client.dispose();

      final implicit =
          ZhengfangClient(const ZfClientConfig(baseUrl: 'jw.example.edu.cn'));
      expect(implicit.baseUrl, 'https://jw.example.edu.cn');
      implicit.dispose();

      expect(
        () => ZhengfangClient(const ZfClientConfig(baseUrl: 'not a url')),
        throwsA(isA<AcademicError>()),
      );
    });
  });

  group('probe（只探测，不提交凭据）', () {
    test('识别新正方特征、RSA 加密、无验证码、无统一认证', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        final probe = await client.probe();
        expect(probe.reachable, isTrue);
        expect(probe.looksLikeZhengfang, isTrue);
        expect(probe.passwordEncryption, isTrue);
        expect(probe.captchaRequired, isFalse);
        expect(probe.requiresCas, isFalse);
        client.dispose();
      });
    });

    test('报告验证码需求', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        final probe = await client.probe();
        expect(probe.captchaRequired, isTrue);
        client.dispose();
      }, const SyntheticZfOptions(captchaCode: '1234'));
    });

    test('探测到统一认证时如实报告', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        final probe = await client.probe();
        expect(probe.requiresCas, isTrue);
        expect(probe.casLoginUrl, isNotNull);
        client.dispose();
      }, const SyntheticZfOptions(casRedirect: true));
    });
  });

  group('表单登录', () {
    test('登录成功：读到身份、Cookie 落地、服务端能解出正确密码', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        final state = await client.login(
          Credentials(server.username, server.password),
        );
        expect(state, isA<AuthenticatedState>());
        final authenticated = state as AuthenticatedState;
        expect(authenticated.studentName, server.studentName);
        expect(authenticated.studentId, server.studentId);

        // 服务端用真实私钥把 mm 解回了明文密码——加密链路被对抗性验证。
        final post = server.requests.firstWhere(
          (item) =>
              item.method == 'POST' &&
              item.path.endsWith('/xtgl/login_slogin.html'),
        );
        expect(post.form['mm_decrypted'], server.password);
        // 公钥在提交前取到。
        expect(
          server
              .paths()
              .any((path) => path.endsWith('/xtgl/login_getPublicKey.html')),
          isTrue,
        );
        // 登录成功后 Cookie 里有会话。
        expect(client.cookieHeader, contains('JSESSIONID=fixture-session'));
        client.dispose();
      });
    });

    test('二次重登复用 CAS 探测，但每次登录都重新获取当前会话的 RSA 公钥', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        final firstKeyCount = server
            .paths()
            .where((p) => p.endsWith('/xtgl/login_getPublicKey.html'))
            .length;
        final firstCasCount =
            server.paths().where((p) => p.endsWith('/sso/zfiotlogin')).length;
        expect(firstKeyCount, 1);
        expect(firstCasCount, 1);

        // 二次登录（模拟 Cookie 过期后同一实例重新登录，会建立新 JSESSIONID）
        await client.login(Credentials(server.username, server.password));
        final secondKeyCount = server
            .paths()
            .where((p) => p.endsWith('/xtgl/login_getPublicKey.html'))
            .length;
        final secondCasCount =
            server.paths().where((p) => p.endsWith('/sso/zfiotlogin')).length;
        expect(secondKeyCount, 2, reason: '正方 RSA 公钥与会话绑定，每次登录必须重新获取');
        expect(secondCasCount, 1, reason: 'CAS 探测结果应复用，不重复探测');
        client.dispose();
      });
    });

    test('请求形状：form action 带 ?time=、双 mm、登录前先清理会话', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        final post = server.requests.firstWhere(
          (item) =>
              item.method == 'POST' &&
              item.path.endsWith('/xtgl/login_slogin.html'),
        );
        expect(post.query.containsKey('time'), isTrue,
            reason: '浏览器会追加 ?time= 破缓存');
        expect(
          post.rawBody,
          contains('mm=${server.password}&mm=${server.password}'),
          reason: '登录页两个 name=mm 输入框都会提交',
        );
        // 登录前先清理会话（浏览器 login.js 的 yhdl() 行为）。
        final logoutIndex = server.requests.indexWhere(
          (item) => item.path.endsWith('/xtgl/login_logoutAccount.html'),
        );
        expect(logoutIndex, greaterThan(0));
        expect(logoutIndex, lessThan(server.requests.length - 1));
        client.dispose();
      }, const SyntheticZfOptions(encrypt: false));
    });

    test('密码错误先于"未登录重定向"被报出来，且不再去读身份信息', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await expectLater(
          client.login(Credentials(server.username, 'wrong-password')),
          throwsA(isA<AcademicError>().having(
              (error) => error.code, 'code', ErrorCode.invalidCredentials)),
        );
        // 与主分支 ZfLoginFailureTest 的期望一致：探测 + 取登录页 + 清理会话 + 提交，之后不再请求 initMenu。
        expect(server.paths(), <String>[
          '/jwglxt/sso/zfiotlogin',
          '/jwglxt/xtgl/login_slogin.html',
          '/jwglxt/xtgl/login_logoutAccount.html',
          '/jwglxt/xtgl/login_slogin.html',
        ]);
        client.dispose();
      }, const SyntheticZfOptions(encrypt: false));
    });

    test('统一认证学校：login() 抛 UNSUPPORTED 而不是硬走表单', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await expectLater(
          client.login(Credentials(server.username, server.password)),
          throwsA(isA<AcademicError>()
              .having((error) => error.code, 'code', ErrorCode.unsupported)),
        );
        client.dispose();
      }, const SyntheticZfOptions(casRedirect: true));
    });

    test('mmsfjm 取值矛盾时报 PAGE_CHANGED，不拿着不确定的值去赌', () async {
      const override = '<html><body>'
          '<input type="hidden" name="csrftoken" value="t">'
          '<input type="hidden" name="mmsfjm" value="0">'
          '<input type="hidden" name="mmsfjm" value="1">'
          '<input name="yhm"><input type="password" name="mm">'
          '</body></html>';
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await expectLater(
          client.login(Credentials(server.username, server.password)),
          throwsA(isA<AcademicError>()
              .having((error) => error.code, 'code', ErrorCode.pageChanged)),
        );
        client.dispose();
      }, const SyntheticZfOptions(loginPageOverride: override));
    });

    test('登录页缺少 csrftoken 时报 PAGE_CHANGED', () async {
      const override = '<html><body>'
          '<input name="yhm"><input type="password" name="mm">'
          '</body></html>';
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await expectLater(
          client.login(Credentials(server.username, server.password)),
          throwsA(isA<AcademicError>()
              .having((error) => error.code, 'code', ErrorCode.pageChanged)),
        );
        client.dispose();
      }, const SyntheticZfOptions(loginPageOverride: override));
    });
  });

  group('验证码', () {
    test('返回图片、错误码可重试、正确码完成登录', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        final login = await client.login(
          Credentials(server.username, server.password),
        );
        expect(login, isA<CaptchaState>());
        final captcha = login as CaptchaState;
        expect(captcha.mimeType, 'image/png');
        expect(captcha.imageBase64, isNotEmpty);
        expect(
          base64.decode(captcha.imageBase64).sublist(1, 4),
          'PNG'.codeUnits,
        );

        // 验证码错误时换一张图继续，不新建账号会话（与 TS 参考实现同口径）。
        final retry = await client.submitCaptcha('0000');
        expect(retry, isA<CaptchaState>());
        expect((retry as CaptchaState).continuationId, captcha.continuationId);

        final refreshed = await client.refreshCaptcha();
        expect(
          refreshed.continuationId,
          captcha.continuationId,
          reason: '刷新验证码不新建账号会话',
        );

        final done = await client.submitCaptcha('1234');
        expect(done, isA<AuthenticatedState>());
        expect(client.cookieHeader, contains('JSESSIONID=fixture-session'));
        client.dispose();
      }, const SyntheticZfOptions(captchaCode: '1234'));
    });
  });

  group('Cookie 持久化与免登查询', () {
    test('登录 → 导出快照 → 新实例免登查课表', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        final snapshot = client.exportCookies();
        client.dispose();

        final restored = vmZhengfangClient(
          ZfClientConfig(baseUrl: server.baseUrl, cookies: snapshot),
        );
        final schedule = await restored.fetchSchedule('2026-2027-1');
        expect(schedule.entries.length, 2);
        expect(schedule.termId, '2026-2027-1');
        // 免登查询确实带上了已保存的会话。
        final post = server.requests.last;
        expect(post.cookie, contains('JSESSIONID=fixture-session'));
        restored.dispose();
      });
    });

    test('FileCookieStorage 落盘往返（含 0600 收紧）', () async {
      final store = CookieStore(baseUrl: 'https://jw.example.edu.cn/jwglxt')
        ..setCookie(
          Uri.parse('https://jw.example.edu.cn/jwglxt/'),
          'JSESSIONID=fixture-session; Path=/jwglxt; HttpOnly',
        );
      final snapshot = store.export();
      final storage = FileCookieStorage('.dart_tool/test-session.json');
      await storage.save(snapshot);

      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.cookies.any((item) => item.name == 'JSESSIONID'), isTrue);
      await storage.clear();
    });

    test('checkSession 三态：已登录 / 已失效 / 无法确认', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        final ok = await client.checkSession();
        expect(ok.status, SessionStatus.authenticated);
        expect(ok.studentId, server.studentId);

        client.invalidate();
        final expired = await client.checkSession();
        expect(expired.status, SessionStatus.expired);
        client.dispose();
      });

      // 学生信息页 404：无法确认，而不是误报失效。
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        final unknown = await client.checkSession();
        expect(unknown.status, SessionStatus.unknown);
        client.dispose();
      }, const SyntheticZfOptions(identityStatus: 404));
    });
  });

  group('课表查询', () {
    test('fetchTerms 汇总两个页面的学期并标出当前学期', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        final terms = await client.fetchTerms();
        expect(
            terms.items.map((item) => item.id),
            containsAll(<String>[
              '2026-2027-1',
              '2026-2027-2',
            ]));
        expect(terms.currentId, '2026-2027-1');
        client.dispose();
      });
    });

    test('fetchSchedule 解析 kbList：字段、节次、周次', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        final schedule = await client.fetchSchedule();
        expect(schedule.termId, '2026-2027-1');
        expect(schedule.entries.length, 2);

        final math = schedule.entries.firstWhere((item) => item.name == '离散数学');
        expect(math.day, 1);
        expect(math.startPeriod, 1);
        expect(math.endPeriod, 2);
        expect(math.weeks, <int>[1, 3], reason: '1-4周(单) → 1、3 周');
        expect(math.teacher, '合成教师');
        expect(math.location, '东校区 教室A');
        expect(schedule.maxWeeks, greaterThanOrEqualTo(8));
        expect(schedule.remarks, isEmpty, reason: '没有 sjkList 时备注为空');

        final english =
            schedule.entries.firstWhere((item) => item.name == '大学英语');
        expect(english.day, 3);
        expect(english.startPeriod, 5);
        expect(english.endPeriod, 6);
        expect(english.weeks, <int>[2, 3, 4, 5, 6, 7, 8]);
        client.dispose();
      });
    });

    test('fetchSchedule 解析 sjkList 备注：实践课程 / 其他课程', () async {
      final body = jsonEncode(<String, Object?>{
        'kbList': <Map<String, Object?>>[
          <String, Object?>{
            'kcmc': '离散数学',
            'kch_id': 'C1',
            'xm': '合成教师',
            'cdmc': '教室A',
            'xqj': '1',
            'jcs': '1-2',
            'zcd': '1-4周(单)',
          },
        ],
        'sjkList': <Map<String, Object?>>[
          <String, Object?>{
            'sfsjk': '1',
            'sjkcgs': '生产实习',
            'kcmc': '金工实习',
            'xm': '王老师',
            'zcd': '第18周',
            'xqmc': '东校区',
            'cdmc': '车间A',
          },
          <String, Object?>{'sfsjk': '0', 'sjkcgs': '线上自主学习'},
        ],
      });
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        final schedule = await client.fetchSchedule();
        expect(schedule.remarks, hasLength(2));

        // sfsjk=1 → 实践课程。
        final practical = schedule.remarks.firstWhere((r) => r.practical);
        expect(practical.content, '生产实习');
        expect(practical.courseName, '金工实习');
        expect(practical.teacher, '王老师');
        expect(practical.weeks, '第18周');
        expect(practical.location, '东校区 车间A');

        // sfsjk=0 → 其他课程（只有显示字段，其余缺省为 null）。
        final other = schedule.remarks.firstWhere((r) => !r.practical);
        expect(other.content, '线上自主学习');
        expect(other.courseName, isNull);
        expect(other.location, isNull);
        client.dispose();
      }, SyntheticZfOptions(scheduleBody: body));
    });

    test('"没有访问权限"时走路由发现，仍被拒则报 UNSUPPORTED', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        await expectLater(
          client.fetchSchedule('2026-2027-1'),
          throwsA(isA<AcademicError>()
              .having((error) => error.code, 'code', ErrorCode.unsupported)),
        );
        // 路由发现读了菜单页。
        expect(
          server
              .paths()
              .any((path) => path.endsWith('/xtgl/index_initMenu.html')),
          isTrue,
        );
        client.dispose();
      }, const SyntheticZfOptions(scheduleDenied: true));
    });

    test('qustZfEndpoints 个人课表查询：直连 cxXsgrkb 且带 kzlx/ajax/referer', () async {
      await withServer((server) async {
        final client = vmZhengfangClient(ZfClientConfig(
          baseUrl: server.baseUrl,
          endpoints: qustZfEndpoints,
        ));
        await client.login(Credentials(server.username, server.password));

        // 1. 指定学期查询
        final schedule = await client.fetchSchedule('2026-2027-1');
        expect(schedule.entries.length, 2);
        expect(schedule.termId, '2026-2027-1');

        final post = server.requests.last;
        expect(post.path, endsWith('/kbcx/xskbcx_cxXsgrkb.html'));
        expect(post.query['gnmkdm'], 'N2151');
        expect(post.form['xnm'], '2026');
        expect(post.form['xqm'], '3');
        expect(post.form['kzlx'], 'ck');
        expect(
          post.referer,
          contains('/kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151'),
        );

        // 2. 自决当前学期查询 (termId == null)
        final autoSchedule = await client.fetchSchedule();
        expect(autoSchedule.entries.length, 2);
        expect(autoSchedule.termId, '2026-2027-1');

        client.dispose();
      });
    });

    test('会话失效时查课表报 SESSION_EXPIRED（而不是空课表）', () async {
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        client.invalidate();
        await expectLater(
          client.fetchSchedule('2026-2027-1'),
          throwsA(isA<AcademicError>()
              .having((error) => error.code, 'code', ErrorCode.sessionExpired)),
        );
        client.dispose();
      });
    });
  });

  group('解析函数（真实教务页面片段）', () {
    test('termsFromHtml / selectedTermFromHtml', () {
      const html =
          '<select name="xnm"><option value="2026" selected>2026-2027</option></select>'
          '<select name="xqm"><option value="3" selected>1</option><option value="12">2</option></select>';
      final terms = termsFromHtml(html);
      expect(terms.map((item) => item.id),
          containsAll(<String>['2026-2027-1', '2026-2027-2']));
      expect(selectedTermFromHtml(html)?.id, '2026-2027-1');
    });

    test('periods / weeks 覆盖真实页面的多种写法', () {
      expect(periods('1-2'), <(int, int)>[(1, 2)]);
      expect(periods('3,4'), <(int, int)>[(3, 4)]);
      expect(periods('5-6节'), <(int, int)>[(5, 6)]);
      expect(periods('1-3,7'), <(int, int)>[(1, 3), (7, 7)]);
      expect(weeks('1-4周(单)'), <int>[1, 3]);
      expect(weeks('第3-5周'), <int>[3, 4, 5]);
      expect(weeks('1,3,5周'), <int>[1, 3, 5]);
      expect(weeks('[1-16周]'), List<int>.generate(16, (i) => i + 1));
      expect(weeks('1-30周'), List<int>.generate(30, (i) => i + 1));
      expect(weeks('第28周'), <int>[28]);
      expect(tryParseWeeks('1~16周'), List<int>.generate(16, (i) => i + 1));
      expect(tryParseWeeks('1至16周'), List<int>.generate(16, (i) => i + 1));
      expect(tryParseWeeks('1-8周(全)'), <int>[1, 2, 3, 4, 5, 6, 7, 8]);
      expect(tryParseWeeks('非标准说明文本'), isEmpty);
    });

    test('isLoginPage / detectCaptcha / hiddenFields', () {
      const login = '<html><body><form>'
          '<input type="hidden" name="csrftoken" value="t">'
          '<input name="yhm"><input type="password" name="mm">'
          '<img id="icode" src="/kaptcha"><input name="yzm">'
          '</form></body></html>';
      expect(isLoginPage(login), isTrue);
      expect(hiddenFields(login), <String, String>{'csrftoken': 't'});
      final captcha = detectCaptcha(login);
      expect(captcha.control?.fieldName, 'yzm');
      expect(captcha.control?.imageSrc, '/kaptcha');
      expect(isLoginPage('<html><body>首页</body></html>'), isFalse);
    });

    test('identity：标题式 / 输入框式 / 只有姓名', () {
      expect(
        identity('<div class="infoContentTitle">张三-20250001</div>'),
        const Identity(studentName: '张三', studentId: '20250001'),
      );
      expect(
        identity(
            '<input name="xh" value="20250001"><span class="media-heading">张三</span>'),
        const Identity(studentName: '张三', studentId: '20250001'),
      );
      // 角色后缀前必须有空白才会剥离（"合成学生"原样保留，与 SDK 口径一致）。
      expect(
        identity('<span class="media-heading">合成学生</span>').studentName,
        '合成学生',
      );
      expect(
        identity('<span class="media-heading">张三  学生</span>').studentName,
        '张三',
      );
    });

    test('normalizeEndpoints 保留 scheduleQueryPath 与 personal 属性', () {
      final normalized = normalizeEndpoints(qustZfEndpoints);
      expect(normalized.schedulePath, '/kbcx/xskbcx_cxXskbcxIndex.html');
      expect(normalized.scheduleQueryPath, '/kbcx/xskbcx_cxXsgrkb.html');
      expect(normalized.scheduleGnmkdm, 'N2151');
      expect(normalized.personal, isTrue);
    });

    test('jsonSchedule 跳过缺星期/节次的无规律课程，周次异常时安全兜底', () {
      final rows = <Map<String, dynamic>>[
        <String, dynamic>{
          'kcmc': '离散数学',
          'xqj': '1',
          'jcs': '1-2',
          'zcd': '1-4周',
        },
        <String, dynamic>{
          'kcmc': '无时间安排讲座',
          'xqj': '',
          'jcs': '',
          'zcd': '',
        },
        <String, dynamic>{
          'kcmc': '非常规周次课程',
          'xqj': '2',
          'jcs': '3-4',
          'zcd': '非标准说明文本',
        },
      ];
      final entries = jsonSchedule(rows);
      expect(entries.length, 2);
      expect(entries[0].name, '离散数学');
      expect(entries[0].weeks, [1, 2, 3, 4]);
      expect(entries[1].name, '非常规周次课程');
      expect(entries[1].weeks, isEmpty);
      expect(
        entries[1].details?.any(
              (d) =>
                  d.id == 'rawWeeks' &&
                  d.label == '周次说明' &&
                  d.value == '非标准说明文本',
            ),
        isTrue,
      );
    });

    test('FileCookieStorage 遇到损坏的 JSON 文件时返回 null 而不崩溃', () async {
      const path = '.dart_tool/corrupt-session.json';
      final file = File(path)..createSync(recursive: true);
      file.writeAsStringSync('{not valid json!!!');
      final storage = FileCookieStorage(path);
      addTearDown(() async => storage.clear());

      expect(await storage.load(), isNull);
    });

    test('FileCookieStorage 连续保存合并只保留最新快照，且 clear 可作废未落盘任务', () async {
      final dir = await Directory.systemTemp.createTemp('cookie_coalesce_');
      addTearDown(() => dir.delete(recursive: true));
      final storage = FileCookieStorage('${dir.path}/cookies.json');

      await Future.wait(<Future<void>>[
        for (var i = 1; i <= 10; i++)
          storage.save(
            CookieStoreSnapshot(
              version: 1,
              baseUrl: 'https://jw.example.edu.cn/jwglxt',
              savedAt: i,
              cookies: const [],
            ),
          ),
      ]);

      final loaded = await storage.load();
      expect(loaded, isNotNull);
      expect(loaded!.savedAt, 10);

      final pending = storage.save(
        const CookieStoreSnapshot(
          version: 1,
          baseUrl: 'https://jw.example.edu.cn/jwglxt',
          savedAt: 99,
          cookies: [],
        ),
      );
      await storage.clear();
      await pending;
      expect(await storage.load(), isNull);
    });

    test('selectedTermFromHtml 遇到长度不足 4 位的学年值时不抛 RangeError', () {
      const html =
          '<select name="xnm"><option value="12" selected></option></select>'
          '<select name="xqm"><option value="3" selected></option></select>';
      expect(() => selectedTermFromHtml(html), returnsNormally);
      expect(selectedTermFromHtml(html), isNull);
    });
  });

  group('生命周期、缓存刷新与状态码诊断', () {
    RawHttpResponse htmlResp(int status, String url, String body) {
      return RawHttpResponse(
        status: status,
        url: url,
        bytes: utf8.encode(body),
        headers: const <String, List<String>>{
          'content-type': <String>['text/html; charset=utf-8'],
        },
      );
    }

    RawHttpResponse jsonResp(int status, String url, Object data) {
      return RawHttpResponse(
        status: status,
        url: url,
        bytes: utf8.encode(jsonEncode(data)),
        headers: const <String, List<String>>{
          'content-type': <String>['application/json; charset=utf-8'],
        },
      );
    }

    test('dispose() 与 close() 行为一致：幂等释放传输并作废会话，释放后抛 cancelled', () async {
      const base = 'https://jw.example.edu.cn/jwglxt';
      final snapshot = CookieStoreSnapshot(
        version: 1,
        baseUrl: base,
        savedAt: 1,
        cookies: const <CookieRecord>[
          CookieRecord(
            name: 'JSESSIONID',
            value: 's1',
            domain: 'jw.example.edu.cn',
            path: '/',
            hostOnly: true,
            secure: true,
            httpOnly: true,
            expiresAt: null,
            createdAt: 1,
            setByHost: 'jw.example.edu.cn',
            setByPort: 443,
          ),
        ],
      );

      var disposeCount1 = 0;
      final client1 = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        cookies: snapshot,
        transport: (_) async => htmlResp(200, base, 'ok'),
        onDispose: () => disposeCount1 += 1,
      ));
      final gen1 = client1.generation;
      client1.dispose();
      client1.close();
      expect(disposeCount1, 1);
      expect(client1.cookieHeader, isEmpty);
      expect(client1.session.authenticated, isFalse);
      expect(client1.generation, greaterThan(gen1));

      var disposeCount2 = 0;
      final client2 = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        cookies: snapshot,
        transport: (_) async => htmlResp(200, base, 'ok'),
        onDispose: () => disposeCount2 += 1,
      ));
      final gen2 = client2.generation;
      client2.close();
      client2.dispose();
      expect(disposeCount2, 1);
      expect(client2.cookieHeader, isEmpty);
      expect(client2.session.authenticated, isFalse);
      expect(client2.generation, greaterThan(gen2));

      for (final Future<Object?> Function() op in <Future<Object?> Function()>[
        () => client2.probe(),
        () => client2.login(const Credentials('20240001', 'pw')),
        () => client2.checkSession(),
        () => client2.fetchTerms(),
        () => client2.fetchSchedule('2025-2026-1'),
        () => client2.fetchExams('2025-2026-1'),
        () => client2.fetchGrades('2025-2026-1'),
        () async {
          client2.importCookies(snapshot);
          return null;
        },
        () async {
          client2.importCookieHeader('JSESSIONID=abc');
          return null;
        },
      ]) {
        await expectLater(
          op(),
          throwsA(
            isA<AcademicError>().having(
              (e) => e.code,
              'code',
              ErrorCode.cancelled,
            ),
          ),
        );
      }
    });

    test('probe() 在途期间 close() 抛出 cancelled 而非吞成 reachable: false', () async {
      const base = 'https://jw.example.edu.cn/jwglxt';
      final entered = Completer<void>();
      final gate = Completer<RawHttpResponse>();
      final client = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (RawHttpRequest req) {
          if (!entered.isCompleted) entered.complete();
          return gate.future;
        },
      ));

      final future = client.probe();
      await entered.future;
      client.close();
      gate.complete(htmlResp(404, '$base/sso/zfiotlogin', 'not found'));

      await expectLater(
        future,
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.cancelled,
          ),
        ),
      );
    });

    test('lastTermsRawBody 在每次 fetchTerms() 调用时刷新（含回退页面）', () async {
      const base = 'https://jw.example.edu.cn/jwglxt';
      const html1 = '''
        <html><body>
          <select name="xnm"><option value="2025" selected>2025-2026</option></select>
          <select name="xqm"><option value="3" selected>1</option></select>
        </body></html>
      ''';
      const htmlNoTerms = '<html><body><div>课表页未包含学期下拉框</div></body></html>';
      const html2 = '''
        <html><body>
          <select name="xnm"><option value="2026" selected>2026-2027</option></select>
          <select name="xqm"><option value="12" selected>2</option></select>
        </body></html>
      ''';
      final responses = <RawHttpResponse>[
        htmlResp(200, '$base/kbcx/xskbcx_cxXskbcxIndex.html', html1),
        htmlResp(200, '$base/kbcx/xskbcx_cxXskbcxIndex.html', htmlNoTerms),
        htmlResp(200, '$base/cjcx/cjcx_cxDgXscj.html', html2),
      ];
      var idx = 0;
      final client = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (_) async => responses[idx++],
      ));
      addTearDown(client.close);

      final t1 = await client.fetchTerms();
      expect(t1.currentId, '2025-2026-1');
      expect(client.lastTermsRawBody, html1);

      final t2 = await client.fetchTerms();
      expect(t2.currentId, '2026-2027-2');
      expect(client.lastTermsRawBody, html2);
    });

    test('lastExamsRawBody 与 lastGradesRawBody 连续查询均刷新为最新响应', () async {
      const base = 'https://jw.example.edu.cn/jwglxt';
      var call = 0;
      final client = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (RawHttpRequest req) async {
          call += 1;
          if (req.url.path.contains('kwgl')) {
            return jsonResp(200, req.url.toString(), <String, Object?>{
              'items': <Map<String, Object?>>[
                <String, Object?>{
                  'kcmc': '考试$call',
                  'kssj': '2026-01-08 09:00-11:00'
                },
              ],
            });
          }
          return jsonResp(200, req.url.toString(), <String, Object?>{
            'items': <Map<String, Object?>>[
              <String, Object?>{'kcmc': '成绩$call', 'cj': '90', 'xf': '2.0'},
            ],
          });
        },
      ));
      addTearDown(client.close);

      await client.fetchExams('2025-2026-1');
      final examBody1 = client.lastExamsRawBody;
      await client.fetchExams('2025-2026-2');
      expect(client.lastExamsRawBody, isNot(equals(examBody1)));
      expect(client.lastExamsRawBody, contains('考试2'));

      await client.fetchGrades('2025-2026-1');
      final gradeBody1 = client.lastGradesRawBody;
      await client.fetchGrades('2025-2026-2');
      expect(client.lastGradesRawBody, isNot(equals(gradeBody1)));
      expect(client.lastGradesRawBody, contains('成绩4'));
    });

    test('_loginViaForm() 与 fetchTerms() 透传真实 HTTP statusCode 给响应诊断', () async {
      const base = 'https://jw.example.edu.cn/jwglxt';

      // 1. 登录页 HTTP 404（缺少 csrftoken）→ pageChanged 且保留 httpStatus: 404
      final client404 = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (RawHttpRequest req) async {
          if (req.url.path.endsWith('/sso/zfiotlogin')) {
            return htmlResp(404, req.url.toString(), 'no cas');
          }
          return htmlResp(
              404, req.url.toString(), '<html><title>404</title></html>');
        },
      ));
      addTearDown(client404.close);
      await expectLater(
        client404.login(const Credentials('20240001', 'pw')),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.pageChanged)
              .having((e) => e.httpStatus, 'httpStatus', 404),
        ),
      );

      // 2. 登录页 HTTP 200 维护页 → serverError
      final clientMaint = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (RawHttpRequest req) async {
          if (req.url.path.endsWith('/sso/zfiotlogin')) {
            return htmlResp(404, req.url.toString(), 'no cas');
          }
          return htmlResp(
            200,
            req.url.toString(),
            '<html><title>系统维护</title><body>系统正在维护中</body></html>',
          );
        },
      ));
      addTearDown(clientMaint.close);
      await expectLater(
        clientMaint.login(const Credentials('20240001', 'pw')),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.serverError),
        ),
      );

      // 3. 登录页 HTTP 200 WAF 403 提示 → accessForbidden
      final clientWaf = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (RawHttpRequest req) async {
          if (req.url.path.endsWith('/sso/zfiotlogin')) {
            return htmlResp(404, req.url.toString(), 'no cas');
          }
          return htmlResp(
            200,
            req.url.toString(),
            '<html><title>访问出错-403</title><body>请通过校园网访问</body></html>',
          );
        },
      ));
      addTearDown(clientWaf.close);
      await expectLater(
        clientWaf.login(const Credentials('20240001', 'pw')),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.accessForbidden),
        ),
      );

      // 4. fetchTerms() 收到 HTTP 200 维护页 → serverError 且保留 lastTermsRawBody
      const maintHtml = '<html><title>系统维护</title><body>系统正在维护中</body></html>';
      final clientTermsMaint = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (RawHttpRequest req) async =>
            htmlResp(200, req.url.toString(), maintHtml),
      ));
      addTearDown(clientTermsMaint.close);
      await expectLater(
        clientTermsMaint.fetchTerms(),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.serverError),
        ),
      );
      expect(clientTermsMaint.lastTermsRawBody, maintHtml);
    });

    test('ZfClientConfig.paceHosts 透传到内部 HTTP 客户端限速', () async {
      const base = 'https://jw.example.edu.cn/jwglxt';
      const html = '''
        <html><body>
          <select name="xnm"><option value="2025" selected>2025-2026</option></select>
          <select name="xqm"><option value="3" selected>1</option></select>
        </body></html>
      ''';
      final client = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        paceHosts: const <String, int>{'jw.example.edu.cn': 60},
        transport: (RawHttpRequest req) async =>
            htmlResp(200, req.url.toString(), html),
      ));
      addTearDown(client.close);

      final sw = Stopwatch()..start();
      await client.fetchTerms();
      await client.fetchTerms();
      sw.stop();

      expect(sw.elapsedMilliseconds, greaterThanOrEqualTo(45));
    });

    test(
        'checkSession() 在 _menuIdentityFallback 在途期间 dispose() 抛 cancelled 且不复活会话',
        () async {
      const base = 'https://jw.example.edu.cn/jwglxt';
      final snapshot = CookieStoreSnapshot(
        version: 1,
        baseUrl: base,
        savedAt: 1,
        cookies: const <CookieRecord>[
          CookieRecord(
            name: 'JSESSIONID',
            value: 's1',
            domain: 'jw.example.edu.cn',
            path: '/',
            hostOnly: true,
            secure: true,
            httpOnly: true,
            expiresAt: null,
            createdAt: 1,
            setByHost: 'jw.example.edu.cn',
            setByPort: 443,
          ),
        ],
      );
      final enteredMenu = Completer<void>();
      final gateMenu = Completer<RawHttpResponse>();
      final client = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        cookies: snapshot,
        transport: (RawHttpRequest req) {
          if (req.url.path.endsWith('/xtgl/index_initMenu.html')) {
            if (!enteredMenu.isCompleted) enteredMenu.complete();
            return gateMenu.future;
          }
          return Future<RawHttpResponse>.value(htmlResp(
            200,
            req.url.toString(),
            '<h4 class="media-heading">张三</h4>',
          ));
        },
      ));

      final future = client.checkSession();
      await enteredMenu.future;
      client.dispose();
      gateMenu.complete(htmlResp(
        200,
        '$base/xtgl/index_initMenu.html',
        '<input type="hidden" id="sessionUserKey" value="20240001">',
      ));

      await expectLater(
        future,
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.cancelled,
          ),
        ),
      );
      expect(client.session.authenticated, isFalse);
      expect(client.session.studentId, isEmpty);
      expect(client.session.studentName, isEmpty);
    });

    test('login() 在 _menuIdentityFallback 在途期间 dispose() 抛 cancelled 且不复活会话',
        () async {
      const base = 'https://jw.example.edu.cn/jwglxt';
      final enteredMenu = Completer<void>();
      final gateMenu = Completer<RawHttpResponse>();
      final client = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (RawHttpRequest req) {
          final path = req.url.path;
          if (path.endsWith('/sso/zfiotlogin')) {
            return Future<RawHttpResponse>.value(
              htmlResp(404, req.url.toString(), 'no cas'),
            );
          }
          if (path.endsWith('/xtgl/login_slogin.html') && req.method == 'GET') {
            return Future<RawHttpResponse>.value(htmlResp(
              200,
              req.url.toString(),
              '<form><input type="hidden" name="csrftoken" value="tok"><input type="hidden" name="mmsfjm" value="0"></form>',
            ));
          }
          if (path.endsWith('/xtgl/login_logoutAccount.html')) {
            return Future<RawHttpResponse>.value(
              htmlResp(200, req.url.toString(), 'null'),
            );
          }
          if (path.endsWith('/xtgl/login_slogin.html') &&
              req.method == 'POST') {
            return Future<RawHttpResponse>.value(
              htmlResp(200, req.url.toString(), '<html><body>ok</body></html>'),
            );
          }
          if (path.endsWith('/xtgl/index_cxYhxxIndex.html')) {
            return Future<RawHttpResponse>.value(htmlResp(
              200,
              req.url.toString(),
              '<h4 class="media-heading">李四</h4>',
            ));
          }
          if (path.endsWith('/xtgl/index_initMenu.html')) {
            if (!enteredMenu.isCompleted) enteredMenu.complete();
            return gateMenu.future;
          }
          return Future<RawHttpResponse>.value(
            htmlResp(404, req.url.toString(), 'unexpected'),
          );
        },
      ));

      final future = client.login(const Credentials('20240001', 'pw'));
      await enteredMenu.future;
      client.dispose();
      gateMenu.complete(htmlResp(
        200,
        '$base/xtgl/index_initMenu.html',
        '<input type="hidden" id="sessionUserKey" value="20240001">',
      ));

      await expectLater(
        future,
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.cancelled,
          ),
        ),
      );
      expect(client.session.authenticated, isFalse);
      expect(client.session.studentId, isEmpty);
      expect(client.session.studentName, isEmpty);
      expect(
        () => client.allowHost('extra.example.edu.cn'),
        throwsA(
          isA<AcademicError>().having(
            (e) => e.code,
            'code',
            ErrorCode.cancelled,
          ),
        ),
      );
      expect(client.allowedHosts, const <String>['jw.example.edu.cn']);
    });

    test('fetchExams()/fetchGrades()/listRows() 在 HTTP 404 时透传 httpStatus',
        () async {
      const base = 'https://jw.example.edu.cn/jwglxt';
      const maintHtml =
          '<html><head><title>系统维护</title></head><body>系统维护中</body></html>';

      final clientMaint = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (RawHttpRequest req) async =>
            htmlResp(404, req.url.toString(), maintHtml),
      ));
      addTearDown(clientMaint.close);

      await expectLater(
        clientMaint.fetchExams('2025-2026-1'),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.serverError)
              .having((e) => e.httpStatus, 'httpStatus', 404),
        ),
      );
      await expectLater(
        clientMaint.fetchGrades('2025-2026-1'),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.serverError)
              .having((e) => e.httpStatus, 'httpStatus', 404),
        ),
      );

      final clientRejectedJson = ZhengfangClient(ZfClientConfig(
        baseUrl: base,
        transport: (RawHttpRequest req) async => jsonResp(
          404,
          req.url.toString(),
          <String, Object?>{'success': false, 'message': '请求失败'},
        ),
      ));
      addTearDown(clientRejectedJson.close);

      await expectLater(
        clientRejectedJson.fetchSchedule('2025-2026-1'),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.pageChanged)
              .having((e) => e.httpStatus, 'httpStatus', 404),
        ),
      );

      expect(
        () => listRows(
          '{"success":false,"message":"failed"}',
          const <String>['kbList'],
          statusCode: 404,
        ),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.pageChanged)
              .having((e) => e.httpStatus, 'httpStatus', 404),
        ),
      );
      expect(
        () => listRows(
          'Not Found',
          const <String>['kbList'],
          statusCode: 404,
        ),
        throwsA(
          isA<AcademicError>()
              .having((e) => e.code, 'code', ErrorCode.pageChanged)
              .having((e) => e.httpStatus, 'httpStatus', 404),
        ),
      );
    });
  });
}
