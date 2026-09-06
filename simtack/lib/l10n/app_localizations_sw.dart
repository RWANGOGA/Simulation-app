// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Swahili (`sw`).
class AppLocalizationsSw extends AppLocalizations {
  AppLocalizationsSw([String locale = 'sw']) : super(locale);

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
  String get languageRunyankole => 'Runyankore';

  @override
  String get languageLusoga => 'Lusoga';

  @override
  String get languageKiswahili => 'Kiswahili';

  @override
  String get languageSignLanguage => 'Sign Language';

  @override
  String get consentText =>
      'I understand this app will process my health information on this device to help assess my condition. My data stays on this device unless I choose to share it.';

  @override
  String get consentRequiredError => 'Please accept to continue';

  @override
  String get continueButton => 'Continue';

  @override
  String get displayAccessibilityTooltip => 'Display & accessibility';

  @override
  String get practitionerLogin => 'Practitioner Login';

  @override
  String get welcomeTitle => 'Welcome';

  @override
  String get welcomeSubtitle => 'Let\'s get started';

  @override
  String get privacyCaption =>
      'Your data stays on this device.\nYou are in control.';

  @override
  String get savedDraftsTitle => 'Saved drafts';

  @override
  String get deleteDraftTooltip => 'Delete draft';

  @override
  String get resumeButton => 'Resume';

  @override
  String get chooseButton => 'Choose';

