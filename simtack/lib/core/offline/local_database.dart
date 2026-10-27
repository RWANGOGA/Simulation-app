import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'local_envelope.dart';

/// The device's own copy of every clinical record the app needs.
///
/// One JSON document holds every patient, every triage session and the sync
/// outbox. A single document rather than a key per record because the point is
/// that a mutation is atomic: a crash mid-write leaves the previous document
/// intact instead of half of a visit. Malformed or newer documents are moved
/// aside rather than thrown away silently.
///
/// `shared_preferences` is the backing store because it is the one durable
/// option that already works on Android, iOS, web and in tests with no native
/// setup, and a clinic's worth of visits is a few hundred kilobytes. If that
/// ever stops being true, this class is the only thing that has to change.
///
/// At rest the document is encrypted ([local_envelope.dart], `ABL1:` AES-256-GCM)
/// under a data key held in the platform keystore. A host with no keystore — a
/// unit test, or a platform where the key cannot be kept apart from the data —
/// keeps the plaintext document instead, because encrypting with a key stored
/// beside the ciphertext protects nothing and would be a claim this file could
/// not honour. The choice is made once, in [open], and remembered on the
/// instance so every later write goes to the same place.
///
/// Nothing here knows what a triage session *means* — [OfflineRepository] does.
/// This layer owns the shape on disk and the atomicity of writing it.
class LocalDatabase {
  LocalDatabase._(this._root, {Uint8List? dataKey}) : _dataKey = dataKey;

  /// Bumped when the on-disk *shape* changes; [open] refuses anything else. The
  /// move from plaintext to an encrypted envelope did not change the shape, so
  /// this stayed 1; the storage format is marked by the envelope prefix instead.
  static const int schemaVersion = 1;

  /// The plaintext document, and where every record lived before at-rest
  /// encryption. Kept readable so a device can be migrated, and is removed only
  /// once the encrypted document verifies.
  static const String _documentKey = 'offline_db_v1';

  /// The encrypted document, `ABL1:` over the same JSON.
  static const String _secureKey = 'offline_db_v2';

  static LocalDatabase? _cached;

  /// The keystore the app configured at startup, or null for plaintext storage.
  /// Set only through [configureKeyStore]; production passes a
  /// `SecureDataKeyStore`, a unit test passes an in-memory one to reach the
  /// encrypted path, and the default — never configured — is exactly what a
  /// widget test runs against, so the secure-storage plugin is never touched
  /// unless the app opted in. This matters because `flutter_secure_storage`'s
  /// read never returns under `flutter_tester`.
  static DataKeyStore? _keyStore;

  final Map<String, dynamic> _root;

  /// Non-null when this instance stores encrypted under [local_envelope]. Null
  /// means the plaintext document. Decided once in [open].
  final Uint8List? _dataKey;

  /// A write is applied to [_root] and then persisted while holding this chain,
  /// so two mutations cannot interleave and lose one another.
  Future<void> _chain = Future<void>.value();

  static Future<LocalDatabase> open() async {
    final cached = _cached;
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();

    // Encryption is opted into, never discovered: the app wires a keystore in at
    // startup through [configureKeyStore], and only then does the document go
    // through the envelope. A host that has not configured one — a widget test,
    // or a platform where a key cannot be kept apart from the data — keeps the
    // plaintext document, because encrypting with a key stored beside the
    // ciphertext protects nothing and would be a claim this file could not
    // honour. Reaching for the platform keystore here would also hang a test
    // harness, so this layer deliberately never constructs one itself.
    final keyStore = _keyStore;
    if (keyStore != null) {
      return _openEncrypted(prefs, keyStore);
    }
    return _openPlaintext(prefs);
  }

