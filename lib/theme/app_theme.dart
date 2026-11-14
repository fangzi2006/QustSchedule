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

/// 全工程语义色扩展，集中收口未纳入默认 [ColorScheme] 的业务与状态颜色。
///
/// 当前仅配置浅色令牌 [light]；后续接入深色主题时只需补充对应的深色实例即可。
@immutable
class AppColors extends ThemeExtension<AppColors> {
  const AppColors({
    required this.success,
    required this.successContainer,
    required this.warning,
    required this.warningStrong,
    required this.warningChipBg,
    required this.warningBannerBg,
    required this.warningBannerBorder,
    required this.onWarningBanner,
    required this.danger,
    required this.dangerContainer,
    required this.scoreExcellent,
    required this.gridLine,
    required this.timeAxisText,
    required this.conflictCardBg,
    required this.conflictDot,
    required this.conflictBadge,
    required this.examOngoingBg,
    required this.examUrgentBg,
    required this.examTomorrowBg,
    required this.onExamAccentBadge,
    required this.categoryAdd,
    required this.categoryImprove,
    required this.categoryFix,
    required this.categoryNote,
    required this.captchaSurface,
  });

  /// 浅色默认令牌表（与历史视觉完全一致，不随系统切换产生偏移）。
  static const AppColors light = AppColors(
    success: Color(0xFF2E7D32),
    successContainer: Color(0xFFE8F5E9),
    warning: Color(0xFFB26A00),
    warningStrong: Color(0xFFE65100),
    warningChipBg: Color(0xFFFFF3E0),
    warningBannerBg: Color(0x26FFC107),
    warningBannerBorder: Color(0x66FFA000),
    onWarningBanner: Color(0xFFFF6F00),
    danger: Color(0xFFC62828),
    dangerContainer: Color(0xFFFFEBEE),
    scoreExcellent: Color(0xFF009688),
    gridLine: Color(0xFFE4E6EB),
    timeAxisText: Color(0xFF8C929B),
    conflictCardBg: Color(0xFFFFE9A8),
    conflictDot: Color(0xFFE6A700),
    conflictBadge: Color(0xFFE53935),
    examOngoingBg: Color(0xFFFF9800),
    examUrgentBg: Color(0xFFFF5252),
    examTomorrowBg: Color(0xFFFFAB40),
    onExamAccentBadge: Colors.white,
    categoryAdd: Color(0xFF2E7D32),
    categoryImprove: Color(0xFF1976D2),
    categoryFix: Color(0xFFE65100),
    categoryNote: Color(0xFF7B1FA2),
    // 教务系统验证码为深色文字配浅底/透明底图片，任何主题下都需保持浅画布确保可读性。
    captchaSurface: Colors.white,
  );

  final Color success;
  final Color successContainer;
  final Color warning;
  final Color warningStrong;
  final Color warningChipBg;
  final Color warningBannerBg;
  final Color warningBannerBorder;
  final Color onWarningBanner;
  final Color danger;
  final Color dangerContainer;
  final Color scoreExcellent;
  final Color gridLine;
  final Color timeAxisText;
  final Color conflictCardBg;
  final Color conflictDot;
  final Color conflictBadge;
  final Color examOngoingBg;
  final Color examUrgentBg;
  final Color examTomorrowBg;
  final Color onExamAccentBadge;
  final Color categoryAdd;
  final Color categoryImprove;
  final Color categoryFix;
  final Color categoryNote;
  final Color captchaSurface;

  /// 安全获取当前主题下的语义色表（裸 MaterialApp 测试未挂主题时回退至 [light]）。
  static AppColors of(BuildContext context) =>
      Theme.of(context).extension<AppColors>() ?? light;

