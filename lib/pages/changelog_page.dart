/// 更新日志页面：展示根目录 CHANGELOG.md 中的版本历史与改进说明。
///
/// 并发与转场解耦设计：
/// - 资产读取、UTF-8 解码、Markdown 结构解析与行内 `**加粗**`/`` `代码` `` 分词
///   在进入页面时立即并行发起，并卸载到后台 Isolate 执行（UI 线程 0ms 解析开销）；
/// - 260ms 路由滑入期间仅渲染超轻量骨架外壳且不中途触发 `setState`，
///   动画落稳瞬间直接挂载已就绪数据，交由原生 `ListView.separated` 按视口懒构建。
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_version.dart';
import '../src/formatted_text_span.dart';
import '../src/route_settled.dart';
import '../widgets/changelog_category_badge.dart';
import '../widgets/page_skeleton.dart';
import '../widgets/tactile_button.dart';

/// 更新日志页面。
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({
    super.key,
    this.initialReleases,
    this.forceRefresh = false,
  });

  /// 可选的预加载更新日志列表（命中缓存或测试传入时无需再读资产）
  final List<ReleaseLog>? initialReleases;

  /// 是否忽略内存缓存重新加载并解析
  final bool forceRefresh;

  /// 单例静态缓存：解析完成后保留，后续打开 0 I/O
  static List<ReleaseLog>? _cachedReleases;

  /// 并发去重中的在途加载任务
  static Future<List<ReleaseLog>>? _inFlightLoad;

  /// 测试清理静态缓存与在途状态
  @visibleForTesting
  static void resetCache() {
    _cachedReleases = null;
    _inFlightLoad = null;
  }

  /// 读取并解析 CHANGELOG.md（命中缓存直接返回，否则后台 Isolate 并行解码与解析）。
  static Future<List<ReleaseLog>> loadReleases({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedReleases != null) {
      return _cachedReleases!;
    }
    if (!forceRefresh && _inFlightLoad != null) {
      return _inFlightLoad!;
    }

    late final Future<List<ReleaseLog>> future;
    future = _loadAndParseReleases().whenComplete(() {
      if (identical(_inFlightLoad, future)) {
        _inFlightLoad = null;
      }
    });
    _inFlightLoad = future;
    return future;
  }

  static Future<List<ReleaseLog>> _loadAndParseReleases() async {
    final data = await rootBundle.load('CHANGELOG.md');
    final bytes = Uint8List.fromList(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
    );
    final parsed = await runInBackground<List<ReleaseLog>>(
      () => parseChangelogBytes(bytes),
    );
    final unmodifiable = List<ReleaseLog>.unmodifiable(parsed);
    _cachedReleases = unmodifiable;
    return unmodifiable;
  }

  /// 点击「更新日志」时的即时导航快捷方法：
  /// 立即发起切页动画不阻塞点击响应，同时在页面挂载首帧并行加载与解析日志。
  static Future<void> open(BuildContext context, {bool forceRefresh = false}) {
    final cached = !forceRefresh ? _cachedReleases : null;
    return Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) =>
            ChangelogPage(initialReleases: cached, forceRefresh: forceRefresh),
      ),
    );
  }

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage>
    with RouteSettledStateMixin<ChangelogPage> {
  List<ReleaseLog>? _releases;
  String? _errorMessage;
  int _loadGeneration = 0;

  @override
  void initState() {
    super.initState();
    final preloaded =
        widget.initialReleases ??
        (!widget.forceRefresh ? ChangelogPage._cachedReleases : null);
    if (preloaded != null) {
      _releases = preloaded;
    } else {
      // 立即并行启动后台 I/O 与 Isolate 解析，与 260ms 路由滑入动画完全并行。
      _loadChangelog(forceRefresh: widget.forceRefresh);
    }
  }

  Future<void> _loadChangelog({required bool forceRefresh}) async {
    final generation = ++_loadGeneration;
    try {
      final parsed = await ChangelogPage.loadReleases(
        forceRefresh: forceRefresh,
      );
      if (!mounted || generation != _loadGeneration) return;
      _releases = parsed;
      _errorMessage = null;
      // 入场动画尚未落稳时不触发中途 setState，待 onRouteSettled 一次性挂载。
      if (isRouteSettled) {
        setState(() {});
      }
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      _errorMessage = '无法加载更新日志: $e';
      if (isRouteSettled) {
        setState(() {});
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: TactileAppBar(
        leading: const TactileBackButton(),
        title: const Text('更新日志'),
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
    if (!isRouteSettled) {
      return const CardListTransitionPlaceholder(cardCount: 2);
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.error_outline_rounded,
                size: 48,
                color: theme.colorScheme.error,
              ),
              const SizedBox(height: 12),
              Text(
                _errorMessage!,
                style: TextStyle(color: theme.colorScheme.error),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              TactileActionButton(
                variant: TactileActionVariant.tonal,
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _releases = null;
                  });
                  _loadChangelog(forceRefresh: true);
                },
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    final releases = _releases;
    if (releases == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (releases.isEmpty) {
      return const Center(child: Text('暂无更新日志记录'));
    }

    return SelectionArea(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: releases.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) =>
            _ReleaseLogCard(release: releases[index]),
      ),
    );
  }
}

class _ReleaseLogCard extends StatelessWidget {
  const _ReleaseLogCard({required this.release});

  final ReleaseLog release;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isCurrentVersion = appVersion != '-' && release.version == appVersion;
    final descBaseStyle = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      height: 1.5,
    );
    final itemBaseStyle = theme.textTheme.bodyMedium?.copyWith(height: 1.45);

    return Card(
      // 卡片内部全为带 16px 内边距的纯展示内容、无点击水波纹，关闭抗锯齿圆角裁剪减少光栅开销。
      clipBehavior: Clip.none,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: isCurrentVersion
            ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
            : BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1.0,
              ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 版本标题栏
            Row(
              children: [
                Text(
                  'v${release.version}',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isCurrentVersion
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurface,
                  ),
                ),
                if (isCurrentVersion) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2.5,
                    ),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      '当前版本',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimary,
                      ),
                    ),
                  ),
                ],
                const Spacer(),
                if (release.date.isNotEmpty)
                  Text(
                    release.date,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.hintColor,
                    ),
                  ),
              ],
            ),
            // 核心亮点速览 Callout 引用框
            if (release.description.isNotEmpty) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: isCurrentVersion
                      ? theme.colorScheme.primary.withValues(alpha: 0.05)
                      : theme.colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.35,
                        ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isCurrentVersion
                        ? theme.colorScheme.primary.withValues(alpha: 0.2)
                        : theme.colorScheme.outlineVariant.withValues(
                            alpha: 0.3,
                          ),
                  ),
                ),
                child: Text.rich(
                  release.descriptionSegments != null
                      ? buildTextSpanFromSegments(
                          release.descriptionSegments!,
                          baseStyle: descBaseStyle,
                        )
                      : buildFormattedTextSpan(
                          context,
                          release.description,
                          baseStyle: descBaseStyle,
                        ),
                ),
              ),
            ],
            // 各小节分类 (新增 / 优化 / 修复 等)
            for (final section in release.sections) ...[
              const SizedBox(height: 14),
              if (section.title.isNotEmpty) ...[
                ChangelogCategoryBadge(
                  title: section.title,
                  backgroundAlpha: 0.1,
                ),
                const SizedBox(height: 8),
              ],
              for (var i = 0; i < section.items.length; i++) ...[
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(
                          top: 7,
                          right: 8,
                          left: 2,
                        ),
                        child: Container(
                          width: 5,
                          height: 5,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: theme.colorScheme.primary.withValues(
                              alpha: 0.7,
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text.rich(
                          section.itemSegments != null &&
                                  i < section.itemSegments!.length
                              ? buildTextSpanFromSegments(
                                  section.itemSegments![i],
                                  baseStyle: itemBaseStyle,
                                )
                              : buildFormattedTextSpan(
                                  context,
                                  section.items[i],
                                  baseStyle: itemBaseStyle,
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class ReleaseLog {
  const ReleaseLog({
    required this.version,
    required this.date,
    required this.description,
    required this.sections,
    this.descriptionSegments,
  });

  final String version;
  final String date;
  final String description;
  final List<LogSection> sections;

  /// 后台预解析好的亮点描述行内分词（为空时回退按需解析，兼容测试直接构造）。
  final List<FormattedSegment>? descriptionSegments;
}

class LogSection {
  const LogSection({
    required this.title,
    required this.items,
    this.itemSegments,
  });

  final String title;
  final List<String> items;

  /// 后台预解析好的各条目行内分词（与 [items] 一一对应，为空时回退按需解析）。
  final List<List<FormattedSegment>>? itemSegments;
}

final RegExp _changelogVersionRegex = RegExp(
  r'^##\s*\[(.*?)\](?:\s*-\s*(\d{4}-\d{2}-\d{2}))?',
);
final RegExp _changelogSectionRegex = RegExp(r'^###\s*(.*)');

List<List<String>> _splitReleaseLineGroups(String markdown) {
  final groups = <List<String>>[];
  List<String>? currentGroup;
  for (final rawLine in LineSplitter.split(markdown)) {
    final trimmed = rawLine.trim();
    if (_changelogVersionRegex.hasMatch(trimmed)) {
      currentGroup = <String>[trimmed];
      groups.add(currentGroup);
    } else if (currentGroup != null && trimmed.isNotEmpty) {
      currentGroup.add(trimmed);
    }
  }
  return groups;
}

ReleaseLog _parseReleaseGroup(List<String> lines) {
  final headerMatch = _changelogVersionRegex.firstMatch(lines.first);
  final version = headerMatch?.group(1)?.trim() ?? '';
  final date = headerMatch?.group(2)?.trim() ?? '';
  final descBuffer = StringBuffer();
  String? currentSectionTitle;
  final currentSectionItems = <String>[];
  final currentSections = <LogSection>[];

  void commitCurrentSection() {
    if (currentSectionItems.isNotEmpty || currentSectionTitle != null) {
      final items = List<String>.unmodifiable(currentSectionItems);
      final itemSegments = List<List<FormattedSegment>>.unmodifiable(
        <List<FormattedSegment>>[
          for (final item in items) parseFormattedSegments(item),
        ],
      );
      currentSections.add(
        LogSection(
          title: currentSectionTitle ?? '',
          items: items,
          itemSegments: itemSegments,
        ),
      );
      currentSectionItems.clear();
    }
    currentSectionTitle = null;
  }

  for (var i = 1; i < lines.length; i++) {
    final line = lines[i];
    final sMatch = _changelogSectionRegex.firstMatch(line);
    if (sMatch != null) {
      commitCurrentSection();
      currentSectionTitle = sMatch.group(1)?.trim() ?? '';
      continue;
    }

    if (line.startsWith('- ') ||
        line.startsWith('* ') ||
        line.startsWith('+ ')) {
      final itemText = line.substring(2).trim();
      if (itemText.isNotEmpty) {
        currentSectionItems.add(itemText);
      }
    } else if (!line.startsWith('#')) {
      if (currentSectionTitle == null) {
        if (descBuffer.isNotEmpty) descBuffer.write('\n');
        descBuffer.write(line);
      } else if (currentSectionItems.isNotEmpty) {
        // 多行条目追加
        final last = currentSectionItems.removeLast();
        currentSectionItems.add('$last $line');
      }
    }
  }

  commitCurrentSection();
  final description = descBuffer.toString().trim();
  return ReleaseLog(
    version: version,
    date: date,
    description: description,
    descriptionSegments: description.isEmpty
        ? const <FormattedSegment>[]
        : parseFormattedSegments(description),
    sections: List<LogSection>.unmodifiable(currentSections),
  );
}

/// 从 UTF-8 字节直接解码并解析 CHANGELOG.md（纯 Dart 顶层函数，可直接在后台 Isolate 执行）。
List<ReleaseLog> parseChangelogBytes(Uint8List bytes) {
  return parseChangelog(utf8.decode(bytes));
}

/// 解析 CHANGELOG.md 为结构化数据（并预拆行内加粗/代码分词）。
List<ReleaseLog> parseChangelog(String markdown) {
  return <ReleaseLog>[
    for (final group in _splitReleaseLineGroups(markdown))
      _parseReleaseGroup(group),
  ];
}
