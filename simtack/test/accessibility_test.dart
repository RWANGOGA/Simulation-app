import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simtack/core/accessibility/accessibility_controller.dart';
import 'package:simtack/features/settings/ui/accessibility_settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AccessibilityController', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults to normal text and system theme when nothing saved', () async {
      final controller = await AccessibilityController.load();
      expect(controller.fontScale, 1.0);
      expect(controller.themeMode, ThemeMode.system);
    });

    test('persists and restores both settings across loads', () async {
      final first = await AccessibilityController.load();
      await first.setFontScale(1.3);
      await first.setThemeMode(ThemeMode.dark);

      final second = await AccessibilityController.load();
      expect(second.fontScale, 1.3);
      expect(second.themeMode, ThemeMode.dark);
    });

    test('ignores corrupt / out-of-range saved values', () async {
      SharedPreferences.setMockInitialValues({
        'a11y_font_scale': 42.0,
        'a11y_theme_mode': 'not-a-mode',
      });
      final controller = await AccessibilityController.load();
      expect(controller.fontScale, 1.0);
      expect(controller.themeMode, ThemeMode.system);
    });

    test('increase/decrease step through the named options', () async {
      final controller = await AccessibilityController.load();
      expect(controller.fontScale, 1.0);

      await controller.increaseFontScale();
      expect(controller.fontScale, 1.3);
      await controller.increaseFontScale();
      expect(controller.fontScale, 1.6);
      // Capped at the biggest option.
      await controller.increaseFontScale();
      expect(controller.fontScale, 1.6);

      await controller.decreaseFontScale();
      expect(controller.fontScale, 1.3);
      await controller.decreaseFontScale();
      await controller.decreaseFontScale();
      expect(controller.fontScale, 0.85);
      // Floored at the smallest option.
      await controller.decreaseFontScale();
      expect(controller.fontScale, 0.85);
    });

    test('notifies listeners when a setting changes', () async {
      final controller = await AccessibilityController.load();
      var notifications = 0;
      controller.addListener(() => notifications++);

      await controller.setFontScale(1.3);
      await controller.setThemeMode(ThemeMode.light);
      // No notification when the value is unchanged.
      await controller.setFontScale(1.3);
      expect(notifications, 2);
    });
  });

  group('AccessibilitySettingsScreen', () {
    Widget _wrap(AccessibilityController controller) {
      return A11yScope(
        controller: controller,
        child: const MaterialApp(home: AccessibilitySettingsScreen()),
      );
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('tapping a text-size chip updates the controller', (tester) async {
      final controller = await AccessibilityController.load();
      await tester.pumpWidget(_wrap(controller));

      expect(controller.fontScale, 1.0);
      await tester.tap(find.text('Large'));
      await tester.pumpAndSettle();
      expect(controller.fontScale, 1.3);

      await tester.tap(find.text('Small'));
      await tester.pumpAndSettle();
      expect(controller.fontScale, 0.85);
    });

    testWidgets('A+/A- buttons enlarge and reduce text', (tester) async {
      final controller = await AccessibilityController.load();
      await tester.pumpWidget(_wrap(controller));

      await tester.tap(find.byTooltip('Enlarge text size'));
      await tester.pumpAndSettle();
      expect(controller.fontScale, 1.3);

      await tester.tap(find.byTooltip('Reduce text size'));
      await tester.pumpAndSettle();
      expect(controller.fontScale, 1.0);
    });

    testWidgets('choosing Dark switches the theme mode', (tester) async {
      final controller = await AccessibilityController.load();
      await tester.pumpWidget(_wrap(controller));

      expect(controller.themeMode, ThemeMode.system);
      await tester.tap(find.text('Dark'));
      await tester.pumpAndSettle();
      expect(controller.themeMode, ThemeMode.dark);

      await tester.tap(find.text('Light'));
      await tester.pumpAndSettle();
      expect(controller.themeMode, ThemeMode.light);
    });
  });
}
