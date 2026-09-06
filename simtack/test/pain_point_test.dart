import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/body_map/ui/pain_point.dart';

void main() {
  group('PainPoint Unit Tests', () {
    test('default initialization has sensible default values', () {
      final point = PainPoint(region: 'Chest / Heart', x: 0.5, y: 0.5);

      expect(point.region, equals('Chest / Heart'));
      expect(point.x, equals(0.5));
      expect(point.y, equals(0.5));
      expect(point.painType, equals('Sharp'));
      expect(point.severity, equals(5));
      expect(point.direction, equals('Towards Back'));
      expect(point.expansionBehavior, equals('Stays Small'));
      expect(point.triggers, isEmpty);
      expect(point.relievers, isEmpty);
      expect(point.dailyLimitations, isEmpty);
    });

    test('isNearby returns true within threshold and false outside', () {
      final point = PainPoint(region: 'Chest', x: 0.5, y: 0.5);

      // Threshold is 0.06
      expect(point.isNearby(0.51, 0.51), isTrue); // Distance ~ 0.014
      expect(point.isNearby(0.54, 0.54), isTrue); // Distance ~ 0.056
      expect(point.isNearby(0.60, 0.60), isFalse); // Distance ~ 0.141
      expect(point.isNearby(0.10, 0.10), isFalse);
    });

    test('toJson and fromJson correctly serialize and deserialize all pain profile fields', () {
      final original = PainPoint(
        region: 'Abdomen (Lower Right)',
        x: 0.45,
        y: 0.65,
        painType: 'Throbbing',
        severity: 8,
        direction: 'Spreading downward',
        depth: 'Deep',
        expansionBehavior: 'Spreading',
        triggers: ['Walking / Moving', 'Sitting Down'],
        relievers: ['Resting Flat', 'Ice / Cold Compact'],
        dailyLimitations: ['Cannot Sleep', 'Cannot Walk'],
      );

      final json = original.toJson();
      expect(json['region'], equals('Abdomen (Lower Right)'));
      expect(json['x'], equals(0.45));
      expect(json['y'], equals(0.65));
      expect(json['painType'], equals('Throbbing'));
      expect(json['severity'], equals(8));
      expect(json['expansionBehavior'], equals('Spreading'));
      expect(json['triggers'], equals(['Walking / Moving', 'Sitting Down']));
      expect(json['relievers'], equals(['Resting Flat', 'Ice / Cold Compact']));
      expect(json['dailyLimitations'], equals(['Cannot Sleep', 'Cannot Walk']));

      final restored = PainPoint.fromJson(json);
      expect(restored.region, equals(original.region));
      expect(restored.x, equals(original.x));
      expect(restored.y, equals(original.y));
      expect(restored.painType, equals(original.painType));
      expect(restored.severity, equals(original.severity));
      expect(restored.direction, equals(original.direction));
      expect(restored.depth, equals(original.depth));
      expect(restored.expansionBehavior, equals('Spreading'));
      expect(restored.triggers, equals(['Walking / Moving', 'Sitting Down']));
      expect(restored.relievers, equals(['Resting Flat', 'Ice / Cold Compact']));
      expect(restored.dailyLimitations, equals(['Cannot Sleep', 'Cannot Walk']));
    });

    test('toJson and fromJson handle symptomDescription and tags', () {
      final original = PainPoint(
        region: 'Headache / Cranial',
        x: 0.5,
        y: 0.1,
        symptomDescription: 'Sharp throbbing pain behind left eye',
        tags: ['Sharp', 'Throbbing', 'Constant'],
      );

      final json = original.toJson();
      expect(json['symptomDescription'], equals('Sharp throbbing pain behind left eye'));
      expect(json['tags'], equals(['Sharp', 'Throbbing', 'Constant']));

      final restored = PainPoint.fromJson(json);
      expect(restored.symptomDescription, equals('Sharp throbbing pain behind left eye'));
      expect(restored.tags, equals(['Sharp', 'Throbbing', 'Constant']));
    });
  });
}
