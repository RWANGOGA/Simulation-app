import 'dart:math' as math;

import 'clinical_data.dart';

/// One retrieved knowledge-base entry, with the score it was ranked on.
class AnatomyHit {
  const AnatomyHit({required this.chunk, required this.score});

  final AnatomyChunk chunk;
  final double score;
}

/// A region the body map can ask about, in knowledge-base order.
class AnatomyRegionOption {
  const AnatomyRegionOption({
    required this.id,
    required this.region,
    required this.system,
  });

  final String id;
  final String region;
  final String system;

  Map<String, dynamic> toJson() =>
      {'id': id, 'region': region, 'system': system};
}

/// Offline port of `app/services/anatomy_retriever.py`.
///
/// Retrieval answers three separate questions, and the port keeps them separate
/// in the same way the server does:
///
/// 1. *Which chunks are side-compatible.* The body part the patient tapped, and
///    which side of the body it is on, are facts. A chunk describing the opposite
///    limb is never context for this complaint - the two sides carry different
///    content here, so a leak is a different diagnosis, not a duplicate.
/// 2. *Which chunks have any evidence behind them.* Away from the tapped region
///    and its family, a monograph is only served if the complaint names something
///    it declares as its subject, or shares two corpus-rare words with its text
///    (see _grounded). This is what lets the system say "not covered" instead of
///    dressing up an accidental word overlap as an answer.
/// 3. *How strongly each eligible chunk matches the words.* BM25 plus a TF-IDF
///    cosine, fused with Reciprocal Rank Fusion, with a bounded prior for the
///    tapped region and its family.
///
/// All of that is reproduced here over the bundled copy of the same knowledge
/// base, so the assistant keeps answering with no network and returns the same
/// chunks in the same order, at the same scores.
///
/// The one thing it deliberately does not do is call an LLM. `_run_ask` already
/// has a knowledge-base-only path for when no API key is configured; the app
/// takes that path always and reports `llm_used: false`, which is what makes
/// the UI show its "KB only" badge.
class AnatomyEngine {
  AnatomyEngine._({
    required Map<String, AnatomyChunk> chunks,
    required Map<String, Map<String, double>> vectors,
    required Map<String, double> idf,
    required double avgdl,
  })  : _chunks = chunks,
        _vectors = vectors,
        _idf = idf,
        _avgdl = avgdl;

  final Map<String, AnatomyChunk> _chunks;

  /// tf-idf vector per chunk id, in knowledge-base order.
  final Map<String, Map<String, double>> _vectors;
  final Map<String, double> _idf;
  final double _avgdl;

  static AnatomyEngine? _instance;

  /// The engine over the currently loaded [ClinicalData].
  static AnatomyEngine get instance {
    final cached = _instance;
    if (cached != null) return cached;
    final built = AnatomyEngine.fromData(ClinicalData.instance);
    _instance = built;
    return built;
  }

  /// Builds an index over [data]. Cheap enough to do once at startup: it is a
  /// single pass over 34 chunks.
  factory AnatomyEngine.fromData(ClinicalData data) {
    final chunks = data.chunks;
    final idf = _buildIdf(chunks);
    final vectors = <String, Map<String, double>>{
      for (final entry in chunks.entries)
        entry.key: _vectorize(entry.value.tokens, idf),
    };
    final totalLength = chunks.values.fold<int>(
      0,
      (sum, chunk) => sum + chunk.tokens.length,
    );
    return AnatomyEngine._(
      chunks: chunks,
      vectors: vectors,
      idf: idf,
      avgdl: totalLength / math.max(1, chunks.length),
    );
  }

  static void resetForTest() => _instance = null;

  /// Port of `list_regions()`.
  List<AnatomyRegionOption> listRegions() => [
        for (final chunk in _chunks.values)
          AnatomyRegionOption(
            id: chunk.id,
            region: chunk.region,
            system: chunk.system,
          ),
      ];

