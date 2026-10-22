/// 应用主题与滚动行为。
///
/// 两件事：
///  1. 浅色主题（这一版不做暗色：彩色格子"浅底深字"在暗色下必须整套反转）；
///  2. **允许鼠标拖动**——Flutter 桌面默认只让触摸拖拽生效，
///     不配这个的话课表左右翻周、时间轮在 Windows 上都拖不动，只能滚轮。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// 品牌主色：偏靛蓝，和课程色板里的蓝/青/紫相邻但不冲突。
const Color _seed = Color(0xFF3F5AA6);

/// 页面底色：比纯白略灰，让白色卡片浮起来。
const Color _canvas = Color(0xFFF6F7F9);

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.light,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _canvas,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: _canvas,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 18,
        fontWeight: FontWeight.w500,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      // 必须裁剪：否则 InkWell 的 hover/点击水波画出方形，在圆角卡片外面露出直角阴影。
      clipBehavior: Clip.antiAlias,
      margin: EdgeInsets.zero,
    ),
    // 页面进出用一个短促的**水平位移**（见 [_SlideTransitionsBuilder]）：
    // 淡入淡出要给整页做离屏合成，桌面端每帧都做一次太贵。
    // 只列本项目实际发布的平台；其余平台走框架默认。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _SlideTransitionsBuilder(),
        TargetPlatform.windows: _SlideTransitionsBuilder(),
        TargetPlatform.linux: _SlideTransitionsBuilder(),
        TargetPlatform.fuchsia: _SlideTransitionsBuilder(),
      },
    ),
    dividerTheme: DividerThemeData(
      color: scheme.outlineVariant.withValues(alpha: 0.5),
      thickness: 0.5,
      space: 0.5,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ),
  );
}

/// 允许鼠标、触控板、触屏、手写笔都能拖拽。
///
/// 桌面端默认只有触摸能拖，会让 PageView（左右翻周）和时间轮"拖不动"。
class AppScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => <PointerDeviceKind>{
    PointerDeviceKind.touch,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  };
}

/// 页面进出转场：短促的**水平位移**（不用淡入淡出）。
///
/// 为什么不用默认的 zoom 转场：它要 300ms、带缩放与整页快照，画面在动的
/// 时间更长，期间点下一条会像"没反应"。这里换成短促的位移：进入 220ms、
/// 退出 180ms（退出更快，回到上一页更跟手）。
///
/// ## 为什么不用淡入淡出
///
/// [FadeTransition] 内部是 [Opacity]，而 [Opacity] 在 0 < alpha < 1 时
/// 必须把整页画进一个**离屏缓冲**再合成——框架源码里对这个分支的注释
/// 直接写着 "expensive"。设置页里的子页面（作息表列表、教务地址、调试信息…）
/// 本身内容不少，动画期间每帧都来一次全页离屏合成，就是"点进子页面时卡一下"
/// 的来源。
///
/// 纯位移只改变换矩阵，不产生离屏缓冲：帧内只重绘"多出来的那一条"，
/// 两页各自的像素被缓存复用。
///
/// ## 位移的方向
///
/// 进入时新页从**右侧**推入、旧页往左让一点（iOS 的 push 观感）；
/// 退出时反过来。这样"往里点 = 往左推"，与外壳的横向翻页是同一套语言。
class _SlideTransitionsBuilder extends PageTransitionsBuilder {
  const _SlideTransitionsBuilder();

  /// 新页从右侧推入的距离（占页宽的比例）。
  static const double _enterDistance = 0.28;

  /// 旧页被推走时的位移（占页宽的比例）。
  static const double _exitDistance = 0.12;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 220);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 180);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // 首个页面（启动直达）不需要转场。
    if (route.isFirst) return child;

    // 新页：随 primary 动画从右侧推进来。
    final Animation<Offset> enter = animation.drive(
      Tween<Offset>(
        begin: const Offset(_enterDistance, 0),
        end: Offset.zero,
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    // 旧页：随 secondary 动画（上一层路由的动画）往左让一点。
    final Animation<Offset> exit = secondaryAnimation.drive(
      Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-_exitDistance, 0),
      ).chain(CurveTween(curve: Curves.easeOutCubic)),
    );
    return SlideTransition(
      position: enter,
      child: SlideTransition(position: exit, child: child),
    );
  }
}
