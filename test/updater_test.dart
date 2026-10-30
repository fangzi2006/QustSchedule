import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/update_dialog.dart';
import 'package:qustschedule/pages/update_settings_dialog.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/updater/update_models.dart';
import 'package:qustschedule/src/updater/update_service.dart';
import 'package:qustschedule/src/updater/version_comparator.dart';

void main() {
  group('版本号比对 (Version Comparator)', () {
    test('标准语义化版本号大小比对', () {
      expect(isVersionNewer('1.2.3', '1.2.2'), isTrue);
      expect(isVersionNewer('1.3.0', '1.2.9'), isTrue);
      expect(isVersionNewer('2.0.0', '1.9.9'), isTrue);
      expect(isVersionNewer('1.2.2', '1.2.2'), isFalse);
      expect(isVersionNewer('1.2.1', '1.2.2'), isFalse);
    });

    test('带 v 前缀与空格清洗', () {
      expect(isVersionNewer('v1.2.3', '1.2.2'), isTrue);
      expect(isVersionNewer('V1.2.3', 'v1.2.2'), isTrue);
      expect(isVersionNewer('  v1.2.3  ', '1.2.3'), isFalse);
    });

    test('带构建号 (+build)', () {
      expect(isVersionNewer('1.2.2+32', '1.2.2+31'), isTrue);
      expect(isVersionNewer('1.2.3+1', '1.2.2+35'), isTrue);
      expect(isVersionNewer('1.2.2', '1.2.2+31'), isFalse);
    });

    test('不同长度版本号 (如 1.2 vs 1.2.1)', () {
      expect(isVersionNewer('1.2.1', '1.2'), isTrue);
      expect(isVersionNewer('1.3', '1.2.5'), isTrue);
      expect(isVersionNewer('1.2.0', '1.2'), isFalse);
    });
  });

  group('加速代理 URL 拼装 (Proxy URL builder)', () {
    test('直连代理为空时原样返回', () {
      const raw =
          'https://api.github.com/repos/fangzi2006/QustSchedule/releases/latest';
      expect(UpdateService.buildProxiedUrl(raw, ''), equals(raw));
      expect(UpdateService.buildProxiedUrl(raw, '   '), equals(raw));
    });

    test('拼接代理前缀并清洗多余斜杠与协议头', () {
      const raw =
          'https://github.com/fangzi2006/QustSchedule/releases/download/v1.2.2/app.apk';
      expect(
        UpdateService.buildProxiedUrl(raw, 'https://gh-proxy.com'),
        equals('https://gh-proxy.com/$raw'),
      );
      expect(
        UpdateService.buildProxiedUrl(raw, 'https://gh-proxy.com/'),
        equals('https://gh-proxy.com/$raw'),
      );
      expect(
        UpdateService.buildProxiedUrl(raw, 'gh-proxy.com'),
        equals('https://gh-proxy.com/$raw'),
      );
    });
  });

  group('产物格式化与架构匹配 (Asset Matching)', () {
    test('人类可读大小格式化', () {
      const a1 = ReleaseAsset(
        name: 'a',
        downloadUrl: '',
        size: 1024,
        contentType: '',
      );
      expect(a1.formattedSize, equals('1.0 KB'));

      const a2 = ReleaseAsset(
        name: 'b',
        downloadUrl: '',
        size: 18 * 1024 * 1024 + 512 * 1024,
        contentType: '',
      );
      expect(a2.formattedSize, equals('18.5 MB'));
    });

    test('下载进度百分比与速度计算', () {
      const p = DownloadProgress(
        receivedBytes: 5 * 1024 * 1024,
        totalBytes: 10 * 1024 * 1024,
        speedBytesPerSec: 2.5 * 1024 * 1024,
      );
      expect(p.percentage, equals(50));
      expect(p.formattedSpeed, equals('2.5 MB/s'));
      expect(p.formattedReceived, equals('5.0 MB'));
      expect(p.formattedTotal, equals('10.0 MB'));
    });
  });

  group('更新偏好设置 (Preferences & AppModel)', () {
    test('默认配置生效', () {
      final prefs = Preferences.inMemory();
      expect(prefs.updateProxyUrl, equals('https://gh-proxy.com'));
      expect(prefs.autoCheckUpdate, isTrue);
      expect(prefs.ignoredUpdateVersion, isEmpty);
    });

    test('修改偏好并触发通知', () async {
      final model = AppModel(preferences: Preferences.inMemory());
      expect(model.updateProxyUrl, equals('https://gh-proxy.com'));

      await model.setUpdateProxyUrl('https://ghproxy.net');
      expect(model.updateProxyUrl, equals('https://ghproxy.net'));

      await model.setAutoCheckUpdate(false);
      expect(model.autoCheckUpdate, isFalse);

      await model.setIgnoredUpdateVersion('1.2.3');
      expect(model.ignoredUpdateVersion, equals('1.2.3'));
    });
  });

  group('更新界面交互 (Update UI Widgets)', () {
    testWidgets('更新对话框渲染版本、大小与日志', (tester) async {
      const asset = ReleaseAsset(
        name: 'QustSchedule_v1.2.3-arm64-v8a.apk',
        downloadUrl: 'https://example.com/app.apk',
        size: 19 * 1024 * 1024,
        contentType: 'application/vnd.android.package-archive',
      );

      const release = ReleaseInfo(
        tagName: 'v1.2.3',
        version: '1.2.3',
        name: '青科课表通 v1.2.3',
        body: '### 碎碎念\n* 测试更新日志项',
        publishedAt: null,
        assets: [asset],
        htmlUrl:
            'https://github.com/fangzi2006/QustSchedule/releases/tag/v1.2.3',
      );

      const updateResult = UpdateCheckResult(
        status: UpdateStatus.hasUpdate,
        release: release,
        targetAsset: asset,
        currentArchName: 'Android (arm64-v8a)',
      );

      bool ignored = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUpdateDialog(
                context,
                updateResult: updateResult,
                proxyPrefix: 'https://gh-proxy.com',
                onIgnore: () => ignored = true,
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 v1.2.3'), findsOneWidget);
      expect(find.textContaining('19.0 MB'), findsOneWidget);
      expect(find.textContaining('Android (arm64-v8a)'), findsOneWidget);
      expect(find.textContaining('测试更新日志项'), findsOneWidget);

      expect(find.text('忽略此版'), findsOneWidget);
      expect(find.text('浏览器下载'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);

      await tester.tap(find.text('忽略此版'));
      await tester.pumpAndSettle();
      expect(ignored, isTrue);
    });

    testWidgets('更新设置弹窗支持切换代理', (tester) async {
      final model = AppModel(preferences: Preferences.inMemory());

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUpdateSettingsDialog(context, model: model),
              child: const Text('Settings'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Settings'));
      await tester.pumpAndSettle();

      expect(find.text('软件更新设置'), findsOneWidget);
      expect(find.text('启动时自动检查更新'), findsOneWidget);
      expect(find.text('gh-proxy.com (推荐)'), findsOneWidget);
      expect(find.text('直连 (GitHub 官方)'), findsOneWidget);

      // 滚动并切换到直连
      await tester.ensureVisible(find.text('直连 (GitHub 官方)'));
      await tester.tap(find.text('直连 (GitHub 官方)'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('保存'));
      await tester.pumpAndSettle();

      expect(model.updateProxyUrl, isEmpty);
    });
  });
}
