/// 课程提醒设置页：开关 + 提前量滑块 + 流体云开关 + 权限状态 + 诊断。
///
/// 设计原则：**所有"为什么不响"都要在界面上说清楚**。上个版本的教训是
/// 通知不响时用户只能猜——所以这里把通知权限、精确闹钟、电池优化、
/// 已排条数、下一条时刻、实际策略全列出来，还给一个"一分钟后测试提醒"。
library;

import 'dart:async';

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
  ReminderRuntimeStatus? _status;

  /// 是否正在跑一次原生操作。**故意不进 State，也不 setState**。
  ///
  /// 之前的写法是把 `_busy` 塞进 setState，按钮渲染成 `onPressed: null`：
  /// 原生同步只要几百毫秒，整页按钮就会在"禁用色 ↔ 正常色"之间闪一下，
  /// 用户看到的是所有按钮一起闪。这里只做重入保护——正在跑时再点直接忽略，
  /// 界面一个像素都不重建（与设置页、作息表页的处理方式一致）。
  bool _running = false;

  /// 拖动中的提前量。null = 跟随已保存值。
  ///
  /// 拖滑块时不能每动 1 像素就落盘 + 重排：那样一次拖动会打出几十次同步，
  /// 原生侧要跑几十遍账本差分。所以拖动只改本地草稿，抬手才落盘。
  int? _leadDraft;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_refreshStatus());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// 从系统设置页返回时重查一次。
  ///
  /// 通知权限、精确闹钟、电池白名单都是在**别的进程**里授权的，
  /// 不重查就一直显示旧值——这是"授权后必须退出重进"的根因。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(_refreshStatus());
  }

  Future<void> _refreshStatus() async {
    final status = await widget.service.refreshStatus();
    if (!mounted) return;
    setState(() => _status = status);
  }

  /// 串行执行一次原生操作：重入时直接忽略（避免连点排出一串闹钟）。
  ///
  /// 不 setState —— 按钮的可用状态不跟着变，就不会闪。
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

  /// 落盘 + 重排。滑块抬手与预设按钮都走这里。
  Future<void> _commitLead(int minutes) async {
    if (_running) {
      // 正在跑别的操作：把滑块退回已保存值，别让界面和偏好对不上。
      if (mounted) setState(() => _leadDraft = null);
      return;
    }
    await _run(() async {
      await widget.model.setReminderLeadMinutes(minutes);
      if (mounted) setState(() => _leadDraft = null);
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

  /// 系统授权页是"跳出去再回来"，返回值必然是跳转前的旧状态，
  /// 所以这里只负责跳转 + 提示，真实结果交给 resume 时的 [_refreshStatus]。
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

  /// 自启动没有公共 API 也不能申请：能跳厂商页就跳，跳不动就跳应用详情。
  Future<void> _openAutostart() => _run(() async {
    final vendor = await widget.service.openAutostartSettings();
    await _refreshStatus();
    if (!mounted) return;
    _toast(vendor ? '已打开自启动管理，请允许本应用自启动' : '已打开应用详情：在「自启动 / 耗电管理」里允许');
  });

  /// 自启动的真实开关读不到（厂商私有），只能告诉用户去哪里确认。
  String _autostartText(ReminderRuntimeStatus? status) {
    if (status == null) return '查询中…';
    if (!status.autoStartDeclared) return '缺少开机广播权限 · 重启后不会恢复';
    return status.autoStartVendorPage
        ? '需手动确认 · 点「去设置」打开自启动管理'
        : '需手动确认 · 点「去设置」到应用详情里开';
  }

  Future<void> _resync() => _run(() async {
    await widget.service.syncNow(force: true);
    await _refreshStatus();
    if (!mounted) return;
    _toast('已重新排程');
  });

  /// 立刻显示一条示例提醒：**不挂闹钟**，只看文案与形态。
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
    return ListenableBuilder(
      listenable: widget.model.prefsNotifier,
      builder: (BuildContext context, _) {
        final model = widget.model;
        final status = _status;
        // 拖动中是草稿值，松手后回到已保存值。
        final lead = _leadDraft ?? model.reminderLeadMinutes;
        return Scaffold(
          appBar: AppBar(title: const Text('课程提醒')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            children: <Widget>[
              const _SectionTitle('提醒设置'),
              Card(
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
                      onChanged: _toggleReminder,
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
                              // 1~60 共 60 档，画刻度点会糊成一条黑边。
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
                                  reminderMaxLeadMinutes -
                                  reminderMinLeadMinutes,
                              label: '$lead 分钟',
                              onChanged: (value) =>
                                  setState(() => _leadDraft = value.round()),
                              onChangeEnd: (value) =>
                                  unawaited(_commitLead(value.round())),
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
                                  onSelected: (_) =>
                                      unawaited(_commitLead(minutes)),
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
                      onChanged: _toggleFluid,
                    ),
                    if (status?.fluidCasting ?? false)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(56, 0, 16, 8),
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: _stopFluid,
                            child: const Text('立即收起卡片'),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const _SectionTitle('权限与可靠性'),
              Card(
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
                      onAction: _requestNotification,
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
                      onAction: _openExactAlarm,
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
                      onAction: _openBattery,
                    ),
                    const Divider(height: 0, indent: 56),
                    _PermissionTile(
                      icon: Icons.power_settings_new_rounded,
                      title: '自启动',
                      // 厂商私有权限，读不到真实状态：用提示色，不给假绿灯。
                      value: _autostartText(status),
                      ok: status == null
                          ? null
                          : (status.autoStartDeclared ? null : false),
                      actionLabel: '去设置',
                      onAction: _openAutostart,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              const _SectionTitle('诊断'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  child: Column(
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
                        value: _timeText(
                          widget.service.lastPlan?.coverageEndMs,
                        ),
                      ),
                      _InfoRow(
                        label: '提醒形态',
                        value: model.reminderStyle == ReminderStyle.fluid
                            ? '流体云卡片'
                            : '横幅通知',
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
                      if (widget.service.lastPlan?.truncated ?? false)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            '提醒条数超过上限，已截断到最近 '
                            '$reminderMaxEvents 条',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: <Widget>[
                          OutlinedButton(
                            onPressed: _resync,
                            child: const Text('立即重排'),
                          ),
                          OutlinedButton(
                            onPressed: _preview,
                            child: const Text('立即显示通知'),
                          ),
                          OutlinedButton(
                            onPressed: _testIn5s,
                            child: const Text('5 秒后测试提醒'),
                          ),
                          OutlinedButton(
                            onPressed: _testInOneMinute,
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
      },
    );
  }

  String _timeText(int? ms) {
    if (ms == null || ms <= 0) return '—';
    final value = DateTime.fromMillisecondsSinceEpoch(ms);
    final hour = value.hour.toString().padLeft(2, '0');
    final minute = value.minute.toString().padLeft(2, '0');
    return '${value.month}/${value.day} $hour:$minute';
  }
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

  /// true = 已满足，false = 未满足，**null = 无法自动判定**（如厂商私有权限）。
  final bool? ok;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (ok) {
      true => const Color(0xFF2E7D32),
      false => theme.colorScheme.error,
      // 读不到就别装：用提示色提醒用户自己去确认。
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
          Expanded(
            child: SelectableText(value, style: theme.textTheme.bodySmall),
          ),
        ],
      ),
    );
  }
}
