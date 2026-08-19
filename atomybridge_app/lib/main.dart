import 'package:flutter/material.dart';
import 'core/theme/app_theme.dart';
import 'features/onboarding/ui/welcome_screen.dart';

void main() {
  runApp(const AtomyBridgeApp());
}

class AtomyBridgeApp extends StatelessWidget {
  const AtomyBridgeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AtomyBridge Care',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      home: const WelcomeScreen(),
    );
  }
}