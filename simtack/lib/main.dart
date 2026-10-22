import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/accessibility/accessibility_controller.dart';
import 'core/clinical/clinical_data.dart';
import 'core/locale/locale_controller.dart';
import 'core/locale/luganda_fallback_delegates.dart';
import 'core/network/api_client.dart';
import 'core/network/auth_service.dart';
import 'core/offline/sync_service.dart';

import 'core/theme/app_page_route.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/dashboard/ui/practitioner_dashboard_screen.dart';
import 'features/onboarding/ui/language_screen.dart';
import 'features/onboarding/ui/welcome_screen.dart';
import 'features/report/ui/clinical_report_screen.dart';
import 'features/settings/ui/accessibility_settings_screen.dart';
import 'l10n/app_localizations.dart';

void main() async {
  // 1. We MUST initialize Flutter bindings before calling async functions in main()
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Restore accessibility preferences (text size, light/dark) before the
  // first frame so the app never flashes in the wrong theme or scale.
  final AccessibilityController accessibility =
      await AccessibilityController.load();

  // 3. Restore the patient's language & consent choice (blueprint §1) —
  // determines whether LanguageScreen or WelcomeScreen opens first.
  final LocaleController locale = await LocaleController.load();

  // 4. Load the clinical rules, body graph and knowledge base from the bundle.
  // Scoring a report needs these and they are the only copy the app has, so they
  // are in memory before any screen can be used. A failure here is not a soft
  // error: without the rule table every report would have to be refused, so the
  // app says so on the first screen instead of letting a patient fill in a
  // whole form that cannot be assessed.
  try {
    await ClinicalData.load();
  } catch (error) {
    runApp(ClinicalAssetsUnavailableApp(reason: error.toString()));
    return;
  }

  // 5. Decide what to open with before the first pixel. A token on disk is no
  // longer enough: the session is confirmed against the server whenever it can
  // be reached, so a deactivated account no longer opens a dashboard whose
  // every request fails. The wait is bounded — a slow or sleeping backend must
  // not hold up the first frame, and any later API call still surfaces the
  // revocation through ApiClient.onSessionExpired.
  final bool isDoctorLoggedIn = await AuthService.instance
      .restoreSession()
      .timeout(const Duration(seconds: 5), onTimeout: () => true);

  // 6. Start pushing what this device recorded to the server, whenever it can be
  // reached. Deliberately not awaited: the app is fully usable without it, and
  // nothing in the UI should ever wait for a network round-trip.
  SyncService.instance.start();

  // 7. Pass this state to the root widget
  runApp(AtomyBridgeApp(
    isDoctorLoggedIn: isDoctorLoggedIn,
    accessibility: accessibility,
    locale: locale,
  ));
}

/// Shown when the bundled clinical assets could not be read.
///
/// The app has no fallback for the rule table — inventing weights would mean
/// scoring patients differently from the server, which is the one thing the
/// device is not allowed to do — so this is a dead end that has to be visible
/// rather than a crash part-way through an assessment.
class ClinicalAssetsUnavailableApp extends StatelessWidget {
  final String reason;

  const ClinicalAssetsUnavailableApp({super.key, required this.reason});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.report_problem_outlined,
                      size: 56, color: Color(0xFFB91C1C)),
                  const SizedBox(height: 16),
                  const Text(
                    'Clinical data failed to load',
                    textAlign: TextAlign.center,
                    style:
                        TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The risk rules that score a report ship inside the app and '
                    'could not be read. Patient reports cannot be assessed '
                    'until this is fixed, so the app has stopped instead of '
                    'guessing. Reinstall the app, or report this to your '
                    'administrator.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    reason,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class AtomyBridgeApp extends StatefulWidget {
  final bool isDoctorLoggedIn;

  /// Loaded in main(); tests may omit it and get unsaved defaults.
  final AccessibilityController? accessibility;

  /// Loaded in main(); tests may omit it and get unsaved defaults (which
  /// means LanguageScreen shows up in widget tests too, same as it would
  /// on a real first launch).
  final LocaleController? locale;

  const AtomyBridgeApp({
    super.key,
    required this.isDoctorLoggedIn,
    this.accessibility,
    this.locale,
  });

  @override
  State<AtomyBridgeApp> createState() => _AtomyBridgeAppState();
}

