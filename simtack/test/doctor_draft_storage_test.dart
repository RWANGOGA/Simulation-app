import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/storage/doctor_draft.dart';
import 'package:simtack/core/storage/doctor_draft_storage.dart';
import 'package:simtack/core/network/api_client.dart';

import 'support/in_memory_credential_vault.dart';

void main() {
  late InMemoryCredentialVault vault;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    vault = InMemoryCredentialVault();
    DoctorDraftStorage.vault = vault;
  });

  group('DoctorDraftStorage', () {
    test('save and loadAll works', () async {
      final draft = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'test@example.com',
          fullName: 'Test Doctor',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('password123'),
      );

      await DoctorDraftStorage.save(draft);
      final drafts = await DoctorDraftStorage.loadAll();

      expect(drafts.length, 1);
      expect(drafts.first.profile.email, 'test@example.com');
      expect(drafts.first.profile.fullName, 'Test Doctor');
    });

    test('save overwrites draft with same email', () async {
      final draft1 = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'test@example.com',
          fullName: 'Doctor One',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('pass1'),
      );

      final draft2 = DoctorDraft.createOffline(
        profile: Doctor(
          id: -2,
          email: 'test@example.com',
          fullName: 'Doctor Two',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('pass2'),
      );

      await DoctorDraftStorage.save(draft1);
      await DoctorDraftStorage.save(draft2);

      final drafts = await DoctorDraftStorage.loadAll();
      expect(drafts.length, 1);
      expect(drafts.first.profile.fullName, 'Doctor Two');
    });

    test('save overwrites draft with same localId', () async {
      final draft1 = DoctorDraft(
        localId: -100,
        profile: Doctor(
          id: -100,
          email: 'one@example.com',
          fullName: 'Doctor One',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('pass1'),
        savedAt: DateTime(2024, 1, 1),
      );

      final draft2 = DoctorDraft(
        localId: -100,
        profile: Doctor(
          id: -100,
          email: 'two@example.com',
          fullName: 'Doctor Two',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('pass2'),
        savedAt: DateTime(2024, 1, 2),
      );

      await DoctorDraftStorage.save(draft1);
      await DoctorDraftStorage.save(draft2);

      final drafts = await DoctorDraftStorage.loadAll();
      expect(drafts.length, 1);
      expect(drafts.first.profile.email, 'two@example.com');
    });

    test('findByEmail returns matching draft', () async {
      final draft = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'findme@example.com',
          fullName: 'Find Me',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('password'),
      );

      await DoctorDraftStorage.save(draft);

      final found = await DoctorDraftStorage.findByEmail('findme@example.com');
      expect(found, isNotNull);
      expect(found!.profile.fullName, 'Find Me');
    });

    test('findByEmail is case-insensitive', () async {
      final draft = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'Test@Example.COM',
          fullName: 'Test',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('password'),
      );

      await DoctorDraftStorage.save(draft);

      final found = await DoctorDraftStorage.findByEmail('test@example.com');
      expect(found, isNotNull);
    });

    test('findByEmail returns null for non-existent email', () async {
      final found =
          await DoctorDraftStorage.findByEmail('nonexistent@example.com');
      expect(found, isNull);
    });

    test('remove deletes draft', () async {
      final draft = DoctorDraft.createOffline(
        profile: Doctor(
          id: -1,
          email: 'remove@example.com',
          fullName: 'Remove Me',
          isActive: true,
        ),
        passwordHash: DoctorDraft.hash('password'),
      );

      await DoctorDraftStorage.save(draft);
      expect((await DoctorDraftStorage.loadAll()).length, 1);

      await DoctorDraftStorage.remove(draft);
      expect((await DoctorDraftStorage.loadAll()).length, 0);
    });

    test('clear removes all drafts', () async {
      await DoctorDraftStorage.save(DoctorDraft(
        localId: -1,
        profile: Doctor(
            id: -1, email: 'a@example.com', fullName: 'A', isActive: true),
        passwordHash: 'hash',
        savedAt: DateTime(2024, 1, 1),
      ));
      await DoctorDraftStorage.save(DoctorDraft(
        localId: -2,
        profile: Doctor(
            id: -2, email: 'b@example.com', fullName: 'B', isActive: true),
        passwordHash: 'hash',
        savedAt: DateTime(2024, 1, 2),
      ));

      expect((await DoctorDraftStorage.loadAll()).length, 2);

      await DoctorDraftStorage.clear();
      expect((await DoctorDraftStorage.loadAll()).length, 0);
    });

    test('loadAll returns drafts sorted newest first', () async {
      final oldDraft = DoctorDraft(
        localId: -1,
        profile: Doctor(
            id: -1, email: 'old@example.com', fullName: 'Old', isActive: true),
        passwordHash: 'hash',
        savedAt: DateTime(2024, 1, 1),
      );

      final newDraft = DoctorDraft(
        localId: -2,
        profile: Doctor(
            id: -2, email: 'new@example.com', fullName: 'New', isActive: true),
        passwordHash: 'hash',
        savedAt: DateTime(2024, 1, 2),
      );

      await DoctorDraftStorage.save(oldDraft);
      await DoctorDraftStorage.save(newDraft);

      final drafts = await DoctorDraftStorage.loadAll();
      expect(drafts.first.profile.fullName, 'New');
      expect(drafts.last.profile.fullName, 'Old');
    });

    test('loadLatest returns most recent draft', () async {
      await DoctorDraftStorage.save(DoctorDraft(
        localId: -1,
        profile: Doctor(
            id: -1, email: 'old@example.com', fullName: 'Old', isActive: true),
        passwordHash: 'hash',
        savedAt: DateTime(2024, 1, 1),
      ));

      await DoctorDraftStorage.save(DoctorDraft(
        localId: -2,
        profile: Doctor(
            id: -2, email: 'new@example.com', fullName: 'New', isActive: true),
        passwordHash: 'hash',
        savedAt: DateTime(2024, 1, 2),
      ));

      final latest = await DoctorDraftStorage.loadLatest();
      expect(latest, isNotNull);
      expect(latest!.profile.fullName, 'New');
    });
  });

  group('credential vault', () {
    DoctorDraft draftWith(String password) => DoctorDraft.createOffline(
          profile: Doctor(
            id: -1,
            email: 'test@example.com',
            fullName: 'Test Doctor',
            isActive: true,
          ),
          passwordHash: DoctorDraft.hash(password),
        );

    test('the digest never reaches the stored document', () async {
      await DoctorDraftStorage.save(draftWith('password123'));

      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString('doctor_drafts')!;

      // The document is not protected: readable by anything that can read app
      // storage. The digest must not be in it.
      expect(stored.contains('pbkdf2-sha256'), isFalse);
      expect(stored.contains('passwordHash'), isFalse);
      expect(vault.digests['test@example.com'], startsWith('pbkdf2-sha256'));
    });

    test('the account still verifies once the digest comes back from the vault',
        () async {
      await DoctorDraftStorage.save(draftWith('password123'));

      final loaded = await DoctorDraftStorage.loadLatest();

      expect(loaded!.verifyPassword('password123'), isTrue);
      expect(loaded.verifyPassword('wrong'), isFalse);
    });

    test('a digest left inline by an older build is moved out on first load',
        () async {
      // Exactly what the previous build wrote: the whole draft, digest included.
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
          'doctor_drafts', jsonEncode([draftWith('password123').toJson()]));

      final loaded = await DoctorDraftStorage.loadAll();

      expect(loaded.single.verifyPassword('password123'), isTrue);
      expect(vault.digests['test@example.com'], startsWith('pbkdf2-sha256'));
      // And the document no longer carries it, without waiting for a sign-in.
      expect(
          prefs.getString('doctor_drafts')!.contains('pbkdf2-sha256'), isFalse);
    });

    test('an unavailable keystore costs offline sign-in, not the account',
        () async {
      vault.failing = true;

      await DoctorDraftStorage.save(draftWith('password123'));
      final loaded = await DoctorDraftStorage.loadLatest();

      // The record survives so a connected sign-in can repair it, but no
      // password verifies against it in the meantime.
      expect(loaded, isNotNull);
      expect(loaded!.verifyPassword('password123'), isFalse);
    });

    test('clearing the accounts clears their digests too', () async {
      await DoctorDraftStorage.save(draftWith('password123'));

      await DoctorDraftStorage.clear();

      expect(vault.digests, isEmpty);
      expect(await DoctorDraftStorage.loadAll(), isEmpty);
    });
  });
}
