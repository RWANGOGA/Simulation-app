import 'dart:math';
import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import 'package:flutter/services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/storage/draft_storage.dart';
import '../../../core/storage/triage_draft.dart';
import '../../success/ui/success_screen.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/app_card.dart';
import '../../body_map/ui/pain_point.dart';
import '../../../l10n/app_localizations.dart';

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

    // Declared outside the try so the catch block below can tell how many
    // pain points already made it to the backend before a failure — only
    // the remainder should ever be saved/retried, or a retry would
    // resubmit points that already succeeded as duplicates.
    final results = <TriageResult>[];

    try {
      final visitId = _generateVisitId();

      // One TriageReport per pain point (the backend's TriageSession model
      // is per-region), all sharing visitId and patientId so they're
      // recognized as one visit. Each point is scored aware of whatever
      // other regions were already submitted earlier in this same loop
      // (see triage_service.compute_risk's sibling_regions), so collecting
      // every result — not just the last one — is what lets the patient
      // see the full picture, including any connectivity findings.
      for (final point in widget.painPoints) {
        results.add(await ApiClient.sendTriage(TriageReport(
          bodyRegion: point.region,
          painType: point.painType,
          severity: point.severity,
          direction: point.direction,
          depth: point.depth,
          heartRate: widget.heartRate,
          spo2: widget.spo2,
          patientId: widget.patientId,
          visitId: visitId,
        )));
      }

      if (results.isEmpty) {
        throw Exception('No pain points to submit.');
      }

      // A submitted report supersedes any saved draft.
      await DraftStorage.clear();

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        AppPageRoute(
          builder: (_) => SuccessScreen(
            patientId: results.first.anonymousCode ?? 'P-UNKNOWN',
            allResults: results,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // Save automatically on failure (most commonly no connection) —
      // DraftSyncService retries this the next time the app opens.
      try {
        // Only the pain points NOT already in `results` — everything up
        // to `results.length` already made it to the backend.
        final remaining = widget.painPoints.skip(results.length).toList();
        if (remaining.isNotEmpty) {
          await DraftStorage.save(TriageDraft(
            painPoints: remaining,
            heartRate: widget.heartRate,
            spo2: widget.spo2,
            patientId: widget.patientId,
            savedAt: DateTime.now(),
          ));
        }
      } catch (_) {
        // If even the local save fails, fall through to the plain error
        // below rather than hiding the original submit failure.
      }
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(AppLocalizations.of(context)!.submitFailedSavedOfflineSnackbar('$e')),
          backgroundColor: const Color(0xFFF59E0B),
          duration: const Duration(seconds: 5),
        ),
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
        SnackBar(
          content: Text(AppLocalizations.of(context)!.draftSavedSnackbar),
          backgroundColor: const Color(0xFF16A34A),
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
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)), onPressed: () => Navigator.of(context).pop()),
        title: Text(t.reviewSubmitTitle, style: TextStyle(color: AppPalette.textPrimary(context), fontWeight: FontWeight.bold, fontSize: 18)),
        centerTitle: true,
        actions: [
          TextButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.edit_outlined, color: Color(0xFF6D28D9), size: 18),
            label: Text(t.editButton, style: const TextStyle(color: Color(0xFF6D28D9), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            color: AppPalette.surface(context),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.anonymousPatientLabel, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
                    Text(t.idGeneratedOnSubmitLabel, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6D28D9))),
                  ],
                ),
                Column(crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(t.timestampLabel, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context))),
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
                  Text(t.clinicalSummaryTitle, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
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
                              t.painPointNumberLabel(index + 1),
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                            ),
                            const SizedBox(height: 12),
                            _buildSummaryRow(t.locationLabel, point.region, Icons.location_on),
                            const Divider(height: 24),
                            _buildSummaryRow(t.painTypeLabel, point.painType, Icons.sick),
                            const Divider(height: 24),
                            _buildSummaryRow(t.intensityLabel, '${point.severity} / 10', Icons.straighten),
                            const Divider(height: 24),
                            _buildSummaryRow(t.directionLabel, point.direction, Icons.arrow_right_alt),
                            const Divider(height: 24),
                            _buildSummaryRow(t.depthLabel, point.depth, Icons.layers),
                          ],
                        ),
                      ),
                    );
                  }),

                  const SizedBox(height: 8),
                  Text(t.vitalsTitle, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                  const SizedBox(height: 16),
                  AppCard(
                    width: double.infinity,
                    child: Row(
                      children: [
                        Expanded(child: _buildVitalMiniCard(t.heartRateLabel, '${widget.heartRate.toInt()} BPM', Icons.favorite, const Color(0xFF6D28D9))),
                        const SizedBox(width: 12),
                        Expanded(child: _buildVitalMiniCard(t.spo2EstLabel, '${widget.spo2.toInt()}%', Icons.air, Colors.green)),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),
                  Text(
                    t.consentSubmitNotice,
                    style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context), fontStyle: FontStyle.italic),
                  ),
                ],
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.all(20),
            color: AppPalette.surface(context),
            child: SafeArea(
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _isSavingDraft ? null : _saveDraft,
                      child: _isSavingDraft
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : Text(t.saveDraftButton),
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
                        : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Text(t.submitButton, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(width: 8),
                            const Icon(Icons.send, color: Colors.white, size: 20),
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
              Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context), fontWeight: FontWeight.w500)),
              Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
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