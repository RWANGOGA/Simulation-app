import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'app_languages.dart';

/// Flutter's own GlobalMaterialLocalizations / GlobalCupertinoLocalizations
/// ship translations for a large fixed set of languages. Luganda (`lg`),
/// Runyankore (`nyn`), and Lusoga (`xog`) are not in that set — that's a
/// gap in the Flutter SDK, not something a project-level ARB file can add.
/// Without these delegates, setting the app locale to those codes crashes
/// with "No MaterialLocalizations found" the moment any framework widget
/// (a button, a date picker) needs its default strings.
///
/// Kiswahili (`sw`) *is* shipped by the SDK, so it does not need a fallback.
///
/// These claim support for the missing codes so MaterialApp's assertion
/// passes, then serve English framework strings. Only affects chrome text
/// Flutter itself owns — every string wired through AppLocalizations still
/// uses the matching ARB file.
class LugandaMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const LugandaMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLanguages.materialFallbackCodes.contains(locale.languageCode);

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(LugandaMaterialLocalizationsDelegate old) => false;
}

class LugandaCupertinoLocalizationsDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const LugandaCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) =>
      AppLanguages.materialFallbackCodes.contains(locale.languageCode);

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(LugandaCupertinoLocalizationsDelegate old) => false;
}
