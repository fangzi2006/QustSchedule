/// 作息时间表列表：管理多张表（夏季/冬季），按生效日期自动切换。
library;

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/timetable.dart';
import '../widgets/app_menu.dart';
import '../widgets/time_wheel_picker.dart';
import 'timetable_edit_page.dart';

class TimetableListPage extends StatelessWidget {
  const TimetableListPage({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    // 只听**偏好**的通知源（见 [AppModel.prefsNotifier]）：课表刷新那些
    // 与本页无关的 model 通知，不该让整页重建一次。
    return ListenableBuilder(
      listenable: model.prefsNotifier,
      builder: (context, _) {
        final tables = model.timetables;
        final active = model.activeTimetable;
        final counts = model.sectionCounts;
        final sectionCount = countsSum(counts);
        final theme = Theme.of(context);
        return Scaffold(
          appBar: AppBar(
            title: const Text('作息时间表'),
            actions: <Widget>[
              IconButton(
                icon: const Icon(Icons.add_rounded),
                tooltip: '新建作息表',
                onPressed: tables.length >= maxTimetables
                    ? null
                    : () => _create(context, model, tables),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: <Widget>[
              Text(
                '课表左侧的时间轴、以及显示多少节课，都取自这里。\n'
                '每张表有一个生效日期，到了那天自动切换——切到哪张由日期决定，不需要手动选。\n'
                '「默认作息」是按常见作息估算的，请按你班级的实际上下课时间改一次。',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.hintColor,
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: ListTile(
                  leading: const Icon(
                    Icons.format_list_numbered_rounded,
                    size: 20,
                  ),
                  title: const Text('课表节数'),
                  subtitle: Text(
                    '共 $sectionCount 节 · 上午 ${counts[PeriodGroup.morning] ?? 0}'
                    ' / 下午 ${counts[PeriodGroup.afternoon] ?? 0}'
                    ' / 晚上 ${counts[PeriodGroup.evening] ?? 0}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => _editSectionCount(context, model),
                ),
              ),
              const SizedBox(height: 14),
              for (final table in tables) ...<Widget>[
                _TimetableCard(
                  table: table,
                  isActive: active?.id == table.id,
                  canDelete: tables.length > 1,
                  onTap: () => _openEditor(context, model, table.id),
                  onDelete: () => _confirmDelete(context, model, table),
                ),
                const SizedBox(height: 10),
              ],
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: tables.length >= maxTimetables
                    ? null
                    : () => _create(context, model, tables),
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('新建作息表'),
              ),
            ],
          ),
        );
      },
    );
  }

  /// 改节数：底部滚轮直接选三段，不跳页面。
  Future<void> _editSectionCount(BuildContext context, AppModel model) async {
    final picked = await showSectionCountWheel(
      context,
      counts: model.sectionCounts,
    );
    if (picked == null) return;
    await model.setSectionCounts(picked);
  }

  Future<void> _create(
    BuildContext context,
    AppModel model,
    List<Timetable> existing,
  ) async {
    final now = DateTime.now();
    // 新建**不落盘**：草稿直接进编辑页，点右上角对勾才真正保存。
    // 否则用户点错了新建、又直接退出，列表里就多出一张没人要的空表。
    final draft = Timetable(
      id: 't${now.millisecondsSinceEpoch}',
      name: '作息表 ${existing.length + 1}',
      effectiveFrom: DateTime(now.year, now.month, now.day),
      sections: reconcileSections(const <SectionTime>[], model.sectionCounts),
    );
    if (!context.mounted) return;
    await _openEditor(context, model, draft.id, initial: draft);
  }

  Future<void> _openEditor(
    BuildContext context,
    AppModel model,
    String id, {
    Timetable? initial,
  }) async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            TimetableEditPage(model: model, timetableId: id, initial: initial),
      ),
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    AppModel model,
    Timetable table,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除作息表'),
        content: Text('「${table.name}」将被删除，课表会改用其余表里生效日期最近的一张。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await model.deleteTimetable(table.id);
    }
  }
}

class _TimetableCard extends StatelessWidget {
  const _TimetableCard({
    required this.table,
    required this.isActive,
    required this.canDelete,
    required this.onTap,
    required this.onDelete,
  });

  final Timetable table;
  final bool isActive;
  final bool canDelete;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = table.sections.isEmpty ? null : table.sections.first;
    final last = table.sections.isEmpty ? null : table.sections.last;
    final span = first == null || last == null
        ? ''
        : '${formatClock(first.startMinutes)} – ${formatClock(last.endMinutes)}';

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            table.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        if (isActive) ...<Widget>[
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 7,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary.withValues(
                                alpha: 0.12,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              '使用中',
                              style: TextStyle(
                                fontSize: 10,
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_dateText(table.effectiveFrom)} 起 · ${table.sectionCount} 节'
                      '${span.isEmpty ? '' : ' · $span'}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                    ),
                  ],
                ),
              ),
              Builder(
                builder: (buttonContext) => IconButton(
                  icon: const Icon(Icons.more_vert_rounded, size: 20),
                  tooltip: '更多',
                  onPressed: () => showAppMenu<String>(
                    context: buttonContext,
                    items: <AppMenuItem<String>>[
                      AppMenuItem<String>(
                        value: 'delete',
                        label: canDelete ? '删除' : '至少保留一张',
                        enabled: canDelete,
                      ),
                    ],
                    onSelected: (value) {
                      if (value == 'delete') onDelete();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _dateText(DateTime value) => formatMonthDayDate(value);
}
