import 'dart:convert';
import 'dart:math';

import 'package:simtack/core/clinical/anatomy_engine.dart';
import 'package:simtack/core/clinical/clinical_data.dart';
import 'package:simtack/core/clinical/risk_engine.dart';
import 'package:simtack/core/models/patient_profile.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/offline/local_database.dart';

/// The app's data layer when there is no server.
///
/// Same methods, same return types and the same error shape as the
/// `ApiClient` calls the screens already make, so a screen becomes a one-line
/// swap and keeps rendering exactly what it rendered before. Underneath:
///
/// * writes go to [LocalDatabase] first and succeed immediately,
/// * scoring and red flags are computed on the device by [RiskEngine],
/// * anatomy questions are answered by [AnatomyEngine] over the bundled KB,
/// * every write also lands in the sync outbox, so nothing is lost when a
///   connection does appear.
///
/// The read endpoints reproduce the server's semantics — including its 404s,
/// its `get_latest_visit` grouping, its risk band filters and its aggregate
/// shapes — because `ClinicalReportScreen` and the dashboard read those shapes
/// directly and should not have to know which side answered them.
///
/// Rows created here are numbered downwards from -1 (see
/// [LocalDatabase.takeLocalId]), so a negative id means "recorded here, not yet
/// on a server" and can never be mistaken for a server id.
class OfflineRepository {
  OfflineRepository({LocalDatabase? database}) : _injected = database;

  static OfflineRepository? _instance;

  static OfflineRepository get instance => _instance ??= OfflineRepository();

  /// Test hook: forgets the singleton (and its database) between tests.
  static void resetForTest() {
    _instance = null;
    LocalDatabase.resetForTest();
  }

  final LocalDatabase? _injected;

  Future<LocalDatabase> get _db async =>
      _injected ?? await LocalDatabase.open();

  RiskEngine get _engine => RiskEngine();

  // ── Patients ────────────────────────────────────────────────────────────

  /// Records a patient on the device and returns the code printed in their QR.
  ///
  /// [PatientResult.id] is negative until the record reaches a server; the
  /// code is what everything else addresses, exactly as on the backend.
  Future<PatientResult> createPatient(PatientProfile profile) async {
    final db = await _db;
    return db.mutate((db) {
      final patient = _newPatientRecord(db, profile);
      db.insertPatient(patient);
      db.enqueue({
        'id': _token(),
        'kind': 'create_patient',
        'entity_local_id': patient['local_id'],
        'payload': profile.toJson(),
        'created_at': _nowIso(),
        'attempts': 0,
        'last_error': null,
      });
      return PatientResult(
        id: patient['local_id'] as int,
        anonymousCode: patient['code'] as String,
      );
    });
  }

  /// Practitioner correction of a patient's demographics. Sends only the fields
  /// the caller actually set, the way `PatientProfile.toJson` does.
  Future<void> updatePatientDemographics(
    String anonymousCode,
    PatientProfile profile,
  ) async {
    final db = await _db;
    await db.mutate((db) {
      final patient = db.patientByCode(anonymousCode);
      if (patient == null) {
        throw ApiException(statusCode: 404, message: 'Patient ID not found');
      }
      final incoming = profile.toJson();
      for (final field in _profileFields) {
        if (incoming.containsKey(field)) {
          patient[field] = incoming[field];
        }
      }
      patient['updated_at'] = _nowIso();
      db.enqueue({
        'id': _token(),
        'kind': 'update_patient',
        'entity_local_id': patient['local_id'],
        'payload': incoming,
        'created_at': _nowIso(),
        'attempts': 0,
        'last_error': null,
      });
    });
  }

  /// The demographics the report screen pre-fills its edit sheet with, if this
  /// patient is on the device.
  Future<Map<String, dynamic>?> findPatient(String anonymousCode) async {
    final db = await _db;
    return db.read((db) => db.patientByCode(anonymousCode));
  }

  // ── Triage ──────────────────────────────────────────────────────────────

