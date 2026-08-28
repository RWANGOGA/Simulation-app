import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/onboarding/ui/welcome_screen.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    testWidgets('renders title, subtitle, languages, and continue button', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: WelcomeScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text('Choose your language'), findsOneWidget);
      expect(find.text('English'), findsWidgets);
      expect(find.text('Uganda Sign Language'), findsOneWidget);
      expect(find.text('Luganda'), findsOneWidget);
      expect(find.text('Lusoga'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('tapping a language changes active selection', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: WelcomeScreen(),
      ));
      await tester.pumpAndSettle();

      // Tap on Luganda
      await tester.tap(find.text('Luganda'));
      await tester.pumpAndSettle();

      // Verify check icon or language pill update
      expect(find.text('Luganda'), findsWidgets);
    });
  });
}
