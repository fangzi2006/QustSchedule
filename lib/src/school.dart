/// 学校配置：默认只适配青岛科技大学，但保留换校能力。
///
/// 换校只需要在登录页修改教务地址（或在这里加一个 [SchoolProfile]），
/// 模块侧的全部能力（登录 / Cookie / 课表 / 路由发现）与学校无关：
///  - 地址：`ZfClientConfig.baseUrl`；
///  - 端点：`ZfClientConfig.endpoints`（课表 `gnmkdm` 等可逐校覆盖）；
///  - 主机白名单：`ZfClientConfig.allowedHosts`。
///
/// 尚未适配的学校类型（会由探测明确报出，而不是静默失败）：
///  - 旧正方 / 强智 / 金智 等非新正方系统；
///  - 需要统一认证（CAS）登录的新正方实例——探测会报 `requiresCas`，
///    app 会提示"该学校需要网页统一认证，暂不支持"。
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
  name: '青岛科技大学（线路 1）',
  baseUrl: 'https://jwglxt1.qust.edu.cn/jwglxt',
  notes: '实测可用；登录成功后会 302 到同主机 http，客户端已自动升级回 https。',
);

/// 青科大的 6 条教务线路：`jwglxt1` ~ `jwglxt6`。
///
/// 同一套系统的多台前端，**账号密码通用**；某条线路检修或超时时换一条即可。
/// 线路 1 是默认地址（也是实测过的那条），2~6 作为备用预设。
const List<SchoolProfile> qustLines = <SchoolProfile>[
  qustProfile,
  SchoolProfile(
    name: '青岛科技大学（线路 2）',
    baseUrl: 'https://jwglxt2.qust.edu.cn/jwglxt',
    notes: '备用线路',
  ),
  SchoolProfile(
    name: '青岛科技大学（线路 3）',
    baseUrl: 'https://jwglxt3.qust.edu.cn/jwglxt',
    notes: '备用线路',
  ),
  SchoolProfile(
    name: '青岛科技大学（线路 4）',
    baseUrl: 'https://jwglxt4.qust.edu.cn/jwglxt',
    notes: '备用线路',
  ),
  SchoolProfile(
    name: '青岛科技大学（线路 5）',
    baseUrl: 'https://jwglxt5.qust.edu.cn/jwglxt',
    notes: '备用线路',
  ),
  SchoolProfile(
    name: '青岛科技大学（线路 6）',
    baseUrl: 'https://jwglxt6.qust.edu.cn/jwglxt',
    notes: '备用线路',
  ),
];

/// 全部已知接入。新增学校时加到这里，登录页 / 地址页的快捷选项就有它。
const List<SchoolProfile> knownSchools = qustLines;

/// 出厂预设的教务地址（地址簿的初始内容，顺序即展示顺序）。
///
/// 第一条就是默认地址：`jwglxt1`。
final List<String> presetSchoolUrls = <String>[
  for (final SchoolProfile profile in qustLines) profile.baseUrl,
];

/// 当前默认使用的学校。
const SchoolProfile defaultSchool = qustProfile;

/// 地址的展示名：命中已知线路就用它的名字，否则退回地址本身。
String schoolLabel(String baseUrl) {
  for (final SchoolProfile profile in knownSchools) {
    if (sameSchool(profile.baseUrl, baseUrl)) return profile.name;
  }
  return baseUrl;
}

/// 判断两个教务地址是否指向同一套系统（忽略末尾斜杠与 http/https 差异）。
///
/// 换校后旧的 Cookie 快照必须丢弃：快照是跟主机绑定的，且 `CookieStore.import`
/// 会用快照里的 baseUrl 覆盖当前配置。
bool sameSchool(String a, String b) {
  String key(String value) {
    var text = value.trim().toLowerCase();
    if (text.endsWith('/')) text = text.substring(0, text.length - 1);
    text = text.replaceFirst(RegExp(r'^https?://'), '');
    return text;
  }

  return key(a) == key(b);
}
