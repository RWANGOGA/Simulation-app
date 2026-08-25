import 'package:flutter/material.dart';

import 'core/accessibility/accessibility_controller.dart';
import 'core/network/auth_service.dart';

import 'core/theme/app_theme.dart';
import 'features/dashboard/ui/practitioner_dashboard_screen.dart';
import 'features/onboarding/ui/welcome_screen.dart';
import 'features/report/ui/clinical_report_screen.dart';
import 'features/settings/ui/accessibility_settings_screen.dart';

void main() async {
  // 1. We MUST initialize Flutter bindings before calling async functions in main()
  WidgetsFlutterBinding.ensureInitialized();

  // 2. Restore accessibility preferences (text size, light/dark) before the
  // first frame so the app never flashes in the wrong theme or scale.
  final AccessibilityController accessibility = await AccessibilityController.load();

  // 3. Check if the doctor is already logged in before the app even draws the first pixel
  final bool isDoctorLoggedIn = await AuthService.instance.isLoggedIn;
  
  // 4. Pass this state to the root widget
  runApp(AtomyBridgeApp(
    isDoctorLoggedIn: isDoctorLoggedIn,
    accessibility: accessibility,
  ));
}

class AtomyBridgeApp extends StatefulWidget {
  final bool isDoctorLoggedIn;

  /// Loaded in main(); tests may omit it and get unsaved defaults.
  final AccessibilityController? accessibility;

  const AtomyBridgeApp({
    super.key,
    required this.isDoctorLoggedIn,
    this.accessibility,
  });

  @override
  State<AtomyBridgeApp> createState() => _AtomyBridgeAppState();
}

class _AtomyBridgeAppState extends State<AtomyBridgeApp> {
  late final AccessibilityController _accessibility =
      widget.accessibility ?? AccessibilityController();

  @override
  void initState() {
    super.initState();
    // Rebuild the MaterialApp whenever text size or theme mode changes so
    // the new setting applies to EVERY screen instantly.
    _accessibility.addListener(_onAccessibilityChanged);
  }

  @override
  void dispose() {
    _accessibility.removeListener(_onAccessibilityChanged);
    super.dispose();
  }

  void _onAccessibilityChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    // 1. Read the URL fragment (the part after the '#' symbol, used for deep linking)
    final String fragment = Uri.base.fragment;
    
    // 2. Determine the route from the URL.
    // The #/dashboard deep link only counts when the doctor is ACTUALLY
    // logged in — previously anyone could open the dashboard by typing the
    // URL, bypassing authentication entirely.
    String? reportPatientId;
    bool isDashboardFromUrl = fragment == '/dashboard' && widget.isDoctorLoggedIn;

    if (fragment.startsWith('/report/')) {
      reportPatientId = fragment.replaceFirst('/report/', '');
    }

    // 3. THE FORK IN THE ROAD: Determine the initial screen
    // If the doctor is logged in, bypass the patient flow and go straight to the dashboard.
    // Otherwise, respect the patient deep links (report) or default to the Welcome Screen.
    final Widget initialScreen = widget.isDoctorLoggedIn || isDashboardFromUrl
        ? const PractitionerDashboardScreen()
        : (reportPatientId != null 
            ? ClinicalReportScreen(patientId: reportPatientId) 
            : const WelcomeScreen());

    return A11yScope(
      controller: _accessibility,
      child: MaterialApp(
        title: 'Simtack',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.lightTheme,
        darkTheme: AppTheme.darkTheme,
        themeMode: _accessibility.themeMode,
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
