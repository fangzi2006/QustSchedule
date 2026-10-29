/// 登录页：账号 + 密码；「教务地址 / 高级」可改线路或手填地址。
///
/// 没有"记住密码"开关：这个 app 的密码只为 Cookie 失效后的自动重登服务，
/// 不保存就永远要手输。退出登录会连密码一起清掉。
///
/// 未登录时是全屏独立页（不显示 dock）。
/// 登录进度与报错走右上角的状态弹窗（和课表页同一个组件），
/// 页面本身只保留"切换学校"这类说明性提示。
library;

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/school.dart';
import '../widgets/status_popup.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key, required this.model});

  final AppModel model;

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _addressController = TextEditingController();
  bool _obscure = true;
  bool _advanced = false;

  AppModel get model => widget.model;

  @override
  void initState() {
    super.initState();
    _usernameController.text = model.username;
    _addressController.text = model.schoolBaseUrl;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _addressController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final address = _addressController.text.trim();
    if (!sameSchool(address, model.schoolBaseUrl)) {
      // 换了地址：只切服务端地址，**不**替用户用旧凭据登录 ——
      // 这里用户已经填了账号密码，就用填的这套（见下一行 signIn）。
      await model.changeSchool(address, relogin: false);
      if (!mounted) return;
    }
    FocusScope.of(context).unfocus();
    await model.signIn(
      _usernameController.text.trim(),
      _passwordController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final busy = model.status == AppStatus.signingIn;

    return Scaffold(
      body: Stack(
        children: <Widget>[
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 32, 24, 32),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 400),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Center(
                          child: Container(
                            width: 60,
                            height: 60,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(18),
                            ),
                            child: Icon(
                              Icons.calendar_month_rounded,
                              size: 30,
                              color: scheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          '青科课表通',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          '用教务系统账号登录',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                          ),
                        ),
                        const SizedBox(height: 28),

                        // 说明性提示（"已切换教务地址"之类）。失败原因不在这里，
                        // 走右上角弹窗，免得表单上方堆一大块红字。
                        ListenableBuilder(
                          listenable: model,
                          builder: (context, _) {
                            if (model.message.isEmpty ||
                                model.status == AppStatus.failed) {
                              return const SizedBox.shrink();
                            }
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 14),
                              child: _Banner(
                                message: model.message,
                                isError: false,
                              ),
                            );
                          },
                        ),

                        TextFormField(
                          controller: _usernameController,
                          decoration: const InputDecoration(
                            labelText: '账号',
                            hintText: '学号',
                            prefixIcon: Icon(
                              Icons.person_outline_rounded,
                              size: 20,
                            ),
                          ),
                          keyboardType: TextInputType.text,
                          textInputAction: TextInputAction.next,
                          validator: (value) =>
                              (value == null || value.trim().isEmpty)
                              ? '请输入账号'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          controller: _passwordController,
                          obscureText: _obscure,
                          decoration: InputDecoration(
                            labelText: '密码',
                            prefixIcon: const Icon(
                              Icons.lock_outline_rounded,
                              size: 20,
                            ),
                            suffixIcon: IconButton(
                              icon: Icon(
                                _obscure
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 20,
                              ),
                              onPressed: () =>
                                  setState(() => _obscure = !_obscure),
                            ),
                          ),
                          textInputAction: TextInputAction.done,
                          onFieldSubmitted: (_) => _submit(),
                          validator: (value) =>
                              (value == null || value.isEmpty) ? '请输入密码' : null,
                        ),
                        const SizedBox(height: 16),
                        FilledButton(
                          onPressed: busy ? null : _submit,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            child: busy
                                ? const SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                    ),
                                  )
                                : const Text('登录'),
                          ),
                        ),
                        const SizedBox(height: 10),
                        TextButton.icon(
                          onPressed: () =>
                              setState(() => _advanced = !_advanced),
                          icon: AnimatedRotation(
                            turns: _advanced ? 0.5 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: const Icon(
                              Icons.expand_more_rounded,
                              size: 18,
                            ),
                          ),
                          label: const Text('教务地址 / 高级'),
                        ),
                        // 展开也要有高度动画，和作息表里的折叠项保持一致。
                        AnimatedSize(
                          duration: const Duration(milliseconds: 200),
                          curve: Curves.easeOutCubic,
                          alignment: Alignment.topCenter,
                          child: _advanced
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: <Widget>[
                                    const SizedBox(height: 4),
                                    TextFormField(
                                      controller: _addressController,
                                      decoration: const InputDecoration(
                                        labelText: '教务系统地址',
                                        hintText: 'https://jwglxt1.qust.edu.cn/jwglxt',
                                        helperText:
                                            '支持新正方教务系统，地址写到 /jwglxt 为止',
                                        helperMaxLines: 2,
                                      ),
                                    ),
                                    const SizedBox(height: 10),
                                    Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      children: <Widget>[
                                        for (final school in knownSchools)
                                          ActionChip(
                                            label: Text(school.name),
                                            onPressed: () {
                                              _addressController.text =
                                                  school.baseUrl;
                                              setState(() {});
                                            },
                                          ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      '改完地址后点「登录」，会用上面填写的账号重新登录。',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(color: theme.hintColor),
                                    ),
                                  ],
                                )
                              : const SizedBox(width: double.infinity),
                        ),
                        const SizedBox(height: 24),
                        Text(
                          '适配青岛科技大学 · 密码只存在本机安全存储',
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.hintColor,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 登录进度 / 报错与课表页共用同一个弹窗组件。
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 10,
            child: ListenableBuilder(
              listenable: model,
              builder: (context, _) => StatusPopup(model: model),
            ),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.message, required this.isError});

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isError ? scheme.errorContainer : scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Icon(
            isError ? Icons.error_outline_rounded : Icons.info_outline_rounded,
            size: 18,
            color: isError ? scheme.error : null,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 12,
                height: 1.45,
                color: isError
                    ? scheme.onErrorContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
