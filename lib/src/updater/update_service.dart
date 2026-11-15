/// 软件更新服务：负责检查更新、匹配架构、测速以及多节点故障自动回退下载。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:path_provider/path_provider.dart';

import 'app_installer.dart';
import 'update_models.dart';
import 'version_comparator.dart';
import '../app_version.dart';

/// 下载取消令牌。
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = <void Function()>[];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    final snapshot = List<void Function()>.of(_listeners);
    _listeners.clear();
    for (final listener in snapshot) {
      try {
        listener();
      } catch (_) {}
    }
  }

  void addListener(void Function() listener) {
    if (_cancelled) {
      listener();
      return;
    }
    _listeners.add(listener);
  }

  void removeListener(void Function() listener) {
    _listeners.remove(listener);
  }
}

class UpdateService {
  UpdateService({
    this.repoOwner = 'fangzi2006',
    this.repoName = 'QustSchedule',
    HttpClient? httpClient,
    @visibleForTesting Duration? probeTimeoutOverride,
    @visibleForTesting Duration? apiTimeoutOverride,
    @visibleForTesting Duration? downloadConnectTimeoutOverride,
    @visibleForTesting Duration? downloadIdleTimeoutOverride,
  }) : _ownsClient = httpClient == null,
       _client = httpClient ?? HttpClient(),
       _probeTimeout = probeTimeoutOverride ?? probeTimeout,
       _apiTimeout = apiTimeoutOverride ?? apiTimeout,
       _downloadConnectTimeout =
           downloadConnectTimeoutOverride ?? downloadConnectTimeout,
       _downloadIdleTimeout =
           downloadIdleTimeoutOverride ?? downloadIdleTimeout;

  final String repoOwner;
  final String repoName;
  final bool _ownsClient;
  final HttpClient _client;
  final Duration _probeTimeout;
  final Duration _apiTimeout;
  final Duration _downloadConnectTimeout;
  final Duration _downloadIdleTimeout;

  /// 释放底层网络连接资源（仅销毁内部自建的 HttpClient）。
  void dispose() {
    if (_ownsClient) {
      _client.close(force: true);
    }
  }

  /// 超时策略定义
  static const Duration probeTimeout = Duration(seconds: 5);
  static const Duration apiTimeout = Duration(seconds: 6);
  static const Duration downloadConnectTimeout = Duration(seconds: 15);
  static const Duration downloadIdleTimeout = Duration(seconds: 30);

  /// 伪装现代浏览器 User-Agent，规避公共反代与 CDN 针对非浏览器爬虫施加的低带宽 QoS 限流队列（防 500KB~1MB/s 限制）
  static const String browserUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36 QustSchedule/App';

  /// 多线程分块并发切片数（3 个并发切片为最佳吞吐与反爬平衡点）
  static const int maxConcurrentChunks = 3;

  /// 启用多线程并发分块的最小体积阈值（小于 4MB 的小文件单线程开销更小）
  static const int minChunkingBytes = 4 * 1024 * 1024;

  /// 静默清理临时目录中残留的历史安装包（版本号 <= 当前应用运行版本）以及未完成的临时切片文件。
  static Future<int> cleanOldUpdateFiles({
    String? currentVersion,
    Directory? targetDirectory,
  }) async {
    try {
      final curVer = currentVersion ?? appVersion;
      if (curVer.isEmpty || curVer == '-') return 0;
      final tempDir = targetDirectory ?? await getTemporaryDirectory();
      AppInstaller.cleanLegacyUpdaterScript(tempDir: tempDir);
      final entities = tempDir.listSync();
      final verRegex = RegExp(r'^QustSchedule_v?([0-9A-Za-z\.\+\-]+?)(?:-|\.)');

      int deletedCount = 0;
      for (final entity in entities) {
        if (entity is! File) continue;
        final filename = entity.uri.pathSegments.last;
        if (!filename.startsWith('QustSchedule_')) continue;

        // 清理切片碎片
        if (filename.contains('.part')) {
          try {
            entity.deleteSync();
            deletedCount++;
          } catch (_) {}
          continue;
        }

        final match = verRegex.firstMatch(filename);
        if (match != null) {
          final fileVer = match.group(1)!;
          if (compareSemanticVersions(fileVer, curVer) <= 0) {
            try {
              entity.deleteSync();
              deletedCount++;
            } catch (_) {}
          }
        }
      }
      return deletedCount;
    } catch (_) {
      return 0;
    }
  }

  /// 根据加速代理前缀拼装最终请求/下载链接。
  static String buildProxiedUrl(String rawUrl, String proxyPrefix) {
    final prefix = proxyPrefix.trim();
    if (prefix.isEmpty) return rawUrl;

    var normalized = prefix;
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      normalized = 'https://$normalized';
    }
    while (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    return '$normalized/$rawUrl';
  }

