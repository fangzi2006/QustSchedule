/// 桌面小组件的样式配置模型、精选预设注册表与按类型独立持久化容器。
///
/// 面向后续扩展设计：
/// - 所有选项均带 `wireName` 与容错 `parse()`，未知枚举或字段平稳回落默认值；
/// - 样式按 [DesktopWidgetKind] 键值对存储，新增第 N 种形态无需破坏性迁移；
/// - 全部视觉/字段开关集中于 [DesktopWidgetStyle]，UI 预览与 Android 原生共用同一 JSON 协议。
library;

/// 桌面小组件形态。
enum DesktopWidgetKind {
  today('today', '今日课表', '4×2 / 2×2 · 时间轴'),
  week('week', '本周课表', '4×4 · 整周网格'),
  next('next', '下一节课', '2×2 / 4×1 · 精简卡');

  const DesktopWidgetKind(this.wireName, this.label, this.sizeHint);

  final String wireName;
  final String label;
  final String sizeHint;

  static DesktopWidgetKind parse(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return DesktopWidgetKind.today;
  }
}

/// 小组件背景主题模式。
enum WidgetThemeMode {
  light('light', '浅色'),
  dark('dark', '深色'),
  system('system', '跟随系统'),
  dynamic('dynamic', '壁纸取色');

  const WidgetThemeMode(this.wireName, this.label);

  final String wireName;
  final String label;

  static WidgetThemeMode parse(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return WidgetThemeMode.light;
  }
}

/// 小组件信息密度（内边距与行距）。
enum WidgetDensity {
  compact('compact', '紧凑'),
  comfortable('comfortable', '舒适');

  const WidgetDensity(this.wireName, this.label);

  final String wireName;
  final String label;

  static WidgetDensity parse(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return WidgetDensity.comfortable;
  }
}

/// 今日课表小组件中「已结束课程」的展示策略。
enum FinishedCourseMode {
  dim('dim', '置灰'),
  hide('hide', '自动隐藏'),
  normal('normal', '正常显示');

  const FinishedCourseMode(this.wireName, this.label);

  final String wireName;
  final String label;

  static FinishedCourseMode parse(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return FinishedCourseMode.dim;
  }
}

/// 本周课表网格小组件的周末列展示策略。
enum WeekendColumnMode {
  auto('auto', '有课显示'),
  show('show', '始终显示'),
  hide('hide', '始终隐藏');

  const WeekendColumnMode(this.wireName, this.label);

  final String wireName;
  final String label;

  static WeekendColumnMode parse(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return WeekendColumnMode.auto;
  }
}

/// 精选风格预设（选择预设写入色彩/透明度/圆角参数，保留用户的密度、字号与内容开关）。
enum WidgetStylePreset {
  minimalWhite('minimal_white', '极简纯白'),
  frostedGlass('frosted_glass', '通透磨砂'),
  darkNight('dark_night', '暗夜模式'),
  pureTransparent('pure_transparent', '纯净透明'),
  materialYou('material_you', '莫奈取色'),
  custom('custom', '自定义');

  const WidgetStylePreset(this.wireName, this.label);

  final String wireName;
  final String label;

  static WidgetStylePreset parse(String? raw) {
    for (final value in values) {
      if (value.wireName == raw) return value;
    }
    return WidgetStylePreset.minimalWhite;
  }
}

/// 单条精选预设的视觉定义（不绑定信息密度与字号）。
class WidgetStylePresetSpec {
  const WidgetStylePresetSpec({
    required this.preset,
    required this.subtitle,
    required this.themeMode,
    required this.backgroundOpacity,
    required this.cornerRadius,
  });

  final WidgetStylePreset preset;
  final String subtitle;
  final WidgetThemeMode themeMode;
  final double backgroundOpacity;
  final double cornerRadius;
}

