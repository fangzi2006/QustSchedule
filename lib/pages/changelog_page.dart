/// 更新日志页面：展示根目录 CHANGELOG.md 中的版本历史与改进说明。
library;

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';

import '../src/app_version.dart';
import '../src/formatted_text_span.dart';
import '../widgets/changelog_category_badge.dart';
import '../widgets/tactile_button.dart';

/// 更新日志页面。
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({
    super.key,
    this.initialReleases,
    this.forceRefresh = false,
  });

  /// 首屏初始渲染的版本批次数量（刚好铺满首屏且转场零卡顿）
  @visibleForTesting
  static const int initialBatchSize = 2;

  /// 转场完成后每帧分段加载的版本批次数量
  @visibleForTesting
  static const int incrementalBatchSize = 2;

  /// 可选的预加载更新日志列表（命中缓存或测试传入时首帧直出首屏批次）
  final List<ReleaseLog>? initialReleases;

  /// 是否忽略内存缓存重新加载并分段解析
  final bool forceRefresh;

  /// 单例静态缓存：全量解析完成后保留，后续打开 0 I/O 且首屏直出
  static List<ReleaseLog>? _cachedReleases;

  /// 测试清理静态缓存
  @visibleForTesting
  static void resetCache() => _cachedReleases = null;

  /// 加载并解析 CHANGELOG.md（若已缓存直接返回，否则读取并全量解析）
  static Future<List<ReleaseLog>> loadReleases({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedReleases != null) return _cachedReleases!;
    final content = await rootBundle.loadString('CHANGELOG.md');
    final parsed = List<ReleaseLog>.unmodifiable(parseChangelog(content));
    _cachedReleases = parsed;
    return parsed;
  }

  /// 点击「更新日志」时的即时导航快捷方法：
  /// 立即发起切页动画不阻塞点击响应；页面挂载后再按首屏批次与转场避让策略分段解析与渲染。
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

class _ChangelogPageState extends State<ChangelogPage> {
  final ScrollController _scrollController = ScrollController();

  List<ReleaseLog>? _releases;
  List<List<String>> _pendingRawGroups = const <List<String>>[];
  int _pendingGroupCursor = 0;
  int _visibleCount = 0;
  String? _errorMessage;

  Animation<double>? _routeAnimation;
  bool _batchScheduled = false;
  int _loadGeneration = 0;

  bool get _hasRemainingChunks =>
      (_releases != null && _visibleCount < _releases!.length) ||
      _pendingGroupCursor < _pendingRawGroups.length;

  bool get _isRouteTransitioning =>
      _routeAnimation != null &&
      _routeAnimation!.status == AnimationStatus.forward;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    final preloaded =
        widget.initialReleases ??
        (!widget.forceRefresh ? ChangelogPage._cachedReleases : null);
    if (preloaded != null) {
      _releases = List<ReleaseLog>.from(preloaded);
      _visibleCount = math.min(
        ChangelogPage.initialBatchSize,
        _releases!.length,
      );
    } else {
      _loadChangelog();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final routeAnim = ModalRoute.of(context)?.animation;
    if (!identical(_routeAnimation, routeAnim)) {
      _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
      _routeAnimation = routeAnim;
      _routeAnimation?.addStatusListener(_handleRouteAnimationStatus);
    }
    _scheduleNextBatchIfNeeded();
  }