  /// 获取当前软件运行平台的架构标识与可读名称。
  static (String archKey, String archDisplay) currentArchitecture() {
    if (Platform.isWindows) {
      return ('windows-x64', 'Windows (64位)');
    }
    if (Platform.isAndroid) {
      try {
        final abi = Abi.current();
        if (abi == Abi.androidArm64) {
          return ('arm64-v8a', 'Android (arm64-v8a 64位)');
        }
        if (abi == Abi.androidArm) {
          return ('armeabi-v7a', 'Android (armeabi-v7a 32位)');
        }
      } catch (_) {}
      return ('arm64-v8a', 'Android (arm64-v8a)');
    }
    return ('unknown', '未知平台');
  }

  /// 判定当前 Windows 客户端是否为便携版（绿色免安装解压版）。
  ///
  /// 原理：Inno Setup 安装版在安装时必然于可执行文件同级目录生成 `unins000.exe` 卸载程序；
  /// CI 生成的便携版 zip 解压目录则不存在该文件。
  static bool isWindowsPortable() {
    if (!Platform.isWindows) return false;
    try {
      final exeFile = File(Platform.resolvedExecutable);
      final uninstaller = File(
        '${exeFile.parent.path}${Platform.pathSeparator}unins000.exe',
      );
      return !uninstaller.existsSync();
    } catch (_) {
      return false;
    }
  }

  /// 匹配适合当前软件自身架构与形态（安装版 / 便携版）的 Release 安装包文件。
  static ReleaseAsset? findTargetAsset(
    List<ReleaseAsset> assets, {
    bool? isPortable,
    bool? isWindows,
    bool? isAndroid,
    String? androidArch,
  }) {
    final onWindows =
        isWindows ?? (isPortable != null ? true : Platform.isWindows);
    if (onWindows) {
      final portable = isPortable ?? isWindowsPortable();
      if (portable) {
        // 便携版优先匹配 x64 的 .zip 绿色压缩包
        for (final a in assets) {
          final name = a.name.toLowerCase();
          if (name.endsWith('.zip') && name.contains('windows-x64')) return a;
        }
        for (final a in assets) {
          if (a.name.toLowerCase().endsWith('.zip')) return a;
        }
      } else {
        // 安装版优先匹配 setup.exe 安装向导
        for (final a in assets) {
          final name = a.name.toLowerCase();
          if (name.endsWith('.exe') && name.contains('setup')) return a;
        }
        for (final a in assets) {
          if (a.name.toLowerCase().endsWith('.exe')) return a;
        }
      }
      // 容错兜底：若线上 Release 缺失对应形态，回退匹配另一种 Windows 产物
      for (final a in assets) {
        final name = a.name.toLowerCase();
        if (name.endsWith('.exe') || name.endsWith('.zip')) return a;
      }
      return null;
    }

    final onAndroid = isAndroid ?? Platform.isAndroid;
    if (onAndroid) {
      final archKey = androidArch ?? currentArchitecture().$1;
      for (final a in assets) {
        final name = a.name.toLowerCase();
        if (name.endsWith('.apk') && name.contains(archKey.toLowerCase())) {
          return a;
        }
      }
      for (final a in assets) {
        final name = a.name.toLowerCase();
        if (name.endsWith('.apk') && name.contains('arm64')) return a;
      }
      for (final a in assets) {
        if (a.name.toLowerCase().endsWith('.apk')) return a;
      }
      return null;
    }

    return null;
  }

  /// 探测代理节点的连通性与延迟，并测试是否支持 api.github.com。
  Future<ProxyTestResult> testProxy(String proxyUrl) async {
    final cleanProxy = proxyUrl.trim();
    final stopwatch = Stopwatch()..start();

    // 1. 测试静态下载连通性
    final probeTarget =
        'https://raw.githubusercontent.com/$repoOwner/$repoName/main/pubspec.yaml';
    final targetUrl = buildProxiedUrl(probeTarget, cleanProxy);

    bool isUsable = false;
    int latency = 0;
    try {
      final request = await _client
          .getUrl(Uri.parse(targetUrl))
          .timeout(_probeTimeout);
      request.headers.set('User-Agent', 'QustSchedule-App');
      final response = await request.close().timeout(_probeTimeout);
      stopwatch.stop();
      latency = stopwatch.elapsedMilliseconds;
      isUsable = (response.statusCode >= 200 && response.statusCode < 400);
      await response.drain<void>().timeout(_probeTimeout);
    } catch (_) {
      return ProxyTestResult(
        proxyUrl: cleanProxy,
        isUsable: false,
        latencyMs: 0,
        supportsApi: false,
        errorMessage: '连接超时或握手失败',
      );
    }

    if (!isUsable) {
      return ProxyTestResult(
        proxyUrl: cleanProxy,
        isUsable: false,
        latencyMs: latency,
        supportsApi: false,
      );
    }

    // 2. 测试是否支持代理 api.github.com
    bool supportsApi = false;
    if (cleanProxy.isEmpty) {
      supportsApi = true;
    } else {
      try {
        final apiTarget =
            'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
        final apiUrl = buildProxiedUrl(apiTarget, cleanProxy);
        final apiReq = await _client
            .getUrl(Uri.parse(apiUrl))
            .timeout(const Duration(seconds: 4));
        apiReq.headers.set('User-Agent', 'QustSchedule-App');
        final apiResp = await apiReq.close().timeout(
          const Duration(seconds: 4),
        );
        supportsApi = (apiResp.statusCode == 200 || apiResp.statusCode == 403);
        await apiResp.drain<void>();
      } catch (_) {
        supportsApi = false;
      }
    }

    return ProxyTestResult(
      proxyUrl: cleanProxy,
      isUsable: true,
      latencyMs: latency,
      supportsApi: supportsApi,
    );
  }

