import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/body_map/ui/body_map_screen.dart';
import 'package:simtack/features/patient_info/ui/patient_info_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

import 'support/clinical_assets.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  group('PatientInfoScreen Widget Tests', () {
    testWidgets('renders patient profile header, inputs, and submit button',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const PatientInfoScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Patient Profile'), findsOneWidget);
      expect(find.text('Female'), findsOneWidget);
      expect(find.text('Male'), findsOneWidget);
      expect(find.text('Age'), findsOneWidget);
      expect(find.text('Weight'), findsOneWidget);
      expect(find.text('Height'), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
    });

    testWidgets('shows validation error when submitting empty form',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const PatientInfoScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Age is required'), findsOneWidget);
      expect(find.text('Weight is required'), findsOneWidget);
      expect(find.text('Height is required'), findsOneWidget);
    });

    testWidgets('validates out of range values', (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const PatientInfoScreen()));
      await tester.pumpAndSettle();

      // Enter invalid age (first TextFormField)
      await tester.enterText(find.byType(TextFormField).at(0), '150');
      await tester.tap(find.text('Continue'));
      await tester.pumpAndSettle();

      expect(find.text('Age must be between 0 and 120'), findsOneWidget);
    });
  });

  // The reported failure: fill in the compulsory details, press Continue, and
  // nothing happens — no next page, no message, and the button keeps its
  // spinner. The write that records the patient begins by reading the local
  // draft slot, so a value in that slot this build cannot parse used to throw a
  // `TypeError` out of `_onContinue` before it reached the navigation, leaving
  // `_isSubmitting` true for good. Both halves are covered here: the read no
  // longer throws (core/storage/stored_json.dart) and the submit cannot wedge
  // whatever else goes wrong.
  group('submitting with a draft slot this build cannot read', () {
    // Captured inside setUp rather than at declaration time: touching
    // ApiClient.httpClient builds an HttpClient, which flutter_test only allows
    // from within a test zone.
    http.Client? defaultClient;

    setUp(() async {
      defaultClient = ApiClient.httpClient;
      SharedPreferences.setMockInitialValues(
          {'patient_drafts': 'not json at all'});
      await loadClinicalDataForTest();
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/anatomy/ask')) {
          return http.Response(
            jsonEncode({
              'region': 'test',
              'complaint': '',
              'llm_used': false,
              'cached': false,
              'summary': 'Test summary',
              'structures': <String>[],
              'likely_conditions': <String>[],
              'red_flags': <String>[],
              'suggested_questions': <String>[],
              'disclaimer': '',
              'sources': <String>[],
              'citations': <String>[],
            }),
            200,
            headers: {'content-type': 'application/json'},
          );
        }
        return http.Response('{}', 200);
      });
    });

    tearDown(() {
      if (defaultClient != null) ApiClient.httpClient = defaultClient!;
    });

    testWidgets('still records the patient and opens the body map',
        (WidgetTester tester) async {
      await tester.pumpWidget(_wrap(const PatientInfoScreen()));
      await tester.pumpAndSettle();

      // Age, weight, height — the compulsory three, in form order.
      await tester.enterText(find.byType(TextFormField).at(0), '34');
      await tester.enterText(find.byType(TextFormField).at(1), '70');
      await tester.enterText(find.byType(TextFormField).at(2), '170');
      await tester.tap(find.text('Continue'));

      // Deliberately not pumpAndSettle: the body view animates forever.
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(BodyMapScreen), findsOneWidget,
          reason: 'the record was stored, so the flow must move on');
    });
  });
}
