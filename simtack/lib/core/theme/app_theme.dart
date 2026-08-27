import 'package:flutter/material.dart';

class AppTheme {
  // Text styles intentionally carry no color: they inherit from the
  // active ColorScheme so the same TextTheme works in light AND dark
  // mode (screens resolve their own tones via AppPalette).
  static const _textTheme = TextTheme(
    displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
    headlineLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
    titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16),
  );

  static ThemeData get lightTheme => _build(Brightness.light);

  static ThemeData get darkTheme => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    return ThemeData(
      useMaterial3: true,
      // Sets the default font for every Text widget in the app that
      // doesn't specify its own fontFamily — which is nearly all of them,
      // since screens build their TextStyles with fontSize/color only.
      // Was the platform default (Roboto) before; Inter reads noticeably
      // better at small sizes, which matters for a low-literacy audience.
      fontFamily: 'Inter',
      // Blueprint Primary: Deep Purple
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF6D28D9),
        brightness: brightness,
      ),
      scaffoldBackgroundColor:
          brightness == Brightness.dark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      textTheme: _textTheme,
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6D28D9), // Purple button
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
      // Shared style for secondary actions (Save Draft, Share, View
      // History, ...) so every screen reads "secondary action" the same way.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF6D28D9),
          side: const BorderSide(color: Color(0xFF6D28D9), width: 1.5),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }
}