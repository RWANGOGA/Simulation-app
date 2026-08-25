import 'package:flutter/material.dart';

import 'core/network/auth_service.dart';

import 'core/theme/app_theme.dart';
import 'features/dashboard/ui/practitioner_dashboard_screen.dart';
import 'features/onboarding/ui/welcome_screen.dart';
import 'features/report/ui/clinical_report_screen.dart';

void main() async {
  // 1. We MUST initialize Flutter bindings before calling async functions in main()
  WidgetsFlutterBinding.ensureInitialized();
  
  // 2. Check if the doctor is already logged in before the app even draws the first pixel
  final bool isDoctorLoggedIn = await AuthService.instance.isLoggedIn;
  
  // 3. Pass this state to the root widget
  runApp(AtomyBridgeApp(isDoctorLoggedIn: isDoctorLoggedIn));
}

class AtomyBridgeApp extends StatelessWidget {
  final bool isDoctorLoggedIn;

  const AtomyBridgeApp({super.key, required this.isDoctorLoggedIn});

  @override
  Widget build(BuildContext context) {
    // 1. Read the URL fragment (the part after the '#' symbol, used for deep linking)
    final String fragment = Uri.base.fragment;
    
    // 2. Determine the route from the URL
    String? reportPatientId;
    bool isDashboardFromUrl = fragment == '/dashboard';

    if (fragment.startsWith('/report/')) {
      reportPatientId = fragment.replaceFirst('/report/', '');
    }

    // 3. THE FORK IN THE ROAD: Determine the initial screen
    // If the doctor is logged in, bypass the patient flow and go straight to the dashboard.
    // Otherwise, respect the patient deep links (report) or default to the Welcome Screen.
    final Widget initialScreen = isDoctorLoggedIn || isDashboardFromUrl
        ? const PractitionerDashboardScreen()
        : (reportPatientId != null 
            ? ClinicalReportScreen(patientId: reportPatientId) 
            : const WelcomeScreen());

    return MaterialApp(
      title: 'Simtack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      
      // 4. The app starts exactly where it is supposed to!
      home: initialScreen, 
    );
  }
}