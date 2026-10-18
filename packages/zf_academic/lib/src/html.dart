/// 轻量 HTML 取值。
///
/// 为了**零依赖**（不引入 html 解析包），这里用一组针对性的扫描函数替代完整 DOM，
/// 覆盖新正方登录页与菜单页真正用到的那几类结构：隐藏域、验证码控件、表单字段、
/// 身份信息、学期下拉框。
///
/// 只做"读"：绝不执行学校页面的 JavaScript。
library;

/// 一个起始标签的扫描结果。
class TagMatch {
  /// 小写标签名。
  final String tag;

  /// 属性表（键为小写；无值属性为空串）。
  final Map<String, String> attrs;

  /// 完整起始标签文本。
  final String raw;

  /// 起始标签在源串中的下标。
  final int start;

  /// 起始标签结束（`>` 之后）的下标。
  final int endOfStartTag;

  const TagMatch({
    required this.tag,
    required this.attrs,
    required this.raw,
    required this.start,
    required this.endOfStartTag,
  });
}

const Set<String> _voidTags = <String>{
  'area',
  'base',
  'br',
  'col',
  'embed',
  'hr',
  'img',
  'input',
  'link',
  'meta',
  'param',
  'source',
  'track',
  'wbr',
};

/// 取第一个元素，空则 null（dart:core 没有 firstOrNull）。
T? _firstOrNull<T>(Iterable<T> items) {
  for (final item in items) {
    return item;
  }
  return null;
}

// `\x22` 是双引号：Dart raw string 里不能写 `\"`（raw string 不转义分隔符）。
final RegExp _tagPattern = RegExp(
  r"<([a-zA-Z][a-zA-Z0-9-]*)((?:\x22[^\x22]*\x22|'[^']*'|[^>\x22'])*)>",
);
final RegExp _attrPattern = RegExp(
  r"([^\s\x22'<>/=]+)(?:\s*=\s*(?:\x22([^\x22]*)\x22|'([^']*)'|([^\s\x22'<>`=]+)))?",
);

Map<String, String> _parseAttributes(String attrRaw) {
  final attrs = <String, String>{};
  for (final match in _attrPattern.allMatches(attrRaw)) {
    final name = (match.group(1) ?? '').toLowerCase();
    if (name == '/' || name.isEmpty) continue;
    attrs[name] = match.group(2) ?? match.group(3) ?? match.group(4) ?? '';
  }
  return attrs;
}

/// 按文档顺序列出所有起始标签。
List<TagMatch> allTags(String html) {
  final result = <TagMatch>[];
  for (final match in _tagPattern.allMatches(html)) {
    final raw = match.group(0) ?? '';
    final tag = (match.group(1) ?? '').toLowerCase();
    if (raw.startsWith('</') || tag == '!doctype') continue;
    final start = match.start;
    result.add(TagMatch(
      tag: tag,
      attrs: _parseAttributes(match.group(2) ?? ''),
      raw: raw,
      start: start,
      endOfStartTag: start + raw.length,
    ));
  }
  return result;
}

bool isVoid(String tag) => _voidTags.contains(tag);

/// 元素的结束标签下标；自闭合或未闭合时返回 -1。
int closingIndex(String html, TagMatch element) {
  if (isVoid(element.tag) || element.raw.endsWith('/>')) return -1;
  final pattern = RegExp('</${element.tag}\\s*>', caseSensitive: false);
  final found = pattern.firstMatch(html.substring(element.endOfStartTag));
  return found == null ? -1 : element.endOfStartTag + found.start;
}

String innerOf(String html, TagMatch element) {
  final end = closingIndex(html, element);
  return end < 0 ? '' : html.substring(element.endOfStartTag, end);
}

