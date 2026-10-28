/// 课程提醒设置页：开关 + 提前量滑块 + 流体云开关 + 权限状态 + 诊断。
///
/// 设计原则：**所有"为什么不响"都要在界面上说清楚**。
/// 架构优化：三张卡片具备各自独立的构建边界（State / ValueListenableBuilder），
/// 拖动滑块只重绘设置卡局部，状态更新只重绘权限与诊断卡，杜绝全页重建卡顿。
library;

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/reminder_gateway.dart';
import '../src/reminder_planner.dart';
import '../src/reminder_service.dart';

class ReminderPage extends StatefulWidget {
  const ReminderPage({super.key, required this.model, required this.service});

  final AppModel model;
  final ReminderService service;

  @override
  State<ReminderPage> createState() => _ReminderPageState();
}

class _ReminderPageState extends State<ReminderPage>
    with WidgetsBindingObserver {
  late final ValueNotifier<ReminderRuntimeStatus?> _statusNotifier =
      ValueNotifier<ReminderRuntimeStatus?>(widget.service.lastStatus);

  /// 是否正在跑一次原生操作。**故意不进 State，也不 setState**。
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusNotifier.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    final status = await widget.service.refreshStatus();
    if (!mounted) return;
    _statusNotifier.value = status;
  }

  /// 串行执行一次原生操作：重入时直接忽略（避免连点排出一串闹钟）。
  Future<void> _run(Future<void> Function() action) async {
    if (_running) return;
    _running = true;
    try {
      await action();
    } finally {
      _running = false;
    }
  }

  Future<void> _toggleReminder(bool value) => _run(() async {
    await widget.model.setReminderEnabled(value);
    await widget.service.syncNow(force: true);
    await _refreshStatus();
    if (!mounted) return;
    _toast(value ? '已开启课程提醒' : '已关闭并取消全部提醒');
  });

  Future<void> _commitLead(int minutes) async {
    if (_running) return;
    await _run(() async {
      await widget.model.setReminderLeadMinutes(minutes);
      await widget.service.syncNow(force: true);
      await _refreshStatus();
    });
  }

  Future<void> _toggleFluid(bool enabled) => _run(() async {
    final style = enabled ? ReminderStyle.fluid : ReminderStyle.banner;
    await widget.model.setReminderStyle(style);
    if (!enabled) {
      await widget.service.stopFluid();
    }
    await widget.service.syncNow(force: true);
    await _refreshStatus();
    if (!mounted) return;
    _toast(enabled ? '已开启流体云卡片' : '已改用横幅通知');
  });

  Future<void> _stopFluid() => _run(() async {
    await widget.service.stopFluid();
    await _refreshStatus();
    if (!mounted) return;
    _toast('已收起流体云卡片');
  });

  Future<void> _requestNotification() => _run(() async {
    final granted = await widget.service.requestNotificationPermission();
    await _refreshStatus();
    if (!mounted) return;
    _toast(granted ? '通知权限已授权' : '未授权：请到系统设置里允许通知');
  });

  Future<void> _openExactAlarm() => _run(() async {
    await widget.service.openExactAlarmSettings();
    await _refreshStatus();
    if (!mounted) return;
    _toast('已打开系统设置，返回后会自动刷新');
  });

  Future<void> _openBattery() => _run(() async {
    await widget.service.openBatterySettings();
    await _refreshStatus();
  });

  Future<void> _openAutostart() => _run(() async {
    final vendor = await widget.service.openAutostartSettings();
    await _refreshStatus();
    if (!mounted) return;
    _toast(vendor ? '已打开自启动管理，请允许本应用自启动' : '已打开应用详情：在「自启动 / 耗电管理」里允许');
  });

  Future<void> _resync() => _run(() async {
    await widget.service.syncNow(force: true);
    await _refreshStatus();
    if (!mounted) return;
    _toast('已重新排程');
  });

  Future<void> _preview() => _run(() async {
    final ok = await widget.service.previewReminder();
    if (!mounted) return;
    _toast(ok ? '已显示预览通知' : '预览失败：请先允许通知权限');
    await _refreshStatus();
  });

  Future<void> _testReminder(int delaySeconds) => _run(() async {
    final ok = await widget.service.sendTestReminder(
      delaySeconds: delaySeconds,
    );
    if (!mounted) return;
    _toast(ok ? '$delaySeconds 秒后会收到一条测试提醒' : '测试提醒未排上：请检查通知与精确闹钟权限');
    await _refreshStatus();
  });

  Future<void> _testIn5s() => _testReminder(5);

  Future<void> _testInOneMinute() => _testReminder(60);

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
      );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('课程提醒')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
        children: <Widget>[
          const _SectionTitle('提醒设置'),
          _ReminderSettingsCard(
            model: widget.model,
            statusNotifier: _statusNotifier,
            onToggleReminder: _toggleReminder,
            onCommitLead: _commitLead,
            onToggleFluid: _toggleFluid,
            onStopFluid: _stopFluid,
          ),
          const SizedBox(height: 18),
          const _SectionTitle('权限与可靠性'),
          _PermissionsCard(
            statusNotifier: _statusNotifier,
            onRequestNotification: _requestNotification,
            onOpenExactAlarm: _openExactAlarm,
            onOpenBattery: _openBattery,
            onOpenAutostart: _openAutostart,
          ),
          const SizedBox(height: 18),
          const _SectionTitle('诊断'),
          _DiagnosticsCard(
            model: widget.model,
            service: widget.service,
            statusNotifier: _statusNotifier,
            onResync: _resync,
            onPreview: _preview,
            onTestIn5s: _testIn5s,
            onTestInOneMinute: _testInOneMinute,
          ),
          const SizedBox(height: 12),
          Text(
            '提醒依赖系统闹钟：重启、覆盖安装、修改时间后会自动恢复；'
            '强制停止 App 或使用"一键清理"后闹钟会被系统清空，'
            '重新打开 App 即可恢复。',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

class _ReminderSettingsCard extends StatefulWidget {
  const _ReminderSettingsCard({
    required this.model,
    required this.statusNotifier,
    required this.onToggleReminder,
    required this.onCommitLead,
    required this.onToggleFluid,
    required this.onStopFluid,
  });

  final AppModel model;
  final ValueListenable<ReminderRuntimeStatus?> statusNotifier;
  final ValueChanged<bool> onToggleReminder;
  final ValueChanged<int> onCommitLead;
  final ValueChanged<bool> onToggleFluid;
  final VoidCallback onStopFluid;

  @override
  State<_ReminderSettingsCard> createState() => _ReminderSettingsCardState();
}

class _ReminderSettingsCardState extends State<_ReminderSettingsCard> {
  int? _leadDraft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: widget.model.prefsNotifier,
      builder: (context, _) {
        final model = widget.model;
        final lead = _leadDraft ?? model.reminderLeadMinutes;
        return Card(
          child: Column(
            children: <Widget>[
              SwitchListTile(
                key: const Key('reminder-enabled-switch'),
                secondary: const Icon(
                  Icons.notifications_active_outlined,
                  size: 20,
                ),
                title: const Text('上课前提醒'),
                subtitle: Text(
                  model.reminderEnabled
                      ? '每节课开始前 ${model.reminderLeadMinutes} 分钟提醒一次'
                      : '关闭时不排任何闹钟',
                ),
                value: model.reminderEnabled,
                onChanged: widget.onToggleReminder,
              ),
              const Divider(height: 0, indent: 56),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            '提前量',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '提前 $lead 分钟',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 8,
                        tickMarkShape: SliderTickMarkShape.noTickMark,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 10,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 20,
                        ),
                      ),
                      child: Slider(
                        key: const Key('reminder-lead-slider'),
                        value: lead.toDouble(),
                        min: reminderMinLeadMinutes.toDouble(),
                        max: reminderMaxLeadMinutes.toDouble(),
                        divisions:
                            reminderMaxLeadMinutes - reminderMinLeadMinutes,
                        label: '$lead 分钟',
                        onChanged: (value) =>
                            setState(() => _leadDraft = value.round()),
                        onChangeEnd: (value) {
                          setState(() => _leadDraft = null);
                          widget.onCommitLead(value.round());
                        },
                      ),
                    ),
                    Text(
                      '拖动调整（1~60 分钟），改动后自动重排全部提醒',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: <Widget>[
                        for (final minutes in reminderLeadOptions)
                          ChoiceChip(
                            label: Text('$minutes 分钟'),
                            selected: lead == minutes,
                            onSelected: (_) {
                              setState(() => _leadDraft = null);
                              widget.onCommitLead(minutes);
                            },
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 0, indent: 56),
              SwitchListTile(
                key: const Key('reminder-fluid-switch'),
                secondary: const Icon(Icons.podcasts_rounded, size: 20),
                title: const Text('流体云卡片'),
                subtitle: Text(
                  model.reminderStyle == ReminderStyle.fluid
                      ? '上课前用常驻卡片倒计时（上课准时收起）'
                      : '关闭时为普通横幅通知，点开回到 App',
                ),
                value: model.reminderStyle == ReminderStyle.fluid,
                onChanged: widget.onToggleFluid,
              ),
              ValueListenableBuilder<ReminderRuntimeStatus?>(
                valueListenable: widget.statusNotifier,
                builder: (context, status, _) {
                  if (!(status?.fluidCasting ?? false)) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: widget.onStopFluid,
                        child: const Text('立即收起卡片'),
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _PermissionsCard extends StatelessWidget {
  const _PermissionsCard({
    required this.statusNotifier,
    required this.onRequestNotification,
    required this.onOpenExactAlarm,
    required this.onOpenBattery,
    required this.onOpenAutostart,
  });

  final ValueListenable<ReminderRuntimeStatus?> statusNotifier;
  final VoidCallback onRequestNotification;
  final VoidCallback onOpenExactAlarm;
  final VoidCallback onOpenBattery;
  final VoidCallback onOpenAutostart;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ReminderRuntimeStatus?>(
      valueListenable: statusNotifier,
      builder: (context, status, _) {
        return Card(
          child: Column(
            children: <Widget>[
              _PermissionTile(
                icon: Icons.notifications_outlined,
                title: '通知权限',
                value: status == null
                    ? '查询中…'
                    : (status.canNotify ? '已授权' : '未授权'),
                ok: status?.canNotify ?? false,
                actionLabel: '去授权',
                onAction: onRequestNotification,
              ),
              const Divider(height: 0, indent: 56),
              _PermissionTile(
                icon: Icons.alarm_rounded,
                title: '精确闹钟',
                value: status == null
                    ? '查询中…'
                    : (status.exactAlarmAllowed ? '已允许' : '未允许 · 提醒可能延迟'),
                ok: status?.exactAlarmAllowed ?? false,
                actionLabel: '去设置',
                onAction: onOpenExactAlarm,
              ),
              const Divider(height: 0, indent: 56),
              _PermissionTile(
                icon: Icons.battery_saver_outlined,
                title: '忽略电池优化',
                value: status == null
                    ? '查询中…'
                    : (status.batteryOptOut
                          ? '已忽略 · 可靠性最好'
                          : '未忽略 · 打开应用详情里的「耗电管理」'),
                ok: status?.batteryOptOut ?? false,
                actionLabel: '去设置',
                onAction: onOpenBattery,
              ),
              const Divider(height: 0, indent: 56),
              _PermissionTile(
                icon: Icons.power_settings_new_rounded,
                title: '自启动',
                value: _autostartText(status),
                ok: status == null
                    ? null
                    : (status.autoStartDeclared ? null : false),
                actionLabel: '去设置',
                onAction: onOpenAutostart,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DiagnosticsCard extends StatelessWidget {
  const _DiagnosticsCard({
    required this.model,
    required this.service,
    required this.statusNotifier,
    required this.onResync,
    required this.onPreview,
    required this.onTestIn5s,
    required this.onTestInOneMinute,
  });

  final AppModel model;
  final ReminderService service;
  final ValueListenable<ReminderRuntimeStatus?> statusNotifier;
  final VoidCallback onResync;
  final VoidCallback onPreview;
  final VoidCallback onTestIn5s;
  final VoidCallback onTestInOneMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            ValueListenableBuilder<ReminderRuntimeStatus?>(
              valueListenable: statusNotifier,
              builder: (context, status, _) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _InfoRow(
                      label: '已排提醒',
                      value: status == null ? '—' : '${status.scheduled} 条',
                    ),
                    _InfoRow(
                      label: '下一条',
                      value: _timeText(status?.nextTriggerMs),
                    ),
                    _InfoRow(
                      label: '数据生成于',
                      value: _timeText(status?.payloadAtMs),
                    ),
                    _InfoRow(
                      label: '覆盖到',
                      value: _timeText(service.lastPlan?.coverageEndMs),
                    ),
                    ListenableBuilder(
                      listenable: model.prefsNotifier,
                      builder: (context, _) => _InfoRow(
                        label: '提醒形态',
                        value: model.reminderStyle == ReminderStyle.fluid
                            ? '流体云卡片'
                            : '横幅通知',
                      ),
                    ),
                    _InfoRow(
                      label: '排程精度',
                      value: (status?.exactAlarmAllowed ?? false)
                          ? '精确闹钟'
                          : '降级：可能晚到几分钟',
                    ),
                    _InfoRow(
                      label: '流体云',
                      value: (status?.fluidCasting ?? false) ? '显示中' : '未显示',
                    ),
                  ],
                );
              },
            ),
            if (service.lastPlan?.truncated ?? false)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '提醒条数超过上限，已截断到最近 $reminderMaxEvents 条',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 8,
              children: <Widget>[
                OutlinedButton(onPressed: onResync, child: const Text('立即重排')),
                OutlinedButton(
                  onPressed: onPreview,
                  child: const Text('立即显示通知'),
                ),
                OutlinedButton(
                  onPressed: onTestIn5s,
                  child: const Text('5 秒后测试提醒'),
                ),
                OutlinedButton(
                  onPressed: onTestInOneMinute,
                  child: const Text('一分钟后测试提醒'),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              '测试提醒是独立闹钟：不计入上面的条数，「立即重排」'
              '也不会取消或重排它。',
              style: theme.textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

String _autostartText(ReminderRuntimeStatus? status) {
  if (status == null) return '查询中…';
  if (!status.autoStartDeclared) return '缺少开机广播权限 · 重启后不会恢复';
  return status.autoStartVendorPage
      ? '需手动确认 · 点「去设置」打开自启动管理'
      : '需手动确认 · 点「去设置」到应用详情里开';
}

String _timeText(int? ms) {
  if (ms == null || ms <= 0) return '—';
  final value = DateTime.fromMillisecondsSinceEpoch(ms);
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '${value.month}/${value.day} $hour:$minute';
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
  const _PermissionTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.ok,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String value;
  final bool? ok;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (ok) {
      true => const Color(0xFF2E7D32),
      false => theme.colorScheme.error,
      null => const Color(0xFFB26A00),
    };
    return ListTile(
      leading: Icon(icon, size: 20),
      title: Text(title),
      subtitle: Text(value, style: TextStyle(color: color)),
      trailing: TextButton(onPressed: onAction, child: Text(actionLabel)),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 84,
            child: Text(label, style: theme.textTheme.bodySmall),
          ),
          Expanded(child: Text(value, style: theme.textTheme.bodySmall)),
        ],
      ),
    );
  }
}
