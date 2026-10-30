/// 设置页：课表 / 账号 / 关于三组。
///
/// - 课表：作息时间表入口、周次校准、显示教师、显示地点、显示课表备注、静默更新；
/// - 账号：身份、教务地址、修改密码、退出登录；
/// - 关于：调试信息、版本号。
///
/// 账号区只有四行：身份、教务地址、修改密码、退出登录。
/// 退出只有一个入口，且**同时清掉保存的密码**——这个 app 不提供"记住密码"开关，
/// 密码只是为了 Cookie 失效时能自动重登。
library;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:zf_academic/zf_academic.dart' show AcademicError;

import '../src/app_model.dart';
import '../src/app_version.dart';
import '../src/preferences_repository.dart';
import '../src/reminder_service.dart';
import '../src/timetable.dart' show formatMonthDayDate;
import '../widgets/floating_dock.dart';
import 'about_page.dart';
import 'reminder_page.dart';
import 'schedule_page.dart' show showCalibrateSheet;
import 'school_address_page.dart';
import 'timetable_list_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.model, this.reminders});

  final AppModel model;

  /// 课程提醒编排层。null = 当前宿主（桌面 / 测试）没有挂它，入口不显示。
  final ReminderService? reminders;

  @override
  Widget build(BuildContext context) {
    // 只听**偏好**的通知源，不听整个 model。
    //
    // 之前听的是 model：任何通知（后台刷新一次课表、切一次周次……）都会让
    // 整页重建一次（实测 21~26ms）。而这些通知多半与设置页显示的内容无关——
    // 用户在设置页里翻两页，却因为后台刷新了一次课表而白白重建一遍；
    // 点进子页面时那一帧尤其明显。
    //
    // [model.prefsNotifier] 只在设置页关心的东西真变了时才发通知。
    return ListenableBuilder(
      listenable: model.prefsNotifier,
      builder: (context, _) {
        final theme = Theme.of(context);
        final active = model.activeTimetable;
        return Scaffold(
          appBar: AppBar(title: const Text('设置')),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              FloatingDock.contentInset(context),
            ),
            children: <Widget>[
              _SectionTitle('课表'),
              Card(
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.schedule_rounded, size: 20),
                      title: const Text('作息时间表'),
                      subtitle: Text(
                        active == null
                            ? '未配置'
                            : '${active.name} · ${active.sectionCount} 节 · ${formatMonthDayDate(active.effectiveFrom)} 起',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => TimetableListPage(model: model),
                        ),
                      ),
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.date_range_rounded, size: 20),
                      title: const Text('学期周次校准'),
                      subtitle: Text(
                        model.termStart == null
                            ? '未定位'
                            : '今天第 ${model.currentWeekOfToday} 周 · 第 1 周 ${_dateText(model.termStart!)} 起',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showCalibrateSheet(context, model),
                    ),
                    if (reminders != null &&
                        defaultTargetPlatform ==
                            TargetPlatform.android) ...<Widget>[
                      const Divider(height: 0, indent: 56),
                      ListTile(
                        leading: const Icon(
                          Icons.notifications_active_outlined,
                          size: 20,
                        ),
                        title: const Text('课程提醒'),
                        subtitle: Text(
                          model.reminderEnabled
                              ? '已开启 · 提前 ${model.reminderLeadMinutes} 分钟'
                              : '未开启',
                        ),
                        trailing: const Icon(Icons.chevron_right_rounded),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) =>
                                ReminderPage(model: model, service: reminders!),
                          ),
                        ),
                      ),
                    ],
                    const Divider(height: 0, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                      ),
                      title: const Text('显示教师'),
                      subtitle: const Text('在课表格子中展示授课教师'),
                      value: model.showTeacher,
                      onChanged: model.setShowTeacher,
                    ),
                    const Divider(height: 0, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(Icons.place_outlined, size: 20),
                      title: const Text('显示上课地点'),
                      subtitle: const Text('在课表格子中展示上课地点'),
                      value: model.showLocation,
                      onChanged: model.setShowLocation,
                    ),
                    const Divider(height: 0, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(
                        Icons.sticky_note_2_outlined,
                        size: 20,
                      ),
                      title: const Text('显示课表备注'),
                      subtitle: const Text('课表页下方显示实践课程与其他课程'),
                      value: model.showScheduleRemarks,
                      onChanged: model.setShowScheduleRemarks,
                    ),
                    const Divider(height: 0, indent: 56),
                    SwitchListTile(
                      secondary: const Icon(Icons.sync_rounded, size: 20),
                      title: const Text('静默更新'),
                      subtitle: const Text('打开 App 时自动刷新课表'),
                      value: model.autoRefresh,
                      onChanged: model.setAutoRefresh,
                    ),
                    if (model.autoRefresh) ...<Widget>[
                      const Divider(height: 0, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined, size: 20),
                        title: const Text('最小更新间隔'),
                        subtitle: Text(
                          _formatInterval(model.autoRefreshIntervalMinutes),
                        ),
                        trailing: _IntervalStepper(
                          value: model.autoRefreshIntervalMinutes,
                          onChanged: model.setAutoRefreshIntervalMinutes,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SectionTitle('账号'),
              Card(
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(
                        Icons.person_outline_rounded,
                        size: 20,
                      ),
                      title: Text(_accountTitle),
                      subtitle: Text(_accountSubtitle),
                      trailing: model.signedIn
                          ? const Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: Color(0xFF2E7D32),
                            )
                          : null,
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.link_rounded, size: 20),
                      title: const Text('教务地址'),
                      subtitle: Text(
                        model.schoolBaseUrl,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => SchoolAddressPage(model: model),
                        ),
                      ),
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.password_rounded, size: 20),
                      title: const Text('修改密码'),
                      subtitle: const Text('修改教务密码后，在此更新本机保存的密码'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => _changePassword(context),
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: Icon(
                        Icons.logout_rounded,
                        size: 20,
                        color: theme.colorScheme.error,
                      ),
                      title: Text(
                        '退出登录',
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                      subtitle: const Text('同时清除保存的账号密码'),
                      onTap: () => _confirmSignOut(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _SectionTitle('关于'),
              Card(
                child: Column(
                  children: <Widget>[
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded, size: 20),
                      title: const Text('关于青科课表通'),
                      subtitle: Text('v$appVersion · 检查更新、日志、协议'),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => AboutPage(model: model),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 姓名 → "已登录 / 未登录"（学号放在副标题里，避免两行重复）。
  ///
  /// 不能只看姓名：Cookie 免登时姓名可能读不到（课表照样能取）。
  String get _accountTitle {
    if (model.studentName.isNotEmpty) return model.studentName;
    return model.signedIn ? '已登录' : '未登录';
  }

  String get _accountSubtitle {
    if (model.studentId.isNotEmpty) return '学号 ${model.studentId}';
    if (model.username.isNotEmpty) return model.username;
    return model.signedIn ? '已连接教务系统' : '尚未登录';
  }

  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('退出登录？'),
        content: const Text('会清除当前会话与保存的学号密码，下次需要重新输入。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) await model.signOut();
  }

  Future<void> _changePassword(BuildContext context) async {
    final password = await showDialog<String>(
      context: context,
      builder: (context) => const _PasswordDialog(),
    );
    if (password == null) return;
    try {
      await model.changePassword(password);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('密码已更新')));
    } on AcademicError catch (error) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('修改失败'),
          content: Text(error.message),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('知道了'),
            ),
          ],
        ),
      );
    }
  }

  static String _dateText(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

/// 修改密码：两次输入 + 一句"会用新密码登录验证"。
class _PasswordDialog extends StatefulWidget {
  const _PasswordDialog();

  @override
  State<_PasswordDialog> createState() => _PasswordDialogState();
}

class _PasswordDialogState extends State<_PasswordDialog> {
  final _formKey = GlobalKey<FormState>();
  final _password = TextEditingController();
  final _confirm = TextEditingController();
  bool _obscure = true;

  @override
  void dispose() {
    _password.dispose();
    _confirm.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.of(context).pop(_password.text);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('修改密码'),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '先到教务网页改密码，再在这里填新密码。\n'
              '确定后会先用新密码登录验证，成功才替换本机保存的密码。',
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: Theme.of(context).hintColor),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _password,
              obscureText: _obscure,
              autofocus: true,
              decoration: InputDecoration(
                labelText: '新密码',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 20,
                  ),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: (value) =>
                  (value == null || value.isEmpty) ? '请输入新密码' : null,
            ),
            const SizedBox(height: 8),
            TextFormField(
              controller: _confirm,
              obscureText: _obscure,
              decoration: const InputDecoration(labelText: '确认新密码'),
              onFieldSubmitted: (_) => _submit(),
              validator: (value) => value == _password.text ? null : '两次输入不一致',
            ),
          ],
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('确定')),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
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

/// 最小更新间隔的步进器：- / + 各 5 分钟，夹在合法区间内。
String _formatInterval(int minutes) {
  final hours = minutes ~/ 60;
  final rem = minutes % 60;
  if (rem == 0) return '$hours 小时';
  return '$hours 小时 $rem 分钟';
}

class _IntervalStepper extends StatelessWidget {
  const _IntervalStepper({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final hours = (value / 60).round();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IconButton(
          icon: const Icon(Icons.remove_circle_outline_rounded, size: 22),
          visualDensity: VisualDensity.compact,
          onPressed: value > minAutoRefreshIntervalMinutes
              ? () => onChanged(((value - 1) ~/ 60) * 60)
              : null,
        ),
        Text('$hours', style: const TextStyle(fontSize: 14)),
        IconButton(
          icon: const Icon(Icons.add_circle_outline_rounded, size: 22),
          visualDensity: VisualDensity.compact,
          onPressed: value < maxAutoRefreshIntervalMinutes
              ? () => onChanged(((value ~/ 60) + 1) * 60)
              : null,
        ),
      ],
    );
  }
}
