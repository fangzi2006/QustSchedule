/// 青科课表通 —— Flutter 跨 Windows/Android 客户端。
///
/// 分层：
///   pages（UI）→ AppModel（状态机）→ ScheduleService（编排）→ zf_academic（协议）
///
/// 已登录后进 [HomeShell] 的三页结构（课表 / 学业 / 设置 + 悬浮 dock）；
/// 未登录与验证码是独立全屏页，不显示 dock。
library;

import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'pages/captcha_page.dart';
import 'pages/home_shell.dart';
import 'pages/login_page.dart';
import 'src/app_model.dart';
import 'src/app_version.dart';
import 'src/reminder_service.dart';
import 'src/widget_service.dart';
import 'theme/app_theme.dart';
import 'widgets/app_menu.dart' show AppMenuScope;
import 'widgets/app_snack_bar.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // 版本号从打包进来的 pubspec.yaml 读，界面不写死。
  //
  // 但**不能在 runApp 之前 await**：那等于让首帧先去读一次 asset，白等一个
  // 资源往返。它只是设置页里的一行字，让它和首帧并行读，读不到就显示 `-`。
  unawaited(loadAppVersion());
  runApp(const CourseApp());
}

class CourseApp extends StatelessWidget {
  const CourseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '青科课表通',
      debugShowCheckedModeBanner: false,
      theme: buildLightTheme(
        routeWrapper: (BuildContext context, Widget child) =>
            AppMenuScope(child: child),
      ),
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

/// 按状态切换「登录 / 验证码 / 三页外壳」。
class _AppShell extends StatefulWidget {
  const _AppShell();

  @override
  State<_AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<_AppShell> {
  final AppModel _model = AppModel();

  /// 课程提醒编排层：只有 Android 有原生闹钟通道，桌面端不建。
  ///
  /// 建它的时候会向 model 注册监听：课表刷新、改调课、改作息、改设置
  /// 都会防抖后重排一次提醒。
  late final ReminderService? _reminders;

  /// 桌面小组件编排层：仅 Android 有原生桌面小组件，桌面端不建。
  late final DesktopWidgetService? _desktopWidgets;

  /// 前后台切换监听：
  /// - `onShow`（`hidden → inactive`）：校正跨天日期/周次与按需静默刷新；
  /// - `onResume`（`inactive → resumed`）：应用真正落稳前台后延时兜底同步提醒与小组件；
  /// - `onInactive` / `onHide`：一旦开始退回桌面或失去焦点，立即取消尚未触发的延时强刷，
  ///   杜绝在缩回桌面小组件动画途中抢占 UI 线程或向系统桌面推送更新。
  late final AppLifecycleListener _lifecycle;
  Timer? _foregroundSyncTimer;
  DateTime? _lastForegroundForceSyncAt;
  static const Duration _foregroundForceSyncCooldown = Duration(seconds: 60);
  int _lastStorageNoticeEvent = 0;
  bool _storageNoticeScheduled = false;

  @override
  void initState() {
    super.initState();
    // 在 boot() 之前初始化并挂载监听，避免冷启动或首登完成时错过首次 ready 通知。
    _reminders = defaultTargetPlatform == TargetPlatform.android
        ? ReminderService(model: _model)
        : null;
    _desktopWidgets = defaultTargetPlatform == TargetPlatform.android
        ? DesktopWidgetService(model: _model)
        : null;
    _model.hints.addListener(_onModelChanged);
    _model.routeNotifier.addListener(_onModelChanged);
    _model.boot();
    _lifecycle = AppLifecycleListener(
      onShow: () => unawaited(_onShown()),
      onResume: _scheduleForegroundSyncIfNeeded,
      onInactive: _cancelForegroundSyncTimer,
      onHide: _cancelForegroundSyncTimer,
    );
  }

  void _onModelChanged() {
    if (!mounted || _model.status == AppStatus.booting) return;
    final event = _model.storageNoticeEvent;
    final message = _model.storageNoticeMessage;
    if (event == _lastStorageNoticeEvent ||
        message == null ||
        message.isEmpty) {
      return;
    }
    if (_storageNoticeScheduled) return;
    _storageNoticeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _storageNoticeScheduled = false;
      if (!mounted || _model.status == AppStatus.booting) return;
      final latestEvent = _model.storageNoticeEvent;
      final latestMessage = _model.storageNoticeMessage;
      if (latestEvent == _lastStorageNoticeEvent ||
          latestMessage == null ||
          latestMessage.isEmpty) {
        return;
      }
      _lastStorageNoticeEvent = latestEvent;
      showAppSnackBar(
        context,
        message: latestMessage,
        type: AppSnackBarType.error,
        aboveDock: _model.status == AppStatus.ready,
        duration: const Duration(seconds: 4),
      );
    });
  }

