/// 桌面小组件样式模型与偏好持久化 schema 14 测试。
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qustschedule/src/preferences_repository.dart';
import 'package:qustschedule/src/widget_style.dart';

void main() {
  group('DesktopWidgetStyle 预设、解耦与夹取', () {
    test('精选预设只更新色彩/透明度/圆角，保留密度、字号与内容开关', () {
      const customFields = DesktopWidgetStyle(
        fontScale: 1.10,
        density: WidgetDensity.compact,
        showHeader: false,
        showLocation: false,
        showTeacher: true,
        showTime: false,
        showExams: false,
        autoSwitchTomorrow: false,
        finishedCourseMode: FinishedCourseMode.hide,
        weekendMode: WeekendColumnMode.show,
      );

      final glass = customFields.applyPreset(WidgetStylePreset.frostedGlass);
      expect(glass.preset, WidgetStylePreset.frostedGlass);
      expect(glass.themeMode, WidgetThemeMode.system);
      expect(glass.backgroundOpacity, 0.75);
      expect(glass.cornerRadius, 22.0);
      // 密度与字号与预设完全解耦，套用预设绝不覆盖用户选择。
      expect(glass.density, WidgetDensity.compact);
      expect(glass.fontScale, 1.10);
      expect(glass.showHeader, isFalse);
      expect(glass.showLocation, isFalse);
      expect(glass.showExams, isFalse);
      expect(glass.autoSwitchTomorrow, isFalse);
      expect(glass.finishedCourseMode, FinishedCourseMode.hide);
      expect(glass.weekendMode, WeekendColumnMode.show);

      // 只改内容开关、信息密度或字号均不打断当前精选预设。
      final tweakedContent = glass.copyWith(
        showLocation: true,
        autoSwitchTomorrow: true,
        density: WidgetDensity.comfortable,
        fontScale: 0.90,
      );
      expect(tweakedContent.preset, WidgetStylePreset.frostedGlass);

      // 微调色彩/透明度/圆角时自动切到 custom。
      final tweakedOpacity = glass.copyWith(backgroundOpacity: 0.50);
      expect(tweakedOpacity.preset, WidgetStylePreset.custom);
      expect(tweakedOpacity.backgroundOpacity, 0.50);

      // 全部 5 套预设的不透明度均对齐 5% 滑块步进，且经 JSON 序列化往返无损。
      for (final spec in widgetStylePresets) {
        final pct = (spec.backgroundOpacity * 100).round();
        expect(pct % 5, 0, reason: '${spec.preset} 不透明度应为 5% 步进倍数');
        final applied = customFields.applyPreset(spec.preset);
        expect(applied.density, WidgetDensity.compact);
        final roundTrip = DesktopWidgetStyle.fromJson(
          jsonDecode(jsonEncode(applied.toJson())),
        );
        expect(roundTrip, applied);
      }

      // 预设与色彩主题文案不重名。
      expect(WidgetStylePreset.materialYou.label, '莫奈取色');
      expect(WidgetThemeMode.dynamic.label, '壁纸取色');
      expect(WeekendColumnMode.hide.label, '始终隐藏');
    });

    test('透明度、圆角、字号严格夹取到 75%~120% 等合法范围并兼容历史 JSON', () {
      expect(widgetMinFontScale, 0.75);
      expect(widgetMaxFontScale, 1.20);

      const style = DesktopWidgetStyle();
      final outOfBounds = style.copyWith(
        backgroundOpacity: 1.8,
        cornerRadius: 2.0,
        fontScale: 2.5,
      );
      expect(outOfBounds.backgroundOpacity, widgetMaxOpacity);
      expect(outOfBounds.cornerRadius, widgetMinCornerRadius);
      expect(outOfBounds.fontScale, 1.20);

      final lowBounds = style.copyWith(
        backgroundOpacity: -0.3,
        cornerRadius: 99.0,
        fontScale: 0.1,
      );
      expect(lowBounds.backgroundOpacity, widgetMinOpacity);
      expect(lowBounds.cornerRadius, widgetMaxCornerRadius);
      expect(lowBounds.fontScale, 0.75);

      // 旧版本 JSON 缺失 autoSwitchTomorrow 且含旧字号 0.60 时平稳迁移。
      final legacy = DesktopWidgetStyle.fromJson(<String, Object?>{
        'preset': 'frosted_glass',
        'themeMode': 'system',
        'backgroundOpacity': 0.78,
        'fontScale': 0.60,
      });
      expect(legacy.autoSwitchTomorrow, isTrue);
      expect(legacy.fontScale, 0.75);
      expect(legacy.backgroundOpacity, 0.78);

      // 畸形 JSON 中 preset 为非字符串时平稳回退默认值，不抛出 TypeError。
      final malformed = DesktopWidgetStyle.fromJson(<String, Object?>{
        'preset': 123,
        'themeMode': 456,
        'showHeader': 'yes',
      }, kind: DesktopWidgetKind.week);
      expect(malformed, DesktopWidgetStyle.defaultsFor(DesktopWidgetKind.week));
    });

    test('DesktopWidgetConfigSet 按类型独立保存、重置与 JSON 往返', () {
      var set = DesktopWidgetConfigSet.defaults();
      expect(set.styleOf(DesktopWidgetKind.week).showTeacher, isFalse);
      expect(set.styleOf(DesktopWidgetKind.today).showTeacher, isTrue);
      expect(set.styleOf(DesktopWidgetKind.today).autoSwitchTomorrow, isTrue);

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
