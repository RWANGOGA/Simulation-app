import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_lg.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('lg')
  ];

  /// Title of the language & consent screen, shown before onboarding starts.
  ///
  /// In en, this message translates to:
  /// **'Choose Your Language'**
  String get chooseLanguageTitle;

  /// Subtitle under the language & consent screen's title.
  ///
  /// In en, this message translates to:
  /// **'Select the language you\'re most comfortable with'**
  String get chooseLanguageSubtitle;

  /// Label for the English language option.
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get languageEnglish;

  /// Label for the Luganda language option.
  ///
  /// In en, this message translates to:
  /// **'Luganda'**
  String get languageLuganda;

  /// Label for the sign-language option.
  ///
  /// In en, this message translates to:
  /// **'Sign Language'**
  String get languageSignLanguage;

  /// Consent checkbox label the patient must accept before continuing.
  ///
  /// In en, this message translates to:
  /// **'I understand this app will process my health information on this device to help assess my condition. My data stays on this device unless I choose to share it.'**
  String get consentText;

  /// Shown when Continue is tapped without accepting consent.
  ///
  /// In en, this message translates to:
  /// **'Please accept to continue'**
  String get consentRequiredError;

  /// Button that proceeds from the language & consent screen.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueButton;

  /// Tooltip on the icon that opens text-size/theme settings.
  ///
  /// In en, this message translates to:
  /// **'Display & accessibility'**
  String get displayAccessibilityTooltip;

  /// Link that opens the practitioner login screen.
  ///
  /// In en, this message translates to:
  /// **'Practitioner Login'**
  String get practitionerLogin;

  /// Welcome screen's main heading.
  ///
  /// In en, this message translates to:
  /// **'Welcome'**
  String get welcomeTitle;

  /// Welcome screen's subheading.
  ///
  /// In en, this message translates to:
  /// **'Let\'s get started'**
  String get welcomeSubtitle;

  /// Privacy reassurance shown under the Continue button.
  ///
  /// In en, this message translates to:
  /// **'Your data stays on this device.\nYou are in control.'**
  String get privacyCaption;

  /// Title of the bottom sheet listing multiple saved drafts.
  ///
  /// In en, this message translates to:
  /// **'Saved drafts'**
  String get savedDraftsTitle;

  /// Tooltip on the delete icon for a saved draft.
  ///
  /// In en, this message translates to:
  /// **'Delete draft'**
  String get deleteDraftTooltip;

  /// Button that resumes the single saved draft.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeButton;

  /// Button that opens the picker when there are several saved drafts.
  ///
  /// In en, this message translates to:
  /// **'Choose'**
  String get chooseButton;

  /// Banner announcing saved offline draft(s) on the Welcome screen.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{You have a saved draft} other{You have {count} saved drafts}}'**
  String savedDraftBanner(int count);

  /// Snackbar shown after offline drafts auto-sync successfully on launch.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 saved report submitted} other{{count} saved reports submitted}}'**
  String draftsSyncedSnackbar(int count);

  /// Generic loading placeholder shown across the practitioner dashboard.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingEllipsis;

  /// Label for the high-risk stat card and body-map legend dot.
  ///
  /// In en, this message translates to:
  /// **'High Risk'**
  String get statHighRiskLabel;

  /// Label for the medium-risk stat card and body-map legend dot.
  ///
  /// In en, this message translates to:
  /// **'Medium Risk'**
  String get statMediumRiskLabel;

  /// Label for the low-risk stat card and body-map legend dot.
  ///
  /// In en, this message translates to:
  /// **'Low Risk'**
  String get statLowRiskLabel;

  /// Status chip / stat label for an open triage session.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get statusOpenLabel;

  /// Status chip / stat label for a closed triage session.
  ///
  /// In en, this message translates to:
  /// **'Closed'**
  String get statusClosedLabel;

  /// Fallback shown when a patient's anonymous code is missing.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get unknownLabel;

  /// Tooltip on the header refresh icon (Dashboard, Patients).
  ///
  /// In en, this message translates to:
  /// **'Refresh Data'**
  String get refreshDataTooltip;

  /// Tooltip on the Reports header's refresh icon.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refreshTooltip;

  /// Title used for the patient-lookup action card and section header.
  ///
  /// In en, this message translates to:
  /// **'Patient Lookup'**
  String get patientLookupTitle;

  /// Tooltip on the hamburger button that opens the sidebar drawer on narrow screens.
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get menuTooltip;

  /// Role caption under the Simtack brand name in the sidebar header.
  ///
  /// In en, this message translates to:
  /// **'Practitioner'**
  String get sidebarRoleLabel;

  /// Sidebar nav item label.
  ///
  /// In en, this message translates to:
  /// **'Dashboard'**
  String get navDashboard;

  /// Sidebar nav item label.
  ///
  /// In en, this message translates to:
  /// **'Patients'**
  String get navPatients;

  /// Sidebar nav item label, also used as the dashboard session-list section title.
  ///
  /// In en, this message translates to:
  /// **'Triage Sessions'**
  String get navTriageSessions;

  /// Sidebar nav item label.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get navReports;

  /// Sidebar nav item label.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get navSettings;

  /// Sidebar nav item label.
  ///
  /// In en, this message translates to:
  /// **'Help & Support'**
  String get navHelpSupport;

  /// Snackbar shown when tapping an unbuilt sidebar nav item.
  ///
  /// In en, this message translates to:
  /// **'Coming soon'**
  String get comingSoonMessage;

  /// Sidebar footer logout button.
  ///
  /// In en, this message translates to:
  /// **'Logout'**
  String get logoutButton;

  /// Dashboard screen header title.
  ///
  /// In en, this message translates to:
  /// **'Dashboard Overview'**
  String get dashboardTitle;

  /// Dashboard screen header subtitle.
  ///
  /// In en, this message translates to:
  /// **'Monitor active triage sessions and patient risk levels.'**
  String get dashboardSubtitle;

  /// Label for the total-sessions stat card on the dashboard.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get statTotalLabel;

  /// Subtitle on the Patient Lookup action card.
  ///
  /// In en, this message translates to:
  /// **'Search patients and view history'**
  String get actionPatientLookupSubtitle;

  /// Title on the New Triage action card.
  ///
  /// In en, this message translates to:
  /// **'New Triage'**
  String get actionNewTriageTitle;

  /// Subtitle on the New Triage action card.
  ///
  /// In en, this message translates to:
  /// **'Start a new patient triage session'**
  String get actionNewTriageSubtitle;

  /// Section title above the recent-sessions list.
  ///
  /// In en, this message translates to:
  /// **'Recent Activity'**
  String get recentActivityTitle;

  /// Button that opens the full session list from Recent Activity.
  ///
  /// In en, this message translates to:
  /// **'See All'**
  String get seeAllButton;

  /// Button that opens the full session list from Triage Sessions.
  ///
  /// In en, this message translates to:
  /// **'View All'**
  String get viewAllButton;

  /// Hint text on the dashboard's patient search field.
  ///
  /// In en, this message translates to:
  /// **'Search Patient ID (e.g., P-...)'**
  String get searchPatientIdHint;

  /// Tooltip on the dashboard's QR scan icon button.
  ///
  /// In en, this message translates to:
  /// **'Scan patient QR'**
  String get scanPatientQrTooltip;

  /// Empty state when the dashboard's session list has no results.
  ///
  /// In en, this message translates to:
  /// **'No triage sessions found.'**
  String get noTriageSessionsFoundMessage;

  /// Button that loads the next page of sessions.
  ///
  /// In en, this message translates to:
  /// **'Load More'**
  String get loadMoreButton;

  /// Fallback session title when the anonymous code is missing.
  ///
  /// In en, this message translates to:
  /// **'Unknown ID'**
  String get unknownIdLabel;

  /// App bar title on the full session-list screen.
  ///
  /// In en, this message translates to:
  /// **'All Triage Sessions'**
  String get allTriageSessionsTitle;

  /// Title of the filter bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Filter Sessions'**
  String get filterSessionsTitle;

  /// Filter sheet section label.
  ///
  /// In en, this message translates to:
  /// **'Risk Level'**
  String get riskLevelLabel;

  /// Filter sheet section label.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get statusLabel;

  /// Clears every active filter chip.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get clearAllButton;

  /// Confirms the filter sheet's selections.
  ///
  /// In en, this message translates to:
  /// **'Apply Filters'**
  String get applyFiltersButton;

  /// Empty state on the full session-list screen.
  ///
  /// In en, this message translates to:
  /// **'No sessions found.'**
  String get noSessionsFoundMessage;

  /// Patient Overview screen header title.
  ///
  /// In en, this message translates to:
  /// **'Patient Overview'**
  String get patientOverviewTitle;

  /// Patient Overview screen header subtitle.
  ///
  /// In en, this message translates to:
  /// **'Review patient history, body map, and triage data.'**
  String get patientOverviewSubtitle;

  /// Hint text on the patient-code lookup field.
  ///
  /// In en, this message translates to:
  /// **'Enter patient code e.g. P-770043'**
  String get patientCodeHint;

  /// Button label for launching the mobile QR scanner.
  ///
  /// In en, this message translates to:
  /// **'Scan Patient QR'**
  String get scanPatientQrButton;

  /// Caption above the looked-up patient's anonymous code badge.
  ///
  /// In en, this message translates to:
  /// **'PATIENT ANONYMOUS ID'**
  String get patientAnonymousIdLabel;

  /// Caption under the patient's QR code image.
  ///
  /// In en, this message translates to:
  /// **'Encrypted QR Passport'**
  String get encryptedQrPassportLabel;

  /// Button that opens the patient's full clinical report.
  ///
  /// In en, this message translates to:
  /// **'Open Full Clinical Report'**
  String get openFullClinicalReportButton;

  /// Section header over the interactive 3D body model.
  ///
  /// In en, this message translates to:
  /// **'3D Body Map'**
  String get bodyMapTitle;

  /// Overlay hint on the body map before a patient code is entered.
  ///
  /// In en, this message translates to:
  /// **'Enter a patient code to see pain points'**
  String get bodyMapEmptyHint;

  /// Section header over the patient's session timeline.
  ///
  /// In en, this message translates to:
  /// **'Visit History'**
  String get visitHistoryTitle;

  /// Pill next to Visit History showing how many sessions are listed.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 session} other{{count} sessions}}'**
  String sessionCountLabel(int count);

  /// Empty state before any patient code has been entered.
  ///
  /// In en, this message translates to:
  /// **'Enter a patient code above to view visit history'**
  String get enterCodeForHistoryHint;

  /// Empty state when a looked-up patient has no recorded visits.
  ///
  /// In en, this message translates to:
  /// **'No visits found for {code}'**
  String noVisitsFoundHint(String code);

  /// Heading on each row of the visit-history timeline.
  ///
  /// In en, this message translates to:
  /// **'Session {number}'**
  String sessionNumberLabel(int number);

  /// Reports screen header title.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsTitle;

  /// Reports screen header subtitle.
  ///
  /// In en, this message translates to:
  /// **'Aggregate breakdown across every triage session on record.'**
  String get reportsSubtitle;

  /// Tooltip on the Reports header's download icon.
  ///
  /// In en, this message translates to:
  /// **'Download PDF report'**
  String get downloadPdfTooltip;

  /// Reports period filter chip.
  ///
  /// In en, this message translates to:
  /// **'This Week'**
  String get periodThisWeek;

  /// Reports period filter chip.
  ///
  /// In en, this message translates to:
  /// **'This Month'**
  String get periodThisMonth;

  /// Reports period filter chip.
  ///
  /// In en, this message translates to:
  /// **'All Time'**
  String get periodAllTime;

  /// Empty state when the selected reporting period has no sessions.
  ///
  /// In en, this message translates to:
  /// **'No triage sessions in this period.'**
  String get noSessionsInPeriodMessage;

  /// Label for the total-sessions stat card on Reports.
  ///
  /// In en, this message translates to:
  /// **'Total Sessions'**
  String get statTotalSessionsLabel;

  /// Label for the average-severity stat card on Reports.
  ///
  /// In en, this message translates to:
  /// **'Avg. Severity'**
  String get statAvgSeverityLabel;

  /// Label for the average-risk-score stat card on Reports.
  ///
  /// In en, this message translates to:
  /// **'Avg. Risk Score'**
  String get statAvgRiskScoreLabel;

  /// Section title above the open/closed donut chart.
  ///
  /// In en, this message translates to:
  /// **'Session Status'**
  String get sessionStatusTitle;

  /// Section title above the body-region donut chart.
  ///
  /// In en, this message translates to:
  /// **'Most Reported Body Regions'**
  String get mostReportedRegionsTitle;

  /// Section title above the pain-type donut chart.
  ///
  /// In en, this message translates to:
  /// **'Pain Type Breakdown'**
  String get painTypeBreakdownTitle;

  /// Button shown on Reports when loading data fails.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retryButton;

  /// Catch-all donut slice label for categories beyond the top 6.
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get otherLabel;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'lg'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'lg':
      return AppLocalizationsLg();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
