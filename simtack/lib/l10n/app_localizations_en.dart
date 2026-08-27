// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get chooseLanguageTitle => 'Choose Your Language';

  @override
  String get chooseLanguageSubtitle =>
      'Select the language you\'re most comfortable with';

  @override
  String get languageEnglish => 'English';

  @override
  String get languageLuganda => 'Luganda';

  @override
  String get languageSignLanguage => 'Sign Language';

  @override
  String get consentText =>
      'I understand this app will process my health information on this device to help assess my condition. My data stays on this device unless I choose to share it.';

  @override
  String get consentRequiredError => 'Please accept to continue';

  @override
  String get continueButton => 'Continue';
}
