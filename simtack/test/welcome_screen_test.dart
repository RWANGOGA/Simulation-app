import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/features/onboarding/ui/welcome_screen.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('renders title, subtitle, and continue button', (WidgetTester tester) async {
      // Language is now chosen once, earlier, on LanguageScreen (see
      // language_screen_test.dart) — WelcomeScreen no longer has its own
      // language picker.
      await tester.pumpWidget(const MaterialApp(
        home: WelcomeScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text("Let's get started"), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Practitioner Login'), findsOneWidget);
    });
  });
}
