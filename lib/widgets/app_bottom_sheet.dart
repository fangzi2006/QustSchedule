/// 应用底部弹窗公共容器与呼出封装。
///
/// 统一样式细节与手势句柄（[showDragHandle]），并为长内容弹窗提供带安全区、
/// 80% 屏高上限及内边距的可滚动外框 [ScrollableBottomSheetFrame]。
library;

import 'package:flutter/material.dart';

/// 按全应用默认视觉规格呼出底部弹窗。
Future<T?> showAppModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool isScrollControlled = true,
  bool showDragHandle = true,
  Color? barrierColor,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    showDragHandle: showDragHandle,
    barrierColor: barrierColor,
    builder: builder,
  );
}

/// 底部弹窗的标准可滚动内容框架：带底部安全区，并在屏高 [maxHeightFactor] 内自适应高度。
class ScrollableBottomSheetFrame extends StatelessWidget {
  const ScrollableBottomSheetFrame({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.fromLTRB(20, 0, 20, 24),
    this.maxHeightFactor = 0.8,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double maxHeightFactor;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * maxHeightFactor,
        ),
        child: SingleChildScrollView(padding: padding, child: child),
      ),
    );
  }
}
