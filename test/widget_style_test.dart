/// 桌面小组件样式模型与偏好持久化 schema 14 测试。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/widget_style.dart';

void main() {
  group('DesktopWidgetStyle 预设与夹取', () {
    test('精选预设套用只更新视觉参数并保留内容字段开关', () {
      const customFields = DesktopWidgetStyle(
        showHeader: false,
        showLocation: false,
        showTeacher: true,
        showTime: false,
        showExams: false,
        finishedCourseMode: FinishedCourseMode.hide,
        weekendMode: WeekendColumnMode.show,
      );

      final glass = customFields.applyPreset(WidgetStylePreset.frostedGlass);
      expect(glass.preset, WidgetStylePreset.frostedGlass);
      expect(glass.themeMode, WidgetThemeMode.system);
      expect(glass.backgroundOpacity, 0.78);
      expect(glass.cornerRadius, 22.0);
      expect(glass.showHeader, isFalse);
      expect(glass.showLocation, isFalse);
      expect(glass.showExams, isFalse);
      expect(glass.finishedCourseMode, FinishedCourseMode.hide);
      expect(glass.weekendMode, WeekendColumnMode.show);

      // 微调视觉滑块自动切到 custom；只改内容开关则保持原预设。
      final tweakedContent = glass.copyWith(showLocation: true);
      expect(tweakedContent.preset, WidgetStylePreset.frostedGlass);

      final tweakedOpacity = glass.copyWith(backgroundOpacity: 0.52);
      expect(tweakedOpacity.preset, WidgetStylePreset.custom);
      expect(tweakedOpacity.backgroundOpacity, 0.52);

      // 全部 5 套预设经 JSON 序列化往返后必须与原样式完全一致。
      for (final spec in widgetStylePresets) {
        final applied = customFields.applyPreset(spec.preset);
        final roundTrip = DesktopWidgetStyle.fromJson(
          jsonDecode(jsonEncode(applied.toJson())),
        );
        expect(roundTrip, applied);
      }
    });

    test('透明度、圆角、字号严格夹取到合法范围并量化', () {
      const style = DesktopWidgetStyle();
      final outOfBounds = style.copyWith(
        backgroundOpacity: 1.8,
        cornerRadius: 2.0,
        fontScale: 2.5,
      );
      expect(outOfBounds.backgroundOpacity, widgetMaxOpacity);
      expect(outOfBounds.cornerRadius, widgetMinCornerRadius);
      expect(outOfBounds.fontScale, widgetMaxFontScale);

      final lowBounds = style.copyWith(
        backgroundOpacity: -0.3,
        cornerRadius: 99.0,
        fontScale: 0.1,
      );
      expect(lowBounds.backgroundOpacity, widgetMinOpacity);
      expect(lowBounds.cornerRadius, widgetMaxCornerRadius);
      expect(lowBounds.fontScale, widgetMinFontScale);
    });

    test('DesktopWidgetConfigSet 按类型独立保存、重置与 JSON 往返', () {
      var set = DesktopWidgetConfigSet.defaults();
      expect(set.styleOf(DesktopWidgetKind.week).showTeacher, isFalse);
      expect(set.styleOf(DesktopWidgetKind.today).showTeacher, isTrue);

      final darkNext = set
          .styleOf(DesktopWidgetKind.next)
          .applyPreset(WidgetStylePreset.pureTransparent);
      set = set.withStyle(DesktopWidgetKind.next, darkNext);

      expect(
        set.styleOf(DesktopWidgetKind.today).preset,
        WidgetStylePreset.minimalWhite,
      );
      expect(set.styleOf(DesktopWidgetKind.next).backgroundOpacity, 0.0);

      final decoded = DesktopWidgetConfigSet.fromJson(
        jsonDecode(jsonEncode(set.toJson())),
      );
      expect(decoded, set);

      final reset = set.resetKind(DesktopWidgetKind.next);
      expect(
        reset.styleOf(DesktopWidgetKind.next),
        DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.next),
      );
    });
  });

  group('Preferences schema 14 迁移与持久化', () {
    test('读取 schema 13 旧配置时平稳回退为默认小组件样式', () {
      final legacyJson = jsonEncode(<String, Object?>{
        'schema': 13,
        'showTeacher': false,
      });
      final prefs = Preferences.decode(legacyJson);
      expect(prefs.showTeacher, isFalse);
      expect(prefs.widgetConfig, DesktopWidgetConfigSet.defaults());
    });

    test('修改单个小组件样式会写入序列化结果且互不覆盖', () async {
      final prefs = Preferences.inMemory();
      final styled = prefs
          .widgetStyleOf(DesktopWidgetKind.week)
          .applyPreset(WidgetStylePreset.darkNight)
          .copyWith(weekendMode: WeekendColumnMode.show);
      await prefs.setWidgetStyle(DesktopWidgetKind.week, styled);

      expect(
        prefs.widgetStyleOf(DesktopWidgetKind.week).themeMode,
        WidgetThemeMode.dark,
      );
      expect(
        prefs.widgetStyleOf(DesktopWidgetKind.week).weekendMode,
        WeekendColumnMode.show,
      );
      expect(
        prefs.widgetStyleOf(DesktopWidgetKind.today),
        DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.today),
      );
    });
  });
}
