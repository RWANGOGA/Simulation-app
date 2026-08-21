import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/draft_storage.dart';
import '../../../core/storage/triage_draft.dart';
import '../../success/ui/success_screen.dart'; // Import the new Screen 6

class ReviewScreen extends StatefulWidget {
  final String region;
  final String painType;
  final int severity;
  final String direction;
  final String depth;
  final double heartRate;
  final double spo2;
  final int patientId;

  const ReviewScreen({
    super.key,
    required this.region,
    required this.painType,
    required this.severity,
    required this.direction,
    required this.depth,
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

  Future<void> _submitToDoctor() async {
    HapticFeedback.heavyImpact();
    setState(() => _isSubmitting = true);

    try {
      final result = await ApiClient.sendTriage(TriageReport(
        bodyRegion: widget.region,
        painType: widget.painType.toLowerCase(),
        severity: widget.severity,
        direction: widget.direction,
        depth: widget.depth,
        heartRate: widget.heartRate,
        patientId: widget.patientId,
      ));

      // A submitted report supersedes any saved draft.
      await DraftStorage.clear();

      if (!mounted) return;

      // Navigate to Screen 6 with the REAL backend-generated 12-char ID
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (_) => SuccessScreen(
            patientId: result.anonymousCode ?? 'P-UNKNOWN',
            triageResult: result,
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
        region: widget.region,
        painType: widget.painType,
        severity: widget.severity,
        direction: widget.direction,
        depth: widget.depth,
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
          // HEADER: Honestly states that ID is generated on submit
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
                  
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white, borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildSummaryRow('Location', widget.region, Icons.location_on),
                        const Divider(height: 24),
                        _buildSummaryRow('Pain Type', widget.painType, Icons.sick),
                        const Divider(height: 24),
                        _buildSummaryRow('Intensity', '${widget.severity} / 10', Icons.straighten),
                        const Divider(height: 24),
                        _buildSummaryRow('Direction', widget.direction, Icons.arrow_right_alt),
                        const Divider(height: 24),
                        _buildSummaryRow('Depth', widget.depth, Icons.layers),
                        const Divider(height: 24),
                        Row(
                          children: [
                            Expanded(child: _buildVitalMiniCard('Heart Rate', '${widget.heartRate.toInt()} BPM', Icons.favorite, const Color(0xFF6D28D9))),
                            const SizedBox(width: 12),
                            Expanded(child: _buildVitalMiniCard('SpO2', '${widget.spo2.toInt()}%', Icons.air, Colors.green)),
                          ],
                        ),
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
                        shadowColor: const Color(0xFF6D28D9).withValues(alpha: 0.4),
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
        Container(padding: const EdgeInsets.all(8), decoration: BoxDecoration(color: const Color(0xFF6D28D9).withValues(alpha: 0.1), shape: BoxShape.circle),
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
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: color.withValues(alpha: 0.3))),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8), fontWeight: FontWeight.w600)),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }
}