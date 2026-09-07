import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/patient_info/ui/patient_info_screen.dart';

void main() {
  group('PatientInfoScreen Widget Tests', () {
    testWidgets('renders profile header, inputs, and submit button', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PatientInfoScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Patient Profile'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Date of Birth'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      // The old separate "Age" number prompt is gone — there is now a single
      // date-of-birth calendar field instead.
      expect(find.text('Age'), findsNothing);
    });

    testWidgets('shows validation error when submitting empty form', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PatientInfoScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Date of Birth is required'), findsOneWidget);
      expect(find.text('Weight is required'), findsOneWidget);
      expect(find.text('Height is required'), findsOneWidget);
    });

    testWidgets('date of birth field opens a calendar and derives age', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PatientInfoScreen(),
      ));
      await tester.pumpAndSettle();

      // Tapping the date-of-birth field opens the calendar date picker.
      await tester.tap(find.byKey(const Key('date_of_birth_field')));
      await tester.pumpAndSettle();
      expect(find.text('DATE OF BIRTH'), findsOneWidget);

      // Confirm with the initially-focused date (Jan 1, now - 30 years) so the
      // picker returns a value without needing a fragile day-grid tap.
      await tester.tap(find.text('OK'));
      await tester.pumpAndSettle();

      final now = DateTime.now();
      final expectedDob = '1 Jan ${now.year - 30}';
      expect(find.text(expectedDob), findsOneWidget);
      expect(find.text('Age: 30 years'), findsOneWidget);
    });
  });
}