  /// Port of `retrieve(region, query, top_k)`.
  ///
  /// Results are ordered by the score reported, which is the point: the number
  /// goes to the client as `sources[].score` and is printed into the prompt as
  /// `score=`, so it must never say the third chunk is more relevant than the
  /// first. It is an absolute confidence in [0, 1] - about 0.48 for the monograph
  /// of a region that was tapped with nothing said about it, approaching 1.0 when
  /// the words match the tapped region too.
  List<AnatomyHit> retrieve({
    String? region,
    String query = '',
    int topK = 3,
  }) {
    final queryTokens = AnatomyTokenizer.tokenize(query.trim().toLowerCase());
    final queryVector = _vectorize(queryTokens, _idf);
    final queryTerms = queryTokens.toSet();
    final regionKey = _governingRegionKey(
      region ?? '',
      AnatomyTokenizer.surfaceTokens(query.trim().toLowerCase()),
    );

    final bm25 = <_Scored>[];
    final tfidf = <_Scored>[];
    final eligible = <_Eligible>[];
    var order = 0;
    for (final entry in _chunks.entries) {
      final chunkRegion = _chunkRegionKeys[entry.key]!;
      if (!_sideCompatible(regionKey, chunkRegion)) {
        order++;
        continue;
      }
      final tier = _regionTier(regionKey, chunkRegion);
      final lexical = _bm25Score(queryTokens, entry.value);
      final cosine = _cosine(queryVector, _vectors[entry.key]!);
      // The region that was tapped and its family qualify on the tap alone: the
      // patient pointed at that part, which is evidence whether or not they found
      // words for it. Anything else has to be grounded in the complaint, and
      // *grounded* is not the same test as *scored above zero* - one shared word
      // between an anxiety complaint and a wrist monograph ('night') is an
      // accident of prose. Padding the window with those was how an out-of-scope
      // question came back looking answered.
      if (tier > _regionFamilyTier && !_grounded(entry.value, queryTerms)) {
        order++;
        continue;
      }
      // _grounded can admit a chunk on a subject word that is really only a region
      // *label* ('left', 'right', 'abdomen' - corpus-rare, so distinctive, yet
      // deliberately absent from the searchable text), leaving it with no ranking
      // signal at all to enter at a bare tier prior. This floor drops those.
      if (tier > _regionFamilyTier && lexical <= 0.0 && cosine <= 0.0) {
        order++;
        continue;
      }
      if (lexical > 0.0) bm25.add(_Scored(entry.key, lexical, order));
      if (cosine > 0.0) tfidf.add(_Scored(entry.key, cosine, order));
      eligible.add(_Eligible(entry.key, tier, order));
      order++;
    }
    _sortDescending(bm25);
    _sortDescending(tfidf);

    // Reciprocal Rank Fusion over the two rankings, then the region prior added
    // on top in the same rank units it was calibrated against.
    const k = 60;
    final fusion = <String, double>{};
    for (final ranked in [bm25, tfidf]) {
      for (var i = 0; i < ranked.length; i++) {
        final rank = i + 1;
        fusion[ranked[i].id] = (fusion[ranked[i].id] ?? 0.0) + 1.0 / (k + rank);
      }
    }

    final ranked = <_Scored>[
      for (final candidate in eligible)
        _Scored(
          candidate.id,
          (fusion[candidate.id] ?? 0.0) + _tierPrior[candidate.tier]!,
          candidate.order,
        ),
    ];
    _sortDescending(ranked);

    return [
      for (final entry in ranked.take(math.max(1, topK)))
        AnatomyHit(
          chunk: _chunks[entry.id]!,
          score: math.min(1.0, entry.score / _maxFused),
        ),
    ];
  }