/// 内置 5 套精选预设注册表（不透明度严格对齐 5% 滑块步进）。
const List<WidgetStylePresetSpec> widgetStylePresets = <WidgetStylePresetSpec>[
  WidgetStylePresetSpec(
    preset: WidgetStylePreset.minimalWhite,
    subtitle: '纯白清爽底色',
    themeMode: WidgetThemeMode.light,
    backgroundOpacity: 1.0,
    cornerRadius: 20.0,
  ),
  WidgetStylePresetSpec(
    preset: WidgetStylePreset.frostedGlass,
    subtitle: '半透明玻璃质感',
    themeMode: WidgetThemeMode.system,
    backgroundOpacity: 0.75,
    cornerRadius: 22.0,
  ),
  WidgetStylePresetSpec(
    preset: WidgetStylePreset.darkNight,
    subtitle: '深邃柔和暗色',
    themeMode: WidgetThemeMode.dark,
    backgroundOpacity: 0.90,
    cornerRadius: 20.0,
  ),
  WidgetStylePresetSpec(
    preset: WidgetStylePreset.pureTransparent,
    subtitle: '无底融入壁纸',
    themeMode: WidgetThemeMode.dark,
    backgroundOpacity: 0.0,
    cornerRadius: 20.0,
  ),
  WidgetStylePresetSpec(
    preset: WidgetStylePreset.materialYou,
    subtitle: '随壁纸动态配色 · Android 12+',
    themeMode: WidgetThemeMode.dynamic,
    backgroundOpacity: 0.90,
    cornerRadius: 24.0,
  ),
];

const double widgetMinOpacity = 0.0;
const double widgetMaxOpacity = 1.0;
const double widgetMinCornerRadius = 8.0;
const double widgetMaxCornerRadius = 28.0;
const double widgetMinFontScale = 0.75;
const double widgetMaxFontScale = 1.20;

double clampWidgetOpacity(double value) {
  if (value.isNaN) return 1.0;
  // 按 1% 量化，兼容历史配置值并保持指纹稳定。
  final clamped = value.clamp(widgetMinOpacity, widgetMaxOpacity).toDouble();
  return (clamped * 100).round() / 100.0;
}

double clampWidgetCornerRadius(double value) {
  if (value.isNaN) return 20.0;
  return value
      .clamp(widgetMinCornerRadius, widgetMaxCornerRadius)
      .roundToDouble();
}

double clampWidgetFontScale(double value) {
  if (value.isNaN) return 1.0;
  final clamped = value
      .clamp(widgetMinFontScale, widgetMaxFontScale)
      .toDouble();
  return (clamped * 20).round() / 20.0;
}

/// 单个小组件类型的完整样式配置。
class DesktopWidgetStyle {
  const DesktopWidgetStyle({
    this.preset = WidgetStylePreset.minimalWhite,
    this.themeMode = WidgetThemeMode.light,
    this.backgroundOpacity = 1.0,
    this.cornerRadius = 20.0,
    this.fontScale = 1.0,
    this.density = WidgetDensity.comfortable,
    this.showHeader = true,
    this.showLocation = true,
    this.showTeacher = true,
    this.showTime = true,
    this.showExams = true,
    this.autoSwitchTomorrow = true,
    this.finishedCourseMode = FinishedCourseMode.dim,
    this.weekendMode = WeekendColumnMode.auto,
  });

  factory DesktopWidgetStyle.defaultsFor(DesktopWidgetKind kind) {
    switch (kind) {
      case DesktopWidgetKind.today:
        return const DesktopWidgetStyle(showTeacher: true);
      case DesktopWidgetKind.week:
        return const DesktopWidgetStyle(showTeacher: false);
      case DesktopWidgetKind.next:
        return const DesktopWidgetStyle(showTeacher: true);
    }
  }

  final WidgetStylePreset preset;
  final WidgetThemeMode themeMode;
  final double backgroundOpacity;
  final double cornerRadius;
  final double fontScale;
  final WidgetDensity density;
  final bool showHeader;
  final bool showLocation;
  final bool showTeacher;
  final bool showTime;
  final bool showExams;
  final bool autoSwitchTomorrow;
  final FinishedCourseMode finishedCourseMode;
  final WeekendColumnMode weekendMode;

  /// 套用精选预设（更新外观色彩、不透明度与圆角，保留用户的密度、字号与内容开关）。
  DesktopWidgetStyle applyPreset(WidgetStylePreset target) {
    for (final spec in widgetStylePresets) {
      if (spec.preset == target) {
        return DesktopWidgetStyle(
          preset: spec.preset,
          themeMode: spec.themeMode,
          backgroundOpacity: spec.backgroundOpacity,
          cornerRadius: spec.cornerRadius,
          fontScale: fontScale,
          density: density,
          showHeader: showHeader,
          showLocation: showLocation,
          showTeacher: showTeacher,
          showTime: showTime,
          showExams: showExams,
          autoSwitchTomorrow: autoSwitchTomorrow,
          finishedCourseMode: finishedCourseMode,
          weekendMode: weekendMode,
        );
      }
    }
    return copyWith(preset: WidgetStylePreset.custom);
  }

