import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'stored_json.dart';
import 'triage_draft.dart';

/// Local, offline-capable storage for in-progress triage reports.
/// Patients can save several entries as drafts (e.g. before losing signal
/// or closing the app) and resume any of them later without re-entering
/// everything. Drafts are kept newest-first.
class DraftStorage {
  static const _key = 'triage_drafts';

  // The app originally stored a single draft under this key; it is
  // migrated into the list on first read so no saved work is lost.
  static const _legacyKey = 'triage_draft';

  static Future<void> save(TriageDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await loadAll();
    drafts.insert(0, draft);
    await prefs.setString(
        _key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  static Future<List<TriageDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = <TriageDraft>[];

    // Tolerant of anything under the key that is not the list this writes: a
    // read that throws would take the save path with it (see stored_json.dart).
    for (final entry in decodeStoredObjects(prefs.getString(_key))) {
      try {
        drafts.add(TriageDraft.fromJson(entry));
      } catch (_) {
        // Skip corrupt entries rather than losing the rest.
      }
    }

    // One-time migration of the old single-draft slot. decodeStoredObjects
    // accepts a bare object, which is exactly what that slot holds.
    final legacyRaw = prefs.getString(_legacyKey);
    if (legacyRaw != null) {
      for (final entry in decodeStoredObjects(legacyRaw)) {
        try {
          drafts.add(TriageDraft.fromJson(entry));
        } catch (_) {}
      }
      await prefs.remove(_legacyKey);
      await prefs.setString(
          _key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
    }

    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return drafts;
  }

  /// Convenience for callers that only care about the most recent draft.
  static Future<TriageDraft?> load() async {
    final drafts = await loadAll();
    return drafts.isEmpty ? null : drafts.first;
  }

  static Future<void> remove(TriageDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await loadAll();
    drafts.removeWhere((d) => d.savedAt == draft.savedAt);
    await prefs.setString(
        _key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  /// A submitted report supersedes every saved draft.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_legacyKey);
  }
}
