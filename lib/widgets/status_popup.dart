/// 状态弹窗：登录 / 取课表 / 重新登录 / 报错，统一从这里出。
///
/// 为什么不做整屏 loading：课表是常驻页面，切走再切回、后台刷新时都不该
/// 被一屏转圈打断。所以进度与错误都收进这个右上角的小卡片：
///  - 进行中：转圈 + 一句话（"正在登录…" / "正在获取课表…" / "正在重新登录…"）；
///  - 成功：打勾，1~2 秒后自动消失；
///  - 失败：红框 + 动作按钮（重试 / 重新登录 / 调试 / 关闭），需用户处理后才消失；
///    没有课表时不提供"重试"——那会去查课表而不是重新登录。
library;

import 'package:flutter/material.dart';

import '../src/app_model.dart';

class StatusPopup extends StatelessWidget {
  const StatusPopup({super.key, required this.model, this.onOpenDebug});

  final AppModel model;
  final VoidCallback? onOpenDebug;

  @override
  Widget build(BuildContext context) {
    final data = _resolve();
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      layoutBuilder: (currentChild, previousChildren) {
        return Stack(
          alignment: Alignment.topRight,
          children: <Widget>[
            ...previousChildren,
            if (currentChild != null) currentChild,
          ],
        );
      },
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.10),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: data == null
          ? const SizedBox.shrink(key: ValueKey<String>('status-none'))
          : _Bubble(
              key: ValueKey<String>('status-${data.text}-${data.error}'),
              data: data,
              canRetry: model.schedule != null,
              onDismiss: model.status == AppStatus.failed
                  ? model.dismissError
                  : model.clearHint,
              onRetry: model.errorCode == 'SESSION_EXPIRED'
                  ? model.retryAfterSessionLoss
                  : model.refresh,
              retryLabel: model.errorCode == 'SESSION_EXPIRED' ? '重新登录' : '重试',
              onOpenDebug: onOpenDebug,
            ),
    );
  }

  /// 优先级：错误 > 登录页/验证码页（不弹）> 登录中 > 提示语 > 加载 > 启动。
  _PopupData? _resolve() {
    if (model.status == AppStatus.failed) {
      return _PopupData(
        text: model.message.isEmpty ? '加载失败' : model.message,
        error: true,
        showActions: true,
      );
    }
    // 登录页与验证码页自己就是"当前任务"，弹窗只会挡住表单。
    // 而且这几页的状态切换很频繁，残留的 hint 容易变成一个永远转的圈。
    if (model.status == AppStatus.needLogin ||
        model.status == AppStatus.needCaptcha) {
      return null;
    }
    if (model.status == AppStatus.signingIn) {
      return const _PopupData(text: '登录中…', busy: true);
    }
    if (model.hint.isNotEmpty) {
      final error = model.hintIsError;
      return _PopupData(
        text: model.hint,
        busy: model.refreshing && !error,
        error: error,
      );
    }
    if (model.status == AppStatus.loading) {
      return const _PopupData(text: '获取中…', busy: true);
    }
    if (model.status == AppStatus.booting) {
      return const _PopupData(text: '连接中…', busy: true);
    }
    return null;
  }
}

class _PopupData {
  const _PopupData({
    required this.text,
    this.busy = false,
    this.error = false,
    this.showActions = false,
  });

  final String text;
  final bool busy;
  final bool error;
  final bool showActions;
}

class _Bubble extends StatelessWidget {
  const _Bubble({
    super.key,
    required this.data,
    required this.canRetry,
    required this.onDismiss,
    required this.onRetry,
    required this.retryLabel,
    this.onOpenDebug,
  });

  final _PopupData data;
  final bool canRetry;
  final VoidCallback onDismiss;
  final VoidCallback onRetry;
  final String retryLabel;
  final VoidCallback? onOpenDebug;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final error = data.error;
    final accent = error ? scheme.error : const Color(0xFF2E7D32);

    return Container(
      constraints: const BoxConstraints(minWidth: 0, maxWidth: 200),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: error
              ? scheme.error.withValues(alpha: 0.40)
              : scheme.outlineVariant,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: data.showActions ? null : onDismiss,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (data.busy)
                    const SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(strokeWidth: 1.7),
                    )
                  else
                    Icon(
                      error
                          ? Icons.error_outline_rounded
                          : Icons.check_circle_outline_rounded,
                      size: 15,
                      color: accent,
                    ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      data.text,
                      softWrap: true,
                      style: TextStyle(
                        fontSize: 12,
                        height: 1.35,
                        color: error ? scheme.error : scheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (data.showActions)
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: <Widget>[
                  if (canRetry && onOpenDebug != null)
                    _TinyAction(label: '调试', onTap: onOpenDebug!),
                  _TinyAction(label: '关闭', onTap: onDismiss),
                  if (canRetry) ...<Widget>[
                    const SizedBox(width: 4),
                    FilledButton(
                      onPressed: onRetry,
                      style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        minimumSize: const Size(0, 30),
                        textStyle: const TextStyle(fontSize: 12),
                      ),
                      child: Text(retryLabel),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _TinyAction extends StatelessWidget {
  const _TinyAction({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onTap,
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        minimumSize: const Size(0, 30),
        textStyle: const TextStyle(fontSize: 12),
      ),
      child: Text(label),
    );
  }
}
