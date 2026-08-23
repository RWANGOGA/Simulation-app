import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../core/network/api_client.dart';

class ClinicalReportScreen extends StatefulWidget {
  final String patientId;

  const ClinicalReportScreen({super.key, required this.patientId});

  @override
  State<ClinicalReportScreen> createState() => _ClinicalReportScreenState();
}

class _ClinicalReportScreenState extends State<ClinicalReportScreen> {
  TriageResult? _report;
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    try {
      final response = await http.get(
        Uri.parse('https://backend-fastapi-linv.onrender.com/api/v1/triage/patient/${widget.patientId}'),
      );
      if (response.statusCode == 200) {
        setState(() {
          _report = TriageResult.fromJson(jsonDecode(response.body));
          _isLoading = false;
        });
      } else {
        setState(() { _error = 'Report not found'; _isLoading = false; });
      }
    } catch (e) {
      setState(() { _error = 'Connection error: $e'; _isLoading = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: Stack(
        children: [
          // THE WATERMARK
          Positioned.fill(
            child: Center(
              child: Transform.rotate(
                angle: -0.3,
                child: Text(
                  'ATOMYBRIDGE CARE',
                  style: TextStyle(
                    fontSize: 60,
                    fontWeight: FontWeight.bold,
                    color: Colors.black.withOpacity(0.03),
                    letterSpacing: 10,
                  ),
                ),
              ),
            ),
          ),

          // MAIN CONTENT
          SafeArea(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? Center(child: Text(_error!, style: const TextStyle(color: Colors.red)))
                    : _buildReport(),
          ),
        ],
      ),
    );
  }

  Widget _buildReport() {
    final score = _report!.riskScore ?? 0.0;
    final isHighRisk = score >= 0.7;
    final riskColor = isHighRisk ? const Color(0xFFDC2626) : const Color(0xFF16A34A);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: const Color(0xFF6D28D9).withOpacity(0.1), shape: BoxShape.circle),
                child: const Icon(Icons.medical_services, color: Color(0xFF6D28D9), size: 32),
              ),
              const SizedBox(width: 16),
              const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Clinical Triage Report', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  Text('AtomyBridge Care • Official Document', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),

          // Patient ID Banner
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: const Color(0xFF6D28D9), borderRadius: BorderRadius.circular(12)),
            child: Column(
              children: [
                const Text('PATIENT ANONYMOUS ID', style: TextStyle(fontSize: 12, color: Colors.white70, letterSpacing: 2)),
                const SizedBox(height: 4),
                Text(widget.patientId, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.white, letterSpacing: 3)),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Risk Assessment Card
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: riskColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: riskColor)),
            child: Row(
              children: [
                Icon(isHighRisk ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: riskColor, size: 32),
                const SizedBox(width: 16),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('AI RISK ASSESSMENT', style: TextStyle(fontSize: 12, color: riskColor, fontWeight: FontWeight.bold)),
                    Text('${_report!.riskLevel} (${(score * 100).toInt()}%)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: riskColor)),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          // Clinical Details
          const Text('Clinical Details', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const SizedBox(height: 16),
          _buildDetailRow('Pain Location', _report!.bodyRegion, Icons.location_on),
          _buildDetailRow('Pain Type', '${_report!.painType} (${_report!.severity}/10)', Icons.sick),
          _buildDetailRow('Direction', _report!.direction ?? 'N/A', Icons.arrow_right_alt),
          _buildDetailRow('Depth', _report!.depth ?? 'N/A', Icons.layers),
          _buildDetailRow('Heart Rate', '${_report!.heartRate?.toInt() ?? 0} BPM', Icons.favorite),
          _buildDetailRow('Reported At', _report!.createdAt.toString().substring(0, 16), Icons.access_time),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, IconData icon) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Icon(icon, color: const Color(0xFF6D28D9), size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
              ],
            ),
          ),
        ],
      ),
    );
  }
}