  /// Scores one pain point on the device and stores it.
  ///
  /// The score is [RiskEngine.compute] over the generated rule table and the
  /// siblings already reported under the same `visit_id`, which is exactly what
  /// the server does — so the number the patient sees offline is the number the
  /// report would show online, not an approximation of it.
  Future<TriageResult> sendTriage(TriageReport report) async {
    final db = await _db;
    return db.mutate((db) {
      final patient = _resolvePatientFor(db, report);
      // Weight and height feed the BMI factor; the server resolves the patient
      // before scoring for the same reason.
      final input = TriageInput(
        bodyRegion: report.bodyRegion,
        painType: report.painType,
        severity: report.severity,
        direction: report.direction,
        // The capture form no longer collects vitals, and TriageReport does not
        // send them, so the server scores these as absent too.
        heartRate: null,
        spo2: null,
        patientWeight: _asDouble(patient['weight']),
        patientHeight: _asDouble(patient['height']),
        siblingRegions: db.regionsInVisit(report.visitId),
      );

      final assessment = _engine.compute(input);
      final now = _nowIso();

      final session = <String, dynamic>{
        'id': db.takeLocalId(),
        'remote_id': null,
        'patient_id': patient['local_id'],
        'body_region': report.bodyRegion,
        'pain_type': report.painType,
        'severity': report.severity,
        'heart_rate': null,
        'spo2': null,
        'direction': report.direction,
        'depth': report.depth,
        'expansion_behavior': report.expansionBehavior,
        'triggers': report.triggers ?? const <String>[],
        'relievers': report.relievers ?? const <String>[],
        'daily_limitations': report.dailyLimitations ?? const <String>[],
        'visit_id': report.visitId,
        'risk_score': assessment.risk,
        'shap_explanation':
            jsonEncode([for (final c in assessment.contributions) c.toJson()]),
        'status': 'open',
        'priority': null,
        'actions_taken': const <String>[],
        'clinical_notes': null,
        'question_answers': report.questionAnswers,
        'created_at': now,
      };
      db.insertSession(session);
      db.enqueue({
        'id': _token(),
        'kind': 'send_triage',
        'entity_local_id': session['id'],
        // The body a server sync would POST, captured at submission time so a
        // later edit to the rule table cannot rewrite history on upload.
        'payload': report.toJson(),
        'created_at': now,
        'attempts': 0,
        'last_error': null,
      });

      return TriageResult.fromJson(_sessionPayload(session, patient));
    });
  }

  /// Port of `GET /triage/patient/{code}`: the patient's most recent visit.
  Future<List<TriageResult>> getLatestVisit(String patientCode) async {
    final db = await _db;
    return db.read((db) {
      final patient = db.patientByCode(patientCode);
      if (patient == null) {
        throw ApiException(statusCode: 404, message: 'Patient ID not found');
      }
      final sessions = db.latestVisitForPatient(patient['local_id'] as int?);
      if (sessions.isEmpty) {
        throw ApiException(
          statusCode: 404,
          message: 'No clinical report found for this patient',
        );
      }
      return [
        for (final session in sessions)
          TriageResult.fromJson(_sessionPayload(session, patient)),
      ];
    });
  }

  /// Port of `GET /triage/patient/{code}/history`: every session, newest first.
  Future<List<TriageResult>> getPatientHistory(String patientCode) async {
    final db = await _db;
    return db.read((db) {
      final patient = db.patientByCode(patientCode);
      if (patient == null) {
        throw ApiException(statusCode: 404, message: 'Patient ID not found');
      }
      return [
        for (final session
            in db.sessionsForPatient(patient['local_id'] as int?))
          TriageResult.fromJson(_sessionPayload(session, patient)),
      ];
    });
  }

  /// Port of `GET /triage/stats`.
  Future<Map<String, dynamic>> getTriageStats() async {
    final db = await _db;
    return db.read((db) {
      final sessions = db.sessions;
      final bands = _bands;
      var high = 0;
      var medium = 0;
      for (final session in sessions) {
        final score = _score(session);
        if (score >= bands.$1) {
          high++;
        } else if (score >= bands.$2) {
          medium++;
        }
      }
      return <String, dynamic>{
        'total': sessions.length,
        'high_risk': high,
        'medium_risk': medium,
        'low_risk': sessions.length - high - medium,
      };
    });
  }

