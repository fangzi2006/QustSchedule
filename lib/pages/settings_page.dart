/// 设置页：课表 / 提醒与小组件（仅 Android） / 账号 / 关于与更新。
///
/// - 课表：作息时间表入口、周次校准、显示教师、显示地点、显示课表备注、静默更新（课表与学业数据同步）；
/// - 提醒与小组件：课程提醒、桌面小组件，以及忽略电池优化、精确闹钟、自启动权限检查；
/// - 账号：身份、教务地址、修改密码、退出登录；
/// - 关于与更新：自动检查新版本（应用安装包）、关于（调试信息、版本号）。
///
/// 账号区只有四行：身份、教务地址、修改密码、退出登录。
/// 退出只有一个入口，且**同时清掉保存的密码**——这个 app 不提供"记住密码"开关，
/// 密码只是为了 Cookie 失效时能自动重登。
library;

import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter/material.dart';
import 'package:zf_academic/zf_academic.dart' show AcademicError;

import '../src/app_model.dart';
import '../src/app_version.dart';
import '../src/preferences_repository.dart';
import '../src/reminder_gateway.dart';
import '../src/reminder_service.dart';
import '../src/route_settled.dart';
import '../src/term_calendar.dart' show formatIsoDate;
import '../src/timetable.dart' show formatMonthDayDate;
import '../src/widget_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snack_bar.dart';
import '../widgets/calibrate_sheet.dart';
import '../widgets/floating_dock.dart';
import '../widgets/reminder_permission_tile.dart';
import '../widgets/section_title.dart';
import '../widgets/tactile_button.dart';
import 'about_page.dart';
import 'reminder_page.dart';
import 'school_address_page.dart';
import 'timetable_list_page.dart';
import 'widget_settings_page.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    super.key,
    required this.model,
    this.reminders,
    this.desktopWidgets,
  });

  final AppModel model;

  /// 课程提醒编排层。null = 当前宿主（桌面 / 测试）没有挂它，入口不显示。
  final ReminderService? reminders;

  /// 桌面小组件编排层。仅 Android 挂上，桌面端 / 测试为 null 时不显示入口。
  final DesktopWidgetService? desktopWidgets;

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
          appBar: TactileAppBar(title: const Text('设置')),
          body: ListView(
            padding: EdgeInsets.fromLTRB(
              16,
              4,
              16,
              FloatingDock.contentInset(context),
            ),
            children: <Widget>[
              const SectionTitle('课表'),
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
                            : '今天第 ${model.currentWeekOfToday} 周 · 第 1 周 ${formatIsoDate(model.termStart!)} 起',
                      ),
                      trailing: const Icon(Icons.chevron_right_rounded),
                      onTap: () => showCalibrateSheet(context, model),
                    ),
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
                      title: const Text('自动同步课表与学业'),
                      subtitle: const Text('打开 App 时自动同步数据'),
                      value: model.autoRefresh,
                      onChanged: model.setAutoRefresh,
                    ),
                    if (model.autoRefresh) ...<Widget>[
                      const Divider(height: 0, indent: 56),
                      ListTile(
                        leading: const Icon(Icons.timer_outlined, size: 20),
                        title: const Text('最小同步间隔'),
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
              if (defaultTargetPlatform == TargetPlatform.android &&
                  (reminders != null || desktopWidgets != null)) ...<Widget>[
                const SizedBox(height: 18),
                const SectionTitle('提醒与小组件'),
                _ReminderAndWidgetCard(
                  model: model,
                  reminders: reminders,
                  desktopWidgets: desktopWidgets,
                ),
              ],
              const SizedBox(height: 18),
              const SectionTitle('账号'),
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
                          ? Icon(
                              Icons.check_circle_rounded,
                              size: 18,
                              color: AppColors.of(context).success,
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
              const SectionTitle('关于与更新'),
              Card(
                child: Column(
                  children: <Widget>[
                    SwitchListTile(
                      secondary: const Icon(Icons.autorenew_rounded, size: 20),
                      title: const Text('自动检查新版本'),
                      subtitle: const Text('启动应用时检测是否有新版本安装包'),
                      value: model.autoCheckUpdate,
                      onChanged: model.setAutoCheckUpdate,
                    ),
                    const Divider(height: 0, indent: 56),
                    ListTile(
                      leading: const Icon(Icons.info_outline_rounded, size: 20),
                      title: const Text('关于'),
                      subtitle: Text('v$appVersion · 检查更新、代理、协议'),
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
          TactileActionButton(
            variant: TactileActionVariant.text,
            onPressed: () => Navigator.of(context).pop(false),
            label: const Text('取消'),
          ),
          TactileActionButton(
            variant: TactileActionVariant.filled,
            onPressed: () => Navigator.of(context).pop(true),
            label: const Text('退出'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await model.signOut();
      unawaited(reminders?.cancelAll());
      unawaited(desktopWidgets?.syncNow());
    }
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
      showAppSnackBar(
        context,
        message: '密码已更新',
        type: AppSnackBarType.success,
        aboveDock: true,
      );
    } on AcademicError catch (error) {
      if (!context.mounted) return;
      showAppSnackBar(
        context,
        message: '修改失败：${error.message}',
        type: AppSnackBarType.error,
        aboveDock: true,
        duration: const Duration(seconds: 4),
      );
    }
  }
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
        TactileActionButton(
          variant: TactileActionVariant.text,
          onPressed: () => Navigator.of(context).pop(),
          label: const Text('取消'),
        ),
        TactileActionButton(
          variant: TactileActionVariant.filled,
          onPressed: _submit,
          label: const Text('确定'),
        ),
      ],
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
        TactileIconButton(
          icon: const Icon(Icons.remove_rounded),
          size: 32,
          iconSize: 20,
          surfaceStyle: TactileSurfaceStyle.tinted,
          onPressed: value > minAutoRefreshIntervalMinutes
              ? () => onChanged(((value - 1) ~/ 60) * 60)
              : null,
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: Text('$hours', style: const TextStyle(fontSize: 14)),
        ),
        TactileIconButton(
          icon: const Icon(Icons.add_rounded),
          size: 32,
          iconSize: 20,
          surfaceStyle: TactileSurfaceStyle.tinted,
          onPressed: value < maxAutoRefreshIntervalMinutes
              ? () => onChanged(((value ~/ 60) + 1) * 60)
              : null,
        ),
      ],
    );
  }
}

/// 提醒与小组件卡片：课程提醒、桌面小组件，以及后台保活/闹钟/自启动权限检查。
class _ReminderAndWidgetCard extends StatefulWidget {
  const _ReminderAndWidgetCard({
    required this.model,
    required this.reminders,
    required this.desktopWidgets,
  });

  final AppModel model;
  final ReminderService? reminders;
  final DesktopWidgetService? desktopWidgets;

  @override
  State<_ReminderAndWidgetCard> createState() => _ReminderAndWidgetCardState();
}

class _ReminderAndWidgetCardState extends State<_ReminderAndWidgetCard>
    with
        WidgetsBindingObserver,
        RouteSettledStateMixin<_ReminderAndWidgetCard> {
  late final ValueNotifier<ReminderRuntimeStatus?> _statusNotifier =
      ValueNotifier<ReminderRuntimeStatus?>(widget.reminders?.lastStatus);

  bool _running = false;
  int _statusEpoch = 0;
  ReminderRuntimeStatus? _pendingStatus;
  int _pendingStatusEpoch = 0;
  bool _pendingResumeRefresh = false;

  bool get _isTabActive =>
      mounted &&
      TickerMode.valuesOf(context).enabled &&
      (ModalRoute.of(context)?.isCurrent ?? true);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.reminders != null) {
      unawaited(_refreshStatus(deferUntilSettled: true));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_pendingResumeRefresh && _isTabActive && widget.reminders != null) {
      _pendingResumeRefresh = false;
      unawaited(_refreshStatus());
    }
  }

  @override
  void onRouteSettled() {
    _flushPendingStatus();
  }

  @override
  void didUpdateWidget(covariant _ReminderAndWidgetCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reminders != oldWidget.reminders) {
      _statusEpoch++;
      _pendingStatus = null;
      _pendingResumeRefresh = false;
      _statusNotifier.value = widget.reminders?.lastStatus;
      if (widget.reminders != null) {
        unawaited(_refreshStatus());
      }
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.reminders != null) {
      // 设置页离屏常驻于 HomeShell，仅当前实际停留在设置页时立即查询原生提醒权限状态；
      // 停留在课表/学业页频繁往返桌面小组件时跳过冗余 Binder 查询，切回设置页时再补刷。
      if (_isTabActive) {
        _pendingResumeRefresh = false;
        unawaited(_refreshStatus());
      } else {
        _pendingResumeRefresh = true;
      }
    }
  }

  void _flushPendingStatus() {
    final pending = _pendingStatus;
    if (pending == null) return;
    _pendingStatus = null;
    if (_pendingStatusEpoch == _statusEpoch) {
      _statusNotifier.value = pending;
    }
  }

  Future<void> _refreshStatus({bool deferUntilSettled = false}) async {
    final service = widget.reminders;
    if (service == null) return;
    final epoch = ++_statusEpoch;
    try {
      final status = await service.refreshStatus();
      if (!mounted || epoch != _statusEpoch) return;
      if (deferUntilSettled && !isRouteSettled) {
        _pendingStatus = status;
        _pendingStatusEpoch = epoch;
        return;
      }
      _pendingStatus = null;
      _statusNotifier.value = status;
    } catch (_) {
      // 查询异常时保持上次状态，避免未捕获异步异常。
    }
  }

  Future<void> _run(
    Future<void> Function(ReminderService service) action,
  ) async {
    final service = widget.reminders;
    if (service == null || _running) return;
    _running = true;
    try {
      await action(service);
    } finally {
      _running = false;
    }
  }

  Future<void> _openBattery() => _run((service) async {
    showReminderGuideToast(
      context,
      service,
      '请在「耗电管理」或「省电策略」中允许后台运行',
      aboveDock: true,
    );
    await service.openBatterySettings();
    await _refreshStatus();
  });

  Future<void> _openExactAlarm() => _run((service) async {
    showReminderGuideToast(
      context,
      service,
      '请开启「允许设置闹钟和提醒」以确保准时响铃',
      aboveDock: true,
    );
    await service.openExactAlarmSettings();
    await _refreshStatus();
  });

  Future<void> _openAutostart() => _run((service) async {
    final vendor = await service.openAutostartSettings();
    if (mounted) {
      showReminderGuideToast(
        context,
        service,
        vendor ? '请在列表中找到本应用并允许自启动' : '请在设置顶部搜索「自启动」，开启本应用开关',
        aboveDock: true,
      );
    }
    await _refreshStatus();
  });

  @override
  Widget build(BuildContext context) {
    final reminders = widget.reminders;
    final desktopWidgets = widget.desktopWidgets;
    final model = widget.model;
    return Card(
      child: Column(
        children: <Widget>[
          if (reminders != null)
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
              onTap: () => Navigator.of(context)
                  .push(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ReminderPage(model: model, service: reminders),
                    ),
                  )
                  .then((_) {
                    if (mounted) unawaited(_refreshStatus());
                  }),
            ),
          if (desktopWidgets != null) ...<Widget>[
            if (reminders != null) const Divider(height: 0, indent: 56),
            ListTile(
              leading: const Icon(Icons.widgets_outlined, size: 20),
              title: const Text('桌面小组件'),
              subtitle: const Text('添加并自定义小组件样式'),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => WidgetSettingsPage(
                    model: model,
                    widgetService: desktopWidgets,
                  ),
                ),
              ),
            ),
          ],
          if (reminders != null)
            ValueListenableBuilder<ReminderRuntimeStatus?>(
              valueListenable: _statusNotifier,
              builder: (context, status, _) {
                return Column(
                  children: <Widget>[
                    const Divider(height: 0, indent: 56),
                    ReminderPermissionTile(
                      icon: Icons.battery_saver_outlined,
                      title: '忽略电池优化',
                      value: status == null
                          ? '查询中...'
                          : (status.batteryOptOut
                                ? '已忽略'
                                : '受省电策略限制 · 后台可能被清理'),
                      ok: status?.batteryOptOut ?? false,
                      actionLabel: '去设置',
                      onAction: _openBattery,
                    ),
                    const Divider(height: 0, indent: 56),
                    ReminderPermissionTile(
                      icon: Icons.alarm_rounded,
                      title: '精确闹钟',
                      value: status == null
                          ? '查询中...'
                          : (status.exactAlarmAllowed
                                ? '已允许'
                                : '未允许 · 息屏时可能推迟数分钟'),
                      ok: status?.exactAlarmAllowed ?? false,
                      actionLabel: '去设置',
                      onAction: _openExactAlarm,
                    ),
                    const Divider(height: 0, indent: 56),
                    ReminderPermissionTile(
                      icon: Icons.power_settings_new_rounded,
                      title: '自启动',
                      value: '该权限不可检测，需自行确认',
                      ok: null,
                      actionLabel: '去设置',
                      onAction: _openAutostart,
                    ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}