  @override
  String savedDraftBanner(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'You have $count saved drafts',
      one: 'You have a saved draft',
    );
    return '$_temp0';
  }

  @override
  String draftsSyncedSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count saved reports submitted',
      one: '1 saved report submitted',
    );
    return '$_temp0';
  }

  @override
  String get loadingEllipsis => 'Loading...';

  @override
  String get statHighRiskLabel => 'High Risk';

  @override
  String get statMediumRiskLabel => 'Medium Risk';

  @override
  String get statLowRiskLabel => 'Low Risk';

  @override
  String get statusOpenLabel => 'Open';

  @override
  String get statusClosedLabel => 'Closed';

  @override
  String get unknownLabel => 'Unknown';

  @override
  String get refreshDataTooltip => 'Refresh Data';

  @override
  String get refreshTooltip => 'Refresh';

  @override
  String get patientLookupTitle => 'Patient Lookup';

  @override
  String get menuTooltip => 'Menu';

  @override
  String get sidebarRoleLabel => 'Practitioner';

  @override
  String get navDashboard => 'Dashboard';

  @override
  String get navPatients => 'Patients';

  @override
  String get navTriageSessions => 'Triage Sessions';

  @override
  String get navReports => 'Reports';

  @override
  String get navSettings => 'Settings';

  @override
  String get navHelpSupport => 'Help & Support';

  @override
  String get comingSoonMessage => 'Coming soon';

  @override
  String get logoutButton => 'Logout';

  @override
  String get dashboardTitle => 'Dashboard Overview';

  @override
  String get dashboardSubtitle =>
      'Monitor active triage sessions and patient risk levels.';

  @override
  String get statTotalLabel => 'Total';

  @override
  String get actionPatientLookupSubtitle => 'Search patients and view history';

  @override
  String get actionNewTriageTitle => 'New Triage';

  @override
  String get actionNewTriageSubtitle => 'Start a new patient triage session';

  @override
  String get recentActivityTitle => 'Recent Activity';

  @override
  String get seeAllButton => 'See All';

  @override
  String get viewAllButton => 'View All';

  @override
  String get searchPatientIdHint => 'Search Patient ID (e.g., P-...)';

  @override
  String get scanPatientQrTooltip => 'Scan patient QR';

  @override
  String get noTriageSessionsFoundMessage => 'No triage sessions found.';

  @override
  String get loadMoreButton => 'Load More';

  @override
  String get unknownIdLabel => 'Unknown ID';

  @override
  String get allTriageSessionsTitle => 'All Triage Sessions';

  @override
  String get filterSessionsTitle => 'Filter Sessions';

  @override
  String get riskLevelLabel => 'Risk Level';

  @override
  String get statusLabel => 'Status';

  @override
  String get clearAllButton => 'Clear All';

  @override
  String get applyFiltersButton => 'Apply Filters';

  @override
  String get noSessionsFoundMessage => 'No sessions found.';

  @override
  String get patientOverviewTitle => 'Patient Overview';

  @override
  String get patientOverviewSubtitle =>
      'Review patient history, body map, and triage data.';

  @override
  String get patientCodeHint => 'Enter patient code e.g. P-770043';

  @override
  String get scanPatientQrButton => 'Scan Patient QR';

  @override
  String get patientAnonymousIdLabel => 'PATIENT ANONYMOUS ID';

  @override
  String get encryptedQrPassportLabel => 'Encrypted QR Passport';

  @override
  String get openFullClinicalReportButton => 'Open Full Clinical Report';

  @override
  String get bodyMapTitle => '3D Body Map';

  @override
  String get bodyMapEmptyHint => 'Enter a patient code to see pain points';

  @override
  String get visitHistoryTitle => 'Visit History';

  @override
  String sessionCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sessions',
      one: '1 session',
    );
    return '$_temp0';
  }

  @override
  String get enterCodeForHistoryHint =>
      'Enter a patient code above to view visit history';

  @override
  String noVisitsFoundHint(String code) {
    return 'No visits found for $code';
  }

  @override
  String sessionNumberLabel(int number) {
    return 'Session $number';
  }

  @override
  String get reportsTitle => 'Reports';

  @override
  String get reportsSubtitle =>
      'Aggregate breakdown across every triage session on record.';

  @override
  String get downloadPdfTooltip => 'Download PDF report';

  @override
  String get periodThisWeek => 'This Week';

  @override
  String get periodThisMonth => 'This Month';

  @override
  String get periodAllTime => 'All Time';

  @override
  String get noSessionsInPeriodMessage => 'No triage sessions in this period.';

  @override
  String get statTotalSessionsLabel => 'Total Sessions';

  @override
  String get statAvgSeverityLabel => 'Avg. Severity';

  @override
  String get statAvgRiskScoreLabel => 'Avg. Risk Score';

  @override
  String get sessionStatusTitle => 'Session Status';

  @override
  String get mostReportedRegionsTitle => 'Most Reported Body Regions';

  @override
  String get painTypeBreakdownTitle => 'Pain Type Breakdown';

  @override
  String get retryButton => 'Retry';

  @override
  String get otherLabel => 'Other';

  @override
  String get genderFemale => 'Female';

  @override
  String get genderMale => 'Male';

  @override
  String get genderOther => 'Other';

  @override
  String get notSetLabel => 'Not set';

  @override
  String get naLabel => 'N/A';

  @override
  String get patientProfileTitle => 'Patient Profile';

  @override
  String get patientProfileSubtitle => 'This helps us build your body map';

  @override
  String get ageLabel => 'Age';

  @override
  String get yearsSuffix => 'years';

  @override
  String get weightLabel => 'Weight';

  @override
  String get kgSuffix => 'kg';

  @override
  String get heightLabel => 'Height';

  @override
  String get cmSuffix => 'cm';

  @override
  String get contactIdentityOptionalTitle => 'CONTACT & IDENTITY (OPTIONAL)';

  @override
  String get contactIdentityHint =>
      'Add these so the practitioner can identify and reach you. Skip them to stay fully anonymous.';

  @override
  String get fullNameLabel => 'Full Name';

  @override
  String get dateOfBirthLabel => 'Date of Birth';

  @override
  String get dateOfBirthHelpText => 'DATE OF BIRTH';

  @override
  String get contactPhoneLabel => 'Contact Phone';

  @override
  String get addressLabel => 'Address';

  @override
  String get nextOfKinNameLabel => 'Next of Kin Name';

  @override
  String get nextOfKinNameHelper =>
      'Useful when reporting for a child or dependent';

  @override
  String get nextOfKinPhoneLabel => 'Next of Kin Phone';

  @override
  String get hospitalClinicNameLabel => 'Hospital / Clinic Name';

  @override
  String fieldRequiredError(String label) {
    return '$label is required';
  }

  @override
  String get enterValidNumberError => 'Enter a valid number';

  @override
  String fieldRangeError(String label, String min, String max) {
    return '$label must be between $min and $max';
  }

  @override
  String get bodyMapSelectPainTitle => 'Body Map - Select Pain';

  @override
  String get resetViewTooltip => 'Reset View';

  @override
  String get rotateModelTooltip => 'Rotate Model';

  @override
  String get zoomInTooltip => 'Zoom In';

  @override
  String get zoomOutTooltip => 'Zoom Out';

  @override
  String get tapABodyPartLabel => 'Tap a body part';

  @override
  String locationsSelectedLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count locations selected',
      one: '1 location selected',
    );
    return '$_temp0';
  }

  @override
  String get viewFront => 'Front';

  @override
  String get viewBack => 'Back';

  @override
  String get viewLeft => 'Left';

  @override
  String get viewRight => 'Right';

  @override
  String get tapBodyToMarkPain => 'Tap the body to mark pain';

  @override
  String continueToPainDetailsButton(int count) {
    return 'Continue to Pain Details ($count)';
  }

  @override
  String get painLocationsSheetTitle => 'Pain Locations';

  @override
  String get noLocationsMarkedHint =>
      'No locations marked yet. Tap anywhere on the body to add one.';

  @override
  String get removeTooltip => 'Remove';

  @override
  String get addAnotherLocationLabel => 'Add another location';

  @override
  String get selectPainLocationTitle => 'Select Pain Location';

  @override
  String get bodyMapHelpTitle => 'How to use Body Map';

  @override
  String get bodyMapHelpBullet1 =>
      '• 3D Body (OpenHuman model): Rotate & inspect in 360°.';

  @override
  String get bodyMapHelpBullet2 =>
      '• Tap on body parts to mark pain locations — tap as many as you need.';

  @override
  String get bodyMapHelpBullet3 =>
      '• Tap the same spot again to remove that marker.';

  @override
  String get bodyMapHelpBullet4 =>
      '• Use camera tools on the left overlay to zoom in/out or reset.';

  @override
  String get bodyMapHelpBullet5 =>
      '• Toggle Front, Back, Left, or Right views with bottom tabs.';

  @override
  String get gotItButton => 'Got it';

  @override
  String get painDetailsTitle => '3. Pain Details';

  @override
  String painDetailsTitleWithProgress(int current, int total) {
    return '3. Pain Details ($current of $total)';
  }

  @override
  String get painLocationLabel => 'Pain Location';

  @override
  String get directionLabel => 'Direction';

  @override
  String get depthLabel => 'Depth';

  @override
  String get painTypeLabel => 'Pain Type';

  @override
  String get painIntensityLabel => 'Pain Intensity';

  @override
  String get nextMeasureVitalsButton => 'Next: Measure Vitals';

  @override
  String get nextLocationButton => 'Next Location';

  @override
  String get painDetailsHelpTitle => 'Pain Details Guide';

  @override
  String get painDetailsHelpBullet1 =>
      '• If you marked more than one location, you\'ll fill in details for each one in turn.';

  @override
  String get painDetailsHelpBullet2 =>
      '• Use the Direction dropdown to specify where the pain moves (e.g. Towards Back).';

  @override
  String get painDetailsHelpBullet3 =>
      '• Use the Depth dropdown to specify how deep the pain feels (Deep, Moderate, Superficial).';

  @override
  String get painDetailsHelpBullet4 =>
      '• Tap pain type chips (Sharp, Dull, Burning, Cramping).';

  @override
  String get painDetailsHelpBullet5 =>
      '• Slide to set pain intensity scale from 1 to 10 — each location can be different.';

  @override
  String get vitalsCaptureTitle => '4. Vitals Capture';

  @override
  String get signalQualityLabel => 'Signal Quality';

  @override
  String get tapStartMeasurementStatus => 'Tap \"Start Measurement\"';

  @override
  String get measuringKeepFingerSteadyStatus =>
      'Measuring... Keep finger steady';

  @override
  String get cameraPermissionNeededStatus =>
      'Camera permission is needed to measure your heart rate. Please allow camera access and try again.';

  @override
  String get measurementCompleteStatus => 'Measurement complete!';

  @override
  String get cameraReadyLabel => 'Camera Ready';

  @override
  String get placeFingerHint =>
      'Place your finger gently over the back camera and flash';

  @override
  String get nextReviewSubmitButton => 'Next: Review & Submit';

  @override
  String get measuringEllipsisButton => 'Measuring...';

  @override
  String get startMeasurementButton => 'Start Measurement';

  @override
  String get signalExcellent => 'Excellent';

  @override
  String get signalGood => 'Good';

  @override
  String get signalWeak => 'Weak';

  @override
  String get reviewSubmitTitle => '5. Review & Submit';

  @override
  String get editButton => 'Edit';

  @override
  String get anonymousPatientLabel => 'Anonymous Patient';

  @override
  String get idGeneratedOnSubmitLabel => 'ID generated on submit';

  @override
  String get timestampLabel => 'Timestamp';

  @override
  String get clinicalSummaryTitle => 'Clinical Summary';

  @override
  String painPointNumberLabel(int number) {
    return 'Pain Point $number';
  }

  @override
  String get locationLabel => 'Location';

  @override
  String get intensityLabel => 'Intensity';

  @override
  String get vitalsTitle => 'Vitals';

  @override
  String get heartRateLabel => 'Heart Rate';

  @override
  String get spo2EstLabel => 'SpO2 (est.)';

  @override
  String get consentSubmitNotice =>
      'By submitting, you consent to sharing this clinical data with the attending physician for triage purposes.';

  @override
  String get saveDraftButton => 'Save Draft';

  @override
  String get submitButton => 'Submit';

  @override
  String get draftSavedSnackbar => '✅ Draft saved offline successfully!';

  @override
  String submitFailedSavedOfflineSnackbar(String error) {
    return '⚠️ Could not submit — saved offline, will retry automatically: $error';
  }

  @override
  String get reportSubmittedTitle => 'Report Submitted!';

  @override
  String get patientIdLabel => 'Patient ID';

  @override
  String get noInternetRequiredHint => 'No internet required to view';

  @override
  String get showQrToHealthWorkerHint =>
      'Show this QR code to the health worker';

  @override
  String aiAssessmentLabel(String label) {
    return 'AI Assessment: $label';
  }

  @override
  String get riskAssessmentPendingLabel => 'Risk Assessment Pending';

  @override
  String riskPercentLabel(String level, int percent) {
    return '$level Risk ($percent%)';
  }

  @override
  String get saveButton => 'Save';

  @override
  String get shareButton => 'Share';

  @override
  String get viewHistoryButton => 'View My Triage History';

  @override
  String get startNewTriageButton => 'Start New Triage';

  @override
  String get shareReportSheetTitle => 'Share Report';

  @override
  String get whatsappLabel => 'WhatsApp';

  @override
  String get emailLabel => 'Email';

  @override
  String get smsLabel => 'SMS';

  @override
  String get copyLinkLabel => 'Copy Link';

  @override
  String get linkCopiedSnackbar => 'Link copied to clipboard';

  @override
  String get clinicalReportTitle => 'Clinical Report';

  @override
  String get practitionerModeChip => 'Practitioner Mode';

  @override
  String get reportNotFoundError => 'Report not found';

  @override
  String get clinicalTriageReportTitle => 'Clinical Triage Report';

  @override
  String get officialDocumentSubtitle => 'Simtack Care • Official Document';

  @override
  String get aiRiskAssessmentHighestLabel => 'AI RISK ASSESSMENT (HIGHEST)';

  @override
  String drivenByLabel(String region) {
    return 'Driven by: $region';
  }

  @override
  String get clinicalDetailsTitle => 'Clinical Details';

  @override
  String clinicalDetailsWithCountTitle(int count) {
    return 'Clinical Details ($count pain points)';
  }

  @override
  String get painPointLabel => 'Pain Point';

  @override
  String get riskLabel => 'Risk';

  @override
  String get reportedAtLabel => 'Reported At';

  @override
  String get patientProfileSectionTitle => 'PATIENT PROFILE';

  @override
  String get noDemographicsOnFileMessage => 'No demographics on file yet.';

  @override
  String get nameLabel => 'Name';

  @override
  String get dobLabel => 'DOB';

  @override
  String get genderLabel => 'Gender';

  @override
  String get phoneLabel => 'Phone';

  @override
  String get nextOfKinShortLabel => 'Next of kin';

  @override
  String get hospitalLabel => 'Hospital';

  @override
  String get visitTimelineTitle => 'VISIT TIMELINE';

  @override
  String visitNumberLabel(int number) {
    return 'Visit $number';
  }

  @override
  String ptCountLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pts',
      one: '1 pt',
    );
    return '$_temp0';
  }

  @override
  String get whyThisScoreTitle => 'WHY THIS SCORE?';

  @override
  String get unknownFactorLabel => 'Unknown factor';

  @override
  String get triageDecisionTitle => 'TRIAGE DECISION';

  @override
  String get suggestedPriorityLabel => 'Suggested Priority';

  @override
  String get statusColonLabel => 'Status:';

  @override
  String get recommendedActionsLabel => 'Recommended Actions';

  @override
  String get clinicalNotesHint => 'Clinical notes...';

  @override
  String get saveDecisionButton => 'Save Decision';

  @override
  String get decisionSavedSnackbar => 'Decision saved.';

  @override
  String get editPatientDemographicsTitle => 'Edit Patient Demographics';

  @override
  String get saveChangesButton => 'Save Changes';

  @override
  String get ageGenderWeightHeightRequiredError =>
      'Age, gender, weight, and height are required.';

  @override
  String get hospitalFacilityLabel => 'Hospital / Facility';

  @override
  String get weightKgLabel => 'Weight (kg)';

  @override
  String get heightCmLabel => 'Height (cm)';
}
