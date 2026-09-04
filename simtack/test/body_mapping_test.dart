import 'package:flutter_test/flutter_test.dart';

String classifyBodyRegion(double nx, double ny) {
  if (ny < 0.24) {
    return 'Headache / Cranial';
  } else if (ny < 0.33) {
    if (nx < 0.33) {
      return 'Right Arm / Shoulder';
    } else if (nx > 0.67) {
      return 'Left Arm / Shoulder';
    } else {
      return 'Neck';
    }
  } else if (ny < 0.46) {
    if (nx < 0.30) {
      return 'Right Arm / Shoulder';
    } else if (nx > 0.70) {
      return 'Left Arm / Shoulder';
    } else {
      return 'Chest / Heart';
    }
  } else if (ny < 0.62) {
    if (nx < 0.28) {
      return 'Right Arm / Shoulder';
    } else if (nx > 0.72) {
      return 'Left Arm / Shoulder';
    } else {
      return 'Abdomen';
    }
  } else if (ny < 0.72) {
    if (nx < 0.40) {
      return 'Right Leg / Knee';
    } else if (nx > 0.60) {
      return 'Left Leg / Knee';
    } else {
      return 'Hips / Groin';
    }
  } else {
    if (nx < 0.45) {
      return 'Right Leg / Knee';
    } else if (nx > 0.55) {
      return 'Left Leg / Knee';
    } else {
      return 'Thighs';
    }
  }
}

void main() {
  group('Body Mapping Threshold Classification Tests', () {
    test('head click produces Headache / Cranial', () {
      expect(classifyBodyRegion(0.5, 0.05), equals('Headache / Cranial'));
      expect(classifyBodyRegion(0.5, 0.15), equals('Headache / Cranial'));
      expect(classifyBodyRegion(0.5, 0.22), equals('Headache / Cranial'));
    });

    test('neck click produces Neck', () {
      expect(classifyBodyRegion(0.5, 0.28), equals('Neck'));
    });

    test('chest click produces Chest / Heart', () {
      expect(classifyBodyRegion(0.5, 0.38), equals('Chest / Heart'));
    });

    test('abdomen click produces Abdomen', () {
      expect(classifyBodyRegion(0.5, 0.52), equals('Abdomen'));
    });

    test('hip click produces Hips / Groin', () {
      expect(classifyBodyRegion(0.5, 0.68), equals('Hips / Groin'));
    });

    test('leg click produces Right Leg / Knee or Left Leg / Knee', () {
      expect(classifyBodyRegion(0.2, 0.80), equals('Right Leg / Knee'));
      expect(classifyBodyRegion(0.8, 0.80), equals('Left Leg / Knee'));
    });
  });
}