  /// 带多节点轮询回退与 API 针对性降级的更新检查。
  ///
  /// 优先使用用户选中的首选代理；若不支持 API 或连接失败，自动轮询备选代理；
  /// 若所有代理都不支持 API 代理，最终自动降级为直连官方 `api.github.com`。
  Future<UpdateCheckResult> checkForUpdatesWithFallback({
    required String currentVersion,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
  }) async {
    // 异步清理历史旧版安装包与碎片，不阻塞检查流程
    unawaited(cleanOldUpdateFiles(currentVersion: currentVersion));
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const UpdateCheckResult(
        status: UpdateStatus.unsupportedPlatform,
        errorMessage: '当前平台暂不支持应用内更新',
      );
    }

    // 构造候选队列：选中的代理 -> 其余备选代理 -> 官方直连 (空字符串)
    final candidates = _buildCandidates(selectedProxy, backupProxies);

    final rawApiUrl =
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

    String? lastError;
    bool hadRateLimit = false;

    for (final candidate in candidates) {
      final targetUrl = buildProxiedUrl(rawApiUrl, candidate);
      try {
        final request = await _client
            .getUrl(Uri.parse(targetUrl))
            .timeout(_apiTimeout);
        request.headers.set('User-Agent', 'QustSchedule-App');
        request.headers.set('Accept', 'application/vnd.github.v3+json');

        final response = await request.close().timeout(_apiTimeout);
        final responseBody = await response
            .transform(utf8.decoder)
            .join()
            .timeout(_apiTimeout);

        if (response.statusCode == 403) {
          hadRateLimit = true;
          // 若通过直连仍报 403，说明 IP 确实超限
          if (candidate.isEmpty) {
            return const UpdateCheckResult(
              status: UpdateStatus.rateLimited,
              errorMessage: '检查更新过于频繁，已达访问上限，请稍后重试',
            );
          }
          // 代理报 403 时尝试下一个节点
          continue;
        }

        if (response.statusCode == 200) {
          final json = jsonDecode(responseBody) as Map<String, dynamic>;
          final release = ReleaseInfo.fromJson(json);
          final (_, archDisplay) = currentArchitecture();
          final targetAsset = findTargetAsset(release.assets);

          final hasNew = isVersionNewer(release.version, currentVersion);
          return UpdateCheckResult(
            status: hasNew ? UpdateStatus.hasUpdate : UpdateStatus.noUpdate,
            release: release,
            targetAsset: targetAsset,
            currentArchName: archDisplay,
          );
        }

        // 400（很多只代理文件的 gh-proxy 遇到 api 会报 400）或 502：继续尝试下一节点
        lastError = 'HTTP ${response.statusCode}';
      } catch (e) {
        lastError = e.toString();
        continue;
      }
    }

    if (hadRateLimit) {
      return const UpdateCheckResult(
        status: UpdateStatus.rateLimited,
        errorMessage: '检查更新过于频繁，已达到访问上限，请稍后再试',
      );
    }

