import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks the patient's chosen app language and whether they've accepted
/// the data-processing consent shown on the language & consent screen
/// (blueprint §1). Persisted in SharedPreferences: once consent is given,
/// the screen doesn't need to be shown again on future launches — same
/// "load once before first frame" pattern as AccessibilityController.
class LocaleController extends ChangeNotifier {
  static const _localeKey = 'onboarding_locale';
  static const _consentKey = 'onboarding_consent_given';

  /// The sign-language choice has no ARB locale of its own (there is no
  /// written "sl" translation — it selects sign-language *content*
  /// elsewhere in the app, not a text locale), so it's tracked separately
  /// from [locale] rather than stuffed into supportedLocales.
  static const signLanguageCode = 'sign';

  Locale? _locale;
  bool _isSignLanguage = false;
  bool _hasConsented = false;

  /// Null means "follow system" — only set once the patient actually
  /// picks English or Luganda.
  Locale? get locale => _locale;
  bool get isSignLanguage => _isSignLanguage;
  bool get hasConsented => _hasConsented;

  static Future<LocaleController> load() async {
    final controller = LocaleController();
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_localeKey);
      if (saved == signLanguageCode) {
        controller._isSignLanguage = true;
      } else if (saved != null && saved.isNotEmpty) {
        controller._locale = Locale(saved);
      }
      controller._hasConsented = prefs.getBool(_consentKey) ?? false;
    } catch (_) {
      // Storage unavailable (e.g. first web paint) — keep defaults.
    }
    return controller;
  }

  /// Records the patient's language choice and consent together — they're
  /// accepted from the same screen, in the same action.
  Future<void> setLanguageAndConsent({required String languageCode, required bool consented}) async {
    _isSignLanguage = languageCode == signLanguageCode;
    _locale = _isSignLanguage ? null : Locale(languageCode);
    _hasConsented = consented;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_localeKey, languageCode);
      await prefs.setBool(_consentKey, consented);
    } catch (_) {}
  }
}
