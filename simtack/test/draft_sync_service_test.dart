import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/storage/draft_storage.dart';
import 'package:simtack/core/storage/draft_sync_service.dart';
import 'package:simtack/core/storage/triage_draft.dart';
import 'package:simtack/features/body_map/ui/pain_point.dart';

TriageDraft _draft({List<PainPoint>? painPoints, DateTime? savedAt}) => TriageDraft(
      painPoints: painPoints ?? [PainPoint(region: 'Chest / Heart', x: 0.5, y: 0.3)],
      patientId: 42,
      savedAt: savedAt ?? DateTime.now(),
    );

http.Response _created() => http.Response(
      jsonEncode({
        'id': 1,
        'patient_id': 42,
        'anonymous_code': 'P-TEST',
        'body_region': 'Chest / Heart',
        'pain_type': 'Sharp',
        'severity': 5,
        'created_at': DateTime.now().toIso8601String(),
      }),
      201,
    );

void main() {
  final defaultClient = ApiClient.httpClient;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.httpClient = defaultClient;
  });

  group('DraftSyncService.syncAll', () {
    test('does nothing and returns 0 when there are no drafts', () async {
      ApiClient.httpClient = MockClient((request) async {
        fail('No network call should happen with an empty draft list.');
      });

      final synced = await DraftSyncService.syncAll();

      expect(synced, 0);
    });

    test('submits a saved draft and removes it on success', () async {
      await DraftStorage.save(_draft());

      ApiClient.httpClient = MockClient((request) async => _created());

      final synced = await DraftSyncService.syncAll();

      expect(synced, 1);
      expect(await DraftStorage.loadAll(), isEmpty);
    });

    test('leaves the draft in place when the backend is unreachable', () async {
      await DraftStorage.save(_draft());

      ApiClient.httpClient = MockClient((request) async {
        throw Exception('Connection refused');
      });

      final synced = await DraftSyncService.syncAll();

      expect(synced, 0);
      expect(await DraftStorage.loadAll(), hasLength(1));
    });

    test('leaves the draft in place on a server error response', () async {
      await DraftStorage.save(_draft());

      ApiClient.httpClient = MockClient((request) async => http.Response('Server error', 500));

      final synced = await DraftSyncService.syncAll();

      expect(synced, 0);
      expect(await DraftStorage.loadAll(), hasLength(1));
    });

    test('syncs only the drafts that succeed, leaving the rest for next time', () async {
      final okDraft = _draft(
        painPoints: [PainPoint(region: 'Chest / Heart', x: 0.5, y: 0.3)],
        savedAt: DateTime(2026, 1, 1),
      );
      final failDraft = _draft(
        painPoints: [PainPoint(region: 'Headache / Cranial', x: 0.5, y: 0.1)],
        savedAt: DateTime(2026, 1, 2),
      );
      await DraftStorage.save(okDraft);
      await DraftStorage.save(failDraft);

      ApiClient.httpClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        if (body['body_region'] == 'Headache / Cranial') {
          return http.Response('Server error', 500);
        }
        return _created();
      });

      final synced = await DraftSyncService.syncAll();

      expect(synced, 1);
      final remaining = await DraftStorage.loadAll();
      expect(remaining, hasLength(1));
      expect(remaining.single.painPoints.single.region, 'Headache / Cranial');
    });

    test('submits every pain point in a multi-point draft under one visit', () async {
      await DraftStorage.save(_draft(painPoints: [
        PainPoint(region: 'Chest / Heart', x: 0.5, y: 0.3),
        PainPoint(region: 'Left Arm / Shoulder', x: 0.8, y: 0.3),
      ]));

      final submittedRegions = <String>[];
      final submittedVisitIds = <String?>[];
      ApiClient.httpClient = MockClient((request) async {
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        submittedRegions.add(body['body_region'] as String);
        submittedVisitIds.add(body['visit_id'] as String?);
        return _created();
      });

      final synced = await DraftSyncService.syncAll();

      expect(synced, 1);
      expect(submittedRegions, ['Chest / Heart', 'Left Arm / Shoulder']);
      // Both pain points from the same draft must share one visit_id so
      // the backend groups them back together as a single visit.
      expect(submittedVisitIds[0], isNotNull);
      expect(submittedVisitIds[0], submittedVisitIds[1]);
    });
  });
}
