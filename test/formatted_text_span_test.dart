import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/changelog_page.dart';
import 'package:qustschedule/src/app_version.dart';
import 'package:qustschedule/src/formatted_text_span.dart';
import 'package:qustschedule/theme/app_theme.dart';

void main() {
  group('buildFormattedTextSpan 单元测试', () {
    testWidgets('空文本返回空的 TextSpan', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final span = buildFormattedTextSpan(context, '');
              expect(span.text, '');
              expect(span.children, isNull);
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('纯文本不进行标记分割并继承 baseStyle', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              const baseStyle = TextStyle(fontSize: 14, color: Colors.blue);
              final span = buildFormattedTextSpan(
                context,
                '普通文本毫无标记',
                baseStyle: baseStyle,
              );
              expect(span.text, '普通文本毫无标记');
              expect(span.style, baseStyle);
              expect(span.children, isNull);
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('解析 **加粗** 语法', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final span = buildFormattedTextSpan(context, '这是**加粗内容**测试');
              expect(span.children, isNotNull);
              expect(span.children!.length, 3);

              final first = span.children![0] as TextSpan;
              expect(first.text, '这是');
              expect(first.style, isNull);

              final second = span.children![1] as TextSpan;
              expect(second.text, '加粗内容');
              expect(second.style?.fontWeight, FontWeight.bold);

              final third = span.children![2] as TextSpan;
              expect(third.text, '测试');
              expect(third.style, isNull);
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('解析 `行内代码` 语法', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final span = buildFormattedTextSpan(
                context,
                '调用 `git status` 命令',
              );
              expect(span.children, isNotNull);
              expect(span.children!.length, 3);

              final codeSpan = span.children![1] as TextSpan;
              expect(codeSpan.text, 'git status');
              expect(codeSpan.style?.fontFamily, 'monospace');
              expect(codeSpan.style?.fontWeight, FontWeight.w600);
              return const SizedBox();
            },
          ),
        ),
      );
    });

    testWidgets('混合多种语法与未闭合标记安全容错', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              final span = buildFormattedTextSpan(
                context,
                '混合 **加粗** 与 `代码` 还有单个 * 和 ` 未闭合',
              );
              expect(span.children, isNotNull);
              // 包含：普通文本 -> 加粗 -> 普通文本 -> 代码 -> 普通尾部文本
              expect(span.children!.length, 5);

              final bold = span.children![1] as TextSpan;
              expect(bold.text, '加粗');
              expect(bold.style?.fontWeight, FontWeight.bold);

              final code = span.children![3] as TextSpan;
              expect(code.text, '代码');
              expect(code.style?.fontFamily, 'monospace');

              final tail = span.children![4] as TextSpan;
              expect(tail.text, ' 还有单个 * 和 ` 未闭合');
              return const SizedBox();
            },
          ),
        ),
      );
    });
  });

  group('parseChangelog 纯逻辑解析测试', () {
    test('正确解析标准版本描述并提取结构化小节与条目', () {
      const mockMarkdown = '''
# 更新日志

## [1.5.0] - 2026-11-05

**核心亮点速览**：
1. **新增学业仪表盘**：考试与绩点。
2. **网络超时缩短**：全链路采用 `10s` 超时机制。

### 新增

- **学业仪表盘**：考试倒计时与 `GPA` 统计。
- **平移气泡**：随页面自然滑动。

### 修复

- **学期推导校准**：修复无效学期。
''';

      final releases = parseChangelog(mockMarkdown);
      expect(releases.length, 1);

      final release = releases.first;
      expect(release.version, '1.5.0');
      expect(release.date, '2026-11-05');
      expect(release.description.contains('\n'), isTrue);
      expect(release.description, contains('核心亮点速览'));

      expect(release.sections.length, 2);
      expect(release.sections[0].title, '新增');
      expect(release.sections[0].items.length, 2);
      expect(release.sections[1].title, '修复');
      expect(release.sections[1].items.length, 1);
    });
  });

  group('ChangelogPage 界面、排版与性能测试', () {
    setUp(() {
      ChangelogPage.resetCache();
    });

    tearDown(() {
      ChangelogPage.resetCache();
    });

    testWidgets('支持直接传入 initialReleases 零延迟渲染首帧与全套精致排版', (tester) async {
      const mockReleases = [
        ReleaseLog(
          version: '1.5.0',
          date: '2026-11-05',
          description: '**核心亮点速览**：\n1. 首帧即时呈现',
          sections: [
            LogSection(title: '新增', items: ['即时首帧渲染与 `GPA` 统计']),
            LogSection(title: '修复', items: ['修正常规问题']),
          ],
        ),
      ];

      await tester.pumpWidget(
        const MaterialApp(home: ChangelogPage(initialReleases: mockReleases)),
      );

      // 第 0 帧直接呈现内容，不展示加载转圈
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('v1.5.0'), findsOneWidget);
      expect(find.text('2026-11-05'), findsOneWidget);
      expect(find.textContaining('核心亮点速览'), findsOneWidget);
      expect(find.textContaining('即时首帧渲染'), findsOneWidget);

      // 验证分类胶囊徽章与图标
      expect(find.text('新增'), findsOneWidget);
      expect(find.text('修复'), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
      expect(find.byIcon(Icons.build_circle_outlined), findsOneWidget);

      // 验证富文本加粗与代码渲染
      final richTexts = tester.widgetList<RichText>(find.byType(RichText));
      bool foundBold = false;
      bool foundCode = false;

      void inspectSpan(InlineSpan span) {
        if (span is TextSpan) {
          if (span.style?.fontWeight == FontWeight.bold &&
              span.text?.contains('核心亮点速览') == true) {
            foundBold = true;
          }
          if (span.style?.fontFamily == 'monospace' && span.text == 'GPA') {
            foundCode = true;
          }
          if (span.children != null) {
            for (final child in span.children!) {
              inspectSpan(child);
            }
          }
        }
      }

      for (final rt in richTexts) {
        inspectSpan(rt.text);
      }

      expect(foundBold, isTrue);
      expect(foundCode, isTrue);
    });

    testWidgets('当前版本卡片统一零阴影纯白卡片主题、主色边框与专属胶囊徽章', (tester) async {
      final currentVer = appVersion != '-' ? appVersion : '1.5.0';
      final mockReleases = [
        ReleaseLog(
          version: currentVer,
          date: '2026-11-05',
          description: '**核心亮点速览**：\n1. 测试亮点说明',
          sections: const [
            LogSection(title: '优化', items: ['优化测试条目']),
          ],
        ),
      ];

      final theme = buildLightTheme();
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: ChangelogPage(initialReleases: mockReleases),
        ),
      );

      final card = tester.widget<Card>(find.byType(Card).first);
      expect(card.elevation, isNull);
      expect(card.color, isNull);
      final shape = card.shape as RoundedRectangleBorder;
      final expectsCurrent = appVersion != '-';
      expect(shape.side.width, expectsCurrent ? 1.5 : 1.0);
      if (expectsCurrent) {
        expect(shape.side.color, theme.colorScheme.primary);
        expect(find.text('当前版本'), findsOneWidget);
      }
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(Card).first,
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.elevation, 0);
      expect(material.color, theme.colorScheme.surfaceContainerLowest);
      expect(find.text('v$currentVer'), findsOneWidget);
      expect(find.textContaining('核心亮点速览'), findsOneWidget);
    });

    testWidgets('ChangelogPage.open 支持即时读取真实资产并导航', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => ChangelogPage.open(context),
                child: const Text('打开更新日志'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('打开更新日志'));
      // 立即开始路由入场，推进 50ms 即已在过渡帧中挂载新页面，无需阻塞至资源解析结束才 push
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('更新日志'), findsOneWidget);

      await tester.pumpAndSettle();

      expect(find.text('更新日志'), findsOneWidget);
      // 验证真实 CHANGELOG.md 内容已渲染
      expect(find.textContaining('1.5.0'), findsAtLeastNWidgets(1));
    });

    testWidgets('分段加载首帧仅构建首批版本卡片并在后续帧渐进补齐', (tester) async {
      final manyReleases = <ReleaseLog>[
        for (var v = 8; v >= 1; v--)
          ReleaseLog(
            version: '$v.0.0',
            date: '2026-11-0$v',
            description: '版本 **$v** 核心更新摘要',
            sections: const <LogSection>[
              LogSection(title: '优化', items: <String>['性能优化条目']),
            ],
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(home: ChangelogPage(initialReleases: manyReleases)),
      );

      // 第 0 帧仅渲染首屏批次（initialBatchSize = 2），避免一口气构建全部卡片引发卡顿
      expect(find.text('v8.0.0'), findsOneWidget);
      expect(find.text('v7.0.0'), findsOneWidget);
      expect(find.text('v6.0.0'), findsNothing);
      expect(find.text('v5.0.0'), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      // 下一帧渐进追加第二批，第 3 张卡片随即进入可视/预加载区
      await tester.pump();
      expect(find.text('v6.0.0'), findsOneWidget);

      // 全部批次完成后底部加载指示器自动消失，向下滚动可看到后续全部版本
      await tester.pumpAndSettle();
      expect(find.byType(CircularProgressIndicator), findsNothing);
      await tester.scrollUntilVisible(
        find.text('v5.0.0'),
        200,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('v5.0.0'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('v1.0.0'),
        300,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('v1.0.0'), findsOneWidget);
    });
  });
}
