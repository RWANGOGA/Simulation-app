import 'package:flutter/material.dart';

/// One selectable language on the consent screen.
///
/// [flutterCode] is persisted by [LocaleController] and matches ARB `@@locale`.
/// [sunbirdCode] is the ISO 639-3 code Sunbird's `/tasks/translate` expects
/// (used in a later step — the backend proxy). Sign language has neither
/// an ARB file nor a Sunbird code.
class AppLanguage {
  final String flutterCode;
  final String? sunbirdCode;
  final IconData icon;

  const AppLanguage({
    required this.flutterCode,
    required this.icon,
    this.sunbirdCode,
  });

  bool get isSignLanguage => flutterCode == AppLanguages.signLanguageCode;
}

/// Canonical list of languages this app offers. Keep LanguageScreen,
/// LocaleController, and the future Sunbird script aligned with this file.
class AppLanguages {
  static const signLanguageCode = 'sign';

  static const english = AppLanguage(
    flutterCode: 'en',
    sunbirdCode: 'eng',
    icon: Icons.language,
  );
  static const luganda = AppLanguage(
    flutterCode: 'lg',
    sunbirdCode: 'lug',
    icon: Icons.translate,
  );
  static const runyankole = AppLanguage(
    flutterCode: 'nyn',
    sunbirdCode: 'nyn',
    icon: Icons.translate,
  );
  static const lusoga = AppLanguage(
    flutterCode: 'xog',
    sunbirdCode: 'xog',
    icon: Icons.translate,
  );
  static const kiswahili = AppLanguage(
    flutterCode: 'sw',
    sunbirdCode: 'swa',
    icon: Icons.translate,
  );
  static const signLanguage = AppLanguage(
    flutterCode: signLanguageCode,
    sunbirdCode: null,
    icon: Icons.back_hand_outlined,
  );

  static const List<AppLanguage> pickerOptions = [
    english,
    luganda,
    runyankole,
    lusoga,
    kiswahili,
    signLanguage,
  ];

  /// Locales that need English Material/Cupertino chrome — Flutter's SDK
  /// does not ship framework strings for these language codes. Kiswahili
  /// (`sw`) is already in the SDK, so it is not listed here.
  static const Set<String> materialFallbackCodes = {'lg', 'nyn', 'xog'};

  static String? sunbirdCodeFor(String flutterCode) {
    for (final lang in pickerOptions) {
      if (lang.flutterCode == flutterCode) return lang.sunbirdCode;
    }
    return null;
  }
}
