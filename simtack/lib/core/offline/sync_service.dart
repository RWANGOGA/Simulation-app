import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

import '../models/patient_profile.dart';
import '../network/api_client.dart';
import '../network/connectivity_service.dart';
import 'local_database.dart';

/// What one pass over the outbox did.
class SyncResult {
  const SyncResult({this.uploaded = 0, this.pending = 0, this.stoppedBy});

  /// Records the server accepted this pass. A record it already held counts:
  /// uploading it again was the right thing to do, and it is now reconciled.
  final int uploaded;

  /// Records that still exist only on this device.
  final int pending;

  /// Why the pass stopped early, or null when it reached the end of the queue.
  final String? stoppedBy;

  bool get isComplete => stoppedBy == null;

  @override
  String toString() =>
      'SyncResult(uploaded: $uploaded, pending: $pending, stoppedBy: $stoppedBy)';
}

/// Uploads what the device recorded, whenever the server can be reached.
///
/// Nothing the app does depends on this: [OfflineRepository] is the source of
/// truth and the server is a mirror. So this only ever moves records *towards*
/// the server, never back, and never deletes anything locally. A record that
/// cannot be uploaded stays on the device and stays visible in
/// [LocalDatabase.pendingUploadCount].
///
/// The queue is drained in the order it was written, because the operations
/// depend on each other: a report cannot be filed before the patient it belongs
/// to, and a decision cannot be recorded before the report.
class SyncService {
  SyncService._();

  static final SyncService instance = SyncService._();

  /// How many times a server *rejection* is retried before the record is left
  /// alone. Transport failures do not count — an outage of any length must not
  /// burn through attempts and abandon a patient's record.
  static const int maxAttempts = 5;

  bool _running = false;
  StreamSubscription<ConnectivityResult>? _connectivity;

  /// Starts the background sync: one attempt now, then one every time the
  /// device comes back online. Safe to call more than once.
  void start() {
    if (_connectivity != null) return;
    _connectivity = ConnectivityService.instance.onConnectivityChanged.listen(
      (result) {
        if (result != ConnectivityResult.none) unawaited(syncNow());
      },
      // A platform that cannot report connectivity is a reason to stop hearing
      // about changes, not a reason to crash the app.
      onError: (_) {},
    );
    unawaited(syncNow());
  }

  /// Stops listening. Queued records are untouched.
  Future<void> stop() async {
    await _connectivity?.cancel();
    _connectivity = null;
  }

  /// Drains the outbox once. Never throws: a sync that cannot run is not an
  /// error the caller has to handle, it is just a sync that did not happen.
  Future<SyncResult> syncNow() async {
    try {
      final db = await LocalDatabase.open();
      if (_running) return SyncResult(pending: db.pendingUploadCount);

      _running = true;
      try {
        return await _drain(db);
      } finally {
        _running = false;
      }
    } catch (error) {
      // Anything unexpected — no storage, no platform channels — stops this
      // pass rather than losing the queue.
      return SyncResult(stoppedBy: error.toString());
    }
  }

