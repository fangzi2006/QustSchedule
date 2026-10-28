/// 调试页：把"学校给的原样数据"和"我们解析出来的结果"摊开对照。
///
/// 用途：
///  - 课表显示不对时，先看这里的 `kbList` 原始行与解析结果，判断是数据问题还是解析问题；
///  - 换个学校接入时，看学期列表怎么来的、请求打到哪、Cookie 在不在；
///  - 反馈问题时一键复制，不需要截图。
///
/// 安全：不显示任何 Cookie **值**，也不显示密码；只显示 Cookie 名与请求元数据。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:zf_academic/zf_academic.dart';

import '../src/app_model.dart';
import '../widgets/course_detail_sheet.dart'
    show compressWeeks, showEntryDetails;

class DebugPage extends StatelessWidget {
  const DebugPage({super.key, required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      const Tab(text: '概览'),
      const Tab(text: '请求'),
      const Tab(text: '原始课表'),
      const Tab(text: '解析结果'),
    ];
    final views = <Widget>[
      _OverviewTab(model: model),
      _RequestsTab(model: model),
      _RawTab(model: model),
      _ParsedTab(model: model),
    ];
    return DefaultTabController(
      length: tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('调试信息'),
          bottom: TabBar(isScrollable: true, tabs: tabs),
        ),
        body: TabBarView(children: views),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 概览
// ---------------------------------------------------------------------------

class _OverviewTab extends StatelessWidget {
  const _OverviewTab({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final rows = <(String, String)>[
      ('教务地址', model.schoolBaseUrl),
      ('状态', model.status.name),
      ('错误码', model.errorCode.isEmpty ? '-' : model.errorCode),
      ('提示', model.message.isEmpty ? '-' : model.message),
      ('学号', model.studentId.isEmpty ? '-' : model.studentId),
      ('姓名', model.studentName.isEmpty ? '-' : model.studentName),
      ('当前学期', model.termId.isEmpty ? '-' : model.termId),
      ('学期总数', model.terms == null ? '未加载' : '${model.terms!.items.length}'),
      (
        '课程条数',
        model.schedule == null ? '未加载' : '${model.schedule!.entries.length}',
      ),
      ('最大周次', '${model.maxWeek}'),
      ('正在查看', '第 ${model.week} 周（本周为第 ${model.currentWeekOfToday} 周）'),
      ('本周课程', '${model.weekEntryCount} 条'),
      (
        '第 1 周周一',
        model.termStart == null
            ? '未定位'
            : '${model.termStart!.year}-${_two(model.termStart!.month)}-${_two(model.termStart!.day)}',
      ),
      ('本周范围', model.weekRange.isEmpty ? '-' : model.weekRange),
      (
        'Cookie 名',
        model.cookieNames.isEmpty ? '无' : model.cookieNames.join(', '),
      ),
      ('请求记录', '${model.requestLog.length} 条'),
      (
        '原始响应',
        model.rawScheduleBody == null
            ? '未获取'
            : '${model.rawScheduleBody!.length} 字符',
      ),
      ('kbList 行', '${model.rawScheduleRows.length} 行'),
    ];

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const Expanded(
                      child: Text(
                        '环境与状态',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.copy_all, size: 20),
                      tooltip: '复制全部',
                      onPressed: () => _copyText(
                        context,
                        rows.map((row) => '${row.$1}: ${row.$2}').join('\n'),
                        '概览已复制',
                      ),
                    ),
                  ],
                ),
                for (final (label, value) in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        SizedBox(
                          width: 92,
                          child: Text(
                            label,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                        Expanded(
                          child: SelectableText(
                            value,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text(
                  '周次相关（教务不提供开学日期）',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 6),
                const Text(
                  '第 1 周周一要么是按学期估算的，要么是你在课表页「校准当前周次」时反推出来的。'
                  '若周视图与真实校历不符，先看这里的日期，再到课表页校准一次。',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 8),
                Text(
                  '估算规则：秋季学期=该年 9 月 1 日所在周的周一；春季=次年 2 月 23 日所在周的周一。',
                  style: TextStyle(
                    fontSize: 12,
                    color: Theme.of(context).hintColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

// ---------------------------------------------------------------------------
// 请求
// ---------------------------------------------------------------------------

class _RequestsTab extends StatelessWidget {
  const _RequestsTab({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final log = model.requestLog;
    if (log.isEmpty) {
      return const Center(child: Text('还没有请求记录'));
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '最近 ${log.length} 条（不含 Cookie 值与请求体）\n'
                  '绿勾 = 状态码正常且正文不像错误页；红/橙 = 这一跳有问题',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制'),
                onPressed: () => _copyText(
                  context,
                  log
                      .map(
                        (item) =>
                            '${item.method} ${item.url} '
                            '[${item.status}${item.issue == null ? '' : ' ${item.issue}'}] '
                            '${item.purpose.name}',
                      )
                      .join('\n'),
                  '请求记录已复制',
                ),
              ),
            ],
          ),
        ),
        // 把"本次失败被归成哪一类"直接写在请求列表上方。
        // 逐条看请求很难看出结论，而错误码正是用户反馈时最需要的那一条信息。
        if (model.status == AppStatus.failed)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Icon(Icons.error_outline, size: 16, color: Colors.red),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '本次失败：${model.errorCode.isEmpty ? '未分类' : model.errorCode}'
                    '${model.message.isEmpty ? '' : ' · ${model.message}'}',
                    style: const TextStyle(fontSize: 12, color: Colors.red),
                  ),
                ),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
          child: Text(
            '课表是走**数据接口**抓的（如 kbcx/xskbcx_cxXsKb.html?gnmkdm=N253508）：'
            '它在浏览器里直接打开是空的——要登录态 + POST 才返回数据。'
            '想人工核对课表，请在已登录的浏览器里打开"课表查询"页面（如 '
            'kbcx/xskbcx_cxXskbcxIndex.html?gnmkdm=N2151）。',
            style: Theme.of(context).textTheme.bodySmall
                ?.copyWith(color: Theme.of(context).hintColor),
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: log.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              // 最新的在上。
              final item = log[log.length - 1 - index];
              // **不能只看状态码**：网关的错误页、运维的"系统维护"页都能带着
              // HTTP 200 回来。只按 2xx 打绿勾，就会出现"请求记录显示正常、
              // 右上角却说页面结构不一致"的矛盾。issue 在收到响应时就算好了。
              final String? issue = item.issue;
              final bool statusOk = item.status >= 200 && item.status < 400;
              final bool ok = statusOk && issue == null;
              // 4xx 是"这一跳的请求/权限问题"；5xx 与错误页才是服务端坏了。
              final bool serverSide =
                  issue != null && !issue.startsWith('HTTP 4');
              return ListTile(
                dense: true,
                leading: Icon(
                  ok ? Icons.check_circle_outline : Icons.error_outline,
                  size: 18,
                  color: ok
                      ? Colors.green
                      : (serverSide ? Colors.red : Colors.orange),
                ),
                title: Text(
                  '${item.method} ${item.status}'
                  '${issue == null ? '' : ' · $issue'}',
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(item.url, style: const TextStyle(fontSize: 11)),
                trailing: Text(
                  item.purpose.name,
                  style: const TextStyle(fontSize: 10),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// 原始课表
// ---------------------------------------------------------------------------

class _RawTab extends StatelessWidget {
  const _RawTab({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final body = model.rawScheduleBody;
    final rows = model.rawScheduleRows;
    if (body == null && rows.isEmpty) {
      return const Center(child: Text('还没有获取过课表'));
    }
    return ListView(
      padding: const EdgeInsets.all(12),
      children: <Widget>[
        Card(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        '原始响应（${body?.length ?? 0} 字符）',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.copy, size: 16),
                      label: const Text('复制'),
                      onPressed: body == null
                          ? null
                          : () => _copyText(context, body, '原始响应已复制'),
                    ),
                  ],
                ),
                _CollapsibleText(text: body ?? ''),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          'kbList 行（${rows.length}）',
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        for (var index = 0; index < rows.length; index++)
          _RawRowTile(index: index, row: rows[index]),
      ],
    );
  }
}

class _RawRowTile extends StatelessWidget {
  const _RawRowTile({required this.index, required this.row});

  final int index;
  final Map<String, dynamic> row;

  @override
  Widget build(BuildContext context) {
    final name = row['kcmc'] ?? row['KCMC'] ?? '(无课程名)';
    final day = row['xqj'] ?? row['XQJ'] ?? '?';
    final periods =
        row['jcs'] ?? row['JCS'] ?? row['jcor'] ?? row['JCOR'] ?? '?';
    final weeks = row['zcd'] ?? row['ZCD'] ?? '?';
    final text = const JsonEncoder.withIndent('  ').convert(row);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ExpansionTile(
        dense: true,
        title: Text('$name', style: const TextStyle(fontSize: 13)),
        subtitle: Text(
          '#$index  周$day  第$periods节  $weeks',
          style: const TextStyle(fontSize: 11),
        ),
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    icon: const Icon(Icons.copy, size: 16),
                    label: const Text('复制这行 JSON'),
                    onPressed: () => _copyText(context, text, '已复制第 $index 行'),
                  ),
                ),
                SelectableText(
                  text,
                  style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// 解析结果
// ---------------------------------------------------------------------------

class _ParsedTab extends StatelessWidget {
  const _ParsedTab({required this.model});

  final AppModel model;

  @override
  Widget build(BuildContext context) {
    final entries = model.schedule?.entries ?? const <ScheduleEntry>[];
    if (entries.isEmpty) {
      return const Center(child: Text('还没有解析结果'));
    }
    return Column(
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 8, 0),
          child: Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${entries.length} 条记录（同一门课跨节会拆成多条）',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              TextButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('复制'),
                onPressed: () => _copyText(
                  context,
                  entries.map((entry) => _describe(entry)).join('\n'),
                  '解析结果已复制',
                ),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView.separated(
            itemCount: entries.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final entry = entries[index];
              final inWeek =
                  entry.weeks.isEmpty || entry.weeks.contains(model.week);
              return ListTile(
                dense: true,
                leading: Icon(
                  inWeek
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  size: 16,
                  color: inWeek
                      ? Theme.of(context).colorScheme.primary
                      : Theme.of(context).hintColor,
                ),
                title: Text(entry.name, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  '周${entry.day} 第 ${entry.startPeriod}-${entry.endPeriod} 节  '
                  '${entry.weeks.isEmpty ? "每周" : (entry.weeks.length > 12 ? "${entry.weeks.first}-${entry.weeks.last} 周等 ${entry.weeks.length} 周" : compressWeeks(entry.weeks))}\n'
                  '${entry.location ?? "-"}  ${entry.teacher ?? "-"}',
                  style: const TextStyle(fontSize: 11),
                ),
                isThreeLine: true,
                onTap: () => showEntryDetails(context, entry, model.week),
              );
            },
          ),
        ),
      ],
    );
  }

  static String _describe(ScheduleEntry entry) {
    final buffer = StringBuffer()
      ..write(
        '${entry.name} | 周${entry.day} 第${entry.startPeriod}-${entry.endPeriod}节 | ',
      )
      ..write(entry.weeks.isEmpty ? '每周' : compressWeeks(entry.weeks))
      ..write(' | 周次原始: [${entry.weeks.join(",")}]')
      ..write(' | ${entry.teacher ?? "-"} | ${entry.location ?? "-"}')
      ..write(' | id=${entry.id}');
    for (final detail in entry.details ?? const <ScheduleDetail>[]) {
      buffer.write(' | ${detail.label}=${detail.value}');
    }
    return buffer.toString();
  }
}

// ---------------------------------------------------------------------------
// 小部件
// ---------------------------------------------------------------------------

/// 长文本：默认只显示前 1200 字符，可展开/折叠，避免一次性排版几十 KB 卡住。
class _CollapsibleText extends StatefulWidget {
  const _CollapsibleText({required this.text});

  final String text;

  @override
  State<_CollapsibleText> createState() => _CollapsibleTextState();
}

class _CollapsibleTextState extends State<_CollapsibleText> {
  bool _expanded = false;

  static const int _previewLength = 1200;

  @override
  Widget build(BuildContext context) {
    final text = widget.text;
    if (text.isEmpty) return const Text('（空）');
    final long = text.length > _previewLength;
    final shown = _expanded || !long
        ? text
        : '${text.substring(0, _previewLength)}\n…';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        SelectableText(
          shown,
          style: const TextStyle(fontSize: 11, fontFamily: 'monospace'),
        ),
        if (long)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: () => setState(() => _expanded = !_expanded),
              child: Text(_expanded ? '收起' : '展开全部（${text.length} 字符）'),
            ),
          ),
      ],
    );
  }
}

void _copyText(BuildContext context, String text, String message) {
  Clipboard.setData(ClipboardData(text: text));
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(message), duration: const Duration(seconds: 2)),
  );
}
