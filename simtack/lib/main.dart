import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/ui/login_screen.dart';
import 'features/onboarding/ui/welcome_screen.dart';
import 'features/report/ui/clinical_report_screen.dart';

void main() {
  runApp(const AtomyBridgeApp());
}

class AtomyBridgeApp extends StatelessWidget {
  const AtomyBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Read the URL fragment (the part after the '#' symbol)
    final String fragment = Uri.base.fragment;
    
    // 2. Determine the route
    String? reportPatientId;
    bool isDashboard = false;

    if (fragment.startsWith('/report/')) {
      reportPatientId = fragment.replaceFirst('/report/', '');
    } else if (fragment == '/dashboard') {
      isDashboard = true;
    }

    // 3. Determine the initial screen based on the URL
    // '/dashboard' opens the practitioner login gate, not the dashboard
    // itself — LoginScreen pushes on to PractitionerDashboardScreen only
    // after a successful sign-in.
    final Widget initialScreen = isDashboard
        ? const LoginScreen()
        : (reportPatientId != null
            ? ClinicalReportScreen(patientId: reportPatientId)
            : const WelcomeScreen());

    // REAL APP: Use the dynamic routing we just tested
    return MaterialApp(
      title: 'Simtack',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: initialScreen, // <-- This brings your real app back!
    );
  }
}