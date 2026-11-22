/// 路由入场转场期间使用的超轻量静态占位骨架：
///
/// 零 Ticker、零文本排版、零 `SelectionArea`、零抗锯齿裁剪，仅用极少数纯色圆角矩形
/// 维持视觉连续性，避免 260ms 滑入动画期间出现空白闪烁或重子树构建卡顿。
library;

import 'package:flutter/material.dart';

/// 卡片列表型页面（如更新日志、调试页）的轻量入场占位。
class CardListTransitionPlaceholder extends StatelessWidget {
  const CardListTransitionPlaceholder({
    super.key,
    this.cardCount = 2,
    this.padding = const EdgeInsets.fromLTRB(16, 12, 16, 24),
  });

  final int cardCount;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surfaceContainerLowest;
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.35);
    final barPrimary = scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final barSecondary = scheme.surfaceContainerHighest.withValues(alpha: 0.35);

    return ExcludeSemantics(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        children: <Widget>[
          for (var i = 0; i < cardCount; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: _SkeletonBar(
                            maxWidth: 84,
                            height: 18,
                            color: barPrimary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Spacer(),
                        Flexible(
                          child: _SkeletonBar(
                            maxWidth: 68,
                            height: 12,
                            color: barSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    _SkeletonBar(height: 44, radius: 8, color: barSecondary),
                    const SizedBox(height: 14),
                    _SkeletonBar(maxWidth: 64, height: 20, color: barPrimary),
                    const SizedBox(height: 10),
                    _SkeletonBar(height: 14, color: barSecondary),
                    const SizedBox(height: 8),
                    _SkeletonBar(
                      widthFactor: 0.72,
                      height: 14,
                      color: barSecondary,
                    ),
                    if (i == 0) ...<Widget>[
                      const SizedBox(height: 8),
                      _SkeletonBar(height: 14, color: barSecondary),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 纯文档段落型页面（如开源协议全文）的轻量入场占位。
class DocumentTransitionPlaceholder extends StatelessWidget {
  const DocumentTransitionPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final barPrimary = scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final barSecondary = scheme.surfaceContainerHighest.withValues(alpha: 0.35);

    return ExcludeSemantics(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
        children: <Widget>[
          _SkeletonBar(widthFactor: 0.58, height: 18, color: barPrimary),
          const SizedBox(height: 16),
          for (var i = 0; i < 4; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 18),
            _SkeletonBar(height: 13, color: barSecondary),
            const SizedBox(height: 8),
            _SkeletonBar(height: 13, color: barSecondary),
            const SizedBox(height: 8),
            _SkeletonBar(
              widthFactor: i.isEven ? 0.64 : 0.78,
              height: 13,
              color: barSecondary,
            ),
          ],
        ],
      ),
    );
  }
}

/// 顶部预览舞台 + 下方配置卡片型页面（如桌面小组件设置页）的轻量入场占位。
class PreviewSettingsTransitionPlaceholder extends StatelessWidget {
  const PreviewSettingsTransitionPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final surface = scheme.surfaceContainerLowest;
    final borderColor = scheme.outlineVariant.withValues(alpha: 0.35);
    final barPrimary = scheme.surfaceContainerHighest.withValues(alpha: 0.55);
    final barSecondary = scheme.surfaceContainerHighest.withValues(alpha: 0.35);

    return ExcludeSemantics(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: <Widget>[
          // 顶部预览舞台轮廓
          DecoratedBox(
            decoration: BoxDecoration(
              color: surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: borderColor),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _SkeletonBar(height: 36, radius: 18, color: barSecondary),
                  const SizedBox(height: 14),
                  _SkeletonBar(height: 148, radius: 16, color: barSecondary),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          for (var i = 0; i < 2; i++) ...<Widget>[
            if (i > 0) const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _SkeletonBar(maxWidth: 96, height: 16, color: barPrimary),
                    const SizedBox(height: 12),
                    _SkeletonBar(height: 44, radius: 10, color: barSecondary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SkeletonBar extends StatelessWidget {
  const _SkeletonBar({
    required this.height,
    required this.color,
    this.maxWidth,
    this.widthFactor,
    this.radius = 6,
  });

  final double? maxWidth;
  final double? widthFactor;
  final double height;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    Widget bar = SizedBox(
      width: maxWidth ?? double.infinity,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
    if (widthFactor != null) {
      bar = Align(
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(widthFactor: widthFactor, child: bar),
      );
    }
    return bar;
  }
}
