import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/changelog_page.dart';
import 'package:qustschedule/src/app_version.dart';
import 'package:qustschedule/src/formatted_text.dart';
import 'package:qustschedule/theme/app_theme.dart';
import 'package:qustschedule/widgets/formatted_text_span.dart';

void main() {
  group('buildFormattedTextSpan 单元测试', () {
    testWidgets('支持空文本、baseStyle、加粗、行内代码与未闭合标记容错', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              // 空文本
              final empty = buildFormattedTextSpan(context, '');
              expect(empty.text, '');
              expect(empty.children, isNull);

              // 纯文本继承 baseStyle
              const baseStyle = TextStyle(fontSize: 14, color: Colors.blue);
              final plain = buildFormattedTextSpan(
                context,
                '普通文本毫无标记',
                baseStyle: baseStyle,
              );
              expect(plain.text, '普通文本毫无标记');
              expect(plain.style, baseStyle);
              expect(plain.children, isNull);

              // **加粗**
              final boldSpan = buildFormattedTextSpan(context, '这是**加粗内容**测试');
              expect(boldSpan.children!.length, 3);
              expect((boldSpan.children![0] as TextSpan).text, '这是');
              expect((boldSpan.children![0] as TextSpan).style, isNull);
              expect((boldSpan.children![1] as TextSpan).text, '加粗内容');
              expect(
                (boldSpan.children![1] as TextSpan).style?.fontWeight,
                FontWeight.bold,
              );
              expect((boldSpan.children![2] as TextSpan).text, '测试');
              expect((boldSpan.children![2] as TextSpan).style, isNull);

              // `行内代码`
              final codeSpan = buildFormattedTextSpan(
                context,
                '调用 `git status` 命令',
              );
              expect(codeSpan.children!.length, 3);
              final codePart = codeSpan.children![1] as TextSpan;
              expect(codePart.text, 'git status');
              expect(codePart.style?.fontFamily, 'monospace');
              expect(codePart.style?.fontWeight, FontWeight.w600);

              // 混合与未闭合容错
              final mixed = buildFormattedTextSpan(
                context,
                '混合 **加粗** 与 `代码` 还有单个 * 和 ` 未闭合',
              );
              expect(mixed.children!.length, 5);
              expect((mixed.children![1] as TextSpan).text, '加粗');
              expect(
                (mixed.children![1] as TextSpan).style?.fontWeight,
                FontWeight.bold,
              );
              expect((mixed.children![3] as TextSpan).text, '代码');
              expect(
                (mixed.children![3] as TextSpan).style?.fontFamily,
                'monospace',
              );
              expect((mixed.children![4] as TextSpan).text, ' 还有单个 * 和 ` 未闭合');
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
      expect(release.sections[0].itemSegments, isNotNull);
      expect(release.sections[0].itemSegments!.length, 2);
      expect(release.descriptionSegments, isNotNull);
      expect(release.sections[1].title, '修复');
      expect(release.sections[1].items.length, 1);
    });

    test('parseChangelogBytes 可在真实后台 Isolate 中解码并预拆行内加粗/代码片段', () async {
      const mockMarkdown = '''
## [2.0.0] - 2026-11-22

**并行加载**：后台 `Isolate` 预解析无 UI 阻塞。

### 优化

- 去除 `Clip.antiAlias` 与手工分页补丁，**原生懒构建**更轻量。
''';
      final bytes = Uint8List.fromList(utf8.encode(mockMarkdown));
      final releases = await Isolate.run(() => parseChangelogBytes(bytes));

      expect(releases, hasLength(1));
      final release = releases.first;
      expect(release.version, '2.0.0');
      expect(release.descriptionSegments, isNotNull);
      expect(
        release.descriptionSegments!.any(
          (s) => s.kind == FormattedSegmentKind.bold && s.text == '并行加载',
        ),
        isTrue,
      );
      expect(
        release.descriptionSegments!.any(
          (s) => s.kind == FormattedSegmentKind.code && s.text == 'Isolate',
        ),
        isTrue,
      );
      expect(release.sections.single.itemSegments, isNotNull);
      expect(
        release.sections.single.itemSegments!.single.any(
          (s) =>
              s.kind == FormattedSegmentKind.code && s.text == 'Clip.antiAlias',
        ),
        isTrue,
      );
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
      final latestVersion = parseChangelog(
        await rootBundle.loadString('CHANGELOG.md'),
      ).first.version;
      expect(find.text('v$latestVersion'), findsOneWidget);
    });

    testWidgets('原生 ListView.separated 按视口懒构建大量版本卡片、无伪加载底栏且关闭无意义卡片裁剪', (
      tester,
    ) async {
      final manyReleases = <ReleaseLog>[
        for (var v = 20; v >= 1; v--)
          ReleaseLog(
            version: '$v.0.0',
            date: '2026-11-${v.toString().padLeft(2, '0')}',
            description: '版本 **$v** 核心更新摘要',
            sections: const <LogSection>[
              LogSection(title: '优化', items: <String>['性能优化条目一', '性能优化条目二']),
            ],
          ),
      ];

      await tester.pumpWidget(
        MaterialApp(home: ChangelogPage(initialReleases: manyReleases)),
      );

      // 已落稳路由首帧即渲染视口内卡片，无人工分页底栏转圈，远端离屏卡片不会提前建树
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('v20.0.0'), findsOneWidget);
      expect(find.text('v1.0.0'), findsNothing);

      final firstCard = tester.widget<Card>(find.byType(Card).first);
      expect(firstCard.clipBehavior, Clip.none);

      // 向下滚动时按需懒构建后续全部版本
      await tester.scrollUntilVisible(
        find.text('v1.0.0'),
        400,
        scrollable: find.byType(Scrollable),
      );
      expect(find.text('v1.0.0'), findsOneWidget);
    });
  });
}
