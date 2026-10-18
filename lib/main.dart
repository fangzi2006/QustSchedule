/// 青科课表通 —— Flutter 跨 Windows/Android 客户端。
///
/// 分层：
///   pages（UI）→ AppModel（状态机）→ ScheduleService（编排）→ zf_academic（协议）
///
/// 已登录后进 [HomeShell] 的两页结构（课表 / 设置 + 悬浮 dock）；
/// 未登录与验证码是独立全屏页，不显示 dock。
library;

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/captcha_page.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'src/app_model.dart';
import 'theme/app_theme.dart';

void main() {
  runApp(const CourseApp());
}

class CourseApp extends StatelessWidget {
  const CourseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '青科课表通',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(),
      // 桌面端允许鼠标/触控板拖拽（翻周、时间轮都依赖它）。
      scrollBehavior: AppScrollBehavior(),
      locale: const Locale('zh', 'CN'),
      supportedLocales: const <Locale>[Locale('zh', 'CN'), Locale('en')],
      localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: const _AppShell(),
    );
  }
}

/// 按状态切换「登录 / 验证码 / 两页外壳」。
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final AppModel _model = AppModel();

  @override
  void initState() {
    super.initState();
    _model.boot();
  }

  @override
  void dispose() {
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model,
      builder: (BuildContext context, _) => pageForStatus(_model),
    );
  }
}

/// 状态 → 该显示哪个页面。
///
/// 抽成函数是为了能测路由：这里判错一次，用户打错密码就会直接被丢到
/// 一张空课表上（而不是留在表单前面）。
@visibleForTesting
Widget pageForStatus(AppModel model) {
  switch (model.status) {
    case AppStatus.booting:
      return const _BootScreen();
    case AppStatus.needLogin:
      return LoginPage(model: model);
    case AppStatus.needCaptcha:
      return CaptchaPage(model: model);
    case AppStatus.signingIn:
      // 登录还没成功：留在原地。验证码挑战还在就回验证码页。
      return model.captcha != null
          ? CaptchaPage(model: model)
          : LoginPage(model: model);
    case AppStatus.failed:
      // 会话过期、或者压根没拿到过课表 → 回登录页（错误以弹窗显示）；
      // 有课表就留在课表页，错误弹窗浮在上面。
      if (model.errorCode == 'SESSION_EXPIRED' || model.schedule == null) {
        return LoginPage(model: model);
      }
      return HomeShell(model: model);
    case AppStatus.loading:
    case AppStatus.ready:
      return HomeShell(model: model);
  }
}

class _BootScreen extends StatelessWidget {
  const _BootScreen();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.calendar_month_rounded,
                color: scheme.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 18),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(height: 12),
            Text(
              '正在连接教务系统…',
              style: TextStyle(
                fontSize: 13,
                color: Theme.of(context).hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