  /// Port of `GET /triage/reports`, including its `period` window and rounding.
  Future<Map<String, dynamic>> getTriageReports({
    String period = 'all',
  }) async {
    final db = await _db;
    return db.read((db) {
      final now = DateTime.now().toUtc();
      final cutoff = switch (period) {
        'week' => now.subtract(const Duration(days: 7)),
        'month' => now.subtract(const Duration(days: 30)),
        _ => null,
      };
      final sessions = [
        for (final session in db.sessions)
          if (cutoff == null || _createdAt(session).isAfter(cutoff)) session,
      ];

      final bands = _bands;
      var high = 0;
      var medium = 0;
      var open = 0;
      var closed = 0;
      final byRegion = <String, int>{};
      final byPainType = <String, int>{};
      var severitySum = 0;
      var riskSum = 0.0;
      var riskCount = 0;

      for (final session in sessions) {
        final score = _score(session);
        if (score >= bands.$1) {
          high++;
        } else if (score >= bands.$2) {
          medium++;
        }
        // Rows written before the decision workflow existed have no status;
        // they are "open" in every practical sense, as on the server.
        if (session['status'] == 'closed') {
          closed++;
        } else {
          open++;
        }
        final region = session['body_region'];
        if (region is String && region.isNotEmpty) {
          byRegion[region] = (byRegion[region] ?? 0) + 1;
        }
        final painType = session['pain_type'];
        if (painType is String && painType.isNotEmpty) {
          byPainType[painType] = (byPainType[painType] ?? 0) + 1;
        }
        severitySum += (session['severity'] as num?)?.toInt() ?? 0;
        riskSum += score;
        riskCount++;
      }

      return <String, dynamic>{
        'period': period,
        'total': sessions.length,
        'high_risk_count': high,
        'medium_risk_count': medium,
        'low_risk_count': sessions.length - high - medium,
        'open_count': open,
        'closed_count': closed,
        'by_region': _breakdown(byRegion, 'region'),
        'by_pain_type': _breakdown(byPainType, 'pain_type'),
        'avg_severity': sessions.isEmpty
            ? null
            : (_round(severitySum / sessions.length, 1)),
        'avg_risk_score':
            riskCount == 0 ? null : _round(riskSum / riskCount, 2),
      };
    });
  }

  /// Port of `GET /triage/list`: one shallow row per session, newest first.
  ///
  /// The dashboard renders these maps directly, so the keys have to match the
  /// server's row for row.
  Future<List<Map<String, dynamic>>> getTriageList({
    int limit = 50,
    int offset = 0,
    String? patientCode,
    String? riskLevel,
    String? status,
  }) async {
    final db = await _db;
    return db.read((db) {
      final bands = _bands;
      final needle = patientCode?.trim().toLowerCase();
      final rows = <Map<String, dynamic>>[];

      for (final session in db.sessions) {
        final patient = db.patientByLocalId(session['patient_id'] as int?);
        final code = (patient?['code'] as String?) ?? 'Unknown';
        if (needle != null && needle.isNotEmpty) {
          // The server matches with ilike '%needle%'.
          if (!code.toLowerCase().contains(needle)) continue;
        }
        final score = _score(session);
        if (riskLevel == 'HIGH' && score < bands.$1) continue;
        if (riskLevel == 'MEDIUM' && (score < bands.$2 || score >= bands.$1)) {
          continue;
        }
        if (riskLevel == 'LOW' && score >= bands.$2) continue;
        final sessionStatus = (session['status'] as String?) ?? 'open';
        if (status != null && status.isNotEmpty && sessionStatus != status) {
          continue;
        }

        rows.add(<String, dynamic>{
          'id': session['id'],
          'anonymous_code': code,
          'body_region': session['body_region'],
          'pain_type': session['pain_type'],
          'severity': session['severity'],
          'risk_score': session['risk_score'],
          'shap_explanation': session['shap_explanation'],
          'patient_age': patient?['age'],
          'patient_gender': patient?['gender'],
          'status': sessionStatus,
          'created_at': session['created_at'],
        });
      }

      final start = offset.clamp(0, rows.length);
      final end = (start + limit).clamp(start, rows.length);
      return rows.sublist(start, end);
    });
  }

