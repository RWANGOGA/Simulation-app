import 'dart:convert';

import 'package:flutter/services.dart';

/// Offline port of `app/services/organ_lookup.py`: the body map's tap-to-organ
/// lookup, which replaced retrieval. The tap already says which part was
/// touched, so this is a dictionary lookup over three bundled files:
///
///   organ_reports.json   report name -> description, functions, sub-parts,
///                        disorders (from the textbook dataset)
///   part_to_organ.json   tap name -> {system, candidates}, most specific first
///   anatomy_kb.json      per-region red flags, questions, common conditions
///
/// [lookup] returns exactly the JSON `GET /anatomy/part/{name}` does, so both
/// paths feed [AnatomyInsight.fromOrganJson].
class OrganLookup {
  OrganLookup._(this._reports, this._parts, this._regions);

  final Map<String, Map<String, dynamic>> _reports;
  final Map<String, Map<String, dynamic>> _parts;
  final Map<String, Map<String, dynamic>> _regions;

  static const String comingSoon =
      'Detailed information for this part is coming soon.';

  /// Where the body map's answer comes from, chosen at build time with
  /// `--dart-define=ANATOMY_SOURCE=...`:
  ///
  ///   both   (default) the organ report, with retrieval filling in only what
  ///          the report does not already say - see [AnatomyInsight.combine]
  ///   organ  the organ report alone
  ///   rag    the retrieval answer alone, as before organ reports existed
  ///
  /// `--dart-define=USE_RAG=true` still means `rag`.
  static const String source = bool.fromEnvironment('USE_RAG')
      ? 'rag'
      : String.fromEnvironment('ANATOMY_SOURCE', defaultValue: 'both');

  static bool get useRag => source == 'rag';

  static OrganLookup? _instance;
  static Future<OrganLookup>? _loading;

  /// Loads once; later calls share the same instance. [bundle] and [prefix]
  /// let tests read the files from disk, as [ClinicalData.load] does.
  static Future<OrganLookup> load({
    AssetBundle? bundle,
    String prefix = 'assets/clinical',
  }) {
    final cached = _instance;
    if (cached != null) return Future.value(cached);
    return _loading ??= _read(bundle ?? rootBundle, prefix).then((value) {
      _instance = value;
      return value;
    }).whenComplete(() => _loading = null);
  }

  static Future<OrganLookup> _read(AssetBundle source, String prefix) async {
    Map<String, Map<String, dynamic>> objects(Object? json) => {
          for (final e in (json as Map<String, dynamic>).entries)
            e.key: e.value as Map<String, dynamic>,
        };
    final reports =
        objects(jsonDecode(await source.loadString('$prefix/organ_reports.json')));
    final parts =
        objects(jsonDecode(await source.loadString('$prefix/part_to_organ.json')));
    final kb = jsonDecode(await source.loadString('$prefix/anatomy_kb.json'))
        as Map<String, dynamic>;
    final regions = {
      for (final r in (kb['regions'] as List).whereType<Map<String, dynamic>>())
        (r['region'] as String).toLowerCase(): r,
    };
    return OrganLookup._(reports, parts, regions);
  }

  /// Test hook: drops the cached instance so a test can reload from elsewhere.
  static void resetForTest() {
    _instance = null;
    _loading = null;
  }

  static String _key(String? name) =>
      (name ?? '').trim().split(RegExp(r'\s+')).join(' ').toLowerCase();

  /// Whether [name] is a tap name or report name this data can answer.
  bool knows(String? name) {
    final key = _key(name);
    return _parts.containsKey(key) ||
        _reports.containsKey(key.replaceAll(' ', '_'));
  }

  /// The fixed safety text for a body-map region, or null if it is not one.
  Map<String, dynamic>? regionInfo(String? region) {
    final entry = _regions[_key(region)];
    if (entry == null) return null;
    List<String> list(String field) =>
        ((entry[field] as List?) ?? const []).whereType<String>().toList();
    return {
      'region': entry['region'],
      'red_flags': list('red_flags'),
      'suggested_questions': list('suggested_questions'),
      'common_conditions': list('common_conditions'),
    };
  }

  /// Information for a tap name or a report name; null if the name is unknown.
  ///
  /// [region] is the body-map region the tap resolved to. It only adds that
  /// region's safety text; when [name] is itself a region it is used for that.
  Map<String, dynamic>? lookup(String name, {String? region}) {
    final key = _key(name);
    final extra = regionInfo(region) ?? regionInfo(key);

    final reportKey = key.replaceAll(' ', '_');
    final direct = _reports[reportKey];
    if (direct != null) {
      return {
        'part': key,
        'system': direct['system'],
        'about': reportKey,
        'match': 'report',
        'report': direct,
        'related': const <String>[],
        'region': extra,
      };
    }

    final entry = _parts[key];
    if (entry == null) return null;
    final found = ((entry['candidates'] as List?) ?? const [])
        .whereType<String>()
        .where(_reports.containsKey)
        .toList();
    if (found.isNotEmpty) {
      return {
        'part': key,
        'system': entry['system'],
        'about': found.first,
        'match': 'report',
        'report': _reports[found.first],
        'related': found.sublist(1),
        'region': extra,
      };
    }
    return {
      'part': key,
      'system': entry['system'],
      'about': null,
      'match': 'system',
      'report': null,
      'related': const <String>[],
      'region': extra,
      'message': comingSoon,
    };
  }
}
