/// 软件更新数据模型。
library;

/// 单个发布产物信息。
class ReleaseAsset {
  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
    required this.contentType,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> json) {
    return ReleaseAsset(
      name: (json['name'] as String?)?.trim() ?? '',
      downloadUrl: (json['browser_download_url'] as String?)?.trim() ?? '',
      size: (json['size'] as num?)?.toInt() ?? 0,
      contentType: (json['content_type'] as String?)?.trim() ?? '',
    );
  }

  final String name;
  final String downloadUrl;
  final int size;
  final String contentType;

  /// 人类可读的大小（如 `18.5 MB`）。
  String get formattedSize {
    if (size <= 0) return '未知大小';
    const kb = 1024;
    const mb = kb * 1024;
    if (size >= mb) {
      return '${(size / mb).toStringAsFixed(1)} MB';
    }
    if (size >= kb) {
      return '${(size / kb).toStringAsFixed(1)} KB';
    }
    return '$size B';
  }
}

/// GitHub Release 发布版本信息。
class ReleaseInfo {
  const ReleaseInfo({
    required this.tagName,
    required this.version,
    required this.name,
    required this.body,
    required this.publishedAt,
    required this.assets,
    required this.htmlUrl,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> json) {
    final rawTag = (json['tag_name'] as String?)?.trim() ?? '';
    final cleanVer = rawTag.startsWith('v') || rawTag.startsWith('V')
        ? rawTag.substring(1).trim()
        : rawTag;

    final rawAssets = json['assets'];
    final parsedAssets = <ReleaseAsset>[];
    if (rawAssets is List<dynamic>) {
      for (final item in rawAssets) {
        if (item is Map<String, dynamic>) {
          parsedAssets.add(ReleaseAsset.fromJson(item));
        }
      }
    }

    DateTime? publishedDate;
    final rawPublished = json['published_at'] as String?;
    if (rawPublished != null && rawPublished.isNotEmpty) {
      publishedDate = DateTime.tryParse(rawPublished);
    }

    return ReleaseInfo(
      tagName: rawTag,
      version: cleanVer,
      name: (json['name'] as String?)?.trim() ?? '',
      body: (json['body'] as String?)?.trim() ?? '',
      publishedAt: publishedDate,
      assets: parsedAssets,
      htmlUrl: (json['html_url'] as String?)?.trim() ?? '',
    );
  }

  final String tagName;
  final String version;
  final String name;
  final String body;
  final DateTime? publishedAt;
  final List<ReleaseAsset> assets;
  final String htmlUrl;

  /// 清洗后的更新说明（去除 GitHub CI 自动拼接的下载表格、Shield 徽章与比对链接）。
  String get cleanBody => cleanReleaseBody(body);

  /// 过滤 GitHub Actions 自动化拼接模板内容。
  static String cleanReleaseBody(String rawBody) {
    if (rawBody.trim().isEmpty) return '';

    final lines = rawBody.split(RegExp(r'\r?\n'));
    final resultLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      // 遇到 CI 自动追加的操作系统下载指引或表格行，直接截断后面的所有冗余内容
      if (trimmed.startsWith('## 📥') ||
          trimmed.startsWith('### 📥') ||
          trimmed.contains('根据你的操作系统下载') ||
          trimmed.startsWith('| OS |') ||
          trimmed.startsWith('|:--:')) {
        break;
      }
      // 过滤比对与变更外链行
      if (trimmed.startsWith('所有变更列表：') ||
          (trimmed.startsWith('[ChangeLog](') && trimmed.endsWith(')'))) {
        continue;
      }
      resultLines.add(line);
    }

    return resultLines.join('\n').trim();
  }

  /// 格式化发布日期（如 `2026-10-30`）。
  String get formattedDate {
    final d = publishedAt;
    if (d == null) return '';
    return '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}

/// 检查更新结果状态。
enum UpdateStatus {
  /// 发现新版本。
  hasUpdate,

  /// 已是最新版本。
  noUpdate,

  /// API 访问频次达到上限（HTTP 403 Rate Limit）。
  rateLimited,

  /// 网络连接异常或超时。
  networkError,

  /// 当前运行平台不支持应用内更新。
  unsupportedPlatform,

  /// 其他异常错误。
  error,
}

/// 检查更新返回结果。
class UpdateCheckResult {
  const UpdateCheckResult({
    required this.status,
    this.release,
    this.targetAsset,
    this.currentArchName = '',
    this.errorMessage,
  });

  final UpdateStatus status;
  final ReleaseInfo? release;
  final ReleaseAsset? targetAsset;
  final String currentArchName;
  final String? errorMessage;

  bool get hasUpdate => status == UpdateStatus.hasUpdate;
}

/// 下载进度信息。
class DownloadProgress {
  const DownloadProgress({
    required this.receivedBytes,
    required this.totalBytes,
    required this.speedBytesPerSec,
  });

  final int receivedBytes;
  final int totalBytes;
  final double speedBytesPerSec;

  double get progress {
    if (totalBytes <= 0) return 0.0;
    return (receivedBytes / totalBytes).clamp(0.0, 1.0);
  }

  int get percentage {
    return (progress * 100).toInt();
  }

  String get formattedSpeed {
    const kb = 1024.0;
    const mb = kb * 1024.0;
    if (speedBytesPerSec >= mb) {
      return '${(speedBytesPerSec / mb).toStringAsFixed(1)} MB/s';
    }
    if (speedBytesPerSec >= kb) {
      return '${(speedBytesPerSec / kb).toStringAsFixed(1)} KB/s';
    }
    return '${speedBytesPerSec.toStringAsFixed(0)} B/s';
  }

  String get formattedReceived {
    const mb = 1024 * 1024.0;
    return '${(receivedBytes / mb).toStringAsFixed(1)} MB';
  }

  String get formattedTotal {
    const mb = 1024 * 1024.0;
    return '${(totalBytes / mb).toStringAsFixed(1)} MB';
  }
}

/// 代理节点连通性测试结果。
class ProxyTestResult {
  const ProxyTestResult({
    required this.proxyUrl,
    required this.isUsable,
    required this.latencyMs,
    required this.supportsApi,
    this.errorMessage,
  });

  final String proxyUrl;
  final bool isUsable;
  final int latencyMs;
  final bool supportsApi;
  final String? errorMessage;

  String get summary {
    if (!isUsable) return '超时或不可用';
    final apiTag = supportsApi ? '支持 API' : '仅下载加速';
    return '$latencyMs ms · $apiTag';
  }
}

/// 辅助函数：根据代理地址展示简洁名称。
String displayProxyName(String proxyUrl) {
  final trimmed = proxyUrl.trim();
  if (trimmed.isEmpty) return '官方直连 (GitHub)';
  if (trimmed.contains('gh-proxy.com')) return 'gh-proxy.com (默认推荐)';
  return trimmed;
}
