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

    final kbEntries =
        (kbJson['regions'] as List).whereType<Map<String, dynamic>>().toList();
    // The inflection collapse is defined by the corpus, so the vocabulary has to
    // exist before a single chunk is tokenised.
    AnatomyTokenizer.vocabulary = AnatomyTokenizer.buildVocabulary(kbEntries);

    final chunks = <String, AnatomyChunk>{};
    for (final entry in kbEntries) {
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
    required this.tierScale,
    required this.tierOrder,
    required this.tierCategories,
    required this.tierOrangeScoreMin,
    required this.tierYellowScoreMin,
    required this.tierRuleCodes,
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

  // No SpO2 thresholds: the offline engine scores exactly what the server scores,
  // and the server dropped the camera perfusion estimate from the risk model.

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

  // ── Triage tier (SATS categories) ──────────────────────────────────────
  //
  // Every number and code below comes from the generated rule table, exactly like
  // the scoring weights. That is deliberate: a device that hardcodes its own
  // thresholds can hand a patient one category and the practitioner's server
  // another, offline, with nobody beside it to notice.

  /// The scale these categories come from — 'SATS'. Sent with every tier so a
  /// reader knows which four-word vocabulary is in use.
  final String tierScale;

  /// Most urgent first. Clients draw the colour strip in this order.
  final List<String> tierOrder;

  /// tier -> the scale's own name for it, e.g. 'orange' -> 'very_urgent'.
  final Map<String, String> tierCategories;

  final double tierOrangeScoreMin;
  final double tierYellowScoreMin;

  /// The three reasons no finding can name, exported so `decided_by` is
  /// byte-identical on both platforms and localisable by code.
  final Map<String, String> tierRuleCodes;

  factory RiskRules.fromJson(Map<String, dynamic> json) {
    final heartRate = json['heart_rate'] as Map<String, dynamic>;
    final bmi = json['bmi'] as Map<String, dynamic>;
    final severity = json['severity'] as Map<String, dynamic>;
    final bands = json['bands'] as Map<String, dynamic>;
    final escalation = json['escalation'] as Map<String, dynamic>;
    final tiers = json['tiers'] as Map<String, dynamic>;

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
      tierScale: tiers['scale'] as String,
      tierOrder: (tiers['order'] as List).map((e) => e as String).toList(),
      tierCategories: (tiers['categories'] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value as String)),
      tierOrangeScoreMin: (tiers['orange_score_min'] as num).toDouble(),
      tierYellowScoreMin: (tiers['yellow_score_min'] as num).toDouble(),
      tierRuleCodes: (tiers['rule_codes'] as Map<String, dynamic>)
          .map((key, value) => MapEntry(key, value as String)),
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
    required this.subject,
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

  /// What this monograph is *about*: its region label, the structures it covers
  /// and the conditions it names, folded to base form. Not searchable text - the
  /// chunk's own declaration of its subject, read by the minimum-evidence test
  /// (`AnatomyEngine._grounded`) to decide whether a complaint is even pointing at
  /// this part. Red flags are excluded: they are prose about symptom patterns, and
  /// counting them let out-of-scope complaints back in. Mirrors `AnatomyChunk.subject`
  /// on the server.
  final Set<String> subject;

  factory AnatomyChunk.fromEntry(Map<String, dynamic> entry) {
    List<String> list(String key) =>
        ((entry[key] as List?) ?? const []).map((e) => e.toString()).toList();

    final text = entry['text'] as String? ?? '';
    final structures = list('structures');
    final conditions = list('common_conditions');
    final redFlags = list('red_flags');
    final questions = list('suggested_questions');
    final region = entry['region'] as String;

    return AnatomyChunk(
      id: entry['id'] as String,
      region: region,
      system: entry['system'] as String? ?? '',
      text: text,
      structures: structures,
      commonConditions: conditions,
      redFlags: redFlags,
      suggestedQuestions: questions,
      // Mirrors the server's document path: indexed as written, no synonym
      // expansion, inflections folded onto the corpus's own base forms.
      tokens:
          AnatomyTokenizer.indexTokens(AnatomyTokenizer.searchableText(entry)),
      // Port of `load_kb`'s subject build: the region label plus the structures
      // and named conditions, over the raw entry, folded the same way documents
      // are (no query-side expansion).
      subject: AnatomyTokenizer.indexTokens(
        [region, ...structures, ...conditions].join(' '),
      ).toSet(),
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
    // Clinical vocabulary: the monographs are written in plain prose, so these
    // terms reached nothing at all until the backend added them. Mirrored from
    // MEDICAL_SYNONYMS - test/clinical_parity_test.dart compares the derived
    // expansion table against the server's, so drift fails the suite.
    'dyspnea': ['breath', 'shortness', 'chest'],
    'exertion': ['breath', 'shortness', 'chest'],
    'orthopnea': ['breath', 'lying', 'chest'],
    'pleuritic': ['pleura', 'breath', 'chest', 'rib'],
    'hematemesis': ['blood', 'vomiting', 'stomach'],
    'hematochezia': ['blood', 'stool', 'bowel'],
    'melena': ['black', 'tarry', 'stool', 'blood'],
    'odynophagia': ['throat', 'esophagus', 'gerd'],
    'dysphagia': ['throat', 'esophagus'],
    'hepatic': ['liver', 'gallbladder', 'pancreas'],
    'biliary': ['gallbladder', 'gallstones', 'liver'],
    'cholelithiasis': ['gallstones', 'gallbladder'],
    'colic': ['cramp', 'gallstones', 'stone', 'kidney', 'back', 'waves'],
    'renal': ['kidney', 'ureter', 'stone', 'back', 'groin', 'side'],
    'diaphoresis': ['sweat', 'sweating'],
    'syncope': ['fainting', 'faint', 'dizzy'],
    'crepitus': ['joint', 'knee', 'grinding', 'osteoarthritis'],
    'edema': ['swelling', 'swollen', 'ankle'],
    'ambulate': ['bear', 'weight', 'leg'],
    'flank': ['side', 'back', 'kidney', 'groin'],
    'emesis': ['vomiting', 'nausea'],
    'heel': ['foot', 'plantar', 'arch', 'steps'],
    'ankle': ['foot', 'leg', 'shin'],
    'shin': ['leg', 'calf', 'ankle'],
    'instep': ['foot', 'ankle'],
    'groin': ['hip', 'testicle', 'abdomen', 'pubic'],
    'jaw': ['mouth', 'neck', 'teeth'],
  };

  /// Suppletive and Latin/Greek plurals, where no suffix rule can help. An entry
  /// whose base form is absent from [vocabulary] is ignored, so this table cannot
  /// invent a stem either.
  static const Map<String, String> _irregularForms = {
    'feet': 'foot',
    'teeth': 'tooth',
    'calves': 'calf',
    'menisci': 'meniscus',
    'phalanges': 'phalanx',
    'ligaments': 'ligament',
  };

  static const List<String> _sSuffixExclusions = ['ss', 'us', 'is', 'xs'];

  /// Every surface word in the knowledge base, region titles included.
  ///
  /// The inflection collapse below is defined *by the corpus*: a form is folded
  /// onto another only when both occur here. That is what keeps it safe on
  /// biomedical text, where a general-English stemmer folds 'diabetes' onto a
  /// non-word and treats '-us' as a suffix. Set once by `ClinicalData.load`
  /// before any chunk is tokenised; empty means unconfigured, not no vocabulary.
  static Set<String> vocabulary = const <String>{};

  static final RegExp _wordPattern = RegExp(r'[a-z0-9]+');

  /// The searchable text of an entry: prose, then its critical terms repeated.
  /// Mirrors `_chunk_to_text`. The region title is deliberately absent - indexing
  /// it was measured to change no ranking while making 'right'/'left' searchable
  /// laterality, which the structured filter already owns.
  static String searchableText(Map<String, dynamic> entry) {
    List<String> list(String key) =>
        ((entry[key] as List?) ?? const []).map((e) => e.toString()).toList();
    final structures = list('structures');
    final conditions = list('common_conditions');
    final redFlags = list('red_flags');
    return [
      entry['text'] as String? ?? '',
      ...structures,
      ...structures,
      ...conditions,
      ...conditions,
      ...redFlags,
      ...redFlags,
      ...list('suggested_questions'),
    ].join(' ');
  }

  static Set<String> buildVocabulary(Iterable<Map<String, dynamic>> entries) {
    final words = <String>{};
    for (final entry in entries) {
      words.addAll(surfaceTokens(searchableText(entry)));
      words.addAll(surfaceTokens((entry['region'] as String?) ?? ''));
    }
    return words;
  }

  /// Content words only: lower-cased, no punctuation, stopwords and 1-2 character
  /// fragments dropped, order preserved, duplicates removed.
  static List<String> surfaceTokens(String text) {
    if (text.isEmpty) return const [];
    final seen = <String>{};
    final out = <String>[];
    for (final match in _wordPattern.allMatches(text.toLowerCase())) {
      final token = match.group(0)!;
      if (_stopwords.contains(token) || token.length < 3) continue;
      if (seen.add(token)) out.add(token);
    }
    return out;
  }

  /// Symmetric (key <-> target) expansion edges, one hop only, exactly as the
  /// server derives them. Group-sharing the targets instead widens 'chest' from 7
  /// terms to 15 and measured two fewer passing cases on the server's fixture.
  static final Map<String, List<String>> _expansionTable = () {
    final table = <String, Set<String>>{};
    for (final entry in synonyms.entries) {
      (table[entry.key] ??= <String>{}).addAll(entry.value);
      for (final target in entry.value) {
        (table[target] ??= <String>{}).add(entry.key);
      }
    }
    return {
      for (final entry in table.entries)
        entry.key: (entry.value.toList()..sort())
            .where((word) => word != entry.key)
            .toList(),
    };
  }();

  /// The derived table, exposed for `test/clinical_parity_test.dart`: the golden
  /// fixture records the server's own edges, so a synonym added on one side and
  /// not the other fails there rather than silently changing what a patient's
  /// words retrieve.
  static Map<String, List<String>> get expansionTable => _expansionTable;

  static List<String> expandQuery(List<String> tokens) {
    final seen = tokens.toSet();
    final out = <String>[...tokens];
    for (final token in tokens) {
      for (final synonym in _expansionTable[token] ?? const <String>[]) {
        if (seen.add(synonym)) out.add(synonym);
      }
    }
    return out;
  }

  /// Base form of an inflected word, using only vocabulary the corpus owns.
  static String canonicalForm(String token) {
    final irregular = _irregularForms[token];
    if (irregular != null && vocabulary.contains(irregular)) return irregular;
    if (token.length > 4 && token.endsWith('ies')) {
      final base = '${token.substring(0, token.length - 3)}y';
      if (vocabulary.contains(base)) return base;
    }
    if (token.length > 4 && token.endsWith('es')) {
      final base = token.substring(0, token.length - 2);
      if (vocabulary.contains(base)) return base;
    }
    if (token.length > 3 &&
        token.endsWith('s') &&
        !_sSuffixExclusions.any(token.endsWith)) {
      final base = token.substring(0, token.length - 1);
      if (vocabulary.contains(base)) return base;
    }
    return token;
  }

  /// Collapse inflections, then drop the duplicates the collapse creates.
  static List<String> normalise(List<String> tokens) {
    final seen = <String>{};
    final out = <String>[];
    for (final token in tokens) {
      if (seen.add(canonicalForm(token))) out.add(canonicalForm(token));
    }
    return out;
  }

  /// Document side: indexed exactly as written, no synonym expansion.
  static List<String> indexTokens(String text) =>
      normalise(surfaceTokens(text));

  /// Query side, port of `anatomy_retriever._tokenize`: content words, their
  /// synonym bridge, then inflections folded.
  static List<String> tokenize(String text) =>
      normalise(expandQuery(surfaceTokens(text)));

  /// Mirrors `_STOPWORDS` in the retriever. Keep the two in step: a function word
  /// the offline engine keeps is a symptom the offline engine invents, and
  /// "I can't breathe when I walk up the stairs" once retrieved the abdomen
  /// monograph on the strength of "when" alone.
  static const Set<String> _stopwords = {
    // articles, prepositions, conjunctions
    'a', 'an', 'and', 'as', 'at', 'by', 'for', 'from', 'in', 'into', 'of',
    'on', 'onto', 'or', 'over', 'since', 'that', 'the', 'their', 'them',
    'then', 'than', 'this', 'those', 'to', 'under', 'upon', 'with', 'within',
    'without', 'yet',
    // auxiliary and copular verbs
    'am', 'are', 'be', 'been', 'being', 'did', 'does', 'doing', 'done', 'get',
    'gets', 'getting', 'got', 'had', 'has', 'have', 'having', 'is', 'may',
    'might', 'must', 'was', 'were', 'will', 'would', 'should', 'could',
    'used', 'cannot', 'cant', 'can', 'doesnt', 'didnt', 'dont', 'isnt',
    'wont', 'arent', 'wasnt', 'havent', 'hasnt', 'hadnt', 'wouldnt',
    'couldnt', 'shouldnt',
    // pronouns and possessives
    'he', 'him', 'his', 'her', 'hers', 'herself', 'i', 'it', 'its', 'me',
    'mine', 'my', 'ours', 'our', 'she', 'theirs', 'they', 'us', 'you',
    'your', 'yours',
    // question and filler words
    'any', 'anyone', 'anything', 'because', 'before', 'both', 'each', 'else',
    'enough', 'even', 'every', 'how', 'just', 'like', 'much', 'mostly', 'no',
    'not', 'only', 'own', 'quite', 'rather', 'really', 'same', 'some',
    'such', 'though', 'through', 'very', 'what', 'when', 'whenever', 'where',
    'whether', 'which', 'who', 'whom', 'whose', 'why',
    // verbs of reporting and everyday action found in patient prose
    'always', 'asked', 'came', 'comes', 'coming', 'come', 'feel', 'feeling',
    'felt', 'go', 'goes', 'going', 'gone', 'make', 'makes', 'made', 'need',
    'needed', 'needs', 'often', 'patient', 'patients', 'say', 'said', 'says',
    'seems', 'take', 'takes', 'taking', 'told', 'wants', 'wanted', 'usually',
    'sometimes',
  };
}
