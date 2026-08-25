import 'dart:convert';

import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';

class ClinicalReportScreen extends StatefulWidget {
  final String patientId;
  // The decision card (status / priority / actions / notes) is for
  // practitioners only — patients viewing their own report must not see it.
  final bool practitionerMode;

  const ClinicalReportScreen({super.key, required this.patientId, this.practitionerMode = false});

  @override
  State<ClinicalReportScreen> createState() => _ClinicalReportScreenState();
}

class _ClinicalReportScreenState extends State<ClinicalReportScreen> {
  List<TriageResult> _reports = [];
  // Sessions grouped into visits (newest first). Practitioners can scrub
  // through the patient's whole history; patients only ever get their
  // latest visit from the backend.
  List<List<TriageResult>> _visits = [];
  int _selectedVisit = 0;
  bool _isLoading = true;
  String? _error;

  // ---- Practitioner decision workflow state ----
  String _decisionStatus = 'open';
  final Set<String> _checkedActions = {};
  final TextEditingController _notesController = TextEditingController();
  bool _savingDecision = false;

  List<TriageResult> get _currentVisit =>
      _visits.isEmpty ? const <TriageResult>[] : _visits[_selectedVisit];

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetchReport();
  }

  Future<void> _fetchReport() async {
    try {
      // Practitioners get the FULL history (visit timeline); patients keep
      // the unauthenticated latest-visit route.
      final results = widget.practitionerMode
          ? await ApiClient.getPatientHistory(widget.patientId)
          : await ApiClient.getLatestVisit(widget.patientId);
      setState(() {
        _reports = results;
        _visits = _groupIntoVisits(results);
        _selectedVisit = 0;
        _isLoading = false;
        // Pre-fill the decision form from whatever a practitioner saved
        // on a previous review of the selected (latest) visit.
        if (widget.practitionerMode && _currentVisit.isNotEmpty) {
          _applyDecisionFrom(_visitWorst(_currentVisit));
        }
      });
    } catch (e) {
      setState(() {
        _error = 'Connection error: $e';
        _isLoading = false;
      });
    }
  }

  /// Groups sessions into visits, preserving the backend's newest-first
  /// visit order. Rows without a visit_id (legacy submissions) each count
  /// as a visit of one.
  List<List<TriageResult>> _groupIntoVisits(List<TriageResult> sessions) {
    final grouped = <String, List<TriageResult>>{};
    final order = <String>[];
    for (final s in sessions) {
      final key = s.visitId ?? 'single-${s.id}';
      if (!grouped.containsKey(key)) {
        grouped[key] = [];
        order.add(key);
      }
      // Insert at the front so sessions inside a visit read chronologically.
      grouped[key]!.insert(0, s);
    }
    return order.map((k) => grouped[k]!).toList();
  }

  TriageResult _visitWorst(List<TriageResult> visit) => visit.reduce(
        (a, b) => (a.riskScore ?? 0.0) >= (b.riskScore ?? 0.0) ? a : b,
      );

  /// Switching visits re-points the decision form at that visit's saved
  /// outcome, so each visit is reviewed on its own terms.
  void _applyDecisionFrom(TriageResult worst) {
    _decisionStatus = worst.status;
    _notesController.text = worst.clinicalNotes ?? '';
    _checkedActions
      ..clear()
      ..addAll(worst.actionsTaken);
  }

  void _selectVisit(int index) {
    if (index == _selectedVisit) return;
    setState(() {
      _selectedVisit = index;
      if (_currentVisit.isNotEmpty) {
        _applyDecisionFrom(_visitWorst(_currentVisit));
      }
    });
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
    // Everything below reflects the SELECTED visit — practitioners scrub
    // through the timeline, patients only ever have one visit loaded.
    final visit = _currentVisit;
    // Overall banner uses the highest-risk pain point from the visit —
    // a patient's clinical priority is driven by their worst finding, not
    // an average across several unrelated regions.
    final worst = _visitWorst(visit);
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

          // Visit timeline (blueprint section 3) — practitioner-only, and
          // only meaningful once the patient has more than one visit.
          if (widget.practitionerMode && _visits.length > 1) ...[
            _buildVisitTimeline(),
            const SizedBox(height: 24),
          ],

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
                      if (visit.length > 1)
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

          // WHY this risk score: the backend stores a per-factor breakdown
          // (shap_explanation) on every session, but it was fetched and
          // then never shown. Surface it under the headline assessment.
          _buildRiskExplanation(worst),

          // Practitioner-only review workflow (blueprint section 5):
          // suggested priority, recommended actions, notes, open/closed.
          if (widget.practitionerMode) ...[
            _buildDecisionCard(worst),
            const SizedBox(height: 24),
          ],

          Text(
            visit.length > 1 ? 'Clinical Details (${visit.length} pain points)' : 'Clinical Details',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
          ),
          const SizedBox(height: 16),

          // One card per pain point submitted in this visit.
          ...visit.asMap().entries.map((entry) {
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
                    if (visit.length > 1) ...[
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
                    _buildDetailRow('SpO2 (est.)', report.spo2 != null ? '${report.spo2!.toInt()}%' : 'N/A', Icons.air),
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

  /// Renders an ISO date ("2018-03-14") as "14 Mar 2018"; falls back to
  /// the raw string if it can't be parsed.
  String _formatDob(String iso) {
    final parsed = DateTime.tryParse(iso);
    if (parsed == null) return iso;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${parsed.day} ${months[parsed.month - 1]} ${parsed.year}';
  }

  Widget _buildPatientDemographics() {
    // All pain points in a visit belong to the same patient, so the first
    // record carries the demographics for the whole report.
    final p = _reports.first;
    final hasAny = p.patientAge != null ||
        p.patientGender != null ||
        p.patientWeight != null ||
        p.patientHeight != null ||
        (p.patientName?.isNotEmpty ?? false) ||
        (p.patientDateOfBirth?.isNotEmpty ?? false) ||
        (p.patientPhone?.isNotEmpty ?? false) ||
        (p.patientAddress?.isNotEmpty ?? false) ||
        (p.patientNextOfKinName?.isNotEmpty ?? false) ||
        (p.patientHospitalName?.isNotEmpty ?? false);
    if (!hasAny) return const SizedBox.shrink();

    final chips = <Widget>[];
    if (p.patientName != null && p.patientName!.isNotEmpty) {
      chips.add(_demoChip(Icons.badge_outlined, 'Name', p.patientName!));
    }
    if (p.patientDateOfBirth != null && p.patientDateOfBirth!.isNotEmpty) {
      chips.add(_demoChip(Icons.calendar_today_outlined, 'DOB', _formatDob(p.patientDateOfBirth!)));
    }
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
    if (p.patientPhone != null && p.patientPhone!.isNotEmpty) {
      chips.add(_demoChip(Icons.phone_outlined, 'Phone', p.patientPhone!));
    }
    if (p.patientAddress != null && p.patientAddress!.isNotEmpty) {
      chips.add(_demoChip(Icons.home_outlined, 'Address', p.patientAddress!));
    }
    // Next-of-kin matters most for children/dependents — show name and
    // phone together so the practitioner can reach the guardian directly.
    if ((p.patientNextOfKinName?.isNotEmpty ?? false) ||
        (p.patientNextOfKinPhone?.isNotEmpty ?? false)) {
      final kin = [
        if (p.patientNextOfKinName != null && p.patientNextOfKinName!.isNotEmpty) p.patientNextOfKinName!,
        if (p.patientNextOfKinPhone != null && p.patientNextOfKinPhone!.isNotEmpty) p.patientNextOfKinPhone!,
      ].join(' · ');
      chips.add(_demoChip(Icons.family_restroom, 'Next of kin', kin));
    }
    if (p.patientHospitalName != null && p.patientHospitalName!.isNotEmpty) {
      chips.add(_demoChip(Icons.local_hospital_outlined, 'Hospital', p.patientHospitalName!));
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

  /// Horizontal timeline across the patient's visits (newest last in the
  /// numbering, newest first in the row). Tapping a visit re-points the
  /// whole report — risk banner, SHAP bars, decision card, pain cards.
  Widget _buildVisitTimeline() {
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
            'VISIT TIMELINE',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), letterSpacing: 1.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: _visits.length,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (context, index) => _visitCard(index),
            ),
          ),
        ],
      ),
    );
  }

  Widget _visitCard(int index) {
    final visit = _visits[index];
    final worst = _visitWorst(visit);
    final score = worst.riskScore ?? 0.0;
    final isSelected = index == _selectedVisit;
    final riskColor = score >= 0.7
        ? const Color(0xFFDC2626)
        : score >= 0.4
            ? const Color(0xFFF59E0B)
            : const Color(0xFF16A34A);
    // _visits is newest-first; label so the oldest reads as Visit 1.
    final number = _visits.length - index;
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final date = visit.first.createdAt;
    final dateLabel = '${date.day} ${months[date.month - 1]} ${date.year}';

    return GestureDetector(
      onTap: () => _selectVisit(index),
      child: Container(
        width: 148,
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6D28D9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFFE2E8F0),
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Visit $number',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.bold,
                color: isSelected ? Colors.white : const Color(0xFF1E293B),
              ),
            ),
            Text(
              dateLabel,
              style: TextStyle(
                fontSize: 11,
                color: isSelected ? Colors.white70 : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: isSelected ? Colors.white.withOpacity(0.2) : riskColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '${(score * 100).toInt()}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.white : riskColor,
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '${visit.length} pt${visit.length > 1 ? 's' : ''}',
                  style: TextStyle(
                    fontSize: 11,
                    color: isSelected ? Colors.white70 : const Color(0xFF64748B),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Renders the per-factor risk breakdown (shap_explanation) that the
  /// backend computes and stores with every triage session. The format is a
  /// JSON array of {"factor": "...", "shap": 0.xx, "impact": "+"/"-"},
  /// sorted descending. Each factor is drawn as a horizontal bar whose
  /// length is proportional to its contribution relative to the biggest
  /// factor, colored by whether it raises (+) or lowers (-) the risk.
  Widget _buildRiskExplanation(TriageResult report) {
    final raw = report.shapExplanation;
    if (raw == null || raw.isEmpty) return const SizedBox.shrink();

    List<dynamic>? factors;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List && decoded.isNotEmpty) factors = decoded;
    } catch (_) {
      // Malformed JSON shouldn't break the report — just hide the section.
    }
    if (factors == null) return const SizedBox.shrink();

    final parsed = factors.map((f) {
      final factor = f is Map<String, dynamic> ? f : <String, dynamic>{};
      final label = (factor['factor'] ?? 'Unknown factor').toString();
      final shap = factor['shap'] is num ? (factor['shap'] as num).toDouble() : 0.0;
      // Older records have no impact key — fall back to the shap sign.
      final hasImpactKey = factor.containsKey('impact');
      final impact = hasImpactKey
          ? (factor['impact'] == '-' ? '-' : '+')
          : (shap < 0 ? '-' : '+');
      return (label: label, shap: shap, impact: impact);
    }).toList();
    final maxShap = parsed.fold<double>(
      0.0,
      (m, f) => f.shap.abs() > m ? f.shap.abs() : m,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
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
            const Text(
              'WHY THIS SCORE?',
              style: TextStyle(fontSize: 12, color: Color(0xFF64748B), letterSpacing: 1.5, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            ...parsed.map((f) => _shapBar(f.label, f.shap, f.impact, maxShap)),
          ],
        ),
      ),
    );
  }

  Widget _shapBar(String label, double shap, String impact, double maxShap) {
    final raises = impact == '+';
    final magnitude = shap.abs();
    final barColor = !raises
        ? const Color(0xFF16A34A)
        : magnitude >= 0.25
            ? const Color(0xFFDC2626)
            : magnitude >= 0.10
                ? const Color(0xFFF59E0B)
                : const Color(0xFF94A3B8);
    final fraction = maxShap > 0 ? (magnitude / maxShap).clamp(0.04, 1.0) : 0.04;
    final valueLabel = '${raises ? '+' : '-'}${(magnitude * 100).toInt()}%';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(label,
                    style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B))),
              ),
              Text(
                valueLabel,
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: barColor),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(height: 8, color: const Color(0xFFF1F5F9)),
                FractionallySizedBox(
                  alignment: Alignment.centerLeft,
                  widthFactor: fraction,
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      color: barColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---- Practitioner decision workflow (blueprint section 5) ----

  String _suggestedPriority(double? score) {
    if ((score ?? 0) >= 0.7) return 'Review Immediately';
    if ((score ?? 0) >= 0.4) return 'Urgent Review (24h)';
    return 'Routine Follow-up';
  }

  List<String> _recommendedActions(double? score) {
    if ((score ?? 0) >= 0.7) {
      return ['Physical examination', 'Urgent review', 'Consider urgent labs / imaging'];
    }
    if ((score ?? 0) >= 0.4) {
      return ['Urgent review within 24h', 'Targeted physical exam'];
    }
    return ['Routine follow-up', 'Safety-net advice'];
  }

  /// Saves the same decision onto every pain point of the SELECTED visit,
  /// so that visit flips to closed together.
  Future<void> _saveDecision(TriageResult worst) async {
    setState(() => _savingDecision = true);
    try {
      for (final report in _currentVisit) {
        await ApiClient.updateTriageDecision(
          report.id,
          status: _decisionStatus,
          priority: _suggestedPriority(worst.riskScore),
          actionsTaken: _checkedActions.toList(),
          clinicalNotes: _notesController.text,
        );
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Decision saved.'), backgroundColor: Color(0xFF16A34A)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save decision: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _savingDecision = false);
    }
  }

  Widget _buildDecisionCard(TriageResult worst) {
    final score = worst.riskScore;
    final suggested = _suggestedPriority(score);
    final options = _recommendedActions(score);
    // Keep any previously saved actions that aren't in the default list.
    final allOptions = [
      ...options,
      ..._checkedActions.where((a) => !options.contains(a)),
    ];
    final priorityColor = (score ?? 0) >= 0.7
        ? const Color(0xFFDC2626)
        : (score ?? 0) >= 0.4
            ? const Color(0xFFF59E0B)
            : const Color(0xFF16A34A);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'TRIAGE DECISION',
            style: TextStyle(fontSize: 12, color: Color(0xFF64748B), letterSpacing: 1.5, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Icon(Icons.flag_outlined, size: 18, color: Color(0xFF64748B)),
              const SizedBox(width: 8),
              const Text('Suggested Priority', style: TextStyle(fontSize: 14, color: Color(0xFF1E293B))),
              const Spacer(),
              Text(suggested, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: priorityColor)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Status:', style: TextStyle(fontSize: 14, color: Color(0xFF1E293B))),
              const SizedBox(width: 8),
              for (final value in const ['open', 'closed'])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(value[0].toUpperCase() + value.substring(1)),
                    selected: _decisionStatus == value,
                    onSelected: (picked) => setState(() => _decisionStatus = value),
                    selectedColor: value == 'closed'
                        ? const Color(0xFF16A34A).withOpacity(0.2)
                        : const Color(0xFFF59E0B).withOpacity(0.2),
                    labelStyle: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Recommended Actions', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
          ...allOptions.map(
            (action) => CheckboxListTile(
              value: _checkedActions.contains(action),
              dense: true,
              contentPadding: EdgeInsets.zero,
              activeColor: const Color(0xFF6D28D9),
              title: Text(action, style: const TextStyle(fontSize: 14)),
              onChanged: (checked) {
                setState(() {
                  if (checked == true) {
                    _checkedActions.add(action);
                  } else {
                    _checkedActions.remove(action);
                  }
                });
              },
            ),
          ),
          TextField(
            controller: _notesController,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'Clinical notes...',
              filled: true,
              fillColor: const Color(0xFFF8FAFC),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              onPressed: _savingDecision ? null : () => _saveDecision(worst),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6D28D9),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: _savingDecision
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_outlined, size: 18),
              label: const Text('Save Decision', style: TextStyle(fontWeight: FontWeight.w600)),
            ),
          ),
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