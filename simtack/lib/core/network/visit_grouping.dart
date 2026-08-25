import 'api_client.dart';

/// Groups a flat list of [TriageResult]s (newest-first from the backend)
/// into visits, preserving newest-visit-first order.
///
/// Sessions that share a [TriageResult.visitId] belong to the same visit.
/// Legacy submissions that have no visitId each form a visit of one so
/// nothing is lost.  Sessions inside a visit are reordered chronologically
/// (oldest first) so they read in the order the patient submitted them.
///
/// Extracted from ClinicalReportScreen so it can be shared by
/// PatientOverviewPane without duplicating code.
List<List<TriageResult>> groupIntoVisits(List<TriageResult> sessions) {
  final grouped = <String, List<TriageResult>>{};
  final order = <String>[];
  for (final s in sessions) {
    final key = s.visitId ?? 'single-${s.id}';
    if (!grouped.containsKey(key)) {
      grouped[key] = [];
      order.add(key);
    }
    // Insert at front → sessions inside a visit read chronologically.
    grouped[key]!.insert(0, s);
  }
  return order.map((k) => grouped[k]!).toList();
}

/// Returns the highest-risk [TriageResult] from a single visit list.
TriageResult visitWorst(List<TriageResult> visit) => visit.reduce(
      (a, b) => (a.riskScore ?? 0.0) >= (b.riskScore ?? 0.0) ? a : b,
    );

/// Maps a risk score to one of the three clinical colour codes used
/// throughout the app.  Centralised here so both panes stay consistent.
///
///  >= 0.7  → red    0xFFDC2626
///  >= 0.4  → amber  0xFFF59E0B
///  < 0.4   → green  0xFF16A34A
int riskColorValue(double? score) {
  final s = score ?? 0.0;
  if (s >= 0.7) return 0xFFDC2626;
  if (s >= 0.4) return 0xFFF59E0B;
  return 0xFF16A34A;
}

/// Short risk label: "HIGH" / "MEDIUM" / "LOW".
String riskLabel(double? score) {
  final s = score ?? 0.0;
  if (s >= 0.7) return 'HIGH';
  if (s >= 0.4) return 'MEDIUM';
  return 'LOW';
}