  /// Port of `_run_ask`'s no-LLM branch, returning the exact JSON shape
  /// `POST /anatomy/ask` responds with so [AnatomyInsight.fromJson] keeps
  /// working untouched.
  Map<String, dynamic> ask({
    String? region,
    String complaint = '',
    int topK = 3,
  }) {
    final trimmedRegion = (region ?? '').trim();
    final regionOrNull = trimmedRegion.isEmpty ? null : trimmedRegion;
    final trimmedComplaint = complaint.trim();

    // The server asks for twice as many chunks and lets the LLM rerank them.
    // With no LLM it simply keeps the first top_k, which is what we do here.
    final hits = retrieve(
      region: regionOrNull,
      query: trimmedComplaint,
      topK: topK * 2,
    ).take(topK).toList();

    // Minimum-evidence abstention, mirroring the server's `_run_ask`: the
    // retriever kept nothing this complaint is grounded in, so there is no context
    // to answer from and none is invented.
    final answered = hits.isNotEmpty;
    final top = answered ? hits.first.chunk : null;

    return <String, dynamic>{
      'region': regionOrNull,
      'complaint': trimmedComplaint,
      'answered': answered,
      'laterality_note': _lateralityNote(regionOrNull, trimmedComplaint),
      'llm_used': false,
      'cached': false,
      'summary': answered
          ? 'Possible structures and conditions in the '
              '${regionOrNull ?? 'selected'} region based on the knowledge base.'
          : 'This complaint is not covered by the anatomy knowledge base, and '
              'there was no grounded context to answer from. Try naming the body '
              'part or rephrasing the symptom.',
      'structures': top?.structures ?? const <String>[],
      'likely_conditions': [
        for (final condition in top?.commonConditions ?? const <String>[])
          {'name': condition, 'rationale': ''},
      ],
      'red_flags': top?.redFlags ?? const <String>[],
      'suggested_questions': top?.suggestedQuestions ?? const <String>[],
      'disclaimer': answered
          ? 'This is supportive information for the clinician, not a '
              'diagnosis. The knowledge base was used directly because the '
              'AI summarizer is unavailable.'
          : 'This is supportive information for the clinician, not a '
              'diagnosis. No knowledge-base context met the minimum evidence '
              'bar for this complaint, so none was supplied.',
      'sources': [
        for (final hit in hits) hit.chunk.toSourceJson(_round4(hit.score)),
      ],
      'citations': [
        for (final hit in hits.take(3))
          {
            'text': _cite(hit.chunk.text),
            'region': hit.chunk.region,
            'system': hit.chunk.system,
            'chunk_id': hit.chunk.id,
          },
      ],
    };
  }

  // ── Scoring internals, ported one-for-one ───────────────────────────────

  static Map<String, double> _buildIdf(Map<String, AnatomyChunk> chunks) {
    final n = math.max(1, chunks.length);
    final documentFrequency = <String, int>{};
    for (final chunk in chunks.values) {
      for (final token in chunk.tokens.toSet()) {
        documentFrequency[token] = (documentFrequency[token] ?? 0) + 1;
      }
    }
    // Port of the non-negative idf form. `log(n / (1 + df))` is negative for any
    // term in two or more chunks, and "pain" is in all 34 of these, so every
    // chunk containing the most common symptom word in the knowledge base was
    // scored *below* one that did not.
    return {
      for (final entry in documentFrequency.entries)
        entry.key:
            math.log(1.0 + (n - entry.value + 0.5) / (entry.value + 0.5)),
    };
  }

  static Map<String, double> _vectorize(
    List<String> tokens,
    Map<String, double> idf,
  ) {
    final termFrequency = <String, double>{};
    for (final token in tokens) {
      termFrequency[token] = (termFrequency[token] ?? 0.0) + 1.0;
    }
    return {
      for (final entry in termFrequency.entries)
        entry.key: entry.value * (idf[entry.key] ?? 0.0),
    };
  }

  static double _cosine(Map<String, double> a, Map<String, double> b) {
    if (a.isEmpty || b.isEmpty) return 0.0;
    var dot = 0.0;
    for (final entry in a.entries) {
      final other = b[entry.key];
      if (other != null) dot += entry.value * other;
    }
    var squaresA = 0.0;
    for (final weight in a.values) {
      squaresA += weight * weight;
    }
    var squaresB = 0.0;
    for (final weight in b.values) {
      squaresB += weight * weight;
    }
    final normA = math.sqrt(squaresA);
    final normB = math.sqrt(squaresB);
    if (normA == 0.0 || normB == 0.0) return 0.0;
    return dot / (normA * normB);
  }

  double _bm25Score(List<String> queryTokens, AnatomyChunk chunk) {
    const k1 = 1.5;
    const b = 0.75;
    final documentLength = chunk.tokens.length;
    var score = 0.0;
    for (final token in queryTokens) {
      final frequency = chunk.tokens.where((t) => t == token).length;
      if (frequency == 0) continue;
      final idf = _idf[token] ?? 0.0;
      final numerator = frequency * (k1 + 1.0);
      final denominator =
          frequency + k1 * (1.0 - b + b * (documentLength / _avgdl));
      score += idf * numerator / denominator;
    }
    return score;
  }

  // ── Region structure, ported one-for-one ────────────────────────────────
  //
  // The body map sends free-text labels ("Left Arm / Shoulder", "Knee (Left)",
  // "Thighs"), and everything the retriever needs from one is which side it is on
  // and which body parts it names. Comparing the labels as strings is what let
  // "thigh" fail against "thighs" and the mirror-image chunk survive.

