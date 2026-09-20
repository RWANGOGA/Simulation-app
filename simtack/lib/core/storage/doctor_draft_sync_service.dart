import '../network/api_client.dart';
import 'doctor_draft_storage.dart';
import 'doctor_draft.dart';

/// Syncs locally-stored practitioner accounts to the backend when online.
/// Runs on startup and when connectivity is restored.
class DoctorDraftSyncService {
  /// Returns how many doctor drafts were successfully synced.
  static Future<int> syncAll() async {
    final drafts = await DoctorDraftStorage.loadAll();
    int synced = 0;

    for (final draft in drafts) {
      // Skip if already synced
      if (draft.isSynced) continue;

      try {
        // Try to register the account on the server
        final doctor = await ApiClient.register(
          email: draft.profile.email,
          password: 'synced_offline', // Placeholder - actual password not stored
          fullName: draft.profile.fullName,
          role: draft.profile.role,
          licenseNumber: draft.profile.licenseNumber,
          phone: draft.profile.phone,
          hospitalName: draft.profile.hospitalName,
        );

        // Update draft with server response
        final syncedDraft = draft.copyWith(
          doctorId: doctor.id,
          isSynced: true,
        );

        await DoctorDraftStorage.save(syncedDraft);
        synced++;
      } catch (e) {
        // If email already exists, try to login instead
        if (e.toString().toLowerCase().contains('email') ||
            e.toString().toLowerCase().contains('exists') ||
            e.toString().toLowerCase().contains('duplicate')) {
          try {
            // Try login to verify credentials
            final doctor = await ApiClient.login(
              email: draft.profile.email,
              password: '', // We don't have the actual password
            );
            // If login succeeds, mark as synced
            final syncedDraft = draft.copyWith(
              doctorId: doctor.id,
              isSynced: true,
            );
            await DoctorDraftStorage.save(syncedDraft);
            synced++;
          } catch (_) {
            // Can't verify, leave for next sync
          }
        }
        // Other errors - leave for next sync attempt
      }
    }

    return synced;
  }
}