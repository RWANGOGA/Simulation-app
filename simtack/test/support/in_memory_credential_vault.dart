import 'package:simtack/core/storage/credential_vault.dart';

/// A keystore stand-in for tests.
///
/// The real vault is platform-backed, so it is not available in a unit test at
/// all. This keeps the same contract in memory, which lets a test assert the
/// two things that matter: the digest is reachable through the vault, and it is
/// absent from the JSON document.
class InMemoryCredentialVault implements CredentialVault {
  final Map<String, String> digests = {};

  /// Makes every call fail, standing in for a keystore that is unavailable.
  bool failing = false;

  void _guard() {
    if (failing) throw StateError('keystore unavailable');
  }

  @override
  Future<String?> read(String email) async {
    _guard();
    return digests[email.toLowerCase()];
  }

  @override
  Future<void> write(String email, String digest) async {
    _guard();
    digests[email.toLowerCase()] = digest;
  }

  @override
  Future<void> delete(String email) async {
    _guard();
    digests.remove(email.toLowerCase());
  }

  @override
  Future<void> clear() async {
    _guard();
    digests.clear();
  }
}
