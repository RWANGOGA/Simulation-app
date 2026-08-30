import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Storage contract for the auth token — abstracted so tests can inject
/// an in-memory fake instead of touching platform secure storage.
abstract class TokenStorage {
  Future<void> write(String value);
  Future<String?> read();
  Future<void> delete();
}

class SecureTokenStorage implements TokenStorage {
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(),
  );
  static const _tokenKey = 'auth_token';

  @override
  Future<void> write(String value) => _storage.write(key: _tokenKey, value: value);

  @override
  Future<String?> read() => _storage.read(key: _tokenKey);

  @override
  Future<void> delete() => _storage.delete(key: _tokenKey);
}

class Doctor {
  final int id;
  final String email;
  final String fullName;
  final bool isActive;
  final String? role;
  final String? licenseNumber;
  final String? phone;
  final String? hospitalName;

  const Doctor({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
    this.role,
    this.licenseNumber,
    this.phone,
    this.hospitalName,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) => Doctor(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        isActive: json['is_active'] as bool,
        role: json['role'] as String?,
        licenseNumber: json['license_number'] as String?,
        phone: json['phone'] as String?,
        hospitalName: json['hospital_name'] as String?,
      );
}

/// Error thrown by auth calls, with FastAPI's error shape parsed out —
/// handles both {"detail": "..."} (401) and {"detail": [...]} (422).
class ApiException implements Exception {
  final int? statusCode;
  final String message;

  ApiException({required this.message, this.statusCode});

  bool get isUnauthorized => statusCode == 401;

  @override
  String toString() => message;

  factory ApiException.fromResponse(int statusCode, String body) {
    try {
      final decoded = body.isNotEmpty ? jsonDecode(body) : null;
      final detail = decoded is Map ? decoded['detail'] : null;
      if (detail is String) {
        return ApiException(statusCode: statusCode, message: detail);
      }
      if (detail is List && detail.isNotEmpty) {
        final first = detail.first;
        final msg = first is Map
            ? (first['msg']?.toString() ?? 'Validation error')
            : first.toString();
        return ApiException(statusCode: statusCode, message: msg);
      }
      return ApiException(
        statusCode: statusCode,
        message: "Unexpected error (status $statusCode)",
      );
    } catch (_) {
      return ApiException(
        statusCode: statusCode,
        message: "Unexpected error (status $statusCode)",
      );
    }
  }
}

class PatientProfile {
  final int age;
  final String gender;
  final double weight;
  final double height;
  // Optional personal demographics — the flow stays fast for anonymous
  // walk-ins, but anything provided is stored and carried onto the
  // clinical report / QR-scan lookup.
  final String? fullName;
  final DateTime? dateOfBirth;
  final String? phone;
  final String? address;
  final String? nextOfKinName;
  final String? nextOfKinPhone;
  final String? hospitalName;

  const PatientProfile({
    required this.age,
    required this.gender,
    required this.weight,
    required this.height,
    this.fullName,
    this.dateOfBirth,
    this.phone,
    this.address,
    this.nextOfKinName,
    this.nextOfKinPhone,
    this.hospitalName,
  });

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'weight': weight,
        'height': height,
        if (fullName != null && fullName!.trim().isNotEmpty)
          'full_name': fullName!.trim(),
        if (dateOfBirth != null)
          'date_of_birth':
              '${dateOfBirth!.year.toString().padLeft(4, '0')}-'
              '${dateOfBirth!.month.toString().padLeft(2, '0')}-'
              '${dateOfBirth!.day.toString().padLeft(2, '0')}',
        if (phone != null && phone!.trim().isNotEmpty) 'phone': phone!.trim(),
        if (address != null && address!.trim().isNotEmpty)
          'address': address!.trim(),
        if (nextOfKinName != null && nextOfKinName!.trim().isNotEmpty)
          'next_of_kin_name': nextOfKinName!.trim(),
        if (nextOfKinPhone != null && nextOfKinPhone!.trim().isNotEmpty)
          'next_of_kin_phone': nextOfKinPhone!.trim(),
        if (hospitalName != null && hospitalName!.trim().isNotEmpty)
          'hospital_name': hospitalName!.trim(),
      };
}

class PatientResult {
  final int id;
  final String anonymousCode;

  const PatientResult({required this.id, required this.anonymousCode});

