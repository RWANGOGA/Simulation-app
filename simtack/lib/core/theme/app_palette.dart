import 'package:flutter/material.dart';

/// Brightness-aware palette for the app's recurring slate tones. Every
/// surface/text/border color resolves through these helpers against the
/// ambient theme brightness, so toggling dark mode repaints the whole app.
///
/// Brand accents (purple 0xFF6D28D9, risk reds/ambers/greens) are NOT
/// here on purpose — they read well on both backgrounds and carry
/// clinical meaning, so they stay constant.
class AppPalette {
  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// Full-screen background (was 0xFFF8FAFC light).
  static Color scaffold(BuildContext context) =>
      _isDark(context) ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

  /// Card / panel surface (was Colors.white).
  static Color surface(BuildContext context) =>
      _isDark(context) ? const Color(0xFF1E293B) : Colors.white;

  /// Subtle fill for chips, tracks and dividers (was 0xFFF1F5F9).
  static Color subtleFill(BuildContext context) =>
      _isDark(context) ? const Color(0xFF334155) : const Color(0xFFF1F5F9);

  /// Headings / primary text (was 0xFF1E293B).
  static Color textPrimary(BuildContext context) =>
      _isDark(context) ? const Color(0xFFF1F5F9) : const Color(0xFF1E293B);

  /// Body / secondary text (was 0xFF334155).
  static Color textSecondary(BuildContext context) =>
      _isDark(context) ? const Color(0xFFCBD5E1) : const Color(0xFF334155);

  /// Captions and de-emphasized text (was 0xFF64748B).
  static Color textMuted(BuildContext context) =>
      _isDark(context) ? const Color(0xFF94A3B8) : const Color(0xFF64748B);

  /// Card and field borders (was 0xFFE2E8F0).
  static Color border(BuildContext context) =>
      _isDark(context) ? const Color(0xFF334155) : const Color(0xFFE2E8F0);

  /// Text field fill (was 0xFFF8FAFC inputs on white cards).
  static Color inputFill(BuildContext context) =>
      _isDark(context) ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC);

  /// Placeholder / disabled text.
  static Color textDisabled(BuildContext context) =>
      _isDark(context) ? const Color(0xFF64748B) : const Color(0xFF94A3B8);
}
