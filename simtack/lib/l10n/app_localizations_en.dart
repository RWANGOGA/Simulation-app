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
}