  factory PatientResult.fromJson(Map<String, dynamic> json) => PatientResult(
        id: json['id'] as int,
        anonymousCode: json['anonymous_code'] as String,
      );
}

class TriageReport {
  final String bodyRegion;
  final String painType;
  final int severity;
  final String? direction;
  final String? depth;
  final int? patientId;
  final String? visitId;

  const TriageReport({
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.direction,
    this.depth,
    this.patientId,
    this.visitId,
  });

  Map<String, dynamic> toJson() => {
        'body_region': bodyRegion,
        'pain_type': painType,
        'severity': severity,
        if (direction != null) 'direction': direction,
        if (depth != null) 'depth': depth,
        if (patientId != null) 'patient_id': patientId,
        if (visitId != null) 'visit_id': visitId,
      };
}

class TriageResult {
  final int id;
  final int? patientId;
  final String? anonymousCode;
  final String bodyRegion;
  final String painType;
  final int severity;
  final String? direction;
  final String? depth;
  final String? visitId;
  final double? riskScore;
  final String? shapExplanation;
  final String? qrPayloadHash;
  final DateTime createdAt;
  // Patient demographics — collected at intake and stored server-side, now
  // joined onto every triage response so they can actually be displayed.
  final int? patientAge;
  final String? patientGender;
  final double? patientWeight;
  final double? patientHeight;
  // Personal demographics carried through so the practitioner sees the
  // patient's identity/contact when scanning the QR passport.
  final String? patientName;
  final String? patientDateOfBirth;
  final String? patientPhone;
  final String? patientAddress;
  final String? patientNextOfKinName;
  final String? patientNextOfKinPhone;
  final String? patientHospitalName;
  // Practitioner decision workflow (blueprint section 5).
  final String status; // 'open' until reviewed, then 'closed'
  final String? priority;
  final List<String> actionsTaken;
  final String? clinicalNotes;

  const TriageResult({
    required this.id,
    this.patientId,
    this.anonymousCode,
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.direction,
    this.depth,
    this.visitId,
    this.riskScore,
    this.shapExplanation,
    this.qrPayloadHash,
    required this.createdAt,
    this.patientAge,
    this.patientGender,
    this.patientWeight,
    this.patientHeight,
    this.patientName,
    this.patientDateOfBirth,
    this.patientPhone,
    this.patientAddress,
    this.patientNextOfKinName,
    this.patientNextOfKinPhone,
    this.patientHospitalName,
    this.status = 'open',
    this.priority,
    this.actionsTaken = const [],
    this.clinicalNotes,
  });

  String get riskLevel {
    final score = riskScore ?? 0.0;
    if (score >= 0.7) return 'HIGH RISK';
    if (score >= 0.4) return 'MEDIUM RISK';
    return 'LOW RISK';
  }

  factory TriageResult.fromJson(Map<String, dynamic> json) {
    return TriageResult(
      id: json['id'] as int,
      patientId: json['patient_id'] as int?,
      anonymousCode: json['anonymous_code'] as String?,
      bodyRegion: json['body_region'] as String,
      painType: json['pain_type'] as String,
      severity: json['severity'] as int,
      direction: json['direction'] as String?,
      depth: json['depth'] as String?,
      visitId: json['visit_id'] as String?,
      riskScore: (json['risk_score'] as num?)?.toDouble(),
      shapExplanation: json['shap_explanation'] as String?,
      qrPayloadHash: json['qr_payload_hash'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
      patientAge: json['patient_age'] as int?,
      patientGender: json['patient_gender'] as String?,
      patientWeight: (json['patient_weight'] as num?)?.toDouble(),
      patientHeight: (json['patient_height'] as num?)?.toDouble(),
      patientName: json['patient_name'] as String?,
      patientDateOfBirth: json['patient_date_of_birth'] as String?,
      patientPhone: json['patient_phone'] as String?,
      patientAddress: json['patient_address'] as String?,
      patientNextOfKinName: json['patient_next_of_kin_name'] as String?,
      patientNextOfKinPhone: json['patient_next_of_kin_phone'] as String?,
      patientHospitalName: json['patient_hospital_name'] as String?,
      status: (json['status'] as String?) ?? 'open',
      priority: json['priority'] as String?,
      actionsTaken: _parseActionsTaken(json['actions_taken']),
      clinicalNotes: json['clinical_notes'] as String?,
    );
  }

  // actions_taken travels as a JSON array string ("[\"a\", \"b\"]").
  static List<String> _parseActionsTaken(dynamic raw) {
    if (raw is String && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) return decoded.map((e) => e.toString()).toList();
      } catch (_) {
        // Malformed JSON — treat as no actions rather than crashing.
      }
    }
    return const [];
  }
}

