import 'dart:convert';

import 'package:flutter/services.dart' show AssetBundle, rootBundle;

/// The clinical brain of the app, loaded from assets instead of from a server.
///
/// Everything here is generated from the Python services by
/// `Backend-fastapi/scripts/export_offline_assets.py`:
///
/// * `risk_rules.json` — the weight tables and escalation constants that
///   `triage_service` uses.
/// * `body_graph.json` — the anatomical connections and their concern levels.
/// * `anatomy_kb.json` — a byte-identical copy of the backend knowledge base.
///
/// The point of generating rather than hand-copying is that the app can score a
/// report with no network and still agree with the server. A transcription slip
/// in either engine fails `test/clinical_parity_test.dart`, which replays
/// hundreds of cases recorded from the Python implementation.
class ClinicalData {
  ClinicalData._({
    required this.rules,
    required this.graph,
    required this.chunks,
  });

  final RiskRules rules;
  final Map<String, List<BodyConnection>> graph;
  final Map<String, AnatomyChunk> chunks;

  static ClinicalData? _instance;

  /// The loaded instance. Throws if [load] has not run — a silent empty rule
  /// set would score every patient as low risk, which is far worse than an
  /// obvious crash on the first screen.
  static ClinicalData get instance {
    final data = _instance;
    if (data == null) {
      throw StateError(
        'ClinicalData.load() must be awaited before scoring. '
        'It is called from main() and from the test setup.',
      );
    }
    return data;
  }

  static bool get isLoaded => _instance != null;

  /// Loads and caches the asset bundle. [bundle] and [prefix] exist so tests
  /// can read the same files from disk without relying on the test runner's
  /// asset manifest.
  static Future<ClinicalData> load({
    AssetBundle? bundle,
    String prefix = 'assets/clinical',
  }) async {
    final source = bundle ?? rootBundle;

    final rulesJson =
        jsonDecode(await source.loadString('$prefix/risk_rules.json'))
            as Map<String, dynamic>;
    final graphJson =
        jsonDecode(await source.loadString('$prefix/body_graph.json'))
            as Map<String, dynamic>;
    final kbJson =
        jsonDecode(await source.loadString('$prefix/anatomy_kb.json'))
            as Map<String, dynamic>;

    final graph = <String, List<BodyConnection>>{
      for (final entry in graphJson.entries)
        entry.key: (entry.value as List)
            .whereType<Map<String, dynamic>>()
            .map(BodyConnection.fromJson)
            .toList(),
    };

    final chunks = <String, AnatomyChunk>{};
    for (final entry
        in (kbJson['regions'] as List).whereType<Map<String, dynamic>>()) {
      final chunk = AnatomyChunk.fromEntry(entry);
      chunks[chunk.id] = chunk;
    }

    final data = ClinicalData._(
      rules: RiskRules.fromJson(rulesJson),
      graph: graph,
      chunks: chunks,
    );
    _instance = data;
    return data;
  }

  /// Test hook: drops the cached instance so a test can reload from elsewhere.
  static void resetForTest() => _instance = null;
}

/// One rule in the region matcher. The Python scorer is an ordered keyword
/// chain, so order matters and is preserved by the export.
class RegionRule {
  const RegionRule({
    required this.keywords,
    required this.weight,
    this.leftWeight,
  });

  final List<String> keywords;
  final double weight;

  /// The arm/shoulder branch scores higher on the left, because referred
  /// cardiac pain presents there.
  final double? leftWeight;

  factory RegionRule.fromJson(Map<String, dynamic> json) => RegionRule(
        keywords: (json['keywords'] as List).map((e) => e as String).toList(),
        weight: (json['weight'] as num).toDouble(),
        leftWeight: (json['left_weight'] as num?)?.toDouble(),
      );
}

class RiskRules {
  const RiskRules({
    required this.regionRules,
    required this.defaultRegionWeight,
    required this.painTypeWeights,
    required this.defaultPainTypeWeight,
    required this.heartRateCriticalAbove,
    required this.heartRateCriticalBelow,
    required this.heartRateHighAbove,
    required this.heartRateCriticalBump,
    required this.heartRateHighBump,
    required this.spo2LowBelow,
    required this.spo2ModerateBelow,
    required this.spo2LowBump,
    required this.spo2ModerateBump,
    required this.bmiObeseAt,
    required this.bmiUnderweightBelow,
    required this.bmiBump,
    required this.severityMax,
    required this.severityWeight,
    required this.highBand,
    required this.mediumBand,
    required this.concernBumps,
    required this.emergencyLevel,
    required this.urgentLevel,
    required this.routineLevel,
    required this.actionByLevel,
    required this.concerningChestPainTypes,
    required this.highConcernRegionKeywords,
  });

