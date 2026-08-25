import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';

class ClinicalReportScreen extends StatefulWidget {
  final String patientId;

  const ClinicalReportScreen({super.key, required this.patientId});

  @override
  State<ClinicalReportScreen> createState() => _ClinicalReportScreenState();
}

class _ClinicalReportScreenState extends State<ClinicalReportScreen> {
  List<TriageResult> _reports = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    try {
      // Uses ApiClient.getLatestVisit, which already decodes the backend's
      // list response correctly (the endpoint now returns every pain point
      // from the patient's most recent visit, not just one).
      final results = await ApiClient.getLatestVisit(widget.patientId);
      setState(() {
        _reports = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = 'Connection error: $e';
        _isLoading = false;
      });
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
                : (_error != null || _reports.isEmpty)
                    ? Center(child: Text(_error ?? 'Report not found', style: const TextStyle(color: Colors.red)))
                    : _buildReport(),
          ),
        ],
      ),
    );
  }

  Widget _buildReport() {
    // Overall banner uses the highest-risk pain point from the visit —
    // a patient's clinical priority is driven by their worst finding, not
    // an average across several unrelated regions.
    final worst = _reports.reduce(
      (a, b) => (a.riskScore ?? 0.0) >= (b.riskScore ?? 0.0) ? a : b,
    );
    final score = worst.riskScore ?? 0.0;
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
          const SizedBox(height: 16),

          // Patient demographics — collected at intake and stored, now surfaced
          // here so the reading is tied to who the patient actually is.
          _buildPatientDemographics(),
          const SizedBox(height: 24),

          // Overall Risk Assessment Card (worst finding across the visit)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(color: riskColor.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: riskColor)),
            child: Row(
              children: [
                Icon(isHighRisk ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: riskColor, size: 32),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('AI RISK ASSESSMENT (HIGHEST)', style: TextStyle(fontSize: 12, color: riskColor, fontWeight: FontWeight.bold)),
                      Text('${worst.riskLevel} (${(score * 100).toInt()}%)', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: riskColor)),
                      if (_reports.length > 1)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            'Driven by: ${worst.bodyRegion}',
                            style: TextStyle(fontSize: 12, color: riskColor.withOpacity(0.8)),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),

          Text(
            _reports.length > 1 ? 'Clinical Details (${_reports.length} pain points)' : 'Clinical Details',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 16),

          // One card per pain point submitted in this visit.
          ..._reports.asMap().entries.map((entry) {
            final index = entry.key;
            final report = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_reports.length > 1) ...[
                      Text(
                        'Pain Point ${index + 1}',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                      ),
                      const SizedBox(height: 8),
                    ],
                    _buildDetailRow('Pain Location', report.bodyRegion, Icons.location_on),
                    _buildDetailRow('Pain Type', '${report.painType} (${report.severity}/10)', Icons.sick),
                    _buildDetailRow('Direction', report.direction ?? 'N/A', Icons.arrow_right_alt),
                    _buildDetailRow('Depth', report.depth ?? 'N/A', Icons.layers),
                    _buildDetailRow('Heart Rate', '${report.heartRate?.toInt() ?? 0} BPM', Icons.favorite),
                    _buildDetailRow('Risk', '${report.riskLevel} (${((report.riskScore ?? 0.0) * 100).toInt()}%)', Icons.analytics),
                    _buildDetailRow('Reported At', report.createdAt.toString().substring(0, 16), Icons.access_time),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildPatientDemographics() {
    // All pain points in a visit belong to the same patient, so the first
    // record carries the demographics for the whole report.
    final p = _reports.first;
    final hasAny = p.patientAge != null ||
        p.patientGender != null ||
        p.patientWeight != null ||
        p.patientHeight != null;
    if (!hasAny) return const SizedBox.shrink();

    final chips = <Widget>[];
    if (p.patientAge != null) {
      chips.add(_demoChip(Icons.cake_outlined, 'Age', '${p.patientAge} yrs'));
    }
    if (p.patientGender != null && p.patientGender!.isNotEmpty) {
      chips.add(_demoChip(Icons.person_outline, 'Gender', p.patientGender!));
    }
    if (p.patientWeight != null) {
      chips.add(_demoChip(Icons.monitor_weight_outlined, 'Weight', '${p.patientWeight!.toInt()} kg'));
    }
    if (p.patientHeight != null) {
      chips.add(_demoChip(Icons.height_outlined, 'Height', '${p.patientHeight!.toInt()} cm'));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'PATIENT PROFILE',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), letterSpacing: 1.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Wrap(spacing: 12, runSpacing: 12, children: chips),
        ],
      ),
    );
  }

  Widget _demoChip(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF6D28D9).withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: const Color(0xFF6D28D9), size: 18),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 10, color: Color(0xFF64748B))),
              Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF1E293B))),
            ],
          ),
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