String decodeEntities(String text) {
  return text
      .replaceAll(RegExp(r'&nbsp;?', caseSensitive: false), ' ')
      .replaceAll(RegExp('&lt;', caseSensitive: false), '<')
      .replaceAll(RegExp('&gt;', caseSensitive: false), '>')
      .replaceAll(RegExp('&quot;', caseSensitive: false), '"')
      .replaceAll(RegExp(r'&#39;|&apos;', caseSensitive: false), "'")
      .replaceAllMapped(
        RegExp(r'&#x([0-9a-f]+);', caseSensitive: false),
        (match) => String.fromCharCode(int.parse(match.group(1)!, radix: 16)),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (match) => String.fromCharCode(int.parse(match.group(1)!)),
      )
      .replaceAll(RegExp('&amp;', caseSensitive: false), '&');
}

/// 去标签取纯文本，并归一空白。
String stripTags(String html) {
  final withoutMarkup = html
      .replaceAll(
          RegExp(r'<script[\s\S]*?</script\s*>', caseSensitive: false), ' ')
      .replaceAll(
          RegExp(r'<style[\s\S]*?</style\s*>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ')
      .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
      .replaceAll(RegExp(r'<[^>]*>'), ' ');
  return decodeEntities(withoutMarkup).replaceAll(RegExp(r'\s+'), ' ').trim();
}

String textOf(String html, TagMatch element) =>
    stripTags(innerOf(html, element));

/// class 判定按 Jsoup 语义大小写不敏感（`.infoContentTitle` 与 `.infocontenttitle` 等价）。
bool hasClass(Map<String, String> attrs, String token) {
  final wanted = token.toLowerCase();
  return (attrs['class'] ?? '')
      .split(RegExp(r'\s+'))
      .any((part) => part.toLowerCase() == wanted);
}

String elementText(String html, TagMatch element) => element.tag == 'input'
    ? (element.attrs['value'] ?? '')
    : textOf(html, element);

/// 表单范围内允许提交的字段值，语义与 Jsoup 版 `formFields` 对齐。
Map<String, String> formValues(String scope) {
  final values = <String, String>{};
  for (final element in allTags(scope)) {
    final name = element.attrs['name'];
    if (name == null || name.isEmpty || element.attrs.containsKey('disabled')) {
      continue;
    }
    if (element.tag == 'input') {
      final type = (element.attrs['type'] ?? 'text').toLowerCase();
      if (const {'submit', 'button', 'reset', 'file', 'image'}.contains(type)) {
        continue;
      }
      if ((type == 'checkbox' || type == 'radio') &&
          !element.attrs.containsKey('checked')) {
        continue;
      }
      values[name] = element.attrs['value'] ?? '';
    } else if (element.tag == 'select') {
      final inner = innerOf(scope, element);
      final options =
          allTags(inner).where((node) => node.tag == 'option').toList();
      final chosen = _firstOrNull(
              options.where((node) => node.attrs.containsKey('selected'))) ??
          (options.isNotEmpty ? options.first : null);
      if (chosen != null) {
        values[name] =
            chosen.attrs['value'] ?? stripTags(innerOf(inner, chosen));
      }
    } else if (element.tag == 'textarea') {
      values[name] = textOf(scope, element);
    }
  }
  return values;
}

/// 页面里所有 `type=hidden` 输入框（不限是否在 form 内）。
Map<String, String> hiddenFields(String html) {
  final values = <String, String>{};
  for (final element in allTags(html)) {
    if (element.tag != 'input') continue;
    if ((element.attrs['type'] ?? '').toLowerCase() != 'hidden') continue;
    final name = element.attrs['name'];
    if (name != null && name.isNotEmpty) {
      values[name] = element.attrs['value'] ?? '';
    }
  }
  return values;
}

TagMatch? findInputByName(String html, List<String> names) {
  final wanted = names.map((name) => name.toLowerCase()).toSet();
  return _firstOrNull(allTags(html).where((element) {
    final name = element.attrs['name'] ?? '';
    return element.tag == 'input' && wanted.contains(name.toLowerCase());
  }));
}

TagMatch? findById(String html, String id) {
  final lower = id.toLowerCase();
  return _firstOrNull(allTags(html)
      .where((element) => (element.attrs['id'] ?? '').toLowerCase() == lower));
}

List<TagMatch> findByClass(String html, String token) {
  return allTags(html)
      .where((element) => hasClass(element.attrs, token))
      .toList();
}

bool hasPasswordInput(String html) {
  return allTags(html).any((element) =>
      element.tag == 'input' &&
      ((element.attrs['type'] ?? '').toLowerCase() == 'password' ||
          const {'mm', 'textbox2'}
              .contains((element.attrs['name'] ?? '').toLowerCase())));
}

/// 是否为登录页。与原项目 `AcademicHtml.isLoginPage` 等价：密码框、跳转脚本、
/// 或"空 body + 直接跳 authserver/login 的脚本"三种特征取其一。
bool isLoginPage(String html) {
  if (hasPasswordInput(html)) return true;
  final locationPattern = RegExp(
    r"(?:top\.|window\.|parent\.)?location(?:\.href)?\s*=\s*['\x22][^'\x22]*(?:login_slogin|default2\.aspx|LoginToXk)",
    caseSensitive: false,
  );
  if (locationPattern.hasMatch(html)) return true;
  final stripped = html
      .replaceAll(
          RegExp(r'<script[\s\S]*?</script\s*>', caseSensitive: false), ' ')
      .replaceAll(
          RegExp(r'<style[\s\S]*?</style\s*>', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'<!--[\s\S]*?-->'), ' ');
  if (stripTags(stripped) != '') return false;
  for (final match
      in RegExp(r'<script[^>]*>([\s\S]*?)</script\s*>', caseSensitive: false)
          .allMatches(html)) {
    final code = match.group(1) ?? '';
    if (RegExp(
      r"""^\s*(?:(?:top|window|parent)\.)?location(?:\.href)?\s*=\s*['\x22]https?://[^'\x22\s]+/authserver/login(?:\?[^'\x22]*)?['\x22]\s*;?\s*$""",
    ).hasMatch(code)) {
      return true;
    }
  }
  return false;
}

class LoginForm {
  final Map<String, String> attrs;
  final String inner;

  const LoginForm({required this.attrs, required this.inner});
}

/// 页面里承载登录提交的表单：优先"含 execution + password"，其次"含密码框"，最后第一个 form。
LoginForm? loginForm(String html) {
  final forms =
      allTags(html).where((element) => element.tag == 'form').toList();
  if (forms.isEmpty) return null;
  bool containsPassword(TagMatch form) => hasPasswordInput(innerOf(html, form));
  bool containsExecution(TagMatch form) =>
      allTags(innerOf(html, form)).any((element) =>
          element.tag == 'input' && element.attrs['name'] == 'execution');
  final chosen = _firstOrNull(forms.where(
          (form) => containsExecution(form) && containsPassword(form))) ??
      _firstOrNull(forms.where(containsPassword)) ??
      forms.first;
  return LoginForm(attrs: chosen.attrs, inner: innerOf(html, chosen));
}

class CaptchaControl {
  /// 提交验证码的字段名，如 `yzm`。
  final String fieldName;

  /// 验证码图片地址（可能是相对地址，由调用方按页面地址解析）。
  final String imageSrc;

  const CaptchaControl({required this.fieldName, required this.imageSrc});
}

class CaptchaScan {
  final CaptchaControl? control;
  final String? imageOnly;
  final String? fieldOnly;

  const CaptchaScan({this.control, this.imageOnly, this.fieldOnly});
}

/// 找验证码控件。语义与原项目一致：只有图片、只有输入框、或两者都没有时返回空 / 标记，
/// 由上层决定走 CAPTCHA_REQUIRED 还是 WEB_LOGIN_REQUIRED。
CaptchaScan detectCaptcha(
  String html, {
  List<String> fieldNames = const ['RANDOMCODE', 'yzm', 'authcode', 'captcha'],
}) {
  final form = loginForm(html);
  final scope = form == null ? html : form.inner;
  final wanted = fieldNames.map((name) => name.toLowerCase()).toSet();
  final field = _firstOrNull(allTags(scope).where((element) {
    final name = element.attrs['name'] ?? '';
    return element.tag == 'input' &&
        wanted.contains(name.toLowerCase()) &&
        !element.attrs.containsKey('disabled');
  }));
  final image = _firstOrNull(allTags(scope).where((element) {
    final id = element.attrs['id'] ?? '';
    final src = element.attrs['src'] ?? '';
    return element.tag == 'img' &&
        (RegExp(r'^(icode|safecodeimg)$', caseSensitive: false).hasMatch(id) ||
            RegExp(r'checkcode|verifycode|yzm|captcha|kaptcha',
                    caseSensitive: false)
                .hasMatch(src));
  }));
  if (field != null && image != null) {
    return CaptchaScan(
      control: CaptchaControl(
        fieldName: field.attrs['name']!,
        imageSrc: image.attrs['src'] ?? '',
      ),
    );
  }
  if (image != null) return CaptchaScan(imageOnly: image.attrs['src'] ?? '');
  if (field != null) return CaptchaScan(fieldOnly: field.attrs['name']!);
  return const CaptchaScan();
}

class Identity {
  final String studentName;
  final String studentId;

  const Identity({required this.studentName, required this.studentId});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Identity &&
          runtimeType == other.runtimeType &&
          studentName == other.studentName &&
          studentId == other.studentId;

  @override
  int get hashCode => Object.hash(studentName, studentId);

  @override
  String toString() =>
      'Identity(studentName: $studentName, studentId: $studentId)';
}

/// 归一空白；文本源剥离"同学/学生/教师/老师"身份后缀。
///
/// 采用 plugin-sdk-v3 `schoolIdentity` 的语义：**后缀前必须空白**才算角色标记。
/// 主分支 Kotlin 版是无条件 removeSuffix，会把"合成学生"剪成"合成"；两个仓库的样本
/// 互相矛盾，本模块选择同时满足两者的口径（与 TS 版一致）。
String _cleanIdentityText(String raw, bool stripRoleSuffix) {
  final normalized =
      raw.replaceAll('\u00A0', ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (!stripRoleSuffix) return normalized;
  return normalized.replaceAll(RegExp(r'\s+(?:同学|学生|教师|老师)$'), '').trim();
}

/// 从首页 HTML 读学号/姓名。移植自原项目 `parseName()`：
/// `.infoContentTitle` 一类"姓名-学号"标题 → 姓名/学号输入框 → `.middletopdwxxtit` 标签对，
/// 兼容正方 v5 定制首页与"只有姓名没有学号"的变体。
Identity identity(String html) {
  if (isLoginPage(html)) return const Identity(studentName: '', studentId: '');
  final tags = allTags(html);

  for (final element in tags) {
    if (!const {'infoContentTitle', 'userInfo', 'user-info'}
        .any((token) => hasClass(element.attrs, token))) {
      continue;
    }
    // 修正 TS 版的捕获组遗漏：原正则只捕获了姓名，学号组缺失（恒为 undefined）。
    final match = RegExp(r'^(.+?)[-\[]([A-Za-z0-9]{6,})\]?$')
        .firstMatch(textOf(html, element).trim());
    if (match != null) {
      return Identity(
        studentName: (match.group(1) ?? '').trim(),
        studentId: match.group(2) ?? '',
      );
    }
  }

  final profile = <String, String>{};
  for (final label
      in tags.where((element) => hasClass(element.attrs, 'middletopdwxxtit'))) {
    final next = _nextSiblingElement(html, label);
    if (next == null || !hasClass(next.attrs, 'middletopdwxxcont')) continue;
    final key = textOf(html, label)
        .replaceAll(RegExp(r'\s+'), '')
        .replaceAll(RegExp(r'[:：]$'), '');
    profile[key] = textOf(html, next);
  }

  final nameSelectors = <bool Function(TagMatch)>[
    (element) => element.tag == 'input' && element.attrs['name'] == 'xm',
    (element) => hasClass(element.attrs, 'media-heading'),
    (element) => element.attrs['name'] == 'studentName',
    (element) => element.attrs['id'] == 'xhxm',
    (element) => hasClass(element.attrs, 'user-name'),
    (element) => element.attrs['id'] == 'studentName',
  ];
  var studentName = '';
  for (final predicate in nameSelectors) {
    final found = _firstOrNull(tags.where(predicate));
    if (found == null) continue;
    // input 的 value 是纯姓名，不做角色后缀剥离；文本节点可能带"学生/教师"标签。
    studentName =
        _cleanIdentityText(elementText(html, found), found.tag != 'input');
    if (studentName.isNotEmpty) break;
  }
  if (studentName.isEmpty) studentName = profile['学生姓名'] ?? '';

  final idSelectors = <bool Function(TagMatch)>[
    (element) => element.tag == 'input' && element.attrs['name'] == 'xh',
    (element) => element.tag == 'input' && element.attrs['name'] == 'studentId',
    (element) => element.attrs['id'] == 'studentId',
    (element) => element.attrs['id'] == 'sessionUserKey',
  ];
  var studentId = '';
  for (final predicate in idSelectors) {
    final found = _firstOrNull(tags.where(predicate));
    if (found == null) continue;
    studentId = elementText(html, found).trim();
    if (studentId.isNotEmpty) break;
  }
  if (studentId.isEmpty) studentId = (profile['学号'] ?? '').trim();

  return Identity(studentName: studentName.trim(), studentId: studentId.trim());
}

TagMatch? _nextSiblingElement(String html, TagMatch element) {
  final rest = html.substring(element.endOfStartTag);
  final next = _firstOrNull(allTags(rest));
  if (next == null) return null;
  return TagMatch(
    tag: next.tag,
    attrs: next.attrs,
    raw: next.raw,
    start: next.start + element.endOfStartTag,
    endOfStartTag: next.endOfStartTag + element.endOfStartTag,
  );
}

class SelectOptions {
  final String name;
  final List<({String value, String text})> options;

  const SelectOptions({required this.name, required this.options});
}

List<SelectOptions> selectOptions(String html, List<String> names) {
  final wanted = names.map((name) => name.toLowerCase()).toSet();
  final result = <SelectOptions>[];
  for (final element in allTags(html)) {
    if (element.tag != 'select') continue;
    final name = element.attrs['name'] ?? '';
    final tail = name.split('\$').last;
    if (!wanted.contains(tail.toLowerCase())) continue;
    final inner = innerOf(html, element);
    result.add(SelectOptions(
      name: name,
      options: allTags(inner)
          .where((node) =>
              node.tag == 'option' && !node.attrs.containsKey('disabled'))
          .map((node) => (
                value: node.attrs['value'] ?? '',
                text: stripTags(innerOf(inner, node)).isNotEmpty
                    ? stripTags(innerOf(inner, node))
                    : (node.attrs['value'] ?? ''),
              ))
          .toList(),
    ));
  }
  return result;
}

String selectedOptionText(String html, List<String> names) {
  final wanted = names.map((name) => name.toLowerCase()).toSet();
  for (final element in allTags(html)) {
    if (element.tag != 'select') continue;
    final tail = (element.attrs['name'] ?? '').split('\$').last;
    if (!wanted.contains(tail.toLowerCase())) continue;
    final inner = innerOf(html, element);
    final options =
        allTags(inner).where((node) => node.tag == 'option').toList();
    final chosen = _firstOrNull(
        options.where((node) => node.attrs.containsKey('selected')));
    if (chosen != null) {
      return chosen.attrs['value'] ?? stripTags(innerOf(inner, chosen));
    }
  }
  return '';
}
