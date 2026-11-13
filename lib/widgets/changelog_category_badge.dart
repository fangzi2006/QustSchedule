import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 更新日志与更新弹窗共用的分类标签徽章（新增 / 优化 / 修复 / 碎碎念）。
class ChangelogCategoryBadge extends StatelessWidget {
  const ChangelogCategoryBadge({
    super.key,
    required this.title,
    this.backgroundAlpha = 0.12,
  });

  final String title;
  final double backgroundAlpha;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final (Color color, IconData icon) = switch (title) {
      final t when t.contains('新增') => (
        colors.categoryAdd,
        Icons.add_circle_outline_rounded,
      ),
      final t when t.contains('优化') => (
        colors.categoryImprove,
        Icons.auto_awesome_outlined,
      ),
      final t when t.contains('修复') => (
        colors.categoryFix,
        Icons.build_circle_outlined,
      ),
      final t when t.contains('碎碎念') => (
        colors.categoryNote,
        Icons.chat_bubble_outline_rounded,
      ),
      _ => (scheme.primary, Icons.label_outline_rounded),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: backgroundAlpha),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 5),
          Text(
            title,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