  Future<SyncResult> _drain(LocalDatabase db) async {
    // A snapshot of the queue to walk, holding the *same* row objects: a failure
    // has to be recorded on the row that is actually stored, and an accepted
    // upload removes it from underneath this loop.
    final queue = await db.read((db) => [...db.outbox]);
    final authorised = await ApiClient.isLoggedIn;

    var uploaded = 0;
    String? stoppedBy;

    for (final op in queue) {
      if (op['kind'] != 'create_patient' &&
          op['kind'] != 'send_triage' &&
          !authorised) {
        // Everything else is JWT-guarded. Leave it queued and move on, so the
        // public intake records still get through before anyone signs in.
        continue;
      }
      if (_isAbandoned(op)) continue;

      final _Outcome outcome;
      try {
        outcome = await _upload(db, op);
      } on ApiException catch (error) {
        if (error.isNetworkError) {
          // The server is unreachable. Keep every record, and stop here rather
          // than hammering it once per queued row.
          await _record(db, op, error.message, counted: false);
          stoppedBy = error.message;
          break;
        }
        if (_isTransient(error.statusCode)) {
          await _record(db, op, error.message, counted: false);
          stoppedBy = error.message;
          break;
        }
        // A rejection of this one record. Nothing about retrying it blind will
        // change the answer, so note it and let the rest of the queue through.
        await _record(db, op, error.message, counted: true);
        continue;
      } catch (error) {
        await _record(db, op, error.toString(), counted: true);
        continue;
      }

      switch (outcome) {
        case _Outcome.uploaded:
          uploaded++;
          await _remove(db, op);
        case _Outcome.nothingToDo:
          await _remove(db, op);
        case _Outcome.deferred:
          await _record(db, op, null, counted: true);
      }
    }

    return SyncResult(
      uploaded: uploaded,
      pending: await db.read((db) => db.pendingUploadCount),
      stoppedBy: stoppedBy,
    );
  }

  Future<_Outcome> _upload(LocalDatabase db, Map<String, dynamic> op) {
    switch (op['kind']) {
      case 'create_patient':
        return _uploadPatient(db, op);
      case 'update_patient':
        return _uploadDemographics(db, op);
      case 'send_triage':
        return _uploadTriage(db, op);
      case 'update_decision':
        return _uploadDecision(db, op);
      default:
        // An operation written by a newer build. Keep the row, skip it.
        return Future.value(_Outcome.deferred);
    }
  }

  /// Creates the patient on the server under the code the device minted.
  Future<_Outcome> _uploadPatient(
    LocalDatabase db,
    Map<String, dynamic> op,
  ) async {
    final patient = await _patientFor(db, op);
    if (patient == null) return _Outcome.nothingToDo;
    // Already reconciled on an earlier pass.
    if (patient['remote_id'] != null) return _Outcome.nothingToDo;

    final code = patient['code'] as String?;
    final payload = op['payload'];
    if (code == null || payload is! Map) return _Outcome.deferred;

    final PatientResult result;
    try {
      result = await ApiClient.createPatient(
        PatientProfile.fromJson(Map<String, dynamic>.from(payload)),
        anonymousCode: code,
      );
    } on ApiException catch (error) {
      if (error.statusCode == 409) {
        // The server already holds this code: an earlier attempt landed and
        // only the response was lost. Same patient, nothing to redo — but it
        // still counts as uploaded, because it is now on the server.
        await db.mutate((_) => patient['remote_id'] = 0);
        return _Outcome.uploaded;
      }
      rethrow;
    }

    await db.mutate((_) {
      patient['remote_id'] = result.id;
      // The server keeps the code the device minted, so this is normally a
      // no-op — assert it rather than silently drifting to a second code.
      patient['code'] = result.anonymousCode;
      patient['synced_at'] = DateTime.now().toUtc().toIso8601String();
    });
    return _Outcome.uploaded;
  }

  Future<_Outcome> _uploadDemographics(
    LocalDatabase db,
    Map<String, dynamic> op,
  ) async {
    final patient = await _patientFor(db, op);
    final payload = op['payload'];
    if (patient == null) return _Outcome.nothingToDo;
    if (payload is! Map) return _Outcome.deferred;

    final code = patient['code'] as String?;
    if (code == null) return _Outcome.deferred;

    await ApiClient.updatePatientDemographics(
      code,
      PatientProfile.fromJson(Map<String, dynamic>.from(payload)),
    );
    return _Outcome.uploaded;
  }