class _AtomyBridgeAppState extends State<AtomyBridgeApp> {
  late final AccessibilityController _accessibility =
      widget.accessibility ?? AccessibilityController();
  late final LocaleController _locale = widget.locale ?? LocaleController();

  /// Needed so [ApiClient] can drop the practitioner back on the login screen
  /// from anywhere once a session can no longer be refreshed.
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    // Rebuild the MaterialApp whenever text size or theme mode changes so
    // the new setting applies to EVERY screen instantly.
    _accessibility.addListener(_onAccessibilityChanged);
    _locale.addListener(_onAccessibilityChanged);
    ApiClient.onSessionExpired = _returnToLogin;
  }

  @override
  void dispose() {
    _accessibility.removeListener(_onAccessibilityChanged);
    _locale.removeListener(_onAccessibilityChanged);
    ApiClient.onSessionExpired = null;
    super.dispose();
  }

  void _onAccessibilityChanged() => setState(() {});

  /// The access token expired and could not be refreshed: wipe the practitioner
  /// stack so no stale protected screen stays reachable.
  void _returnToLogin() {
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    // 1. Read the URL fragment (the part after the '#' symbol, used for deep linking)
    final String fragment = Uri.base.fragment;

    // 2. Determine the route from the URL.
    // The #/dashboard deep link only counts when the doctor is ACTUALLY
    // logged in, so typing the URL alone can't bypass authentication.
    String? reportPatientId;
    bool isDashboardFromUrl =
        fragment == '/dashboard' && widget.isDoctorLoggedIn;

    if (fragment.startsWith('/report/')) {
      reportPatientId = fragment.replaceFirst('/report/', '');
    }

    // 3. THE FORK IN THE ROAD: Determine the initial screen
    // If the doctor is logged in, bypass the patient flow and go straight to the dashboard.
    // A deep-linked report is next. Otherwise: the language & consent
    // screen (blueprint §1) gates the patient flow until accepted once,
    // then every later launch skips straight to Welcome.
    final Widget initialScreen = widget.isDoctorLoggedIn || isDashboardFromUrl
        ? const PractitionerDashboardScreen()
        : (reportPatientId != null
            ? ClinicalReportScreen(patientId: reportPatientId)
            : (_locale.hasConsented
                ? const WelcomeScreen()
                : LanguageScreen(localeController: _locale)));

    return LocaleScope(
      controller: _locale,
      child: A11yScope(
        controller: _accessibility,
        child: MaterialApp(
          navigatorKey: _navigatorKey,
          title: 'Simtack',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.lightTheme,
          darkTheme: AppTheme.darkTheme,
          themeMode: _accessibility.themeMode,
          locale: _locale.locale,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            // Flutter's own Material/Cupertino localizations don't ship
            // Luganda, Runyankore, or Lusoga — these fall back to English
            // for framework-owned chrome text only.
            LugandaMaterialLocalizationsDelegate(),
            LugandaCupertinoLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          // Accessibility text size: scales ALL text in the app at once.
          // This SDK's MaterialApp has no textScaler parameter, so we
          // override the ambient MediaQuery instead (device font setting
          // still multiplies in via mediaQuery.textScaler).
          builder: (context, child) {
            final mediaQuery = MediaQuery.of(context);
            return MediaQuery(
              data: mediaQuery.copyWith(
                textScaler: TextScaler.linear(
                  mediaQuery.textScaler.scale(_accessibility.fontScale),
                ),
              ),
              child: child!,
            );
          },

          // 4. The app starts exactly where it is supposed to!
          home: initialScreen,
        ),
      ),
    );
  }
}
