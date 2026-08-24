import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/storage/triage_draft.dart';
import 'package:simtack/features/body_map/ui/pain_point.dart';

void main() {
  group('TriageDraft Unit Tests', () {
    test('toJson and fromJson handle empty and non-empty pain points list', () {
      final now = DateTime.now();
      final draft = TriageDraft(
        painPoints: [
          PainPoint(region: 'Chest', x: 0.5, y: 0.4, severity: 7, painType: 'Crushing'),
          PainPoint(region: 'Head', x: 0.5, y: 0.1, severity: 4, painType: 'Dull'),
        ],
        heartRate: 88.0,
        spo2: 98.0,
        patientId: 101,
        savedAt: now,
      );

      final json = draft.toJson();
      expect(json['patientId'], equals(101));
      expect(json['heartRate'], equals(88.0));
      expect(json['spo2'], equals(98.0));
      expect((json['painPoints'] as List).length, equals(2));

      final restored = TriageDraft.fromJson(json);
      expect(restored.patientId, equals(101));
      expect(restored.heartRate, equals(88.0));
      expect(restored.spo2, equals(98.0));
      expect(restored.painPoints.length, equals(2));
      expect(restored.painPoints[0].region, equals('Chest'));
      expect(restored.painPoints[0].severity, equals(7));
      expect(restored.painPoints[1].region, equals('Head'));
    });
  });
}