  @override
  AppColors copyWith({
    Color? success,
    Color? successContainer,
    Color? warning,
    Color? warningStrong,
    Color? warningChipBg,
    Color? warningBannerBg,
    Color? warningBannerBorder,
    Color? onWarningBanner,
    Color? danger,
    Color? dangerContainer,
    Color? scoreExcellent,
    Color? gridLine,
    Color? timeAxisText,
    Color? conflictCardBg,
    Color? conflictDot,
    Color? conflictBadge,
    Color? examOngoingBg,
    Color? examUrgentBg,
    Color? examTomorrowBg,
    Color? onExamAccentBadge,
    Color? categoryAdd,
    Color? categoryImprove,
    Color? categoryFix,
    Color? categoryNote,
    Color? captchaSurface,
  }) {
    return AppColors(
      success: success ?? this.success,
      successContainer: successContainer ?? this.successContainer,
      warning: warning ?? this.warning,
      warningStrong: warningStrong ?? this.warningStrong,
      warningChipBg: warningChipBg ?? this.warningChipBg,
      warningBannerBg: warningBannerBg ?? this.warningBannerBg,
      warningBannerBorder: warningBannerBorder ?? this.warningBannerBorder,
      onWarningBanner: onWarningBanner ?? this.onWarningBanner,
      danger: danger ?? this.danger,
      dangerContainer: dangerContainer ?? this.dangerContainer,
      scoreExcellent: scoreExcellent ?? this.scoreExcellent,
      gridLine: gridLine ?? this.gridLine,
      timeAxisText: timeAxisText ?? this.timeAxisText,
      conflictCardBg: conflictCardBg ?? this.conflictCardBg,
      conflictDot: conflictDot ?? this.conflictDot,
      conflictBadge: conflictBadge ?? this.conflictBadge,
      examOngoingBg: examOngoingBg ?? this.examOngoingBg,
      examUrgentBg: examUrgentBg ?? this.examUrgentBg,
      examTomorrowBg: examTomorrowBg ?? this.examTomorrowBg,
      onExamAccentBadge: onExamAccentBadge ?? this.onExamAccentBadge,
      categoryAdd: categoryAdd ?? this.categoryAdd,
      categoryImprove: categoryImprove ?? this.categoryImprove,
      categoryFix: categoryFix ?? this.categoryFix,
      categoryNote: categoryNote ?? this.categoryNote,
      captchaSurface: captchaSurface ?? this.captchaSurface,
    );
  }

  @override
  AppColors lerp(covariant ThemeExtension<AppColors>? other, double t) {
    if (other is! AppColors) return this;
    return AppColors(
      success: Color.lerp(success, other.success, t) ?? success,
      successContainer:
          Color.lerp(successContainer, other.successContainer, t) ??
          successContainer,
      warning: Color.lerp(warning, other.warning, t) ?? warning,
      warningStrong:
          Color.lerp(warningStrong, other.warningStrong, t) ?? warningStrong,
      warningChipBg:
          Color.lerp(warningChipBg, other.warningChipBg, t) ?? warningChipBg,
      warningBannerBg:
          Color.lerp(warningBannerBg, other.warningBannerBg, t) ??
          warningBannerBg,
      warningBannerBorder:
          Color.lerp(warningBannerBorder, other.warningBannerBorder, t) ??
          warningBannerBorder,
      onWarningBanner:
          Color.lerp(onWarningBanner, other.onWarningBanner, t) ??
          onWarningBanner,
      danger: Color.lerp(danger, other.danger, t) ?? danger,
      dangerContainer:
          Color.lerp(dangerContainer, other.dangerContainer, t) ??
          dangerContainer,
      scoreExcellent:
          Color.lerp(scoreExcellent, other.scoreExcellent, t) ?? scoreExcellent,
      gridLine: Color.lerp(gridLine, other.gridLine, t) ?? gridLine,
      timeAxisText:
          Color.lerp(timeAxisText, other.timeAxisText, t) ?? timeAxisText,
      conflictCardBg:
          Color.lerp(conflictCardBg, other.conflictCardBg, t) ?? conflictCardBg,
      conflictDot: Color.lerp(conflictDot, other.conflictDot, t) ?? conflictDot,
      conflictBadge:
          Color.lerp(conflictBadge, other.conflictBadge, t) ?? conflictBadge,
      examOngoingBg:
          Color.lerp(examOngoingBg, other.examOngoingBg, t) ?? examOngoingBg,
      examUrgentBg:
          Color.lerp(examUrgentBg, other.examUrgentBg, t) ?? examUrgentBg,
      examTomorrowBg:
          Color.lerp(examTomorrowBg, other.examTomorrowBg, t) ?? examTomorrowBg,
      onExamAccentBadge:
          Color.lerp(onExamAccentBadge, other.onExamAccentBadge, t) ??
          onExamAccentBadge,
      categoryAdd: Color.lerp(categoryAdd, other.categoryAdd, t) ?? categoryAdd,
      categoryImprove:
          Color.lerp(categoryImprove, other.categoryImprove, t) ??
          categoryImprove,
      categoryFix: Color.lerp(categoryFix, other.categoryFix, t) ?? categoryFix,
      categoryNote:
          Color.lerp(categoryNote, other.categoryNote, t) ?? categoryNote,
      captchaSurface:
          Color.lerp(captchaSurface, other.captchaSurface, t) ?? captchaSurface,
    );
  }
}

ThemeData buildLightTheme() {
  final scheme = ColorScheme.fromSeed(
    seedColor: _seed,
    brightness: Brightness.light,
  ).copyWith(surfaceContainerLowest: Colors.white);
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: _canvas,
    extensions: const <ThemeExtension<dynamic>>[AppColors.light],
    splashFactory: NoSplash.splashFactory,
    highlightColor: scheme.primary.withValues(alpha: 0.07),
    hoverColor: scheme.primary.withValues(alpha: 0.04),
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
      color: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.horizontal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(
          color: scheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      backgroundColor: scheme.surface,
      contentTextStyle: TextStyle(
        color: scheme.onSurface,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      elevation: 3,
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