  /// Encrypted storage: read the data key (creating it on first use), open the
  /// `ABL1:` document, or migrate a plaintext one up. The plaintext original is
  /// kept until the encrypted write reads back and authenticates, so a migration
  /// can never strand a clinic's records halfway.
  static Future<LocalDatabase> _openEncrypted(
    SharedPreferences prefs,
    DataKeyStore keyStore,
  ) async {
    final stored = await keyStore.read();
    final createdKey = stored == null;
    final key = stored ?? newDataKey();

    final secureRaw = prefs.getString(_secureKey);
    final plainRaw = prefs.getString(_documentKey);

    Map<String, dynamic> root;
    if (secureRaw != null && secureRaw.isNotEmpty) {
      final opening = openDocument(secureRaw, key);
      if (opening.isOpened && opening.record!['version'] == schemaVersion) {
        root = opening.record!;
      } else {
        // Will not open (the key rotated or the bytes are corrupt), or a shape
        // this build does not understand. Never guess a record out of it: set
        // the blob aside and fall back to the plaintext original, if any, so a
        // clinic's records stay recoverable rather than overwritten.
        await _quarantine(prefs, _secureKey, secureRaw);
        root = await _rootFromPlaintext(prefs, plainRaw);
      }
    } else {
      // No encrypted document yet: migrate the plaintext one, or start fresh.
      root = await _rootFromPlaintext(prefs, plainRaw);
    }

    // Persist, then read the persisted bytes back and confirm they authenticate
    // under this key, before trusting the encrypted store or clearing the
    // plaintext. Only after that do we drop the plaintext original.
    await prefs.setString(_secureKey, sealDocument(root, key));
    if (createdKey) await keyStore.write(key);
    final verify = openDocument(prefs.getString(_secureKey) ?? '', key);
    if (verify.isOpened && plainRaw != null && plainRaw.isNotEmpty) {
      await prefs.remove(_documentKey);
    }

    final database = LocalDatabase._(root, dataKey: key);
    _cached = database;
    return database;
  }

  /// The plaintext path: exactly the document handling that predates at-rest
  /// encryption, used wherever a keystore is unavailable.
  static Future<LocalDatabase> _openPlaintext(SharedPreferences prefs) async {
    final root = await _rootFromPlaintext(prefs, prefs.getString(_documentKey));
    final database = LocalDatabase._(root);
    _cached = database;
    return database;
  }

  /// Parses a plaintext [raw], quarantining anything unparseable or newer than
  /// this build rather than overwriting it.
  static Future<Map<String, dynamic>> _rootFromPlaintext(
    SharedPreferences prefs,
    String? raw,
  ) async {
    if (raw == null || raw.isEmpty) return _emptyDocument();
    var root = _parseOrQuarantine(prefs, raw);
    if (root['version'] != schemaVersion) {
      // A document written by a future build. Rather than guess at its shape,
      // keep it and start clean: the records it holds are still recoverable by
      // hand, which they would not be if this overwrote them.
      await prefs.setString(
        '${_documentKey}_unsupported_${DateTime.now().millisecondsSinceEpoch}',
        raw,
      );
      root = _emptyDocument();
    }
    return root;
  }

  /// Sets [raw] aside under a timestamped key so an unreadable or future-shape
  /// document is recoverable by hand rather than overwritten.
  static Future<void> _quarantine(
    SharedPreferences prefs,
    String fromKey,
    String raw,
  ) =>
      prefs.setString(
        '${fromKey}_corrupt_${DateTime.now().millisecondsSinceEpoch}',
        raw,
      );

  /// Test hook: drops the cached document so a fresh one is read next time.
  static void resetForTest() {
    _cached = null;
    _keyStore = null;
  }

  /// Configures the keystore used to encrypt the document at rest. Call this
  /// once at startup, before the first [open]; passing null — or never calling
  /// it, which is what every widget test does — leaves the document in
  /// plaintext. Also forgets any cached instance so the next [open] honours the
  /// new setting.
  static void configureKeyStore(DataKeyStore? store) {
    _keyStore = store;
    _cached = null;
  }

  static Map<String, dynamic> _emptyDocument() => <String, dynamic>{
        'version': schemaVersion,
        'next_local_id': -1,
        'patients': <Map<String, dynamic>>[],
        'sessions': <Map<String, dynamic>>[],
        'outbox': <Map<String, dynamic>>[],
      };

