import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
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
    await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  static Future<List<TriageDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = <TriageDraft>[];

    final raw = prefs.getString(_key);
    if (raw != null) {
      for (final entry in (jsonDecode(raw) as List)) {
        try {
          drafts.add(TriageDraft.fromJson(entry as Map<String, dynamic>));
        } catch (_) {
          // Skip corrupt entries rather than losing the rest.
        }
      }
    }

    // One-time migration of the old single-draft slot.
    final legacyRaw = prefs.getString(_legacyKey);
    if (legacyRaw != null) {
      try {
        drafts.add(TriageDraft.fromJson(jsonDecode(legacyRaw) as Map<String, dynamic>));
      } catch (_) {}
      await prefs.remove(_legacyKey);
      await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
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
    await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  /// A submitted report supersedes every saved draft.
  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
    await prefs.remove(_legacyKey);
  }
}
