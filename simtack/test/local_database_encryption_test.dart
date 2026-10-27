import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/offline/local_database.dart';
import 'package:simtack/core/offline/local_envelope.dart';

/// The store's on-disk behaviour once at-rest encryption is switched on.
///
/// A `DataKeyStore` is injected so the encrypted path — which on a real device is
/// the platform keystore — is reachable in a unit test. These assert the three
/// things the security claim rests on: the clinical document is never written as
/// plaintext once a key exists, a legacy plaintext store is migrated without
/// losing records and only after the encrypted copy verifies, and an envelope
/// that will not open is never guessed back into a partly readable document.
class _MemoryKeyStore implements DataKeyStore {
  Uint8List? key;

  @override
  Future<Uint8List?> read() async => key;

  @override
  Future<void> write(Uint8List value) async => key = value;
}

const _plaintextKey = 'offline_db_v1';
const _secureKey = 'offline_db_v2';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    LocalDatabase.resetForTest();
  });

  test('a fresh store writes the document encrypted, never as plaintext',
      () async {
    LocalDatabase.configureKeyStore(_MemoryKeyStore());

    final db = await LocalDatabase.open();
    final code = db.newPatientCode();
    await db.mutate((d) => d.insertPatient({'code': code}));

    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_secureKey);
    expect(stored, isNotNull);
    expect(stored, startsWith('ABL1:'));
    // The patient's own code must not be sitting in the file in the clear.
    expect(stored, isNot(contains(code)));
    expect(prefs.getString(_plaintextKey), isNull,
        reason: 'the encrypted path must not also leave a plaintext document');
  });

  test('a store that was already open reads its own encrypted writes back',
      () async {
    final store = _MemoryKeyStore();
    LocalDatabase.configureKeyStore(store);

    final first = await LocalDatabase.open();
    await first.mutate((d) {
      d.insertPatient({'code': 'P-KEEP123', 'local_id': -1});
      return null;
    });

    // Same key, fresh open: exactly what a relaunch does.
    LocalDatabase.resetForTest();
    LocalDatabase.configureKeyStore(store);
    final second = await LocalDatabase.open();

    expect(await second.read((d) => d.patientByCode('P-KEEP123')), isNotNull);
  });

  test('a legacy plaintext store is migrated and the plaintext is removed',
      () async {
    // Write the way a pre-encryption build did: a JSON document under v1.
    SharedPreferences.setMockInitialValues({
      _plaintextKey: jsonEncode({
        'version': 1,
        'next_local_id': -2,
        'patients': [
          {'code': 'P-OLD123', 'local_id': -1}
        ],
        'sessions': <Map<String, dynamic>>[],
        'outbox': <Map<String, dynamic>>[],
      }),
    });
    LocalDatabase.resetForTest();
    LocalDatabase.configureKeyStore(_MemoryKeyStore());

    final db = await LocalDatabase.open();

    // The record survived the migration ...
    expect(await db.read((d) => d.patientByCode('P-OLD123')), isNotNull);
    // ... and the plaintext it came from is gone once the encrypted copy verified.
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(_plaintextKey), isNull,
        reason: 'migration must not leave the plaintext document behind');
    expect(prefs.getString(_secureKey), startsWith('ABL1:'));
  });

  test('an unreadable envelope is quarantined, never returned as plaintext',
      () async {
    final store = _MemoryKeyStore()..key = newDataKey();
    // Seal under one key, then swap the keystore to a different key: the device
    // can no longer open its own store (a rotated/lost key).
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _secureKey,
      sealDocument({'version': 1, 'patients': [], 'sessions': [], 'outbox': []},
          newDataKey()),
    );
    LocalDatabase.resetForTest();
    LocalDatabase.configureKeyStore(store);

    final db = await LocalDatabase.open();

    // It starts clean rather than fabricating a record it cannot authenticate.
    expect(await db.read((d) => d.patients), isEmpty);
    // And the unreadable blob was set aside, not deleted.
    final keys = (await SharedPreferences.getInstance()).getKeys();
    expect(
      keys.any((k) => k.startsWith('${_secureKey}_corrupt_')),
      isTrue,
      reason: 'an unreadable store is kept for recovery, not silently dropped',
    );
  });

  test('a future-shape encrypted document is not opened as a current one',
      () async {
    final store = _MemoryKeyStore()..key = newDataKey();
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    // A document from a future build: it opens under the key, but its shape
    // version is not this one, so it must not be treated as a current store.
    await prefs.setString(
      _secureKey,
      sealDocument({
        'version': 99,
        'patients': [
          {'code': 'P-FUTURE', 'local_id': -1}
        ],
        'sessions': <Map<String, dynamic>>[],
        'outbox': <Map<String, dynamic>>[],
      }, store.key!),
    );
    LocalDatabase.resetForTest();
    LocalDatabase.configureKeyStore(store);

    final db = await LocalDatabase.open();

    expect(await db.read((d) => d.patientByCode('P-FUTURE')), isNull,
        reason: 'a future-shape document is started clean, not misread');
  });
}
