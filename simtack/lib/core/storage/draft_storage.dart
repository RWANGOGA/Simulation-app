import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'triage_draft.dart';

/// Local, offline-capable storage for a single in-progress triage report.
/// A patient can save their entry as a draft (e.g. before losing signal or
/// closing the app) and resume it later without re-entering everything.
class DraftStorage {
  static const _key = 'triage_draft';

  static Future<void> save(TriageDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, jsonEncode(draft.toJson()));
  }

  static Future<TriageDraft?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_key);
    if (raw == null) return null;
    return TriageDraft.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  static Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key);
  }
}
