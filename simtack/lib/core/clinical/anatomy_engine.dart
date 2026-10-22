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
/// The server ranks with BM25 plus a TF-IDF cosine, fuses the two with
/// Reciprocal Rank Fusion, and adds a region bonus so the body map's own
/// region wins ties. All of that is reproduced here over the bundled copy of
/// the same knowledge base, so the assistant keeps answering with no network
/// and returns the same chunks in the same order.
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
    required Map<String, int> order,
    required double avgdl,
  })  : _chunks = chunks,
        _vectors = vectors,
        _idf = idf,
        _order = order,
        _avgdl = avgdl;

  final Map<String, AnatomyChunk> _chunks;

  /// tf-idf vector per chunk id, in knowledge-base order.
  final Map<String, Map<String, double>> _vectors;
  final Map<String, double> _idf;

  /// Chunk position in the knowledge base. Fusion ties have to break the same
  /// way the server's insertion-ordered dict breaks them.
  final Map<String, int> _order;
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
      order: {
        for (final (index, id) in chunks.keys.indexed) id: index,
      },
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
  /// Results keep the fusion order, not the order of the reported score: the
  /// fused rank is the ranking, and the score is only the better of the two
  /// underlying ones, exactly as the server reports it.
  List<AnatomyHit> retrieve({
    String? region,
    String query = '',
    int topK = 3,
  }) {
    final regionKey = (region ?? '').trim().toLowerCase();
    final queryTokens = AnatomyTokenizer.tokenize(query.trim().toLowerCase());
    final queryVector = _vectorize(queryTokens, _idf);

    final bm25 = <_Scored>[];
    final tfidf = <_Scored>[];
    var order = 0;
    for (final entry in _chunks.entries) {
      final chunk = entry.value;
      final chunkRegion = chunk.region.toLowerCase();

      var lexical = _bm25Score(queryTokens, chunk);
      if (regionKey.isNotEmpty) {
        lexical += _regionBoost(regionKey, chunkRegion);
      }
      if (lexical > 0.0) {
        bm25.add(_Scored(entry.key, lexical, order));
      }

      var cosine = _cosine(queryVector, _vectors[entry.key]!);
      if (regionKey.isNotEmpty) {
        cosine += _regionBoost(regionKey, chunkRegion);
      }
      if (cosine > 0.0) {
        tfidf.add(_Scored(entry.key, cosine, order));
      }

      order++;
    }
    _sortDescending(bm25);
    _sortDescending(tfidf);

    // Reciprocal Rank Fusion over the two rankings.
    const k = 60;
    final fusion = <String, double>{};
    for (final ranked in [bm25, tfidf]) {
      for (var i = 0; i < ranked.length; i++) {
        final rank = i + 1;
        fusion[ranked[i].id] = (fusion[ranked[i].id] ?? 0.0) + 1.0 / (k + rank);
      }
    }
    final fused = <_Scored>[
      for (final entry in fusion.entries)
        _Scored(entry.key, entry.value, _order[entry.key] ?? 0),
    ];
    _sortDescending(fused);

    final bm25ById = {for (final hit in bm25) hit.id: hit.score};
    final tfidfById = {for (final hit in tfidf) hit.id: hit.score};

    final hits = <AnatomyHit>[];
    for (final entry in fused.take(math.max(1, topK))) {
      final score = math.max(
        bm25ById[entry.id] ?? 0.0,
        tfidfById[entry.id] ?? 0.0,
      );
      if (score > 0.0) {
        hits.add(AnatomyHit(chunk: _chunks[entry.id]!, score: score));
      }
    }
    return hits;
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

    final top = hits.isEmpty ? null : hits.first.chunk;

    return <String, dynamic>{
      'region': regionOrNull,
      'complaint': trimmedComplaint,
      'llm_used': false,
      'cached': false,
      'summary': top != null
          ? 'Possible structures and conditions in the '
              '${regionOrNull ?? 'selected'} region based on the knowledge base.'
          : 'No matching anatomy context was found.',
      'structures': top?.structures ?? const <String>[],
      'likely_conditions': [
        for (final condition in top?.commonConditions ?? const <String>[])
          {'name': condition, 'rationale': ''},
      ],
      'red_flags': top?.redFlags ?? const <String>[],
      'suggested_questions': top?.suggestedQuestions ?? const <String>[],
      'disclaimer': 'This is supportive information for the clinician, not a '
          'diagnosis. The knowledge base was used directly because the '
          'AI summarizer is unavailable.',
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
    return {
      for (final entry in documentFrequency.entries)
        entry.key: math.log(n / (1.0 + entry.value)),
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

  /// The bonus that makes the region the patient actually tapped win.
  static double _regionBoost(String regionKey, String chunkRegion) {
    if (regionKey == chunkRegion) return 10.0;
    if (chunkRegion.contains(regionKey) || regionKey.contains(chunkRegion)) {
      return 3.0;
    }
    const directionals = {'right', 'left', 'upper', 'lower', 'pain', 'side'};
    Set<String> parts(String value) => value
        .split(' ')
        .where((word) => word.isNotEmpty)
        .where((word) => !directionals.contains(word) && word.length > 2)
        .toSet();
    final regionParts = parts(regionKey);
    final chunkParts = parts(chunkRegion);
    if (regionParts.isNotEmpty && regionParts.intersection(chunkParts).isNotEmpty) {
      return 2.0;
    }
    return 0.0;
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

  static double _round4(double value) => (value * 10000).roundToDouble() / 10000;
}

class _Scored {
  const _Scored(this.id, this.score, this.order);

  final String id;
  final double score;
  final int order;
}
