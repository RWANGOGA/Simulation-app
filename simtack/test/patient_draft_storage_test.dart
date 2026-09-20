import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/storage/patient_draft.dart';
import 'package:simtack/core/storage/patient_draft_storage.dart';
import 'package:simtack/core/models/patient_profile.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('PatientDraftStorage', () {
    test('save and loadAll works', () async {
      final profile = PatientProfile(
        age: 30,
        gender: 'Female',
        weight: 70.0,
        height: 165.0,
        fullName: 'Jane Doe',
      );

      final draft = PatientDraft.createOffline(profile);
      await PatientDraftStorage.save(draft);

      final drafts = await PatientDraftStorage.loadAll();
      expect(drafts.length, 1);
      expect(drafts.first.profile.fullName, 'Jane Doe');
    });

    test('save overwrites draft with same patientCode', () async {
      final profile1 = PatientProfile(
        age: 30,
        gender: 'Female',
        weight: 70.0,
        height: 165.0,
        fullName: 'Jane Doe',
      );

      final profile2 = PatientProfile(
        age: 31,
        gender: 'Female',
        weight: 71.0,
        height: 166.0,
        fullName: 'Jane Smith',
      );

      final draft1 = PatientDraft.createOffline(profile1).copyWith(patientCode: 'ABC123');
      final draft2 = PatientDraft.createOffline(profile2).copyWith(patientCode: 'ABC123');

      await PatientDraftStorage.save(draft1);
      await PatientDraftStorage.save(draft2);

      final drafts = await PatientDraftStorage.loadAll();
      expect(drafts.length, 1);
      expect(drafts.first.profile.fullName, 'Jane Smith');
    });

    test('save overwrites draft with same localId', () async {
      final profile1 = PatientProfile(
        age: 30,
        gender: 'Female',
        weight: 70.0,
        height: 165.0,
      );

      final profile2 = PatientProfile(
        age: 31,
        gender: 'Male',
        weight: 71.0,
        height: 166.0,
      );

      final draft1 = PatientDraft(
        localId: -100,
        profile: profile1,
        savedAt: DateTime(2024, 1, 1),
      );

      final draft2 = PatientDraft(
        localId: -100,
        profile: profile2,
        savedAt: DateTime(2024, 1, 2),
      );

      await PatientDraftStorage.save(draft1);
      await PatientDraftStorage.save(draft2);

      final drafts = await PatientDraftStorage.loadAll();
      expect(drafts.length, 1);
      expect(drafts.first.profile.age, 31);
    });

    test('findByPatientCode returns matching draft', () async {
      final profile = PatientProfile(
        age: 25,
        gender: 'Male',
        weight: 80.0,
        height: 180.0,
      );

      final draft = PatientDraft.createOffline(profile).copyWith(patientCode: 'XYZ789');
      await PatientDraftStorage.save(draft);

      final found = await PatientDraftStorage.loadAll();
      expect(found.any((d) => d.patientCode == 'XYZ789'), isTrue);
    });

    test('remove deletes draft', () async {
      final profile = PatientProfile(
        age: 30,
        gender: 'Female',
        weight: 70.0,
        height: 165.0,
      );

      final draft = PatientDraft.createOffline(profile);
      await PatientDraftStorage.save(draft);
      expect((await PatientDraftStorage.loadAll()).length, 1);

      await PatientDraftStorage.remove(draft);
      expect((await PatientDraftStorage.loadAll()).length, 0);
    });

    test('clear removes all drafts', () async {
      await PatientDraftStorage.save(PatientDraft(
        localId: -1,
        profile: PatientProfile(age: 20, gender: 'Male', weight: 60.0, height: 170.0),
        savedAt: DateTime(2024, 1, 1),
      ));
      await PatientDraftStorage.save(PatientDraft(
        localId: -2,
        profile: PatientProfile(age: 25, gender: 'Female', weight: 65.0, height: 165.0),
        savedAt: DateTime(2024, 1, 2),
      ));

      expect((await PatientDraftStorage.loadAll()).length, 2);

      await PatientDraftStorage.clear();
      expect((await PatientDraftStorage.loadAll()).length, 0);
    });

    test('loadAll returns drafts sorted newest first', () async {
      final oldDraft = PatientDraft(
        localId: -1,
        profile: PatientProfile(age: 20, gender: 'Male', weight: 60.0, height: 170.0),
        savedAt: DateTime(2024, 1, 1),
      );

      final newDraft = PatientDraft(
        localId: -2,
        profile: PatientProfile(age: 25, gender: 'Female', weight: 65.0, height: 165.0),
        savedAt: DateTime(2024, 1, 2),
      );

      await PatientDraftStorage.save(oldDraft);
      await PatientDraftStorage.save(newDraft);

      final drafts = await PatientDraftStorage.loadAll();
      expect(drafts.first.profile.age, 25);
      expect(drafts.last.profile.age, 20);
    });

    test('loadLatest returns most recent draft', () async {
      await PatientDraftStorage.save(PatientDraft(
        localId: -1,
        profile: PatientProfile(age: 20, gender: 'Male', weight: 60.0, height: 170.0),
        savedAt: DateTime(2024, 1, 1),
      ));

      await PatientDraftStorage.save(PatientDraft(
        localId: -2,
        profile: PatientProfile(age: 25, gender: 'Female', weight: 65.0, height: 165.0),
        savedAt: DateTime(2024, 1, 2),
      ));

      final latest = await PatientDraftStorage.loadLatest();
      expect(latest, isNotNull);
      expect(latest!.profile.age, 25);
    });
  });

  group('PatientDraft', () {
    test('createOffline generates negative localId', () {
      final profile = PatientProfile(
        age: 30,
        gender: 'Female',
        weight: 70.0,
        height: 165.0,
      );

      final draft = PatientDraft.createOffline(profile);

      expect(draft.localId, lessThan(0));
      expect(draft.isSynced, isFalse);
      expect(draft.patientId, isNull);
      expect(draft.patientCode, isNull);
    });

    test('copyWith updates only specified fields', () {
      final profile = PatientProfile(
        age: 30,
        gender: 'Female',
        weight: 70.0,
        height: 165.0,
      );

      final original = PatientDraft.createOffline(profile);
      final updated = original.copyWith(isSynced: true, patientId: 42, patientCode: 'ABC123');

      expect(updated.isSynced, isTrue);
      expect(updated.patientId, 42);
      expect(updated.patientCode, 'ABC123');
      expect(updated.localId, original.localId);
      expect(updated.profile, original.profile);
    });

    test('toJson and fromJson round-trip preserves data', () {
      final profile = PatientProfile(
        age: 28,
        gender: 'Male',
        weight: 75.0,
        height: 178.0,
        fullName: 'John Smith',
        dateOfBirth: DateTime(1996, 3, 10),
        phone: '+15551234567',
        address: '789 Elm St',
        nextOfKinName: 'Mary Smith',
        nextOfKinPhone: '+15557654321',
        hospitalName: 'Central Hospital',
      );

      final original = PatientDraft.createOffline(profile)
          .copyWith(patientId: 100, patientCode: 'PAT123', isSynced: true);

      final json = original.toJson();
      final restored = PatientDraft.fromJson(json);

      expect(restored.localId, original.localId);
      expect(restored.patientId, original.patientId);
      expect(restored.patientCode, original.patientCode);
      expect(restored.isSynced, original.isSynced);
      expect(restored.profile.age, original.profile.age);
      expect(restored.profile.gender, original.profile.gender);
      expect(restored.profile.weight, original.profile.weight);
      expect(restored.profile.height, original.profile.height);
      expect(restored.profile.fullName, original.profile.fullName);
      expect(restored.profile.dateOfBirth, original.profile.dateOfBirth);
      expect(restored.profile.phone, original.profile.phone);
      expect(restored.profile.address, original.profile.address);
      expect(restored.profile.nextOfKinName, original.profile.nextOfKinName);
      expect(restored.profile.nextOfKinPhone, original.profile.nextOfKinPhone);
      expect(restored.profile.hospitalName, original.profile.hospitalName);
    });
  });
}