import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/storage/draft_storage.dart';
import 'package:simtack/features/body_map/ui/pain_point.dart';
import 'package:simtack/features/review/ui/review_screen.dart';

void main() {
  final defaultClient = ApiClient.httpClient;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.httpClient = defaultClient;
  });

  testWidgets(
    'a mid-visit submit failure only saves the pain points that never made it through — '
    'not the ones already accepted by the backend',
    (WidgetTester tester) async {
      final submittedRegions = <String>[];
      ApiClient.httpClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final region = body['body_region'] as String;
        submittedRegions.add(region);

        // First pain point succeeds, second one fails (simulating a
        // connection drop partway through a multi-point submit).
        if (region == 'Chest / Heart') {
          return http.Response(
            jsonEncode({
              'id': 1,
              'patient_id': 7,
              'anonymous_code': 'P-TEST',
              'body_region': region,
              'pain_type': 'Sharp',
              'severity': 5,
              'created_at': DateTime.now().toIso8601String(),
            }),
            201,
          );
        }
        return http.Response('Server error', 500);
      });

      await tester.pumpWidget(MaterialApp(
        home: ReviewScreen(
          painPoints: [
            PainPoint(region: 'Chest / Heart', x: 0.5, y: 0.3),
            PainPoint(region: 'Left Arm / Shoulder', x: 0.8, y: 0.3),
          ],
          heartRate: 80,
          spo2: 96,
          patientId: 7,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Submit'));
      await tester.pumpAndSettle();

      // Both points were attempted, in order, before the failure surfaced.
      expect(submittedRegions, ['Chest / Heart', 'Left Arm / Shoulder']);

      // Only the point that never succeeded should be saved for retry —
      // saving both would resubmit "Chest / Heart" as a duplicate later.
      final drafts = await DraftStorage.loadAll();
      expect(drafts, hasLength(1));
      expect(drafts.single.painPoints, hasLength(1));
      expect(drafts.single.painPoints.single.region, 'Left Arm / Shoulder');

      // The patient is told their data is safe, not just that it failed.
      expect(find.textContaining('saved offline'), findsOneWidget);
    },
  );
}
