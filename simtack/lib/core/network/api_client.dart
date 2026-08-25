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

  const Doctor({
    required this.id,
    required this.email,
    required this.fullName,
    required this.isActive,
  });

  factory Doctor.fromJson(Map<String, dynamic> json) => Doctor(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        isActive: json['is_active'] as bool,
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

  const PatientProfile({
    required this.age,
    required this.gender,
    required this.weight,
    required this.height,
  });

  Map<String, dynamic> toJson() => {
        'age': age,
        'gender': gender,
        'weight': weight,
        'height': height,
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
  final double? heartRate;
  final int? patientId;
  final String? visitId;

  const TriageReport({
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.direction,
    this.depth,
    this.heartRate,
    this.patientId,
    this.visitId,
  });

  Map<String, dynamic> toJson() => {
        'body_region': bodyRegion,
        'pain_type': painType,
        'severity': severity,
        if (direction != null) 'direction': direction,
        if (depth != null) 'depth': depth,
        if (heartRate != null) 'heart_rate': heartRate,
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
  final double? heartRate;
  final String? direction;
  final String? depth;
  final String? visitId;
  final double? riskScore;
  final String? shapExplanation;
  final String? qrPayloadHash;
  final String? notes;
  final String status;
  final DateTime createdAt;

  const TriageResult({
    required this.id,
    this.patientId,
    this.anonymousCode,
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.heartRate,
    this.direction,
    this.depth,
    this.visitId,
    this.riskScore,
    this.shapExplanation,
    this.qrPayloadHash,
    this.notes,
    this.status = 'Open',
    required this.createdAt,
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
      heartRate: (json['heart_rate'] as num?)?.toDouble(),
      direction: json['direction'] as String?,
      depth: json['depth'] as String?,
      visitId: json['visit_id'] as String?,
      riskScore: (json['risk_score'] as num?)?.toDouble(),
      shapExplanation: json['shap_explanation'] as String?,
      qrPayloadHash: json['qr_payload_hash'] as String?,
      notes: json['notes'] as String?,
      status: json['status'] as String? ?? 'Open',
      createdAt: DateTime.parse(json['created_at'] as String),
    );
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
    final response = await http.post(
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

  static Future<TriageResult> sendTriage(TriageReport report) async {
    debugPrint('🚀 Sending to backend ($baseUrl): ${report.toJson()}');
    final response = await http.post(
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
    final response = await http.get(
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

  static Future<Map<String, dynamic>> getTriageStats() async {
    final response = await http.get(Uri.parse('$baseUrl/triage/stats'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load stats: ${response.body}');
  }

  static Future<TriageResult> updateTriageDecision(
    int sessionId, {
    String? notes,
    String? status,
  }) async {
    final response = await httpClient.patch(
      Uri.parse('$baseUrl/triage/$sessionId/decision'),
      headers: await _authHeaders(),
      body: jsonEncode({
        if (notes != null) 'notes': notes,
        if (status != null) 'status': status,
      }),
    );
    if (response.statusCode == 200) {
      return TriageResult.fromJson(jsonDecode(response.body) as Map<String, dynamic>);
    }
    throw ApiException.fromResponse(response.statusCode, response.body);
  }

  static Future<List<Map<String, dynamic>>> getTriageList({
    int limit = 50,
    int offset = 0,
    String? patientCode,
    String? riskLevel,
  }) async {
    final uri = Uri.parse('$baseUrl/triage/list').replace(queryParameters: {
      'limit': limit.toString(),
      'offset': offset.toString(),
      if (patientCode != null) 'patient_code': patientCode,
      if (riskLevel != null) 'risk_level': riskLevel,
    });
    final response = await http.get(uri);
    if (response.statusCode == 200) {
      return List<Map<String, dynamic>>.from(jsonDecode(response.body));
    }
    throw Exception('Failed to load triage list: ${response.body}');
  }
}