  bool get _isLifecycleResumed {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  void _cancelForegroundSyncTimer() {
    _foregroundSyncTimer?.cancel();
    _foregroundSyncTimer = null;
  }

  /// 回到前台：先校正日期/周次，再在真正处于前台活跃态时安排提醒与小组件兜底恢复。
  ///
  /// 提醒**必须强制重排**：系统会在 force-stop、一键清理、覆盖安装时
  /// 清空闹钟，而指纹没变——不 force 就会漏排。
  Future<void> _onShown() async {
    await _model.onAppShown();
    if (!mounted || !_isLifecycleResumed) return;
    _scheduleForegroundSyncIfNeeded();
  }

  void _scheduleForegroundSyncIfNeeded() {
    if (!mounted || !_isLifecycleResumed) return;
    if (_reminders == null && _desktopWidgets == null) return;

    // 短时间内在桌面小组件与应用之间频繁来回切换时，进程未被系统杀掉，
    // 真正的数据/样式变更已由监听者自动同步，无需每次切回都在动画期间强刷提醒与小组件。
    final now = DateTime.now();
    final last = _lastForegroundForceSyncAt;
    final sameDay =
        last != null &&
        last.year == now.year &&
        last.month == now.month &&
        last.day == now.day;
    if (sameDay && now.difference(last) < _foregroundForceSyncCooldown) {
      return;
    }

    // 提醒与桌面小组件的回前台兜底刷新统一延后至进场缩放动画落稳后再执行，
    // 避免第 0 帧在 UI 线程同步规划 14 天日程/JSON 序列化与 Binder 通信引发掉帧；
    // 若 600ms 内用户已开始退回桌面（进入 inactive/hidden），定时器会被立即取消。
    _foregroundSyncTimer?.cancel();
    _foregroundSyncTimer = Timer(const Duration(milliseconds: 600), () {
      _foregroundSyncTimer = null;
      if (!mounted || !_isLifecycleResumed) return;
      _lastForegroundForceSyncAt = DateTime.now();
      if (_reminders != null) {
        unawaited(_reminders.syncNow(force: true));
      }
      if (_desktopWidgets != null) {
        unawaited(_desktopWidgets.syncNow(force: true));
      }
    });
  }

  @override
  void dispose() {
    _cancelForegroundSyncTimer();
    _lifecycle.dispose();
    _model.hints.removeListener(_onModelChanged);
    _model.routeNotifier.removeListener(_onModelChanged);
    // 先停编排（它监听 model），再销毁 model。
    _reminders?.dispose();
    _desktopWidgets?.dispose();
    _model.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _model.routeNotifier,
      builder: (BuildContext context, _) => pageForStatus(
        _model,
        reminders: _reminders,
        desktopWidgets: _desktopWidgets,
      ),
    );
  }
}

/// 状态 → 该显示哪个页面。
///
/// 抽成函数是为了能测路由：这里判错一次，用户打错密码就会直接被丢到
/// 一张空课表上（而不是留在表单前面）。
@visibleForTesting
Widget pageForStatus(
  AppModel model, {
  ReminderService? reminders,
  DesktopWidgetService? desktopWidgets,
}) {
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
      // 压根没拿到过课表 → 回登录页（错误以弹窗显示）；
      // 有课表就留在课表页，错误弹窗浮在上面提供「重试 / 重新登录」，
      // 仅在用户主动点「重新登录」进入 needLogin 后才跳转登录页。
      if (model.schedule == null) {
        return LoginPage(model: model);
      }
      return HomeShell(
        model: model,
        reminders: reminders,
        desktopWidgets: desktopWidgets,
      );
    case AppStatus.loading:
    case AppStatus.ready:
      return HomeShell(
        model: model,
        reminders: reminders,
        desktopWidgets: desktopWidgets,
      );
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
              '正在连接教务系统...',
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
