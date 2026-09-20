import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'patient_draft.dart';

/// Local, offline-capable storage for patient profiles.
/// Allows creating patient profiles offline and syncing later.
class PatientDraftStorage {
  static const _key = 'patient_drafts';

  static Future<void> save(PatientDraft draft) async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = await loadAll();
    
    // Remove any existing draft with same localId (update) or patientCode
    drafts.removeWhere((d) => d.localId == draft.localId || 
        (d.patientCode != null && draft.patientCode != null && d.patientCode == draft.patientCode));
    
    drafts.insert(0, draft);
    await prefs.setString(_key, jsonEncode(drafts.map((d) => d.toJson()).toList()));
  }

  static Future<List<PatientDraft>> loadAll() async {
    final prefs = await SharedPreferences.getInstance();
    final drafts = <PatientDraft>[];

    final raw = prefs.getString(_key);
    if (raw != null) {
      for (final entry in (jsonDecode(raw) as List)) {
        try {
          drafts.add(PatientDraft.fromJson(entry as Map<String, dynamic>));
        } catch (_) {
          // Skip corrupt entries
        }
      }
    }

    drafts.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return drafts;
  }

  static Future<PatientDraft?> loadLatest() async {
    final drafts = await loadAll();
    return drafts.isEmpty ? null : drafts.first;
  }

  static Future<void> remove(PatientDraft draft) async {
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