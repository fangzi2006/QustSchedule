/// 更新日志页面：展示根目录 CHANGELOG.md 中的版本历史与改进说明。
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../src/app_version.dart';

/// 更新日志页面。
class ChangelogPage extends StatefulWidget {
  const ChangelogPage({super.key});

  @override
  State<ChangelogPage> createState() => _ChangelogPageState();
}

class _ChangelogPageState extends State<ChangelogPage> {
  List<_ReleaseLog>? _releases;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadChangelog();
  }

  Future<void> _loadChangelog() async {
    try {
      final content = await rootBundle.loadString('CHANGELOG.md');
      if (!mounted) return;
      setState(() {
        _releases = _parseChangelog(content);
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

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      itemCount: _releases!.length,
      separatorBuilder: (_, _) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final release = _releases![index];
        final isCurrentVersion = release.version == appVersion;

        return Card(
          elevation: isCurrentVersion ? 1.5 : 0.5,
          color: isCurrentVersion
              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.25)
              : null,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: isCurrentVersion
                ? BorderSide(
                    color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    width: 1.2,
                  )
                : BorderSide(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.4,
                    ),
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
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          '当前版本',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
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
                if (release.description.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    release.description,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                // 各小节分类 (新增 / 优化 / 修复 等)
                for (final section in release.sections) ...[
                  const SizedBox(height: 12),
                  _buildSectionHeader(context, section.title),
                  const SizedBox(height: 6),
                  for (final item in section.items) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 5),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 6, right: 8),
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          Expanded(
                            child: SelectableText(
                              item,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                height: 1.45,
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
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    final theme = Theme.of(context);
    Color color;
    IconData icon;

    switch (title) {
      case '新增':
        color = const Color(0xFF2E7D32); // Green
        icon = Icons.add_circle_outline_rounded;
        break;
      case '优化':
        color = const Color(0xFF1976D2); // Blue
        icon = Icons.auto_awesome_outlined;
        break;
      case '修复':
        color = const Color(0xFFE65100); // Orange
        icon = Icons.build_circle_outlined;
        break;
      default:
        color = theme.colorScheme.primary;
        icon = Icons.label_outline_rounded;
    }

    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 6),
        Text(
          title,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }
}

class _ReleaseLog {
  const _ReleaseLog({
    required this.version,
    required this.date,
    required this.description,
    required this.sections,
  });

  final String version;
  final String date;
  final String description;
  final List<_LogSection> sections;
}

class _LogSection {
  const _LogSection({required this.title, required this.items});

  final String title;
  final List<String> items;
}

/// 解析 CHANGELOG.md 为结构化数据
List<_ReleaseLog> _parseChangelog(String markdown) {
  final lines = markdown.split(RegExp(r'\r?\n'));
  final releases = <_ReleaseLog>[];

  String? currentVersion;
  String currentDate = '';
  final descBuffer = StringBuffer();
  String? currentSectionTitle;
  final currentSectionItems = <String>[];
  final currentSections = <_LogSection>[];

  void commitCurrentSection() {
    if (currentSectionTitle != null && currentSectionItems.isNotEmpty) {
      currentSections.add(
        _LogSection(
          title: currentSectionTitle!,
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
        _ReleaseLog(
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

    if (line.startsWith('- ')) {
      final itemText = line.substring(2).trim();
      if (itemText.isNotEmpty) {
        currentSectionItems.add(itemText);
      }
    } else if (line.isNotEmpty && !line.startsWith('#')) {
      if (currentSectionTitle == null) {
        if (descBuffer.isNotEmpty) descBuffer.write(' ');
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