  static const List<String> _sideWords = ['left', 'right'];

  /// Words that locate a region without naming a body part. Counting them as
  /// parts would make every quadrant of the abdomen "the same region"; ignoring
  /// them entirely would make upper and lower back the same region.
  static const Set<String> _nonPartWords = {
    'left',
    'right',
    'upper',
    'lower',
    'pain',
    'side',
    'anterior',
    'posterior',
  };

  /// The prior on rank for each tier, in the same Reciprocal Rank units as the
  /// evidence it is added to: a chunk first in both rankings earns about 0.033 and
  /// one that matched a single incidental word about 0.016, so 0.0305 puts the
  /// tapped region ahead of incidental matches without putting it ahead of a
  /// chunk the complaint's own words led both rankings.
  static const Map<int, double> _tierPrior = {
    0: 0.0305,
    1: 0.0100,
    2: 0.0030,
    3: 0.0,
  };

  static const int _regionFamilyTier = 2;

  static const double _maxFused = 2.0 / 61.0 + 0.0305;

  // ── Minimum evidence, ported one-for-one from `_grounded` ───────────────
  //
  // A word shared with a monograph is not the same thing as a monograph that is
  // *about* the complaint. The server's module docstring records how four
  // out-of-scope complaints were each answered from a chunk with exactly one word
  // in common. Two of the three admissibility tests are corpus-derived rather than
  // tuned: the subject set is what the monograph declares it is about, and
  // "distinctive" is measured by idf, so a word in most of the knowledge base
  // ('pain' has idf ~0.014) cannot qualify a chunk on its own. `_minDistinctiveIdf`
  // is the only hand-chosen number; it sits between the corpus's two vocabulary
  // layers. Ported verbatim so the offline engine abstains on the same complaints
  // the server does - parity is the safety property here, not a nice-to-have.
  static const double _minDistinctiveIdf = 1.5;
  static const int _minDistinctiveTerms = 2;

  /// Port of `_grounded`: does this monograph have anything to say about *this*
  /// complaint? True when the complaint names a distinctive subject the monograph
  /// declares, or shares at least [_minDistinctiveTerms] corpus-rare words with its
  /// text. `queryTerms` is the *expanded* query - a clinician's word is the
  /// patient's word after the synonym bridge, and that counts as evidence.
  bool _grounded(AnatomyChunk chunk, Set<String> queryTerms) {
    for (final token in chunk.subject) {
      if (queryTerms.contains(token) &&
          (_idf[token] ?? 0.0) >= _minDistinctiveIdf) {
        return true;
      }
    }
    var matches = 0;
    for (final token in chunk.tokens) {
      if (queryTerms.contains(token) &&
          (_idf[token] ?? 0.0) >= _minDistinctiveIdf &&
          ++matches >= _minDistinctiveTerms) {
        return true;
      }
    }
    return false;
  }

  /// Parsed region key per chunk, so the parse happens once per knowledge base
  /// rather than once per query.
  late final Map<String, _RegionKey> _chunkRegionKeys = {
    for (final entry in _chunks.entries)
      entry.key: _regionKey(entry.value.region),
  };

  /// Port of `_region_key`.
  static _RegionKey _regionKey(String region) {
    final cleaned =
        region.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
    // Folded through the same normalisation as text, in the same order: drop the
    // short fragments first, then collapse, so a tap on 'Thighs' and a monograph
    // titled 'Thighs' agree about which body part is meant.
    final words = [
      for (final word
          in cleaned.split(RegExp(r'\s+')).where((word) => word.length > 2))
        AnatomyTokenizer.canonicalForm(word)
    ];
    String? side;
    for (final word in words) {
      if (_sideWords.contains(word)) {
        side = word;
        break;
      }
    }
    return _RegionKey(
      side,
      words.where((word) => !_nonPartWords.contains(word)).toSet(),
      words.where(_nonPartWords.contains).toSet(),
    );
  }

  /// Port of `_side_compatible`: false only when both sides are known and differ.
  /// A complaint naming no side keeps both limbs in play, because nothing has
  /// ruled either out.
  static bool _sideCompatible(_RegionKey query, _RegionKey chunk) {
    final a = query.side;
    final b = chunk.side;
    if (a == null || b == null) return true;
    return a == b;
  }

