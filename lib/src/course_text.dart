/// 课表文本的派生规则：**课表格子与课程提醒必须共用同一套**。
///
/// 教务给的地点常常是「青岛科技大学 崂山校区 明德楼 201」这种长串，
/// 格子里只放得下房间号；如果通知里贴原串，就会出现"同一节课两处地点不一样"。
library;

/// 从完整地点里取出房间号（课表格子与通知都用它）。
///
/// 规则（与历史实现保持一致，改之前先看测试）：
///  1. 去首尾空白；
///  2. 有多段（空白分隔）时只留**最后一段**：`高密校区 M1-239` → `M1-239`；
///  3. 单段里带「xx校区」前缀时截掉前缀：`崂山校区3教201` → `3教201`；
///  4. 截完为空则退回原串（去空白），全空则返回空串。
String roomOnly(String location) {
  var text = location.trim();
  if (text.isEmpty) return text;

  final lastSpace = text.lastIndexOf(RegExp(r'\s'));
  if (lastSpace >= 0 && lastSpace < text.length - 1) {
    text = text.substring(lastSpace + 1).trim();
  }

  final campus = RegExp(r'^.*?校区').firstMatch(text);
  if (campus != null) {
    final rest = text.substring(campus.end).trim();
    if (rest.isNotEmpty) text = rest;
  }

  return text.isEmpty ? location.trim() : text;
}
