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
  String get languageRunyankole => 'Runyankore';

  @override
  String get languageLusoga => 'Lusoga';

  @override
  String get languageKiswahili => 'Kiswahili';

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

  @override
  String get genderFemale => 'Omukazi';

  @override
  String get genderMale => 'Omusajja';

  @override
  String get genderOther => 'Ebirala';

  @override
  String get notSetLabel => 'Tekyassibwewo';

  @override
  String get naLabel => 'Tekiriwo';

  @override
  String get patientProfileTitle => 'Bbaluwa y\'Omulwadde';

  @override
  String get patientProfileSubtitle =>
      'Kino kitusobozesa okuzimba ekifaananyi ky\'omubiri gwo';

  @override
  String get ageLabel => 'Emyaka';

  @override
  String get yearsSuffix => 'emyaka';

  @override
  String get weightLabel => 'Obuzito';

  @override
  String get kgSuffix => 'kg';

  @override
  String get heightLabel => 'Obugulumivu';

  @override
  String get cmSuffix => 'cm';

  @override
  String get contactIdentityOptionalTitle => 'OBUYITA N\'ENNONYO (SI BWETAAVU)';

  @override
  String get contactIdentityHint =>
      'Wandiika bino omusawo asobole okukumanya n\'okukutuukako. Bisobola okulekebwa okusigala nga toomanyiddwa.';

  @override
  String get fullNameLabel => 'Erinnya Ery\'Amazima';

  @override
  String get dateOfBirthLabel => 'Olunaku olw\'Amazaalibwa';

  @override
  String get dateOfBirthHelpText => 'OLUNAKU OLW\'AMAZAALIBWA';

  @override
  String get contactPhoneLabel => 'Ennamba y\'Essimu';

  @override
  String get addressLabel => 'Aw\'Obeera';

  @override
  String get nextOfKinNameLabel => 'Erinnya ly\'Omuntu Okumpi';

  @override
  String get nextOfKinNameHelper =>
      'Kigasa nga owandiika ku lw\'omwana oba omuntu gw\'olabirira';

  @override
  String get nextOfKinPhoneLabel => 'Ennamba y\'Omuntu Okumpi';

  @override
  String get hospitalClinicNameLabel => 'Erinnya ly\'Eddwaliro';

  @override
  String fieldRequiredError(String label) {
    return '$label yeetaagisa';
  }

  @override
  String get enterValidNumberError => 'Wandiika omuwendo omutuufu';

  @override
  String fieldRangeError(String label, String min, String max) {
    return '$label kirina okuba wakati wa $min ne $max';
  }

  @override
  String get bodyMapSelectPainTitle =>
      'Ekifaananyi ky\'Omubiri - Londa Obulumi';

  @override
  String get resetViewTooltip => 'Ddamu Otandike';

  @override
  String get rotateModelTooltip => 'Kyuusa Ekifaananyi';

  @override
  String get zoomInTooltip => 'Sembeza';

  @override
  String get zoomOutTooltip => 'Ggwayo';

  @override
  String get tapABodyPartLabel => 'Kuba ku kitundu ky\'omubiri';

  @override
  String locationsSelectedLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ebifo $count birondeddwa',
      one: 'Ekifo 1 kirondeddwa',
    );
    return '$_temp0';
  }

  @override
  String get viewFront => 'Ebbali';

  @override
  String get viewBack => 'Emabega';

  @override
  String get viewLeft => 'Ekkono';

  @override
  String get viewRight => 'Eddyo';

  @override
  String get tapBodyToMarkPain => 'Kuba ku mubiri okulaga obulumi';

  @override
  String continueToPainDetailsButton(int count) {
    return 'Weyongereyo ku Bikwata ku Bulumi ($count)';
  }

  @override
  String get painLocationsSheetTitle => 'Ebifo eby\'Obulumi';

  @override
  String get noLocationsMarkedHint =>
      'Tewali kifo kirondeddwa. Kuba wonna ku mubiri okwongerako.';

  @override
  String get removeTooltip => 'Ggyawo';

  @override
  String get addAnotherLocationLabel => 'Ongerako ekifo ekirala';

  @override
  String get selectPainLocationTitle => 'Londa Ekifo ky\'Obulumi';

  @override
  String get bodyMapHelpTitle => 'Engeri y\'okukozesa Ekifaananyi ky\'Omubiri';

  @override
  String get bodyMapHelpBullet1 =>
      '• Omubiri mu 3D: Kyuusa era okenneenye mu 360°.';

  @override
  String get bodyMapHelpBullet2 =>
      '• Kuba ku bitundu by\'omubiri okulaga ebifo by\'obulumi — kuba nga bwe weetaaga.';

  @override
  String get bodyMapHelpBullet3 => '• Kuba ku kifo kye kimu ate okukiggyawo.';

  @override
  String get bodyMapHelpBullet4 =>
      '• Kozesa ebyuma ku ludda olwa kkono okusembeza, okuggwayo, oba okuddamu okutandika.';

  @override
  String get bodyMapHelpBullet5 =>
      '• Kyusakyusa wakati wa Ebbali, Emabega, Ekkono, oba Eddyo.';

  @override
  String get gotItButton => 'Ntegedde';

  @override
  String get painDetailsTitle => '3. Ebikwata ku Bulumi';

  @override
  String painDetailsTitleWithProgress(int current, int total) {
    return '3. Ebikwata ku Bulumi ($current ku $total)';
  }

  @override
  String get painLocationLabel => 'Ekifo ky\'Obulumi';

  @override
  String get directionLabel => 'Kkubo';

  @override
  String get depthLabel => 'Obuwanvu';

  @override
  String get painTypeLabel => 'Ekika ky\'Obulumi';

  @override
  String get painIntensityLabel => 'Amaanyi g\'Obulumi';

  @override
  String get nextMeasureVitalsButton => 'Ekiddako: Pima Obulamu';

  @override
  String get nextLocationButton => 'Ekifo Ekiddako';

  @override
  String get painDetailsHelpTitle => 'Obulagirizi ku Bikwata ku Bulumi';

  @override
  String get painDetailsHelpBullet1 =>
      '• Bwe waba weerondeddewo ebifo bisukka ekimu, ojja kujjuza ebikwata ku buli kimu ku lwakyo.';

  @override
  String get painDetailsHelpBullet2 =>
      '• Kozesa Kkubo okulaga w\'obulumi bugenda (gamba, Emabega).';

  @override
  String get painDetailsHelpBullet3 =>
      '• Kozesa Obuwanvu okulaga obulumi gye buli (Wangi, Bulijjo, Waggulu).';

  @override
  String get painDetailsHelpBullet4 =>
      '• Kuba ku bika by\'obulumi (Obwogi, Obukakali, Okwokya, Okukwata).';

  @override
  String get painDetailsHelpBullet5 =>
      '• Seeza okuteekawo amaanyi g\'obulumi okuva ku 1 okutuuka ku 10 — buli kifo kiyinza okwawukana.';

  @override
  String get vitalsCaptureTitle => '4. Okupima Obulamu';

  @override
  String get signalQualityLabel => 'Omutindo gw\'Akabonero';

  @override
  String get tapStartMeasurementStatus => 'Kuba \"Tandika Okupima\"';

  @override
  String get measuringKeepFingerSteadyStatus => 'Nkyapima... Nyweza olunwe';

  @override
  String get cameraPermissionNeededStatus =>
      'Olukusa lw\'ekkamera lwetaagisa okupima omutima gwo. Kkiriza ekkamera oddemu ogezeeko.';

  @override
  String get measurementCompleteStatus => 'Okupima kuwedde!';

  @override
  String get cameraReadyLabel => 'Ekkamera Etegefu';

  @override
  String get placeFingerHint =>
      'Teeka olunwe lwo mpola ku kkamera y\'emabega n\'ettaala';

  @override
  String get nextReviewSubmitButton => 'Ekiddako: Kebera & Weereza';

  @override
  String get measuringEllipsisButton => 'Nkyapima...';

  @override
  String get startMeasurementButton => 'Tandika Okupima';

  @override
  String get signalExcellent => 'Ekisingayo';

  @override
  String get signalGood => 'Kirungi';

  @override
  String get signalWeak => 'Kinafu';

  @override
  String get reviewSubmitTitle => '5. Kebera & Weereza';

  @override
  String get editButton => 'Kyusa';

  @override
  String get anonymousPatientLabel => 'Omulwadde Atamanyiddwa';

  @override
  String get idGeneratedOnSubmitLabel => 'Ekika kikolebwa nga oweerezza';

  @override
  String get timestampLabel => 'Ekiseera';

  @override
  String get clinicalSummaryTitle => 'Ebifunze eby\'Obusawo';

  @override
  String painPointNumberLabel(int number) {
    return 'Ekifo ky\'Obulumi $number';
  }

  @override
  String get locationLabel => 'Ekifo';

  @override
  String get intensityLabel => 'Amaanyi';

  @override
  String get vitalsTitle => 'Obulamu';

  @override
  String get heartRateLabel => 'Omutima';

  @override
  String get spo2EstLabel => 'SpO2 (okulambika)';

  @override
  String get consentSubmitNotice =>
      'Bw\'oweereza, okkiriza okugabana amawulire gano n\'omusawo akulabirira ku lw\'okwekenneenya.';

  @override
  String get saveDraftButton => 'Terekera Oluvannyuma';

  @override
  String get submitButton => 'Weereza';

  @override
  String get draftSavedSnackbar => '✅ Ekiwandiiko kiterekeddwa bulungi!';

  @override
  String submitFailedSavedOfflineSnackbar(String error) {
    return '⚠️ Tekiyinzikanga kuweerezebwa — kiterekeddwa, kijja kuddamu kugezaako: $error';
  }

  @override
  String get reportSubmittedTitle => 'Lipoota Eweereddwa!';

  @override
  String get patientIdLabel => 'Ekika ky\'Omulwadde';

  @override
  String get noInternetRequiredHint => 'Tewetaagisa yintaneeti okulaba';

  @override
  String get showQrToHealthWorkerHint =>
      'Laga QR eno eri omukozi w\'ebyobulamu';

  @override
  String aiAssessmentLabel(String label) {
    return 'Okwekenneenya kwa AI: $label';
  }

  @override
  String get riskAssessmentPendingLabel => 'Okwekenneenya Akabi Tekunnamalibwa';

  @override
  String riskPercentLabel(String level, int percent) {
    return 'Akabi $level ($percent%)';
  }

  @override
  String get saveButton => 'Terekera';

  @override
  String get shareButton => 'Gabana';

  @override
  String get viewHistoryButton => 'Laba Ebyafaayo Byange';

  @override
  String get startNewTriageButton => 'Tandika Okwekenneenya Okuggya';

  @override
  String get shareReportSheetTitle => 'Gabana Lipoota';

  @override
  String get whatsappLabel => 'WhatsApp';

  @override
  String get emailLabel => 'Email';

  @override
  String get smsLabel => 'SMS';

  @override
  String get copyLinkLabel => 'Kopa Ekkufulu';

  @override
  String get linkCopiedSnackbar => 'Ekkufulu ekopeddwa';

  @override
  String get clinicalReportTitle => 'Lipoota y\'Obusawo';

  @override
  String get practitionerModeChip => 'Embeera y\'Omusawo';

  @override
  String get reportNotFoundError => 'Lipoota teyazuulibwa';

  @override
  String get clinicalTriageReportTitle => 'Lipoota y\'Okwekenneenya';

  @override
  String get officialDocumentSubtitle =>
      'Simtack Care • Ekiwandiiko Ekikakasibwa';

  @override
  String get aiRiskAssessmentHighestLabel =>
      'OKWEKENNEENYA AKABI KA AI (AKASINGAYO)';

  @override
  String drivenByLabel(String region) {
    return 'Kivudde ku: $region';
  }

  @override
  String get clinicalDetailsTitle => 'Ebikwata ku Busawo';

  @override
  String clinicalDetailsWithCountTitle(int count) {
    return 'Ebikwata ku Busawo (ebifo $count)';
  }

  @override
  String get painPointLabel => 'Ekifo ky\'Obulumi';

  @override
  String get riskLabel => 'Akabi';

  @override
  String get reportedAtLabel => 'Kyawandiikibwa';

  @override
  String get patientProfileSectionTitle => 'BBALUWA Y\'OMULWADDE';

  @override
  String get noDemographicsOnFileMessage =>
      'Tewali mawulire ga bulwadde gawandiikiddwa.';

  @override
  String get nameLabel => 'Erinnya';

  @override
  String get dobLabel => 'Amazaalibwa';

  @override
  String get genderLabel => 'Ekikula';

  @override
  String get phoneLabel => 'Essimu';

  @override
  String get nextOfKinShortLabel => 'Omuntu okumpi';

  @override
  String get hospitalLabel => 'Eddwaliro';

  @override
  String get visitTimelineTitle => 'EBYAFAAYO BY\'OKUKYALA';

  @override
  String visitNumberLabel(int number) {
    return 'Okukyala $number';
  }

  @override
  String ptCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ebifo $count',
      one: 'Ekifo 1',
    );
    return '$_temp0';
  }

  @override
  String get whyThisScoreTitle => 'LWAKI OMUWENDO GUNO?';

  @override
  String get unknownFactorLabel => 'Ensonga Etamanyiddwa';

  @override
  String get triageDecisionTitle => 'EKISALAWO KY\'OKWEKENNEENYA';

  @override
  String get suggestedPriorityLabel => 'Obukulu Obuteesebwa';

  @override
  String get statusColonLabel => 'Embeera:';

  @override
  String get recommendedActionsLabel => 'Ebikolwa Ebiteesebwa';

  @override
  String get clinicalNotesHint => 'Ebiwandiiko by\'obusawo...';

  @override
  String get saveDecisionButton => 'Terekera Ekisalawo';

  @override
  String get decisionSavedSnackbar => 'Ekisalawo kiterekeddwa.';

  @override
  String get editPatientDemographicsTitle => 'Kyusa Amawulire g\'Omulwadde';

  @override
  String get saveChangesButton => 'Terekera Enkyukakyuka';

  @override
  String get ageGenderWeightHeightRequiredError =>
      'Emyaka, ekikula, obuzito, n\'obugulumivu byetaagisa.';

  @override
  String get hospitalFacilityLabel => 'Eddwaliro';

  @override
  String get weightKgLabel => 'Obuzito (kg)';

  @override
  String get heightCmLabel => 'Obugulumivu (cm)';
}