  /// Port of `PATCH /triage/{session_id}/decision`.
  Future<TriageResult> updateTriageDecision(
    int sessionId, {
    String? status,
    String? priority,
    List<String>? actionsTaken,
    String? clinicalNotes,
  }) async {
    final db = await _db;
    return db.mutate((db) {
      final session = db.sessionByLocalId(sessionId);
      if (session == null) {
        throw ApiException(
          statusCode: 404,
          message: 'Triage session not found',
        );
      }
      if (status != null) session['status'] = status;
      if (priority != null) session['priority'] = priority;
      if (actionsTaken != null) session['actions_taken'] = actionsTaken;
      if (clinicalNotes != null) session['clinical_notes'] = clinicalNotes;

      final patient = db.patientByLocalId(session['patient_id'] as int?);
      db.enqueue({
        'id': _token(),
        'kind': 'update_decision',
        'entity_local_id': sessionId,
        'payload': {
          if (status != null) 'status': status,
          if (priority != null) 'priority': priority,
          if (actionsTaken != null) 'actions_taken': actionsTaken,
          if (clinicalNotes != null) 'clinical_notes': clinicalNotes,
        },
        'created_at': _nowIso(),
        'attempts': 0,
        'last_error': null,
      });

      return TriageResult.fromJson(_sessionPayload(session, patient));
    });
  }

  // ── Anatomy ─────────────────────────────────────────────────────────────

  /// Answers from the bundled knowledge base. There is no LLM on the device, so
  /// `llm_used` is false and the UI shows its "KB only" badge.
  Future<AnatomyInsight> askAnatomy({
    required String region,
    String complaint = '',
    int topK = 3,
    String? conversationId,
  }) async {
    final engine = AnatomyEngine.instance;
    return AnatomyInsight.fromJson(
      engine.ask(region: region, complaint: complaint, topK: topK),
    );
  }

  Future<List<AnatomyRegion>> listAnatomyRegions() async => [
        for (final option in AnatomyEngine.instance.listRegions())
          AnatomyRegion(
            id: option.id,
            region: option.region,
            system: option.system,
          ),
      ];

  // ── Internals ───────────────────────────────────────────────────────────

  /// The band thresholds the engine is using, so a filter can never disagree
  /// with the label the same score gets.
  (double, double) get _bands {
    final rules = ClinicalData.isLoaded ? ClinicalData.instance.rules : null;
    return (rules?.highBand ?? 0.7, rules?.mediumBand ?? 0.4);
  }

  Map<String, dynamic> _newPatientRecord(
    LocalDatabase db,
    PatientProfile profile,
  ) {
    final json = profile.toJson();
    final now = _nowIso();
    return <String, dynamic>{
      'local_id': db.takeLocalId(),
      'remote_id': null,
      'code': db.newPatientCode(),
      'aliases': const <String>[],
      'age': json['age'],
      'gender': json['gender'],
      'weight': json['weight'],
      'height': json['height'],
      'full_name': json['full_name'],
      'date_of_birth': json['date_of_birth'],
      'phone': json['phone'],
      'address': json['address'],
      'next_of_kin_name': json['next_of_kin_name'],
      'next_of_kin_phone': json['next_of_kin_phone'],
      'hospital_name': json['hospital_name'],
      'created_at': now,
      'updated_at': now,
    };
  }

  /// Finds the patient a report belongs to, creating an anonymous one when the
  /// report names nobody — the same thing `POST /triage/` does when
  /// `patient_id` is absent, and the reason every offline session still has a
  /// code to print and scan.
  ///
  /// The visit is consulted before minting a new anonymous patient: a patient
  /// who submits three pain points without a profile must end up with one record
  /// and one QR code, not three unlinked ones.
  Map<String, dynamic> _resolvePatientFor(
    LocalDatabase db,
    TriageReport report,
  ) {
    final byId = db.patientByLocalId(report.patientId);
    if (byId != null) return byId;
    final code = report.patientCode;
    if (code != null && code.isNotEmpty) {
      final byCode = db.patientByCode(code);
      if (byCode != null) return byCode;
    }
    final fromVisit = db.patientByLocalId(db.patientIdForVisit(report.visitId));
    if (fromVisit != null) return fromVisit;

    final anonymous = _newPatientRecord(
      db,
      const PatientProfile(age: 0, gender: '', weight: 0, height: 0),
    );
    db.insertPatient(anonymous);
    return anonymous;
  }

