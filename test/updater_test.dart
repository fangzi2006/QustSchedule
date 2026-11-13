import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/about_page.dart';
import 'package:qustschedule/pages/changelog_page.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/update_dialog.dart';
import 'package:qustschedule/pages/update_proxy_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/updater/update_flow_controller.dart';
import 'package:qustschedule/src/updater/update_models.dart';
import 'package:qustschedule/src/updater/update_service.dart';
import 'package:qustschedule/src/updater/version_comparator.dart';

import 'support/fake_backend.dart';

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

  group('Release 日志清洗 (Release Notes Cleaning)', () {
    test('过滤 GitHub CI 自动拼接的下载表格与比较链接', () {
      const raw = '''
### 新增
- 增加关于页面与 FlClash 风格检查更新
- 增加自定义加速代理配置

### 修复
- 修复下载断流重试问题

## 📥 根据你的操作系统下载

| OS | 下载 | 使用加速代理下载 |
|:--:|:--|:--|
| **安卓** | [![APK ARMv8](https://img.shields.io/badge/APK-ARMv8-3DDC84)](https://example.com/app.apk) |
| **Windows** | [![Setup x64](https://img.shields.io/badge/Setup-x64-0078D6)](https://example.com/setup.exe) |

所有变更列表：[ChangeLog](https://github.com/fangzi2006/QustSchedule/compare/v1.2.2...v1.2.3)
''';

      final cleaned = ReleaseInfo.cleanReleaseBody(raw);
      expect(cleaned, contains('### 新增'));
      expect(cleaned, contains('- 增加关于页面与 FlClash 风格检查更新'));
      expect(cleaned, contains('### 修复'));
      expect(cleaned, contains('- 修复下载断流重试问题'));

      // 验证截断并过滤了 CI 自动拼接内容
      expect(cleaned, isNot(contains('根据你的操作系统下载')));
      expect(cleaned, isNot(contains('| OS |')));
      expect(cleaned, isNot(contains('|:--:|')));
      expect(cleaned, isNot(contains('img.shields.io')));
      expect(cleaned, isNot(contains('所有变更列表：')));
    });

    test('空说明或纯空白返回空字符串', () {
      expect(ReleaseInfo.cleanReleaseBody(''), isEmpty);
      expect(ReleaseInfo.cleanReleaseBody('   \n  \r\n  '), isEmpty);
    });
  });

  group('安装包历史文件自动清理 (Clean Old Update Files)', () {
    test('自动静默清理历史旧版本安装包与未完成的临时分片文件', () async {
      final tempDir = Directory.systemTemp.createTempSync('qust_update_test_');
      try {
        final oldApk = File(
          '${tempDir.path}/QustSchedule_v1.0.0-arm64-v8a.apk',
        );
        await oldApk.writeAsString('test-old-content');

        final sameApk = File(
          '${tempDir.path}/QustSchedule_v1.2.2-arm64-v8a.apk',
        );
        await sameApk.writeAsString('test-same-content');

        final newerApk = File(
          '${tempDir.path}/QustSchedule_v9.9.9-arm64-v8a.apk',
        );
        await newerApk.writeAsString('test-newer-content');

        final partFile = File('${tempDir.path}/QustSchedule_v1.2.3.apk.part0');
        await partFile.writeAsString('test-part');

        final unrelated = File('${tempDir.path}/other_app.apk');
        await unrelated.writeAsString('unrelated');

        // 当前运行版本为 1.2.2
        final deleted = await UpdateService.cleanOldUpdateFiles(
          currentVersion: '1.2.2',
          targetDirectory: tempDir,
        );
        expect(deleted, equals(3));

        // 1.0.0 与 1.2.2 均应当被删除
        expect(await oldApk.exists(), isFalse);
        expect(await sameApk.exists(), isFalse);
        // .part 切片临时文件应当被删除
        expect(await partFile.exists(), isFalse);
        // 比当前版本新的安装包应当保留
        expect(await newerApk.exists(), isTrue);
        // 与更新无关的其他文件保留
        expect(await unrelated.exists(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
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

    test('Windows 架构产物智能匹配（安装版 vs 便携版）', () {
      const setupAsset = ReleaseAsset(
        name: 'QustSchedule_v1.3.0-windows-x64-setup.exe',
        downloadUrl: 'https://example.com/setup.exe',
        size: 20 * 1024 * 1024,
        contentType: '',
      );
      const zipAsset = ReleaseAsset(
        name: 'QustSchedule_v1.3.0-windows-x64.zip',
        downloadUrl: 'https://example.com/portable.zip',
        size: 22 * 1024 * 1024,
        contentType: '',
      );
      final assets = [setupAsset, zipAsset];

      // 便携版应优先匹配 .zip 绿色包
      final portableTarget = UpdateService.findTargetAsset(
        assets,
        isPortable: true,
      );
      expect(portableTarget, equals(zipAsset));

      // 安装版应优先匹配 setup.exe 安装向导
      final installerTarget = UpdateService.findTargetAsset(
        assets,
        isPortable: false,
      );
      expect(installerTarget, equals(setupAsset));
    });
  });

  group('更新偏好设置与代理增删 (Preferences & AppModel)', () {
    test('默认配置生效（仅默认加速地址与直连）', () {
      final prefs = Preferences.inMemory();
      expect(prefs.selectedUpdateProxy, equals('https://gh-proxy.org'));
      expect(prefs.customUpdateProxies, isEmpty);
      expect(
        prefs.allUpdateProxies,
        equals([
          'https://gh-proxy.org',
          'https://axisnow.gh-proxy.org',
          'https://gh-proxy.com',
        ]),
      );
      expect(prefs.autoCheckUpdate, isTrue);
    });

    test('新增、删除自定义代理并持久化', () async {
      final model = AppModel(preferences: Preferences.inMemory());
      expect(model.customUpdateProxies, isEmpty);

      int prefsNotified = 0;
      model.prefsNotifier.addListener(() => prefsNotified++);

      // 添加自定义代理
      await model.addCustomUpdateProxy('https://ghproxy.net');
      expect(model.customUpdateProxies, equals(['https://ghproxy.net']));
      expect(
        model.allUpdateProxies,
        equals([
          'https://gh-proxy.org',
          'https://axisnow.gh-proxy.org',
          'https://gh-proxy.com',
          'https://ghproxy.net',
        ]),
      );
      expect(prefsNotified, greaterThan(0));

      // 切换当前选中代理
      await model.setSelectedUpdateProxy('https://ghproxy.net');
      expect(model.selectedUpdateProxy, equals('https://ghproxy.net'));

      // 删除自定义代理
      await model.removeCustomUpdateProxy('https://ghproxy.net');
      expect(model.customUpdateProxies, isEmpty);
      expect(
        model.allUpdateProxies,
        equals([
          'https://gh-proxy.org',
          'https://axisnow.gh-proxy.org',
          'https://gh-proxy.com',
        ]),
      );

      // 其他偏好设置
      await model.setAutoCheckUpdate(false);
      expect(model.autoCheckUpdate, isFalse);
    });

    test('历史旧配置中的 ignoredUpdateVersion 字段在反序列化时被安全忽略与丢弃', () {
      final decoded = Preferences.decode('{"ignoredUpdateVersion": "1.3.0"}');
      expect(decoded.autoCheckUpdate, isTrue);
    });

    test('直连官方空字符串配置在反序列化后依然保持为空', () {
      final decoded = Preferences.decode('{"selectedUpdateProxy": ""}');
      expect(decoded.selectedUpdateProxy, isEmpty);
    });
  });

  group('更新界面交互 (Update UI Widgets)', () {
    testWidgets('更新对话框渲染版本、大小与日志，且不包含历史版本链接', (tester) async {
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

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUpdateDialog(
                context,
                updateResult: updateResult,
                proxyPrefix: 'https://gh-proxy.com',
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

      expect(find.text('稍后再说'), findsNothing);
      expect(find.byTooltip('稍后再说'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('浏览器下载'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);

      // 验证「浏览器下载」靠左、「立即更新」靠右，且两按钮之间有明显间距
      final browserRect = tester.getRect(
        find.widgetWithText(OutlinedButton, '浏览器下载'),
      );
      final updateRect = tester.getRect(
        find.widgetWithText(FilledButton, '立即更新'),
      );
      expect(browserRect.right, lessThan(updateRect.left));

      // 验证未附带「查看全部历史版本」与已废弃的「忽略此版」
      expect(find.textContaining('历史版本'), findsNothing);
      expect(find.text('忽略此版'), findsNothing);

      await tester.tap(find.byTooltip('稍后再说'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.2.3'), findsNothing);
    });

    testWidgets('极窄屏与超大字体下更新弹窗操作按钮自动换行不溢出', (tester) async {
      tester.view.physicalSize = const Size(300, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      const asset = ReleaseAsset(
        name: 'qustschedule-arm64-v8a-release.apk',
        downloadUrl: 'https://example.com/app.apk',
        size: 1024 * 1024 * 10,
        contentType: 'application/vnd.android.package-archive',
      );
      const release = ReleaseInfo(
        tagName: 'v1.2.3',
        version: '1.2.3',
        name: '青科课表通 v1.2.3',
        body: '测试更新日志',
        publishedAt: null,
        assets: [asset],
        htmlUrl: 'https://example.com/release',
      );
      const updateResult = UpdateCheckResult(
        status: UpdateStatus.hasUpdate,
        release: release,
        targetAsset: asset,
        currentArchName: 'Android (arm64-v8a)',
      );

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUpdateDialog(
                context,
                updateResult: updateResult,
                proxyPrefix: 'https://gh-proxy.com',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      final browserRect = tester.getRect(
        find.widgetWithText(OutlinedButton, '浏览器下载'),
      );
      final updateRect = tester.getRect(
        find.widgetWithText(FilledButton, '立即更新'),
      );
      expect(browserRect.bottom, lessThanOrEqualTo(updateRect.top));
    });

    testWidgets('更新对话框无对应架构产物时展示友好提示', (tester) async {
      const release = ReleaseInfo(
        tagName: 'v1.2.3',
        version: '1.2.3',
        name: '青科课表通 v1.2.3',
        body: '更新说明',
        publishedAt: null,
        assets: [],
        htmlUrl: 'https://example.com/release',
      );

      const updateResult = UpdateCheckResult(
        status: UpdateStatus.hasUpdate,
        release: release,
        targetAsset: null,
        currentArchName: 'Windows (x64)',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUpdateDialog(
                context,
                updateResult: updateResult,
                proxyPrefix: '',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('发现新版本 v1.2.3'), findsOneWidget);
      expect(find.textContaining('暂未匹配到直接升级安装包'), findsOneWidget);
      expect(find.text('前往 Release 页面'), findsOneWidget);
      expect(find.text('知道了'), findsOneWidget);

      await tester.tap(find.text('知道了'));
      await tester.pumpAndSettle();
    });

    testWidgets('下载进度弹窗生命周期安全，取消后关闭弹窗', (tester) async {
      const asset = ReleaseAsset(
        name: 'test_app.apk',
        downloadUrl: 'https://example.com/test_app.apk',
        size: 10 * 1024 * 1024,
        contentType: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showDownloadProgressDialog(
                context,
                asset: asset,
                selectedProxy: 'https://gh-proxy.com',
              ),
              child: const Text('Download'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Download'));
      await tester.pump(); // 构建首帧，启动下载

      expect(find.text('正在下载更新'), findsOneWidget);
      expect(find.text('test_app.apk'), findsOneWidget);
      expect(find.text('取消下载'), findsOneWidget);

      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();

      expect(find.text('正在下载更新'), findsNothing);
    });

    testWidgets('更新代理管理页支持选择节点与添加代理', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final model = AppModel(preferences: Preferences.inMemory());

      await tester.pumpWidget(MaterialApp(home: UpdateProxyPage(model: model)));

      expect(find.text('更新代理设置'), findsOneWidget);
      expect(find.text('主加速节点(默认推荐)'), findsOneWidget);
      expect(find.text('副加速节点'), findsOneWidget);
      expect(find.text('加速主站（最稳定但是部分网络环境下速度较慢）'), findsOneWidget);
      expect(find.text('直连'), findsOneWidget);
      expect(find.text('多层自动回退机制'), findsOneWidget);

      // 切换至直连
      await tester.tap(find.text('直连'));
      await tester.pumpAndSettle();
      expect(model.selectedUpdateProxy, isEmpty);

      // 打开添加代理弹窗并输入
      await tester.tap(find.text('新增自定义代理'));
      await tester.pumpAndSettle();

      expect(find.text('新增加速代理'), findsOneWidget);
      await tester.enterText(
        find.byType(TextField),
        'https://mirror.ghproxy.com',
      );
      await tester.tap(find.text('添加'));
      await tester.pumpAndSettle();

      expect(model.customUpdateProxies, contains('https://mirror.ghproxy.com'));
      expect(find.text('https://mirror.ghproxy.com'), findsOneWidget);
    });

    testWidgets('关于页面呈现 FlClash 风格头部与各项入口', (tester) async {
      final model = AppModel(preferences: Preferences.inMemory());

      await tester.pumpWidget(MaterialApp(home: AboutPage(model: model)));

      expect(find.text('关于青科课表通'), findsOneWidget);
      expect(find.text('青科课表通'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);

      // 验证下方各项列表入口
      expect(find.text('更新日志'), findsOneWidget);
      expect(find.text('更新代理设置'), findsOneWidget);
      expect(find.text('调试信息'), findsOneWidget);
      expect(find.text('开源许可'), findsOneWidget);
      expect(find.text('开源协议'), findsOneWidget);
      expect(find.text('项目主页与源码'), findsOneWidget);
    });

    testWidgets('更新对话框自动过滤 CI 下载表格并美化展示 Markdown 标签', (tester) async {
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
        body: '''
### 新增
- 增加关于页面与**全新**检查更新

### 优化
- 提升下载速度

## 📥 根据你的操作系统下载
| OS | 下载 | 使用加速代理下载 |
|:--:|:--|:--|
| **安卓** | [下载](https://example.com) |
''',
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

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => showUpdateDialog(
                context,
                updateResult: updateResult,
                proxyPrefix: 'https://gh-proxy.com',
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();

      expect(find.text('新增'), findsOneWidget);
      expect(find.text('优化'), findsOneWidget);
      expect(find.textContaining('增加关于页面与全新检查更新'), findsOneWidget);
      expect(find.textContaining('提升下载速度'), findsOneWidget);

      // 绝不包含 CI 拼接的操作系统下载表格源码
      expect(find.textContaining('根据你的操作系统下载'), findsNothing);
      expect(find.textContaining('| OS |'), findsNothing);
    });

    testWidgets('更新日志页面能够正常构建', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: ChangelogPage()));

      expect(find.text('更新日志'), findsOneWidget);
    });
  });

  group('自动更新重试机制 (UpdateService.checkForUpdatesWithRetry)', () {
    test('首次检测成功不触发重试', () async {
      final service = _MockRetryUpdateService(
        results: const [UpdateCheckResult(status: UpdateStatus.hasUpdate)],
      );
      int delayCalls = 0;
      final result = await service.checkForUpdatesWithRetry(
        currentVersion: '1.0.0',
        selectedProxy: '',
        delayFn: (_) async => delayCalls++,
      );
      expect(result.status, UpdateStatus.hasUpdate);
      expect(service.calls, 1);
      expect(delayCalls, 0);
    });

    test('网络超时触发重试并在成功后返回', () async {
      final service = _MockRetryUpdateService(
        results: const [
          UpdateCheckResult(status: UpdateStatus.networkError),
          UpdateCheckResult(status: UpdateStatus.hasUpdate),
        ],
      );
      int delayCalls = 0;
      final result = await service.checkForUpdatesWithRetry(
        currentVersion: '1.0.0',
        selectedProxy: '',
        delayFn: (_) async => delayCalls++,
      );
      expect(result.status, UpdateStatus.hasUpdate);
      expect(service.calls, 2);
      expect(delayCalls, 1);
    });

    test('持续网络错误达到最大重试次数后返回错误', () async {
      final service = _MockRetryUpdateService(
        results: const [
          UpdateCheckResult(status: UpdateStatus.networkError),
          UpdateCheckResult(status: UpdateStatus.networkError),
          UpdateCheckResult(status: UpdateStatus.networkError),
        ],
      );
      int delayCalls = 0;
      final result = await service.checkForUpdatesWithRetry(
        currentVersion: '1.0.0',
        selectedProxy: '',
        maxRetries: 2,
        delayFn: (_) async => delayCalls++,
      );
      expect(result.status, UpdateStatus.networkError);
      expect(service.calls, 3);
      expect(delayCalls, 2);
    });
  });

  group('统一更新流程与后台下载 (UpdateFlowController & 课表顶栏)', () {
    testWidgets('单弹窗全程禁止点空白关闭，后台下载收起后不中断且可重开恢复，取消下载回到预览', (tester) async {
      final service = _MockDownloadUpdateService();
      final tempDir = Directory.systemTemp.createTempSync('update_flow_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final fakeApk = File('${tempDir.path}/app.apk')..writeAsStringSync('apk');

      final controller = UpdateFlowController(
        updateService: service,
        canInstallCheck: () async => true,
        installRunner: (_) async {},
      );
      addTearDown(controller.dispose);

      const asset = ReleaseAsset(
        name: 'qustschedule-setup.exe',
        downloadUrl: 'https://example.com/setup.exe',
        size: 1024 * 1024 * 12,
        contentType: 'application/octet-stream',
      );
      const release = ReleaseInfo(
        tagName: 'v1.6.0',
        version: '1.6.0',
        name: 'v1.6.0',
        body: '新功能',
        publishedAt: null,
        assets: [asset],
        htmlUrl: 'https://example.com/release',
      );
      const result = UpdateCheckResult(
        status: UpdateStatus.hasUpdate,
        release: release,
        targetAsset: asset,
        currentArchName: 'Windows (x64)',
      );
      controller.setAvailableUpdate(
        result: result,
        selectedProxy: 'https://gh-proxy.com',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () =>
                    showUpdateDialog(context, controller: controller),
                child: const Text('OpenUpdate'),
              ),
            ),
          ),
        ),
      );

      // 1. 打开弹窗，点击弹窗外空白区域不得关闭弹窗
      await tester.tap(find.text('OpenUpdate'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.6.0'), findsOneWidget);

      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.6.0'), findsOneWidget);

      // 2. 点击「立即更新」，在同一弹窗内切换为「正在下载更新」
      await tester.tap(find.text('立即更新'));
      await tester.pump();
      expect(find.text('正在下载更新'), findsOneWidget);
      expect(controller.stage, UpdateFlowStage.downloading);

      // 3. 点击「后台下载」，关闭弹窗但下载任务不取消
      await tester.tap(find.text('后台下载'));
      await tester.pumpAndSettle();
      expect(find.text('正在下载更新'), findsNothing);
      expect(controller.stage, UpdateFlowStage.downloading);
      expect(service.lastToken?.isCancelled, isFalse);

      // 4. 重开弹窗直接恢复到下载进度并更新进度条
      await tester.tap(find.text('OpenUpdate'));
      await tester.pump();
      expect(find.text('正在下载更新'), findsOneWidget);
      service.emitProgress(500, 1000);
      await tester.pump();
      expect(find.text('50%'), findsOneWidget);

      // 5. 点击「取消下载」中止任务并回到「发现新版本」预览页
      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();
      expect(service.lastToken?.isCancelled, isTrue);
      expect(controller.stage, UpdateFlowStage.available);
      expect(find.text('发现新版本 v1.6.0'), findsOneWidget);

      // 6. 再次启动下载并完成，进入「下载完成」阶段
      await tester.tap(find.text('立即更新'));
      await tester.pump();
      expect(controller.stage, UpdateFlowStage.downloading);
      service.completeSuccess(fakeApk);
      await tester.pumpAndSettle();
      expect(controller.stage, UpdateFlowStage.readyToInstall);
      expect(find.text('下载完成'), findsOneWidget);
    });

    testWidgets('下载失败后可点击「重试下载」恢复成功', (tester) async {
      final service = _MockDownloadUpdateService();
      final tempDir = Directory.systemTemp.createTempSync('update_retry_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final fakeApk = File('${tempDir.path}/app.apk')..writeAsStringSync('apk');

      final controller = UpdateFlowController(
        updateService: service,
        canInstallCheck: () async => true,
        installRunner: (_) async {},
      );
      addTearDown(controller.dispose);

      const asset = ReleaseAsset(
        name: 'app.apk',
        downloadUrl: 'https://example.com/app.apk',
        size: 1024,
        contentType: 'application/vnd.android.package-archive',
      );
      const release = ReleaseInfo(
        tagName: 'v1.6.0',
        version: '1.6.0',
        name: 'v1.6.0',
        body: '日志',
        publishedAt: null,
        assets: [asset],
        htmlUrl: '',
      );
      controller.setAvailableUpdate(
        result: const UpdateCheckResult(
          status: UpdateStatus.hasUpdate,
          release: release,
          targetAsset: asset,
        ),
        selectedProxy: '',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: ElevatedButton(
                onPressed: () =>
                    showUpdateDialog(context, controller: controller),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即更新'));
      await tester.pump();

      service.completeError(Exception('network timeout'));
      await tester.pumpAndSettle();
      expect(controller.stage, UpdateFlowStage.error);
      expect(find.text('下载出错'), findsOneWidget);
      expect(find.text('重试下载'), findsOneWidget);

      await tester.tap(find.text('重试下载'));
      await tester.pump();
      expect(controller.stage, UpdateFlowStage.downloading);
      service.completeSuccess(fakeApk);
      await tester.pumpAndSettle();
      expect(controller.stage, UpdateFlowStage.readyToInstall);
    });

    testWidgets('课表页顶栏更新入口随状态展示，且后台下载完成触发悬浮提示', (tester) async {
      final service = _MockDownloadUpdateService();
      final tempDir = Directory.systemTemp.createTempSync('update_bar_test');
      addTearDown(() => tempDir.deleteSync(recursive: true));
      final fakeApk = File('${tempDir.path}/app.apk')..writeAsStringSync('apk');

      final flow = UpdateFlowController(
        updateService: service,
        canInstallCheck: () async => true,
        installRunner: (_) async {},
      );
      final model = AppModel(
        preferences: Preferences.inMemory(),
        updateFlow: flow,
      );
      addTearDown(model.dispose);
      model.hydrateForTest(schedule: sampleSchedule('2026-2027-1'));

      await tester.pumpWidget(MaterialApp(home: HomeShell(model: model)));
      await tester.pump();

      const updateButtonKey = ValueKey<String>('schedule-update-button');
      expect(find.byKey(updateButtonKey), findsNothing);

      const asset = ReleaseAsset(
        name: 'app.apk',
        downloadUrl: 'https://example.com/app.apk',
        size: 1024,
        contentType: 'application/vnd.android.package-archive',
      );
      const release = ReleaseInfo(
        tagName: 'v1.6.0',
        version: '1.6.0',
        name: 'v1.6.0',
        body: '新版本说明',
        publishedAt: null,
        assets: [asset],
        htmlUrl: '',
      );
      flow.setAvailableUpdate(
        result: const UpdateCheckResult(
          status: UpdateStatus.hasUpdate,
          release: release,
          targetAsset: asset,
        ),
        selectedProxy: '',
      );
      await tester.pump();

      // 检测到新版本后图标立即常驻出现在「刷新课表」左侧
      expect(find.byKey(updateButtonKey), findsOneWidget);
      final updateRect = tester.getRect(find.byKey(updateButtonKey));
      final refreshRect = tester.getRect(
        find.widgetWithIcon(IconButton, Icons.refresh_rounded),
      );
      expect(updateRect.right, lessThanOrEqualTo(refreshRect.left));

      // 点击顶栏图标打开弹窗，启动下载并点击后台下载收起
      await tester.tap(find.byKey(updateButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即更新'));
      await tester.pump();
      await tester.tap(find.text('后台下载'));
      // 下载中顶栏存在不定进度条无限动画，不能用 pumpAndSettle
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('正在下载更新'), findsNothing);
      expect(find.byKey(updateButtonKey), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

      // 后台下载完成：弹窗未打开时通过 AppSnackBar 提醒并可点击安装
      service.completeSuccess(fakeApk);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(flow.stage, UpdateFlowStage.readyToInstall);
      expect(find.text('新版本 v1.6.0 下载完成'), findsOneWidget);
      expect(find.text('立即安装'), findsOneWidget);
      expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
    });
  });
}

class _MockDownloadUpdateService extends UpdateService {
  Completer<File>? _completer;
  void Function(DownloadProgress)? _onProgress;
  CancelToken? lastToken;

  @override
  Future<File> downloadAssetWithFallback({
    required ReleaseAsset asset,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
    required void Function(DownloadProgress progress) onProgress,
    void Function(String currentProxy)? onProxySwitched,
    CancelToken? cancelToken,
    String? expectedSha256,
  }) {
    _completer = Completer<File>();
    _onProgress = onProgress;
    lastToken = cancelToken;
    return _completer!.future;
  }

  void emitProgress(int received, int total) {
    _onProgress?.call(
      DownloadProgress(
        receivedBytes: received,
        totalBytes: total,
        speedBytesPerSec: 102400,
      ),
    );
  }

  void completeSuccess(File file) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.complete(file);
    }
  }

  void completeError(Object error) {
    if (_completer != null && !_completer!.isCompleted) {
      _completer!.completeError(error);
    }
  }
}

class _MockRetryUpdateService extends UpdateService {
  _MockRetryUpdateService({required this.results});
  final List<UpdateCheckResult> results;
  int calls = 0;

  @override
  Future<UpdateCheckResult> checkForUpdatesWithFallback({
    required String currentVersion,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
  }) async {
    final result = results[calls];
    calls++;
    return result;
  }
}
