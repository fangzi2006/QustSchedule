import 'package:test/test.dart';
import 'package:zf_academic/src/html.dart';

void main() {
  group('HTML 标签闭合与多层嵌套', () {
    test('closingIndex / innerOf 正确匹配多层嵌套同名标签', () {
      const html = '<div id="outer"><div class="inner">'
          '<span>里层</span></div>尾段文字</div><div>兄弟</div>';
      final outer = findById(html, 'outer')!;
      expect(
          innerOf(html, outer), '<div class="inner"><span>里层</span></div>尾段文字');
      expect(textOf(html, outer), '里层 尾段文字');

      final inner = findByClass(html, 'inner').single;
      expect(innerOf(html, inner), '<span>里层</span>');
    });

    test('嵌套中混入自闭合同名标签时不破坏层级计数', () {
      const html = '<div id="wrap"><div class="spacer"/><p>正文</p></div>';
      final wrap = findById(html, 'wrap')!;
      expect(innerOf(html, wrap), '<div class="spacer"/><p>正文</p>');
      expect(textOf(html, wrap), '正文');
    });

    test('属性引号内的假标签与闭合标签不干扰匹配', () {
      const html = '<div id="box" data-tip="</div><div class=fake>">'
          "<span title='</div>'>安全</span>"
          '</div>';
      final box = findById(html, 'box')!;
      expect(innerOf(html, box), "<span title='</div>'>安全</span>");
      expect(textOf(html, box), '安全');
    });

    test('注释、script 与 style 中的假闭合标签不影响外层闭合', () {
      const html = '<div id="panel">'
          '<!-- </div><div> -->'
          '<style>.a::before { content: "</div>"; }</style>'
          '<script type="text/javascript">const x = "</div>";</script>'
          '<span>真实文本</span>'
          '</div>';
      final panel = findById(html, 'panel')!;
      expect(textOf(html, panel), '真实文本');
    });

    test('自闭合、void 标签与未闭合标签返回 -1 / 空串', () {
      const html = '<input id="i" value="1"><div id="open"><span>未关';
      final input = findById(html, 'i')!;
      expect(closingIndex(html, input), -1);
      expect(innerOf(html, input), '');

      final open = findById(html, 'open')!;
      expect(closingIndex(html, open), -1);
      expect(innerOf(html, open), '');
    });

    test('嵌套 div 下的用户信息标题可正确提取姓名与学号', () {
      const html = '<div class="user-info">'
          '<div class="avatar"><img src="a.png"></div>'
          '<div>张三-2024010101</div>'
          '</div>';
      final info = identity(html);
      expect(info.studentName, '张三');
      expect(info.studentId, '2024010101');
    });
  });
}
