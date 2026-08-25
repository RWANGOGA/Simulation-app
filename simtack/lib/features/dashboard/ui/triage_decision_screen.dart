import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_card.dart';
import 'dashboard_shared.dart';

class TriageDecisionScreen extends StatefulWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> allSessions;

  const TriageDecisionScreen({super.key, required this.session, required this.allSessions});

  @override
  State<TriageDecisionScreen> createState() => _TriageDecisionScreenState();
}

class _TriageDecisionScreenState extends State<TriageDecisionScreen> {
  late final TextEditingController _notesController;
  late String _status;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _notesController = TextEditingController(text: widget.session['notes'] as String? ?? '');
    _status = widget.session['status'] as String? ?? 'Open';
  }

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _isSaving = true);
    try {
      final updated = await ApiClient.updateTriageDecision(
        widget.session['id'] as int,
        notes: _notesController.text,
        status: _status,
      );
      // `widget.session` is the same Map instance held by the Dashboard's
      // session list, so this mutation is visible there the moment we pop
      // back — no separate reload needed.
      widget.session['notes'] = updated.notes;
      widget.session['status'] = updated.status;

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Decision saved'), backgroundColor: DashboardPalette.success),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save: $e'), backgroundColor: DashboardPalette.danger),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final score = (widget.session['risk_score'] as num?)?.toDouble();
    final level = riskLevel(score);
    final color = riskColor(level);
    final priorityLabel = switch (level) {
      'HIGH' => 'Review Immediately',
      'MEDIUM' => 'Routine Review',
      'LOW' => 'Monitor',
      _ => 'Pending Assessment',
    };
    final actions = switch (level) {
      'HIGH' => const ['Urgent clinical review', 'Escalate to attending physician', 'Consider imaging / labs'],
      'MEDIUM' => const ['Schedule follow-up', 'Monitor symptom progression'],
      'LOW' => const ['Routine monitoring', 'Patient education'],
      _ => const ['Awaiting risk assessment'],
    };

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
        title: const Text('Triage Decision', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('5. TRIAGE DECISION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DashboardPalette.primary, letterSpacing: 0.5)),
                        const SizedBox(height: 20),
                        const Text('Suggested Priority', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                        Text(riskTitleCase(level), style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
                        Text('($priorityLabel)', style: TextStyle(fontSize: 13, color: color)),
                        const SizedBox(height: 20),
                        const Text('Recommended Actions', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        const SizedBox(height: 8),
                        ...actions.map((a) => Padding(
                              padding: const EdgeInsets.symmetric(vertical: 3),
                              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                const Padding(padding: EdgeInsets.only(top: 6), child: Icon(Icons.circle, size: 6, color: Color(0xFF94A3B8))),
                                const SizedBox(width: 8),
                                Expanded(child: Text(a, style: const TextStyle(fontSize: 13.5, color: Color(0xFF475569)))),
                              ]),
                            )),
                        const SizedBox(height: 20),
                        const Text('Status', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        const SizedBox(height: 8),
                        Row(children: [
                          _statusChip('Open'),
                          const SizedBox(width: 10),
                          _statusChip('Closed'),
                        ]),
                        const SizedBox(height: 20),
                        const Text('Notes', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        const SizedBox(height: 8),
                        TextField(
                          controller: _notesController,
                          maxLines: 4,
                          style: const TextStyle(fontSize: 13.5),
                          decoration: InputDecoration(
                            hintText: 'Enter notes...',
                            hintStyle: const TextStyle(fontSize: 13.5, color: Color(0xFFB0B8C4)),
                            contentPadding: const EdgeInsets.all(12),
                            filled: true,
                            fillColor: const Color(0xFFF8FAFC),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _isSaving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: DashboardPalette.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: _isSaving
                          ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusChip(String value) {
    final active = _status == value;
    final color = value == 'Open' ? DashboardPalette.secondary : DashboardPalette.neutral;
    return GestureDetector(
      onTap: () => setState(() => _status = value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? color.withValues(alpha: 0.12) : Colors.transparent,
          border: Border.all(color: active ? color : const Color(0xFFE2E8F0)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(value, style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: active ? color : const Color(0xFF94A3B8))),
      ),
    );
  }
}
