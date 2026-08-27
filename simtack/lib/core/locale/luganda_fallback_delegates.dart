import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

/// Flutter's own GlobalMaterialLocalizations / GlobalCupertinoLocalizations
/// ship translations for a large fixed set of languages, and Luganda ("lg")
/// isn't one of them — that's a real gap in the Flutter SDK itself, not
/// something a project-level ARB file can add. Without these, setting the
/// app's locale to "lg" crashes with "No MaterialLocalizations found" the
/// moment any framework-level widget (a button, a date picker) needs its
/// default strings.
///
/// These are the standard fallback pattern for an unsupported locale: they
/// claim support for "lg" so MaterialApp's assertion passes, then quietly
/// serve the English framework strings. Only affects default/chrome text
/// Flutter itself owns (e.g. a date picker's month names) — every string
/// actually wired through AppLocalizations still shows real Luganda.
class LugandaMaterialLocalizationsDelegate extends LocalizationsDelegate<MaterialLocalizations> {
  const LugandaMaterialLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lg';

  @override
  Future<MaterialLocalizations> load(Locale locale) =>
      GlobalMaterialLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(LugandaMaterialLocalizationsDelegate old) => false;
}

class LugandaCupertinoLocalizationsDelegate extends LocalizationsDelegate<CupertinoLocalizations> {
  const LugandaCupertinoLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => locale.languageCode == 'lg';

  @override
  Future<CupertinoLocalizations> load(Locale locale) =>
      GlobalCupertinoLocalizations.delegate.load(const Locale('en'));

  @override
  bool shouldReload(LugandaCupertinoLocalizationsDelegate old) => false;
}
