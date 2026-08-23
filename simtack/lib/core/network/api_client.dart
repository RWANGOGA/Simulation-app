import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

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

  const TriageReport({
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.direction,
    this.depth,
    this.heartRate,
    this.patientId,
  });

  Map<String, dynamic> toJson() => {
        'body_region': bodyRegion,
        'pain_type': painType,
        'severity': severity,
        if (direction != null) 'direction': direction,
        if (depth != null) 'depth': depth,
        if (heartRate != null) 'heart_rate': heartRate,
        if (patientId != null) 'patient_id': patientId,
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
  final double? riskScore;
  final String? shapExplanation;
  final String? qrPayloadHash;
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
    this.riskScore,
    this.shapExplanation,
    this.qrPayloadHash,
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
      riskScore: (json['risk_score'] as num?)?.toDouble(),
      shapExplanation: json['shap_explanation'] as String?,
      qrPayloadHash: json['qr_payload_hash'] as String?,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}

class ApiClient {
  // 🌟 SMART URL SWITCHING:
  // - Local development (flutter run): uses localhost for fast, reliable testing.
  // - Production build (GitHub Pages release): uses the live Render backend.
  static String get baseUrl {
    if (kDebugMode) {
      return 'http://127.0.0.1:8000/api/v1'; // Local backend
    } else {
      return 'https://backend-fastapi-linv.onrender.com/api/v1'; // Production backend
    }
  }

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

  // --- METHODS FOR PRACTITIONER DASHBOARD ---

  static Future<Map<String, dynamic>> getTriageStats() async {
    final response = await http.get(Uri.parse('$baseUrl/triage/stats'));
    if (response.statusCode == 200) {
      return jsonDecode(response.body) as Map<String, dynamic>;
    }
    throw Exception('Failed to load stats: ${response.body}');
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