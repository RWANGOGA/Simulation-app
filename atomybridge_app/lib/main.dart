import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/ui/welcome_screen.dart';
import 'features/report/ui/clinical_report_screen.dart'; // <-- NEW: Import the report screen

void main() {
  runApp(const AtomyBridgeApp());
}

class AtomyBridgeApp extends StatelessWidget {
  const AtomyBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    // 1. Read the URL fragment (the part after the '#' symbol)
    final String fragment = Uri.base.fragment;
    
    // 2. Check if it's a clinical report route (e.g., #/report/P-BHRXBWXP927T)
    String? reportPatientId;
    if (fragment.startsWith('/report/')) {
      reportPatientId = fragment.replaceFirst('/report/', '');
    }

    // 3. Determine the initial screen based on the URL
    final Widget initialScreen = reportPatientId != null
        ? ClinicalReportScreen(patientId: reportPatientId)
        : const WelcomeScreen();

    return MaterialApp(
      title: 'AtomyBridge Care',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: initialScreen, // <-- Use the dynamic screen
    );
  }
}