/// Completion point for practitioner accounts that were created offline.
///
/// This used to POST `/auth/register` with `password: 'synced_offline'`, because
/// the plaintext was never kept — only a PBKDF2 hash of it. That is the worst of
/// both worlds: the server got an account nobody could sign in to (the real
/// password is unrecoverable, so the practitioner is locked out online for
/// good), and everybody else got one protected by a password that is written
/// down in this repository. Approval-gating new accounts limited the damage but
/// did not remove the credential.
///
/// So the device no longer invents accounts. Doing this properly needs the
/// plaintext retained from the moment of registration (secure storage, not
/// shared preferences) until the account reaches the server, or it needs the
/// practitioner to register again while connected. Neither is implemented, and
/// nothing in the UI creates an offline practitioner account today — the
/// registration screen calls the API directly and reports the connection error
/// — so there is nothing to sync yet.
class DoctorDraftSyncService {
  /// Returns how many doctor drafts were successfully synced. Always 0 until a
  /// correct implementation exists; kept so callers do not need to change.
  static Future<int> syncAll() async => 0;
}
