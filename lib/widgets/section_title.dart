import 'package:flutter/material.dart';

/// 统一的页面分组小标题（小号浅灰紧凑风，次级引导不抢卡片主体视线）。
class SectionTitle extends StatelessWidget {
  const SectionTitle(
    this.text, {
    super.key,
    this.padding = const EdgeInsets.fromLTRB(4, 8, 4, 8),
  });

  final String text;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: Theme.of(context).hintColor,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
