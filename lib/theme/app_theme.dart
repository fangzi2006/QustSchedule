/// 应用主题与滚动行为。
///
/// 两件事：
///  1. 浅色主题（这一版不做暗色：彩色格子"浅底深字"在暗色下必须整套反转）；
///  2. **允许鼠标拖动**——Flutter 桌面默认只让触摸拖拽生效，
///     不配这个的话课表左右翻周、时间轮在 Windows 上都拖不动，只能滚轮。
library;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../widgets/app_menu.dart' show AppMenuScope;

/// 品牌主色：偏靛蓝，和课程色板里的蓝/青/紫相邻但不冲突。
const Color _seed = Color(0xFF3F5AA6);

/// 页面底色：比纯白略灰，让白色卡片浮起来。
const Color _canvas = Color(0xFFF6F7F9);

/// 全工程统一圆角等级规范（特殊同心圆/课表块 8dp/胶囊 999dp 等除外）：
/// - [card] (20dp)：主卡片、底部抽屉、弹出菜单、悬浮容器
/// - [medium] (14dp)：输入框、块级按钮、提示横幅、嵌套子卡片
/// - [small] (8dp)：小色块、内嵌列表块、进度条
/// - [micro] (6dp)：极小状态标签与徽章
abstract final class AppRadius {
  static const double card = 20.0;
  static const double medium = 14.0;
  static const double small = 8.0;
  static const double micro = 6.0;
  static const double pill = 999.0;
}

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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
      ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.medium),
        ),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerLowest,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(AppRadius.medium),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surfaceContainerLowest,
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.card),
        ),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      dismissDirection: DismissDirection.horizontal,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.card),
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

/// 页面进出转场：全宽**水平位移** + 轻量边缘投影与背层微暗（不用离屏透明与整页快照）。
///
/// ## 为什么旧版会"半路突然切掉"且"返回加速过快"
///
/// 1. 旧版 `_enterDistance = 0.28` 只滑了 28% 屏宽且无透明过渡：进入第 0 帧 72% 画面瞬间突入，
///    返回到终点（`animation = 0`）时仍有 72% 页面遮挡在屏幕上随后一帧直接消失；
/// 2. 旧版把 `Curves.easeOutCubic` 直接用于反向（`1 -> 0`），导致退出时变成 `easeInCubic`：
///    刚点返回时几乎不动，越接近退场结束速度越快（3 倍末速度直接撞停消失）；
/// 3. 旧版 `if (route.isFirst) return child;` 跳过了首页的 `secondaryAnimation` 联动。
///
/// ## 现方案设计
///
/// - **全宽位移（`1.0 <-> 0.0`）**：入场从屏幕右侧外完整滑入，退场完整滑出到右侧之外才销毁，
///   彻底消除半途截断感；背层同步轻微左移（`-0.24`）并叠加单矩形微暗遮罩（最大 6% 黑色），
///   无需 `Opacity`/`FadeTransition` 整页离屏 `saveLayer`，也不用 `SnapshotWidget` 整页纹理快照。
/// - **连续双向缓动（[_ContinuousCurveAnimation]）**：正向入场与正常反向退场均呈“起步跟手、
///   收尾柔和减速”；若入场尚未播完用户就点击返回（或动画中途折返），直接从**当前视觉进度**
///   平滑衔接折返至目标端点，绝不跳帧、不闪回、不卡顿。
/// - **入场期间即可交互**：不使用静态快照，不阻塞点击/滚动，命中测试随 `SlideTransition` 实时跟随。
class _SlideTransitionsBuilder extends PageTransitionsBuilder {
  const _SlideTransitionsBuilder();

  /// 旧页被推走时的视差位移（占页宽的比例）。
  static const double _exitParallaxDistance = 0.24;

  static const Curve _curve = Curves.easeOutCubic;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 240);

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return _SmoothSlidePageTransition(
      route: route,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      exitParallaxDistance: _exitParallaxDistance,
      curve: _curve,
      child: child,
    );
  }
}

class _SmoothSlidePageTransition extends StatefulWidget {
  const _SmoothSlidePageTransition({
    required this.route,
    required this.animation,
    required this.secondaryAnimation,
    required this.exitParallaxDistance,
    required this.curve,
    required this.child,
  });

  final PageRoute<dynamic> route;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final double exitParallaxDistance;
  final Curve curve;
  final Widget child;

  @override
  State<_SmoothSlidePageTransition> createState() =>
      _SmoothSlidePageTransitionState();
}

