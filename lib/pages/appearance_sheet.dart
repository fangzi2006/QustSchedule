/// 外观面板：从底部弹出，改完立刻能看到课表变化。
///
/// 两个滑块——课表格子高度、课程卡片文字缩放。做在弹窗里（而不是单独一页）
/// 是因为**预览**：面板只占下半屏，上面的课表实时跟着变，不用来回切换页面。
///
/// 两个滑块在**默认值**处画了圆环靶点标记：用户调乱了以后知道该拖回哪里。
/// 拖到刻度附近会触发一次短震动（只在手机上有感觉，桌面端是空操作）。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_model.dart';
import '../src/preferences_repository.dart';

/// 弹出外观面板。
Future<void> showAppearanceSheet(BuildContext context, AppModel model) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    // 遮罩很淡：面板的目的就是"边拖边看课表"，压暗了还预览什么。
    barrierColor: Colors.black.withValues(alpha: 0.06),
    builder: (_) => _AppearanceSheet(model: model),
  );
}

class _AppearanceSheet extends StatefulWidget {
  const _AppearanceSheet({required this.model});

  final AppModel model;

  @override
  State<_AppearanceSheet> createState() => _AppearanceSheetState();
}

class _AppearanceSheetState extends State<_AppearanceSheet> {
  static const int _heightDivisions = 35; // 50..120，每格 2px
  static const int _scaleDivisions = 12; // 0.8..1.4，每格 0.05

  /// 上一次是不是停在默认值上：只在"刚刚进入默认值"那一刻震一下。
  bool _heightAtDefault = true;
  bool _scaleAtDefault = true;

  AppModel get model => widget.model;

  @override
  void dispose() {
    // 关面板（包括点外面关掉）立即落盘，不等防抖定时器。
    model.flushAppearance();
    super.dispose();
  }

  /// 拖到默认值附近时给一次短震动。
  ///
  /// 桌面端 `HapticFeedback` 没有实现，硬调也不会有反应，
  /// 所以按平台判断——免得在 Windows 上白跑一次平台通道。
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

  @override
  Widget build(BuildContext context) {
    // **必须订阅 model**：滑块拿到的 `value` 只在这个 build 里读一次，
    // 不重建的话拇指永远停在按下时的位置（课表那边动了，滑块却不动）。
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final theme = Theme.of(context);
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('外观', style: theme.textTheme.titleMedium),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        model.setCellHeight(defaultCellHeight);
                        model.setCourseTextScale(defaultCourseTextScale);
                        _heightAtDefault = true;
                        _scaleAtDefault = true;
                      },
                      child: const Text('恢复默认'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                _SliderRow(
                  label: '课表格子高度',
                  valueText: '${model.cellHeight.round()}',
                  min: minCellHeight,
                  max: maxCellHeight,
                  divisions: _heightDivisions,
                  defaultValue: defaultCellHeight,
                  value: model.cellHeight,
                  onChanged: (value) {
                    final atDefault = (value - defaultCellHeight).abs() < 1;
                    _maybeHaptic(atDefault, _heightAtDefault);
                    _heightAtDefault = atDefault;
                    model.setCellHeight(value);
                  },
                ),
                const SizedBox(height: 6),
                _SliderRow(
                  label: '课程文字大小',
                  valueText: '${(model.courseTextScale * 100).round()}%',
                  min: minCourseTextScale,
                  max: maxCourseTextScale,
                  divisions: _scaleDivisions,
                  defaultValue: defaultCourseTextScale,
                  value: model.courseTextScale,
                  onChanged: (value) {
                    final atDefault =
                        (value - defaultCourseTextScale).abs() < 0.026;
                    _maybeHaptic(atDefault, _scaleAtDefault);
                    _scaleAtDefault = atDefault;
                    model.setCourseTextScale(value);
                  },
                ),
                const SizedBox(height: 2),
                Text(
                  '只影响课程卡片里的文字与行高，时间列和其他文字不变。',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.hintColor,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// 一行滑块：左边标签、右边当前值、下面圆形滑柄轨道（默认值处有圆环靶点）。
class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueText,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.defaultValue,
    required this.onChanged,
  });

