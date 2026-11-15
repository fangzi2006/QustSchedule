import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/about_page.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/timetable_edit_page.dart';
import 'package:qustschedule/pages/update_dialog.dart';
import 'package:qustschedule/pages/update_proxy_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/updater/app_installer.dart';
import 'package:qustschedule/src/updater/update_flow_controller.dart';
import 'package:qustschedule/src/updater/update_models.dart';
import 'package:qustschedule/src/updater/update_service.dart';
import 'package:qustschedule/src/updater/version_comparator.dart';

import 'support/fake_backend.dart';

void main() {
  group('版本号比对与加速代理 URL 拼装', () {
    test('isVersionNewer 处理语义化版本、v 前缀、构建号与不同长度', () {
      expect(isVersionNewer('1.2.3', '1.2.2'), isTrue);
      expect(isVersionNewer('1.3.0', '1.2.9'), isTrue);
      expect(isVersionNewer('2.0.0', '1.9.9'), isTrue);
      expect(isVersionNewer('1.2.2', '1.2.2'), isFalse);
      expect(isVersionNewer('1.2.1', '1.2.2'), isFalse);

      expect(isVersionNewer('v1.2.3', '1.2.2'), isTrue);
      expect(isVersionNewer('V1.2.3', 'v1.2.2'), isTrue);
      expect(isVersionNewer('  v1.2.3  ', '1.2.3'), isFalse);

      expect(isVersionNewer('1.2.2+32', '1.2.2+31'), isTrue);
      expect(isVersionNewer('1.2.3+1', '1.2.2+35'), isTrue);
      expect(isVersionNewer('1.2.2', '1.2.2+31'), isFalse);

      expect(isVersionNewer('1.2.1', '1.2'), isTrue);
      expect(isVersionNewer('1.3', '1.2.5'), isTrue);
      expect(isVersionNewer('1.2.0', '1.2'), isFalse);
    });

    test('UpdateService.buildProxiedUrl 处理空直连、斜杠与缺省协议头', () {
      const api =
          'https://api.github.com/repos/fangzi2006/QustSchedule/releases/latest';
      expect(UpdateService.buildProxiedUrl(api, ''), equals(api));
      expect(UpdateService.buildProxiedUrl(api, '   '), equals(api));

      const assetUrl =
          'https://github.com/fangzi2006/QustSchedule/releases/download/v1.2.2/app.apk';
      expect(
        UpdateService.buildProxiedUrl(assetUrl, 'https://gh-proxy.com'),
        equals('https://gh-proxy.com/$assetUrl'),
      );
      expect(
        UpdateService.buildProxiedUrl(assetUrl, 'https://gh-proxy.com/'),
        equals('https://gh-proxy.com/$assetUrl'),
      );
      expect(
        UpdateService.buildProxiedUrl(assetUrl, 'gh-proxy.com'),
        equals('https://gh-proxy.com/$assetUrl'),
      );
    });
  });

  group('Release 日志清洗、文件清理与产物匹配', () {
    test('cleanReleaseBody 过滤 GitHub CI 下载表格与比较链接，空白返回空串', () {
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
      expect(cleaned, isNot(contains('根据你的操作系统下载')));
      expect(cleaned, isNot(contains('| OS |')));
      expect(cleaned, isNot(contains('img.shields.io')));
      expect(cleaned, isNot(contains('所有变更列表：')));

      expect(ReleaseInfo.cleanReleaseBody(''), isEmpty);
      expect(ReleaseInfo.cleanReleaseBody('   \n  \r\n  '), isEmpty);
    });

    test('cleanOldUpdateFiles 自动静默清理历史旧版本安装包与未完成的临时分片文件', () async {
      final tempDir = Directory.systemTemp.createTempSync('qust_update_test_');
      try {
        final oldApk = File('${tempDir.path}/QustSchedule_v1.0.0-arm64-v8a.apk')
          ..writeAsStringSync('test-old-content');
        final sameApk = File(
          '${tempDir.path}/QustSchedule_v1.2.2-arm64-v8a.apk',
        )..writeAsStringSync('test-same-content');
        final newerApk = File(
          '${tempDir.path}/QustSchedule_v9.9.9-arm64-v8a.apk',
        )..writeAsStringSync('test-newer-content');
        final partFile = File('${tempDir.path}/QustSchedule_v1.2.3.apk.part0')
          ..writeAsStringSync('test-part');
        final unrelated = File('${tempDir.path}/other_app.apk')
          ..writeAsStringSync('unrelated');

        final deleted = await UpdateService.cleanOldUpdateFiles(
          currentVersion: '1.2.2',
          targetDirectory: tempDir,
        );
        expect(deleted, equals(3));
        expect(await oldApk.exists(), isFalse);
        expect(await sameApk.exists(), isFalse);
        expect(await partFile.exists(), isFalse);
        expect(await newerApk.exists(), isTrue);
        expect(await unrelated.exists(), isTrue);
      } finally {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('产物大小、下载进度格式化与 Windows 架构产物智能匹配（安装版 vs 便携版）', () {
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

      const p = DownloadProgress(
        receivedBytes: 5 * 1024 * 1024,
        totalBytes: 10 * 1024 * 1024,
        speedBytesPerSec: 2.5 * 1024 * 1024,
      );
      expect(p.percentage, equals(50));
      expect(p.formattedSpeed, equals('2.5 MB/s'));
      expect(p.formattedReceived, equals('5.0 MB'));
      expect(p.formattedTotal, equals('10.0 MB'));

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
      expect(
        UpdateService.findTargetAsset(assets, isPortable: true),
        equals(zipAsset),
      );
      expect(
        UpdateService.findTargetAsset(assets, isPortable: false),
        equals(setupAsset),
      );
    });
  });

  group('更新偏好设置与自动重试', () {
    test('默认代理配置、旧字段反序列化兼容与自定义代理增删持久化', () async {
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
      expect(
        Preferences.decode('{"ignoredUpdateVersion": "1.3.0"}').autoCheckUpdate,
        isTrue,
      );
      expect(
        Preferences.decode('{"selectedUpdateProxy": ""}').selectedUpdateProxy,
        isEmpty,
      );
      expect(
        Preferences.decode(
          '{"updateProxyUrl": " https://legacy-proxy.example "}',
        ).selectedUpdateProxy,
        equals('https://legacy-proxy.example'),
      );
      expect(
        Preferences.decode(
          '{"selectedUpdateProxy": "https://new-proxy.example", "updateProxyUrl": "https://legacy-proxy.example"}',
        ).selectedUpdateProxy,
        equals('https://new-proxy.example'),
      );
      expect(
        Preferences.decode(
          '{"selectedUpdateProxy": "", "updateProxyUrl": "https://legacy-proxy.example"}',
        ).selectedUpdateProxy,
        isEmpty,
      );
      expect(
        Preferences.decode(
          '{"selectedUpdateProxy": 123, "updateProxyUrl": " https://legacy-proxy.example "}',
        ).selectedUpdateProxy,
        equals('https://legacy-proxy.example'),
      );

      final model = AppModel(preferences: prefs);
      addTearDown(model.dispose);
      int prefsNotified = 0;
      model.prefsNotifier.addListener(() => prefsNotified++);

      await model.addCustomUpdateProxy('https://ghproxy.net');
      expect(model.customUpdateProxies, equals(['https://ghproxy.net']));
      expect(prefsNotified, greaterThan(0));

      await model.setSelectedUpdateProxy('https://ghproxy.net');
      expect(model.selectedUpdateProxy, equals('https://ghproxy.net'));

      await model.removeCustomUpdateProxy('https://ghproxy.net');
      expect(model.customUpdateProxies, isEmpty);

      await model.setAutoCheckUpdate(false);
      expect(model.autoCheckUpdate, isFalse);
    });

    test('checkForUpdatesWithRetry：首次成功不重试、网络错误重试恢复与达上限返回错误', () async {
      final okService = _MockRetryUpdateService(
        results: const [UpdateCheckResult(status: UpdateStatus.hasUpdate)],
      );
      int delayCalls = 0;
      final okResult = await okService.checkForUpdatesWithRetry(
        currentVersion: '1.0.0',
        selectedProxy: '',
        delayFn: (_) async => delayCalls++,
      );
      expect(okResult.status, UpdateStatus.hasUpdate);
      expect(okService.calls, 1);
      expect(delayCalls, 0);

      final recoverService = _MockRetryUpdateService(
        results: const [
          UpdateCheckResult(status: UpdateStatus.networkError),
          UpdateCheckResult(status: UpdateStatus.hasUpdate),
        ],
      );
      delayCalls = 0;
      final recoverResult = await recoverService.checkForUpdatesWithRetry(
        currentVersion: '1.0.0',
        selectedProxy: '',
        delayFn: (_) async => delayCalls++,
      );
      expect(recoverResult.status, UpdateStatus.hasUpdate);
      expect(recoverService.calls, 2);
      expect(delayCalls, 1);

      final failService = _MockRetryUpdateService(
        results: const [
          UpdateCheckResult(status: UpdateStatus.networkError),
          UpdateCheckResult(status: UpdateStatus.networkError),
          UpdateCheckResult(status: UpdateStatus.networkError),
        ],
      );
      delayCalls = 0;
      final failResult = await failService.checkForUpdatesWithRetry(
        currentVersion: '1.0.0',
        selectedProxy: '',
        maxRetries: 2,
        delayFn: (_) async => delayCalls++,
      );
      expect(failResult.status, UpdateStatus.networkError);
      expect(failService.calls, 3);
      expect(delayCalls, 2);
    });
  });

  group('更新界面交互 (Update UI Widgets)', () {
    testWidgets('更新对话框渲染版本、大小、过滤 CI 表格的 Markdown 日志与操作按钮并支持关闭', (tester) async {
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
|:--|:--|:--|
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

      expect(find.text('发现新版本 v1.2.3'), findsOneWidget);
      expect(find.textContaining('19.0 MB'), findsOneWidget);
      expect(find.textContaining('Android (arm64-v8a)'), findsOneWidget);
      expect(find.text('新增'), findsOneWidget);
      expect(find.text('优化'), findsOneWidget);
      expect(find.textContaining('增加关于页面与全新检查更新'), findsOneWidget);
      expect(find.textContaining('提升下载速度'), findsOneWidget);

      expect(find.textContaining('根据你的操作系统下载'), findsNothing);
      expect(find.textContaining('| OS |'), findsNothing);
      expect(find.textContaining('历史版本'), findsNothing);
      expect(find.text('忽略此版'), findsNothing);

      expect(find.text('稍后再说'), findsNothing);
      expect(find.byTooltip('稍后再说'), findsOneWidget);
      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.text('浏览器下载'), findsOneWidget);
      expect(find.text('立即更新'), findsOneWidget);

      final browserRect = tester.getRect(
        find.widgetWithText(OutlinedButton, '浏览器下载'),
      );
      final updateRect = tester.getRect(
        find.widgetWithText(FilledButton, '立即更新'),
      );
      expect(browserRect.right, lessThan(updateRect.left));

      await tester.tap(find.byTooltip('稍后再说'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.2.3'), findsNothing);
    });

    testWidgets('极窄屏与超大字体下更新弹窗操作按钮自动换行不溢出，无对应架构产物时展示友好提示', (tester) async {
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

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.8)),
            child: child!,
          ),
          home: Builder(
            builder: (context) => Column(
              children: <Widget>[
                ElevatedButton(
                  onPressed: () => showUpdateDialog(
                    context,
                    updateResult: const UpdateCheckResult(
                      status: UpdateStatus.hasUpdate,
                      release: release,
                      targetAsset: asset,
                      currentArchName: 'Android (arm64-v8a)',
                    ),
                    proxyPrefix: 'https://gh-proxy.com',
                  ),
                  child: const Text('OpenWithAsset'),
                ),
                ElevatedButton(
                  onPressed: () => showUpdateDialog(
                    context,
                    updateResult: const UpdateCheckResult(
                      status: UpdateStatus.hasUpdate,
                      release: release,
                      targetAsset: null,
                      currentArchName: 'Windows (x64)',
                    ),
                    proxyPrefix: '',
                  ),
                  child: const Text('OpenNoAsset'),
                ),
              ],
            ),
          ),
        ),
      );

      await tester.tap(find.text('OpenWithAsset'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final browserRect = tester.getRect(
        find.widgetWithText(OutlinedButton, '浏览器下载'),
      );
      final updateRect = tester.getRect(
        find.widgetWithText(FilledButton, '立即更新'),
      );
      expect(browserRect.bottom, lessThanOrEqualTo(updateRect.top));
      await tester.tap(find.byTooltip('稍后再说'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('OpenNoAsset'));
      await tester.pumpAndSettle();
      expect(find.textContaining('暂未匹配到直接升级安装包'), findsOneWidget);
      expect(find.text('前往 Release 页面'), findsOneWidget);
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
      await tester.pump();

      expect(find.text('正在下载更新'), findsOneWidget);
      expect(find.text('test_app.apk'), findsOneWidget);
      expect(find.text('取消下载'), findsOneWidget);

      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();
      expect(find.text('正在下载更新'), findsNothing);
    });

    testWidgets('更新代理管理页与关于页面呈现并支持选择节点、新增自定义代理', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });
      final model = AppModel(preferences: Preferences.inMemory());
      addTearDown(model.dispose);

      await tester.pumpWidget(MaterialApp(home: AboutPage(model: model)));
      expect(find.text('关于青科课表通'), findsOneWidget);
      expect(find.text('检查更新'), findsOneWidget);
      expect(find.text('更新日志'), findsOneWidget);
      expect(find.text('更新代理设置'), findsOneWidget);
      expect(find.text('调试信息'), findsOneWidget);
      expect(find.text('开源许可'), findsOneWidget);
      expect(find.text('开源协议'), findsOneWidget);
      expect(find.text('项目主页与源码'), findsOneWidget);

      await tester.pumpWidget(MaterialApp(home: UpdateProxyPage(model: model)));
      expect(find.text('更新代理设置'), findsOneWidget);
      expect(find.text('主加速节点(默认推荐)'), findsOneWidget);
      expect(find.text('直连'), findsOneWidget);

      await tester.tap(find.text('直连'));
      await tester.pumpAndSettle();
      expect(model.selectedUpdateProxy, isEmpty);

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
  });

  group('统一更新流程与后台下载 (UpdateFlowController & 课表顶栏)', () {
    testWidgets('单弹窗禁止点空白关闭，支持后台下载收起/重开恢复、取消回到预览与失败重试恢复', (tester) async {
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
      controller.setAvailableUpdate(
        result: const UpdateCheckResult(
          status: UpdateStatus.hasUpdate,
          release: release,
          targetAsset: asset,
          currentArchName: 'Windows (x64)',
        ),
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

      // 1. 打开弹窗，点击空白不关闭
      await tester.tap(find.text('OpenUpdate'));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.6.0'), findsOneWidget);
      await tester.tapAt(const Offset(10, 10));
      await tester.pumpAndSettle();
      expect(find.text('发现新版本 v1.6.0'), findsOneWidget);

      // 2. 点击「立即更新」进入下载，再点「后台下载」收起弹窗但任务继续
      await tester.tap(find.text('立即更新'));
      await tester.pump();
      expect(controller.stage, UpdateFlowStage.downloading);
      await tester.tap(find.text('后台下载'));
      await tester.pumpAndSettle();
      expect(find.text('正在下载更新'), findsNothing);
      expect(service.lastToken?.isCancelled, isFalse);

      // 3. 重开弹窗恢复进度，点击「取消下载」回到预览
      await tester.tap(find.text('OpenUpdate'));
      await tester.pump();
      service.emitProgress(500, 1000);
      await tester.pump();
      expect(find.text('50%'), findsOneWidget);

      await tester.tap(find.text('取消下载'));
      await tester.pumpAndSettle();
      expect(service.lastToken?.isCancelled, isTrue);
      expect(controller.stage, UpdateFlowStage.available);
      expect(find.text('发现新版本 v1.6.0'), findsOneWidget);

      // 4. 再次启动下载，模拟出错后点「重试下载」并完成
      await tester.tap(find.text('立即更新'));
      await tester.pump();
      service.completeError(Exception('network timeout'));
      await tester.pumpAndSettle();
      expect(controller.stage, UpdateFlowStage.error);
      expect(find.text('下载出错'), findsOneWidget);

      await tester.tap(find.text('重试下载'));
      await tester.pump();
      expect(controller.stage, UpdateFlowStage.downloading);
      service.completeSuccess(fakeApk);
      await tester.pumpAndSettle();
      expect(controller.stage, UpdateFlowStage.readyToInstall);
      expect(find.text('下载完成'), findsOneWidget);
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

      expect(find.byKey(updateButtonKey), findsOneWidget);
      final updateRect = tester.getRect(find.byKey(updateButtonKey));
      final refreshRect = tester.getRect(
        find.widgetWithIcon(IconButton, Icons.refresh_rounded),
      );
      expect(updateRect.right, lessThanOrEqualTo(refreshRect.left));

      await tester.tap(find.byKey(updateButtonKey));
      await tester.pumpAndSettle();
      await tester.tap(find.text('立即更新'));
      await tester.pump();
      await tester.tap(find.text('后台下载'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('正在下载更新'), findsNothing);
      expect(find.byKey(updateButtonKey), findsOneWidget);
      expect(find.byIcon(Icons.arrow_downward_rounded), findsOneWidget);

      service.completeSuccess(fakeApk);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(flow.stage, UpdateFlowStage.readyToInstall);
      expect(find.text('新版本 v1.6.0 下载完成'), findsOneWidget);
      expect(find.text('立即安装'), findsOneWidget);
      expect(find.byIcon(Icons.download_done_rounded), findsOneWidget);
    });
  });

  group('SHA256 校验与 Windows 更新脚本', () {
    test('parseSha256Sums 解析与 fetchExpectedSha256 远端拉取及下载透传', () async {
      const sumA =
          '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';
      const sumB =
          'ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789ABCDEF0123456789';
      const content =
          '# comment\n'
          '$sumA  ./QustSchedule-v1.0.0-arm64-v8a.apk\n'
          '$sumB *QustSchedule-v1.0.0-windows.zip\n'
          'invalid-line\n';

      final parsed = UpdateService.parseSha256Sums(content);
      expect(parsed['QustSchedule-v1.0.0-arm64-v8a.apk'], sumA);
      expect(parsed['QustSchedule-v1.0.0-windows.zip'], sumB.toLowerCase());
      expect(parsed.length, 2);

      final prevOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevOverrides);

      const digest =
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824';
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));

      server.listen((req) async {
        if (req.uri.path == '/SHA256SUMS') {
          req.response.statusCode = HttpStatus.ok;
          req.response.write('$digest  ./target.apk\n');
        } else {
          req.response.statusCode = HttpStatus.notFound;
        }
        await req.response.close();
      });

      final baseUrl = 'http://127.0.0.1:${server.port}';
      final service = UpdateService();
      addTearDown(service.dispose);

      const targetAsset = ReleaseAsset(
        name: 'target.apk',
        downloadUrl: 'https://example.com/target.apk',
        size: 5,
        contentType: 'application/vnd.android.package-archive',
      );
      final release = ReleaseInfo(
        tagName: 'v1.0.0',
        version: '1.0.0',
        name: 'v1.0.0',
        body: '',
        publishedAt: null,
        assets: [
          targetAsset,
          ReleaseAsset(
            name: 'SHA256SUMS',
            downloadUrl: '$baseUrl/SHA256SUMS',
            size: 80,
            contentType: 'text/plain',
          ),
        ],
        htmlUrl: '',
      );

      final actual = await service.fetchExpectedSha256(
        release: release,
        targetAsset: targetAsset,
      );
      expect(actual, digest);

      // UpdateFlowController 下载时向服务传递预期 SHA256
      final mockService = _MockDownloadUpdateService(resolvedSha256: digest);
      final flow = UpdateFlowController(
        updateService: mockService,
        canInstallCheck: () async => true,
        installRunner: (_) async {},
        openSettingsRunner: () async {},
      );
      addTearDown(flow.dispose);
      flow.setAvailableUpdate(
        result: const UpdateCheckResult(
          status: UpdateStatus.hasUpdate,
          release: ReleaseInfo(
            tagName: 'v1.6.0',
            version: '1.6.0',
            name: 'v1.6.0',
            body: '',
            publishedAt: null,
            assets: [targetAsset],
            htmlUrl: '',
          ),
          targetAsset: targetAsset,
        ),
        selectedProxy: '',
      );

      final future = flow.startDownload();
      await Future<void>.delayed(Duration.zero);
      expect(mockService.lastExpectedSha256, digest);

      final tmpFile = File('${Directory.systemTemp.path}/dummy_sha_test.apk')
        ..writeAsBytesSync(const <int>[1, 2, 3]);
      addTearDown(() {
        if (tmpFile.existsSync()) tmpFile.deleteSync();
      });
      mockService.completeSuccess(tmpFile);
      await future;
    });

    test('Windows 便携版/安装版更新脚本、隐藏 VBS 启动器生成与遗留文件清理', () {
      final portable = AppInstaller.buildWindowsPortableScript(
        exeName: 'qustschedule.exe',
        processId: 4321,
      );
      expect(portable.codeUnits.every((c) => c < 128), isTrue);
      expect(portable, contains('tasklist /FI "PID eq 4321" /FO CSV /NH'));
      expect(portable, contains('if not errorlevel 8'));
      expect(portable, contains('rd /s /q ".update_staging"'));
      expect(portable, contains('start "" "qustschedule.exe"'));
      expect(portable, contains(AppInstaller.portableVbsFileName));
      expect(portable, contains('del /f /q "%~f0"'));

      final setup = AppInstaller.buildWindowsSetupLauncherScript(
        setupFileName: 'QustSchedule_v1.6.0-windows-x64-setup.exe',
        processId: 9876,
      );
      expect(setup.codeUnits.every((c) => c < 128), isTrue);
      expect(setup, contains('tasklist /FI "PID eq 9876" /FO CSV /NH'));
      expect(setup, contains('/VERYSILENT'));
      expect(setup, contains('/AUTOSTART=1'));
      expect(setup, contains(AppInstaller.setupVbsFileName));

      final vbs = AppInstaller.buildHiddenVbsLauncher(
        AppInstaller.portableCmdFileName,
      );
      expect(vbs, contains(r'"\qustschedule_updater.cmd"'));
      expect(vbs, isNot(contains(r'\\qustschedule_updater.cmd')));
      expect(vbs, endsWith('0, False'));

      final sandbox = Directory.systemTemp.createTempSync('qust_cleanup_test_');
      addTearDown(() {
        if (sandbox.existsSync()) sandbox.deleteSync(recursive: true);
      });
      final appDir = Directory('${sandbox.path}/app')..createSync();
      final tempDir = Directory('${sandbox.path}/temp')..createSync();

      final files = <File>[
        File('${appDir.path}/${AppInstaller.portableCmdFileName}'),
        File('${appDir.path}/${AppInstaller.portableVbsFileName}'),
        File('${tempDir.path}/${AppInstaller.setupCmdFileName}'),
        File('${tempDir.path}/${AppInstaller.setupVbsFileName}'),
      ];
      for (final f in files) {
        f.writeAsStringSync('stub');
      }
      final staging = Directory('${appDir.path}/.update_staging')..createSync();
      File('${staging.path}/qustschedule.exe').writeAsStringSync('bin');

      AppInstaller.cleanLegacyUpdaterScript(appDir: appDir, tempDir: tempDir);

      for (final f in files) {
        expect(f.existsSync(), isFalse);
      }
      expect(staging.existsSync(), isFalse);
    });
  });

  group('并发分片取消、句柄关闭与流超时回归', () {
    test('任一分片异常时立即取消其余挂起分片、关闭句柄清理 .part 并安全回退单流下载', () async {
      final prevOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevOverrides);

      const totalSize = UpdateService.minChunkingBytes;
      final payload = Uint8List.fromList(
        List<int>.generate(totalSize, (i) => i & 0xff),
      );
      final expectedSha = sha256.convert(payload).toString();

      final tempDir = Directory.systemTemp.createTempSync('qust_chunk_fb_');
      final openStalledResponses = <HttpResponse>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        for (final res in openStalledResponses) {
          try {
            await res.close();
          } catch (_) {}
        }
        await server.close(force: true);
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      var rangeRequestCount = 0;
      var singleStreamCount = 0;
      server.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range == 'bytes=0-0') {
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-0/$totalSize',
          );
          req.response.add(<int>[payload[0]]);
          await req.response.close();
          return;
        }
        if (range != null) {
          final index = rangeRequestCount++;
          if (index == 0) {
            // 第一个分片写入少量数据后返回 500 失败（或连接失败），触发快速失败
            req.response.statusCode = HttpStatus.internalServerError;
            await req.response.close();
            return;
          }
          // 其余分片返回 206 并写入少量分片数据后挂起不关闭，模拟慢连接阻塞
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-1/$totalSize',
          );
          req.response.add(<int>[1, 2, 3]);
          await req.response.flush();
          openStalledResponses.add(req.response);
          return;
        }

        // 回退到单线程全量下载
        singleStreamCount++;
        req.response.statusCode = HttpStatus.ok;
        req.response.headers.contentLength = totalSize;
        req.response.add(payload);
        await req.response.close();
      });

      final service = UpdateService();
      addTearDown(service.dispose);
      final asset = ReleaseAsset(
        name: 'QustSchedule_test.apk',
        downloadUrl: 'http://${server.address.address}:${server.port}/pkg.apk',
        size: totalSize,
        contentType: 'application/vnd.android.package-archive',
      );

      final sw = Stopwatch()..start();
      final out = await service.downloadAssetWithFallback(
        asset: asset,
        selectedProxy: '',
        expectedSha256: expectedSha,
        targetDirectory: tempDir,
        onProgress: (_) {},
      );
      sw.stop();

      expect(sw.elapsed, lessThan(const Duration(seconds: 5)));
      expect(singleStreamCount, 1);
      expect(await out.readAsBytes(), payload);
      final leftoverParts = tempDir
          .listSync()
          .where((e) => e.path.contains('.part'))
          .toList();
      expect(leftoverParts, isEmpty);
    });

    test('外部取消并发分片下载时立即终止所有挂起分片并清理 .part 文件', () async {
      final prevOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevOverrides);

      const totalSize = UpdateService.minChunkingBytes;
      final tempDir = Directory.systemTemp.createTempSync('qust_chunk_cancel_');
      final openStalledResponses = <HttpResponse>[];
      final chunkStarted = Completer<void>();
      var chunkWorkers = 0;
      var fallbackSingleCount = 0;

      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        for (final res in openStalledResponses) {
          try {
            await res.close();
          } catch (_) {}
        }
        await server.close(force: true);
        if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
      });

      server.listen((req) async {
        final range = req.headers.value(HttpHeaders.rangeHeader);
        if (range == 'bytes=0-0') {
          req.response.statusCode = HttpStatus.partialContent;
          req.response.headers.set(
            HttpHeaders.contentRangeHeader,
            'bytes 0-0/$totalSize',
          );
          req.response.add(<int>[0]);
          await req.response.close();
          return;
        }
        if (range != null) {
          chunkWorkers++;
          req.response.statusCode = HttpStatus.partialContent;
          req.response.add(List<int>.filled(64, 7));
          await req.response.flush();
          openStalledResponses.add(req.response);
          if (chunkWorkers == UpdateService.maxConcurrentChunks &&
              !chunkStarted.isCompleted) {
            chunkStarted.complete();
          }
          return;
        }
        fallbackSingleCount++;
        req.response.statusCode = HttpStatus.ok;
        await req.response.close();
      });

      final service = UpdateService();
      addTearDown(service.dispose);
      final token = CancelToken();
      final asset = ReleaseAsset(
        name: 'QustSchedule_cancel.apk',
        downloadUrl: 'http://${server.address.address}:${server.port}/pkg.apk',
        size: totalSize,
        contentType: 'application/vnd.android.package-archive',
      );

      final future = service.downloadAssetWithFallback(
        asset: asset,
        selectedProxy: '',
        cancelToken: token,
        targetDirectory: tempDir,
        onProgress: (_) {},
      );

      await chunkStarted.future.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      token.cancel();

      await expectLater(future, throwsException);
      expect(fallbackSingleCount, 0);
      final leftoverParts = tempDir
          .listSync()
          .where((e) => e.path.contains('.part'))
          .toList();
      expect(leftoverParts, isEmpty);
    });

    test('checkForUpdatesWithFallback 在 200 响应体读取挂起时触发 .join().timeout 并回退下一节点', () async {
      final prevOverrides = HttpOverrides.current;
      HttpOverrides.global = null;
      addTearDown(() => HttpOverrides.global = prevOverrides);

      final openResponses = <HttpResponse>[];
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() async {
        for (final res in openResponses) {
          try {
            await res.close();
          } catch (_) {}
        }
        await server.close(force: true);
      });

      final releaseJson = jsonEncode(<String, Object?>{
        'tag_name': 'v9.9.9',
        'name': 'v9.9.9',
        'body': 'update',
        'assets': <Map<String, Object?>>[
          <String, Object?>{
            'name': 'QustSchedule-windows-x64.zip',
            'browser_download_url':
                'http://${server.address.address}:${server.port}/good/pkg.zip',
            'size': 128,
            'content_type': 'application/zip',
          },
        ],
        'html_url': 'https://github.com/fangzi2006/QustSchedule',
      });

      var attempts = 0;
      server.listen((req) async {
        attempts++;
        if (req.uri.path.startsWith('/hang/')) {
          req.response.statusCode = HttpStatus.ok;
          req.response.write('{"tag_name":');
          await req.response.flush();
          openResponses.add(req.response);
          return;
        }
        req.response.statusCode = HttpStatus.ok;
        req.response.write(releaseJson);
        await req.response.close();
      });

      final baseRoot = 'http://${server.address.address}:${server.port}';
      final service = UpdateService(
        apiTimeoutOverride: const Duration(milliseconds: 120),
      );
      addTearDown(service.dispose);

      // 注意 checkForUpdatesWithFallback 内部会把 api.github.com 拼到 proxy 后
      final result = await service.checkForUpdatesWithFallback(
        currentVersion: '1.0.0',
        selectedProxy: '$baseRoot/hang',
        backupProxies: <String>['$baseRoot/good'],
      );

      expect(attempts, 2);
      expect(result.status, UpdateStatus.hasUpdate);
      expect(result.release?.version, '9.9.9');
    });

    test(
      'fetchExpectedSha256 在 drain/join 超时时回退，且支持 CancelToken 立即中止挂起响应',
      () async {
        final prevOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = prevOverrides);

        final openResponses = <HttpResponse>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          for (final res in openResponses) {
            try {
              await res.close();
            } catch (_) {}
          }
          await server.close(force: true);
        });

        final validSha = List<String>.filled(64, 'b').join();
        final bodyStarted = Completer<void>();
        server.listen((req) async {
          final path = req.uri.path;
          if (path.startsWith('/drain_hang/')) {
            req.response.statusCode = HttpStatus.serviceUnavailable;
            req.response.write('busy');
            await req.response.flush();
            openResponses.add(req.response);
            return;
          }
          if (path.startsWith('/join_hang/')) {
            req.response.statusCode = HttpStatus.ok;
            req.response.write('dead');
            await req.response.flush();
            if (!bodyStarted.isCompleted) bodyStarted.complete();
            openResponses.add(req.response);
            return;
          }
          req.response.statusCode = HttpStatus.ok;
          req.response.write('$validSha  QustSchedule.apk\n');
          await req.response.close();
        });

        final baseRoot = 'http://${server.address.address}:${server.port}';
        final service = UpdateService(
          apiTimeoutOverride: const Duration(milliseconds: 120),
        );
        addTearDown(service.dispose);

        const asset = ReleaseAsset(
          name: 'QustSchedule.apk',
          downloadUrl: 'https://example.com/QustSchedule.apk',
          size: 100,
          contentType: 'application/vnd.android.package-archive',
        );
        const release = ReleaseInfo(
          tagName: 'v2.0.0',
          version: '2.0.0',
          name: 'v2.0.0',
          body: '',
          publishedAt: null,
          assets: <ReleaseAsset>[
            asset,
            ReleaseAsset(
              name: 'SHA256SUMS',
              downloadUrl: 'https://example.com/SHA256SUMS',
              size: 64,
              contentType: 'text/plain',
            ),
          ],
          htmlUrl: '',
        );

        // 1. 非 200 drain 超时 + 200 join 超时均能自动回退至健康节点
        final resolved = await service.fetchExpectedSha256(
          release: release,
          targetAsset: asset,
          selectedProxy: '$baseRoot/drain_hang',
          backupProxies: <String>['$baseRoot/join_hang', '$baseRoot/ok'],
        );
        expect(resolved, validSha);

        // 2. CancelToken 可立即打断挂起的 200 流，无需等待长超时
        final slowService = UpdateService(
          apiTimeoutOverride: const Duration(seconds: 10),
        );
        addTearDown(slowService.dispose);
        final token = CancelToken();
        final sw = Stopwatch()..start();
        final cancelledFuture = slowService.fetchExpectedSha256(
          release: release,
          targetAsset: asset,
          selectedProxy: '$baseRoot/join_hang',
          cancelToken: token,
        );
        await bodyStarted.future.timeout(const Duration(seconds: 2));
        token.cancel();
        expect(await cancelledFuture, isNull);
        expect(sw.elapsedMilliseconds, lessThan(2000));
      },
    );

    test(
      'downloadAssetWithFallback 在 probeRes.drain 超时后回退，单流挂起被取消立即退出并删碎片',
      () async {
        final prevOverrides = HttpOverrides.current;
        HttpOverrides.global = null;
        addTearDown(() => HttpOverrides.global = prevOverrides);

        final tempDir = Directory.systemTemp.createTempSync(
          'qust_probe_cancel_',
        );
        addTearDown(() {
          if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
        });

        final openResponses = <HttpResponse>[];
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        addTearDown(() async {
          for (final res in openResponses) {
            try {
              await res.close();
            } catch (_) {}
          }
          await server.close(force: true);
        });

        final payload = Uint8List.fromList(
          List<int>.generate(256, (i) => i & 0xff),
        );
        final streamStarted = Completer<void>();

        server.listen((req) async {
          final path = req.uri.path;
          if (path.startsWith('/probe_drain_hang/')) {
            req.response.statusCode = HttpStatus.partialContent;
            req.response.headers.set(
              HttpHeaders.contentRangeHeader,
              'bytes 0-0/${payload.length}',
            );
            req.response.add(<int>[0]);
            await req.response.flush();
            openResponses.add(req.response);
            return;
          }
          if (path.startsWith('/stream_hang/')) {
            req.response.statusCode = HttpStatus.ok;
            req.response.headers.contentLength = 4096;
            req.response.add(Uint8List(64));
            await req.response.flush();
            if (!streamStarted.isCompleted) streamStarted.complete();
            openResponses.add(req.response);
            return;
          }
          req.response.statusCode = HttpStatus.ok;
          req.response.headers.contentLength = payload.length;
          req.response.add(payload);
          await req.response.close();
        });

        final baseRoot = 'http://${server.address.address}:${server.port}';

        // 1. probeRes.drain().timeout(...) 触发后正确回退到健康节点下载
        final timeoutService = UpdateService(
          downloadConnectTimeoutOverride: const Duration(milliseconds: 120),
        );
        addTearDown(timeoutService.dispose);
        final downloaded = await timeoutService.downloadAssetWithFallback(
          asset: const ReleaseAsset(
            name: 'QustSchedule_probe.zip',
            downloadUrl: 'https://example.com/pkg.zip',
            size: 256,
            contentType: 'application/zip',
          ),
          selectedProxy: '$baseRoot/probe_drain_hang',
          backupProxies: <String>['$baseRoot/ok'],
          targetDirectory: tempDir,
          onProgress: (_) {},
        );
        expect(downloaded.existsSync(), isTrue);
        expect(downloaded.readAsBytesSync(), orderedEquals(payload));

        // 2. 单流读取挂起时 CancelToken 立即中止（无需等 idle timeout），并清理部分文件
        final idleService = UpdateService(
          downloadIdleTimeoutOverride: const Duration(seconds: 20),
        );
        addTearDown(idleService.dispose);
        final token = CancelToken();
        final sw = Stopwatch()..start();
        final cancelFuture = idleService.downloadAssetWithFallback(
          asset: const ReleaseAsset(
            name: 'QustSchedule_single_cancel.zip',
            downloadUrl: 'https://example.com/pkg.zip',
            size: 4096,
            contentType: 'application/zip',
          ),
          selectedProxy: '$baseRoot/stream_hang',
          cancelToken: token,
          targetDirectory: tempDir,
          onProgress: (_) {},
        );
        await streamStarted.future.timeout(const Duration(seconds: 2));
        await Future<void>.delayed(const Duration(milliseconds: 30));
        token.cancel();
        await expectLater(cancelFuture, throwsException);
        expect(sw.elapsedMilliseconds, lessThan(2000));
        expect(
          File('${tempDir.path}/QustSchedule_single_cancel.zip').existsSync(),
          isFalse,
        );
      },
    );

    testWidgets('UpdateProxyPage 与 TimetableEditPage 弹窗期间页面卸载不触发 setState 异常', (
      tester,
    ) async {
      final model = AppModel(preferences: Preferences.inMemory());
      addTearDown(model.dispose);
      await model.addCustomUpdateProxy('https://custom-proxy.example');

      final navKey = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navKey,
          home: const Scaffold(body: SizedBox.shrink()),
        ),
      );

      // 1. UpdateProxyPage._removeProxy 弹窗期间卸载页面后点删除
      final proxyRoute = MaterialPageRoute<void>(
        builder: (_) => UpdateProxyPage(model: model),
      );
      navKey.currentState!.push(proxyRoute);
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('删除'));
      await tester.pumpAndSettle();
      expect(find.text('删除代理'), findsOneWidget);

      navKey.currentState!.removeRoute(proxyRoute);
      await tester.pump();
      await tester.tap(find.text('删除'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(model.customUpdateProxies, isEmpty);

      // 2. TimetableEditPage 弹出时间轮期间卸载页面后点确定
      final editRoute = MaterialPageRoute<void>(
        builder: (_) => TimetableEditPage(
          model: model,
          timetableId: model.timetables.first.id,
        ),
      );
      navKey.currentState!.push(editRoute);
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.text('第 1 节'));
      await tester.tap(find.text('第 1 节'));
      await tester.pumpAndSettle();
      expect(find.text('确定'), findsOneWidget);

      navKey.currentState!.removeRoute(editRoute);
      await tester.pump();
      await tester.tap(find.text('确定'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });
}

class _MockDownloadUpdateService extends UpdateService {
  _MockDownloadUpdateService({this.resolvedSha256});

  final String? resolvedSha256;
  Completer<File>? _completer;
  void Function(DownloadProgress)? _onProgress;
  CancelToken? lastToken;
  String? lastExpectedSha256;

  @override
  Future<String?> fetchExpectedSha256({
    required ReleaseInfo release,
    required ReleaseAsset targetAsset,
    String selectedProxy = '',
    List<String> backupProxies = const <String>[],
    CancelToken? cancelToken,
  }) async => resolvedSha256;

  @override
  Future<File> downloadAssetWithFallback({
    required ReleaseAsset asset,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
    required void Function(DownloadProgress progress) onProgress,
    void Function(String currentProxy)? onProxySwitched,
    CancelToken? cancelToken,
    String? expectedSha256,
    Directory? targetDirectory,
  }) {
    _completer = Completer<File>();
    _onProgress = onProgress;
    lastToken = cancelToken;
    lastExpectedSha256 = expectedSha256;
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
