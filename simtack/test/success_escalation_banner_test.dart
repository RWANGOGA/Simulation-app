import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/success/ui/success_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    );

TriageResult _result({
  int id = 1,
  String region = 'Chest / Heart',
  String painType = 'Crushing',
  int severity = 9,
  double? riskScore = 0.65,
  TriageEscalation? escalation,
}) =>
    TriageResult(
      id: id,
      bodyRegion: region,
      painType: painType,
      severity: severity,
      riskScore: riskScore,
      escalation: escalation,
      createdAt: DateTime.utc(2026, 1, 1),
    );

const _emergency = TriageEscalation(
  level: 'emergency',
  action: 'seek_emergency_care',
  reasons: ['Crushing chest pain', 'Chest pain rated 9/10'],
);

const _urgent = TriageEscalation(
  level: 'urgent',
  action: 'seek_urgent_care',
  reasons: ['Heart rate 110 bpm'],
);

Map<String, dynamic> _json({Map<String, dynamic>? escalation}) => {
      'id': 1,
      'body_region': 'Chest / Heart',
      'pain_type': 'Crushing',
      'severity': 9,
      'risk_score': 0.65,
      'created_at': '2026-01-01T00:00:00Z',
      if (escalation != null) 'escalation': escalation,
    };

void main() {
  group('escalation parsing', () {
    test('reads the level, the action and each reason', () {
      final result = TriageResult.fromJson(_json(escalation: {
        'level': 'emergency',
        'action': 'seek_emergency_care',
        'triggers': [
          {'code': 'chest_pain_crushing', 'detail': 'Crushing chest pain'},
        ],
      }));

      expect(result.needsEmergencyCare, isTrue);
      expect(result.escalation!.action, 'seek_emergency_care');
      expect(result.escalation!.reasons, ['Crushing chest pain']);
    });

    test('a server that predates the field is not an error', () {
      final result = TriageResult.fromJson(_json());

      expect(result.escalation, isNull);
      expect(result.needsEmergencyCare, isFalse);
      expect(result.needsUrgentCare, isFalse);
    });

    test('malformed escalation is ignored rather than thrown', () {
      final result = TriageResult.fromJson(_json(escalation: {
        'level': 42,
        'triggers': 'not a list',
      }));

      expect(result.escalation, isNull);
    });
  });

  group('patient banner', () {
    testWidgets('an emergency is stated even when the score is only medium',
        (tester) async {
      await tester.pumpWidget(_wrap(SuccessScreen(
        patientId: 'P-TEST1234',
        allResults: [_result(escalation: _emergency)],
      )));
      await tester.pump();

      expect(find.text('Go to an emergency department now'), findsOneWidget);
      expect(find.textContaining('Crushing chest pain'), findsOneWidget);
      // The whole premise: 65% would read as "Medium Risk" on its own, and it
      // still has to be shown as an emergency.
      expect(find.textContaining('Medium Risk'), findsOneWidget);
      // Urgent wording must not appear alongside it.
      expect(find.text('Be seen today'), findsNothing);
    });

    testWidgets('an urgent verdict does not claim an emergency',
        (tester) async {
      await tester.pumpWidget(_wrap(SuccessScreen(
        patientId: 'P-TEST1234',
        allResults: [_result(region: 'Head', escalation: _urgent)],
      )));
      await tester.pump();

      expect(find.text('Be seen today'), findsOneWidget);
      expect(find.textContaining('Heart rate 110 bpm'), findsOneWidget);
      expect(find.text('Go to an emergency department now'), findsNothing);
    });

    testWidgets('no red flag means no banner', (tester) async {
      await tester.pumpWidget(_wrap(SuccessScreen(
        patientId: 'P-TEST1234',
        allResults: [_result(region: 'Left Leg', riskScore: 0.2)],
      )));
      await tester.pump();

      expect(find.text('Go to an emergency department now'), findsNothing);
      expect(find.text('Be seen today'), findsNothing);
    });

    testWidgets('the worst verdict across a visit wins', (tester) async {
      await tester.pumpWidget(_wrap(SuccessScreen(
        patientId: 'P-TEST1234',
        allResults: [
          _result(id: 1, region: 'Head', escalation: _urgent, riskScore: 0.55),
          _result(id: 2, escalation: _emergency),
        ],
      )));
      await tester.pump();

      expect(find.text('Go to an emergency department now'), findsOneWidget);
      expect(find.text('Be seen today'), findsNothing);
      // The urgent finding is not listed under an emergency instruction.
      expect(find.textContaining('Heart rate 110 bpm'), findsNothing);
    });
  });
}
