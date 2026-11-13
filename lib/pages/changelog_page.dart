/// 更新日志页面：展示根目录 CHANGELOG.md 中的版本历史与改进说明。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_version.dart';
import '../src/formatted_text_span.dart';
import '../widgets/changelog_category_badge.dart';

/// 更新日志页面。
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key, this.initialReleases});

  /// 可选的预加载更新日志列表（用于点击时直传首帧渲染，彻底消除转场突变与掉帧）
  final List<ReleaseLog>? initialReleases;

  /// 单例静态缓存：首次解析后内存保留，再次进入 0 毫秒首帧直出
  static List<ReleaseLog>? _cachedReleases;

  /// 测试清理静态缓存
  @visibleForTesting
  static void resetCache() => _cachedReleases = null;

  /// 加载并解析 CHANGELOG.md（若已缓存直接返回，否则仅在调用时读取）
  static Future<List<ReleaseLog>> loadReleases({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh && _cachedReleases != null) return _cachedReleases!;
    final content = await rootBundle.loadString('CHANGELOG.md');
    final parsed = parseChangelog(content);
    _cachedReleases = parsed;
    return parsed;
  }

  /// 点击「更新日志」时的即时导航快捷方法：
  /// 点击瞬间读取本地内置资产并直接跳转，切页动画从第 0 帧开始就是完整内容。
  static Future<void> open(
    BuildContext context, {
    bool forceRefresh = false,
  }) async {
    final releases = await loadReleases(forceRefresh: forceRefresh);
    if (!context.mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => ChangelogPage(initialReleases: releases),
      ),
    );
  }

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  List<ReleaseLog>? _releases;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    if (widget.initialReleases != null) {
      _releases = widget.initialReleases;
    } else if (ChangelogPage._cachedReleases != null) {
      _releases = ChangelogPage._cachedReleases;
    } else {
      _loadChangelog();
    }
  }

  Future<void> _loadChangelog() async {
    try {
      final releases = await ChangelogPage.loadReleases();
      if (!mounted) return;
      setState(() {
        _releases = releases;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = '无法加载更新日志: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('更新日志')),
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
              FilledButton.tonal(
                onPressed: () {
                  setState(() {
                    _errorMessage = null;
                    _releases = null;
                  });
                  _loadChangelog();
                },
                child: const Text('重试'),
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

    return SelectionArea(
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        itemCount: _releases!.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final release = _releases![index];
          final isCurrentVersion =
              appVersion != '-' && release.version == appVersion;

          return Card(
            elevation: isCurrentVersion ? 2.0 : 0.5,
            color: theme.colorScheme.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: isCurrentVersion
                  ? BorderSide(color: theme.colorScheme.primary, width: 1.5)
                  : BorderSide(
                      color: theme.colorScheme.outlineVariant.withValues(
                        alpha: 0.4,
                      ),
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
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.25,
                                ),
                                blurRadius: 4,
                                offset: const Offset(0, 1),
                              ),
                            ],
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
                            : theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.35),
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
                                  baseStyle: theme.textTheme.bodyMedium
                                      ?.copyWith(height: 1.45),
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
        },
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

/// 解析 CHANGELOG.md 为结构化数据
List<ReleaseLog> parseChangelog(String markdown) {
  final lines = markdown.split(RegExp(r'\r?\n'));
  final releases = <ReleaseLog>[];

  String? currentVersion;
  String currentDate = '';
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

  void commitCurrentRelease() {
    commitCurrentSection();
    if (currentVersion != null) {
      releases.add(
        ReleaseLog(
          version: currentVersion!,
          date: currentDate,
          description: descBuffer.toString().trim(),
          sections: List.unmodifiable(currentSections),
        ),
      );
      currentSections.clear();
      descBuffer.clear();
    }
    currentVersion = null;
    currentDate = '';
  }

  final versionRegex = RegExp(
    r'^##\s*\[(.*?)\](?:\s*-\s*(\d{4}-\d{2}-\d{2}))?',
  );
  final sectionRegex = RegExp(r'^###\s*(.*)');

  for (final rawLine in lines) {
    final line = rawLine.trim();

    final vMatch = versionRegex.firstMatch(line);
    if (vMatch != null) {
      commitCurrentRelease();
      currentVersion = vMatch.group(1)?.trim() ?? '';
      currentDate = vMatch.group(2)?.trim() ?? '';
      continue;
    }

    if (currentVersion == null) {
      // 头部未进入版本前的内容跳过
      continue;
    }

    final sMatch = sectionRegex.firstMatch(line);
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
    } else if (line.isNotEmpty && !line.startsWith('#')) {
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

  commitCurrentRelease();
  return releases;
}
