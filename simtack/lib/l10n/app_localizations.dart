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

  /// Label for the Runyankole language option.
  ///
  /// In en, this message translates to:
  /// **'Runyankole'**
  String get languageRunyankole;

  /// Label for the Lusoga language option.
  ///
  /// In en, this message translates to:
  /// **'Lusoga'**
  String get languageLusoga;

  /// Label for the Kiswahili language option.
  ///
  /// In en, this message translates to:
  /// **'Kiswahili'**
  String get languageKiswahili;

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

  /// Caption over the QR code shown after submitting.
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

  /// Display label for the Female gender option. The value sent to the backend stays the English literal 'Female' regardless of locale.
  ///
  /// In en, this message translates to:
  /// **'Female'**
  String get genderFemale;

  /// Display label for the Male gender option. The value sent to the backend stays the English literal 'Male' regardless of locale.
  ///
  /// In en, this message translates to:
  /// **'Male'**
  String get genderMale;

  /// Display label for the Other gender option (demographics edit sheet).
  ///
  /// In en, this message translates to:
  /// **'Other'**
  String get genderOther;

  /// Shown when an optional date field has no value yet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get notSetLabel;

  /// Shown when an optional clinical field has no value.
  ///
  /// In en, this message translates to:
  /// **'N/A'**
  String get naLabel;

  /// Title of the patient intake form screen.
  ///
  /// In en, this message translates to:
  /// **'Patient Profile'**
  String get patientProfileTitle;

  /// Subtitle under Patient Profile.
  ///
  /// In en, this message translates to:
  /// **'This helps us build your body map'**
  String get patientProfileSubtitle;

  /// Age field label.
  ///
  /// In en, this message translates to:
  /// **'Age'**
  String get ageLabel;

  /// Unit suffix on the age field.
  ///
  /// In en, this message translates to:
  /// **'years'**
  String get yearsSuffix;

  /// Weight field label.
  ///
  /// In en, this message translates to:
  /// **'Weight'**
  String get weightLabel;

  /// Unit suffix on the weight field.
  ///
  /// In en, this message translates to:
  /// **'kg'**
  String get kgSuffix;

  /// Height field label.
  ///
  /// In en, this message translates to:
  /// **'Height'**
  String get heightLabel;

  /// Unit suffix on the height field.
  ///
  /// In en, this message translates to:
  /// **'cm'**
  String get cmSuffix;

  /// Section header for optional identifying fields.
  ///
  /// In en, this message translates to:
  /// **'CONTACT & IDENTITY (OPTIONAL)'**
  String get contactIdentityOptionalTitle;

  /// Explanation under the optional contact/identity section.
  ///
  /// In en, this message translates to:
  /// **'Add these so the practitioner can identify and reach you. Skip them to stay fully anonymous.'**
  String get contactIdentityHint;

  /// Full name field label.
  ///
  /// In en, this message translates to:
  /// **'Full Name'**
  String get fullNameLabel;

  /// Date of birth field label.
  ///
  /// In en, this message translates to:
  /// **'Date of Birth'**
  String get dateOfBirthLabel;

  /// Native date picker dialog header text.
  ///
  /// In en, this message translates to:
  /// **'DATE OF BIRTH'**
  String get dateOfBirthHelpText;

  /// Phone number field label on the patient intake form.
  ///
  /// In en, this message translates to:
  /// **'Contact Phone'**
  String get contactPhoneLabel;

  /// Address field label.
  ///
  /// In en, this message translates to:
  /// **'Address'**
  String get addressLabel;

  /// Next-of-kin name field label.
  ///
  /// In en, this message translates to:
  /// **'Next of Kin Name'**
  String get nextOfKinNameLabel;

  /// Helper text under the next-of-kin name field.
  ///
  /// In en, this message translates to:
  /// **'Useful when reporting for a child or dependent'**
  String get nextOfKinNameHelper;

  /// Next-of-kin phone field label.
  ///
  /// In en, this message translates to:
  /// **'Next of Kin Phone'**
  String get nextOfKinPhoneLabel;

  /// Hospital/clinic name field label on the patient intake form.
  ///
  /// In en, this message translates to:
  /// **'Hospital / Clinic Name'**
  String get hospitalClinicNameLabel;

  /// Validation error when a required numeric field is left empty.
  ///
  /// In en, this message translates to:
  /// **'{label} is required'**
  String fieldRequiredError(String label);

  /// Validation error when a numeric field can't be parsed.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid number'**
  String get enterValidNumberError;

  /// Validation error when a numeric field is outside its allowed range.
  ///
  /// In en, this message translates to:
  /// **'{label} must be between {min} and {max}'**
  String fieldRangeError(String label, String min, String max);

  /// Body Map screen app bar title.
  ///
  /// In en, this message translates to:
  /// **'Body Map - Select Pain'**
  String get bodyMapSelectPainTitle;

  /// Tooltip on the camera reset overlay button.
  ///
  /// In en, this message translates to:
  /// **'Reset View'**
  String get resetViewTooltip;

  /// Tooltip on the rotate-view overlay button.
  ///
  /// In en, this message translates to:
  /// **'Rotate Model'**
  String get rotateModelTooltip;

  /// Tooltip on the zoom-in overlay button.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get zoomInTooltip;

  /// Tooltip on the zoom-out overlay button.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get zoomOutTooltip;

  /// Badge shown before any pain location has been marked.
  ///
  /// In en, this message translates to:
  /// **'Tap a body part'**
  String get tapABodyPartLabel;

  /// Badge showing how many pain locations are currently marked.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 location selected} other{{count} locations selected}}'**
  String locationsSelectedLabel(int count);

  /// Body-map camera angle button.
  ///
  /// In en, this message translates to:
  /// **'Front'**
  String get viewFront;

  /// Body-map camera angle button.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get viewBack;

  /// Body-map camera angle button.
  ///
  /// In en, this message translates to:
  /// **'Left'**
  String get viewLeft;

  /// Body-map camera angle button.
  ///
  /// In en, this message translates to:
  /// **'Right'**
  String get viewRight;

  /// CTA button text before any pain location is marked.
  ///
  /// In en, this message translates to:
  /// **'Tap the body to mark pain'**
  String get tapBodyToMarkPain;

  /// CTA button text once at least one pain location is marked.
  ///
  /// In en, this message translates to:
  /// **'Continue to Pain Details ({count})'**
  String continueToPainDetailsButton(int count);

  /// Title of the marked-locations management bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Pain Locations'**
  String get painLocationsSheetTitle;

  /// Empty state inside the pain-locations bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'No locations marked yet. Tap anywhere on the body to add one.'**
  String get noLocationsMarkedHint;

  /// Tooltip on the remove-location icon.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get removeTooltip;

  /// Entry point into the preset region picker from the locations sheet.
  ///
  /// In en, this message translates to:
  /// **'Add another location'**
  String get addAnotherLocationLabel;

  /// Title of the preset region picker bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Select Pain Location'**
  String get selectPainLocationTitle;

  /// Title of the Body Map help dialog.
  ///
  /// In en, this message translates to:
  /// **'How to use Body Map'**
  String get bodyMapHelpTitle;

  /// First bullet in the Body Map help dialog.
  ///
  /// In en, this message translates to:
  /// **'• 3D Body (OpenHuman model): Rotate & inspect in 360°.'**
  String get bodyMapHelpBullet1;

  /// Second bullet in the Body Map help dialog.
  ///
  /// In en, this message translates to:
  /// **'• Tap on body parts to mark pain locations — tap as many as you need.'**
  String get bodyMapHelpBullet2;

  /// Third bullet in the Body Map help dialog.
  ///
  /// In en, this message translates to:
  /// **'• Tap the same spot again to remove that marker.'**
  String get bodyMapHelpBullet3;

  /// Fourth bullet in the Body Map help dialog.
  ///
  /// In en, this message translates to:
  /// **'• Use camera tools on the left overlay to zoom in/out or reset.'**
  String get bodyMapHelpBullet4;

  /// Fifth bullet in the Body Map help dialog.
  ///
  /// In en, this message translates to:
  /// **'• Toggle Front, Back, Left, or Right views with bottom tabs.'**
  String get bodyMapHelpBullet5;

  /// Dismiss button on help dialogs.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get gotItButton;

  /// Pain Details app bar title when there's only one pain point.
  ///
  /// In en, this message translates to:
  /// **'3. Pain Details'**
  String get painDetailsTitle;

  /// Pain Details app bar title when stepping through multiple pain points.
  ///
  /// In en, this message translates to:
  /// **'3. Pain Details ({current} of {total})'**
  String painDetailsTitleWithProgress(int current, int total);

  /// Label above the currently selected body region.
  ///
  /// In en, this message translates to:
  /// **'Pain Location'**
  String get painLocationLabel;

  /// Direction dropdown label.
  ///
  /// In en, this message translates to:
  /// **'Direction'**
  String get directionLabel;

  /// Depth dropdown label.
  ///
  /// In en, this message translates to:
  /// **'Depth'**
  String get depthLabel;

  /// Pain type section title / detail row label.
  ///
  /// In en, this message translates to:
  /// **'Pain Type'**
  String get painTypeLabel;

  /// Pain intensity slider section title.
  ///
  /// In en, this message translates to:
  /// **'Pain Intensity'**
  String get painIntensityLabel;

  /// CTA on the last pain point, advancing to Vitals Capture.
  ///
  /// In en, this message translates to:
  /// **'Next: Measure Vitals'**
  String get nextMeasureVitalsButton;

  /// CTA advancing to the next pain point's details.
  ///
  /// In en, this message translates to:
  /// **'Next Location'**
  String get nextLocationButton;

  /// Title of the Pain Details help dialog.
  ///
  /// In en, this message translates to:
  /// **'Pain Details Guide'**
  String get painDetailsHelpTitle;

  /// First bullet in the Pain Details help dialog.
  ///
  /// In en, this message translates to:
  /// **'• If you marked more than one location, you\'ll fill in details for each one in turn.'**
  String get painDetailsHelpBullet1;

  /// Second bullet in the Pain Details help dialog.
  ///
  /// In en, this message translates to:
  /// **'• Use the Direction dropdown to specify where the pain moves (e.g. Towards Back).'**
  String get painDetailsHelpBullet2;

  /// Third bullet in the Pain Details help dialog.
  ///
  /// In en, this message translates to:
  /// **'• Use the Depth dropdown to specify how deep the pain feels (Deep, Moderate, Superficial).'**
  String get painDetailsHelpBullet3;

  /// Fourth bullet in the Pain Details help dialog.
  ///
  /// In en, this message translates to:
  /// **'• Tap pain type chips (Sharp, Dull, Burning, Cramping).'**
  String get painDetailsHelpBullet4;

  /// Fifth bullet in the Pain Details help dialog.
  ///
  /// In en, this message translates to:
  /// **'• Slide to set pain intensity scale from 1 to 10 — each location can be different.'**
  String get painDetailsHelpBullet5;

  /// Vitals Capture app bar title.
  ///
  /// In en, this message translates to:
  /// **'4. Vitals Capture'**
  String get vitalsCaptureTitle;

  /// Label on the signal-quality vital circle.
  ///
  /// In en, this message translates to:
  /// **'Signal Quality'**
  String get signalQualityLabel;

  /// Initial status message before measurement begins.
  ///
  /// In en, this message translates to:
  /// **'Tap \"Start Measurement\"'**
  String get tapStartMeasurementStatus;

  /// Status message while a PPG measurement is in progress.
  ///
  /// In en, this message translates to:
  /// **'Measuring... Keep finger steady'**
  String get measuringKeepFingerSteadyStatus;

  /// Status message when camera permission is denied on mobile.
  ///
  /// In en, this message translates to:
  /// **'Camera permission is needed to measure your heart rate. Please allow camera access and try again.'**
  String get cameraPermissionNeededStatus;

  /// Status message once a measurement finishes.
  ///
  /// In en, this message translates to:
  /// **'Measurement complete!'**
  String get measurementCompleteStatus;

  /// Placeholder shown before the camera preview starts.
  ///
  /// In en, this message translates to:
  /// **'Camera Ready'**
  String get cameraReadyLabel;

  /// Instruction under the status message.
  ///
  /// In en, this message translates to:
  /// **'Place your finger gently over the back camera and flash'**
  String get placeFingerHint;

  /// CTA once a heart rate reading has been captured.
  ///
  /// In en, this message translates to:
  /// **'Next: Review & Submit'**
  String get nextReviewSubmitButton;

  /// CTA button label while a measurement is running.
  ///
  /// In en, this message translates to:
  /// **'Measuring...'**
  String get measuringEllipsisButton;

  /// CTA button label before measurement begins.
  ///
  /// In en, this message translates to:
  /// **'Start Measurement'**
  String get startMeasurementButton;

  /// Qualitative signal-quality label.
  ///
  /// In en, this message translates to:
  /// **'Excellent'**
  String get signalExcellent;

  /// Qualitative signal-quality label.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get signalGood;

  /// Qualitative signal-quality label.
  ///
  /// In en, this message translates to:
  /// **'Weak'**
  String get signalWeak;

  /// Review screen app bar title.
  ///
  /// In en, this message translates to:
  /// **'5. Review & Submit'**
  String get reviewSubmitTitle;

  /// Button that pops back to Pain Details to make a correction.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get editButton;

  /// Label above the not-yet-generated patient ID.
  ///
  /// In en, this message translates to:
  /// **'Anonymous Patient'**
  String get anonymousPatientLabel;

  /// Explanation that the anonymous ID appears after submitting.
  ///
  /// In en, this message translates to:
  /// **'ID generated on submit'**
  String get idGeneratedOnSubmitLabel;

  /// Label above the visit timestamp.
  ///
  /// In en, this message translates to:
  /// **'Timestamp'**
  String get timestampLabel;

  /// Section title over the list of pain points on the review screen.
  ///
  /// In en, this message translates to:
  /// **'Clinical Summary'**
  String get clinicalSummaryTitle;

  /// Heading on each pain point card during review.
  ///
  /// In en, this message translates to:
  /// **'Pain Point {number}'**
  String painPointNumberLabel(int number);

  /// Detail row label for the body region.
  ///
  /// In en, this message translates to:
  /// **'Location'**
  String get locationLabel;

  /// Detail row label for pain severity.
  ///
  /// In en, this message translates to:
  /// **'Intensity'**
  String get intensityLabel;

  /// Section title over the captured vitals on the review screen.
  ///
  /// In en, this message translates to:
  /// **'Vitals'**
  String get vitalsTitle;

  /// Label for the captured heart rate.
  ///
  /// In en, this message translates to:
  /// **'Heart Rate'**
  String get heartRateLabel;

  /// Label for the estimated signal-quality proxy shown as SpO2.
  ///
  /// In en, this message translates to:
  /// **'SpO2 (est.)'**
  String get spo2EstLabel;

  /// Consent notice above the submit button.
  ///
  /// In en, this message translates to:
  /// **'By submitting, you consent to sharing this clinical data with the attending physician for triage purposes.'**
  String get consentSubmitNotice;

  /// Button that saves an offline draft instead of submitting.
  ///
  /// In en, this message translates to:
  /// **'Save Draft'**
  String get saveDraftButton;

  /// Final submit button on the review screen.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get submitButton;

  /// Confirmation snackbar after saving a draft.
  ///
  /// In en, this message translates to:
  /// **'✅ Draft saved offline successfully!'**
  String get draftSavedSnackbar;

  /// Snackbar shown when submission fails and is queued offline instead.
  ///
  /// In en, this message translates to:
  /// **'⚠️ Could not submit — saved offline, will retry automatically: {error}'**
  String submitFailedSavedOfflineSnackbar(String error);

  /// Success screen heading.
  ///
  /// In en, this message translates to:
  /// **'Report Submitted!'**
  String get reportSubmittedTitle;

  /// Label above the generated anonymous patient ID on the success screen.
  ///
  /// In en, this message translates to:
  /// **'Patient ID'**
  String get patientIdLabel;

  /// Reassurance under the QR code.
  ///
  /// In en, this message translates to:
  /// **'No internet required to view'**
  String get noInternetRequiredHint;

  /// Instruction under the QR code.
  ///
  /// In en, this message translates to:
  /// **'Show this QR code to the health worker'**
  String get showQrToHealthWorkerHint;

  /// Risk summary line on the success screen.
  ///
  /// In en, this message translates to:
  /// **'AI Assessment: {label}'**
  String aiAssessmentLabel(String label);

  /// Shown when no risk score is available yet.
  ///
  /// In en, this message translates to:
  /// **'Risk Assessment Pending'**
  String get riskAssessmentPendingLabel;

  /// Risk level with percentage, e.g. 'High Risk (82%)'.
  ///
  /// In en, this message translates to:
  /// **'{level} Risk ({percent}%)'**
  String riskPercentLabel(String level, int percent);

  /// Button that saves the QR code image.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get saveButton;

  /// Button that shares the report link.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shareButton;

  /// Button that opens the patient's own visit history.
  ///
  /// In en, this message translates to:
  /// **'View My Triage History'**
  String get viewHistoryButton;

  /// Button that returns to the very start of the flow.
  ///
  /// In en, this message translates to:
  /// **'Start New Triage'**
  String get startNewTriageButton;

  /// Title of the web share-fallback bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Share Report'**
  String get shareReportSheetTitle;

  /// Share option label.
  ///
  /// In en, this message translates to:
  /// **'WhatsApp'**
  String get whatsappLabel;

  /// Share option label.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get emailLabel;

  /// Share option label.
  ///
  /// In en, this message translates to:
  /// **'SMS'**
  String get smsLabel;

  /// Share option label.
  ///
  /// In en, this message translates to:
  /// **'Copy Link'**
  String get copyLinkLabel;

  /// Confirmation after using Copy Link.
  ///
  /// In en, this message translates to:
  /// **'Link copied to clipboard'**
  String get linkCopiedSnackbar;

  /// Clinical Report app bar title.
  ///
  /// In en, this message translates to:
  /// **'Clinical Report'**
  String get clinicalReportTitle;

  /// Chip shown when a practitioner (not the patient) is viewing the report.
  ///
  /// In en, this message translates to:
  /// **'Practitioner Mode'**
  String get practitionerModeChip;

  /// Fallback error text when a report can't be loaded.
  ///
  /// In en, this message translates to:
  /// **'Report not found'**
  String get reportNotFoundError;

  /// Heading at the top of the report body.
  ///
  /// In en, this message translates to:
  /// **'Clinical Triage Report'**
  String get clinicalTriageReportTitle;

  /// Subtitle under the report heading.
  ///
  /// In en, this message translates to:
  /// **'Simtack Care • Official Document'**
  String get officialDocumentSubtitle;

  /// Caption over the worst-finding risk score in a multi-point visit.
  ///
  /// In en, this message translates to:
  /// **'AI RISK ASSESSMENT (HIGHEST)'**
  String get aiRiskAssessmentHighestLabel;

  /// Notes which body region produced the visit's highest risk score.
  ///
  /// In en, this message translates to:
  /// **'Driven by: {region}'**
  String drivenByLabel(String region);

  /// Section title over the per-point clinical detail cards.
  ///
  /// In en, this message translates to:
  /// **'Clinical Details'**
  String get clinicalDetailsTitle;

  /// Section title variant when the visit has multiple pain points.
  ///
  /// In en, this message translates to:
  /// **'Clinical Details ({count} pain points)'**
  String clinicalDetailsWithCountTitle(int count);

  /// Small heading on each clinical detail card in a multi-point visit.
  ///
  /// In en, this message translates to:
  /// **'Pain Point'**
  String get painPointLabel;

  /// Detail row label for a single pain point's risk score.
  ///
  /// In en, this message translates to:
  /// **'Risk'**
  String get riskLabel;

  /// Detail row label for the submission timestamp.
  ///
  /// In en, this message translates to:
  /// **'Reported At'**
  String get reportedAtLabel;

  /// All-caps section header over the demographics chip list.
  ///
  /// In en, this message translates to:
  /// **'PATIENT PROFILE'**
  String get patientProfileSectionTitle;

  /// Empty state when a patient has no demographics recorded.
  ///
  /// In en, this message translates to:
  /// **'No demographics on file yet.'**
  String get noDemographicsOnFileMessage;

  /// Demographics chip label.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get nameLabel;

  /// Demographics chip label (date of birth, abbreviated).
  ///
  /// In en, this message translates to:
  /// **'DOB'**
  String get dobLabel;

  /// Demographics chip / form field label.
  ///
  /// In en, this message translates to:
  /// **'Gender'**
  String get genderLabel;

  /// Demographics chip / form field label.
  ///
  /// In en, this message translates to:
  /// **'Phone'**
  String get phoneLabel;

  /// Demographics chip label combining next-of-kin name and phone.
  ///
  /// In en, this message translates to:
  /// **'Next of kin'**
  String get nextOfKinShortLabel;

  /// Demographics chip label.
  ///
  /// In en, this message translates to:
  /// **'Hospital'**
  String get hospitalLabel;

  /// Section header over the horizontal visit-history strip (practitioner mode).
  ///
  /// In en, this message translates to:
  /// **'VISIT TIMELINE'**
  String get visitTimelineTitle;

  /// Label on each visit card in the timeline.
  ///
  /// In en, this message translates to:
  /// **'Visit {number}'**
  String visitNumberLabel(int number);

  /// Compact pain-point count on a visit timeline card.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 pt} other{{count} pts}}'**
  String ptCountLabel(int count);

  /// Section header over the SHAP risk-factor breakdown.
  ///
  /// In en, this message translates to:
  /// **'WHY THIS SCORE?'**
  String get whyThisScoreTitle;

  /// Fallback label for a risk factor with no description.
  ///
  /// In en, this message translates to:
  /// **'Unknown factor'**
  String get unknownFactorLabel;

  /// Section header over the practitioner decision card.
  ///
  /// In en, this message translates to:
  /// **'TRIAGE DECISION'**
  String get triageDecisionTitle;

  /// Label before the AI-suggested priority in the decision card.
  ///
  /// In en, this message translates to:
  /// **'Suggested Priority'**
  String get suggestedPriorityLabel;

  /// Label before the open/closed status chips in the decision card.
  ///
  /// In en, this message translates to:
  /// **'Status:'**
  String get statusColonLabel;

  /// Label over the checklist of recommended actions.
  ///
  /// In en, this message translates to:
  /// **'Recommended Actions'**
  String get recommendedActionsLabel;

  /// Hint text on the practitioner's free-text notes field.
  ///
  /// In en, this message translates to:
  /// **'Clinical notes...'**
  String get clinicalNotesHint;

  /// Button that saves the practitioner's triage decision.
  ///
  /// In en, this message translates to:
  /// **'Save Decision'**
  String get saveDecisionButton;

  /// Confirmation after saving a triage decision.
  ///
  /// In en, this message translates to:
  /// **'Decision saved.'**
  String get decisionSavedSnackbar;

  /// Title of the demographics edit bottom sheet.
  ///
  /// In en, this message translates to:
  /// **'Edit Patient Demographics'**
  String get editPatientDemographicsTitle;

  /// Button that saves edited demographics.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get saveChangesButton;

  /// Validation error on the demographics edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Age, gender, weight, and height are required.'**
  String get ageGenderWeightHeightRequiredError;

  /// Hospital field label on the demographics edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Hospital / Facility'**
  String get hospitalFacilityLabel;

  /// Weight field label on the demographics edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Weight (kg)'**
  String get weightKgLabel;

  /// Height field label on the demographics edit sheet.
  ///
  /// In en, this message translates to:
  /// **'Height (cm)'**
  String get heightCmLabel;
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