  final List<RegionRule> regionRules;
  final double defaultRegionWeight;
  final Map<String, double> painTypeWeights;
  final double defaultPainTypeWeight;

  final double heartRateCriticalAbove;
  final double heartRateCriticalBelow;
  final double heartRateHighAbove;
  final double heartRateCriticalBump;
  final double heartRateHighBump;

  final double spo2LowBelow;
  final double spo2ModerateBelow;
  final double spo2LowBump;
  final double spo2ModerateBump;

  final double bmiObeseAt;
  final double bmiUnderweightBelow;
  final double bmiBump;

  final int severityMax;
  final double severityWeight;

  final double highBand;
  final double mediumBand;

  final Map<String, double> concernBumps;

  final String emergencyLevel;
  final String urgentLevel;
  final String routineLevel;
  final Map<String, String> actionByLevel;
  final List<String> concerningChestPainTypes;
  final List<String> highConcernRegionKeywords;

  factory RiskRules.fromJson(Map<String, dynamic> json) {
    final heartRate = json['heart_rate'] as Map<String, dynamic>;
    final spo2 = json['spo2'] as Map<String, dynamic>;
    final bmi = json['bmi'] as Map<String, dynamic>;
    final severity = json['severity'] as Map<String, dynamic>;
    final bands = json['bands'] as Map<String, dynamic>;
    final escalation = json['escalation'] as Map<String, dynamic>;

    return RiskRules(
      regionRules: (json['region_rules'] as List)
          .whereType<Map<String, dynamic>>()
          .map(RegionRule.fromJson)
          .toList(),
      defaultRegionWeight: (json['default_region_weight'] as num).toDouble(),
      painTypeWeights: (json['pain_type_weights'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
      defaultPainTypeWeight:
          (json['default_pain_type_weight'] as num).toDouble(),
      heartRateCriticalAbove: (heartRate['critical_above'] as num).toDouble(),
      heartRateCriticalBelow: (heartRate['critical_below'] as num).toDouble(),
      heartRateHighAbove: (heartRate['high_above'] as num).toDouble(),
      heartRateCriticalBump: (heartRate['critical_bump'] as num).toDouble(),
      heartRateHighBump: (heartRate['high_bump'] as num).toDouble(),
      spo2LowBelow: (spo2['low_below'] as num).toDouble(),
      spo2ModerateBelow: (spo2['moderate_below'] as num).toDouble(),
      spo2LowBump: (spo2['low_bump'] as num).toDouble(),
      spo2ModerateBump: (spo2['moderate_bump'] as num).toDouble(),
      bmiObeseAt: (bmi['obese_at'] as num).toDouble(),
      bmiUnderweightBelow: (bmi['underweight_below'] as num).toDouble(),
      bmiBump: (bmi['bump'] as num).toDouble(),
      severityMax: severity['max'] as int,
      severityWeight: (severity['weight'] as num).toDouble(),
      highBand: (bands['high'] as num).toDouble(),
      mediumBand: (bands['medium'] as num).toDouble(),
      concernBumps: (json['concern_bumps'] as Map<String, dynamic>).map(
        (key, value) => MapEntry(key, (value as num).toDouble()),
      ),
      emergencyLevel: escalation['emergency'] as String,
      urgentLevel: escalation['urgent'] as String,
      routineLevel: escalation['routine'] as String,
      actionByLevel: (escalation['action_by_level'] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value as String)),
      concerningChestPainTypes:
          (escalation['concerning_chest_pain_types'] as List)
              .map((e) => e as String)
              .toList(),
      highConcernRegionKeywords:
          (escalation['high_concern_region_keywords'] as List)
              .map((e) => e as String)
              .toList(),
    );
  }
}

/// One anatomical relationship out of a region, as used by the connectivity
/// part of the score.
class BodyConnection {
  const BodyConnection({
    required this.region,
    required this.note,
    required this.concern,
  });

  final String region;
  final String note;
  final String concern;

  factory BodyConnection.fromJson(Map<String, dynamic> json) => BodyConnection(
        region: json['region'] as String,
        note: json['note'] as String,
        concern: json['concern'] as String,
      );
}

/// One knowledge-base entry, with the token vector the retriever ranks on.
class AnatomyChunk {
  AnatomyChunk({
    required this.id,
    required this.region,
    required this.system,
    required this.text,
    required this.structures,
    required this.commonConditions,
    required this.redFlags,
    required this.suggestedQuestions,
    required this.tokens,
  });

