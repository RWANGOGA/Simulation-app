// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Ganda Luganda (`lg`).
class AppLocalizationsLg extends AppLocalizations {
  AppLocalizationsLg([String locale = 'lg']) : super(locale);

  @override
  String get chooseLanguageTitle => 'Londa Olulimi Lwo';

  @override
  String get chooseLanguageSubtitle => 'Londa olulimi kw\'oyagala okukozesa';

  @override
  String get languageEnglish => 'Lungereza';

  @override
  String get languageLuganda => 'Luganda';

  @override
  String get languageSignLanguage => 'Olulimi lw\'Emikono';

  @override
  String get consentText =>
      'Ntegeera nti app eno ejja kukozesa amawulire gange ag\'obulamu ku kaweefube kano okunnyamba okwekenneenya embeera yange. Amawulire gange gasigala ku kaweefube kano okuggyako nga nsazeewo okugabana nago.';

  @override
  String get consentRequiredError =>
      'Tukusaba okukkiriza okusobola okweyongerayo';

  @override
  String get continueButton => 'Weyongereyo';

  @override
  String get displayAccessibilityTooltip => 'Enjawulo n\'obuyambi';

  @override
  String get practitionerLogin => 'Okuyingira kw\'Omusawo';

  @override
  String get welcomeTitle => 'Tukwaniriza';

  @override
  String get welcomeSubtitle => 'Tutandike';

  @override
  String get privacyCaption =>
      'Amawulire go gasigala ku kaweefube kano.\nOli mu buyinza.';

  @override
  String get savedDraftsTitle => 'Ebiwandiiko ebiterekeddwa';

  @override
  String get deleteDraftTooltip => 'Sazaamu ekiwandiiko';

  @override
  String get resumeButton => 'Ddirira';

  @override
  String get chooseButton => 'Londa';

  @override
  String savedDraftBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Olina ebiwandiiko $count ebiterekeddwa',
      one: 'Olina ekiwandiiko ekiterekeddwa',
    );
    return '$_temp0';
  }

  @override
  String draftsSyncedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Lipoota $count ziweereddwa',
      one: 'Lipoota 1 etuweereddwa',
    );
    return '$_temp0';
  }
}
