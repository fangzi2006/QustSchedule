/// 软件更新服务：负责检查更新、匹配架构与流式下载。
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
  }) : _client =
           httpClient ??
           (HttpClient()..connectionTimeout = const Duration(seconds: 15));

  final String repoOwner;
  final String repoName;
  final HttpClient _client;

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
      // 优先匹配 Inno Setup 安装包（支持原地覆盖更新）
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
      // 精确匹配当前包的运行 ABI
      for (final a in assets) {
        final name = a.name.toLowerCase();
        if (name.endsWith('.apk') && name.contains(archKey.toLowerCase())) {
          return a;
        }
      }
      // 兜底匹配
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

  /// 检查 GitHub 发布页的最新版本。
  Future<UpdateCheckResult> checkForUpdates({
    required String currentVersion,
    required String proxyPrefix,
  }) async {
    if (!Platform.isAndroid && !Platform.isWindows) {
      return const UpdateCheckResult(
        status: UpdateStatus.unsupportedPlatform,
        errorMessage: '当前平台暂不支持应用内更新',
      );
    }

    final rawApiUrl =
        'https://api.github.com/repos/$repoOwner/$repoName/releases/latest';
    final targetUrl = buildProxiedUrl(rawApiUrl, proxyPrefix);

    try {
      final request = await _client
          .getUrl(Uri.parse(targetUrl))
          .timeout(const Duration(seconds: 15));
      request.headers.set('User-Agent', 'QustSchedule-App');
      request.headers.set('Accept', 'application/vnd.github.v3+json');

      final response = await request.close().timeout(
        const Duration(seconds: 15),
      );
      final responseBody = await response.transform(utf8.decoder).join();

      if (response.statusCode == 403) {
        return const UpdateCheckResult(
          status: UpdateStatus.rateLimited,
          errorMessage: '检查更新过于频繁，已达到访问上限，请稍后再试或切换加速节点',
        );
      }

      if (response.statusCode != 200) {
        return UpdateCheckResult(
          status: UpdateStatus.error,
          errorMessage: '获取最新版本失败 (HTTP ${response.statusCode})',
        );
      }

      final json = jsonDecode(responseBody) as Map<String, dynamic>;
      final release = ReleaseInfo.fromJson(json);
      final (_, archDisplay) = currentArchitecture();
      final targetAsset = findTargetAsset(release.assets);

      final hasNew = isVersionNewer(release.version, currentVersion);
      if (hasNew) {
        return UpdateCheckResult(
          status: UpdateStatus.hasUpdate,
          release: release,
          targetAsset: targetAsset,
          currentArchName: archDisplay,
        );
      } else {
        return UpdateCheckResult(
          status: UpdateStatus.noUpdate,
          release: release,
          targetAsset: targetAsset,
          currentArchName: archDisplay,
        );
      }
    } on TimeoutException {
      return const UpdateCheckResult(
        status: UpdateStatus.networkError,
        errorMessage: '检查更新连接超时，请检查网络或在更新设置中切换加速节点',
      );
    } on SocketException catch (e) {
      return UpdateCheckResult(
        status: UpdateStatus.networkError,
        errorMessage: '网络连接失败 (${e.message})，可尝试切换加速节点',
      );
    } catch (e) {
      return UpdateCheckResult(
        status: UpdateStatus.error,
        errorMessage: '检查更新失败: $e',
      );
    }
  }

  /// 下载安装包并报告实时进度。
  Future<File> downloadAsset({
    required ReleaseAsset asset,
    required String proxyPrefix,
    required void Function(DownloadProgress progress) onProgress,
    CancelToken? cancelToken,
    String? expectedSha256,
  }) async {
    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/${asset.name}');
    if (file.existsSync()) {
      try {
        await file.delete();
      } catch (_) {}
    }

    final downloadUrl = buildProxiedUrl(asset.downloadUrl, proxyPrefix);
    final request = await _client.getUrl(Uri.parse(downloadUrl));
    request.headers.set('User-Agent', 'QustSchedule-App');
    final response = await request.close();

    if (response.statusCode != 200) {
      throw HttpException(
        '下载失败，HTTP 状态码: ${response.statusCode}',
        uri: Uri.parse(downloadUrl),
      );
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
      await for (final chunk in response) {
        if (cancelToken?.isCancelled == true) {
          throw Exception('下载已取消');
        }
        sink.add(chunk);
        receivedBytes += chunk.length;

        final now = DateTime.now();
        final elapsedMs = now.difference(lastTime).inMilliseconds;
        if (elapsedMs >= 300 || receivedBytes == totalBytes) {
          if (elapsedMs > 0) {
            currentSpeed = (receivedBytes - lastBytes) / (elapsedMs / 1000.0);
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
      await sink.close();
      if (file.existsSync()) {
        try {
          await file.delete();
        } catch (_) {}
      }
      rethrow;
    } finally {
      await sink.close();
    }

    // SHA256 校验（若提供）
    if (expectedSha256 != null && expectedSha256.isNotEmpty) {
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString().toLowerCase() !=
          expectedSha256.trim().toLowerCase()) {
        await file.delete();
        throw StateError('文件校验不匹配，安装包可能已损坏或被篡改');
      }
    }

    return file;
  }
}
