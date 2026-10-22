import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simtack/features/dashboard/ui/reports_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

import 'support/offline_fixtures.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  // The screen totals whatever the device holds, so each test fills the store
  // rather than answering an HTTP mock.
  setUp(setUpOfflineWorld);

  testWidgets('renders aggregates over the records on this device',
      (tester) async {
    final patient = await seedPatient();
    await fileReport(
      patientCode: patient.code,
      region: 'Chest / Heart',
      painType: 'Sharp',
      severity: 7,
      riskScore: 0.80, // HIGH
    );
    await fileReport(
      patientCode: patient.code,
      region: 'Chest / Heart',
      painType: 'Sharp',
      severity: 6,
      riskScore: 0.45, // MEDIUM
    );
    await fileReport(
      patientCode: patient.code,
      region: 'Headache / Cranial',
      painType: 'Throbbing',
      severity: 6,
      riskScore: 0.20, // LOW
      status: 'closed',
    );

    await tester.pumpWidget(_wrap(const ReportsScreen()));
    await tester.pumpAndSettle();

    // Matches both the screen's own header and the sidebar's "Reports" nav label.
    expect(find.text('Reports'), findsWidgets);
    expect(find.text('3'), findsWidgets); // Total Sessions
    expect(find.text('2'), findsWidgets); // Open count (stat card + legend)
    expect(find.text('6.3/10'), findsOneWidget); // (7 + 6 + 6) / 3, rounded
    expect(find.text('0.48'), findsOneWidget); // (0.80 + 0.45 + 0.20) / 3
    expect(find.text('Chest / Heart'), findsOneWidget);
    expect(find.text('Headache / Cranial'), findsOneWidget);
    expect(find.text('Sharp'), findsOneWidget);
    expect(find.text('Throbbing'), findsOneWidget);
  });

  testWidgets('shows a real empty state when there are no sessions yet',
      (tester) async {
    await tester.pumpWidget(_wrap(const ReportsScreen()));
    await tester.pumpAndSettle();

    expect(find.textContaining('No triage sessions in this period'),
        findsOneWidget);
  });

  testWidgets('refresh re-reads the store, so a new record shows up',
      (tester) async {
    final patient = await seedPatient();
    await fileReport(
      patientCode: patient.code,
      region: 'Chest / Heart',
      painType: 'Sharp',
      severity: 5,
    );

    await tester.pumpWidget(_wrap(const ReportsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('2'), findsNothing); // one session, so no "2" anywhere

    // A second patient submits while the practitioner has the screen open.
    await fileReport(
      patientCode: patient.code,
      region: 'Headache / Cranial',
      painType: 'Sharp',
      severity: 5,
    );
    await tester.tap(find.byIcon(Icons.refresh));
    await tester.pumpAndSettle();

    expect(find.text('2'), findsWidgets);
  });
}