    return UpdateCheckResult(
      status: UpdateStatus.networkError,
      errorMessage: '网络连接超时或所有代理节点不可用 ($lastError)',
    );
  }

  /// 兼容单代理调用的封装
  /// 带弱网重试机制的更新检测（纯网络策略：遇到网络错误退避重试）。
  Future<UpdateCheckResult> checkForUpdatesWithRetry({
    required String currentVersion,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
    int maxRetries = 2,
    Duration retryDelay = const Duration(seconds: 2),
    Future<void> Function(Duration delay)? delayFn,
  }) async {
    int retries = 0;
    while (true) {
      try {
        final result = await checkForUpdatesWithFallback(
          currentVersion: currentVersion,
          selectedProxy: selectedProxy,
          backupProxies: backupProxies,
        );
        if (result.status == UpdateStatus.networkError &&
            retries < maxRetries) {
          retries++;
          if (delayFn != null) {
            await delayFn(retryDelay);
          } else {
            await Future<void>.delayed(retryDelay);
          }
          continue;
        }
        return result;
      } catch (e) {
        if (retries < maxRetries) {
          retries++;
          if (delayFn != null) {
            await delayFn(retryDelay);
          } else {
            await Future<void>.delayed(retryDelay);
          }
          continue;
        }
        return UpdateCheckResult(
          status: UpdateStatus.networkError,
          errorMessage: '检查更新网络异常: $e',
        );
      }
    }
  }

  Future<UpdateCheckResult> checkForUpdates({
    required String currentVersion,
    required String proxyPrefix,
  }) {
    return checkForUpdatesWithFallback(
      currentVersion: currentVersion,
      selectedProxy: proxyPrefix,
    );
  }

  List<String> _buildCandidates(
    String selectedProxy,
    List<String> backupProxies,
  ) {
    final candidates = <String>[selectedProxy.trim()];
    for (final p in backupProxies) {
      final clean = p.trim();
      if (!candidates.contains(clean)) candidates.add(clean);
    }
    if (!candidates.contains('')) {
      candidates.add(''); // 确保最后总有直连兜底
    }
    return candidates;
  }

  /// 解析标准 `sha256sum` 生成的校验清单（支持 `./` 或 `*` 前缀）。
  static Map<String, String> parseSha256Sums(String content) {
    final result = <String, String>{};
    final lineRegex = RegExp(r'^([a-fA-F0-9]{64})\s+[*]?(.+)$');
    for (final rawLine in content.split(RegExp(r'\r?\n'))) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      final match = lineRegex.firstMatch(line);
      if (match == null) continue;
      final digest = match.group(1)!.toLowerCase();
      var filePath = match.group(2)!.trim();
      if (filePath.startsWith('./') || filePath.startsWith(r'.\')) {
        filePath = filePath.substring(2);
      }
      final fileName = filePath.split(RegExp(r'[/\\]')).last;
      if (fileName.isNotEmpty) {
        result[fileName] = digest;
      }
    }
    return result;
  }

  /// 从 Release 的 `SHA256SUMS` 产物中查询目标安装包对应的 SHA-256 摘要。
  Future<String?> fetchExpectedSha256({
    required ReleaseInfo release,
    required ReleaseAsset targetAsset,
    String selectedProxy = '',
    List<String> backupProxies = const <String>[],
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) return null;
    ReleaseAsset? sumAsset;
    for (final asset in release.assets) {
      if (asset.name.toUpperCase() == 'SHA256SUMS') {
        sumAsset = asset;
        break;
      }
    }
    if (sumAsset == null || sumAsset.downloadUrl.isEmpty) return null;

    final candidates = _buildCandidates(selectedProxy, backupProxies);
    for (final candidate in candidates) {
      if (cancelToken?.isCancelled == true) return null;
      final url = buildProxiedUrl(sumAsset.downloadUrl, candidate);
      HttpClientRequest? activeReq;
      final cancelSignal = Completer<void>();
      void onCancelled() {
        try {
          activeReq?.abort();
        } catch (_) {}
        if (!cancelSignal.isCompleted) {
          cancelSignal.complete();
        }
      }

      cancelToken?.addListener(onCancelled);
      try {
        final req = await _raceWithCancel(
          _client.getUrl(Uri.parse(url)).timeout(_apiTimeout),
          cancelSignal,
          onLateValue: _abortLateRequest,
        );
        activeReq = req;
        if (cancelToken?.isCancelled == true) {
          _abortLateRequest(req);
          return null;
        }
        req.headers.set('User-Agent', browserUserAgent);
        final res = await _raceWithCancel(
          req.close().timeout(_apiTimeout),
          cancelSignal,
          onLateValue: _cancelLateResponse,
        );
        if (res.statusCode != HttpStatus.ok) {
          await _raceWithCancel(
            res.drain<void>().timeout(_apiTimeout),
            cancelSignal,
          );
          continue;
        }
        final body = await _raceWithCancel(
          res.transform(utf8.decoder).join().timeout(_apiTimeout),
          cancelSignal,
        );
        final digest = parseSha256Sums(body)[targetAsset.name];
        if (digest != null && digest.isNotEmpty) {
          return digest;
        }
      } catch (_) {
        if (cancelToken?.isCancelled == true) return null;
        continue;
      } finally {
        cancelToken?.removeListener(onCancelled);
      }
    }
    return null;
  }

  /// 带多节点轮询回退与 3 线程并发分块加速的安装包下载方法。
  Future<File> downloadAssetWithFallback({
    required ReleaseAsset asset,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
    required void Function(DownloadProgress progress) onProgress,
    void Function(String proxyUrl)? onProxySwitched,
    CancelToken? cancelToken,
    String? expectedSha256,
    Directory? targetDirectory,
  }) async {
    final candidates = _buildCandidates(selectedProxy, backupProxies);

    final tempDir = targetDirectory ?? await getTemporaryDirectory();
    final file = File('${tempDir.path}/${asset.name}');

    // 1. 本地完整性嗅探与复用：若本地已存在同名且大小完全匹配的文件，直接跳过网络下载（0秒秒进安装）
    if (file.existsSync()) {
      try {
        final localLen = file.lengthSync();
        if (localLen == asset.size && asset.size > 0) {
          bool valid = true;
          if (expectedSha256 != null && expectedSha256.isNotEmpty) {
            final digest = await sha256.bind(file.openRead()).first;
            valid =
                digest.toString().toLowerCase() ==
                expectedSha256.trim().toLowerCase();
          }
          if (valid) {
            onProgress(
              DownloadProgress(
                receivedBytes: localLen,
                totalBytes: localLen,
                speedBytesPerSec: 0,
              ),
            );
            return file;
          }
        }
      } catch (_) {}

      // 本地文件不完整或校验未通过，清理后重新下载
      try {
        await file.delete();
      } catch (_) {}
    }

    Object? lastError;

    for (final candidate in candidates) {
      if (cancelToken?.isCancelled == true) {
        throw Exception('下载已取消');
      }

      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }

      onProxySwitched?.call(candidate);

      final downloadUrl = buildProxiedUrl(asset.downloadUrl, candidate);

      HttpClientRequest? activeProbeReq;
      final probeCancelSignal = Completer<void>();
      void onProbeCancelled() {
        try {
          activeProbeReq?.abort();
        } catch (_) {}
        if (!probeCancelSignal.isCompleted) {
          probeCancelSignal.complete();
        }
      }

      cancelToken?.addListener(onProbeCancelled);
      try {
        // 先发送 Range 探测请求：检查服务端是否支持 206 Partial Content，并读取精准文件总长
        final probeReq = await _raceWithCancel(
          _client
              .getUrl(Uri.parse(downloadUrl))
              .timeout(_downloadConnectTimeout),
          probeCancelSignal,
          onLateValue: _abortLateRequest,
        );
        activeProbeReq = probeReq;
        if (cancelToken?.isCancelled == true) {
          _abortLateRequest(probeReq);
          throw Exception('下载已取消');
        }

        probeReq.headers.set('User-Agent', browserUserAgent);
        probeReq.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
        probeReq.headers.set(HttpHeaders.rangeHeader, 'bytes=0-0');
        probeReq.headers.set(HttpHeaders.acceptHeader, '*/*');
        probeReq.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

        final probeRes = await _raceWithCancel(
          probeReq.close().timeout(_downloadConnectTimeout),
          probeCancelSignal,
          onLateValue: _cancelLateResponse,
        );

        if (probeRes.statusCode == HttpStatus.partialContent) {
          // 服务端支持 Range (206)
          int totalBytes = asset.size;
          final cr = probeRes.headers.value(HttpHeaders.contentRangeHeader);
          if (cr != null && cr.contains('/')) {
            final parsedTotal = int.tryParse(cr.split('/').last.trim());
            if (parsedTotal != null && parsedTotal > 0) {
              totalBytes = parsedTotal;
            }
          }
          await _raceWithCancel(
            probeRes.drain<void>().timeout(_downloadConnectTimeout),
            probeCancelSignal,
          );

          if (totalBytes >= minChunkingBytes) {
            try {
              // 文件大于 4MB 且支持 Range：优先开启 3 线程并发分块极速下载
              await _downloadMultiChunk(
                downloadUrl: downloadUrl,
                targetFile: file,
                totalBytes: totalBytes,
                onProgress: onProgress,
                cancelToken: cancelToken,
              );
            } catch (chunkError) {
              if (cancelToken?.isCancelled == true) rethrow;
              // 若该节点对并发切片限流或连接中断，立即在该节点内平滑回退单线程直通流
              await _downloadSingleUrl(
                downloadUrl: downloadUrl,
                targetFile: file,
                totalBytes: totalBytes,
                onProgress: onProgress,
                cancelToken: cancelToken,
              );
            }
          } else {
            // 小文件开销不大，走单连接直通
            await _downloadSingleUrl(
              downloadUrl: downloadUrl,
              targetFile: file,
              totalBytes: totalBytes,
              onProgress: onProgress,
              cancelToken: cancelToken,
            );
          }
        } else if (probeRes.statusCode == HttpStatus.ok) {
          // 服务端忽略了 Range 返回了 200，说明不支持 Range，但此时流已就绪！
          // 零额外网络握手，直接复用当前响应流作为单线程下载
          final totalBytes = probeRes.contentLength > 0
              ? probeRes.contentLength
              : asset.size;
          await _downloadSingleStream(
            response: probeRes,
            targetFile: file,
            totalBytes: totalBytes,
            onProgress: onProgress,
            cancelToken: cancelToken,
          );
        } else {
          await _raceWithCancel(
            probeRes.drain<void>().timeout(_downloadConnectTimeout),
            probeCancelSignal,
          );
          lastError = HttpException(
            'HTTP ${probeRes.statusCode}',
            uri: Uri.parse(downloadUrl),
          );
          continue;
        }

        // SHA256 校验
        if (expectedSha256 != null && expectedSha256.isNotEmpty) {
          final digest = await sha256.bind(file.openRead()).first;
          if (digest.toString().toLowerCase() !=
              expectedSha256.trim().toLowerCase()) {
            await file.delete();
            throw StateError('文件校验不匹配，安装包可能已损坏或被篡改');
          }
        }

        return file;
      } catch (e) {
        if (cancelToken?.isCancelled == true) {
          try {
            if (file.existsSync()) await file.delete();
          } catch (_) {}
          rethrow;
        }
        lastError = e;
        continue;
      } finally {
        cancelToken?.removeListener(onProbeCancelled);
      }
    }

    throw Exception('所有加速节点与直连下载均尝试失败: $lastError');
  }

  /// 3 线程并发分块下载并在完成后自动组装。
  Future<void> _downloadMultiChunk({
    required String downloadUrl,
    required File targetFile,
    required int totalBytes,
    required void Function(DownloadProgress progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    const numChunks = maxConcurrentChunks;
    final chunkSize = totalBytes ~/ numChunks;

    final workerReceived = List<int>.filled(numChunks, 0);
    var lastReportTime = DateTime.now();
    var lastTotalBytes = 0;
    var currentSpeed = 0.0;

    void reportProgress() {
      final now = DateTime.now();
      final elapsedMs = now.difference(lastReportTime).inMilliseconds;
      final currentTotal = workerReceived.fold<int>(0, (sum, val) => sum + val);

      if (elapsedMs >= 350 || currentTotal >= totalBytes) {
        if (elapsedMs > 0) {
          final instantSpeed =
              (currentTotal - lastTotalBytes) / (elapsedMs / 1000.0);
          currentSpeed = currentSpeed == 0.0
              ? instantSpeed
              : 0.7 * instantSpeed + 0.3 * currentSpeed;
        }
        lastReportTime = now;
        lastTotalBytes = currentTotal;

        onProgress(
          DownloadProgress(
            receivedBytes: currentTotal.clamp(0, totalBytes),
            totalBytes: totalBytes,
            speedBytesPerSec: currentSpeed,
          ),
        );
      }
    }

    final chunkCancel = CancelToken();
    void propagateCancel() => chunkCancel.cancel();
    cancelToken?.addListener(propagateCancel);

    final futures = <Future<void>>[];
    final partFiles = <File>[];

    for (int i = 0; i < numChunks; i++) {
      final start = i * chunkSize;
      final end = (i == numChunks - 1)
          ? (totalBytes - 1)
          : ((i + 1) * chunkSize - 1);
      final partFile = File('${targetFile.path}.part$i');
      partFiles.add(partFile);

      futures.add(
        _downloadSingleChunk(
          downloadUrl: downloadUrl,
          partFile: partFile,
          start: start,
          end: end,
          workerIndex: i,
          onBytes: (receivedInChunk) {
            workerReceived[i] = receivedInChunk;
            reportProgress();
          },
          cancelToken: chunkCancel,
        ).catchError((Object e, StackTrace st) {
          chunkCancel.cancel();
          Error.throwWithStackTrace(e, st);
        }),
      );
    }

    try {
      await Future.wait(futures, eagerError: true);

      if (cancelToken?.isCancelled == true || chunkCancel.isCancelled) {
        throw Exception('下载已取消');
      }

      // 所有切片下载成功，合并分片文件
      final outSink = targetFile.openWrite();
      try {
        for (final part in partFiles) {
          await outSink.addStream(part.openRead());
          try {
            await part.delete();
          } catch (_) {}
        }
        await outSink.flush();
      } finally {
        try {
          await outSink.close();
        } catch (_) {}
      }
    } catch (e) {
      // 发生异常或取消时先通知其余分片取消，待所有文件句柄关闭后再清理碎片。
      chunkCancel.cancel();
      await Future.wait(futures.map((f) => f.catchError((Object _) {})));
      for (final part in partFiles) {
        try {
          if (part.existsSync()) await part.delete();
        } catch (_) {}
      }
      try {
        if (targetFile.existsSync()) await targetFile.delete();
      } catch (_) {}
      rethrow;
    } finally {
      cancelToken?.removeListener(propagateCancel);
    }
  }

  void _abortLateRequest(HttpClientRequest request) {
    try {
      request.abort();
    } catch (_) {}
  }

  void _cancelLateResponse(HttpClientResponse response) {
    try {
      response
          .listen((_) {}, onError: (Object _) {}, cancelOnError: true)
          .cancel();
    } catch (_) {}
  }

  Future<T> _raceWithCancel<T>(
    Future<T> future,
    Completer<void> cancelSignal, {
    void Function(T value)? onLateValue,
  }) {
    if (cancelSignal.isCompleted) {
      if (onLateValue != null) {
        future.then((value) {
          try {
            onLateValue(value);
          } catch (_) {}
        }, onError: (Object _) {});
      } else {
        future.ignore();
      }
      return Future<T>.error(Exception('下载已取消'));
    }
    final out = Completer<T>();
    future.then(
      (value) {
        if (!out.isCompleted) {
          out.complete(value);
        } else if (onLateValue != null) {
          try {
            onLateValue(value);
          } catch (_) {}
        }
      },
      onError: (Object error, StackTrace st) {
        if (!out.isCompleted) out.completeError(error, st);
      },
    );
    cancelSignal.future.then((_) {
      if (!out.isCompleted) out.completeError(Exception('下载已取消'));
    });
    return out.future;
  }

  /// 单个切片的工作线程下载流。
  Future<void> _downloadSingleChunk({
    required String downloadUrl,
    required File partFile,
    required int start,
    required int end,
    required int workerIndex,
    required void Function(int receivedInChunk) onBytes,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw Exception('下载已取消');
    }
    if (partFile.existsSync()) {
      try {
        await partFile.delete();
      } catch (_) {}
    }

    HttpClientRequest? activeReq;
    final cancelSignal = Completer<void>();
    void onCancelled() {
      try {
        activeReq?.abort();
      } catch (_) {}
      if (!cancelSignal.isCompleted) {
        cancelSignal.complete();
      }
    }

    cancelToken?.addListener(onCancelled);
    try {
      final request = await _raceWithCancel(
        _client.getUrl(Uri.parse(downloadUrl)).timeout(_downloadConnectTimeout),
        cancelSignal,
        onLateValue: _abortLateRequest,
      );
      activeReq = request;
      if (cancelToken?.isCancelled == true) {
        _abortLateRequest(request);
        throw Exception('下载已取消');
      }

      request.headers.set('User-Agent', browserUserAgent);
      request.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      request.headers.set(HttpHeaders.rangeHeader, 'bytes=$start-$end');
      request.headers.set(HttpHeaders.acceptHeader, '*/*');
      request.headers.set(HttpHeaders.connectionHeader, 'keep-alive');

      final response = await _raceWithCancel(
        request.close().timeout(_downloadConnectTimeout),
        cancelSignal,
        onLateValue: _cancelLateResponse,
      );

      if (response.statusCode != HttpStatus.partialContent) {
        await _raceWithCancel(
          response.drain<void>().timeout(_downloadConnectTimeout),
          cancelSignal,
        );
        throw HttpException(
          'Chunk $workerIndex HTTP ${response.statusCode}',
          uri: Uri.parse(downloadUrl),
        );
      }

      final expectedBytes = end - start + 1;
      final sink = partFile.openWrite();
      var received = 0;
      StreamSubscription<List<int>>? subscription;
      Timer? idleTimer;
      final streamDone = Completer<void>();
      var streamFailed = false;

      void failStream(Object error, [StackTrace? st]) {
        streamFailed = true;
        idleTimer?.cancel();
        if (!streamDone.isCompleted) {
          streamDone.completeError(error, st);
        }
      }

      void resetIdleTimer() {
        idleTimer?.cancel();
        idleTimer = Timer(_downloadIdleTimeout, () {
          failStream(
            TimeoutException('Chunk $workerIndex stream idle timeout'),
          );
        });
      }

      try {
        resetIdleTimer();
        subscription = response.listen(
          (chunk) {
            if (streamFailed || cancelToken?.isCancelled == true) {
              if (cancelToken?.isCancelled == true) {
                failStream(Exception('下载已取消'));
              }
              return;
            }
            resetIdleTimer();
            if (received + chunk.length > expectedBytes) {
              failStream(
                HttpException(
                  'Chunk $workerIndex 超出预期长度: 预期 $expectedBytes 字节',
                  uri: Uri.parse(downloadUrl),
                ),
              );
              return;
            }
            sink.add(chunk);
            received += chunk.length;
            onBytes(received);
          },
          onError: (Object error, StackTrace st) {
            failStream(error, st);
          },
          onDone: () {
            idleTimer?.cancel();
            if (!streamDone.isCompleted) {
              if (received != expectedBytes) {
                streamDone.completeError(
                  HttpException(
                    'Chunk $workerIndex 传输未完成: 接收 $received 字节，预期 $expectedBytes 字节',
                    uri: Uri.parse(downloadUrl),
                  ),
                );
              } else {
                streamDone.complete();
              }
            }
          },
          cancelOnError: true,
        );

        await _raceWithCancel(streamDone.future, cancelSignal);
        await sink.flush();
      } finally {
        idleTimer?.cancel();
        try {
          await subscription?.cancel();
        } catch (_) {}
        try {
          await sink.close();
        } catch (_) {}
      }
    } finally {
      cancelToken?.removeListener(onCancelled);
    }
  }

  /// 发起单连接 GET 请求并验证 HTTP 200 后交由直通流处理器落盘。
  Future<void> _downloadSingleUrl({
    required String downloadUrl,
    required File targetFile,
    required int totalBytes,
    required void Function(DownloadProgress progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      throw Exception('下载已取消');
    }

    HttpClientRequest? activeReq;
    final cancelSignal = Completer<void>();
    void onCancelled() {
      try {
        activeReq?.abort();
      } catch (_) {}
      if (!cancelSignal.isCompleted) {
        cancelSignal.complete();
      }
    }

    cancelToken?.addListener(onCancelled);
    try {
      final singleReq = await _raceWithCancel(
        _client.getUrl(Uri.parse(downloadUrl)).timeout(_downloadConnectTimeout),
        cancelSignal,
        onLateValue: _abortLateRequest,
      );
      activeReq = singleReq;
      if (cancelToken?.isCancelled == true) {
        _abortLateRequest(singleReq);
        throw Exception('下载已取消');
      }
      singleReq.headers.set('User-Agent', browserUserAgent);
      singleReq.headers.set(HttpHeaders.acceptEncodingHeader, 'identity');
      singleReq.headers.set(HttpHeaders.acceptHeader, '*/*');
      singleReq.headers.set(HttpHeaders.connectionHeader, 'keep-alive');
      final singleRes = await _raceWithCancel(
        singleReq.close().timeout(_downloadConnectTimeout),
        cancelSignal,
        onLateValue: _cancelLateResponse,
      );
      if (singleRes.statusCode != HttpStatus.ok) {
        await _raceWithCancel(
          singleRes.drain<void>().timeout(_downloadConnectTimeout),
          cancelSignal,
        );
        throw HttpException(
          'HTTP ${singleRes.statusCode}',
          uri: Uri.parse(downloadUrl),
        );
      }
      await _downloadSingleStream(
        response: singleRes,
        targetFile: targetFile,
        totalBytes: totalBytes,
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } finally {
      cancelToken?.removeListener(onCancelled);
    }
  }

  /// 单线程直通下载流处理（带零额外网络握手与平滑限频更新）。
  Future<void> _downloadSingleStream({
    required HttpClientResponse response,
    required File targetFile,
    required int totalBytes,
    required void Function(DownloadProgress progress) onProgress,
    CancelToken? cancelToken,
  }) async {
    if (cancelToken?.isCancelled == true) {
      _cancelLateResponse(response);
      throw Exception('下载已取消');
    }

    final sink = targetFile.openWrite();
    var receivedBytes = 0;
    var lastTime = DateTime.now();
    var lastBytes = 0;
    var currentSpeed = 0.0;

    StreamSubscription<List<int>>? subscription;
    Timer? idleTimer;
    final streamDone = Completer<void>();
    final cancelSignal = Completer<void>();
    var streamFailed = false;

    void failStream(Object error, [StackTrace? st]) {
      streamFailed = true;
      idleTimer?.cancel();
      if (!streamDone.isCompleted) {
        streamDone.completeError(error, st);
      }
    }

    void resetIdleTimer() {
      idleTimer?.cancel();
      idleTimer = Timer(_downloadIdleTimeout, () {
        failStream(TimeoutException('Download stream idle timeout'));
      });
    }

    void onCancelled() {
      if (!cancelSignal.isCompleted) {
        cancelSignal.complete();
      }
    }

    cancelToken?.addListener(onCancelled);
    var shouldDeleteTarget = false;

    try {
      resetIdleTimer();
      subscription = response.listen(
        (chunk) {
          if (streamFailed || cancelToken?.isCancelled == true) {
            if (cancelToken?.isCancelled == true) {
              failStream(Exception('下载已取消'));
            }
            return;
          }
          resetIdleTimer();
          sink.add(chunk);
          receivedBytes += chunk.length;

          final now = DateTime.now();
          final elapsedMs = now.difference(lastTime).inMilliseconds;
          if (elapsedMs >= 350 || receivedBytes == totalBytes) {
            if (elapsedMs > 0) {
              final instantSpeed =
                  (receivedBytes - lastBytes) / (elapsedMs / 1000.0);
              currentSpeed = currentSpeed == 0.0
                  ? instantSpeed
                  : 0.7 * instantSpeed + 0.3 * currentSpeed;
            }
            lastTime = now;
            lastBytes = receivedBytes;
            onProgress(
              DownloadProgress(
                receivedBytes: receivedBytes,
                totalBytes: totalBytes,
                speedBytesPerSec: currentSpeed,
              ),
            );
          }
        },
        onError: (Object error, StackTrace st) {
          failStream(error, st);
        },
        onDone: () {
          idleTimer?.cancel();
          if (!streamDone.isCompleted) {
            if (totalBytes > 0 && receivedBytes < totalBytes) {
              streamDone.completeError(
                HttpException(
                  '下载流传输未完成: 实际接收 $receivedBytes 字节，预期 $totalBytes 字节',
                ),
              );
            } else {
              streamDone.complete();
            }
          }
        },
        cancelOnError: true,
      );

      await _raceWithCancel(streamDone.future, cancelSignal);
      await sink.flush();
    } catch (_) {
      shouldDeleteTarget = true;
      rethrow;
    } finally {
      cancelToken?.removeListener(onCancelled);
      idleTimer?.cancel();
      try {
        await subscription?.cancel();
      } catch (_) {}
      try {
        await sink.close();
      } catch (_) {}
      if (shouldDeleteTarget) {
        try {
          if (targetFile.existsSync()) await targetFile.delete();
        } catch (_) {}
      }
    }
  }

  /// 兼容单节点调用的下载方法。
  Future<File> downloadAsset({
    required ReleaseAsset asset,
    required String proxyPrefix,
    required void Function(DownloadProgress progress) onProgress,
    CancelToken? cancelToken,
    String? expectedSha256,
  }) {
    return downloadAssetWithFallback(
      asset: asset,
      selectedProxy: proxyPrefix,
      onProgress: onProgress,
      cancelToken: cancelToken,
      expectedSha256: expectedSha256,
    );
  }
}