  @override
  void dispose() {
    _routeAnimation?.removeStatusListener(_handleRouteAnimationStatus);
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleRouteAnimationStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed ||
        status == AnimationStatus.dismissed) {
      _scheduleNextBatchIfNeeded();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients || !_hasRemainingChunks) return;
    if (_scrollController.position.extentAfter < 360) {
      _appendNextBatch(count: ChangelogPage.incrementalBatchSize * 2);
    }
  }

  void _scheduleNextBatchIfNeeded() {
    if (!mounted ||
        _batchScheduled ||
        !_hasRemainingChunks ||
        _isRouteTransitioning) {
      return;
    }
    _batchScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _batchScheduled = false;
      if (!mounted) return;
      _appendNextBatch();
    });
    SchedulerBinding.instance.scheduleFrame();
  }

  void _appendNextBatch({int count = ChangelogPage.incrementalBatchSize}) {
    final releases = _releases;
    if (releases == null || !_hasRemainingChunks) return;

    var changed = false;
    if (_pendingGroupCursor < _pendingRawGroups.length) {
      final end = math.min(
        _pendingGroupCursor + count,
        _pendingRawGroups.length,
      );
      for (var i = _pendingGroupCursor; i < end; i++) {
        releases.add(_parseReleaseGroup(_pendingRawGroups[i]));
      }
      _pendingGroupCursor = end;
      _visibleCount = releases.length;
      changed = true;
      if (_pendingGroupCursor >= _pendingRawGroups.length) {
        _pendingRawGroups = const <List<String>>[];
        _pendingGroupCursor = 0;
        ChangelogPage._cachedReleases = List<ReleaseLog>.unmodifiable(releases);
      }
    } else if (_visibleCount < releases.length) {
      _visibleCount = math.min(releases.length, _visibleCount + count);
      changed = true;
    }

    if (changed) {
      setState(() {});
    }
    _scheduleNextBatchIfNeeded();
  }

  Future<void> _loadChangelog() async {
    final generation = ++_loadGeneration;
    try {
      final content = await rootBundle.loadString('CHANGELOG.md');
      if (!mounted || generation != _loadGeneration) return;

      final groups = _splitReleaseLineGroups(content);
      if (groups.isEmpty) {
        ChangelogPage._cachedReleases = const <ReleaseLog>[];
        setState(() {
          _releases = <ReleaseLog>[];
          _pendingRawGroups = const <List<String>>[];
          _pendingGroupCursor = 0;
          _visibleCount = 0;
        });
        return;
      }

      final initialEnd = math.min(
        ChangelogPage.initialBatchSize,
        groups.length,
      );
      final initialReleases = <ReleaseLog>[
        for (var i = 0; i < initialEnd; i++) _parseReleaseGroup(groups[i]),
      ];

      setState(() {
        _releases = initialReleases;
        _visibleCount = initialReleases.length;
        if (initialEnd < groups.length) {
          _pendingRawGroups = groups;
          _pendingGroupCursor = initialEnd;
        } else {
          _pendingRawGroups = const <List<String>>[];
          _pendingGroupCursor = 0;
          ChangelogPage._cachedReleases = List<ReleaseLog>.unmodifiable(
            initialReleases,
          );
        }
      });
      _scheduleNextBatchIfNeeded();
    } catch (e) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _errorMessage = '无法加载更新日志: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        leading: const TactileBackButton(),
        title: const Text('更新日志'),
      ),
      body: SafeArea(child: _buildBody(theme)),
    );
  }

  Widget _buildBody(ThemeData theme) {
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
                    _pendingRawGroups = const <List<String>>[];
                    _pendingGroupCursor = 0;
                    _visibleCount = 0;
                  });
                  _loadChangelog();
                },
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_releases == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_releases!.isEmpty) {
      return const Center(child: Text('暂无更新日志记录'));
    }

    final showFooter = _hasRemainingChunks;
    return SelectionArea(
      child: ListView.separated(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _visibleCount + (showFooter ? 1 : 0),
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          if (index >= _visibleCount) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return RepaintBoundary(
            child: _ReleaseLogCard(release: _releases![index]),
          );
        },
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

    return Card(
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
                  buildFormattedTextSpan(
                    context,
                    release.description,
                    baseStyle: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
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
              for (final item in section.items) ...[
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
                          buildFormattedTextSpan(
                            context,
                            item,
                            baseStyle: theme.textTheme.bodyMedium?.copyWith(
                              height: 1.45,
                            ),
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
  });

  final String version;
  final String date;
  final String description;
  final List<LogSection> sections;
}

class LogSection {
  const LogSection({required this.title, required this.items});

  final String title;
  final List<String> items;
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
      currentSections.add(
        LogSection(
          title: currentSectionTitle ?? '',
          items: List.unmodifiable(currentSectionItems),
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
  return ReleaseLog(
    version: version,
    date: date,
    description: descBuffer.toString().trim(),
    sections: List.unmodifiable(currentSections),
  );
}

/// 解析 CHANGELOG.md 为结构化数据
List<ReleaseLog> parseChangelog(String markdown) {
  return <ReleaseLog>[
    for (final group in _splitReleaseLineGroups(markdown))
      _parseReleaseGroup(group),
  ];
}
