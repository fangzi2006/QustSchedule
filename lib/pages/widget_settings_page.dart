/// 桌面小组件样式配置与实时预览页。
///
/// 三种形态（今日课表 / 本周课表 / 下一节课）拥有各自独立的样式配置，
/// 顶部预览舞台吸顶常驻并在滚动长卡片（如本周课表）时平滑缩放，支持「实时课表 / 示例课表」切换；
/// 拖动透明度/圆角/字号滑块时仅刷新局部草稿状态（不重建快照），抬手 [onChangeEnd] 才持久化并同步桌面。
library;

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import '../src/app_model.dart';
import '../src/route_settled.dart';
import '../src/timetable.dart';
import '../src/widget_gateway.dart';
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
  bool _todayNarrow = false;
  bool _nextWide = false;
  late bool _useSampleData;

  // 缓存真实快照与黄金示例快照，彻底消除滑块拖动 60fps 重建整份 14 天日程快照。
  WidgetSnapshot? _cachedRealSnapshot;
  late final WidgetSnapshot _cachedSampleSnapshot;
  late final DateTime _sampleClock;
  Object? _lastDataKey;

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
    _sampleClock = samplePreviewClock();
    _cachedSampleSnapshot = buildSampleWidgetSnapshot(reference: _sampleClock);
    _refreshRealSnapshotCache(force: true);

    final real = _cachedRealSnapshot;
    final hasRealContent =
        real != null &&
        real.signedIn &&
        real.days.isNotEmpty &&
        real.weeks.isNotEmpty &&
        (real.days.first.items.isNotEmpty ||
            real.weeks.first.blocks.isNotEmpty);
    _useSampleData = !hasRealContent;

    widget.model.addListener(_onSourceDataChanged);
    widget.model.academicNotifier.addListener(_onSourceDataChanged);
    widget.widgetService.ensureLivePinnedUpdates();
    MethodChannelDesktopWidgetGateway.livePinnedCounts.addListener(
      _onLivePinnedCounts,
    );
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
      _refreshRealSnapshotCache(force: true);
      if (mounted) setState(() {});
      unawaited(_refreshPinnedCounts());
    }
  }

  @override
  void dispose() {
    _pinnedQueryHandle?.cancel();
    _pinnedQueryHandle = null;
    widget.model.removeListener(_onSourceDataChanged);
    widget.model.academicNotifier.removeListener(_onSourceDataChanged);
    MethodChannelDesktopWidgetGateway.livePinnedCounts.removeListener(
      _onLivePinnedCounts,
    );
    WidgetsBinding.instance.removeObserver(this);
    _pinnedCounts.dispose();
    super.dispose();
  }

  Object _computeSourceDataKey() {
    final counts = widget.model.sectionCounts;
    return Object.hash(
      widget.model.preferencesLoaded,
      widget.model.schedule,
      widget.model.termStart,
      widget.model.maxWeek,
      widget.model.loadedAcademicTerm,
      Object.hashAll(widget.model.reschedules),
      Object.hashAll(widget.model.timetables),
      Object.hashAll(widget.model.exams),
      counts[PeriodGroup.morning],
      counts[PeriodGroup.afternoon],
      counts[PeriodGroup.evening],
    );
  }

  void _refreshRealSnapshotCache({bool force = false}) {
    final key = _computeSourceDataKey();
    if (!force && key == _lastDataKey) return;
    _lastDataKey = key;
    _cachedRealSnapshot = widget.widgetService.buildSnapshot();
  }

  void _onSourceDataChanged() {
    final prevKey = _lastDataKey;
    _refreshRealSnapshotCache();
    if (mounted && prevKey != _lastDataKey) {
      setState(() {});
    }
  }

  void _onLivePinnedCounts() {
    final latest = MethodChannelDesktopWidgetGateway.livePinnedCounts.value;
    if (latest != null && mounted) {
      _pinnedCounts.value = latest;
    }
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

  void _maybeHaptic(bool atDefault, bool wasAtDefault) {
    if (!atDefault || wasAtDefault) return;
    switch (Theme.of(context).platform) {
      case TargetPlatform.android:
      case TargetPlatform.iOS:
        HapticFeedback.selectionClick();
      case TargetPlatform.fuchsia:
      case TargetPlatform.linux:
      case TargetPlatform.macOS:
      case TargetPlatform.windows:
        break;
    }
  }

  Future<void> _commitStyle(DesktopWidgetStyle next) async {
    setState(() {
      _opacityDraft = null;
      _radiusDraft = null;
      _fontScaleDraft = null;
    });
    await widget.model.setWidgetStyle(_selectedKind, next);
    // 落盘后立刻跳过 300ms 防抖推送给原生桌面，避免用户滑回桌面时外观尚未生效。
    unawaited(widget.widgetService.syncNow());
  }

  Future<void> _resetCurrentKind() async {
    final kind = _selectedKind;
    final previous = widget.model.widgetStyleOf(kind);
    final defaults = DesktopWidgetStyle.defaultsFor(kind);
    if (previous == defaults) {
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: '「${kind.label}」已是默认样式',
        type: AppSnackBarType.info,
      );
      return;
    }

    await widget.model.resetWidgetStyle(kind);
    if (!mounted) return;
    setState(() {
      _opacityDraft = null;
      _radiusDraft = null;
      _fontScaleDraft = null;
    });
    unawaited(widget.widgetService.syncNow());
    showAppSnackBar(
      context,
      message: '已恢复「${kind.label}」默认样式',
      type: AppSnackBarType.success,
      duration: const Duration(seconds: 4),
      action: SnackBarAction(
        label: '撤销',
        onPressed: () {
          if (!mounted) return;
          unawaited(_restoreStyle(kind, previous));
        },
      ),
    );
  }

  Future<void> _restoreStyle(
    DesktopWidgetKind kind,
    DesktopWidgetStyle style,
  ) async {
    if (mounted && _selectedKind == kind) {
      setState(() {
        _opacityDraft = null;
        _radiusDraft = null;
        _fontScaleDraft = null;
      });
    }
    await widget.model.setWidgetStyle(kind, style);
    unawaited(widget.widgetService.syncNow());
  }

  Future<void> _pinSelectedWidget() async {
    if (_pinning) return;
    _pinning = true;
    final kind = _selectedKind;
    try {
      await widget.widgetService.syncNow(force: true);
      final accepted = await widget.widgetService.requestPinWidget(kind);
      await _refreshPinnedCounts();
      if (!mounted) return;
      showAppSnackBar(
        context,
        message: accepted
            ? '已向系统桌面发起添加「${kind.label}」'
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
    final viewportHeight = MediaQuery.sizeOf(context).height;
    return Scaffold(
      appBar: TactileAppBar(
        leading: const TactileBackButton(),
        title: const Text('桌面小组件'),
      ),
      body: ListenableBuilder(
        listenable: widget.model.prefsNotifier,
        builder: (context, _) {
          final style = _effectiveStyle();
          final previewSnapshot = _useSampleData
              ? _cachedSampleSnapshot
              : _cachedRealSnapshot;
          final previewNow = _useSampleData ? _sampleClock : null;
          final isTransparent = style.backgroundOpacity <= 0.01;
          final isToday = _selectedKind == DesktopWidgetKind.today;
          final isWeek = _selectedKind == DesktopWidgetKind.week;
          final isNext = _selectedKind == DesktopWidgetKind.next;
          final scheme = Theme.of(context).colorScheme;

          // 按当前小组件高度、系统字号缩放与视口计算吸顶预览舞台的展开/折叠高度，
          // 确保本周课表滚动及超大字体模式下控制项依然宽松顺手、绝不溢出。
          final textScaleFactor =
              (MediaQuery.textScalerOf(context).scale(14.0) / 14.0).clamp(
                1.0,
                2.2,
              );
          final chromeHeight = 112.0 + (textScaleFactor - 1.0) * 26.0;
          final rawMaxCanvas = switch (_selectedKind) {
            DesktopWidgetKind.today => 196.0,
            DesktopWidgetKind.week => 336.0,
            DesktopWidgetKind.next => _nextWide ? 96.0 : 196.0,
          };
          final rawMinCanvas = switch (_selectedKind) {
            DesktopWidgetKind.today => 148.0,
            DesktopWidgetKind.week => 190.0,
            DesktopWidgetKind.next => _nextWide ? 84.0 : 136.0,
          };
          final maxAllowedExtent = math.max(
            chromeHeight + 88.0,
            viewportHeight * 0.56,
          );
          final minAllowedExtent = math.max(
            chromeHeight + 64.0,
            viewportHeight * 0.36,
          );
          final maxExtent = math.min(
            chromeHeight + rawMaxCanvas,
            maxAllowedExtent,
          );
          final minExtent = math.min(
            math.min(chromeHeight + rawMinCanvas, minAllowedExtent),
            maxExtent,
          );

          return CustomScrollView(
            slivers: <Widget>[
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
                sliver: SliverToBoxAdapter(
                  child: _KindSegmentedHeader(
                    selected: _selectedKind,
                    onSelect: _selectKind,
                  ),
                ),
              ),
              SliverPersistentHeader(
                pinned: true,
                delegate: _PreviewStageHeaderDelegate(
                  maxExtent: maxExtent,
                  minExtent: minExtent,
                  kind: _selectedKind,
                  style: style,
                  snapshot: previewSnapshot,
                  previewNow: previewNow,
                  useSampleData: _useSampleData,
                  wallpaper: _wallpaper,
                  todayNarrow: _todayNarrow,
                  nextWide: _nextWide,
                  pinnedCounts: _pinnedCounts,
                  onToggleSampleData: (sample) =>
                      setState(() => _useSampleData = sample),
                  onSelectWallpaper: (wp) => setState(() => _wallpaper = wp),
                  onToggleTodayNarrow: (narrow) =>
                      setState(() => _todayNarrow = narrow),
                  onToggleNextWide: (wide) => setState(() => _nextWide = wide),
                  onRequestPin: _pinSelectedWidget,
                ),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 36),
                sliver: SliverList(
                  delegate: SliverChildListDelegate(<Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainerHighest.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            Icons.picture_in_picture_alt_rounded,
                            size: 16,
                            color: scheme.primary,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '上方预览仅供参考，以桌面实际效果为准；推荐开启系统小窗或分屏对着桌面调整。',
                              style: Theme.of(context).textTheme.bodySmall
                                  ?.copyWith(color: scheme.onSurfaceVariant),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
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
                            helperText:
                                style.themeMode == WidgetThemeMode.dynamic
                                ? 'Android 12+ 桌面上将随系统壁纸自动取色，旧版本使用默认莫奈色板'
                                : null,
                            onChanged: (mode) => unawaited(
                              _commitStyle(style.copyWith(themeMode: mode)),
                            ),
                          ),
                          const Divider(height: 0, indent: 16, endIndent: 16),
                          _LabeledSliderTile(
                            icon: Icons.opacity_rounded,
                            title: '背景不透明度',
                            valueLabel:
                                '${(style.backgroundOpacity * 100).round()}%',
                            value: style.backgroundOpacity,
                            min: widgetMinOpacity,
                            max: widgetMaxOpacity,
                            divisions: 20,
                            defaultValue: 1.0,
                            onChanged: (v) {
                              final prevAtDef =
                                  (style.backgroundOpacity - 1.0).abs() < 0.01;
                              final atDef = (v - 1.0).abs() < 0.01;
                              _maybeHaptic(atDef, prevAtDef);
                              setState(() => _opacityDraft = v);
                            },
                            onChangeEnd: (v) => unawaited(
                              _commitStyle(
                                widget.model
                                    .widgetStyleOf(_selectedKind)
                                    .copyWith(backgroundOpacity: v),
                              ),
                            ),
                          ),
                          if (!isTransparent) ...<Widget>[
                            const Divider(height: 0, indent: 16, endIndent: 16),
                            _LabeledSliderTile(
                              icon: Icons.rounded_corner_rounded,
                              title: '卡片圆角',
                              valueLabel: '${style.cornerRadius.round()} dp',
                              value: style.cornerRadius,
                              min: widgetMinCornerRadius,
                              max: widgetMaxCornerRadius,
                              divisions: 20,
                              defaultValue: 20.0,
                              onChanged: (v) {
                                final prevAtDef =
                                    (style.cornerRadius - 20.0).abs() < 0.5;
                                final atDef = (v - 20.0).abs() < 0.5;
                                _maybeHaptic(atDef, prevAtDef);
                                setState(() => _radiusDraft = v);
                              },
                              onChangeEnd: (v) => unawaited(
                                _commitStyle(
                                  widget.model
                                      .widgetStyleOf(_selectedKind)
                                      .copyWith(cornerRadius: v),
                                ),
                              ),
                            ),
                          ],
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
                            divisions: 9,
                            defaultValue: 1.0,
                            onChanged: (v) {
                              final prevAtDef =
                                  (style.fontScale - 1.0).abs() < 0.02;
                              final atDef = (v - 1.0).abs() < 0.02;
                              _maybeHaptic(atDef, prevAtDef);
                              setState(() => _fontScaleDraft = v);
                            },
                            onChangeEnd: (v) => unawaited(
                              _commitStyle(
                                widget.model
                                    .widgetStyleOf(_selectedKind)
                                    .copyWith(fontScale: v),
                              ),
                            ),
                          ),
                          if (!isNext) ...<Widget>[
                            const Divider(height: 0, indent: 16, endIndent: 16),
                            _OptionRowTile<WidgetDensity>(
                              icon: Icons.density_medium_rounded,
                              title: '信息密度',
                              options: WidgetDensity.values,
                              selected: style.density,
                              labelOf: (v) => v.label,
                              onChanged: (v) => unawaited(
                                _commitStyle(style.copyWith(density: v)),
                              ),
                            ),
                            const Divider(height: 0, indent: 16, endIndent: 16),
                            SwitchListTile(
                              secondary: const Icon(
                                Icons.title_rounded,
                                size: 20,
                              ),
                              title: const Text('显示顶部标题栏'),
                              subtitle: Text(
                                isToday
                                    ? '关闭后更简洁，展示明日安排时仍保留精简提示'
                                    : '显示当前周次与本周日期范围',
                              ),
                              value: style.showHeader,
                              onChanged: (v) => unawaited(
                                _commitStyle(style.copyWith(showHeader: v)),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 18),
                    const SectionTitle('内容显示'),
                    Card(
                      child: Column(
                        children: <Widget>[
                          SwitchListTile(
                            secondary: const Icon(
                              Icons.place_outlined,
                              size: 20,
                            ),
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
                              isWeek
                                  ? '显示左侧节次列'
                                  : isToday
                                  ? '显示上课时间'
                                  : '显示起止时间',
                            ),
                            value: style.showTime,
                            onChanged: (v) => unawaited(
                              _commitStyle(style.copyWith(showTime: v)),
                            ),
                          ),
                          if (!isWeek) ...<Widget>[
                            const Divider(height: 0, indent: 56),
                            SwitchListTile(
                              secondary: const Icon(
                                Icons.event_note_outlined,
                                size: 20,
                              ),
                              title: const Text('融合考试安排'),
                              subtitle: Text(
                                isToday
                                    ? '当天考试按时间混排，无课期展示 7 天内倒计时'
                                    : '优先展示当天考试，近期无课时展示 7 天内倒计时',
                              ),
                              value: style.showExams,
                              onChanged: (v) => unawaited(
                                _commitStyle(style.copyWith(showExams: v)),
                              ),
                            ),
                          ],
                          if (isToday) ...<Widget>[
                            const Divider(height: 0, indent: 56),
                            SwitchListTile(
                              secondary: const Icon(
                                Icons.auto_mode_rounded,
                                size: 20,
                              ),
                              title: const Text('课后自动切明日预告'),
                              subtitle: const Text('当天最后一节课结束后自动预览明日安排'),
                              value: style.autoSwitchTomorrow,
                              onChanged: (v) => unawaited(
                                _commitStyle(
                                  style.copyWith(autoSwitchTomorrow: v),
                                ),
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
                                _commitStyle(
                                  style.copyWith(finishedCourseMode: v),
                                ),
                              ),
                            ),
                          ],
                          if (isWeek) ...<Widget>[
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
                        onPressed: () => unawaited(_resetCurrentKind()),
                      ),
                    ),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewStageHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _PreviewStageHeaderDelegate({
    required this.maxExtent,
    required this.minExtent,
    required this.kind,
    required this.style,
    required this.snapshot,
    required this.previewNow,
    required this.useSampleData,
    required this.wallpaper,
    required this.todayNarrow,
    required this.nextWide,
    required this.pinnedCounts,
    required this.onToggleSampleData,
    required this.onSelectWallpaper,
    required this.onToggleTodayNarrow,
    required this.onToggleNextWide,
    required this.onRequestPin,
  });

  @override
  final double maxExtent;

  @override
  final double minExtent;

  final DesktopWidgetKind kind;
  final DesktopWidgetStyle style;
  final WidgetSnapshot? snapshot;
  final DateTime? previewNow;
  final bool useSampleData;
  final PreviewWallpaper wallpaper;
  final bool todayNarrow;
  final bool nextWide;
  final ValueNotifier<Map<DesktopWidgetKind, int>> pinnedCounts;
  final ValueChanged<bool> onToggleSampleData;
  final ValueChanged<PreviewWallpaper> onSelectWallpaper;
  final ValueChanged<bool> onToggleTodayNarrow;
  final ValueChanged<bool> onToggleNextWide;
  final VoidCallback onRequestPin;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final currentExtent = (maxExtent - shrinkOffset).clamp(
      minExtent,
      maxExtent,
    );
    final collapseT = maxExtent > minExtent
        ? (shrinkOffset / (maxExtent - minExtent)).clamp(0.0, 1.0)
        : 0.0;

    return ColoredBox(
      color: theme.scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
        child: SizedBox(
          height: math.max(0.0, currentExtent - 6),
          child: Card(
            child: Padding(
              padding: EdgeInsets.fromLTRB(
                14,
                10 - collapseT * 2,
                14,
                10 - collapseT * 2,
              ),
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Flexible(
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _CompactChoicePill(
                              icon: useSampleData
                                  ? Icons.auto_awesome_outlined
                                  : Icons.calendar_today_rounded,
                              label: useSampleData ? '示例课表' : '实时课表',
                              highlighted: useSampleData,
                              onTap: () => onToggleSampleData(!useSampleData),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (kind == DesktopWidgetKind.today) ...<Widget>[
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _CompactChoicePill(
                                icon: Icons.swap_horiz_rounded,
                                label: todayNarrow ? '2×2' : '4×2',
                                onTap: () => onToggleTodayNarrow(!todayNarrow),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ] else if (kind == DesktopWidgetKind.next) ...<Widget>[
                        Flexible(
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              child: _CompactChoicePill(
                                icon: Icons.swap_horiz_rounded,
                                label: nextWide ? '4×1' : '2×2',
                                onTap: () => onToggleNextWide(!nextWide),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                      for (final wp in PreviewWallpaper.values)
                        Padding(
                          padding: const EdgeInsets.only(left: 5),
                          child: TactileSurfaceButton(
                            minSize: const Size(24, 24),
                            borderRadius: BorderRadius.circular(12),
                            filled: false,
                            tooltip: wp.label,
                            onTap: () => onSelectWallpaper(wp),
                            child: Center(
                              child: Container(
                                width: 19,
                                height: 19,
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
                  const SizedBox(height: 8),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.medium),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: double.infinity,
                        padding: EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10 - collapseT * 4,
                        ),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: <Color>[
                              wallpaper.startColor,
                              wallpaper.endColor,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: DesktopWidgetPreview(
                              kind: kind,
                              style: style,
                              snapshot: snapshot,
                              useSampleData: useSampleData,
                              todayNarrow: todayNarrow,
                              nextWide: nextWide,
                              now: previewNow,
                              systemBrightness: wallpaper.brightness,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child:
                            ValueListenableBuilder<Map<DesktopWidgetKind, int>>(
                              valueListenable: pinnedCounts,
                              builder: (context, counts, _) {
                                final count = counts[kind] ?? 0;
                                return Text(
                                  count > 0
                                      ? '桌面上已有 $count 个「${kind.label}」'
                                      : '尚未添加到桌面',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: scheme.onSurfaceVariant,
                                  ),
                                );
                              },
                            ),
                      ),
                      TactileActionButton(
                        variant: TactileActionVariant.filled,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 6,
                        ),
                        icon: const Icon(
                          Icons.add_to_home_screen_rounded,
                          size: 16,
                        ),
                        label: const Text(
                          '添加到桌面',
                          style: TextStyle(fontSize: 12.5),
                        ),
                        onPressed: onRequestPin,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _PreviewStageHeaderDelegate oldDelegate) =>
      oldDelegate.maxExtent != maxExtent ||
      oldDelegate.minExtent != minExtent ||
      oldDelegate.kind != kind ||
      oldDelegate.style != style ||
      oldDelegate.snapshot != snapshot ||
      oldDelegate.previewNow != previewNow ||
      oldDelegate.useSampleData != useSampleData ||
      oldDelegate.wallpaper != wallpaper ||
      oldDelegate.todayNarrow != todayNarrow ||
      oldDelegate.nextWide != nextWide;
}

class _KindSegmentedHeader extends StatelessWidget {
  const _KindSegmentedHeader({required this.selected, required this.onSelect});

  final DesktopWidgetKind selected;
  final ValueChanged<DesktopWidgetKind> onSelect;

  static const List<BoxShadow> _kPillShadows = <BoxShadow>[
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.045),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final kinds = DesktopWidgetKind.values;
    return _ZOrderedRow(
      children: <Widget>[
        for (var index = 0; index < kinds.length; index++) ...<Widget>[
          if (index > 0) const SizedBox(width: 8),
          Expanded(
            child: _ZOrderedItem(
              child: () {
                final kind = kinds[index];
                final active = selected == kind;
                return TactileSurfaceButton(
                  minSize: const Size(0, 38),
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                  filled: false,
                  onTap: () => onSelect(kind),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: active
                          ? scheme.primaryContainer
                          : scheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(AppRadius.pill),
                      border: Border.all(
                        color: active
                            ? scheme.primary.withValues(alpha: 0.16)
                            : scheme.outlineVariant.withValues(alpha: 0.28),
                      ),
                      boxShadow: _kPillShadows,
                    ),
                    child: Center(
                      child: Text(
                        kind.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: active
                              ? FontWeight.w600
                              : FontWeight.w500,
                          color: active
                              ? scheme.onPrimaryContainer
                              : scheme.onSurface,
                        ),
                      ),
                    ),
                  ),
                );
              }(),
            ),
          ),
        ],
      ],
    );
  }
}

class _CompactChoicePill extends StatelessWidget {
  const _CompactChoicePill({
    required this.icon,
    required this.label,
    required this.onTap,
    this.highlighted = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = highlighted
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final fg = highlighted ? scheme.onPrimaryContainer : scheme.primary;
    return TactileSurfaceButton(
      minSize: const Size(0, 26),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      filled: false,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(AppRadius.pill),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 13.5, color: fg),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PresetStrip extends StatelessWidget {
  const _PresetStrip({required this.currentPreset, required this.onSelect});

  final WidgetStylePreset currentPreset;
  final ValueChanged<WidgetStylePreset> onSelect;

  static const List<BoxShadow> _kPresetShadows = <BoxShadow>[
    BoxShadow(
      color: Color.fromRGBO(0, 0, 0, 0.045),
      blurRadius: 8,
      offset: Offset(0, 2),
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SingleChildScrollView(
      clipBehavior: Clip.none,
      scrollDirection: Axis.horizontal,
      child: IntrinsicHeight(
        child: _ZOrderedRow(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (var index = 0; index < widgetStylePresets.length; index++) ...[
              if (index > 0) const SizedBox(width: 8),
              _ZOrderedItem(
                child: () {
                  final spec = widgetStylePresets[index];
                  final active = currentPreset == spec.preset;
                  return TactileSurfaceButton(
                    minSize: const Size(0, 56),
                    borderRadius: BorderRadius.circular(AppRadius.medium),
                    filled: false,
                    onTap: () => onSelect(spec.preset),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: active
                            ? scheme.primaryContainer
                            : scheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                        border: Border.all(
                          color: active
                              ? scheme.primary.withValues(alpha: 0.16)
                              : scheme.outlineVariant.withValues(alpha: 0.28),
                        ),
                        boxShadow: _kPresetShadows,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            spec.preset.label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: active
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                              color: active
                                  ? scheme.onPrimaryContainer
                                  : scheme.onSurface,
                            ),
                          ),
                          Text(
                            spec.subtitle,
                            style: TextStyle(
                              fontSize: 10.5,
                              color: active
                                  ? scheme.onPrimaryContainer.withValues(
                                      alpha: 0.78,
                                    )
                                  : scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }(),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 支持将最近按下或悬停的子项自动置顶绘制（Z-order 提升）的横向 Flex 容器，
/// 确保相邻触控按钮在按压放大及回弹动画期间始终完整盖在邻居之上，不被右侧兄弟遮挡。
class _ZOrderedRow extends Flex {
  const _ZOrderedRow({super.children, super.crossAxisAlignment})
    : super(direction: Axis.horizontal, clipBehavior: Clip.none);

  @override
  RenderFlex createRenderObject(BuildContext context) {
    return _RenderZOrderedFlex(
      direction: direction,
      mainAxisAlignment: mainAxisAlignment,
      mainAxisSize: mainAxisSize,
      crossAxisAlignment: crossAxisAlignment,
      textDirection: getEffectiveTextDirection(context),
      verticalDirection: verticalDirection,
      textBaseline: textBaseline,
      clipBehavior: clipBehavior,
    );
  }
}

class _RenderZOrderedFlex extends RenderFlex {
  _RenderZOrderedFlex({
    super.direction,
    super.mainAxisAlignment,
    super.mainAxisSize,
    super.crossAxisAlignment,
    super.textDirection,
    super.verticalDirection,
    super.textBaseline,
    super.clipBehavior,
  });

  RenderBox? _elevatedChild;

  RenderBox? get elevatedChild => _elevatedChild;

  set elevatedChild(RenderBox? value) {
    if (identical(_elevatedChild, value)) return;
    _elevatedChild = value;
    markNeedsPaint();
  }

  @override
  void remove(RenderBox child) {
    if (identical(_elevatedChild, child)) {
      _elevatedChild = null;
    }
    super.remove(child);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderBox? topChild;
    Offset? topOffset;
    RenderBox? child = firstChild;
    while (child != null) {
      final childParentData = child.parentData! as FlexParentData;
      if (identical(child, _elevatedChild)) {
        topChild = child;
        topOffset = childParentData.offset + offset;
      } else {
        context.paintChild(child, childParentData.offset + offset);
      }
      child = childParentData.nextSibling;
    }
    if (topChild != null && topOffset != null) {
      context.paintChild(topChild, topOffset);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final top = _elevatedChild;
    if (top != null && identical(top.parent, this)) {
      final topParentData = top.parentData! as FlexParentData;
      final isHit = result.addWithPaintOffset(
        offset: topParentData.offset,
        position: position,
        hitTest: (BoxHitTestResult result, Offset transformed) {
          return top.hitTest(result, position: transformed);
        },
      );
      if (isHit) return true;
    }
    return defaultHitTestChildren(result, position: position);
  }
}

class _ZOrderedItem extends SingleChildRenderObjectWidget {
  const _ZOrderedItem({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderZOrderedItem();
}

class _RenderZOrderedItem extends RenderProxyBox {
  @override
  void handleEvent(PointerEvent event, BoxHitTestEntry entry) {
    if (event is PointerDownEvent ||
        (event is PointerEnterEvent && event.buttons == 0) ||
        (event is PointerHoverEvent && event.buttons == 0)) {
      final parent = this.parent;
      if (parent is _RenderZOrderedFlex) {
        parent.elevatedChild = this;
      }
    }
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
    required this.defaultValue,
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
  final double defaultValue;
  final ValueChanged<double> onChanged;
  final ValueChanged<double> onChangeEnd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final activeTick = scheme.onPrimary.withValues(alpha: 0.55);
    final idleTick = scheme.onSecondaryContainer.withValues(alpha: 0.35);
    final activeDef = scheme.onPrimary.withValues(alpha: 0.95);
    final idleDef = scheme.primary.withValues(alpha: 0.85);
    final fraction = max > min
        ? ((defaultValue - min) / (max - min)).clamp(0.0, 1.0)
        : 0.0;

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
                  fontFeatures: const <FontFeature>[
                    FontFeature.tabularFigures(),
                  ],
                ),
              ),
            ],
          ),
          SliderTheme(
            data: SliderTheme.of(context).copyWith(
              trackHeight: 10,
              tickMarkShape: SliderTickMarkShape.noTickMark,
              thumbShape: const RoundSliderThumbShape(
                enabledThumbRadius: 10,
                elevation: 2,
                pressedElevation: 4,
              ),
              overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
              trackShape: _WidgetTickedTrackShape(
                divisions: divisions,
                tickFraction: fraction,
                activeTrackColor: scheme.primary,
                idleTrackColor: scheme.secondaryContainer,
                activeTickColor: activeTick,
                idleTickColor: idleTick,
                activeDefaultColor: activeDef,
                idleDefaultColor: idleDef,
              ),
            ),
            child: Slider(
              value: value.clamp(min, max),
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

/// 与 `appearance_sheet.dart` 同款的胶囊轨道 + 居中对齐刻度点 + 默认值圆环靶点。
class _WidgetTickedTrackShape extends RoundedRectSliderTrackShape {
  const _WidgetTickedTrackShape({
    required this.divisions,
    required this.tickFraction,
    required this.activeTrackColor,
    required this.idleTrackColor,
    required this.activeTickColor,
    required this.idleTickColor,
    required this.activeDefaultColor,
    required this.idleDefaultColor,
  });

  final int divisions;
  final double tickFraction;
  final Color activeTrackColor;
  final Color idleTrackColor;
  final Color activeTickColor;
  final Color idleTickColor;
  final Color activeDefaultColor;
  final Color idleDefaultColor;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    if (rect.isEmpty) return;

    final canvas = context.canvas;
    final r = rect.height / 2;
    final radius = Radius.circular(r);
    final thumbX = thumbCenter.dx;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, radius),
      Paint()..color = idleTrackColor,
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTRB(rect.left, rect.top, thumbX, rect.bottom),
        topLeft: radius,
        bottomLeft: radius,
      ),
      Paint()..color = activeTrackColor,
    );

    final cy = rect.center.dy;
    final trackLeft = rect.left + r;
    final trackWidth = rect.width - rect.height;
    final hasDefault = tickFraction >= 0 && tickFraction <= 1;
    final defaultX = trackLeft + trackWidth * tickFraction;

    if (divisions > 0 && trackWidth > 0) {
      final activePaint = Paint()..color = activeTickColor;
      final idlePaint = Paint()..color = idleTickColor;
      for (var i = 0; i <= divisions; i++) {
        final x = trackLeft + trackWidth * (i / divisions);
        if (hasDefault && (x - defaultX).abs() < 0.5) continue;
        canvas.drawCircle(
          Offset(x, cy),
          1.4,
          x <= thumbX ? activePaint : idlePaint,
        );
      }
    }

    if (hasDefault) {
      final onActive = defaultX <= thumbX;
      canvas.drawCircle(
        Offset(defaultX, cy),
        3.0,
        Paint()
          ..color = onActive ? activeDefaultColor : idleDefaultColor
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6,
      );
    }
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
    this.helperText,
  });

  final IconData icon;
  final String title;
  final List<T> options;
  final T selected;
  final String Function(T) labelOf;
  final ValueChanged<T> onChanged;
  final String? helperText;

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
                _OptionPill<T>(
                  label: labelOf(option),
                  selected: selected == option,
                  onTap: () => onChanged(option),
                ),
            ],
          ),
          if (helperText != null) ...<Widget>[
            const SizedBox(height: 8),
            Text(
              helperText!,
              style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionPill<T> extends StatelessWidget {
  const _OptionPill({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bgColor = selected
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest.withValues(alpha: 0.45);
    final fgColor = selected ? scheme.onPrimaryContainer : scheme.onSurface;

    return TactileSurfaceButton(
      minSize: const Size(0, 34),
      borderRadius: BorderRadius.circular(17),
      filled: false,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(17),
        ),
        child: Center(
          widthFactor: 1.0,
          heightFactor: 1.0,
          child: Text(
            label,
            textAlign: TextAlign.center,
            textHeightBehavior: const TextHeightBehavior(
              applyHeightToFirstAscent: false,
              applyHeightToLastDescent: false,
            ),
            style: TextStyle(
              fontSize: 13,
              height: 1.15,
              leadingDistribution: TextLeadingDistribution.even,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
              color: fgColor,
            ),
          ),
        ),
      ),
    );
  }
}
