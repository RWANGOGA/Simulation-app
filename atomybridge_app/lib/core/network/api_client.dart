import 'dart:convert';
import 'package:http/http.dart' as http;

class TriageReport {
  final String bodyRegion;
  final String painType;
  final int severity;
  final String? direction;
  final String? depth;
  final double? heartRate;

  const TriageReport({
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.direction,
    this.depth,
    this.heartRate,
  });

  Map<String, dynamic> toJson() => {
        'body_region': bodyRegion,
        'pain_type': painType,
        'severity': severity,
        if (direction != null) 'direction': direction,
        if (depth != null) 'depth': depth,
        if (heartRate != null) 'heart_rate': heartRate,
      };
}

class TriageResult {
  final int id;
  final int? patientId;
  final String? anonymousCode; // <-- NEW: The 12-char Base36 ID from backend
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
      anonymousCode: json['anonymous_code'] as String?, // <-- NEW: Map the backend field
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
  // Use 127.0.0.1 instead of localhost for Chrome Web
  static const String baseUrl = 'http://127.0.0.1:8000/api/v1';

  static Future<TriageResult> sendTriage(TriageReport report) async {
    print('🚀 Sending to backend: ${report.toJson()}'); // Debug log
    
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
}