class _SmoothSlidePageTransitionState
    extends State<_SmoothSlidePageTransition> {
  late _ContinuousCurveAnimation _primaryVisual;
  late _ContinuousCurveAnimation _secondaryVisual;
  late Animation<Offset> _primaryOffset;
  late Animation<Offset> _secondaryOffset;

  @override
  void initState() {
    super.initState();
    _initAnimations();
  }

  void _initAnimations() {
    _primaryVisual = _ContinuousCurveAnimation(
      parent: widget.animation,
      curve: widget.curve,
    );
    _secondaryVisual = _ContinuousCurveAnimation(
      parent: widget.secondaryAnimation,
      curve: widget.curve,
    );
    _bindOffsets();
  }

  void _bindOffsets() {
    final beginOffset = widget.route.fullscreenDialog
        ? const Offset(0.0, 1.0)
        : const Offset(1.0, 0.0);
    _primaryOffset = _primaryVisual.drive(
      Tween<Offset>(begin: beginOffset, end: Offset.zero),
    );
    _secondaryOffset = _secondaryVisual.drive(
      Tween<Offset>(
        begin: Offset.zero,
        end: Offset(-widget.exitParallaxDistance, 0.0),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant _SmoothSlidePageTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    final primaryChanged = oldWidget.animation != widget.animation;
    final secondaryChanged =
        oldWidget.secondaryAnimation != widget.secondaryAnimation;
    final curveChanged = oldWidget.curve != widget.curve;
    final dialogChanged =
        oldWidget.route.fullscreenDialog != widget.route.fullscreenDialog;
    final parallaxChanged =
        oldWidget.exitParallaxDistance != widget.exitParallaxDistance;

    if (primaryChanged || curveChanged) {
      _primaryVisual.dispose();
      _primaryVisual = _ContinuousCurveAnimation(
        parent: widget.animation,
        curve: widget.curve,
      );
    }
    if (secondaryChanged || curveChanged) {
      _secondaryVisual.dispose();
      _secondaryVisual = _ContinuousCurveAnimation(
        parent: widget.secondaryAnimation,
        curve: widget.curve,
      );
    }
    if (primaryChanged ||
        secondaryChanged ||
        curveChanged ||
        dialogChanged ||
        parallaxChanged) {
      _bindOffsets();
    }
  }

  @override
  void dispose() {
    _primaryVisual.dispose();
    _secondaryVisual.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = Directionality.maybeOf(context) ?? TextDirection.ltr;

    // 无论是否为首页，都保留 secondaryAnimation 的视差与微暗遮罩，
    // 并在转场位移内部挂载路由级 AppMenuScope，使二级页入场途中打开菜单也随页面同步滑入落位，
    // 并在页面退场或被上层路由覆盖时自动收起并拒绝继续展开。
    Widget content = CustomPaint(
      foregroundPainter: _RouteScrimPainter(progress: _secondaryVisual),
      child: AppMenuScope(child: widget.child),
    );

    if (!widget.route.isFirst && !widget.route.fullscreenDialog) {
      content = CustomPaint(
        painter: _EdgeShadowPainter(
          progress: _primaryVisual,
          textDirection: textDirection,
        ),
        child: content,
      );
    }

    content = SlideTransition(
      position: _secondaryOffset,
      textDirection: textDirection,
      child: content,
    );

    if (widget.route.isFirst) {
      return content;
    }

    return SlideTransition(
      position: _primaryOffset,
      textDirection: textDirection,
      child: content,
    );
  }
}

/// 将线性路由动画映射到连续双向缓动进度 `[0.0, 1.0]`：
/// - 完整正向与完整反向都从起点快启、终点柔顺减速；
/// - 动画中途改变方向时，以当前视觉进度为新起点无缝衔接至目标端点，绝不跳变。
class _ContinuousCurveAnimation extends Animation<double>
    with AnimationWithParentMixin<double> {
  _ContinuousCurveAnimation({required this.parent, required this.curve}) {
    _syncFromParentStatus(
      parent.status,
      raw: parent.value.clamp(0.0, 1.0),
      initialize: true,
    );
    parent.addStatusListener(_handleStatusChanged);
  }

  @override
  final Animation<double> parent;
  final Curve curve;

  AnimationStatus? _lastStatus;
  double _fromRaw = 0.0;
  double _toRaw = 1.0;
  double _fromVisual = 0.0;
  double _toVisual = 1.0;
  bool _disposed = false;

  void _syncFromParentStatus(
    AnimationStatus status, {
    required double raw,
    bool initialize = false,
  }) {
    final prevStatus = _lastStatus;
    _lastStatus = status;

    switch (status) {
      case AnimationStatus.dismissed:
      case AnimationStatus.completed:
        _fromRaw = 0.0;
        _toRaw = 1.0;
        _fromVisual = 0.0;
        _toVisual = 1.0;
      case AnimationStatus.forward:
        if (!initialize && prevStatus == AnimationStatus.forward) {
          return;
        }
        if (initialize || prevStatus != AnimationStatus.reverse) {
          _fromRaw = 0.0;
          _toRaw = 1.0;
          _fromVisual = 0.0;
          _toVisual = 1.0;
        } else {
          final currentVisual = _evaluate(raw, fromStatus: prevStatus);
          _fromRaw = raw;
          _toRaw = 1.0;
          _fromVisual = currentVisual;
          _toVisual = 1.0;
        }
      case AnimationStatus.reverse:
        if (!initialize && prevStatus == AnimationStatus.reverse) {
          return;
        }
        if (initialize || prevStatus != AnimationStatus.forward) {
          _fromRaw = 1.0;
          _toRaw = 0.0;
          _fromVisual = 1.0;
          _toVisual = 0.0;
        } else {
          final currentVisual = _evaluate(raw, fromStatus: prevStatus);
          _fromRaw = raw;
          _toRaw = 0.0;
          _fromVisual = currentVisual;
          _toVisual = 0.0;
        }
    }
  }

  void _handleStatusChanged(AnimationStatus status) {
    if (_disposed) return;
    _syncFromParentStatus(status, raw: parent.value.clamp(0.0, 1.0));
  }

  double _evaluate(double raw, {AnimationStatus? fromStatus}) {
    final effectiveStatus = fromStatus ?? _lastStatus;
    if (effectiveStatus == AnimationStatus.forward && raw < _fromRaw - 1e-6) {
      _fromRaw = 0.0;
      _toRaw = 1.0;
      _fromVisual = 0.0;
      _toVisual = 1.0;
    } else if (effectiveStatus == AnimationStatus.reverse &&
        raw > _fromRaw + 1e-6) {
      _fromRaw = 1.0;
      _toRaw = 0.0;
      _fromVisual = 1.0;
      _toVisual = 0.0;
    }
    final span = _toRaw - _fromRaw;
    if (span.abs() < 1e-6) {
      return _toVisual;
    }
    final u = ((raw - _fromRaw) / span).clamp(0.0, 1.0);
    final c = curve.transform(u);
    return _fromVisual + (_toVisual - _fromVisual) * c;
  }

  @override
  double get value {
    final status = parent.status;
    final raw = parent.value.clamp(0.0, 1.0);
    if (status != _lastStatus) {
      _syncFromParentStatus(status, raw: raw);
    }
    if (status == AnimationStatus.dismissed) return 0.0;
    if (status == AnimationStatus.completed) return 1.0;
    return _evaluate(raw);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    parent.removeStatusListener(_handleStatusChanged);
  }
}

/// 分段纯色矩形绘制的页面左边缘投影：不触发线性渐变着色器编译，也不创建离屏图层。
class _EdgeShadowPainter extends CustomPainter {
  _EdgeShadowPainter({required this.progress, required this.textDirection})
    : super(repaint: progress);

  final Animation<double> progress;
  final TextDirection textDirection;

  static const double _shadowWidth = 16.0;
  static const int _bandCount = 8;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    if (p <= 0.001 || p >= 0.999) return;
    final edgeFade = ((1.0 - p) * 6.0).clamp(0.0, 1.0);
    final maxAlpha = 0.08 * edgeFade;
    if (maxAlpha <= 0.001) return;

    final bandWidth = _shadowWidth / _bandCount;
    final paint = Paint()..isAntiAlias = false;
    final isRtl = textDirection == TextDirection.rtl;

    for (var i = 0; i < _bandCount; i++) {
      final t = (i + 1) / _bandCount;
      final alpha = maxAlpha * t * t;
      paint.color = Colors.black.withValues(alpha: alpha);
      final left = isRtl
          ? size.width + (_bandCount - 1 - i) * bandWidth
          : -(_bandCount - i) * bandWidth;
      canvas.drawRect(Rect.fromLTWH(left, 0, bandWidth, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(_EdgeShadowPainter oldDelegate) =>
      oldDelegate.progress != progress ||
      oldDelegate.textDirection != textDirection;
}

/// 覆盖在背层页面上的轻量微暗遮罩（单矩形纯色绘制，无 `saveLayer` 离屏开销）。
class _RouteScrimPainter extends CustomPainter {
  _RouteScrimPainter({required this.progress}) : super(repaint: progress);

  final Animation<double> progress;

  @override
  void paint(Canvas canvas, Size size) {
    final p = progress.value;
    if (p <= 0.001) return;
    final alpha = 0.06 * p.clamp(0.0, 1.0);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.black.withValues(alpha: alpha),
    );
  }

  @override
  bool shouldRepaint(_RouteScrimPainter oldDelegate) =>
      oldDelegate.progress != progress;
}
