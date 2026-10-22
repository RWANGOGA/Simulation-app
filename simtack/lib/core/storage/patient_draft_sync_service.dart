import '../offline/offline_repository.dart';
import 'patient_draft.dart';
import 'patient_draft_storage.dart';

/// Finishes recording patient profiles that were saved before the device could
/// store them.
///
/// Intake used to write a profile here first and only turn it into a patient
/// once the server answered, so a crash in between left a profile with no
/// record and no code behind it. Intake now records the patient on the device
/// immediately, which makes an unsynced draft a leftover rather than a queue.
/// Committing one here is what turns it back into a real, scannable patient.
///
/// Nothing is uploaded from here: the sync outbox in
/// [OfflineRepository] carries every record to the server in one place, in
/// order, with the patient's own code.
class PatientDraftSyncService {
  /// Returns how many leftover profiles were turned into patient records.
  static Future<int> syncAll() async {
    final List<PatientDraft> drafts;
    try {
      drafts = await PatientDraftStorage.loadAll();
    } catch (_) {
      // Storage is unreadable on this platform. Nothing to recover.
      return 0;
    }

    var committed = 0;

    for (final draft in drafts) {
      if (draft.isSynced) continue;

      try {
        final result =
            await OfflineRepository.instance.createPatient(draft.profile);
        await PatientDraftStorage.save(draft.copyWith(
          patientId: result.id,
          patientCode: result.anonymousCode,
          isSynced: true,
        ));
        committed++;
      } catch (_) {
        // Never drop the profile: leave it for the next launch.
      }
    }

    return committed;
  }
}
