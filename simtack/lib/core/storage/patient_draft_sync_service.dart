import '../network/api_client.dart';
import 'patient_draft_storage.dart';

/// Syncs locally-stored patient profiles to the backend when online.
/// Runs on startup and when connectivity is restored.
class PatientDraftSyncService {
  /// Returns how many patient drafts were successfully synced.
  static Future<int> syncAll() async {
    final drafts = await PatientDraftStorage.loadAll();
    int synced = 0;

    for (final draft in drafts) {
      // Skip if already synced
      if (draft.isSynced) continue;

      try {
        final result = await ApiClient.createPatient(draft.profile);

        // Update draft with server response
        final syncedDraft = draft.copyWith(
          patientId: result.id,
          patientCode: result.anonymousCode,
          isSynced: true,
        );

        await PatientDraftStorage.save(syncedDraft);
        synced++;
      } catch (_) {
        // Still offline, or a real failure — leave for next sync attempt
      }
    }

    return synced;
  }
}