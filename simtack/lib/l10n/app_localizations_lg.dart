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

  @override
  String get loadingEllipsis => 'Kulinda...';

  @override
  String get statHighRiskLabel => 'Akabi Kanene';

  @override
  String get statMediumRiskLabel => 'Akabi Ekiriwakati';

  @override
  String get statLowRiskLabel => 'Akabi Katono';

  @override
  String get statusOpenLabel => 'Kiggule';

  @override
  String get statusClosedLabel => 'Kiggaliddwa';

  @override
  String get unknownLabel => 'Tekimanyiddwa';

  @override
  String get refreshDataTooltip => 'Ddamu Otereeze Amawulire';

  @override
  String get refreshTooltip => 'Ddamu Otereeze';

  @override
  String get patientLookupTitle => 'Okunoonya Omulwadde';

  @override
  String get menuTooltip => 'Lametaanyi';

  @override
  String get sidebarRoleLabel => 'Omusawo';

  @override
  String get navDashboard => 'Endagiriro';

  @override
  String get navPatients => 'Abalwadde';

  @override
  String get navTriageSessions => 'Emirundi gy\'Okulambulula';

  @override
  String get navReports => 'Lipoota';

  @override
  String get navSettings => 'Enteekateeka';

  @override
  String get navHelpSupport => 'Obuyambi';

  @override
  String get comingSoonMessage => 'Kijja Mangu';

  @override
  String get logoutButton => 'Fuluma';

  @override
  String get dashboardTitle => 'Endagiriro y\'Omulimu';

  @override
  String get dashboardSubtitle =>
      'Lambula emirimu egikyagenda mu maaso n\'obungi bw\'akabi eri abalwadde.';

  @override
  String get statTotalLabel => 'Omuwendo Gwonna';

  @override
  String get actionPatientLookupSubtitle =>
      'Noonya abalwadde era olabe ebyafaayo byabwe';

  @override
  String get actionNewTriageTitle => 'Okwekenneenya Okuggya';

  @override
  String get actionNewTriageSubtitle =>
      'Tandika omulundi omuggya ogw\'okwekenneenya omulwadde';

  @override
  String get recentActivityTitle => 'Ebibaddewo Enseka Nga';

  @override
  String get seeAllButton => 'Laba Byonna';

  @override
  String get viewAllButton => 'Laba Byonna';

  @override
  String get searchPatientIdHint => 'Noonya ekika ky\'Omulwadde (gamba, P-...)';

  @override
  String get scanPatientQrTooltip => 'Kuba QR y\'Omulwadde';

  @override
  String get noTriageSessionsFoundMessage =>
      'Tewali mirundi gya kwekenneenya gizuuliddwa.';

  @override
  String get loadMoreButton => 'Weongereeko Ebirala';

  @override
  String get unknownIdLabel => 'Ekika Ekitamanyiddwa';

  @override
  String get allTriageSessionsTitle => 'Emirundi Gyonna Egy\'Okwekenneenya';

  @override
  String get filterSessionsTitle => 'Sengejja Emirundi';

  @override
  String get riskLevelLabel => 'Omutindo gw\'Akabi';

  @override
  String get statusLabel => 'Embeera';

  @override
  String get clearAllButton => 'Sazaamu Byonna';

  @override
  String get applyFiltersButton => 'Kozesa Ensengejja';

  @override
  String get noSessionsFoundMessage => 'Tewali mirundi gizuuliddwa.';

  @override
  String get patientOverviewTitle => 'Ebikwata ku Mulwadde';

  @override
  String get patientOverviewSubtitle =>
      'Lambula ebyafaayo by\'omulwadde, ekifaananyi ky\'omubiri, n\'ebikwata ku kwekenneenya.';

  @override
  String get patientCodeHint => 'Wandiika ekika ky\'omulwadde gamba, P-770043';

  @override
  String get scanPatientQrButton => 'Kuba QR y\'Omulwadde';

  @override
  String get patientAnonymousIdLabel => 'EKIKA KY\'OMULWADDE EKITALINA LINNYA';

  @override
  String get encryptedQrPassportLabel => 'Paasipoota ya QR Ekusike';

  @override
  String get openFullClinicalReportButton =>
      'Sumulula Lipoota Yonna ey\'Ebyobusawo';

  @override
  String get bodyMapTitle => 'Ekifaananyi ky\'Omubiri mu 3D';

  @override
  String get bodyMapEmptyHint =>
      'Wandiika ekika ky\'omulwadde okulaba w\'obulumi buli';

  @override
  String get visitHistoryTitle => 'Ebyafaayo by\'Okukyala';

  @override
  String sessionCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Emirundi $count',
      one: 'Omulundi 1',
    );
    return '$_temp0';
  }

  @override
  String get enterCodeForHistoryHint =>
      'Wandiika ekika ky\'omulwadde waggulu okulaba ebyafaayo by\'okukyala';

  @override
  String noVisitsFoundHint(String code) {
    return 'Tewali kukyala kuzuuliddwa ku $code';
  }

  @override
  String sessionNumberLabel(int number) {
    return 'Omulundi $number';
  }

  @override
  String get reportsTitle => 'Lipoota';

  @override
  String get reportsSubtitle =>
      'Okugabanyaamu kw\'emirundi gyonna egy\'okwekenneenya egyawandiikibwa.';

  @override
  String get downloadPdfTooltip => 'Ssibbawo Lipoota ya PDF';

  @override
  String get periodThisWeek => 'Wiiki Eno';

  @override
  String get periodThisMonth => 'Omwezi Guno';

  @override
  String get periodAllTime => 'Ebbanga Lyonna';

  @override
  String get noSessionsInPeriodMessage =>
      'Tewali mirundi gya kwekenneenya mu kiseera kino.';

  @override
  String get statTotalSessionsLabel => 'Omuwendo gw\'Emirundi';

  @override
  String get statAvgSeverityLabel => 'Omuwendo Ogw\'Awamu ogw\'Obuzibu';

  @override
  String get statAvgRiskScoreLabel => 'Omuwendo Ogw\'Awamu ogw\'Akabi';

  @override
  String get sessionStatusTitle => 'Embeera y\'Omulundi';

  @override
  String get mostReportedRegionsTitle =>
      'Ebitundu by\'Omubiri Ebisinga Okuwandiikibwa';

  @override
  String get painTypeBreakdownTitle => 'Okugabanyaamu kw\'Ebika by\'Obulumi';

  @override
  String get retryButton => 'Ddamu Ogezaako';

  @override
  String get otherLabel => 'Ebirala';
}
