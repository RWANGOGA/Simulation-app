import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/draft_storage.dart';
import '../../../core/storage/triage_draft.dart';
import '../../success/ui/success_screen.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/app_card.dart';
import '../../body_map/ui/pain_point.dart';

class ReviewScreen extends StatefulWidget {
  final List<PainPoint> painPoints;
  final double heartRate;
  final double spo2;
  final int patientId;

  const ReviewScreen({
    super.key,
    required this.painPoints,
    required this.heartRate,
    required this.spo2,
    required this.patientId,
  });

  @override
  State<ReviewScreen> createState() => _ReviewScreenState();
}

class _ReviewScreenState extends State<ReviewScreen> {
  bool _isSubmitting = false;
  bool _isSavingDraft = false;

  final String _timestamp = DateTime.now().toString().substring(0, 16).replaceAll('T', ', ');

  // A patient can mark several pain points in one visit; each becomes its
  // own TriageReport row on the backend, but they're tagged with this same
  // visit_id so the QR / patient-code lookup can group them back together.
  // No `uuid` package dependency needed — timestamp + random suffix is
  // unique enough for this purpose.
  String _generateVisitId() {
    final rand = Random();
    final suffix = List.generate(6, (_) => rand.nextInt(36).toRadixString(36)).join();
    return '${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  Future<void> _submitToDoctor() async {
    HapticFeedback.heavyImpact();
    setState(() => _isSubmitting = true);

    try {
      final visitId = _generateVisitId();

      // One TriageReport per pain point (the backend's TriageSession model
      // is per-region), all sharing visitId and patientId so they're
      // recognized as one visit.
      TriageResult? lastResult;
      for (final point in widget.painPoints) {
        lastResult = await ApiClient.sendTriage(TriageReport(
          bodyRegion: point.region,
          painType: point.painType,
          severity: point.severity,
          direction: point.direction,
          depth: point.depth,
          heartRate: widget.heartRate,
          patientId: widget.patientId,
          visitId: visitId,
        ));
      }

      if (lastResult == null) {
        throw Exception('No pain points to submit.');
      }

      // A submitted report supersedes any saved draft.
      await DraftStorage.clear();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        AppPageRoute(
          builder: (_) => SuccessScreen(
            patientId: lastResult!.anonymousCode ?? 'P-UNKNOWN',
            triageResult: lastResult,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('⚠️ Error: $e'), backgroundColor: const Color(0xFFF59E0B)),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _saveDraft() async {
    HapticFeedback.lightImpact();
    setState(() => _isSavingDraft = true);

    try {
      await DraftStorage.save(TriageDraft(
        painPoints: widget.painPoints,
        heartRate: widget.heartRate,
        spo2: widget.spo2,
        patientId: widget.patientId,
        savedAt: DateTime.now(),
      ));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✅ Draft saved offline successfully!'),
          backgroundColor: Color(0xFF16A34A),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save draft: $e'), backgroundColor: const Color(0xFFF59E0B)),
      );
    } finally {
      if (mounted) setState(() => _isSavingDraft = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)), onPressed: () => Navigator.of(context).pop()),
        title: const Text('5. Review & Submit', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF6D28D9), size: 18),
            label: const Text('Edit', style: TextStyle(color: Color(0xFF6D28D9), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: Colors.white,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Anonymous Patient', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    Text('ID generated on submit', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6D28D9))),
                  ],
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Text('Timestamp', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    Text(_timestamp, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Clinical Summary', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 16),

                  ...widget.painPoints.asMap().entries.map((entry) {
                    final index = entry.key;
                    final point = entry.value;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: AppCard(
                        width: double.infinity,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Pain Point ${index + 1}',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                            ),
                            const SizedBox(height: 12),
                            _buildSummaryRow('Location', point.region, Icons.location_on),
                            const Divider(height: 24),
                            _buildSummaryRow('Pain Type', point.painType, Icons.sick),
                            const Divider(height: 24),
                            _buildSummaryRow('Intensity', '${point.severity} / 10', Icons.straighten),
                            const Divider(height: 24),
                            _buildSummaryRow('Direction', point.direction, Icons.arrow_right_alt),
                            const Divider(height: 24),
                            _buildSummaryRow('Depth', point.depth, Icons.layers),
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 8),
                  const Text('Vitals', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                  const SizedBox(height: 16),
                  AppCard(
                    width: double.infinity,
                    child: Row(
                      children: [
                        Expanded(child: _buildVitalMiniCard('Heart Rate', '${widget.heartRate.toInt()} BPM', Icons.favorite, const Color(0xFF6D28D9))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildVitalMiniCard('SpO2', '${widget.spo2.toInt()}%', Icons.air, Colors.green)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  const Text(
                    'By submitting, you consent to sharing this clinical data with the attending physician for triage purposes.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSavingDraft ? null : _saveDraft,
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        side: const BorderSide(color: Color(0xFFCBD5E1)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSavingDraft
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text('Save Draft', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    flex: 2,
                    child: ElevatedButton(
                      onPressed: _isSubmitting ? null : _submitToDoctor,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6D28D9),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        elevation: 3,
                        shadowColor: const Color(0xFF6D28D9).withOpacity(0.4),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: _isSubmitting
                        ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3))
                        : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text('Submit', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                            SizedBox(width: 8),
                            Icon(Icons.send, color: Colors.white, size: 20),
                          ]),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(String label, String value, IconData icon) {
    return Row(
      children: [
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF6D28D9).withOpacity(0.1), shape: BoxShape.circle),
          child: Icon(icon, color: const Color(0xFF6D28D9), size: 20)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
              Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildVitalMiniCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withOpacity(0.3))),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: color.withOpacity(0.8), fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}