import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/accessibility/accessibility_controller.dart';
import 'core/locale/locale_controller.dart';
import 'core/locale/luganda_fallback_delegates.dart';
import 'core/network/auth_service.dart';

import 'core/theme/app_theme.dart';
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
  final AccessibilityController accessibility = await AccessibilityController.load();

  // 3. Restore the patient's language & consent choice (blueprint §1) —
  // determines whether LanguageScreen or WelcomeScreen opens first.
  final LocaleController locale = await LocaleController.load();

  // 4. Check if the doctor is already logged in before the app even draws the first pixel
  final bool isDoctorLoggedIn = await AuthService.instance.isLoggedIn;

  // 5. Pass this state to the root widget
  runApp(AtomyBridgeApp(
    isDoctorLoggedIn: isDoctorLoggedIn,
    accessibility: accessibility,
    locale: locale,
  ));
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

  @override
  void initState() {
    super.initState();
    // Rebuild the MaterialApp whenever text size or theme mode changes so
    // the new setting applies to EVERY screen instantly.
    _accessibility.addListener(_onAccessibilityChanged);
    _locale.addListener(_onAccessibilityChanged);
  }

  @override
  void dispose() {
    _accessibility.removeListener(_onAccessibilityChanged);
    _locale.removeListener(_onAccessibilityChanged);
    super.dispose();
  }

  void _onAccessibilityChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // 1. Read the URL fragment (the part after the '#' symbol, used for deep linking)
    final String fragment = Uri.base.fragment;
    
    // 2. Determine the route from the URL.
    // The #/dashboard deep link only counts when the doctor is ACTUALLY
    // logged in, so typing the URL alone can't bypass authentication.
    String? reportPatientId;
    bool isDashboardFromUrl = fragment == '/dashboard' && widget.isDoctorLoggedIn;

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

    return A11yScope(
      controller: _accessibility,
      child: MaterialApp(
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
          // Luganda — these fall back to English for framework-owned
          // chrome text only (see luganda_fallback_delegates.dart).
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
    );
  }
}
