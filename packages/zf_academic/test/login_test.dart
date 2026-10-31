import 'dart:convert';

import 'package:test/test.dart';
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

    test('二次重登复用 CAS 探测与 RSA 公钥，不重复发起多余请求', () async {
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

        // 二次登录（模拟 Cookie 过期后同一实例重新登录）
        await client.login(Credentials(server.username, server.password));
        final secondKeyCount = server
            .paths()
            .where((p) => p.endsWith('/xtgl/login_getPublicKey.html'))
            .length;
        final secondCasCount =
            server.paths().where((p) => p.endsWith('/sso/zfiotlogin')).length;
        expect(secondKeyCount, 1, reason: '公钥应从客户端缓存复用，不重复发起网络请求');
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
      await withServer((server) async {
        final client =
            vmZhengfangClient(ZfClientConfig(baseUrl: server.baseUrl));
        await client.login(Credentials(server.username, server.password));
        final storage = FileCookieStorage('.dart_tool/test-session.json');
        await storage.save(client.exportCookies());
        client.dispose();

        final loaded = await storage.load();
        expect(loaded, isNotNull);
        expect(
            loaded!.cookies.any((item) => item.name == 'JSESSIONID'), isTrue);
        await storage.clear();
      });
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
  });
}
