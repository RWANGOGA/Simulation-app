import 'dart:convert';
import 'package:http/http.dart' as http;

class TriageReport {
  final String bodyRegion;
  final String painType;
  final int severity;
  final String? direction;   // NEW
  final String? depth;       // NEW
  final double? heartRate;
  final int? patientId; // TODO: wire to real patient once login exists


  const TriageReport({
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.direction,
    this.depth,
    this.heartRate,
    this.patientId, // just added
  });

  Map<String, dynamic> toJson() => {
        'body_region': bodyRegion,
        'pain_type': painType,
        'severity': severity,
        if (direction != null) 'direction': direction,
        if (depth != null) 'depth': depth,
        if (heartRate != null) 'heart_rate': heartRate,
        if (patientId != null) 'patient_id': patientId, // just added
      };
}

class TriageResult {
  final int id;
  final int? patientId; // just added
  final double riskScore;
  final String shapExplanation;
  final String? qrData; // just added
  final DateTime? createdAt; // just added

  const TriageResult({
    required this.id,
    this.patientId, // just added
    required this.riskScore,
    required this.shapExplanation,
    this.qrData, // just added
    required this.createdAt, // just added
  });

  String get riskLevel {
    if (riskScore >= 0.7) return 'HIGH RISK';
    if (riskScore >= 0.4) return 'MEDIUM RISK';
    return 'LOW RISK';
  }

  factory TriageResult.fromJson(Map<String, dynamic> json) => TriageResult(
        id: json['id'] as int,
        riskScore: (json['risk_score'] as num?)?.toDouble() ?? 0,
        shapExplanation: json['shap_explanation'] as String? ?? '[]',
        patientId: json['patient_id'] as int?, // added from here
        qrData: json['qr_data'] as String?,
        createdAt: DateTime.parse(json['created_at'] as String),
      );
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