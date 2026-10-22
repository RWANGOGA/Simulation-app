import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/models/patient_profile.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/offline/local_database.dart';
import 'package:simtack/core/offline/offline_repository.dart';
import 'package:simtack/core/offline/sync_service.dart';

import 'support/clinical_assets.dart';

class _TokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<void> write(String value) async => _token = value;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> writeRefreshToken(String value) async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> delete() async => _token = null;
}

/// Proves that what a device records eventually reaches a server, and that a
/// server that is down, slow or unhappy never costs the device a record.
void main() {
  late OfflineRepository repo;
  late List<http.Request> requests;
  late TokenStorage tokens;
  final defaultClient = ApiClient.httpClient;
  final defaultStorage = ApiClient.tokenStorage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OfflineRepository.resetForTest();
    await loadClinicalDataForTest();
    repo = OfflineRepository.instance;
    requests = [];
    tokens = _TokenStorage();
    ApiClient.tokenStorage = tokens;
  });

  tearDown(() {
    ApiClient.httpClient = defaultClient;
    ApiClient.tokenStorage = defaultStorage;
  });

  const profile = PatientProfile(
    age: 41,
    gender: 'Female',
    weight: 82,
    height: 160,
    fullName: 'Amina Nakato',
    phone: '+256700000000',
  );

  String accepted(http.Request request) {
    if (request.url.path.endsWith('/patients/')) {
      final sent = jsonDecode(request.body) as Map<String, dynamic>;
      return jsonEncode({
        'id': 900,
        'anonymous_code': sent['anonymous_code'] ?? 'P-SERVERMADE01',
        ...sent,
      });
    }
    return jsonEncode({
      'id': 501,
      'patient_id': 900,
      'anonymous_code': 'P-RETURNED',
      'body_region': 'Chest / Heart',
      'pain_type': 'Crushing',
      'severity': 7,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
  }

  /// Answers anything the way a healthy server would, recording what it was
  /// asked. Patient ids start at 900 so a server id can never be confused with
  /// the negative ids the device uses.
  void serverThatAccepts({
    int Function(http.Request request)? status,
    String Function(http.Request request)? body,
  }) {
    ApiClient.httpClient = MockClient((request) async {
      requests.add(request);
      // A create is 201; everything else (a decision) is a plain 200.
      final code =
          status?.call(request) ?? (request.method == 'POST' ? 201 : 200);
      final payload = body?.call(request) ?? accepted(request);
      return http.Response(payload, code,
          headers: {'content-type': 'application/json'});
    });
  }

  /// Records one patient and one report, which is the smallest thing that
  /// leaves work for the uploader to do.
  Future<String> recordAVisit() async {
    final patient = await repo.createPatient(profile);
    await repo.sendTriage(TriageReport(
      bodyRegion: 'Chest / Heart',
      painType: 'Crushing',
      severity: 7,
      visitId: 'visit-1',
      patientId: patient.id,
      patientCode: patient.anonymousCode,
    ));
    return patient.anonymousCode;
  }

  test('does nothing when the device has recorded nothing', () async {
    ApiClient.httpClient = MockClient((request) async {
      fail('No request should be made with an empty outbox.');
    });

    final result = await SyncService.instance.syncNow();

    expect(result.uploaded, 0);
    expect(result.pending, 0);
    expect(result.isComplete, isTrue);
  });

  test('uploads the patient first, under the code the device minted', () async {
    final code = await recordAVisit();
    serverThatAccepts();

    final result = await SyncService.instance.syncNow();

    expect(result.uploaded, 2);
    expect(result.pending, 0);
    expect(result.isComplete, isTrue);

    // The patient has to exist before a report can be filed against them.
    expect(requests.map((r) => r.url.path), [
      '/api/v1/patients/',
      '/api/v1/triage/',
    ]);

    final patientBody = jsonDecode(requests.first.body) as Map<String, dynamic>;
    expect(patientBody['anonymous_code'], code);
    expect(patientBody['full_name'], 'Amina Nakato');

    // The report is filed against that same patient record.
    expect(requests.last.headers['X-Patient-Code'], code);
    expect((jsonDecode(requests.last.body) as Map)['visit_id'], 'visit-1');

    final db = await LocalDatabase.open();
    expect(db.outbox, isEmpty);
  });

  test('a code the server already holds is reconciled, not retried', () async {
    await recordAVisit();
    serverThatAccepts(status: (request) {
      return request.url.path.endsWith('/patients/') ? 409 : 201;
    });

    final result = await SyncService.instance.syncNow();

    // Nothing failed: the patient was already there from an earlier attempt
    // whose response was lost, and the report still went through.
    expect(result.uploaded, 2);
    expect(result.pending, 0);
    expect(result.isComplete, isTrue);
  });

  test('an unreachable server costs nothing and is not retried per record',
      () async {
    await recordAVisit();
    ApiClient.httpClient = MockClient((request) async {
      requests.add(request);
      // What a real client throws when nothing answers.
      throw http.ClientException('Connection refused', request.url);
    });

    final result = await SyncService.instance.syncNow();

    expect(result.uploaded, 0);
    expect(result.pending, 2);
    expect(result.stoppedBy, isNotNull);
    // Stopped at the first failure instead of hammering the server twice.
    expect(requests, hasLength(1));

    final db = await LocalDatabase.open();
    expect(db.outbox, hasLength(2));
    // An outage says nothing about the records, so it must not use up the
    // retries that exist for records the server actually rejects.
    expect(db.outbox.every((op) => op['attempts'] == 0), isTrue);
    expect(db.outbox.first['last_error'], isNotNull);
  });

  test('a rejected record is kept without blocking the rest', () async {
    await recordAVisit();
    serverThatAccepts(status: (request) {
      return request.url.path.endsWith('/triage/') ? 422 : 201;
    });

    final result = await SyncService.instance.syncNow();

    expect(result.uploaded, 1);
    expect(result.pending, 1);
    // A 422 is an answer about that one report, not a reason to stop.
    expect(result.isComplete, isTrue);

    final db = await LocalDatabase.open();
    expect(db.outbox, hasLength(1));
    expect(db.outbox.single['kind'], 'send_triage');
    expect(db.outbox.single['attempts'], 1);
    expect(db.outbox.single['last_error'], isNotNull);
  });

  test('a decision is filed against the id the server issued', () async {
    await tokens.write('test-token');
    final code = await recordAVisit();
    final visit = await repo.getLatestVisit(code);
    await repo.updateTriageDecision(
      visit.first.id,
      status: 'closed',
      actionsTaken: ['ECG'],
    );
    serverThatAccepts();

    final result = await SyncService.instance.syncNow();

    expect(result.uploaded, 3);
    expect(result.pending, 0);
    // The device knows this report as a negative local id; the server knows it
    // as 501, and that is what the decision has to name.
    expect(requests.last.url.path, '/api/v1/triage/501/decision');
    expect(jsonDecode(requests.last.body), {
      'status': 'closed',
      'actions_taken': ['ECG'],
    });
  });

  test('a record that needs a session stays queued until one exists', () async {
    final code = await recordAVisit();
    final visit = await repo.getLatestVisit(code);
    await repo.updateTriageDecision(visit.first.id, status: 'closed');
    serverThatAccepts();

    final result = await SyncService.instance.syncNow();

    // Without a practitioner session the decision cannot be PATCHed, but the
    // public intake records still go.
    expect(result.uploaded, 2);
    // No new record is waiting on the server — the session itself made it — but
    // the decision on it is still queued.
    expect(result.pending, 0);

    final db = await LocalDatabase.open();
    expect(db.outbox.single['kind'], 'update_decision');
    // Not the record's fault, so it is not counting towards abandonment.
    expect(db.outbox.single['attempts'], 0);
  });

  test('a second pass picks up exactly what the first left behind', () async {
    await tokens.write('test-token');
    final code = await recordAVisit();
    final visit = await repo.getLatestVisit(code);
    await repo.updateTriageDecision(visit.first.id, status: 'closed');

    // First pass: the server is down.
    ApiClient.httpClient = MockClient((request) async {
      throw http.ClientException('Connection refused', request.url);
    });
    final first = await SyncService.instance.syncNow();
    expect(first.uploaded, 0);
    final db = await LocalDatabase.open();
    expect(db.outbox, hasLength(3));

    // Second pass: it is back.
    serverThatAccepts();
    final second = await SyncService.instance.syncNow();

    expect(second.uploaded, 3);
    expect(second.pending, 0);
    expect(db.outbox, isEmpty);
    expect(requests, hasLength(3));
  });

  test('the patient record keeps the server id once it is accepted', () async {
    final code = await recordAVisit();
    serverThatAccepts();

    await SyncService.instance.syncNow();

    final stored = await repo.findPatient(code);
    // Stored as the server id, so a later edit addresses the right record.
    expect(stored?['remote_id'], 900);
    // The code the patient's card carries is unchanged.
    expect(stored?['code'], code);
  });
}
