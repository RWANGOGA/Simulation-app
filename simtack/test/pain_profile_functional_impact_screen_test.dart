import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/body_map/ui/pain_profile_functional_impact_screen.dart';
import 'package:simtack/features/body_map/ui/pain_point.dart';
import 'package:simtack/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  group('PainProfileFunctionalImpactScreen Widget Tests', () {
    testWidgets('renders all section headers and initial options', (WidgetTester tester) async {
      final points = [
        PainPoint(region: 'Lower Back', x: 0.5, y: 0.5),
      ];

      await tester.pumpWidget(_wrap(PainProfileFunctionalImpactScreen(
        painPoints: points,
        patientId: 101,
      )));
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.text('4 & 5. PAIN PROFILE & FUNCTIONAL IMPACT'), findsOneWidget);

      // Verify Section A
      expect(find.text('SECTION A: PAIN EXPANSION BEHAVIOR'), findsOneWidget);
      expect(find.text('STAYS SMALL'), findsOneWidget);
      expect(find.text('SPREADING'), findsOneWidget);
      expect(find.text('MULTIPLYING'), findsOneWidget);

      // Verify Section B
      expect(find.text('SECTION B: ACTIONS & TRIGGERS'), findsOneWidget);
      expect(find.text('Walking / Moving'), findsOneWidget);
      expect(find.text('Resting Flat'), findsOneWidget);

      // Verify Section C
      expect(find.text('SECTION C: DAILY LIFE LIMITATIONS'), findsOneWidget);
      expect(find.text('CANNOT SLEEP'), findsOneWidget);
      expect(find.text('CANNOT WALK'), findsOneWidget);

      // Verify Bottom Button
      expect(find.text('PROCEED TO REVIEW & SUBMIT'), findsOneWidget);
    });

    testWidgets('toggles triggers, relievers, and daily limitations on tap', (WidgetTester tester) async {
      final point = PainPoint(region: 'Left Shoulder', x: 0.3, y: 0.3);

      await tester.pumpWidget(_wrap(PainProfileFunctionalImpactScreen(
        painPoints: [point],
        patientId: 101,
      )));
      await tester.pumpAndSettle();

      // Tap 'Spreading' expansion behavior
      await tester.tap(find.text('SPREADING'));
      await tester.pumpAndSettle();
      expect(point.expansionBehavior, 'Spreading');

      // Tap 'Walking / Moving' trigger
      await tester.tap(find.text('Walking / Moving'));
      await tester.pumpAndSettle();
      expect(point.triggers, contains('Walking / Moving'));

      // Tap 'Resting Flat' reliever
      await tester.tap(find.text('Resting Flat'));
      await tester.pumpAndSettle();
      expect(point.relievers, contains('Resting Flat'));

      // Tap 'CANNOT SLEEP' limitation
      final cannotSleepFinder = find.text('CANNOT SLEEP');
      await tester.ensureVisible(cannotSleepFinder);
      await tester.tap(cannotSleepFinder);
      await tester.pumpAndSettle();
      expect(point.dailyLimitations, contains('Cannot Sleep'));
    });
  });
}
