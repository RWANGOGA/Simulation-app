import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'doctor_draft.dart';

/// Local, offline-capable storage for practitioner accounts.
/// Allows creating/logging in offline and syncing later.
class DoctorDraftStorage {
  static const _key = 'doctor_drafts';

  static Future<void> save(DoctorDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await loadAll();

    // Remove any existing draft with same email (update) or same localId
    drafts.removeWhere((d) =>
        d.profile.email == draft.profile.email || d.localId == draft.localId);

    drafts.insert(0, draft);
    await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  static Future<List<DoctorDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = <DoctorDraft>[];

    final raw = prefs.getString(_key);
    if (raw != null) {
      for (final entry in (jsonDecode(raw) as List)) {
        try {
          drafts.add(DoctorDraft.fromJson(entry as Map<String, dynamic>));
        } catch (_) {
          // Skip corrupt entries
        }
      }
    }

    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return drafts;
  }

  static Future<DoctorDraft?> findByEmail(String email) async {
    final drafts = await loadAll();
    try {
      return drafts.firstWhere((d) => d.profile.email.toLowerCase() == email.toLowerCase());
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
    await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}