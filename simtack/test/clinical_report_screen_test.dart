import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simtack/features/report/ui/clinical_report_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

import 'support/offline_fixtures.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  // Every test here reads the device's own records, so there is no HTTP client
  // and no token storage to arrange — only a store to fill.
  setUp(setUpOfflineWorld);

  group('ClinicalReportScreen Widget Tests', () {
    testWidgets('an unknown patient code shows the error, not a blank report',
        (WidgetTester tester) async {
      await tester.pumpWidget(
          _wrap(const ClinicalReportScreen(patientId: 'P-NOSUCHCODE1')));

      await tester.pumpAndSettle();

      // The watermark is behind every state of this screen — it is a clinical
      // document and must never be mistaken for a blank page.
      expect(find.text('SIMTACK'), findsOneWidget);
      expect(find.text('Report not found'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('Visit timeline (T2)', () {
    testWidgets('practitioner sees the timeline and can switch visits',
        (tester) async {
      final patient = await seedPatient();
      // Two visits: an older one with two pain points, then a newer one.
      // Written oldest-first so the ordering under test comes from the store,
      // not from the order of insertion.
      await fileReport(
        patientCode: patient.code,
        region: 'Head',
        visitId: 'visit-a',
        createdAt: '2026-08-01T09:00:00',
      );
      await fileReport(
        patientCode: patient.code,
        region: 'Left Arm',
        visitId: 'visit-a',
        createdAt: '2026-08-01T09:05:00',
      );
      await fileReport(
        patientCode: patient.code,
        region: 'Chest',
        visitId: 'visit-b',
        createdAt: '2026-08-20T10:00:00',
      );

      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(ClinicalReportScreen(
          patientId: patient.code, practitionerMode: true)));
      await tester.pumpAndSettle();

      expect(find.text('VISIT TIMELINE'), findsOneWidget);
      expect(find.text('Visit 1'), findsOneWidget); // oldest
      expect(find.text('Visit 2'), findsOneWidget); // newest, selected

      // Newest visit selected by default -> its pain points are shown.
      expect(find.text('Chest'), findsWidgets);

      // Switch to the older visit -> its pain points replace them.
      await tester.tap(find.text('Visit 1'));
      await tester.pumpAndSettle();
      expect(find.text('Head'), findsWidgets);
      expect(find.text('Left Arm'), findsWidgets);
      expect(find.text('Chest'), findsNothing);
    });

    testWidgets('patients never see the timeline', (tester) async {
      final patient = await seedPatient();
      await fileReport(
        patientCode: patient.code,
        region: 'Head',
        visitId: 'visit-a',
        createdAt: '2026-08-01T09:00:00',
      );

      await tester
          .pumpWidget(_wrap(ClinicalReportScreen(patientId: patient.code)));
      await tester.pumpAndSettle();

      expect(find.text('VISIT TIMELINE'), findsNothing);
      expect(find.text('Head'), findsWidgets);
    });
  });

  group('SHAP factor bars (T1)', () {
    testWidgets('renders proportional bars with signed percentages',
        (tester) async {
      // The device's own explanation is replaced here because this test is
      // about the bars: their width and their signed percentage labels.
      final shap = jsonEncode([
        {'factor': 'Severity 5/10', 'shap': 0.25, 'impact': '+'},
        {'factor': 'Region: Chest', 'shap': 0.15, 'impact': '+'},
        {'factor': 'Pain type: throbbing', 'shap': 0.05, 'impact': '+'},
      ]);
      final patient = await seedPatient();
      await fileReport(
        patientCode: patient.code,
        region: 'Chest',
        visitId: 'visit-a',
        createdAt: '2026-08-01T09:00:00',
        shapExplanation: shap,
      );

      // A populated patient card pushes the breakdown below the fold at the
      // default 800x600 viewport, and a tap on it would miss.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester
          .pumpWidget(_wrap(ClinicalReportScreen(patientId: patient.code)));
      await tester.pumpAndSettle();

      expect(find.text('WHY THIS SCORE?'), findsOneWidget);

      // The breakdown starts collapsed on purpose, so the bars only exist
      // once the practitioner opens it.
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      expect(find.text('+25%'), findsOneWidget);
      expect(find.text('+15%'), findsOneWidget);
      expect(find.text('+5%'), findsOneWidget);
      expect(find.text('Severity 5/10'), findsOneWidget);
      // One bar track + fill per factor.
      expect(find.byType(FractionallySizedBox), findsNWidgets(3));
    });

    testWidgets('legacy explanation without impact key still renders',
        (tester) async {
      final shap = jsonEncode([
        {'factor': 'Severity 8/10', 'shap': 0.4},
      ]);
      final patient = await seedPatient();
      await fileReport(
        patientCode: patient.code,
        region: 'Chest',
        visitId: 'visit-a',
        createdAt: '2026-08-01T09:00:00',
        shapExplanation: shap,
      );

      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester
          .pumpWidget(_wrap(ClinicalReportScreen(patientId: patient.code)));
      await tester.pumpAndSettle();

      // The breakdown starts collapsed on purpose, so the bars only exist
      // once the practitioner opens it.
      await tester.tap(find.byType(ExpansionTile));
      await tester.pumpAndSettle();

      expect(find.text('+40%'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsOneWidget);
    });

    testWidgets('a record filed by an older version does not resurface SpO2',
        (tester) async {
      // The row below is what a device that ran the previous version stored:
      // the score and the breakdown were written by an engine that still had a
      // term for the camera's SpO2 estimate. Neither the number nor its label
      // is something this app can verify or stand behind any more, and a
      // practitioner reading "SpO2 88.0%" on a report will act on it as if it
      // were pulse oximetry. The stored record is not rewritten; it is simply
      // not presented as current reasoning.
      final shap = jsonEncode([
        {'factor': 'Severity 8/10', 'shap': 0.35, 'impact': '+'},
        {'factor': 'SpO2 88.0%', 'shap': 0.15, 'impact': '+'},
        {'factor': 'Heart rate 112.0 bpm', 'shap': 0.1, 'impact': '+'},
      ]);
      final patient = await seedPatient();
      await fileReport(
        patientCode: patient.code,
        region: 'Chest',
        painType: 'sharp',
        severity: 8,
        visitId: 'visit-a',
        createdAt: '2026-08-01T09:00:00',
        shapExplanation: shap,
      );

      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(ClinicalReportScreen(
          patientId: patient.code, practitionerMode: true)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(ExpansionTile, 'WHY THIS SCORE?'));
      await tester.pumpAndSettle();

      expect(find.textContaining('SpO2', skipOffstage: false), findsNothing);
      // Everything else on the report still renders: this is a filter on one
      // retired factor, not a report that stops opening.
      expect(find.text('Severity 8/10'), findsOneWidget);
      expect(find.text('Heart rate 112.0 bpm'), findsOneWidget);
    });
  });
}
