import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'credential_vault.dart';
import 'doctor_draft.dart';
import 'stored_json.dart';

/// Local, offline-capable storage for practitioner accounts.
/// Allows creating/logging in offline and syncing later.
///
/// The account record is kept in the app's JSON document because none of it is
/// secret. The password digest is not: it is the one string that lets someone
/// sign in without the server, so it lives in [vault] and the document records
/// only that an account exists. This used to keep both in the same unprotected
/// file, which meant anything able to read app storage could sign in offline.
class DoctorDraftStorage {
  static const _key = 'doctor_drafts';

  /// Replaceable so tests do not need a platform keystore. Production always
  /// uses [SecureCredentialVault].
  static CredentialVault vault = const SecureCredentialVault();

  static Future<void> save(DoctorDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await loadAll();

    // Remove any existing draft with same email (update) or same localId
    drafts.removeWhere((d) =>
        d.profile.email == draft.profile.email || d.localId == draft.localId);

    drafts.insert(0, draft);

    // Written before the document so a crash between the two leaves the digest
    // available rather than a record nobody can sign in to. If the keystore
    // refuses, the account is still saved and simply cannot be signed in to
    // offline until a connected sign-in replaces it — the alternative, leaving
    // the digest in the document, is the leak this exists to close.
    try {
      await vault.write(draft.profile.email, draft.passwordHash);
    } catch (_) {
      // Deliberate: see above.
    }

    await prefs.setString(_key, jsonEncode(drafts.map(_encode).toList()));
  }

  /// The stored form of a draft: everything except the digest.
  static Map<String, dynamic> _encode(DoctorDraft draft) {
    final json = draft.toJson();
    json.remove('passwordHash');
    return json;
  }

  static Future<List<DoctorDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = <DoctorDraft>[];
    var migrated = false;

    // Tolerant by design: an unreadable account list must not stop a save, and
    // the caller here is always mid-save (see stored_json.dart).
    for (final entry in decodeStoredObjects(prefs.getString(_key))) {
      try {
        var draft = DoctorDraft.fromJson(entry);
        final inline = (entry['passwordHash'] as String?) ?? '';

        if (inline.isNotEmpty) {
          // An older build kept the digest in this document. Move it out and
          // rewrite the document without it, so the leak closes on the first
          // launch after the upgrade rather than on the next sign-in.
          try {
            await vault.write(draft.profile.email, inline);
            migrated = true;
          } catch (_) {
            // Keystore unavailable: keep verifying against the value already in
            // memory for this launch and leave the document untouched.
          }
        } else {
          try {
            draft = draft.copyWith(
                passwordHash: await vault.read(draft.profile.email) ?? '');
          } catch (_) {
            // Unreadable vault: the account still loads, but with no usable
            // digest it cannot sign in offline.
          }
        }

        drafts.add(draft);
      } catch (_) {
        // Skip corrupt entries
      }
    }

    if (migrated) {
      await prefs.setString(_key, jsonEncode(drafts.map(_encode).toList()));
    }

    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return drafts;
  }

  static Future<DoctorDraft?> findByEmail(String email) async {
    final drafts = await loadAll();
    try {
      return drafts.firstWhere(
          (d) => d.profile.email.toLowerCase() == email.toLowerCase());
    } catch (_) {
      return null;
    }
  }

  static Future<DoctorDraft?> loadLatest() async {
    final drafts = await loadAll();
    return drafts.isEmpty ? null : drafts.first;
  }

  static Future<void> remove(DoctorDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await loadAll();
    drafts.removeWhere((d) => d.localId == draft.localId);
    try {
      await vault.delete(draft.profile.email);
    } catch (_) {
      // Orphaned digest, not a live credential: the account is gone either way.
    }
    await prefs.setString(_key, jsonEncode(drafts.map(_encode).toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      await vault.clear();
    } catch (_) {
      // Best effort: the records below are what the app reads.
    }
    await prefs.remove(_key);
  }
}