  /// 创建修改后的不可变副本；仅修改色彩/不透明度/圆角且未显式传入 `preset` 时切为 `custom`。
  /// 调整信息密度、字号或内容开关不会打断当前精选预设。
  DesktopWidgetStyle copyWith({
    WidgetStylePreset? preset,
    WidgetThemeMode? themeMode,
    double? backgroundOpacity,
    double? cornerRadius,
    double? fontScale,
    WidgetDensity? density,
    bool? showHeader,
    bool? showLocation,
    bool? showTeacher,
    bool? showTime,
    bool? showExams,
    bool? autoSwitchTomorrow,
    FinishedCourseMode? finishedCourseMode,
    WeekendColumnMode? weekendMode,
  }) {
    final nextThemeMode = themeMode ?? this.themeMode;
    final nextOpacity = backgroundOpacity == null
        ? this.backgroundOpacity
        : clampWidgetOpacity(backgroundOpacity);
    final nextRadius = cornerRadius == null
        ? this.cornerRadius
        : clampWidgetCornerRadius(cornerRadius);
    final nextScale = fontScale == null
        ? this.fontScale
        : clampWidgetFontScale(fontScale);
    final nextDensity = density ?? this.density;

    final visualChanged =
        nextThemeMode != this.themeMode ||
        nextOpacity != this.backgroundOpacity ||
        nextRadius != this.cornerRadius;

    final nextPreset =
        preset ?? (visualChanged ? WidgetStylePreset.custom : this.preset);

    return DesktopWidgetStyle(
      preset: nextPreset,
      themeMode: nextThemeMode,
      backgroundOpacity: nextOpacity,
      cornerRadius: nextRadius,
      fontScale: nextScale,
      density: nextDensity,
      showHeader: showHeader ?? this.showHeader,
      showLocation: showLocation ?? this.showLocation,
      showTeacher: showTeacher ?? this.showTeacher,
      showTime: showTime ?? this.showTime,
      showExams: showExams ?? this.showExams,
      autoSwitchTomorrow: autoSwitchTomorrow ?? this.autoSwitchTomorrow,
      finishedCourseMode: finishedCourseMode ?? this.finishedCourseMode,
      weekendMode: weekendMode ?? this.weekendMode,
    );
  }

  Map<String, Object?> toJson() => <String, Object?>{
    'preset': preset.wireName,
    'themeMode': themeMode.wireName,
    'backgroundOpacity': backgroundOpacity,
    'cornerRadius': cornerRadius,
    'fontScale': fontScale,
    'density': density.wireName,
    'showHeader': showHeader,
    'showLocation': showLocation,
    'showTeacher': showTeacher,
    'showTime': showTime,
    'showExams': showExams,
    'autoSwitchTomorrow': autoSwitchTomorrow,
    'finishedCourseMode': finishedCourseMode.wireName,
    'weekendMode': weekendMode.wireName,
  };

