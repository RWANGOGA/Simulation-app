import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/models/patient_profile.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/offline/local_database.dart';
import 'package:simtack/core/offline/offline_repository.dart';

import 'support/clinical_assets.dart';

/// Proves the app can record and read a whole patient journey with no server.
///
/// Every test here runs against `shared_preferences`' in-memory store and the
/// real generated clinical assets, so it exercises the same code paths a device
/// with no signal does: scores the report on the device, stores it, and serves
/// it back through the same shapes the screens already read.
void main() {
  late OfflineRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    OfflineRepository.resetForTest();
    await loadClinicalDataForTest();
    repo = OfflineRepository.instance;
  });

  const profile = PatientProfile(
    age: 41,
    gender: 'Female',
    weight: 82,
    height: 160,
    fullName: 'Amina Nakato',
    phone: '+256700000000',
    nextOfKinName: 'Joan Nakato',
    nextOfKinPhone: '+256700000001',
  );

  TriageReport report({
    String region = 'Chest / Heart',
    String painType = 'Crushing',
    int severity = 7,
    String? visitId,
    int? patientId,
    String? patientCode,
    String? direction,
    List<String>? triggers,
    Map<String, String>? answers,
  }) =>
      TriageReport(
        bodyRegion: region,
        painType: painType,
        severity: severity,
        direction: direction,
        visitId: visitId,
        patientId: patientId,
        patientCode: patientCode,
        triggers: triggers,
        questionAnswers: answers,
      );

  String newVisitId() => 'visit-${DateTime.now().microsecondsSinceEpoch}';

  group('patients', () {
    test('a patient gets a scannable code and a provisional id', () async {
      final result = await repo.createPatient(profile);

      expect(result.anonymousCode, matches(RegExp(r'^P-[A-Z0-9]{12}$')));
      // Negative means "recorded here, not yet on a server".
      expect(result.id, lessThan(0));
    });

    test('codes never repeat', () async {
      final codes = <String>{};
      for (var i = 0; i < 20; i++) {
        codes.add((await repo.createPatient(profile)).anonymousCode);
      }
      expect(codes, hasLength(20));
    });

    test('demographics can be corrected afterwards', () async {
      final created = await repo.createPatient(profile);
      await repo.updatePatientDemographics(
        created.anonymousCode,
        const PatientProfile(
          age: 42,
          gender: 'Female',
          weight: 80,
          height: 161,
          fullName: 'Amina N. Nakato',
        ),
      );

      final stored = await repo.findPatient(created.anonymousCode);
      expect(stored?['age'], 42);
      expect(stored?['full_name'], 'Amina N. Nakato');
      // Fields the caller did not send are left alone.
      expect(stored?['phone'], '+256700000000');
    });
  });

  group('submitting a report', () {
    test('scores and stores with no network at all', () async {
      final patient = await repo.createPatient(profile);
      final result = await repo.sendTriage(report(
        patientId: patient.id,
        patientCode: patient.anonymousCode,
        visitId: newVisitId(),
        triggers: ['Worse on exertion'],
        answers: {'radiation': 'left arm'},
      ));

      expect(result.id, lessThan(0));
      expect(result.anonymousCode, patient.anonymousCode);
      // 0.40 region + 0.35 severity + 0.20 pain type + 0.05 BMI, clamped at 1.
      expect(result.riskScore, 1.0);
      expect(result.riskLevel, 'HIGH RISK');

      // The audit trail is stored as the same JSON string the server writes.
      expect(result.shapExplanation, contains('Severity 7/10'));
      expect(result.shapExplanation, contains('Region: Chest / Heart'));

      // Crushing chest pain is an emergency regardless of the total.
      expect(result.escalation, isNotNull);
      expect(result.needsEmergencyCare, isTrue);
      expect(result.escalation!.reasons, contains('Crushing chest pain'));

      // Everything the report renders survived the round trip.
      expect(result.triggers, ['Worse on exertion']);
      expect(result.questionAnswers, {'radiation': 'left arm'});
      expect(result.status, 'open');
      expect(result.patientAge, 41);
      expect(result.patientWeight, 82.0);
      expect(result.patientName, 'Amina Nakato');
      expect(result.patientNextOfKinName, 'Joan Nakato');
    });

    test('a report with no patient still gets a code to scan', () async {
      final visitId = newVisitId();
      final result = await repo.sendTriage(report(visitId: visitId));

      expect(result.anonymousCode, matches(RegExp(r'^P-[A-Z0-9]{12}$')));
      expect(result.anonymousCode, isNot('P-UNKNOWN'));

      // A second pain point in the same visit joins the first one's record
      // instead of minting another orphan.
      final sibling = await repo.sendTriage(
        report(
            region: 'Left Arm / Shoulder', painType: 'Sharp', visitId: visitId),
      );
      expect(sibling.anonymousCode, result.anonymousCode);

      final visit = await repo.getLatestVisit(result.anonymousCode!);
      expect(visit, hasLength(2));
    });

    test('sibling regions raise the score through the body graph', () async {
      // A BMI in the normal range, so the connection bonus is visible instead of
      // being absorbed by the clamp at 1.0.
      final patient = await repo.createPatient(const PatientProfile(
        age: 30,
        gender: 'Male',
        weight: 60,
        height: 165,
      ));
      final visitId = newVisitId();

      await repo.sendTriage(report(
        region: 'Left Arm / Shoulder',
        painType: 'Sharp',
        severity: 2,
        visitId: visitId,
        patientId: patient.id,
        patientCode: patient.anonymousCode,
      ));
      final chest = await repo.sendTriage(report(
        region: 'Chest / Heart',
        painType: 'Sharp',
        severity: 4,
        visitId: visitId,
        patientId: patient.id,
        patientCode: patient.anonymousCode,
      ));
      final alone = await repo.sendTriage(report(
        region: 'Chest / Heart',
        painType: 'Sharp',
        severity: 4,
        visitId: newVisitId(),
        patientId: patient.id,
        patientCode: patient.anonymousCode,
      ));

      // Chest / Heart and Left Arm / Shoulder are a high-concern connection:
      // 0.72 alone, 0.97 once the arm is in the same visit.
      expect(alone.riskScore, 0.72);
      expect(chest.riskScore, 0.97);
      expect(chest.shapExplanation, contains('Connected to reported'));
      expect(alone.shapExplanation, isNot(contains('Connected to reported')));
    });
  });

  group('reading back', () {
    late String code;
    late String olderVisit;
    late String newestVisit;

    setUp(() async {
      final patient = await repo.createPatient(profile);
      code = patient.anonymousCode;
      olderVisit = newVisitId();
      newestVisit = newVisitId();

      // Three reports across two visits, one per band: 0.25 low, 1.00 high,
      // 0.60 medium. The third one is in the same visit as the second, but the
      // body graph finds no connection between the two regions.
      await repo.sendTriage(report(
        region: 'Left Leg',
        painType: 'Dull',
        severity: 1,
        visitId: olderVisit,
        patientId: patient.id,
        patientCode: code,
      ));
      await repo.sendTriage(report(
        region: 'Chest / Heart',
        painType: 'Crushing',
        severity: 7,
        visitId: newestVisit,
        patientId: patient.id,
        patientCode: code,
      ));
      await repo.sendTriage(report(
        region: 'Headache / Cranial',
        painType: 'Dull',
        severity: 3,
        visitId: newestVisit,
        patientId: patient.id,
        patientCode: code,
      ));
    });

    test('the latest visit is the last one, not the whole history', () async {
      final latest = await repo.getLatestVisit(code);
      expect(latest, hasLength(2));
      expect(latest.map((r) => r.visitId).toSet(), {newestVisit});
      // Oldest first, inside the visit.
      expect(latest.first.bodyRegion, 'Chest / Heart');
    });

    test('the full history is everything, newest first', () async {
      final history = await repo.getPatientHistory(code);
      expect(history, hasLength(3));
      expect(history.first.visitId, newestVisit);
      expect(history.last.visitId, olderVisit);
    });

    test('an unknown code fails the way the server fails', () async {
      await expectLater(
        repo.getLatestVisit('P-DOESNOTEXIST'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 404)
            .having((e) => e.message, 'message', 'Patient ID not found')),
      );
    });

    test('stats count the bands', () async {
      final stats = await repo.getTriageStats();
      expect(stats['total'], 3);
      expect(stats['high_risk'], 1);
      expect(stats['medium_risk'], 1);
      expect(stats['low_risk'], 1);
      expect(
        (stats['high_risk'] as int) +
            (stats['medium_risk'] as int) +
            (stats['low_risk'] as int),
        stats['total'],
      );
    });

    test('reports break down the way the Reports screen expects', () async {
      final payload = await repo.getTriageReports();

      expect(payload['period'], 'all');
      expect(payload['total'], 3);
      expect(payload['open_count'], 3);
      expect(payload['closed_count'], 0);
      expect(payload['high_risk_count'], 1);
      expect(payload['medium_risk_count'], 1);
      // (1 + 7 + 3) / 3, rounded like Python's round(x, 1).
      expect(payload['avg_severity'], 3.7);
      // (0.25 + 1.0 + 0.6) / 3, rounded like Python's round(x, 2).
      expect(payload['avg_risk_score'], 0.62);

      final byRegion =
          (payload['by_region'] as List).cast<Map<String, dynamic>>();
      expect(byRegion.first['count'], 1);
      expect(
          byRegion.map((e) => e['region']),
          containsAll(<String>[
            'Headache / Cranial',
            'Chest / Heart',
            'Left Leg',
          ]));
      final byPainType =
          (payload['by_pain_type'] as List).cast<Map<String, dynamic>>();
      expect(byPainType.map((e) => e['pain_type']),
          containsAll(<String>['Dull', 'Crushing']));
      expect(byPainType.map((e) => e['pain_type']), contains('Dull'));
      expect(
        byPainType.firstWhere((e) => e['pain_type'] == 'Dull')['count'],
        2,
      );
    });

    test('the list rows carry the keys the dashboard reads', () async {
      final rows = await repo.getTriageList(limit: 50, offset: 0);
      expect(rows, hasLength(3));
      expect(
        rows.first.keys.toSet(),
        {
          'id',
          'anonymous_code',
          'body_region',
          'pain_type',
          'severity',
          'risk_score',
          'shap_explanation',
          'patient_age',
          'patient_gender',
          'status',
          'created_at',
        },
      );
      expect(rows.first['anonymous_code'], code);
      expect(rows.first['patient_age'], 41);
      expect(rows.first['status'], 'open');
      // Newest first.
      expect(rows.first['body_region'], 'Headache / Cranial');

      expect((await repo.getTriageList(riskLevel: 'HIGH')), hasLength(1));
      expect((await repo.getTriageList(riskLevel: 'MEDIUM')), hasLength(1));
      expect((await repo.getTriageList(riskLevel: 'LOW')), hasLength(1));
      // Paging is a ceiling on this side too.
      expect((await repo.getTriageList(limit: 2)), hasLength(2));
      expect((await repo.getTriageList(limit: 2, offset: 2)), hasLength(1));
      // The server matches the code with ilike '%needle%'.
      expect((await repo.getTriageList(patientCode: code.substring(0, 8))),
          hasLength(3));
      expect((await repo.getTriageList(patientCode: 'ZZZZZZ')), isEmpty);
    });

    test('a decision is recorded and reads back on the report', () async {
      final latest = await repo.getLatestVisit(code);
      final updated = await repo.updateTriageDecision(
        latest.first.id,
        status: 'closed',
        priority: 'urgent',
        actionsTaken: ['ECG', 'Referred to A&E'],
        clinicalNotes: 'Sent to Mulago.',
      );

      expect(updated.status, 'closed');
      expect(updated.priority, 'urgent');
      expect(updated.actionsTaken, ['ECG', 'Referred to A&E']);
      expect(updated.clinicalNotes, 'Sent to Mulago.');

      final reread = await repo.getLatestVisit(code);
      expect(reread.first.status, 'closed');
      expect((await repo.getTriageList(status: 'closed')), hasLength(1));
      expect((await repo.getTriageReports())['closed_count'], 1);
    });

    test('a decision on an unknown session is a 404', () async {
      await expectLater(
        repo.updateTriageDecision(-999, status: 'closed'),
        throwsA(
            isA<ApiException>().having((e) => e.statusCode, 'statusCode', 404)),
      );
    });

    test('everything survives an app restart', () async {
      // Drop every cached instance: the next call has to rebuild itself from
      // what is actually on disk.
      LocalDatabase.resetForTest();
      OfflineRepository.resetForTest();
      final reopened = OfflineRepository.instance;

      final history = await reopened.getPatientHistory(code);
      expect(history, hasLength(3));
      expect(history.first.anonymousCode, code);
      expect(history.first.patientName, 'Amina Nakato');
      expect((await reopened.getTriageStats())['total'], 3);
    });
  });

  group('anatomy', () {
    test('answers from the bundled knowledge base', () async {
      final insight = await repo.askAnatomy(
        region: 'Chest / Heart',
        complaint: 'crushing chest pain spreading to left arm',
      );

      expect(insight.llmUsed, isFalse);
      expect(insight.sources, isNotEmpty);
      expect(insight.sources.first.id, 'chest_heart');
      expect(insight.summary, isNotEmpty);
    });

    test('lists regions for the picker', () async {
      final regions = await repo.listAnatomyRegions();
      expect(regions, hasLength(34));
      expect(regions.map((r) => r.region), contains('Abdomen (Upper)'));
    });
  });

  group('sync outbox', () {
    test('every write is queued for a later upload', () async {
      final patient = await repo.createPatient(profile);
      final triage = await repo.sendTriage(report(
        patientId: patient.id,
        patientCode: patient.anonymousCode,
        visitId: newVisitId(),
      ));
      await repo.updateTriageDecision(triage.id, status: 'closed');

      final db = await LocalDatabase.open();
      final kinds = db.outbox.map((op) => op['kind']).toList();
      expect(kinds, ['create_patient', 'send_triage', 'update_decision']);
      // Each op is addressed to the local row it came from, so reconciliation
      // after a server id arrives has somewhere to write back.
      expect(db.outbox[1]['entity_local_id'], triage.id);
      expect(db.outbox[1]['payload'], isA<Map<String, dynamic>>());
      expect(db.outbox.every((op) => op['attempts'] == 0), isTrue);
      expect(db.pendingUploadCount, 2);
    });
  });
}
