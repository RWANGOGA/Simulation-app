import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/report/ui/clinical_report_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

Map<String, dynamic> _session({
  required int id,
  required String visitId,
  required String region,
  required String createdAt,
  double riskScore = 0.5,
  String? shap,
}) =>
    {
      'id': id,
      'patient_id': 7,
      'anonymous_code': 'P-TEST12345678',
      'body_region': region,
      'pain_type': 'throbbing',
      'severity': 5,
      'visit_id': visitId,
      'risk_score': riskScore,
      'shap_explanation': shap,
      'status': 'open',
      'created_at': createdAt,
      'patient_age': 40,
    };

/// In-memory token storage so tests never touch platform secure storage.
class FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<void> write(String value) async => _token = value;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> delete() async => _token = null;
}

void main() {
  final defaultClient = ApiClient.httpClient;
  final defaultStorage = ApiClient.tokenStorage;

  setUp(() {
    // Practitioner-mode fetches carry a JWT header — never let tests hit
    // the platform secure storage.
    ApiClient.tokenStorage = FakeTokenStorage();
  });

  tearDown(() {
    ApiClient.httpClient = defaultClient;
    ApiClient.tokenStorage = defaultStorage;
  });

  group('ClinicalReportScreen Widget Tests', () {
    testWidgets('renders initial loading indicator and watermark', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const ClinicalReportScreen(patientId: 'TEST-12345')));

      expect(find.text('SIMTACK CARE'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });
  });

  group('Visit timeline (T2)', () {
    testWidgets('practitioner sees the timeline and can switch visits', (tester) async {
      // History endpoint: newest visit first (visit-b), older one after.
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/history')) {
          return http.Response(
            jsonEncode([
              _session(id: 3, visitId: 'visit-b', region: 'Chest', createdAt: '2026-08-20T10:00:00'),
              _session(id: 2, visitId: 'visit-a', region: 'Head', createdAt: '2026-08-01T09:00:00'),
              _session(id: 1, visitId: 'visit-a', region: 'Left Arm', createdAt: '2026-08-01T09:05:00'),
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(const ClinicalReportScreen(patientId: 'P-TEST12345678', practitionerMode: true)));
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
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.contains('/triage/patient/')) {
          return http.Response(
            jsonEncode([
              _session(id: 1, visitId: 'visit-a', region: 'Head', createdAt: '2026-08-01T09:00:00'),
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      await tester.pumpWidget(_wrap(const ClinicalReportScreen(patientId: 'P-TEST12345678')));
      await tester.pumpAndSettle();

      expect(find.text('VISIT TIMELINE'), findsNothing);
      expect(find.text('Head'), findsWidgets);
    });
  });

  group('SHAP factor bars (T1)', () {
    testWidgets('renders proportional bars with signed percentages', (tester) async {
      final shap = jsonEncode([
        {'factor': 'Severity 5/10', 'shap': 0.25, 'impact': '+'},
        {'factor': 'Region: Chest', 'shap': 0.15, 'impact': '+'},
        {'factor': 'Pain type: throbbing', 'shap': 0.05, 'impact': '+'},
      ]);
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.contains('/triage/patient/')) {
          return http.Response(
            jsonEncode([
              _session(id: 1, visitId: 'visit-a', region: 'Chest',
                  createdAt: '2026-08-01T09:00:00', shap: shap),
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      await tester.pumpWidget(_wrap(const ClinicalReportScreen(patientId: 'P-TEST12345678')));
      await tester.pumpAndSettle();

      expect(find.text('WHY THIS SCORE?'), findsOneWidget);
      expect(find.text('+25%'), findsOneWidget);
      expect(find.text('+15%'), findsOneWidget);
      expect(find.text('+5%'), findsOneWidget);
      expect(find.text('Severity 5/10'), findsOneWidget);
      // One bar track + fill per factor.
      expect(find.byType(FractionallySizedBox), findsNWidgets(3));
    });

    testWidgets('legacy explanation without impact key still renders', (tester) async {
      final shap = jsonEncode([
        {'factor': 'Severity 8/10', 'shap': 0.4},
      ]);
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.contains('/triage/patient/')) {
          return http.Response(
            jsonEncode([
              _session(id: 1, visitId: 'visit-a', region: 'Chest',
                  createdAt: '2026-08-01T09:00:00', shap: shap),
            ]),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      await tester.pumpWidget(_wrap(const ClinicalReportScreen(patientId: 'P-TEST12345678')));
      await tester.pumpAndSettle();

      expect(find.text('+40%'), findsOneWidget);
      expect(find.byType(FractionallySizedBox), findsOneWidget);
    });
  });
}