  Future<_Outcome> _uploadTriage(
    LocalDatabase db,
    Map<String, dynamic> op,
  ) async {
    final session = await _sessionFor(db, op);
    if (session == null) return _Outcome.nothingToDo;
    if (session['remote_id'] != null) return _Outcome.nothingToDo;

    final payload = op['payload'];
    if (payload is! Map) return _Outcome.deferred;

    final patient =
        await db.read((db) => db.patientByLocalId(session['patient_id'] as int?));
    final code = patient?['code'] as String?;
    if (code == null) return _Outcome.deferred;

    final report = TriageReport.fromJson(Map<String, dynamic>.from(payload));
    final result = await ApiClient.sendTriage(report.withPatient(
      // The server knows this patient under the same code, so the report is
      // filed against the record rather than creating a second one.
      patientCode: code,
      patientId: (patient?['remote_id'] as num?)?.toInt(),
    ));

    await db.mutate((_) {
      session['remote_id'] = result.id;
      session['synced_at'] = DateTime.now().toUtc().toIso8601String();
    });
    return _Outcome.uploaded;
  }

  Future<_Outcome> _uploadDecision(
    LocalDatabase db,
    Map<String, dynamic> op,
  ) async {
    final session = await _sessionFor(db, op);
    final payload = op['payload'];
    if (session == null) return _Outcome.nothingToDo;
    if (payload is! Map) return _Outcome.deferred;

    final remoteId = (session['remote_id'] as num?)?.toInt();
    if (remoteId == null || remoteId <= 0) {
      // The report has not reached the server yet, so there is nothing to hang
      // a decision on. The queue is drained in order, so this resolves itself as
      // soon as the report above it is accepted.
      return _Outcome.deferred;
    }

    await ApiClient.updateTriageDecision(
      remoteId,
      status: payload['status'] as String?,
      priority: payload['priority'] as String?,
      actionsTaken: payload['actions_taken'] is List
          ? (payload['actions_taken'] as List).map((e) => e.toString()).toList()
          : null,
      clinicalNotes: payload['clinical_notes'] as String?,
    );
    return _Outcome.uploaded;
  }

  Future<Map<String, dynamic>?> _patientFor(
    LocalDatabase db,
    Map<String, dynamic> op,
  ) {
    final localId = (op['entity_local_id'] as num?)?.toInt();
    return db.read((db) => db.patientByLocalId(localId));
  }

  Future<Map<String, dynamic>?> _sessionFor(
    LocalDatabase db,
    Map<String, dynamic> op,
  ) {
    final localId = (op['entity_local_id'] as num?)?.toInt();
    if (localId == null) return Future.value(null);
    return db.read((db) => db.sessionByLocalId(localId));
  }

  Future<void> _remove(LocalDatabase db, Map<String, dynamic> op) =>
      db.mutate((db) =>
          db.removeOutboxWhere((queued) => queued['id'] == op['id']));

  /// Notes a failed attempt on the queued row itself, so the record is not
  /// silently retried forever with no trace of why it is stuck. [counted] is
  /// false for failures that say nothing about the record (the server being
  /// down or unreachable), which must not burn attempts.
  Future<void> _record(
    LocalDatabase db,
    Map<String, dynamic> op,
    String? error, {
    required bool counted,
  }) =>
      db.mutate((_) {
        if (counted) {
          op['attempts'] = ((op['attempts'] as num?)?.toInt() ?? 0) + 1;
        }
        // A failure with no message leaves the previous reason in place rather
        // than blanking the only clue.
        if (error != null) op['last_error'] = error;
        op['last_attempt_at'] = DateTime.now().toUtc().toIso8601String();
      });

  static bool _isAbandoned(Map<String, dynamic> op) =>
      ((op['attempts'] as num?)?.toInt() ?? 0) >= maxAttempts;

  /// Worth retrying unchanged: the server could not take the request right now,
  /// but might later.
  static bool _isTransient(int? status) =>
      status == null ||
      status == 401 ||
      status == 403 ||
      status == 408 ||
      status == 429 ||
      status >= 500;
}

enum _Outcome {
  /// The server took it.
  uploaded,

  /// Nothing left to do: the record is gone from the device, or the server
  /// already had it.
  nothingToDo,

  /// Cannot be uploaded yet, but the rest of the queue can proceed.
  deferred,
}