  /// Port of `_narrative_side`: the side the complaint itself states, or null.
  /// Only an unambiguous statement counts, so a sentence naming both sides defers
  /// to the tap instead of silently picking whichever word came first.
  static String? _narrativeSide(List<String> surface) {
    final named = surface.where(_sideWords.contains).toSet();
    return named.length == 1 ? named.first : null;
  }

  /// Port of `_governing_region_key`: the tap's parts, the narrative's side.
  ///
  /// The body map and the sentence are two statements about the same body and the
  /// tap is the coarser one. A patient who taps "Right Arm / Shoulder" and writes
  /// "pain in my left arm and jaw" has contradicted themselves, and the written
  /// side is the more specific, deliberate act - and the one matching a cardiac
  /// referral pattern. Reading laterality from the tap alone made the left-arm
  /// monograph unreachable for that complaint.
  ///
  /// The parts still come from the tap, so prose cannot drag retrieval to an
  /// unrelated body part; only the mirror image of the tapped part is switched.
  /// The locator carrying the old side is replaced rather than kept, so the tapped
  /// part on the stated side is the *same* region (tier 0). Because the side is a
  /// filter, overriding it also withdraws the tapped side's own monograph.
  static _RegionKey _governingRegionKey(String region, List<String> surface) {
    final base = _regionKey(region);
    final side = _narrativeSide(surface);
    if (side == null || side == base.side) return base;
    return _RegionKey(
      side,
      base.parts,
      {...base.locators.where((word) => !_sideWords.contains(word)), side},
    );
  }

  /// Port of `side_override`: `(tap's side, side actually used)` when the
  /// complaint's own words took laterality away from the tap, else null.
  ///
  /// Reconciling a contradiction silently is still a contradiction: the screen
  /// would show left-arm content under a right-arm selection, which reads like a
  /// bug unless it says what it did. Exposed from the retriever itself so a caller
  /// cannot disagree with it about which side was used.
  static (String, String)? sideOverride(String? region, String? query) {
    final base = _regionKey(region ?? '');
    final side = _narrativeSide(
      AnatomyTokenizer.surfaceTokens((query ?? '').trim().toLowerCase()),
    );
    if (side == null || base.side == null || side == base.side) return null;
    return (base.side!, side);
  }

  /// The clinician-facing sentence for [sideOverride], mirroring the server's
  /// `laterality_note`. The golden fixture records the server's own wording for
  /// every probe, so this sentence is checked character-for-character against it
  /// rather than trusted to have been copied correctly.
  static String? _lateralityNote(String? region, String? query) {
    final override = sideOverride(region, query);
    if (override == null) return null;
    final tapped = override.$1;
    final used = override.$2;
    return 'The body map was set to the $tapped side, but this complaint describes '
        'the $used side. The information below follows the $used side, because what '
        'the patient wrote is the more specific statement.';
  }

  /// Port of `_region_tier`.
  static int _regionTier(_RegionKey query, _RegionKey chunk) {
    if (query.parts.isEmpty) return 3;
    final sameParts = query.parts.length == chunk.parts.length &&
        query.parts.containsAll(chunk.parts);
    final sameSide = query.side == chunk.side;
    if (sameParts && sameSide) {
      final sameLocators = query.locators.length == chunk.locators.length &&
          query.locators.containsAll(chunk.locators);
      return sameLocators ? 0 : 1;
    }
    if (query.parts.intersection(chunk.parts).isNotEmpty) return 2;
    return 3;
  }

  /// Python's `sorted(..., reverse=True)` is stable, so ties keep the order the
  /// candidates were discovered in. `List.sort` is not stable, so the order is
  /// carried explicitly instead.
  static void _sortDescending(List<_Scored> scores) {
    scores.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });
  }

  static String _cite(String text) =>
      text.length > 500 ? '${text.substring(0, 500)}...' : text;

  static double _round4(double value) =>
      (value * 10000).roundToDouble() / 10000;
}

class _Scored {
  const _Scored(this.id, this.score, this.order);

  final String id;
  final double score;
  final int order;
}

/// A chunk that passed the eligibility filter, before any evidence was scored.
class _Eligible {
  const _Eligible(this.id, this.tier, this.order);

  final String id;
  final int tier;
  final int order;
}

/// Port of the frozen `RegionKey` dataclass.
class _RegionKey {
  const _RegionKey(this.side, this.parts, this.locators);

  final String? side;
  final Set<String> parts;
  final Set<String> locators;
}