  static Map<String, dynamic> _parseOrQuarantine(
    SharedPreferences prefs,
    String raw,
  ) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        // Normalise the collections so a hand-edited or partial document
        // cannot make a later write throw.
        return <String, dynamic>{
          'version': decoded['version'] ?? schemaVersion,
          'next_local_id': (decoded['next_local_id'] as num?)?.toInt() ?? -1,
          'patients': ((decoded['patients'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(),
          'sessions': ((decoded['sessions'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(),
          'outbox': ((decoded['outbox'] as List?) ?? const [])
              .whereType<Map<String, dynamic>>()
              .toList(),
        };
      }
    } catch (_) {
      // Fall through to quarantine below.
    }
    prefs.setString(
      '${_documentKey}_corrupt_${DateTime.now().millisecondsSinceEpoch}',
      raw,
    );
    return _emptyDocument();
  }

  /// Runs [action] against the document and persists the result before
  /// completing. [action] must be synchronous, which is what makes the write
  /// atomic: nothing can observe or modify a half-applied change.
  Future<T> mutate<T>(T Function(LocalDatabase db) action) {
    final completer = Completer<T>();
    _chain = _chain.then((_) async {
      try {
        final result = action(this);
        await _persist();
        completer.complete(result);
      } catch (error, stack) {
        completer.completeError(error, stack);
      }
    });
    return completer.future;
  }

  /// Reads the document, waiting for any in-flight write to land first so a
  /// caller cannot read the state it just replaced.
  Future<T> read<T>(T Function(LocalDatabase db) action) async {
    await _chain;
    return action(this);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final key = _dataKey;
    if (key != null) {
      // Encrypted store: the whole document is resealed under the data key.
      await prefs.setString(_secureKey, sealDocument(_root, key));
    } else {
      await prefs.setString(_documentKey, jsonEncode(_root));
    }
  }

  // ── Local ids ───────────────────────────────────────────────────────────
  //
  // Device-created rows are numbered downwards from -1 so a local id can never
  // be mistaken for a server id, which is always positive. A negative id is
  // therefore also the honest answer to "has this reached the server yet?".

  int takeLocalId() {
    final next = (_root['next_local_id'] as num).toInt();
    _root['next_local_id'] = next - 1;
    return next;
  }

  /// Every identifier already used by a patient, so a minted code cannot
  /// collide with a record that is still on the device.
  Set<String> get takenPatientCodes => {
        for (final patient in patients) ...{
          if (patient['code'] is String) patient['code'] as String,
          for (final alias in (patient['aliases'] as List?) ?? const [])
            alias.toString(),
        },
      };

  // ── Patients ────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get patients =>
      (_root['patients'] as List).cast<Map<String, dynamic>>();

  Map<String, dynamic>? patientByCode(String code) {
    final wanted = code.trim();
    if (wanted.isEmpty) return null;
    for (final patient in patients) {
      if (patient['code'] == wanted) return patient;
      final aliases = (patient['aliases'] as List?) ?? const [];
      if (aliases.contains(wanted)) return patient;
    }
    return null;
  }

  Map<String, dynamic>? patientByLocalId(int? localId) {
    if (localId == null) return null;
    for (final patient in patients) {
      if (patient['local_id'] == localId) return patient;
    }
    return null;
  }

  void insertPatient(Map<String, dynamic> patient) => patients.add(patient);

  // ── Sessions ────────────────────────────────────────────────────────────

  /// Every session, newest first — the order every server read uses.
  ///
  /// Timestamps decide the order; ids only break ties, and there they count
  /// *upwards*, because local ids count downwards: the newest row has the most
  /// negative id. Two pain points submitted in the same microsecond would
  /// otherwise come back oldest-first, which is enough to invert a visit.
  List<Map<String, dynamic>> get sessions {
    final list = (_root['sessions'] as List).cast<Map<String, dynamic>>();
    final sorted = [...list];
    sorted.sort((a, b) {
      final byDate = _createdAt(b).compareTo(_createdAt(a));
      return byDate != 0
          ? byDate
          : (a['id'] as num).toInt().compareTo((b['id'] as num).toInt());
    });
    return sorted;
  }

  List<Map<String, dynamic>> sessionsForPatient(int? patientLocalId) {
    if (patientLocalId == null) return const [];
    return sessions.where((s) => s['patient_id'] == patientLocalId).toList();
  }

  Map<String, dynamic>? sessionByLocalId(int id) {
    for (final session in sessions) {
      if (session['id'] == id) return session;
    }
    return null;
  }

  void insertSession(Map<String, dynamic> session) =>
      (_root['sessions'] as List).add(session);

  /// Port of `crud_triage.get_latest_visit`: the sibling sessions of the
  /// patient's most recent visit, oldest first. Rows with no `visit_id` are
  /// each their own visit of one, which is what the SQL falls back to.
  List<Map<String, dynamic>> latestVisitForPatient(int? patientLocalId) {
    final all = sessionsForPatient(patientLocalId);
    if (all.isEmpty) return const [];
    final latest = all.first;
    final visitId = latest['visit_id'];
    if (visitId == null || visitId == '') return [latest];
    final sameVisit =
        all.where((s) => s['visit_id'] == visitId).toList().reversed.toList();
    return sameVisit;
  }

  /// Port of `get_regions_in_visit`: every region already reported under this
  /// visit, so a new pain point is scored aware of its siblings.
  List<String> regionsInVisit(String? visitId) {
    if (visitId == null || visitId.isEmpty) return const [];
    return [
      for (final session in sessions.reversed)
        if (session['visit_id'] == visitId && session['body_region'] is String)
          session['body_region'] as String,
    ];
  }

  /// The patient an in-progress visit already belongs to, if any.
  ///
  /// A patient who never created a profile submits several pain points with no
  /// patient attached. Without this, each one would mint its own anonymous
  /// patient and the QR code would only ever resolve to one of them; keying on
  /// the visit keeps the whole visit on one record.
  int? patientIdForVisit(String? visitId) {
    if (visitId == null || visitId.isEmpty) return null;
    for (final session in sessions) {
      if (session['visit_id'] == visitId) {
        return (session['patient_id'] as num?)?.toInt();
      }
    }
    return null;
  }

  static DateTime _createdAt(Map<String, dynamic> session) {
    final raw = session['created_at'];
    if (raw is String) {
      return DateTime.tryParse(raw) ?? DateTime.fromMillisecondsSinceEpoch(0);
    }
    return DateTime.fromMillisecondsSinceEpoch(0);
  }

  // ── Outbox ──────────────────────────────────────────────────────────────

  List<Map<String, dynamic>> get outbox =>
      (_root['outbox'] as List).cast<Map<String, dynamic>>();

  void enqueue(Map<String, dynamic> operation) =>
      (_root['outbox'] as List).add(operation);

  /// Removes the operations matching [test], returning how many went.
  int removeOutboxWhere(bool Function(Map<String, dynamic> op) test) {
    final list = _root['outbox'] as List;
    final before = list.length;
    list.removeWhere((op) => test(op as Map<String, dynamic>));
    return before - list.length;
  }

  /// Number of records that still exist only on this device.
  int get pendingUploadCount => [
        ...patients.where((p) => p['remote_id'] == null),
        ...sessions.where((s) => s['remote_id'] == null),
      ].length;

  /// Mints a patient code in the server's format: `P-` plus twelve base-36
  /// characters. Uses [Random.secure] because the code is the patient's only
  /// credential for the QR lookup — a guessable one would be an access token
  /// someone could enumerate.
  String newPatientCode() {
    const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    final taken = takenPatientCodes;
    while (true) {
      final suffix = List.generate(
        12,
        (_) => alphabet[random.nextInt(alphabet.length)],
      ).join();
      final code = 'P-$suffix';
      if (!taken.contains(code)) return code;
    }
  }
}