  final String id;
  final String region;
  final String system;
  final String text;
  final List<String> structures;
  final List<String> commonConditions;
  final List<String> redFlags;
  final List<String> suggestedQuestions;
  final List<String> tokens;

  factory AnatomyChunk.fromEntry(Map<String, dynamic> entry) {
    List<String> list(String key) =>
        ((entry[key] as List?) ?? const []).map((e) => e.toString()).toList();

    final text = entry['text'] as String? ?? '';
    final structures = list('structures');
    final conditions = list('common_conditions');
    final redFlags = list('red_flags');
    final questions = list('suggested_questions');

    return AnatomyChunk(
      id: entry['id'] as String,
      region: entry['region'] as String,
      system: entry['system'] as String? ?? '',
      text: text,
      structures: structures,
      commonConditions: conditions,
      redFlags: redFlags,
      suggestedQuestions: questions,
      // Mirrors _chunk_to_text: critical medical terms are repeated so they
      // carry more weight in the vector.
      tokens: AnatomyTokenizer.tokenize([
        text,
        ...structures,
        ...structures,
        ...conditions,
        ...conditions,
        ...redFlags,
        ...redFlags,
        ...questions,
      ].join(' ')),
    );
  }

  /// The JSON shape `GET /anatomy/ask` returns for a source, so the local
  /// engine can feed the same UI models the network path did.
  Map<String, dynamic> toSourceJson(double score) => {
        'id': id,
        'region': region,
        'system': system,
        'score': score,
        'text': text,
        'structures': structures,
        'common_conditions': commonConditions,
        'red_flags': redFlags,
        'suggested_questions': suggestedQuestions,
      };
}

/// Port of `anatomy_retriever._tokenize`, including the medical synonym
/// expansion. Kept in its own class so the chunk builder and the query path
/// cannot drift apart.
class AnatomyTokenizer {
  static const Map<String, List<String>> synonyms = {
    'migraine': ['headache', 'cranial', 'head', 'neurological'],
    'headache': ['migraine', 'cranial', 'head'],
    'head': ['headache', 'cranial'],
    'tummy': ['abdomen', 'stomach', 'gut', 'abdominal'],
    'belly': ['abdomen', 'stomach', 'gut', 'abdominal'],
    'stomach': ['abdomen', 'tummy', 'belly', 'abdominal'],
    'gut': ['abdomen', 'stomach'],
    'breathless': ['dyspnea', 'respiratory', 'chest', 'breath'],
    'angina': ['cardiac', 'chest', 'heart', 'coronary'],
    'heart': ['cardiac', 'chest', 'angina'],
    'dizzy': ['cranial', 'neurological', 'vertigo', 'lightheaded'],
    'lightheaded': ['cranial', 'neurological', 'vertigo', 'dizzy'],
    'knee': ['leg', 'knee', 'joint'],
    'leg': ['leg', 'knee', 'thigh'],
    'shoulder': ['arm', 'shoulder', 'joint'],
    'arm': ['arm', 'shoulder'],
    'backache': ['back', 'lumbar', 'spine'],
    'back': ['spine', 'lumbar', 'backache'],
  };

  static const Set<String> _stopwords = {
    'a',
    'an',
    'and',
    'are',
    'as',
    'at',
    'be',
    'by',
    'for',
    'from',
    'has',
    'have',
    'in',
    'is',
    'it',
    'of',
    'on',
    'or',
    'that',
    'the',
    'to',
    'was',
    'were',
    'will',
    'with',
    'this',
    'any',
    'can',
    'may',
    'their',
    'they',
    'you',
    'your',
    'patient',
    'patients',
    'feel',
    'feeling',
  };

  static final RegExp _wordPattern = RegExp(r'[a-z0-9]+');

  static List<String> tokenize(String text) {
    if (text.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final match in _wordPattern.allMatches(text.toLowerCase())) {
      final token = match.group(0)!;
      if (_stopwords.contains(token) || token.length < 3) continue;
      if (seen.add(token)) out.add(token);
      final expansions = synonyms[token];
      if (expansions != null) {
        for (final synonym in expansions) {
          if (seen.add(synonym)) out.add(synonym);
        }
      }
    }
    return out;
  }
}
