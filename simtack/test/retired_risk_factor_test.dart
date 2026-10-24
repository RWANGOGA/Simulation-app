import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simtack/core/clinical/retired_factors.dart';
import 'package:simtack/core/widgets/shap_explanation_card.dart';
import 'package:simtack/features/report/ui/shap_explanation_widget.dart';
import 'package:simtack/l10n/app_localizations.dart';

/// The breakdown exactly as a device or server running the previous version
/// wrote it. The SpO2 line is what the old scoring input produced: the camera's
/// perfusion proxy, labelled as if it were an oxygen saturation.
const legacyExplanation = '''
[
  {"factor": "Severity 8/10", "shap": 0.35, "impact": "+"},
  {"factor": "SpO2 88.0%", "shap": 0.15, "impact": "+"},
  {"factor": "Heart rate 112.0 bpm", "shap": 0.1, "impact": "+"}
]
''';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(width: 420, child: child),
        ),
      ),
    );

void main() {
  group('retired factor predicate', () {
    test('catches the labels the old engines actually wrote', () {
      expect(isRetiredRiskFactor('SpO2 88.0%'), isTrue);
      expect(isRetiredRiskFactor('SpO2 93.5%'), isTrue);
      expect(isRetiredRiskFactor('  SpO2 88.0%'), isTrue);
      // The typographic variant, so a relabelled record cannot slip through.
      expect(isRetiredRiskFactor('SpO₂ 88.0%'), isTrue);
    });

    test('leaves every factor the app still computes alone', () {
      for (final label in [
        'Severity 8/10',
        'Heart rate 112.0 bpm',
        'BMI 32.0 (weight/height)',
        'Region: Chest / Heart',
        'Pain type: sharp',
        'Connected to reported Left Arm',
      ]) {
        expect(isRetiredRiskFactor(label), isFalse, reason: label);
      }
    });
  });

  group('explanation widgets never render a retired factor', () {
    testWidgets('the report breakdown', (tester) async {
      await tester.pumpWidget(_wrap(const ShapExplanationWidget(
        shapExplanation: legacyExplanation,
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('SpO2', skipOffstage: false), findsNothing);
      expect(find.text('Severity 8/10'), findsOneWidget);
      expect(find.text('Heart rate 112.0 bpm'), findsOneWidget);
      // The count on the header is the number of factors shown, so a retired
      // one must not be counted either.
      expect(find.text('2 factors'), findsOneWidget);
    });

    testWidgets('the compact breakdown', (tester) async {
      await tester.pumpWidget(_wrap(const CompactShapExplanationWidget(
        shapExplanation: legacyExplanation,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('SpO2', skipOffstage: false), findsNothing);
      expect(find.text('Severity 8/10'), findsOneWidget);
    });

    testWidgets('the patient-facing card on the success screen',
        (tester) async {
      await tester.pumpWidget(_wrap(const ShapExplanationCard(
        shapExplanation: legacyExplanation,
      )));
      await tester.pumpAndSettle();

      expect(find.textContaining('SpO2', skipOffstage: false), findsNothing);
      expect(find.text('Severity 8/10'), findsOneWidget);
      expect(find.text('Heart rate 112.0 bpm'), findsOneWidget);
    });

    testWidgets('a breakdown made only of retired factors shows nothing',
        (tester) async {
      // Better an absent explanation than a fabricated one: the widget must not
      // invent a placeholder factor to fill the gap.
      await tester.pumpWidget(_wrap(const ShapExplanationWidget(
        shapExplanation:
            '[{"factor": "SpO2 88.0%", "shap": 0.15, "impact": "+"}]',
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      expect(find.byType(ShapExplanationWidget), findsOneWidget);
      expect(find.text('WHY THIS SCORE?'), findsNothing);
      expect(find.textContaining('SpO2', skipOffstage: false), findsNothing);
    });
  });
}
