/// 编辑一张作息时间表。
///
/// 保存是**显式**的：右上角对勾才写盘。改动只落在本地草稿，
/// 退出时若有未保存改动会拦一下——作息表是手工调出来的，不能既怕丢又怕误存。
/// 新建的表同样是草稿：进页面时还没进列表，点对勾才真正创建。
///
/// 节数不在这里设：节数是全局设置（作息表列表 →「课表节数」），
/// 这里只负责"这些节分别几点上"。
library;

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import '../src/timetable.dart';
import '../widgets/time_wheel_picker.dart';

class TimetableEditPage extends StatefulWidget {
  const TimetableEditPage({
    super.key,
    required this.model,
    required this.timetableId,
    this.initial,
  });

  final AppModel model;
  final String timetableId;

  /// 新建时的草稿：还没进 `model.timetables`，保存后才存在。
  final Timetable? initial;

  @override
  State<TimetableEditPage> createState() => _TimetableEditPageState();
}

class _TimetableEditPageState extends State<TimetableEditPage> {
  Timetable? _draft;
  late QuickSetup _quick;
  late bool _bigBreakOn;
  bool _quickExpanded = false;
  bool _dirty = false;

  AppModel get model => widget.model;

  /// 是否是一张还没保存过的新表。
  bool get _isNew => _find() == null;

  @override
  void initState() {
    super.initState();
    final found = _find() ?? widget.initial;
    // 草稿先逐段对齐到全局节数：课表显示多少节，这里就显示多少行。
    _draft = found?.copyWith(
      sections: reconcileSections(found.sections, model.sectionCounts),
    );
    final draft = _draft;
    _quick =
        model.quickSetup ??
        (draft == null ? const QuickSetup() : _deriveQuick(draft));
    _bigBreakOn = _quick.bigBreaks.isNotEmpty;
    // 新表还没落盘，所以一进来就是"有未保存改动"。
    _dirty = _isNew;
  }

  Timetable? _find() {
    for (final table in model.timetables) {
      if (table.id == widget.timetableId) return table;
    }
    return null;
  }

  /// 从现有节次反推快捷参数：时长取第 1 节，小课间取第 1→2 节的间隔。
  QuickSetup _deriveQuick(Timetable table) {
    if (table.sections.isEmpty) return const QuickSetup();
    const fallback = QuickSetup();
    final first = table.sections.first;
    var shortBreak = fallback.shortBreakMinutes;
    if (table.sections.length > 1) {
      final gap = table.sections[1].startMinutes - first.endMinutes;
      if (gap > 0) shortBreak = gap;
    }
    final starts = <PeriodGroup, int>{};
    for (final group in PeriodGroup.values) {
      final groupSections = table.sections
          .where((s) => s.group == group)
          .toList();
      starts[group] = groupSections.isEmpty
          ? fallback.starts[group]!
          : groupSections.first.startMinutes;
    }
    return QuickSetup(
      lessonMinutes: first.durationMinutes,
      shortBreakMinutes: shortBreak,
      starts: starts,
    );
  }

  void _edit(Timetable next) {
    setState(() {
      _draft = next;
      _dirty = true;
    });
  }

  Future<void> _save() async {
    final draft = _draft;
    if (draft == null) return;
    await model.upsertTimetable(
      draft.copyWith(
        sections: reconcileSections(draft.sections, model.sectionCounts),
      ),
    );
    if (!mounted) return;
    setState(() => _dirty = false);
    Navigator.of(context).pop();
  }

