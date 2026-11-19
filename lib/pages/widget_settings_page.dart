/// 桌面小组件样式配置与实时预览页。
///
/// 三种形态（今日课表 / 本周课表 / 下一节课）拥有各自独立的样式配置，
/// 拖动透明度/圆角/字号滑块时仅刷新局部草稿状态，抬手 [onChangeEnd] 时才持久化并同步给桌面。
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/route_settled.dart';
import '../src/widget_planner.dart';
import '../src/widget_service.dart';
import '../src/widget_style.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/desktop_widget_preview.dart';
import '../widgets/section_title.dart';
import '../widgets/tactile_button.dart';

class WidgetSettingsPage extends StatefulWidget {
  const WidgetSettingsPage({
    super.key,
    required this.model,
    required this.widgetService,
    this.initialKind = DesktopWidgetKind.today,
  });

  final AppModel model;
  final DesktopWidgetService widgetService;
  final DesktopWidgetKind initialKind;

  @override
  State<WidgetSettingsPage> createState() => _WidgetSettingsPageState();
}

class _WidgetSettingsPageState extends State<WidgetSettingsPage>
    with WidgetsBindingObserver {
  late DesktopWidgetKind _selectedKind = widget.initialKind;
  PreviewWallpaper _wallpaper = PreviewWallpaper.softLight;
  bool _nextWide = false;

  // 滑块局部草稿，拖动期间不触发写盘和跨通道同步。
  double? _opacityDraft;
  double? _radiusDraft;
  double? _fontScaleDraft;

  bool _pinning = false;
  bool _initialPinnedQueried = false;
  RouteSettledHandle? _pinnedQueryHandle;
  final ValueNotifier<Map<DesktopWidgetKind, int>> _pinnedCounts =
      ValueNotifier<Map<DesktopWidgetKind, int>>(
        const <DesktopWidgetKind, int>{},
      );

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialPinnedQueried) return;
    _initialPinnedQueried = true;
    _pinnedQueryHandle = scheduleAfterRouteSettled(
      context: context,
      isMounted: () => mounted,
      task: _refreshPinnedCounts,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshPinnedCounts());
    }
  }

  @override
  void dispose() {
    _pinnedQueryHandle?.cancel();
    _pinnedQueryHandle = null;
    WidgetsBinding.instance.removeObserver(this);
    _pinnedCounts.dispose();
    super.dispose();
  }

  Future<void> _refreshPinnedCounts() async {
    final counts = await widget.widgetService.getPinnedCounts();
    if (!mounted) return;
    _pinnedCounts.value = counts;
  }

  void _selectKind(DesktopWidgetKind kind) {
    if (_selectedKind == kind) return;
    setState(() {
      _selectedKind = kind;
      _opacityDraft = null;
      _radiusDraft = null;
      _fontScaleDraft = null;
    });
  }

  DesktopWidgetStyle _effectiveStyle() {
    final saved = widget.model.widgetStyleOf(_selectedKind);
    return saved.copyWith(
      preset: (_opacityDraft != null || _radiusDraft != null)
          ? WidgetStylePreset.custom
          : saved.preset,
      backgroundOpacity: _opacityDraft ?? saved.backgroundOpacity,
      cornerRadius: _radiusDraft ?? saved.cornerRadius,
      fontScale: _fontScaleDraft ?? saved.fontScale,
    );
  }

  Future<void> _commitStyle(DesktopWidgetStyle next) async {
    setState(() {
      _opacityDraft = null;
      _radiusDraft = null;
      _fontScaleDraft = null;
    });
    await widget.model.setWidgetStyle(_selectedKind, next);
  }

  Future<void> _pinSelectedWidget() async {
    if (_pinning) return;
    _pinning = true;
    try {
      await widget.widgetService.syncNow(force: true);
      final accepted = await widget.widgetService.requestPinWidget(
        _selectedKind,
      );
      await _refreshPinnedCounts();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: accepted
            ? '已向系统桌面发起添加「${_selectedKind.label}」'
            : '当前桌面暂不支持直接添加，请长按桌面空白处添加小组件',
        type: accepted ? AppSnackBarType.success : AppSnackBarType.info,
        duration: Duration(seconds: accepted ? 2 : 4),
      );
    } finally {
      _pinning = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: TactileAppBar(
        leading: const TactileBackButton(),
        title: const Text('桌面小组件'),
      ),
      body: ListenableBuilder(
        listenable: widget.model.prefsNotifier,
        builder: (context, _) {
          final style = _effectiveStyle();
          final snapshot = widget.widgetService.buildSnapshot();
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: <Widget>[
              _KindSegmentedHeader(
                selected: _selectedKind,
                onSelect: _selectKind,
              ),
              const SizedBox(height: 12),
              _PreviewStageCard(
                kind: _selectedKind,
                style: style,
                snapshot: snapshot,
                wallpaper: _wallpaper,
                nextWide: _nextWide,
                pinnedCounts: _pinnedCounts,
                onSelectWallpaper: (wp) => setState(() => _wallpaper = wp),
                onToggleNextWide: (wide) => setState(() => _nextWide = wide),
                onRequestPin: _pinSelectedWidget,
              ),
              const SizedBox(height: 16),
              const SectionTitle('精选预设'),
              _PresetStrip(
                currentPreset: style.preset,
                onSelect: (preset) =>
                    unawaited(_commitStyle(style.applyPreset(preset))),
              ),
              const SizedBox(height: 18),
              const SectionTitle('外观与质感'),
              Card(
                child: Column(
                  children: <Widget>[
                    _OptionRowTile<WidgetThemeMode>(
                      icon: Icons.palette_outlined,
                      title: '色彩主题',
                      options: WidgetThemeMode.values,
                      selected: style.themeMode,
                      labelOf: (v) => v.label,
                      onChanged: (mode) => unawaited(
                        _commitStyle(style.copyWith(themeMode: mode)),
                      ),
                    ),
                    const Divider(height: 0, indent: 16, endIndent: 16),
                    _LabeledSliderTile(
                      icon: Icons.opacity_rounded,
                      title: '背景不透明度',
                      valueLabel: '${(style.backgroundOpacity * 100).round()}%',
                      value: style.backgroundOpacity,
                      min: widgetMinOpacity,
                      max: widgetMaxOpacity,
                      divisions: 20,
                      onChanged: (v) => setState(() => _opacityDraft = v),
                      onChangeEnd: (v) => unawaited(
                        _commitStyle(
                          widget.model
                              .widgetStyleOf(_selectedKind)
                              .copyWith(backgroundOpacity: v),
                        ),
                      ),
                    ),
                    const Divider(height: 0, indent: 16, endIndent: 16),
                    _LabeledSliderTile(
                      icon: Icons.rounded_corner_rounded,
                      title: '卡片圆角',
                      valueLabel: '${style.cornerRadius.round()} dp',
                      value: style.cornerRadius,
                      min: widgetMinCornerRadius,
                      max: widgetMaxCornerRadius,
                      divisions: 20,
                      onChanged: (v) => setState(() => _radiusDraft = v),
                      onChangeEnd: (v) => unawaited(
                        _commitStyle(
                          widget.model
                              .widgetStyleOf(_selectedKind)
                              .copyWith(cornerRadius: v),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const SectionTitle('排版与字号'),
              Card(
                child: Column(
                  children: <Widget>[
                    _LabeledSliderTile(
                      icon: Icons.format_size_rounded,
                      title: '文字大小',
                      valueLabel: '${(style.fontScale * 100).round()}%',
                      value: style.fontScale,
                      min: widgetMinFontScale,
                      max: widgetMaxFontScale,
                      divisions: 8,
                      onChanged: (v) => setState(() => _fontScaleDraft = v),
                      onChangeEnd: (v) => unawaited(
                        _commitStyle(
                          widget.model
                              .widgetStyleOf(_selectedKind)
                              .copyWith(fontScale: v),
                        ),
                      ),
                    ),
                    const Divider(height: 0, indent: 16, endIndent: 16),
                    _OptionRowTile<WidgetDensity>(
                      icon: Icons.density_medium_rounded,
                      title: '信息密度',
                      options: WidgetDensity.values,
                      selected: style.density,
                      labelOf: (v) => v.label,
                      onChanged: (v) =>
                          unawaited(_commitStyle(style.copyWith(density: v))),
                    ),
                    const Divider(height: 0, indent: 16, endIndent: 16),
                    SwitchListTile(
                      secondary: const Icon(Icons.title_rounded, size: 20),
                      title: const Text('显示顶部标题栏'),
                      subtitle: const Text('关闭后界面更纯净，适合小尺寸卡片'),
                      value: style.showHeader,
                      onChanged: (v) => unawaited(
                        _commitStyle(style.copyWith(showHeader: v)),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const SectionTitle('内容显示'),
              Card(
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      secondary: const Icon(Icons.place_outlined, size: 20),
                      title: const Text('显示上课地点'),
                      value: style.showLocation,
                      onChanged: (v) => unawaited(
                        _commitStyle(style.copyWith(showLocation: v)),
                      ),
                    ),
                    const Divider(height: 0, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                      ),
                      title: const Text('显示授课教师'),
                      value: style.showTeacher,
                      onChanged: (v) => unawaited(
                        _commitStyle(style.copyWith(showTeacher: v)),
                      ),
                    ),
                    const Divider(height: 0, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(
                        Icons.access_time_rounded,
                        size: 20,
                      ),
                      title: Text(
                        _selectedKind == DesktopWidgetKind.week
                            ? '显示左侧节次列'
                            : '显示起止时间',
                      ),
                      value: style.showTime,
                      onChanged: (v) =>
                          unawaited(_commitStyle(style.copyWith(showTime: v))),
                    ),
                    if (_selectedKind != DesktopWidgetKind.week) ...<Widget>[
                      const Divider(height: 0, indent: 56),
                      SwitchListTile(
                        secondary: const Icon(
                          Icons.event_note_outlined,
                          size: 20,
                        ),
                        title: const Text('融合考试安排'),
                        subtitle: const Text('当天考试按时间混排，无课期展示 7 天内倒计时'),
                        value: style.showExams,
                        onChanged: (v) => unawaited(
                          _commitStyle(style.copyWith(showExams: v)),
                        ),
                      ),
                      const Divider(height: 0, indent: 16, endIndent: 16),
                      _OptionRowTile<FinishedCourseMode>(
                        icon: Icons.check_circle_outline_rounded,
                        title: '已结束课程',
                        options: FinishedCourseMode.values,
                        selected: style.finishedCourseMode,
                        labelOf: (v) => v.label,
                        onChanged: (v) => unawaited(
                          _commitStyle(style.copyWith(finishedCourseMode: v)),
                        ),
                      ),
                    ] else ...<Widget>[
                      const Divider(height: 0, indent: 16, endIndent: 16),
                      _OptionRowTile<WeekendColumnMode>(
                        icon: Icons.weekend_outlined,
                        title: '周末列显示',
                        options: WeekendColumnMode.values,
                        selected: style.weekendMode,
                        labelOf: (v) => v.label,
                        onChanged: (v) => unawaited(
                          _commitStyle(style.copyWith(weekendMode: v)),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Center(
                child: TactileActionButton(
                  variant: TactileActionVariant.outlined,
                  icon: const Icon(Icons.restart_alt_rounded, size: 18),
                  label: Text('恢复「${_selectedKind.label}」默认样式'),
                  onPressed: () => unawaited(
                    widget.model.resetWidgetStyle(_selectedKind).then((_) {
                      if (!context.mounted) return;
                      setState(() {
                        _opacityDraft = null;
                        _radiusDraft = null;
                        _fontScaleDraft = null;
                      });
                    }),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _KindSegmentedHeader extends StatelessWidget {
  const _KindSegmentedHeader({required this.selected, required this.onSelect});

  final DesktopWidgetKind selected;
  final ValueChanged<DesktopWidgetKind> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        border: Border.all(
          color: scheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        children: <Widget>[
          for (final kind in DesktopWidgetKind.values)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(kind),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    color: selected == kind
                        ? scheme.primary.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Column(
                    children: <Widget>[
                      Text(
                        kind.label,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selected == kind
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected == kind
                              ? scheme.primary
                              : scheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _PreviewStageCard extends StatelessWidget {
  const _PreviewStageCard({
    required this.kind,
    required this.style,
    required this.snapshot,
    required this.wallpaper,
    required this.nextWide,
    required this.pinnedCounts,
    required this.onSelectWallpaper,
    required this.onToggleNextWide,
    required this.onRequestPin,
  });

  final DesktopWidgetKind kind;
  final DesktopWidgetStyle style;
  final WidgetSnapshot? snapshot;
  final PreviewWallpaper wallpaper;
  final bool nextWide;
  final ValueNotifier<Map<DesktopWidgetKind, int>> pinnedCounts;
  final ValueChanged<PreviewWallpaper> onSelectWallpaper;
  final ValueChanged<bool> onToggleNextWide;
  final VoidCallback onRequestPin;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Text(
                  kind.sizeHint,
                  style: TextStyle(
                    fontSize: 12,
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                if (kind == DesktopWidgetKind.next) ...<Widget>[
                  _CompactChoicePill(
                    label: nextWide ? '4×1 宽条' : '2×2 卡片',
                    onTap: () => onToggleNextWide(!nextWide),
                  ),
                  const SizedBox(width: 8),
                ],
                for (final wp in PreviewWallpaper.values)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: GestureDetector(
                      onTap: () => onSelectWallpaper(wp),
                      child: Tooltip(
                        message: wp.label,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: LinearGradient(
                              colors: <Color>[wp.startColor, wp.endColor],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: wallpaper == wp
                                  ? scheme.primary
                                  : Colors.black12,
                              width: wallpaper == wp ? 2 : 1,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 20,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[wallpaper.startColor, wallpaper.endColor],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                ),
                child: Center(
                  child: DesktopWidgetPreview(
                    kind: kind,
                    style: style,
                    snapshot: snapshot,
                    nextWide: nextWide,
                    systemBrightness: wallpaper.brightness,
                  ),
                ),
              ),
            ),
            if (style.themeMode == WidgetThemeMode.dynamic) ...<Widget>[
              const SizedBox(height: 8),
              Text(
                'Android 12+ 桌面上将自动随系统壁纸切换 Material You 莫奈色板',
                style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: <Widget>[
                Expanded(
                  child: ValueListenableBuilder<Map<DesktopWidgetKind, int>>(
                    valueListenable: pinnedCounts,
                    builder: (context, counts, _) {
                      final count = counts[kind] ?? 0;
                      return Text(
                        count > 0 ? '桌面上已有 $count 个「${kind.label}」' : '尚未添加到桌面',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: scheme.onSurfaceVariant,
                        ),
                      );
                    },
                  ),
                ),
                TactileActionButton(
                  variant: TactileActionVariant.filled,
                  icon: const Icon(Icons.add_to_home_screen_rounded, size: 18),
                  label: const Text('添加到桌面'),
                  onPressed: onRequestPin,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CompactChoicePill extends StatelessWidget {
  const _CompactChoicePill({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: scheme.primary,
          ),
        ),
      ),
    );
  }
}

class _PresetStrip extends StatelessWidget {
  const _PresetStrip({required this.currentPreset, required this.onSelect});

  final WidgetStylePreset currentPreset;
  final ValueChanged<WidgetStylePreset> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 58,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: widgetStylePresets.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final spec = widgetStylePresets[index];
          final active = currentPreset == spec.preset;
          return GestureDetector(
            onTap: () => onSelect(spec.preset),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active
                    ? scheme.primary.withValues(alpha: 0.12)
                    : scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(AppRadius.medium),
                border: Border.all(
                  color: active
                      ? scheme.primary
                      : scheme.outlineVariant.withValues(alpha: 0.5),
                  width: active ? 1.5 : 1,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    spec.preset.label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                      color: active ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  Text(
                    spec.subtitle,
                    style: TextStyle(
                      fontSize: 10.5,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _LabeledSliderTile extends StatelessWidget {
  const _LabeledSliderTile({
    required this.icon,
    required this.title,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
    required this.onChangeEnd,
  });

  final IconData icon;
  final String title;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Expanded(
                child: Text(title, style: const TextStyle(fontSize: 15)),
              ),
              Text(
                valueLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: scheme.primary,
                ),
              ),
            ],
          ),
          Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            onChanged: onChanged,
            onChangeEnd: onChangeEnd,
          ),
        ],
      ),
    );
  }
}

class _OptionRowTile<T> extends StatelessWidget {
  const _OptionRowTile({
    required this.icon,
    required this.title,
    required this.options,
    required this.selected,
    required this.labelOf,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(icon, size: 20, color: scheme.onSurfaceVariant),
              const SizedBox(width: 14),
              Text(title, style: const TextStyle(fontSize: 15)),
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              for (final option in options)
                ChoiceChip(
                  label: Text(labelOf(option)),
                  selected: selected == option,
                  onSelected: (_) => onChanged(option),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