  /// Port of `_session_payload`: the single response shape every read uses.
  ///
  /// Demographics are joined from the patient record on every read rather than
  /// copied onto the session, so a correction shows up in the old reports too —
  /// and `escalation` is recomputed from the stored columns, so a rule fix
  /// applies to records already on the device.
  Map<String, dynamic> _sessionPayload(
    Map<String, dynamic> session,
    Map<String, dynamic>? patient,
  ) {
    final input = TriageInput(
      bodyRegion: (session['body_region'] as String?) ?? '',
      painType: (session['pain_type'] as String?) ?? '',
      severity: (session['severity'] as num?)?.toInt() ?? 0,
      direction: session['direction'] as String?,
      heartRate: _asDouble(session['heart_rate']),
      spo2: _asDouble(session['spo2']),
    );

    return <String, dynamic>{
      'id': session['id'],
      'patient_id': session['patient_id'],
      'anonymous_code': patient?['code'],
      'body_region': session['body_region'],
      'pain_type': session['pain_type'],
      'severity': session['severity'],
      'heart_rate': session['heart_rate'],
      'spo2': session['spo2'],
      'direction': session['direction'],
      'depth': session['depth'],
      'expansion_behavior': session['expansion_behavior'],
      'triggers': session['triggers'],
      'relievers': session['relievers'],
      'daily_limitations': session['daily_limitations'],
      'visit_id': session['visit_id'],
      'risk_score': session['risk_score'],
      'shap_explanation': session['shap_explanation'],
      'escalation': _engine.escalation(input),
      'qr_payload_hash': session['qr_payload_hash'],
      'created_at': session['created_at'],
      'status': (session['status'] as String?) ?? 'open',
      'priority': session['priority'],
      'actions_taken': session['actions_taken'] ?? const <String>[],
      'clinical_notes': session['clinical_notes'],
      'question_answers': session['question_answers'],
      'patient_age': patient?['age'],
      'patient_gender': patient?['gender'],
      'patient_weight': patient?['weight'],
      'patient_height': patient?['height'],
      'patient_name': patient?['full_name'],
      'patient_date_of_birth': patient?['date_of_birth'],
      'patient_phone': patient?['phone'],
      'patient_address': patient?['address'],
      'patient_next_of_kin_name': patient?['next_of_kin_name'],
      'patient_next_of_kin_phone': patient?['next_of_kin_phone'],
      'patient_hospital_name': patient?['hospital_name'],
    };
  }

  static List<Map<String, dynamic>> _breakdown(
    Map<String, int> counts,
    String key,
  ) {
    final entries = counts.entries.toList()
      ..sort((a, b) {
        final byCount = b.value.compareTo(a.value);
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    return [
      for (final entry in entries) {key: entry.key, 'count': entry.value},
    ];
  }

  static double _score(Map<String, dynamic> session) =>
      (session['risk_score'] as num?)?.toDouble() ?? 0.0;

  static DateTime _createdAt(Map<String, dynamic> session) {
    final raw = session['created_at'];
    if (raw is String) {
      final parsed = DateTime.tryParse(raw);
      if (parsed != null) return parsed.toUtc();
    }
    return DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
  }

  static double? _asDouble(Object? value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  static double _round(double value, int places) {
    final factor = places == 1 ? 10.0 : 100.0;
    return (value * factor).roundToDouble() / factor;
  }

  static String _nowIso() => DateTime.now().toUtc().toIso8601String();

  /// Random, unique-enough identifier for an outbox entry.
  static String _token() {
    final micros = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    final rand = _random.nextInt(1 << 32).toRadixString(36);
    return '$micros-$rand';
  }

  static final Random _random = Random.secure();

  /// The patient fields a practitioner may correct.
  static const List<String> _profileFields = [
    'age',
    'gender',
    'weight',
    'height',
    'full_name',
    'date_of_birth',
    'phone',
    'address',
    'next_of_kin_name',
    'next_of_kin_phone',
    'hospital_name',
  ];
}
