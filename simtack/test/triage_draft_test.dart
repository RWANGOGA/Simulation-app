import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/storage/triage_draft.dart';
import 'package:simtack/core/storage/draft_storage.dart';
import 'package:simtack/core/storage/draft_sync_service.dart';
import 'package:simtack/features/body_map/ui/pain_point.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('DraftStorage', () {
    test('save and loadAll works', () async {
      final painPoints = [
        PainPoint(
          region: 'Head',
          x: 0.5,
          y: 0.1,
          painType: 'Sharp',
          severity: 7,
          direction: 'Towards Back',
          depth: 'Deep',
          expansionBehavior: 'Stays Small',
          triggers: ['Moving'],
          relievers: ['Resting'],
          dailyLimitations: ['Cannot Sleep'],
        ),
      ];

      final draft = TriageDraft(
        painPoints: painPoints,
        patientId: 123,
        patientCode: 'ABC123',
        savedAt: DateTime.now(),
      );

      await DraftStorage.save(draft);
      final drafts = await DraftStorage.loadAll();

      expect(drafts.length, 1);
      expect(drafts.first.painPoints.length, 1);
      expect(drafts.first.painPoints.first.region, 'Head');
      expect(drafts.first.patientId, 123);
      expect(drafts.first.patientCode, 'ABC123');
    });

    test('save inserts at front (newest first)', () async {
      final draft1 = TriageDraft(
        painPoints: [PainPoint(region: 'Head', x: 0.5, y: 0.1)],
        patientId: 1,
        savedAt: DateTime(2024, 1, 1),
      );

      final draft2 = TriageDraft(
        painPoints: [PainPoint(region: 'Chest', x: 0.5, y: 0.3)],
        patientId: 2,
        savedAt: DateTime(2024, 1, 2),
      );

      await DraftStorage.save(draft1);
      await DraftStorage.save(draft2);

      final drafts = await DraftStorage.loadAll();
      expect(drafts.first.painPoints.first.region, 'Chest');
      expect(drafts.last.painPoints.first.region, 'Head');
    });

    test('remove deletes specific draft', () async {
      final draft1 = TriageDraft(
        painPoints: [PainPoint(region: 'Head', x: 0.5, y: 0.1)],
        patientId: 1,
        savedAt: DateTime(2024, 1, 1),
      );

      final draft2 = TriageDraft(
        painPoints: [PainPoint(region: 'Chest', x: 0.5, y: 0.3)],
        patientId: 2,
        savedAt: DateTime(2024, 1, 2),
      );

      await DraftStorage.save(draft1);
      await DraftStorage.save(draft2);

      await DraftStorage.remove(draft1);

      final drafts = await DraftStorage.loadAll();
      expect(drafts.length, 1);
      expect(drafts.first.painPoints.first.region, 'Chest');
    });

    test('clear removes all drafts', () async {
      await DraftStorage.save(TriageDraft(
        painPoints: [PainPoint(region: 'Head', x: 0.5, y: 0.1)],
        patientId: 1,
        savedAt: DateTime.now(),
      ));
      await DraftStorage.save(TriageDraft(
        painPoints: [PainPoint(region: 'Chest', x: 0.5, y: 0.3)],
        patientId: 2,
        savedAt: DateTime.now(),
      ));

      await DraftStorage.clear();

      final drafts = await DraftStorage.loadAll();
      expect(drafts.length, 0);
    });

    test('load returns most recent draft', () async {
      final draft1 = TriageDraft(
        painPoints: [PainPoint(region: 'Head', x: 0.5, y: 0.1)],
        patientId: 1,
        savedAt: DateTime(2024, 1, 1),
      );

      final draft2 = TriageDraft(
        painPoints: [PainPoint(region: 'Chest', x: 0.5, y: 0.3)],
        patientId: 2,
        savedAt: DateTime(2024, 1, 2),
      );

      await DraftStorage.save(draft1);
      await DraftStorage.save(draft2);

      final latest = await DraftStorage.load();
      expect(latest, isNotNull);
      expect(latest!.painPoints.first.region, 'Chest');
    });

    test('load returns null when empty', () async {
      await DraftStorage.clear();
      final latest = await DraftStorage.load();
      expect(latest, isNull);
    });

    test('migrates legacy single draft on first load', () async {
      await DraftStorage.clear();
      final prefs = await SharedPreferences.getInstance();
      
      final legacyDraft = TriageDraft(
        painPoints: [PainPoint(region: 'Legacy', x: 0.5, y: 0.5)],
        patientId: 999,
        savedAt: DateTime(2023, 1, 1),
      );
      
      await prefs.setString('triage_draft', '{"painPoints":[{"region":"Legacy","x":0.5,"y":0.5,"viewKey":null,"painType":"Sharp","severity":5,"direction":"Towards Back","depth":"Moderate","expansionBehavior":"Stays Small","triggers":[],"relievers":[],"dailyLimitations":[],"tags":[],"questionAnswers":{}}],"patientId":999,"savedAt":"2023-01-01T00:00:00.000"}');

      final drafts = await DraftStorage.loadAll();
      expect(drafts.length, 1);
      expect(drafts.first.painPoints.first.region, 'Legacy');
      expect(drafts.first.patientId, 999);
    });
  });

  group('TriageDraft', () {
    test('toJson and fromJson round-trip preserves data', () {
      final painPoints = [
        PainPoint(
          region: 'Abdomen',
          x: 0.5,
          y: 0.4,
          viewKey: null,
          painType: 'Dull',
          severity: 4,
          direction: 'Towards Front',
          depth: 'Superficial',
          expansionBehavior: 'Growing',
          triggers: ['Eating', 'Moving'],
          relievers: ['Antacid', 'Resting'],
          dailyLimitations: ['Cannot Eat'],
          tags: ['GI'],
          questionAnswers: {'onset': 'Morning'},
        ),
      ];

      final original = TriageDraft(
        painPoints: painPoints,
        patientId: 456,
        patientCode: 'XYZ789',
        savedAt: DateTime(2024, 6, 15, 10, 30),
      );

      final json = original.toJson();
      final restored = TriageDraft.fromJson(json);

      expect(restored.patientId, original.patientId);
      expect(restored.patientCode, original.patientCode);
      expect(restored.savedAt, original.savedAt);
      expect(restored.painPoints.length, original.painPoints.length);
      expect(restored.painPoints.first.region, 'Abdomen');
      expect(restored.painPoints.first.painType, 'Dull');
      expect(restored.painPoints.first.severity, 4);
      expect(restored.painPoints.first.triggers, ['Eating', 'Moving']);
      expect(restored.painPoints.first.relievers, ['Antacid', 'Resting']);
      expect(restored.painPoints.first.dailyLimitations, ['Cannot Eat']);
      expect(restored.painPoints.first.questionAnswers, {'onset': 'Morning'});
    });
  });
}