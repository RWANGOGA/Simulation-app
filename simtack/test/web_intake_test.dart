// The web target, which no other test in this suite reaches.
//
// `flutter test` runs on the Dart VM, and the VM's `int` is 64-bit: `1 << 32` is
// 4294967296 there. dart2js gives `int` the shift semantics of a 32-bit JS
// integer, so the same expression is **0** in the browser, and
// `Random.nextInt(0)` throws. That is how patient intake came to fail on the
// deployed site while every test here passed: the id minted for the outbox row
// that records a new patient called `nextInt(1 << 32)`, so pressing Continue
// raised `RangeError: max must be in range 0 < max ≤ 2^32, was 0` on the web
// only.
//
// CI does not run this file (see test/web_safe_integers_test.dart, which
// enforces the rule statically instead). Run it by hand when changing anything
// that generates an id, a code or a random range:
//
//     flutter test --platform chrome test/web_intake_test.dart
@TestOn('browser')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/models/patient_profile.dart';
import 'package:simtack/core/offline/local_database.dart';
import 'package:simtack/core/offline/offline_repository.dart';
import 'package:simtack/features/body_map/ui/body_map_screen.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalDatabase.resetForTest();
  });

  test('intake records a patient in the browser', () async {
    final result =
        await OfflineRepository.instance.createPatient(const PatientProfile(
      age: 23,
      gender: 'Male',
      weight: 78,
      height: 178,
    ));

    expect(result.anonymousCode, matches(RegExp(r'^P-[A-Z0-9]{12}$')));
    expect(result.id, isNonPositive,
        reason: 'a device-created row has a negative local id until the server '
            'confirms it');
  });

  test('the body map builds a full 128-bit conversation id in the browser', () {
    final screen = BodyMapScreen(
      patientId: -1,
      patientCode: 'P-TESTTESTTEST',
      gender: 'Male',
      weightKg: 78,
      heightCm: 178,
    );

    expect(screen.conversationId, matches(RegExp(r'^conv_[0-9a-f]{32}$')));
  });
}
