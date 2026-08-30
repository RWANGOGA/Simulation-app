import 'dart:math';
import '../network/api_client.dart';
import 'draft_storage.dart';

/// Silently resubmits any drafts saved while offline (or after a failed
/// submission — see ReviewScreen._submitToDoctor's fallback save). Each
/// draft becomes its own visit, same multi-pain-point grouping the manual
/// Review & Submit flow uses. A draft that still fails (no connection, or
/// a real server error) is left in place so the next sync attempt —
/// currently triggered on app startup — can retry it.
class DraftSyncService {
  static String _generateVisitId() {
    final rand = Random();
    final suffix = List.generate(6, (_) => rand.nextInt(36).toRadixString(36)).join();
    return '${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  /// Returns how many drafts were successfully submitted and removed.
  static Future<int> syncAll() async {
    final drafts = await DraftStorage.loadAll();
    int synced = 0;

    for (final draft in drafts) {
      if (draft.painPoints.isEmpty) continue;
      try {
        final visitId = _generateVisitId();
        for (final point in draft.painPoints) {
          await ApiClient.sendTriage(TriageReport(
            bodyRegion: point.region,
            painType: point.painType,
            severity: point.severity,
            direction: point.direction,
            depth: point.depth,
            patientId: draft.patientId,
            visitId: visitId,
          ));
        }
        await DraftStorage.remove(draft);
        synced++;
      } catch (_) {
        // Still offline, or a real failure — leave this draft for the
        // next sync attempt rather than losing it.
      }
    }

    return synced;
  }
}
