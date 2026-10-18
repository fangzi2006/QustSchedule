/// 外观面板：从底部弹出，改完立刻能看到课表变化。
///
/// 两个滑块——课表格子高度、课程卡片文字缩放。做在弹窗里（而不是单独一页）
/// 是因为**预览**：面板只占下半屏，上面的课表实时跟着变，不用来回切换页面。
///
/// 两个滑块在**默认值**处画了一根刻度：用户调乱了以后知道该拖回哪里。
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
  static const int _heightDivisions = 28; // 56..112，每格 2px
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

/// 一行滑块：左边标签、右边当前值、下面轨道（默认值处有一根刻度）。
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
            // `year2023: false` = Flutter 的 2024 版 M3 滑块：16px 粗轨道 +
            // 一根竖条手柄，按下时手柄变细。默认的 2023 版只有 4px 细线，
            // 在弹窗里看着太轻。
            //
            // 这个开关刚被标记为 deprecated（"以后会默认 false"），但现在默认仍是
            // true，不写它就还是细轨道；等默认翻转后这一行变成无害的空操作。
            // ignore: deprecated_member_use
            year2023: false,
            trackHeight: 16,
            trackGap: 6,
            trackShape: _TickedTrackShape(
              tickFraction: fraction,
              activeTickColor: theme.colorScheme.onPrimary,
              idleTickColor: theme.colorScheme.onSecondaryContainer,
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

/// 在轨道上多画一根"默认值"刻度。
///
/// 继承 `GappedSliderTrackShape`（2024 版 M3 的轨道，手柄两侧留缺口）而不是
/// 在 Slider 外面套一层 Stack：只有 `getPreferredRect` 给的矩形才是轨道真正的两端，
/// 而且缺口要按 `thumbCenter` 让位，自己算位置一定会偏。
class _TickedTrackShape extends GappedSliderTrackShape {
  const _TickedTrackShape({
    required this.tickFraction,
    required this.activeTickColor,
    required this.idleTickColor,
  });

  final double tickFraction;

  /// 落在已走过的一段（主色轨道）上的刻度颜色。
  final Color activeTickColor;

  /// 落在未走过的一段（浅色轨道）上的刻度颜色。
  final Color idleTickColor;

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
    double additionalActiveTrackHeight = 2,
  }) {
    super.paint(
      context,
      offset,
      parentBox: parentBox,
      sliderTheme: sliderTheme,
      enableAnimation: enableAnimation,
      textDirection: textDirection,
      thumbCenter: thumbCenter,
      secondaryOffset: secondaryOffset,
      isDiscrete: isDiscrete,
      isEnabled: isEnabled,
      additionalActiveTrackHeight: additionalActiveTrackHeight,
    );
    if (tickFraction < 0 || tickFraction > 1) return;
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final x = rect.left + rect.width * tickFraction;
    // 刻度比轨道高出一点，压在两种底色上都看得见。
    final half = rect.height / 2 + 2;
    final paint = Paint()
      ..color = x <= thumbCenter.dx ? activeTickColor : idleTickColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    context.canvas.drawLine(
      Offset(x, rect.center.dy - half),
      Offset(x, rect.center.dy + half),
      paint,
    );
  }
}
