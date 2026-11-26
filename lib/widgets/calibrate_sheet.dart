/// 学期周次校准底部弹窗：选择"本周实际是第几周"并反推开学日落盘。
library;

import 'package:flutter/material.dart';

import '../src/app_model.dart';
import 'time_wheel_picker.dart';

/// 校准：'本周实际是第几周' → 滚轮选择并反推开学日落盘。
Future<void> showCalibrateSheet(BuildContext context, AppModel model) async {
  final picked = await showWeekCalibrationWheel(
    context,
    currentWeek: model.currentWeekOfToday,
    maxWeek: model.maxWeek > 30 ? model.maxWeek : 30,
  );
  if (picked == null) return;
  if (picked == 0) {
    await model.resetCalendar();
  } else {
    await model.calibrateCurrentWeek(picked);
  }
}
