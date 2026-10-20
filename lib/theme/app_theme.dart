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
    // 页面进出用一个短促的淡入，替代默认 300ms 的缩放转场（见 [_QuickFadeTransitionsBuilder]）。
    // 只列本项目实际发布的平台；其余平台走框架默认。
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: <TargetPlatform, PageTransitionsBuilder>{
        TargetPlatform.android: _QuickFadeTransitionsBuilder(),
        TargetPlatform.windows: _QuickFadeTransitionsBuilder(),
        TargetPlatform.linux: _QuickFadeTransitionsBuilder(),
        TargetPlatform.fuchsia: _QuickFadeTransitionsBuilder(),
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

/// 页面进出转场：200ms 淡入 + 很小的上移。
///
/// 为什么不用默认的 zoom 转场：它要 300ms、带缩放与快照，画面在动的时间更长，
/// 期间点下一条会像"没反应"；退出也一样拖沓。这里换成短促的淡入：
///  - 进入 200ms、退出 160ms（退出更快，回到上一页更跟手）；
///  - 只有 `FadeTransition` + 1.2% 位移，不做快照缩放，掉帧更少；
///  - 不额外包 `IgnorePointer`：框架只在 pop 阶段忽略"正在退出的那一页"
///    （routes.dart `_shouldIgnoreFocusRequest`），进入阶段页面一直可点。
class _QuickFadeTransitionsBuilder extends PageTransitionsBuilder {
  const _QuickFadeTransitionsBuilder();

  static final Animatable<Offset> _slide = Tween<Offset>(
    begin: const Offset(0, 0.012),
    end: Offset.zero,
  ).chain(CurveTween(curve: Curves.easeOutCubic));

  @override
  Duration get transitionDuration => const Duration(milliseconds: 200);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 160);

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
    return FadeTransition(
      opacity: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOut,
        reverseCurve: Curves.easeIn,
      ),
      child: SlideTransition(position: animation.drive(_slide), child: child),
    );
  }
}
