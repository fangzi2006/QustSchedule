/// 语义化版本号比对工具。
///
/// 支持常见的版本格式：
/// - `1.2.3`
/// - `v1.2.3` / `V1.2.3`
/// - `1.2.2+31`（带构建号）
/// - `1.2.3-beta.1`（预发布标签）
library;

/// 比对两个版本号 [v1] 与 [v2]。
///
/// 若 [v1] > [v2] 返回正数；
/// 若 [v1] == [v2] 返回 0；
/// 若 [v1] < [v2] 返回负数。
int compareSemanticVersions(String v1, String v2) {
  final clean1 = _cleanVersion(v1);
  final clean2 = _cleanVersion(v2);

  final parts1 = clean1.coreParts;
  final parts2 = clean2.coreParts;

  final maxLen = parts1.length > parts2.length ? parts1.length : parts2.length;
  for (var i = 0; i < maxLen; i++) {
    final p1 = i < parts1.length ? parts1[i] : 0;
    final p2 = i < parts2.length ? parts2[i] : 0;
    if (p1 != p2) {
      return p1.compareTo(p2);
    }
  }

  // 主版本段完全一致时，比较构建号（如果有）
  if (clean1.buildNumber != null && clean2.buildNumber != null) {
    if (clean1.buildNumber != clean2.buildNumber) {
      return clean1.buildNumber!.compareTo(clean2.buildNumber!);
    }
  }

  // 若一个带预发布标识而另一个不带，正式版 > 预发布版
  if (clean1.isPreRelease && !clean2.isPreRelease) return -1;
  if (!clean1.isPreRelease && clean2.isPreRelease) return 1;

  return 0;
}

/// 检查 [remoteVersion] 是否严格高于 [currentVersion]。
bool isVersionNewer(String remoteVersion, String currentVersion) {
  return compareSemanticVersions(remoteVersion, currentVersion) > 0;
}

/// 解析与清洗版本号。
_ParsedVersion _cleanVersion(String input) {
  var s = input.trim();
  if (s.startsWith('v') || s.startsWith('V')) {
    s = s.substring(1).trim();
  }

  int? buildNum;
  if (s.contains('+')) {
    final plusIndex = s.indexOf('+');
    final buildStr = s.substring(plusIndex + 1);
    buildNum = int.tryParse(buildStr);
    s = s.substring(0, plusIndex);
  }

  bool isPreRelease = false;
  if (s.contains('-')) {
    isPreRelease = true;
    final dashIndex = s.indexOf('-');
    s = s.substring(0, dashIndex);
  }

  final core = <int>[];
  for (final seg in s.split('.')) {
    core.add(int.tryParse(seg.trim()) ?? 0);
  }
  if (core.isEmpty) {
    core.add(0);
  }

  return _ParsedVersion(
    coreParts: core,
    buildNumber: buildNum,
    isPreRelease: isPreRelease,
  );
}

class _ParsedVersion {
  const _ParsedVersion({
    required this.coreParts,
    required this.buildNumber,
    required this.isPreRelease,
  });

  final List<int> coreParts;
  final int? buildNumber;
  final bool isPreRelease;
}
