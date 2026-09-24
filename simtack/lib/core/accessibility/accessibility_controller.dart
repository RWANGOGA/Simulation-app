import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// App-wide accessibility preferences: how big text renders and whether
/// the app follows the light theme, the dark theme, or the device.
///
/// Persisted in SharedPreferences so a patient who needs large text keeps
/// it across launches. Listenable so the root MaterialApp rebuilds the
/// moment a setting changes.
class AccessibilityController extends ChangeNotifier {
  static const _fontScaleKey = 'a11y_font_scale';
  static const _themeModeKey = 'a11y_theme_mode';

  /// Named steps instead of a free slider — easier targets to tap and a
  /// predictable set of sizes for clinical users.
  static const fontScaleOptions = <double>[0.85, 1.0, 1.3, 1.6];

  double _fontScale = 1.0;
  ThemeMode _themeMode = ThemeMode.system;

  double get fontScale => _fontScale;
  ThemeMode get themeMode => _themeMode;

  /// Loads saved preferences; falls back to defaults (normal text,
  /// follow device) when nothing was saved yet or a value is corrupt.
  static Future<AccessibilityController> load() async {
    final controller = AccessibilityController();
    try {
      final prefs = await SharedPreferences.getInstance();
      final scale = prefs.getDouble(_fontScaleKey);
      if (scale != null && scale >= 0.5 && scale <= 3.0) {
        controller._fontScale = scale;
      }
      final mode = prefs.getString(_themeModeKey);
      if (mode != null) {
        controller._themeMode = ThemeMode.values.firstWhere(
          (m) => m.name == mode,
          orElse: () => ThemeMode.system,
        );
      }
    } catch (_) {
      // Storage unavailable (e.g. first web paint) — keep defaults.
    }
    return controller;
  }

  Future<void> setFontScale(double scale) async {
    final clamped = scale.clamp(0.5, 3.0);
    if (clamped == _fontScale) return;
    _fontScale = clamped;
    notifyListeners();
    await _persistDouble(_fontScaleKey, clamped);
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    if (mode == _themeMode) return;
    _themeMode = mode;
    notifyListeners();
    await _persistString(_themeModeKey, mode.name);
  }

  /// One tap larger, capped at the biggest option.
  Future<void> increaseFontScale() async {
    final index = fontScaleOptions.indexWhere((s) => s > _fontScale);
    await setFontScale(
      index == -1 ? fontScaleOptions.last : fontScaleOptions[index],
    );
  }

  /// One tap smaller, floored at the smallest option.
  Future<void> decreaseFontScale() async {
    final index = fontScaleOptions.lastIndexWhere((s) => s < _fontScale);
    await setFontScale(
      index == -1 ? fontScaleOptions.first : fontScaleOptions[index],
    );
  }

  Future<void> _persistDouble(String key, double value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(key, value);
    } catch (_) {}
  }

  Future<void> _persistString(String key, String value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, value);
    } catch (_) {}
  }
}