  Future<void> _confirmLeave() async {
    final leave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('放弃修改？'),
        content: Text(_isNew ? '这张作息表还没保存，离开后不会创建。' : '这张作息表有未保存的改动，离开后会丢失。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('继续编辑'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('放弃'),
          ),
        ],
      ),
    );
    if (leave == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    if (draft == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('作息时间表')),
        body: const Center(child: Text('这张作息表已被删除')),
      );
    }
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final counts = model.sectionCounts;

    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _confirmLeave();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _isNew ? '新建作息表' : draft.name,
            overflow: TextOverflow.ellipsis,
          ),
          actions: <Widget>[
            IconButton(
              icon: const Icon(Icons.check_rounded),
              tooltip: _dirty ? '保存' : '没有改动',
              color: _dirty
                  ? scheme.primary
                  : scheme.onSurfaceVariant.withValues(alpha: 0.4),
              onPressed: _dirty ? _save : null,
            ),
            if (!_isNew)
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded),
                tooltip: model.timetables.length > 1 ? '删除作息表' : '至少保留一张',
                onPressed: model.timetables.length > 1 ? _delete : null,
              ),
          ],
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: <Widget>[
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    title: const Text('名称'),
                    subtitle: Text(draft.name),
                    trailing: const Icon(Icons.edit_outlined, size: 18),
                    onTap: _rename,
                  ),
                  const Divider(height: 0, indent: 16, endIndent: 16),
                  ListTile(
                    title: const Text('从哪天开始使用'),
                    subtitle: Text(
                      '${formatMonthDay(draft.effectiveFrom.month, draft.effectiveFrom.day)} 起，每年循环',
                    ),
                    trailing: const Icon(Icons.event_outlined, size: 18),
                    onTap: _pickDate,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // 快捷设置放在节次时间上方：先批量生成，再逐节微调。
            Card(
              child: Column(
                children: <Widget>[
                  ListTile(
                    leading: const Icon(Icons.bolt_outlined, size: 20),
                    title: const Text('快捷设置时间'),
                    subtitle: const Text('按时长和课间批量生成，可先预览'),
                    trailing: AnimatedRotation(
                      turns: _quickExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: const Icon(Icons.expand_more_rounded),
                    ),
                    onTap: () =>
                        setState(() => _quickExpanded = !_quickExpanded),
                  ),
                  // 展开/收起要有高度动画：直接 if 插入会让下面的内容"跳"一下。
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    alignment: Alignment.topCenter,
                    child: _quickExpanded
                        ? Column(
                            children: <Widget>[
                              const Divider(height: 0),
                              _QuickSetupPanel(
                                setup: _quick,
                                counts: counts,
                                bigBreakOn: _bigBreakOn,
                                onLessonMinutes: () => _pickDuration(
                                  title: '每节课时长',
                                  current: _quick.lessonMinutes,
                                  min: minLessonMinutes,
                                  max: maxLessonMinutes,
                                  apply: (value) => setState(() {
                                    _quick = _quick.copyWith(
                                      lessonMinutes: value,
                                    );
                                  }),
                                ),
                                onShortBreak: () => _pickDuration(
                                  title: '小课间时长',
                                  current: _quick.shortBreakMinutes,
                                  min: 5,
                                  max: maxShortBreakMinutes,
                                  apply: (value) => setState(() {
                                    _quick = _quick.copyWith(
                                      shortBreakMinutes: value,
                                    );
                                  }),
                                ),
                                onStartOf: (group) => _pickClock(
                                  title: '${group.label}开始时间',
                                  current: _quick.starts[group]!,
                                  apply: (value) => setState(() {
                                    final starts = Map<PeriodGroup, int>.from(
                                      _quick.starts,
                                    );
                                    starts[group] = value;
                                    _quick = _quick.copyWith(starts: starts);
                                  }),
                                ),
                                onBigBreakToggle: (enabled) => setState(() {
                                  _bigBreakOn = enabled;
                                  _quick = _quick.copyWith(
                                    bigBreaks: enabled
                                        ? _defaultBigBreaks()
                                        : const <PeriodGroup, BigBreak>{},
                                  );
                                }),
                                onBigBreakOf: (group) => _pickBigBreak(group),
                                onApply: _applyQuickSetup,
                              ),
                            ],
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            Row(
              children: <Widget>[
                Text('节次时间', style: theme.textTheme.titleSmall),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '共 ${draft.sectionCount} 节（到「课表节数」里改）',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Card(
              child: _SectionList(
                sections: draft.sections,
                onChange: _editSection,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              '提示：课表显示的节数跟随「课表节数」设置；教务里超出该节数的课，课表会自动扩展并标注。',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 名称 / 日期
  // ---------------------------------------------------------------------------

  Future<void> _rename() async {
    final draft = _draft;
    if (draft == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (context) => _RenameDialog(initial: draft.name),
    );
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return;
    _edit(draft.copyWith(name: trimmed));
  }

  /// 生效日期只选月日，年份由 [effectiveDateFor] 推算（早于今天就落到明年）。
  Future<void> _pickDate() async {
    final draft = _draft;
    if (draft == null) return;
    final picked = await showMonthDayWheel(
      context,
      month: draft.effectiveFrom.month,
      day: draft.effectiveFrom.day,
      title: '从哪天开始使用',
    );
    if (picked == null) return;
    _edit(
      draft.copyWith(
        effectiveFrom: effectiveDateFor(month: picked.month, day: picked.day),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 逐节改时间
  // ---------------------------------------------------------------------------

  void _editSection(SectionTime section, {int? start, int? end}) {
    final draft = _draft;
    if (draft == null) return;
    _edit(
      draft.copyWith(
        sections: <SectionTime>[
          for (final item in draft.sections)
            if (item.period == section.period)
              item.copyWith(startMinutes: start, endMinutes: end)
            else
              item,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 快捷设置
  // ---------------------------------------------------------------------------

  Map<PeriodGroup, BigBreak> _defaultBigBreaks() {
    final counts = model.sectionCounts;
    final result = <PeriodGroup, BigBreak>{};
    for (final group in PeriodGroup.values) {
      if ((counts[group] ?? 0) >= 2) {
        result[group] = const BigBreak(afterInGroup: 2, minutes: 20);
      }
    }
    return result;
  }

  Future<void> _pickDuration({
    required String title,
    required int current,
    required int min,
    required int max,
    required void Function(int value) apply,
  }) async {
    final value = await showDurationWheel(
      context,
      initialMinutes: current,
      title: title,
      minMinutes: min,
      maxMinutes: max,
    );
    if (value != null) apply(value);
  }

  Future<void> _pickClock({
    required String title,
    required int current,
    required void Function(int value) apply,
  }) async {
    final value = await showTimeWheel(
      context,
      initialMinutes: current,
      title: title,
    );
    if (value != null) apply(value);
  }

  /// 大课间：一次弹窗同时设「第几节后」与「休息多久」。
  Future<void> _pickBigBreak(PeriodGroup group) async {
    final count = model.sectionCounts[group] ?? 0;
    if (count < 2) return;
    final existing = _quick.bigBreaks[group];
    final picked = await showBigBreakWheel(
      context,
      maxAfter: count - 1,
      after: existing?.afterInGroup ?? 2,
      minutes: existing?.minutes ?? 20,
      title: '${group.label}大课间',
    );
    if (picked == null) return;
    setState(() {
      final bigBreaks = Map<PeriodGroup, BigBreak>.from(_quick.bigBreaks);
      bigBreaks[group] = BigBreak(
        afterInGroup: picked.after,
        minutes: picked.minutes,
      );
      _quick = _quick.copyWith(bigBreaks: bigBreaks);
    });
  }

  /// 应用：生成 → 预览确认 → 写入草稿（不落盘，等点右上角对勾）。
  Future<void> _applyQuickSetup() async {
    List<SectionTime> sections;
    try {
      sections = buildSections(_quick, model.sectionCounts);
    } on ArgumentError catch (error) {
      _toast('${error.message}');
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('将生成 ${sections.length} 节'),
        content: SizedBox(
          width: 320,
          height: 300,
          child: ListView.separated(
            itemCount: sections.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final section = sections[index];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: <Widget>[
                    SizedBox(width: 52, child: Text('第 ${section.period} 节')),
                    SizedBox(
                      width: 40,
                      child: Text(
                        section.group.label,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ),
                    Text(
                      '${formatClock(section.startMinutes)} – ${formatClock(section.endMinutes)}',
                      style: const TextStyle(
                        fontFeatures: <FontFeature>[
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('应用'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final draft = _draft;
    if (draft == null) return;

    // 面板参数记住（下次回填）。
    await model.saveQuickSetup(_quick);
    _edit(draft.copyWith(sections: sections));
    _toast('已应用 ${sections.length} 节，别忘了点右上角保存');
  }

  Future<void> _delete() async {
    final draft = _draft;
    if (draft == null || _isNew) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除作息表'),
        content: Text('「${draft.name}」将被删除。'),
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
    if (confirmed != true) return;
    await model.deleteTimetable(draft.id);
    if (mounted) {
      setState(() => _dirty = false);
      Navigator.of(context).pop();
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

/// 节次列表：按上午/下午/晚上分组，每组一个标题，不再逐行标段名。
class _SectionList extends StatelessWidget {
  const _SectionList({required this.sections, required this.onChange});

  final List<SectionTime> sections;

  /// (被改的节, 新开始时间, 新结束时间)
  final void Function(SectionTime section, {int? start, int? end}) onChange;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (final group in PeriodGroup.values) {
      final items = sections
          .where((section) => section.group == group)
          .toList();
      if (items.isEmpty) continue;
      if (children.isNotEmpty) {
        children.add(const Divider(height: 1, indent: 16, endIndent: 16));
      }
      children.add(_GroupHeader(group: group, items: items));
      for (final item in items) {
        children.add(
          _SectionRow(section: item, onEdit: () => _edit(context, item)),
        );
      }
    }
    return Column(children: children);
  }

  /// 一节的时间用「开始 + 结束」一次调完：改结束时间不该被"时长"绑住，
  /// 有些课就是比别的短/长。
  Future<void> _edit(BuildContext context, SectionTime section) async {
    final picked = await showTimeRangeWheel(
      context,
      startMinutes: section.startMinutes,
      endMinutes: section.endMinutes,
      title: '第 ${section.period} 节',
    );
    if (picked == null) return;
    onChange(section, start: picked.start, end: picked.end);
  }
}

/// 分组标题：`上午 · 4 节 · 08:00 – 11:40`。
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.group, required this.items});

  final PeriodGroup group;
  final List<SectionTime> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final first = items.first;
    final last = items.last;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Row(
        children: <Widget>[
          Text(
            group.label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w500,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              '${items.length} 节 · ${formatClock(first.startMinutes)} – ${formatClock(last.endMinutes)}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.hintColor,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.section, required this.onEdit});

  final SectionTime section;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onEdit,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        child: Row(
          children: <Widget>[
            // 固定宽度 + 不换行：之前 "第 10 节" 比 "第 1 节" 宽，会把右侧时间挤到第二行。
            SizedBox(
              width: 68,
              child: Text(
                '第 ${section.period} 节',
                maxLines: 1,
                softWrap: false,
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const Spacer(),
            _TimeChip(text: formatClock(section.startMinutes)),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text('–', style: theme.textTheme.bodySmall),
            ),
            _TimeChip(text: formatClock(section.endMinutes)),
          ],
        ),
      ),
    );
  }
}

class _TimeChip extends StatelessWidget {
  const _TimeChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest
            .withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 13,
          fontFeatures: <FontFeature>[FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

class _QuickSetupPanel extends StatelessWidget {
  const _QuickSetupPanel({
    required this.setup,
    required this.counts,
    required this.bigBreakOn,
    required this.onLessonMinutes,
    required this.onShortBreak,
    required this.onStartOf,
    required this.onBigBreakToggle,
    required this.onBigBreakOf,
    required this.onApply,
  });

  final QuickSetup setup;

  /// 全局节数（分段）。面板里只读展示，不允许改——改了会牵动所有作息表。
  final Map<PeriodGroup, int> counts;
  final bool bigBreakOn;
  final VoidCallback onLessonMinutes;
  final VoidCallback onShortBreak;
  final void Function(PeriodGroup group) onStartOf;
  final void Function(bool enabled) onBigBreakToggle;
  final void Function(PeriodGroup group) onBigBreakOf;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hint = theme.textTheme.bodySmall?.copyWith(color: theme.hintColor);
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        children: <Widget>[
          _SettingRow(
            label: '每节课时长',
            value: '${setup.lessonMinutes} 分钟',
            onTap: onLessonMinutes,
          ),
          _SettingRow(
            label: '小课间',
            value: '${setup.shortBreakMinutes} 分钟',
            onTap: onShortBreak,
          ),
          for (final group in PeriodGroup.values)
            _SettingRow(
              label: '${group.label}开始',
              value: formatClock(setup.starts[group] ?? 0),
              onTap: () => onStartOf(group),
            ),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            dense: true,
            title: const Text('大课间休息'),
            subtitle: Text(bigBreakOn ? '按下面设置，替代该次小课间' : '默认关闭', style: hint),
            value: bigBreakOn,
            onChanged: onBigBreakToggle,
          ),
          if (bigBreakOn)
            for (final group in PeriodGroup.values)
              if ((counts[group] ?? 0) >= 2)
                _SettingRow(
                  label: '${group.label}大课间',
                  value:
                      '第 ${setup.bigBreaks[group]?.afterInGroup ?? 2} 节后 · '
                      '${setup.bigBreaks[group]?.minutes ?? 20} 分钟',
                  onTap: () => onBigBreakOf(group),
                  indented: true,
                ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 4),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '合计 ${countsSum(counts)} 节（节数在「课表节数」里改）',
                    style: hint,
                  ),
                ),
                FilledButton.icon(
                  onPressed: onApply,
                  icon: const Icon(Icons.playlist_add_check_rounded, size: 18),
                  label: const Text('应用'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一行设置：标签在左、值靠右，**整行都能点**（不只点值）。
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.label,
    required this.value,
    required this.onTap,
    this.indented = false,
  });

  final String label;
  final String value;
  final VoidCallback onTap;
  final bool indented;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.fromLTRB(indented ? 28 : 14, 10, 14, 10),
        child: Row(
          children: <Widget>[
            Text(label, style: theme.textTheme.bodyMedium),
            const Spacer(),
            Text(
              value,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.primary,
                fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 16, color: theme.hintColor),
          ],
        ),
      ),
    );
  }
}

/// 重命名对话框：输入框的 [TextEditingController] 由它自己持有并释放。
///
/// 控制器如果放在调用方 new 出来，就没人负责 dispose（泄漏）；而在对话框退场
/// 动画还没走完时就 dispose，会报"disposed 后又被使用"。
class _RenameDialog extends StatefulWidget {
  const _RenameDialog({required this.initial});

  final String initial;

  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('重命名作息表'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: '名称'),
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_controller.text),
          child: const Text('确定'),
        ),
      ],
    );
  }
}