class ApiClient {
  static String get baseUrl {
    if (kDebugMode) {
      return 'http://127.0.0.1:8000/api/v1';
    } else {
      return 'https://backend-fastapi-linv.onrender.com/api/v1';
    }
  }

  static http.Client httpClient = http.Client();
  static TokenStorage tokenStorage = SecureTokenStorage();

  static Future<Map<String, String>> _authHeaders({bool json = true}) async {
    final token = await tokenStorage.read();
    return {
      if (json) 'Content-Type': 'application/json',
      if (token != null) 'Authorization': "Bearer $token",
    };
  }

  static Future<Doctor> login({required String email, required String password}) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/auth/login'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {'username': email, 'password': password},
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final token = data['access_token'] as String?;
    if (token == null) {
      throw ApiException(message: 'Login response was missing an access token.');
    }
    await tokenStorage.write(token);
    return getCurrentDoctor();
  }

  /// Creates a practitioner account, then logs in with the same
  /// credentials so the user lands directly on the dashboard.
  static Future<Doctor> register({
    required String email,
    required String password,
    required String fullName,
    String? role,
    String? licenseNumber,
    String? phone,
    String? hospitalName,
    DateTime? dateOfBirth,
    String? inviteCode,
  }) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/auth/register'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode({
        'email': email,
        'password': password,
        'full_name': fullName,
        if (role != null && role.isNotEmpty) 'role': role,
        if (licenseNumber != null && licenseNumber.isNotEmpty)
          'license_number': licenseNumber,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (hospitalName != null && hospitalName.trim().isNotEmpty)
          'hospital_name': hospitalName.trim(),
        if (dateOfBirth != null)
          'date_of_birth':
              '${dateOfBirth.year.toString().padLeft(4, '0')}-'
              '${dateOfBirth.month.toString().padLeft(2, '0')}-'
              '${dateOfBirth.day.toString().padLeft(2, '0')}',
        if (inviteCode != null && inviteCode.trim().isNotEmpty)
          'invite_code': inviteCode.trim(),
      }),
    );
    if (response.statusCode != 201) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return login(email: email, password: password);
  }

  static Future<Doctor> getCurrentDoctor() async {
    final response = await httpClient.get(
      Uri.parse('$baseUrl/auth/me'),
      headers: await _authHeaders(),
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
    return Doctor.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
  }

  static Future<bool> get isLoggedIn async => (await tokenStorage.read()) != null;

  static Future<void> logout() => tokenStorage.delete();

  static Future<PatientResult> createPatient(PatientProfile profile) async {
    final response = await httpClient.post(
      Uri.parse('$baseUrl/patients/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(profile.toJson()),
    );
    if (response.statusCode == 201) {
      return PatientResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Hospital answered ${response.statusCode}: ${response.body}');
  }

  /// Practitioner-only correction of a patient's demographics — sends only
  /// the fields the caller actually set on [profile] (see
  /// PatientProfile.toJson), so an edit to just one field doesn't clobber
  /// the rest. JWT-guarded on the backend.
  static Future<void> updatePatientDemographics(String anonymousCode, PatientProfile profile) async {
    final response = await httpClient.patch(
      Uri.parse('$baseUrl/patients/$anonymousCode'),
      headers: await _authHeaders(),
      body: jsonEncode(profile.toJson()),
    );
    if (response.statusCode != 200) {
      throw ApiException.fromResponse(response.statusCode, response.body);
    }
  }

  static Future<TriageResult> sendTriage(TriageReport report) async {
    debugPrint('🚀 Sending to backend ($baseUrl): ${report.toJson()}');
    final response = await httpClient.post(
      Uri.parse('$baseUrl/triage/'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(report.toJson()),
    );
    if (response.statusCode == 201) {
      return TriageResult.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
      );
    }
    throw Exception('Hospital answered ${response.statusCode}: ${response.body}');
  }

  static Future<List<TriageResult>> getLatestVisit(String patientCode) async {
    // Anonymous lookup — no JWT; routed through httpClient anyway so
    // tests can inject a mock.
    final response = await httpClient.get(
      Uri.parse('$baseUrl/triage/patient/$patientCode'),
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list
          .map((e) => TriageResult.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Hospital answered ${response.statusCode}: ${response.body}');
  }

  /// Practitioner-only: every session the patient ever submitted, newest
  /// first. Powers the visit timeline on the clinical report.
  static Future<List<TriageResult>> getPatientHistory(String patientCode) async {
    final response = await httpClient.get(
      Uri.parse('$baseUrl/triage/patient/$patientCode/history'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      final list = jsonDecode(response.body) as List;
      return list
          .map((e) => TriageResult.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception('Hospital answered ${response.statusCode}: ${response.body}');
  }

  static Future<Map<String, dynamic>> getTriageStats() async {
    // Doctor-only endpoint — must carry the JWT.
    final response = await httpClient.get(
      Uri.parse('$baseUrl/triage/stats'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load stats: ${response.body}');
  }

  static Future<Map<String, dynamic>> getTriageReports({String period = 'all'}) async {
    // Doctor-only endpoint — must carry the JWT.
    final response = await httpClient.get(
      Uri.parse('$baseUrl/triage/reports?period=$period'),
      headers: await _authHeaders(),
    );
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw ApiException.fromResponse(response.statusCode, response.body);
  }

  static Future<List<Map<String, dynamic>>> getTriageList({
    int limit = 50,
    int offset = 0,
    String? patientCode,
    String? riskLevel,
    String? status,
  }) async {
    final uri = Uri.parse('$baseUrl/triage/list').replace(queryParameters: {
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (patientCode != null) 'patient_code': patientCode,
      if (riskLevel != null) 'risk_level': riskLevel,
      if (status != null) 'status': status,
    });
    // Doctor-only endpoint — must carry the JWT.
    final response = await httpClient.get(uri, headers: await _authHeaders());
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to load triage list: ${response.body}');
  }

  /// Practitioner review workflow: saves the decision (status, priority,
  /// ticked actions, notes) on one triage session. Doctor-only endpoint —
  /// must carry the JWT.
  static Future<TriageResult> updateTriageDecision(
    int sessionId, {
    String? status,
    String? priority,
    List<String>? actionsTaken,
    String? clinicalNotes,
  }) async {
    final response = await httpClient.patch(
      Uri.parse('$baseUrl/triage/$sessionId/decision'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (status != null) 'status': status,
        if (priority != null) 'priority': priority,
        if (actionsTaken != null) 'actions_taken': actionsTaken,
        if (clinicalNotes != null) 'clinical_notes': clinicalNotes,
      }),
    );
    if (response.statusCode == 200) {
      return TriageResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw Exception('Hospital answered ${response.statusCode}: ${response.body}');
  }

  static Future<Doctor> updateDoctorProfile({
    String? fullName,
    String? role,
    String? licenseNumber,
    String? phone,
    String? hospitalName,
    DateTime? dateOfBirth,
  }) async {
    final body = <String, dynamic>{};
    if (fullName != null) body['full_name'] = fullName.trim();
    if (role != null) body['role'] = role.trim().isEmpty ? null : role.trim();
    if (licenseNumber != null) body['license_number'] = licenseNumber.trim().isEmpty ? null : licenseNumber.trim();
    if (phone != null) body['phone'] = phone.trim().isEmpty ? null : phone.trim();
    if (hospitalName != null) body['hospital_name'] = hospitalName.trim().isEmpty ? null : hospitalName.trim();
    if (dateOfBirth != null) body['date_of_birth'] = '${dateOfBirth.year.toString().padLeft(4, '0')}-${dateOfBirth.month.toString().padLeft(2, '0')}-${dateOfBirth.day.toString().padLeft(2, '0')}';

    final response = await httpClient.patch(
      Uri.parse('$baseUrl/auth/me'),
      headers: await _authHeaders(),
      body: jsonEncode(body),
    );
    if (response.statusCode == 200) {
      return Doctor.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw ApiException.fromResponse(response.statusCode, response.body);
  }
}
