/// 界面回归测试公共构造器与断言辅助函数。
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/pages/home_shell.dart';
import 'package:qustschedule/pages/timetable_edit_page.dart';
import 'package:qustschedule/src/app_model.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/schedule_service.dart';
import 'package:zf_academic/zf_academic_io.dart';

import 'fake_backend.dart';

AppModel buildModel({FakeBackend? backend}) {
  final fake = backend ?? FakeBackend();
  return AppModel(
    service: ScheduleService(
      credentials: InMemoryCredentialStore(),
      cookieStorage: FakeSessionRepository(),
      backendFactory: (_) => fake,
      baseUrl: 'https://jw.example.edu.cn/jwglxt',
    ),
    preferences: Preferences.inMemory(),
    schoolBaseUrl: 'https://jw.example.edu.cn/jwglxt',
  );
}

Widget wrap(Widget child) => MaterialApp(home: child);

/// 读出外壳横向轨道当前的**位置**（0 = 课表页正中，1 = 设置页正中）。
///
/// 外壳改成水平平移后，页面的"可见程度"不再由透明度表示，而是由它在
/// 横向轨道上的位置表示：位置 0 就是课表页完全在屏内，1 就是设置页完全在屏内。
/// 这里直接读实际变换后的偏移量，比断言 widget 树可靠：卡在半页时位置是
/// 0.5 这样的中间值。
double shellPagePosition(WidgetTester tester) {
  final Transform transform = tester.widget<Transform>(
    find.byKey(const ValueKey<String>('shell-page-0')),
  );
  final double width = tester.getSize(find.byType(HomeShell)).width;
  if (width <= 0) return 0;
  return -transform.transform.getTranslation().x / width;
}

/// 外壳当前停在第几页（0 = 课表，1 = 设置）。
///
/// 位置离整页足够近才算停稳：停在半页（0.5 附近）说明动画被打断了。
int shellCurrentPage(WidgetTester tester) {
  final double position = shellPagePosition(tester);
  return (position - position.round()).abs() < 0.02 ? position.round() : -1;
}

AnimatedOpacity todayFab(WidgetTester tester) => tester.widget<AnimatedOpacity>(
  find.byKey(const ValueKey<String>('today-fab')),
);

/// 用 push 的方式打开编辑页：保存后 pop 有上一页可回，不会弹到根路由之外。
Future<void> pushEditor(WidgetTester tester, AppModel model, String id) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      TimetableEditPage(model: model, timetableId: id),
                ),
              ),
              child: const Text('打开编辑'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开编辑'));
  await tester.pumpAndSettle();
}

/// 第 1-2 周与第 15-16 周各一门课：中间的第 8 周是空的，用来测周过滤。
Schedule sparseSchedule() => const Schedule(
  termId: '2026-2027-1',
  maxWeeks: 16,
  entries: <ScheduleEntry>[
    ScheduleEntry(
      id: 'early',
      name: '期初课',
      teacher: '张老师',
      location: 'M1-101',
      day: 1,
      startPeriod: 1,
      endPeriod: 2,
      weeks: <int>[1, 2],
    ),
    ScheduleEntry(
      id: 'late',
      name: '期末课',
      day: 3,
      startPeriod: 5,
      endPeriod: 6,
      weeks: <int>[15, 16],
    ),
  ],
);
