/// 软件更新服务：负责检查更新、匹配架构、测速以及多节点故障自动回退下载。
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

import 'update_models.dart';
import 'version_comparator.dart';

/// 下载取消令牌。
class CancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

class UpdateService {
  UpdateService({
    this.repoOwner = 'fangzi2006',
    this.repoName = 'QustSchedule',
    HttpClient? httpClient,
  }) : _client = httpClient ?? HttpClient();

  final String repoOwner;
  final String repoName;
  final HttpClient _client;

  /// 超时策略定义
  static const Duration probeTimeout = Duration(seconds: 5);
  static const Duration apiTimeout = Duration(seconds: 6);
  static const Duration downloadConnectTimeout = Duration(seconds: 15);
  static const Duration downloadIdleTimeout = Duration(seconds: 30);

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

  /// 匹配适合当前软件自身架构的 Release 安装包文件。
  static ReleaseAsset? findTargetAsset(List<ReleaseAsset> assets) {
    if (Platform.isWindows) {
      for (final a in assets) {
        final name = a.name.toLowerCase();
        if (name.endsWith('.exe') && name.contains('setup')) return a;
      }
      for (final a in assets) {
        if (a.name.toLowerCase().endsWith('.exe')) return a;
      }
      for (final a in assets) {
        if (a.name.toLowerCase().endsWith('.zip')) return a;
      }
      return null;
    }

    if (Platform.isAndroid) {
      final (archKey, _) = currentArchitecture();
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
          .timeout(probeTimeout);
      request.headers.set('User-Agent', 'QustSchedule-App');
      final response = await request.close().timeout(probeTimeout);
      stopwatch.stop();
      latency = stopwatch.elapsedMilliseconds;
      isUsable = (response.statusCode >= 200 && response.statusCode < 400);
      await response.drain<void>();
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
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const UpdateCheckResult(
        status: UpdateStatus.unsupportedPlatform,
        errorMessage: '当前平台暂不支持应用内更新',
      );
    }

    // 构造候选队列：选中的代理 -> 其余备选代理 -> 官方直连 (空字符串)
    final candidates = <String>[];
    candidates.add(selectedProxy.trim());
    for (final p in backupProxies) {
      final clean = p.trim();
      if (!candidates.contains(clean)) candidates.add(clean);
    }
    if (!candidates.contains('')) {
      candidates.add(''); // 确保最后总有直连兜底
    }

    final rawApiUrl =
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';

    String? lastError;
    bool hadRateLimit = false;

    for (final candidate in candidates) {
      final targetUrl = buildProxiedUrl(rawApiUrl, candidate);
      try {
        final request = await _client
            .getUrl(Uri.parse(targetUrl))
            .timeout(apiTimeout);
        request.headers.set('User-Agent', 'QustSchedule-App');
        request.headers.set('Accept', 'application/vnd.github.v3+json');

        final response = await request.close().timeout(apiTimeout);
        final responseBody = await response.transform(utf8.decoder).join();

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
  Future<UpdateCheckResult> checkForUpdates({
    required String currentVersion,
    required String proxyPrefix,
  }) {
    return checkForUpdatesWithFallback(
      currentVersion: currentVersion,
      selectedProxy: proxyPrefix,
    );
  }

  /// 带多节点轮询回退的流式下载安装包。
  Future<File> downloadAssetWithFallback({
    required ReleaseAsset asset,
    required String selectedProxy,
    List<String> backupProxies = const <String>[],
    required void Function(DownloadProgress progress) onProgress,
    void Function(String proxyUrl)? onProxySwitched,
    CancelToken? cancelToken,
    String? expectedSha256,
  }) async {
    final candidates = <String>[];
    candidates.add(selectedProxy.trim());
    for (final p in backupProxies) {
      final clean = p.trim();
      if (!candidates.contains(clean)) candidates.add(clean);
    }
    if (!candidates.contains('')) {
      candidates.add(''); // 最后直连
    }

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${asset.name}');

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

      try {
        final request = await _client
            .getUrl(Uri.parse(downloadUrl))
            .timeout(downloadConnectTimeout);
        request.headers.set('User-Agent', 'QustSchedule-App');
        final response = await request.close().timeout(downloadConnectTimeout);

        if (response.statusCode != 200) {
          lastError = HttpException(
            'HTTP ${response.statusCode}',
            uri: Uri.parse(downloadUrl),
          );
          continue;
        }

        final totalBytes = response.contentLength > 0
            ? response.contentLength
            : asset.size;
        var receivedBytes = 0;
        var lastTime = DateTime.now();
        var lastBytes = 0;
        var currentSpeed = 0.0;

        final sink = file.openWrite();
        try {
          // 使用 timeout 限制每片数据块之间的空闲等待（防断流，充足 30s 缓冲时间）
          await for (final chunk in response.timeout(downloadIdleTimeout)) {
            if (cancelToken?.isCancelled == true) {
              throw Exception('下载已取消');
            }
            sink.add(chunk);
            receivedBytes += chunk.length;

            final now = DateTime.now();
            final elapsedMs = now.difference(lastTime).inMilliseconds;
            if (elapsedMs >= 350 || receivedBytes == totalBytes) {
              if (elapsedMs > 0) {
                final instantSpeed =
                    (receivedBytes - lastBytes) / (elapsedMs / 1000.0);
                // 平滑速度指数移动平均，避免瞬时跳变引发界面抽搐
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
          }
          await sink.flush();
        } catch (e) {
          if (cancelToken?.isCancelled == true) rethrow;
          lastError = e;
          continue; // 断流时切换下一节点重试
        } finally {
          try {
            await sink.close();
          } catch (_) {}
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
        if (cancelToken?.isCancelled == true) rethrow;
        lastError = e;
        continue;
      }
    }

    throw Exception('所有加速节点与直连下载均尝试失败: $lastError');
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
