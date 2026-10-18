import 'dart:convert';

import 'package:test/test.dart';
import 'package:zf_academic/zf_academic.dart';

const _base = 'https://jw.example.edu.cn/jwglxt';

void main() {
  group('Cookie 匹配（RFC 6265）', () {
    test('host-only 只回发同主机，Domain 允许子域', () {
      final store = CookieStore(baseUrl: _base);
      store.setCookies(Uri.parse('https://jw.example.edu.cn/jwglxt/'), const [
        'JSESSIONID=abc; Path=/; HttpOnly',
        'school=1; Domain=example.edu.cn; Path=/',
      ]);
      expect(
        store.cookieHeaderFor(
          Uri.parse('https://jw.example.edu.cn/jwglxt/xtgl/a.html'),
        ),
        'JSESSIONID=abc; school=1',
      );
      // 子域能拿到 Domain Cookie，但拿不到 host-only 的那条。
      expect(
        store.cookieHeaderFor(Uri.parse('https://other.example.edu.cn/')),
        'school=1',
      );
      expect(
        store.cookieHeaderFor(Uri.parse('https://example.edu.cn.evil.test/')),
        '',
      );
    });

    test('Path 采用前缀 + 边界匹配，不会把 /jwglxt 的 Cookie 发给 /jwglxtx', () {
      final store = CookieStore(baseUrl: _base);
      store.setCookies(
        Uri.parse('https://jw.example.edu.cn/jwglxt/xtgl/login_slogin.html'),
        const ['a=1; Path=/jwglxt'],
      );
      expect(
        store.cookieHeaderFor(
          Uri.parse('https://jw.example.edu.cn/jwglxt/xtgl/x.html'),
        ),
        'a=1',
      );
      expect(
        store.cookieHeaderFor(
            Uri.parse('https://jw.example.edu.cn/jwglxtx/x.html')),
        '',
      );
    });

    test('过期的 Set-Cookie 等价于删除；Max-Age<=0 同理', () {
      final nowMs = DateTime.utc(2026, 0, 1).millisecondsSinceEpoch;
      final store = CookieStore(baseUrl: _base, now: () => nowMs);
      store.setCookies(Uri.parse(_base), const ['a=1; Path=/']);
      expect(store.cookieHeaderFor(Uri.parse(_base)), 'a=1');
      store.setCookies(Uri.parse(_base), const ['a=; Path=/; Max-Age=0']);
      expect(store.cookieHeaderFor(Uri.parse(_base)), '');
      expect(store.size, 0);

      store.setCookies(
        Uri.parse(_base),
        const ['b=2; Path=/; Expires=Wed, 21 Oct 2015 07:28:00 GMT'],
      );
      expect(store.size, 0, reason: '过去的时间点不应写入');
    });

    test('Expires 里的逗号不会把一条 Set-Cookie 拆成两条', () {
      final record = parseSetCookie(
        'sid=xyz; Expires=Wed, 21 Oct 2099 07:28:00 GMT; Path=/; Secure; HttpOnly',
        Uri.parse(_base),
        DateTime.utc(2026, 0, 1).millisecondsSinceEpoch,
      );
      expect(record, isNotNull);
      expect(record!.name, 'sid');
      expect(record.path, '/');
      expect(record.secure, isTrue);
      expect(record.httpOnly, isTrue);
      expect(
        record.expiresAt,
        DateTime.utc(2099, 10, 21, 7, 28, 0).millisecondsSinceEpoch,
      );
    });

    test('Secure Cookie 只在 https 下回发，且声明了非本机域名的 Cookie 会被丢弃', () {
      final store = CookieStore(baseUrl: _base);
      store.setCookies(
        Uri.parse('https://jw.example.edu.cn/jwglxt/'),
        const ['sec=1; Path=/; Secure'],
      );
      expect(
        store.cookieHeaderFor(Uri.parse('https://jw.example.edu.cn/jwglxt/')),
        'sec=1',
      );
      expect(
        store.cookieHeaderFor(Uri.parse('http://jw.example.edu.cn/jwglxt/')),
        '',
      );
      store.setCookies(
        Uri.parse('https://jw.example.edu.cn/jwglxt/'),
        const ['bad=1; Domain=evil.test; Path=/'],
      );
      expect(store.size, 1, reason: '域名不匹配的 Set-Cookie 必须被拒绝');
    });

    test('同名同域同路径覆盖，不产生重复条目', () {
      final store = CookieStore(baseUrl: _base);
      store.setCookies(Uri.parse(_base), const ['a=1; Path=/']);
      store.setCookies(Uri.parse(_base), const ['a=2; Path=/']);
      expect(store.size, 1);
      expect(store.cookieHeaderFor(Uri.parse(_base)), 'a=2');
      // 不同 path 是不同 Cookie，长 path 优先。
      store.setCookies(
        Uri.parse('https://jw.example.edu.cn/jwglxt/xtgl/x.html'),
        const ['a=3; Path=/jwglxt'],
      );
      expect(
        store.cookieHeaderFor(
          Uri.parse('https://jw.example.edu.cn/jwglxt/xtgl/x.html'),
        ),
        'a=3; a=2',
      );
      expect(store.cookieHeaderFor(Uri.parse('https://jw.example.edu.cn/')),
          'a=2');
    });

    test('header() 用构造时的教务根地址计算', () {
      final store = CookieStore(baseUrl: _base);
      store.setCookies(Uri.parse(_base), const ['a=1; Path=/']);
      expect(store.header(), 'a=1');
    });
  });

  group('CAS → 教务会话迁移', () {
    test('cookiesSetBy 能按来源回收 Cookie，adopt 只迁教务域的', () {
      final source = CookieStore();
      source.setCookies(
        Uri.parse('https://cas.example.edu.cn/cas/login'),
        const ['iPlanetDirectoryPro=ss0; Path=/'],
      );
      source.setCookies(
        Uri.parse('http://jw.example.edu.cn/jwglxt/ticketlogin?ticket=ST-1'),
        const ['JSESSIONID=teach; Path=/'],
      );
      expect(
        source.cookiesSetBy('cas.example.edu.cn', port: 443).map((r) => r.name),
        ['iPlanetDirectoryPro'],
      );
      expect(
        source.cookiesSetBy('jw.example.edu.cn', port: 80).map((r) => r.name),
        ['JSESSIONID'],
      );

      final teaching = CookieStore(baseUrl: 'http://jw.example.edu.cn/jwglxt');
      expect(
          teaching.adopt(source, 'jw.example.edu.cn', port: 80, secure: false),
          1);
      expect(
        teaching.cookieHeaderFor(
          Uri.parse('http://jw.example.edu.cn/jwglxt/xtgl/x.html'),
        ),
        'JSESSIONID=teach',
      );
      expect(teaching.size, 1, reason: 'CAS 域 Cookie 不应被迁移进来');
    });
  });

  group('快照持久化', () {
    test('导出 / 导入可完整往返，包含会话 Cookie 与过期时间', () {
      final store = CookieStore(baseUrl: _base);
      store.setCookies(Uri.parse('https://jw.example.edu.cn/jwglxt/'), const [
        'session=keep; Path=/',
        'ttl=3600; Path=/; Max-Age=3600',
      ]);
      final snapshot = store.export();
      expect(snapshot.version, 1);
      expect(snapshot.baseUrl, _base);

      // 经 JSON 往返，模拟真实落盘 / 读盘。
      final restored = CookieStore.fromSnapshot(
        CookieStoreSnapshot.fromJson(
          jsonDecode(jsonEncode(snapshot.toJson())) as Map<String, dynamic>,
        ),
      );
      expect(restored.size, 2);
      expect(
        restored.cookieHeaderFor(Uri.parse(_base)),
        store.cookieHeaderFor(Uri.parse(_base)),
      );
      final session = restored.list().firstWhere((r) => r.name == 'session');
      expect(session.expiresAt, isNull, reason: '会话 Cookie 必须保持无过期时间');
      final ttl = restored.list().firstWhere((r) => r.name == 'ttl');
      expect(
        ttl.expiresAt,
        greaterThan(DateTime.now().millisecondsSinceEpoch),
        reason: '带 Max-Age 的 Cookie 必须保留绝对时间',
      );
    });

    test('导入时会丢弃已经过期的条目', () {
      final snapshot = CookieStoreSnapshot(
        version: 1,
        baseUrl: _base,
        savedAt: 0,
        cookies: const [
          CookieRecord(
            name: 'old',
            value: '1',
            domain: 'jw.example.edu.cn',
            path: '/',
            hostOnly: true,
            secure: false,
            httpOnly: false,
            expiresAt: 1000,
            createdAt: 0,
            setByHost: 'jw.example.edu.cn',
            setByPort: 443,
          ),
          CookieRecord(
            name: 'alive',
            value: '1',
            domain: 'jw.example.edu.cn',
            path: '/',
            hostOnly: true,
            secure: false,
            httpOnly: false,
            expiresAt: null,
            createdAt: 0,
            setByHost: 'jw.example.edu.cn',
            setByPort: 443,
          ),
        ],
      );
      final store = CookieStore.fromSnapshot(snapshot);
      expect(store.list().map((r) => r.name), ['alive']);
    });

    test('直接导入 Cookie 头字符串（从 WebView/浏览器复制出来的会话）', () {
      final store = CookieStore.fromCookieHeader(
        'JSESSIONID=fromBrowser; route=abc',
        Uri.parse(_base),
      );
      expect(store.cookieHeaderFor(Uri.parse(_base)),
          'JSESSIONID=fromBrowser; route=abc');
      expect(store.list().first.hostOnly, isTrue);
      expect(store.list().first.path, '/');
    });

    test('invalidate 清空 Cookie 并递增世代；世代可用于判定旧回调失效', () {
      final store = CookieStore(baseUrl: _base);
      store.setCookies(Uri.parse(_base), const ['a=1; Path=/']);
      final before = store.generation;
      store.invalidate();
      expect(store.size, 0);
      expect(store.generation, before + 1);
    });

    test('格式错误的快照版本直接报错', () {
      expect(
        () => CookieStore.fromSnapshot(
          const CookieStoreSnapshot(
            version: 2,
            baseUrl: _base,
            savedAt: 0,
            cookies: [],
          ),
        ),
        throwsA(isA<AcademicError>()),
      );
    });
  });
}
