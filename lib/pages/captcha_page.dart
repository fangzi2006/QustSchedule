/// 验证码页：手动登录与自动重登共用。
library;

import 'dart:convert';

import 'package:flutter/material.dart';

import '../src/app_model.dart';

class CaptchaPage extends StatefulWidget {
  const CaptchaPage({super.key, required this.model});

  final AppModel model;

  @override
  State<CaptchaPage> createState() => _CaptchaPageState();
}

class _CaptchaPageState extends State<CaptchaPage> {
  final _controller = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;

  AppModel get model => widget.model;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final code = _controller.text.trim();
    if (code.isEmpty) return;
    setState(() => _busy = true);
    FocusScope.of(context).unfocus();
    await model.submitCaptcha(code);
    if (!mounted) return;
    setState(() => _busy = false);
    if (model.status != AppStatus.needCaptcha) return;
    _controller.clear();
    _focus.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final captcha = model.captcha;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.close_rounded),
          tooltip: '取消',
          onPressed: model.cancelCaptcha,
        ),
        title: const Text('输入验证码'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (captcha == null)
                    Text(
                      '验证码已过期，请返回重新登录',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium,
                    )
                  else ...<Widget>[
                    Text(
                      '教务系统要求输入验证码',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '看不清就点图片换一张，仍保留当前登录进度',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Center(
                      child: InkWell(
                        onTap: _busy ? null : model.refreshCaptcha,
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.outlineVariant),
                          ),
                          child: Image.memory(
                            base64Decode(captcha.imageBase64),
                            height: 72,
                            fit: BoxFit.contain,
                            gaplessPlayback: true,
                            errorBuilder: (context, error, stack) => SizedBox(
                              height: 72,
                              child: Center(
                                child: Text(
                                  '验证码图片无法显示',
                                  style: theme.textTheme.bodySmall,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 18),
                    TextField(
                      controller: _controller,
                      focusNode: _focus,
                      autofocus: true,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 20,
                        letterSpacing: 6,
                        fontWeight: FontWeight.w500,
                      ),
                      decoration: InputDecoration(
                        hintText: '输入验证码',
                        hintStyle: const TextStyle(
                          fontSize: 15,
                          letterSpacing: 0,
                          fontWeight: FontWeight.w400,
                        ),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.refresh_rounded, size: 20),
                          tooltip: '换一张',
                          onPressed: _busy ? null : model.refreshCaptcha,
                        ),
                      ),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _submit(),
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _busy ? null : _submit,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        child: _busy
                            ? const SizedBox(
                                height: 18,
                                width: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('提交'),
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  ListenableBuilder(
                    listenable: model,
                    builder: (context, _) {
                      if (model.message.isEmpty) return const SizedBox.shrink();
                      return Text(
                        model.message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: model.status == AppStatus.failed
                              ? scheme.error
                              : null,
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
