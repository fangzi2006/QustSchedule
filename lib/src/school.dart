/// 学校配置：适配青岛科技大学，但保留换校能力。
///
/// 受登录策略影响，当前仅保留外网可登录的默认线路（`https://jwglxt.qust.edu.cn/jwglxt`）。
///
/// 换线路只改 `baseUrl`，协议层能力（登录 / Cookie / 课表 / 路由发现）与前端口径无关：
///  - 地址：`ZfClientConfig.baseUrl`；
///  - 端点：`ZfClientConfig.endpoints`；
///  - 主机白名单：`ZfClientConfig.allowedHosts`。
library;

/// 一所学校的接入信息。
class SchoolProfile {
  /// 展示名。
  final String name;

  /// 教务系统根地址（不带 `login_slogin.html`，到 `/jwglxt` 为止）。
  final String baseUrl;

  /// 备注：接入状态、已知坑。
  final String notes;

  const SchoolProfile({
    required this.name,
    required this.baseUrl,
    this.notes = '',
  });
}

/// 默认学校：青岛科技大学。
const SchoolProfile qustProfile = SchoolProfile(
  name: '青岛科技大学',
  baseUrl: 'https://jwglxt.qust.edu.cn/jwglxt',
  notes: '当前外网可登录的默认线路；若登录成功后 302 到同主机 http，客户端已自动升级回 https。',
);

/// 青科大的预设教务线路。
///
/// 受外网登录策略限制，当前默认仅保留 `https://jwglxt.qust.edu.cn/jwglxt` 一条线路。
const List<SchoolProfile> qustLines = <SchoolProfile>[qustProfile];

/// 全部已知接入（当前仅保留青科大默认线路）。加线路时改这里，登录页与地址页的快捷选项随之更新。
const List<SchoolProfile> knownSchools = qustLines;

/// 出厂预设的教务地址（地址簿的初始内容，顺序即展示顺序）。
///
/// 当前默认只保留一条：`https://jwglxt.qust.edu.cn/jwglxt`。
final List<String> presetSchoolUrls = <String>[
  for (final SchoolProfile profile in qustLines) profile.baseUrl,
];

/// 当前默认使用的学校。
const SchoolProfile defaultSchool = qustProfile;

/// 按主机名配置的最小请求间隔（毫秒），兼容对高频请求存在风控的第三方教务站点。
const Map<String, int> defaultAcademicPaceHosts = <String, int>{
  'jw.cqiivc.com': 1200,
};

/// 地址的展示名：命中已知线路就用它的名字，否则退回地址本身。
String schoolLabel(String baseUrl) {
  for (final SchoolProfile profile in knownSchools) {
    if (sameSchool(profile.baseUrl, baseUrl)) return profile.name;
  }
  return baseUrl;
}

/// 判断两个教务地址是否指向同一套系统（忽略末尾斜杠与 http/https 差异）。
///
/// 换地址后旧的 Cookie 快照必须丢弃：快照与主机绑定，且 `CookieStore.import`
/// 会用快照里的 baseUrl 覆盖当前配置。
bool sameSchool(String a, String b) {
  String key(String value) =>
      normalizeSchoolKeyUrl(value).replaceFirst(RegExp(r'^https?://'), '');

  return key(a) == key(b);
}

/// 规范化教务地址用于凭据键拼接（忽略首尾空白、大小写与末尾斜杠）。
String normalizeSchoolKeyUrl(String baseUrl) {
  var text = baseUrl.trim().toLowerCase();
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// 构造凭据存储使用的规范化账号键（忽略 `baseUrl` 首尾空白、大小写与末尾斜杠差异）。
String buildAccountKey(String baseUrl, String username) =>
    '${normalizeSchoolKeyUrl(baseUrl)}|$username';
