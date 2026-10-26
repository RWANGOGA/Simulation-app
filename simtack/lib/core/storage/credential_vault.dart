import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Where the password digest of a cached practitioner account is kept.
///
/// The account record (name, role, hospital, when the server last confirmed it)
/// is not a secret and lives in the app's JSON document alongside everything
/// else. The digest is the one string that grants access, so it is kept apart,
/// behind the platform keystore, and the document never holds it.
abstract class CredentialVault {
  Future<String?> read(String email);
  Future<void> write(String email, String digest);
  Future<void> delete(String email);
  Future<void> clear();
}

/// Keystore-backed vault: Android Keystore, iOS and macOS Keychain.
///
/// Web has no keystore, and `flutter_secure_storage` degrades to the browser's
/// own storage there. That is stated rather than hidden: on web the digest is
/// only as protected as the profile directory, and what remains is the PBKDF2
/// cost plus the seven-day trust window. The practitioner console says which of
/// these a session rests on, which is why the distinction has to be real.
///
/// Failures are raised, never swallowed: the caller drops the credential and
/// asks for a connected sign-in rather than writing the digest somewhere
/// unprotected.
class SecureCredentialVault implements CredentialVault {
  const SecureCredentialVault();

  static const _storage = FlutterSecureStorage(aOptions: AndroidOptions());
  static const _prefix = 'doctor_credential.';

  static String _key(String email) => '$_prefix${email.toLowerCase()}';

  @override
  Future<String?> read(String email) => _storage.read(key: _key(email));

  @override
  Future<void> write(String email, String digest) =>
      _storage.write(key: _key(email), value: digest);

  @override
  Future<void> delete(String email) => _storage.delete(key: _key(email));

  @override
  Future<void> clear() async {
    // Only the account digests: session tokens share this store, and signing an
    // account out of the device must not sign the practitioner out of the app.
    final entries = await _storage.readAll();
    for (final key in entries.keys) {
      if (key.startsWith(_prefix)) await _storage.delete(key: key);
    }
  }
}