  factory DesktopWidgetStyle.fromJson(
    Object? raw, {
    DesktopWidgetKind kind = DesktopWidgetKind.today,
  }) {
    final base = DesktopWidgetStyle.defaultsFor(kind);
    if (raw is! Map) return base;
    return DesktopWidgetStyle(
      preset: raw['preset'] is String
          ? WidgetStylePreset.parse(raw['preset'] as String?)
          : base.preset,
      themeMode: raw['themeMode'] is String
          ? WidgetThemeMode.parse(raw['themeMode'] as String?)
          : base.themeMode,
      backgroundOpacity: raw['backgroundOpacity'] is num
          ? clampWidgetOpacity((raw['backgroundOpacity'] as num).toDouble())
          : base.backgroundOpacity,
      cornerRadius: raw['cornerRadius'] is num
          ? clampWidgetCornerRadius((raw['cornerRadius'] as num).toDouble())
          : base.cornerRadius,
      fontScale: raw['fontScale'] is num
          ? clampWidgetFontScale((raw['fontScale'] as num).toDouble())
          : base.fontScale,
      density: raw['density'] is String
          ? WidgetDensity.parse(raw['density'] as String?)
          : base.density,
      showHeader: raw['showHeader'] is bool
          ? raw['showHeader'] as bool
          : base.showHeader,
      showLocation: raw['showLocation'] is bool
          ? raw['showLocation'] as bool
          : base.showLocation,
      showTeacher: raw['showTeacher'] is bool
          ? raw['showTeacher'] as bool
          : base.showTeacher,
      showTime: raw['showTime'] is bool
          ? raw['showTime'] as bool
          : base.showTime,
      showExams: raw['showExams'] is bool
          ? raw['showExams'] as bool
          : base.showExams,
      autoSwitchTomorrow: raw['autoSwitchTomorrow'] is bool
          ? raw['autoSwitchTomorrow'] as bool
          : base.autoSwitchTomorrow,
      finishedCourseMode: raw['finishedCourseMode'] is String
          ? FinishedCourseMode.parse(raw['finishedCourseMode'] as String?)
          : base.finishedCourseMode,
      weekendMode: raw['weekendMode'] is String
          ? WeekendColumnMode.parse(raw['weekendMode'] as String?)
          : base.weekendMode,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DesktopWidgetStyle &&
          other.preset == preset &&
          other.themeMode == themeMode &&
          other.backgroundOpacity == backgroundOpacity &&
          other.cornerRadius == cornerRadius &&
          other.fontScale == fontScale &&
          other.density == density &&
          other.showHeader == showHeader &&
          other.showLocation == showLocation &&
          other.showTeacher == showTeacher &&
          other.showTime == showTime &&
          other.showExams == showExams &&
          other.autoSwitchTomorrow == autoSwitchTomorrow &&
          other.finishedCourseMode == finishedCourseMode &&
          other.weekendMode == weekendMode;

  @override
  int get hashCode => Object.hash(
    preset,
    themeMode,
    backgroundOpacity,
    cornerRadius,
    fontScale,
    density,
    showHeader,
    showLocation,
    showTeacher,
    showTime,
    showExams,
    autoSwitchTomorrow,
    finishedCourseMode,
    weekendMode,
  );
}

/// 三种小组件形态的独立样式配置集合（按 [DesktopWidgetKind] 索引）。
class DesktopWidgetConfigSet {
  DesktopWidgetConfigSet({Map<DesktopWidgetKind, DesktopWidgetStyle>? styles})
    : _styles = <DesktopWidgetKind, DesktopWidgetStyle>{
        for (final kind in DesktopWidgetKind.values)
          kind: styles?[kind] ?? DesktopWidgetStyle.defaultsFor(kind),
      };

  factory DesktopWidgetConfigSet.defaults() => DesktopWidgetConfigSet();

  final Map<DesktopWidgetKind, DesktopWidgetStyle> _styles;

  DesktopWidgetStyle styleOf(DesktopWidgetKind kind) =>
      _styles[kind] ?? DesktopWidgetStyle.defaultsFor(kind);

  DesktopWidgetConfigSet withStyle(
    DesktopWidgetKind kind,
    DesktopWidgetStyle style,
  ) => DesktopWidgetConfigSet(
    styles: <DesktopWidgetKind, DesktopWidgetStyle>{..._styles, kind: style},
  );

  DesktopWidgetConfigSet resetKind(DesktopWidgetKind kind) =>
      withStyle(kind, DesktopWidgetStyle.defaultsFor(kind));

  Map<String, Object?> toJson() => <String, Object?>{
    for (final kind in DesktopWidgetKind.values)
      kind.wireName: styleOf(kind).toJson(),
  };

  factory DesktopWidgetConfigSet.fromJson(Object? raw) {
    if (raw is! Map) return DesktopWidgetConfigSet.defaults();
    return DesktopWidgetConfigSet(
      styles: <DesktopWidgetKind, DesktopWidgetStyle>{
        for (final kind in DesktopWidgetKind.values)
          kind: DesktopWidgetStyle.fromJson(raw[kind.wireName], kind: kind),
      },
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! DesktopWidgetConfigSet) return false;
    for (final kind in DesktopWidgetKind.values) {
      if (styleOf(kind) != other.styleOf(kind)) return false;
    }
    return true;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    for (final kind in DesktopWidgetKind.values) styleOf(kind),
  ]);
}