  final String label;
  final String valueText;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final double defaultValue;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final activeTick = scheme.onPrimary.withValues(alpha: 0.55);
    final idleTick = scheme.onSecondaryContainer.withValues(alpha: 0.35);
    final activeDef = scheme.onPrimary.withValues(alpha: 0.95);
    final idleDef = scheme.primary.withValues(alpha: 0.85);
    final fraction = max > min
        ? ((defaultValue - min) / (max - min)).clamp(0.0, 1.0)
        : 0.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              valueText,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.hintColor,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 10,
            thumbShape: const RoundSliderThumbShape(
              enabledThumbRadius: 10,
              elevation: 2,
              pressedElevation: 4,
            ),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 20),
            // 禁用内置 tickMark：Flutter 内置刻度向内缩进 trackHeight / 2，
            // 会与 thumbCenter 的坐标系错位。刻度与默认点统一在轨道里按同一坐标系绘制。
            tickMarkShape: SliderTickMarkShape.noTickMark,
            trackShape: _TickedTrackShape(
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
          ),
        ),
      ],
    );
  }
}

/// 胶囊轨道 + 与圆形滑柄中心严格对齐的刻度点与默认值圆环标记。
///
/// 为什么自己画轨道和刻度：
///  1. `GappedSliderTrackShape` 会在滑柄两侧留缺口，填充条右端到不了滑柄中心；
///  2. Flutter 内置 `RoundSliderTickMarkShape` 按 `trackWidth - trackHeight`
///     向内缩进算刻度，而 `RenderSlider` 的 `thumbCenter.dx` 按全宽 `trackWidth`
///     线性插值，两者在非中点处必然错位。
/// 这里统一用 `rect.left + rect.width * t` 算填充条、刻度点与默认位置标记，
/// 保证圆形滑柄中心、填充条右端、当前刻度点、默认位置标记四者完全对齐。
class _TickedTrackShape extends SliderTrackShape with BaseSliderTrackShape {
  const _TickedTrackShape({
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
    final left = rect.left - r;
    final right = rect.right + r;
    final top = rect.top;
    final bottom = rect.bottom;
    final thumbX = thumbCenter.dx;

    // 1. 完整底轨：两端向外延展半个轨道高度，让半圆端帽自然包住首尾刻度点。
    final fullRect = Rect.fromLTRB(left, top, right, bottom);
    final fullRRect = RRect.fromRectAndRadius(fullRect, radius);
    canvas.drawRRect(fullRRect, Paint()..color = idleTrackColor);

    // 2. 已填充轨道：左端带圆角，右端严格停在圆形滑柄中心 thumbCenter.dx。
    final activeRect = Rect.fromLTRB(left, top, thumbX, bottom);
    final activeRRect = RRect.fromRectAndCorners(
      activeRect,
      topLeft: radius,
      bottomLeft: radius,
    );
    canvas.drawRRect(activeRRect, Paint()..color = activeTrackColor);

    final cy = rect.center.dy;
    final hasDefault = tickFraction >= 0 && tickFraction <= 1;
    final defaultX = rect.left + rect.width * tickFraction;

    // 3. 分段刻度点：与 RenderSlider 计算 thumbCenter.dx 用同一线性坐标。
    if (divisions > 0) {
      final activePaint = Paint()..color = activeTickColor;
      final idlePaint = Paint()..color = idleTickColor;
      for (var i = 0; i <= divisions; i++) {
        final x = rect.left + rect.width * (i / divisions);
        if (hasDefault && (x - defaultX).abs() < 0.5) continue;
        final paint = x <= thumbX ? activePaint : idlePaint;
        canvas.drawCircle(Offset(x, cy), 1.5, paint);
      }
    }

    // 4. 默认值标记：同心圆环靶点，严格落在默认刻度坐标上；
    //    滑柄停在默认值时正中覆盖它，滑开后露出圆环提示归位点。
    if (hasDefault) {
      final onActive = defaultX <= thumbX;
      final ringColor = onActive ? activeDefaultColor : idleDefaultColor;
      final ringPaint = Paint()
        ..color = ringColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6;
      canvas.drawCircle(Offset(defaultX, cy), 3.0, ringPaint);
    }
  }
}