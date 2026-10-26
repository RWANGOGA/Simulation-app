import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simtack/core/widgets/shap_explanation_card.dart';
import 'package:simtack/features/report/ui/shap_explanation_widget.dart';
import 'package:simtack/l10n/app_localizations.dart';

/// A breakdown as the server now writes it: the findings sum to 1.30, the score is
/// capped at 1.00, and the difference is recorded as its own negative factor so the
/// list adds up to the number it explains.
///
/// This shape did not exist before the cap became visible. Both widgets had only
/// ever seen non-negative factors, and one of them had learned to render them by
/// prefixing a literal '+' - which was correct by accident, and stopped being
/// correct the moment an honest negative arrived.
const cappedExplanation = '''
[
  {"factor": "Severity 10/10", "shap": 0.5, "impact": "+"},
  {"factor": "Region: Chest / Heart", "shap": 0.4, "impact": "+"},
  {"factor": "Pain type: Crushing", "shap": 0.2, "impact": "+"},
  {"factor": "Heart rate 135.0 bpm", "shap": 0.15, "impact": "+"},
  {"factor": "Score capped at 1.00 (findings summed to 1.30)", "shap": -0.3, "impact": "-"}
]
''';

/// The same list with nothing capped - the ordinary case.
const uncappedExplanation = '''
[
  {"factor": "Severity 6/10", "shap": 0.3, "impact": "+"},
  {"factor": "Region: Left Leg", "shap": 0.1, "impact": "+"}
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
  group('a capped score is signed the way a number is', () {
    testWidgets('the shared card does not render "+-30%"', (tester) async {
      await tester.pumpWidget(_wrap(const ShapExplanationCard(
        shapExplanation: cappedExplanation,
      )));
      await tester.pumpAndSettle();

      final rendered = tester
          .widgetList<Text>(find.byType(Text))
          .map((t) => t.data)
          .whereType<String>()
          .toList();

      expect(rendered, contains('-30%'), reason: rendered.toString());
      expect(
        rendered.where((s) => s.contains('+-') || s.contains('-+')),
        isEmpty,
        reason: 'a sign was prefixed on top of the number’s own: $rendered',
      );
      // The positive factors keep their '+', so the fix is not a blanket removal.
      expect(rendered, contains('+50%'), reason: rendered.toString());
    });

    testWidgets('the report breakdown shows the adjustment with a minus',
        (tester) async {
      await tester.pumpWidget(_wrap(const ShapExplanationWidget(
        shapExplanation: cappedExplanation,
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('-30%'), findsOneWidget);
      expect(find.textContaining(r'^\+-'), findsNothing);
    });

    testWidgets('the adjustment is not painted as a reassuring finding',
        (tester) async {
      await tester.pumpWidget(_wrap(const ShapExplanationWidget(
        shapExplanation: cappedExplanation,
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      // Green in this interface means "this lowers your risk". The cap is the
      // opposite of reassuring - it is reached because findings stacked up - so it
      // must not borrow that colour.
      final adjustmentRow = find.text(
        'Score capped at 1.00 (findings summed to 1.30)',
      );
      expect(adjustmentRow, findsOneWidget);

      Color? colourOf(String text) {
        for (final widget in tester.widgetList<Text>(find.byType(Text))) {
          if (widget.data == text) return widget.style?.color;
        }
        return null;
      }

      // Resolved through the widget's own context, because the accent scale is
      // brightness-aware and a hardcoded hex here would test one theme only.
      final context = tester.element(find.byType(ShapExplanationWidget));
      expect(colourOf('-30%'), ShapExplanationWidget.adjustmentColor(context));
      expect(
        colourOf('-30%'),
        isNot(const Color(0xFF16A34A)),
        reason: 'the cap was drawn in the green of a protective finding',
      );
    });
  });

  group('the legend only advertises colours that are on screen', () {
    testWidgets('no lowering factor means no "Lowers Risk" key',
        (tester) async {
      await tester.pumpWidget(_wrap(const ShapExplanationWidget(
        shapExplanation: uncappedExplanation,
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Raises Risk'), findsOneWidget);
      expect(
        find.text('Lowers Risk'),
        findsNothing,
        reason: 'the legend taught a colour the panel could never show',
      );
    });

    testWidgets('a genuine adjustment brings its legend entry with it',
        (tester) async {
      await tester.pumpWidget(_wrap(const ShapExplanationWidget(
        shapExplanation: cappedExplanation,
        initiallyExpanded: true,
      )));
      await tester.pumpAndSettle();

      expect(find.text('Raises Risk'), findsOneWidget);
      expect(find.text('Lowers Risk'), findsOneWidget);
    });
  });

  // The factor weight was renamed `shap` -> `contribution`, because nothing here
  // is a SHAP value. Sessions are stored on the device, so both names have to be
  // readable for as long as rows written by an older build are still on phones.
  // The failure mode without the fallback is quiet and total: every factor of
  // every historical triage reads back as 0 and the panel claims the score was
  // made of nothing.
  group('rows written before the rename still render', () {
    const oldRow = '''
[
  {"factor": "Severity 8/10", "shap": 0.4, "impact": "+"},
  {"factor": "Score capped at 1.00 (findings summed to 1.10)", "shap": -0.5, "impact": "-"}
]
''';
    const newRow = '''
[
  {"factor": "Severity 8/10", "contribution": 0.4, "impact": "+"},
  {"factor": "Score capped at 1.00 (findings summed to 1.10)", "contribution": -0.5, "impact": "-"}
]
''';

    for (final entry
        in {'legacy shap key': oldRow, 'renamed key': newRow}.entries) {
      testWidgets('${entry.key} gives the same numbers', (tester) async {
        await tester.pumpWidget(_wrap(ShapExplanationCard(
          shapExplanation: entry.value,
        )));
        await tester.pumpAndSettle();

        final rendered = tester
            .widgetList<Text>(find.byType(Text))
            .map((t) => t.data)
            .whereType<String>()
            .toList();

        expect(rendered, contains('+40%'), reason: rendered.toString());
        expect(rendered, contains('-50%'), reason: rendered.toString());
      });
    }
  });
}
