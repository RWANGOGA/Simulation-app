import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/patient_info/ui/patient_info_screen.dart';

void main() {
  group('PatientInfoScreen Widget Tests', () {
    testWidgets('renders patient profile header, inputs, and submit button', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PatientInfoScreen(),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Patient Profile'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Age'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('shows validation error when submitting empty form', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PatientInfoScreen(),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Age is required'), findsOneWidget);
      expect(find.text('Weight is required'), findsOneWidget);
      expect(find.text('Height is required'), findsOneWidget);
    });

    testWidgets('validates out of range values', (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: PatientInfoScreen(),
      ));
      await tester.pumpAndSettle();

      // Enter invalid age (first TextFormField)
      await tester.enterText(find.byType(TextFormField).at(0), '150');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Age must be between 0 and 120'), findsOneWidget);
    });
  });
}
