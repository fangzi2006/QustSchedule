/// 调课页：按日期调——「把 X 月 X 日的课调到 Y 月 Y 日」。
///
/// 只改渲染不改数据：调课规则存在设置里，课表页渲染时叠加，
/// 原始的教务课表（以及缓存、调试页）始终不变。
library;

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/reschedule.dart' show RescheduleRule;
import '../src/timetable.dart' show formatMonthDay;
import '../widgets/time_wheel_picker.dart' show showMonthDayWheel;

class ReschedulePage extends StatelessWidget {
  const ReschedulePage({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: model,
      builder: (context, _) {
        final rules = model.reschedules;
        return Scaffold(
          appBar: AppBar(title: const Text('调课')),
          body: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                child: Text(
                  '把某一天（月日）的课整体挪到另一天（月日），只改显示、'
                  '不覆盖教务课表。例如"10 月 20 日 → 10 月 25 日"。',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: Theme.of(context).hintColor),
                ),
              ),
              Expanded(
                child: rules.isEmpty
                    ? const _Empty()
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
                        itemCount: rules.length,
                        itemBuilder: (context, index) {
                          final rule = rules[index];
                          return Card(
                            child: ListTile(
                              leading: const Icon(
                                Icons.swap_horiz_rounded,
                                size: 20,
                              ),
                              title: Text(
                                '${formatMonthDay(rule.fromMonth, rule.fromDay)}'
                                '  →  ${formatMonthDay(rule.toMonth, rule.toDay)}',
                              ),
                              subtitle: const Text('点击可修改 · 这一天的课整体调过去'),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 20,
                                ),
                                tooltip: '删除',
                                onPressed: () =>
                                    model.removeReschedule(rule.id),
                              ),
                              onTap: () =>
                                  _showAddSheet(context, initial: rule),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () => _showAddSheet(context),
            icon: const Icon(Icons.add_rounded),
            label: const Text('添加调课'),
          ),
        );
      },
    );
  }

  void _showAddSheet(BuildContext context, {RescheduleRule? initial}) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _AddRescheduleSheet(model: model, initialRule: initial),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.swap_horiz_rounded, size: 44, color: theme.hintColor),
          const SizedBox(height: 12),
          Text('还没有调课', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            '点右下角「添加调课」，把某一天（月日）的课挪到另一天。',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          ),
        ],
      ),
    );
  }
}

/// 添加调课：两个「月日」选择，从哪天调到哪天。
class _AddRescheduleSheet extends StatefulWidget {
  const _AddRescheduleSheet({required this.model, this.initialRule});

  final AppModel model;

  /// 非空表示"编辑"这条既有规则；为空表示"新增"。
  final RescheduleRule? initialRule;

  @override
  State<_AddRescheduleSheet> createState() => _AddRescheduleSheetState();
}

class _AddRescheduleSheetState extends State<_AddRescheduleSheet> {
  late int _fromMonth;
  late int _fromDay;
  late int _toMonth;
  late int _toDay;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRule;
    if (initial != null) {
      _fromMonth = initial.fromMonth;
      _fromDay = initial.fromDay;
      _toMonth = initial.toMonth;
      _toDay = initial.toDay;
    } else {
      final today = DateTime.now();
      _fromMonth = today.month;
      _fromDay = today.day;
      _toMonth = today.month;
      _toDay = today.day;
    }
  }

  bool get _same => _fromMonth == _toMonth && _fromDay == _toDay;

  Future<void> _pick(bool from) async {
    final picked = await showMonthDayWheel(
      context,
      month: from ? _fromMonth : _toMonth,
      day: from ? _fromDay : _toDay,
      title: from ? '从哪天调' : '调到哪天',
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _fromMonth = picked.month;
        _fromDay = picked.day;
      } else {
        _toMonth = picked.month;
        _toDay = picked.day;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            widget.initialRule != null ? '编辑调课' : '添加调课',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _DateField(
            label: '从',
            value: formatMonthDay(_fromMonth, _fromDay),
            onTap: () => _pick(true),
          ),
          const SizedBox(height: 4),
          _DateField(
            label: '调到',
            value: formatMonthDay(_toMonth, _toDay),
            onTap: () => _pick(false),
          ),
          const SizedBox(height: 4),
          Text(
            _same ? '选两个不同的一天。' : '这一天（月日）的课整体挪过去。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('取消'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _same
                    ? null
                    : () {
                        final initial = widget.initialRule;
                        if (initial != null) {
                          widget.model.updateReschedule(
                            initial.id,
                            fromMonth: _fromMonth,
                            fromDay: _fromDay,
                            toMonth: _toMonth,
                            toDay: _toDay,
                          );
                        } else {
                          widget.model.addReschedule(
                            fromMonth: _fromMonth,
                            fromDay: _fromDay,
                            toMonth: _toMonth,
                            toDay: _toDay,
                          );
                        }
                        Navigator.of(context).pop();
                      },
                child: const Text('确定'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.value,
    required this.onTap,
  });

  final String label;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: <Widget>[
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(width: 12),
            Text(value, style: Theme.of(context).textTheme.titleMedium),
            const Spacer(),
            const Icon(Icons.chevron_right_rounded, size: 20),
          ],
        ),
      ),
    );
  }
}
