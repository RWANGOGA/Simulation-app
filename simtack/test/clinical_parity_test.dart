import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/clinical/anatomy_engine.dart';
import 'package:simtack/core/clinical/clinical_data.dart';
import 'package:simtack/core/clinical/risk_engine.dart';
import 'package:simtack/core/network/api_client.dart';

import 'support/clinical_assets.dart';

/// Proves the offline clinical engine still answers exactly what the server
/// answers.
///
/// `test/fixtures/clinical_golden.json` is recorded from the Python services by
/// `Backend-fastapi/scripts/export_offline_assets.py`: 425 scored reports, 30
/// retrieval queries and the raw output of the lexical normalisation, each with
/// the answer the server produced. The app has to reproduce every one of them. If
/// a rule, a rounding, a tie-break, a stem or a synonym edge changes on either
/// side without the other following, this file goes red — which is the only thing
/// standing between "works offline" and "scores a patient differently offline".
void main() {
  late ClinicalData data;
  late Map<String, dynamic> golden;
  late Map<String, dynamic> lexicalVectors;

  setUpAll(() async {
    data = await loadClinicalDataForTest();
    golden = jsonDecode(
      File('test/fixtures/clinical_golden.json').readAsStringSync(),
    ) as Map<String, dynamic>;
    final raw = golden['lexical_vectors'];
    if (raw is! Map<String, dynamic>) {
      // Fail once, loudly, with the fix in the message: three loops over an
      // absent section would otherwise pass as perfect parity.
      throw StateError(
        'the golden fixture carries no lexical_vectors — regenerate it with '
        '`venv/bin/python -m scripts.export_offline_assets`',
      );
    }
    lexicalVectors = raw;
  });

  tearDownAll(() {
    ClinicalData.resetForTest();
    AnatomyEngine.resetForTest();
  });

  test('the generated assets describe the whole clinical model', () {
    expect(data.rules.regionRules, hasLength(7));
    // Order is the matcher: "chest" has to win before the arm family does.
    expect(data.rules.regionRules.first.keywords, contains('chest'));
    expect(data.rules.regionRules[5].leftWeight, 0.20);

    expect(data.graph, hasLength(34));
    expect(data.graph.values.expand((c) => c).length, 116);
    expect(data.rules.concernBumps.keys,
        containsAll(<String>['high', 'moderate', 'low']));

    // The bundled KB is a copy of the backend's, not a subset of it.
    expect(data.chunks, hasLength(34));
    expect(data.chunks['chest_heart'], isNotNull);
    expect(data.chunks['chest_heart']!.tokens, isNotEmpty);

    expect(golden['risk_cases'], isA<List>());
    expect((golden['risk_cases'] as List).length, greaterThan(400));
    expect((golden['anatomy_cases'] as List).length, 38);
  });

  group('risk scoring', () {
    test('reproduces every recorded report', () {
      final engine = RiskEngine(data);
      final cases = (golden['risk_cases'] as List).cast<Map<String, dynamic>>();
      final mismatches = <String>[];

      for (final recorded in cases) {
        final input = TriageInput.fromJson(
          recorded['input'] as Map<String, dynamic>,
        );
        final expected = recorded['expected'] as Map<String, dynamic>;

        final assessment = engine.compute(input);
        final label = '${input.bodyRegion} / ${input.painType} / '
            'sev ${input.severity}';

        final expectedRisk = (expected['risk'] as num).toDouble();
        if ((assessment.risk - expectedRisk).abs() > 1e-12) {
          mismatches.add(
            '$label: risk ${assessment.risk} != $expectedRisk',
          );
          continue;
        }

        if (assessment.level != expected['level']) {
          mismatches.add(
            '$label: level ${assessment.level} != ${expected['level']}',
          );
          continue;
        }

        final expectedContributions =
            (expected['contributions'] as List).cast<Map<String, dynamic>>();
        if (assessment.contributions.length != expectedContributions.length) {
          mismatches.add(
            '$label: ${assessment.contributions.length} contributions != '
            '${expectedContributions.length}',
          );
          continue;
        }

        for (var i = 0; i < expectedContributions.length; i++) {
          final actual = assessment.contributions[i];
          final want = expectedContributions[i];
          if (actual.factor != want['factor'] ||
              (actual.shap - (want['shap'] as num).toDouble()).abs() > 1e-12 ||
              actual.impact != want['impact']) {
            mismatches.add(
              '$label: contribution $i is ${actual.toJson()} != $want',
            );
            break;
          }
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason: '${mismatches.length} of ${cases.length} cases diverged:\n'
            '${mismatches.take(10).join('\n')}',
      );
    });

    test('reproduces every recorded red-flag verdict', () {
      final engine = RiskEngine(data);
      final cases = (golden['risk_cases'] as List).cast<Map<String, dynamic>>();
      final mismatches = <String>[];

      for (final recorded in cases) {
        final input = TriageInput.fromJson(
          recorded['input'] as Map<String, dynamic>,
        );
        final expected = (recorded['expected']
            as Map<String, dynamic>)['escalation'] as Map<String, dynamic>;
        final actual = engine.escalation(input);

        if (actual['level'] != expected['level'] ||
            actual['action'] != expected['action'] ||
            jsonEncode(actual['triggers']) !=
                jsonEncode(expected['triggers'])) {
          mismatches.add(
            '${input.bodyRegion} / sev ${input.severity}: '
            '${jsonEncode(actual)} != ${jsonEncode(expected)}',
          );
        }
      }

      expect(
        mismatches,
        isEmpty,
        reason: '${mismatches.length} verdicts diverged:\n'
            '${mismatches.take(10).join('\n')}',
      );
    });

    test('a high score and a red flag are decided independently', () {
      final engine = RiskEngine(data);

      // A middle-of-the-road score, but crushing chest pain that radiates to
      // the arm: the score is not allowed to talk the escalation out of the
      // ambulance.
      const mild = TriageInput(
        bodyRegion: 'Chest / Heart',
        painType: 'Dull',
        severity: 1,
        direction: 'Radiates to left arm',
      );
      final mildAssessment = engine.compute(mild);
      expect(mildAssessment.risk, lessThan(0.7));
      expect(mildAssessment.level, 'medium');
      expect(engine.escalation(mild)['level'], 'emergency');
      expect(RiskEngine.isEmergency(engine.escalation(mild)), isTrue);

      // The reverse: nothing red-flagged, but several factors add up.
      const heavy = TriageInput(
        bodyRegion: 'Chest / Heart',
        painType: 'Crushing',
        severity: 9,
        heartRate: 130,
      );
      expect(engine.compute(heavy).risk, 1.0);
    });

    test('bands fall back to the documented thresholds before assets load', () {
      ClinicalData.resetForTest();
      addTearDown(() async {
        data = await ClinicalData.load(bundle: DiskAssetBundle());
      });

      expect(RiskEngine.levelFor(0.7), 'high');
      expect(RiskEngine.levelFor(0.69), 'medium');
      expect(RiskEngine.levelFor(0.4), 'medium');
      expect(RiskEngine.levelFor(0.39), 'low');
      expect(
        RiskEngine.isEmergency(<String, dynamic>{'level': 'emergency'}),
        isTrue,
      );
    });

    test('scoring without loaded assets fails loudly, not quietly', () {
      ClinicalData.resetForTest();
      addTearDown(() async {
        data = await ClinicalData.load(bundle: DiskAssetBundle());
      });

      expect(
        () => RiskEngine().compute(
          const TriageInput(
            bodyRegion: 'Chest / Heart',
            painType: 'Sharp',
            severity: 5,
          ),
        ),
        throwsA(isA<StateError>()),
      );
    });
  });

  group('anatomy retrieval', () {
    test('reproduces every recorded ranking', () {
      final engine = AnatomyEngine.fromData(data);
      final cases =
          (golden['anatomy_cases'] as List).cast<Map<String, dynamic>>();

      for (final recorded in cases) {
        final region = recorded['region'] as String;
        final query = recorded['query'] as String;
        final topK = recorded['top_k'] as int;
        final expected =
            (recorded['expected'] as List).cast<Map<String, dynamic>>();

        final hits = engine.retrieve(region: region, query: query, topK: topK);
        final label = '"$query" in "$region" (top $topK)';

        expect(
          hits.map((hit) => hit.chunk.id).toList(),
          expected.map((e) => e['id'] as String).toList(),
          reason: '$label returned a different ranking',
        );
        for (var i = 0; i < hits.length; i++) {
          expect(
            hits[i].score,
            closeTo((expected[i]['score'] as num).toDouble(), 1e-6),
            reason: '$label: score of ${hits[i].chunk.id} at rank $i',
          );
        }
      }
    });

    test('the region tapped wins over a looser textual match', () {
      final engine = AnatomyEngine.fromData(data);
      final hits =
          engine.retrieve(region: 'Chest / Heart', query: 'chest pain');
      expect(hits.first.chunk.region, 'Chest / Heart');
    });

    test('answers with the knowledge base and says so', () {
      final engine = AnatomyEngine.fromData(data);
      final payload = engine.ask(
        region: 'Chest / Heart',
        complaint: 'crushing chest pain spreading to left arm',
      );

      // No LLM on the device, so the UI must show its "KB only" badge rather
      // than claiming an AI answered.
      expect(payload['llm_used'], isFalse);
      expect(payload['cached'], isFalse);
      expect(payload['summary'], contains('knowledge base'));
      expect(payload['sources'], isA<List>());
      expect((payload['sources'] as List), isNotEmpty);
      expect(payload['citations'], isA<List>());
      expect(
        (payload['citations'] as List).length,
        lessThanOrEqualTo(3),
      );

      // The whole point: the existing model parses the offline payload as-is.
      final insight = AnatomyInsight.fromJson(payload);
      expect(insight.llmUsed, isFalse);
      expect(insight.region, 'Chest / Heart');
      expect(insight.complaint, 'crushing chest pain spreading to left arm');
      expect(insight.sources, isNotEmpty);
      expect(insight.sources.first.id, 'chest_heart');
      expect(insight.sources.first.structures, isNotEmpty);
      expect(insight.citations.first.chunkId, 'chest_heart');
      expect(insight.summary, isNotEmpty);
      expect(insight.disclaimer, isNotEmpty);
    });

    test('never returns more than top_k, and more context when asked for it',
        () {
      final engine = AnatomyEngine.fromData(data);
      // The server returns fewer than top_k when fewer chunks score at all,
      // so the invariant is a ceiling plus monotonicity, not equality.
      for (final region in [
        'Chest / Heart',
        'Knee (Left)',
        'Headache / Cranial'
      ]) {
        var previous = 0;
        for (final topK in [1, 3, 6]) {
          final sources =
              engine.ask(region: region, topK: topK)['sources'] as List;
          expect(sources.length, lessThanOrEqualTo(topK));
          expect(sources.length, greaterThanOrEqualTo(previous),
              reason: 'top_k $topK for $region returned less than a smaller k');
          previous = sources.length;
        }
      }
    });

    test('lists every region for the picker', () {
      final engine = AnatomyEngine.fromData(data);
      final regions = engine.listRegions();
      expect(regions, hasLength(34));
      expect(regions.first.id, isNotEmpty);
      expect(regions.map((r) => r.region), contains('Chest / Heart'));
    });

    test('an empty question degrades instead of throwing', () {
      final engine = AnatomyEngine.fromData(data);
      final payload = engine.ask(region: '', complaint: '');
      expect(payload['answered'], isFalse);
      expect(payload['summary'], contains('not covered'));
      expect(payload['sources'], isEmpty);
      expect(AnatomyInsight.fromJson(payload).sources, isEmpty);
      expect(AnatomyInsight.fromJson(payload).answered, isFalse);
    });

    test('abstains on the same complaints the server abstains on', () {
      final engine = AnatomyEngine.fromData(data);
      final cases =
          (golden['anatomy_cases'] as List).cast<Map<String, dynamic>>();
      // Every recorded abstention (the server kept nothing) must also be empty in
      // the offline engine. Parity here is a shared refusal, not a shared ranking:
      // a rule drift that let an out-of-scope complaint back in would surface as a
      // non-empty result against an empty expected list.
      var abstentions = 0;
      for (final recorded in cases) {
        final expected =
            (recorded['expected'] as List).cast<Map<String, dynamic>>();
        if (expected.isNotEmpty) continue;
        abstentions++;
        final hits = engine.retrieve(
          region: recorded['region'] as String,
          query: recorded['query'] as String,
          topK: recorded['top_k'] as int,
        );
        expect(hits, isEmpty,
            reason: '${recorded['query']} should abstain but returned '
                '${hits.map((h) => h.chunk.id).toList()}');
      }
      expect(abstentions, greaterThanOrEqualTo(8),
          reason: 'the golden set must carry the P0-6 abstention probes');

      final payload = engine.ask(
        region: '',
        complaint: 'how many days of antibiotics for a sinus infection',
      );
      expect(payload['answered'], isFalse);
      expect(payload['sources'], isEmpty);
    });
  });

  // The two mechanisms P0-9 added, asserted on their own rather than through a
  // score. Thirty matching rankings prove the engines agree about those thirty
  // queries; they do not prove the offline engine folds 'thighs' the same way or
  // knows the same synonym edges — a drifted rule can hide behind a monograph
  // that dominates the ranking and surface on the next complaint nobody vector
  // picked. These are the raw functions, compared to what the server returns.
  group('lexical normalisation parity', () {
    test('folds exactly the inflections the server folds', () {
      final probes = (lexicalVectors['canonical_form'] as List)
          .cast<Map<String, dynamic>>();
      expect(probes.length, greaterThan(500));

      final mismatches = <String>[
        for (final probe in probes)
          if (AnatomyTokenizer.canonicalForm(probe['word'] as String) !=
              probe['canonical'])
            '${probe['word']} -> '
                '${AnatomyTokenizer.canonicalForm(probe['word'] as String)} '
                '!= ${probe['canonical']}',
      ];
      expect(
        mismatches,
        isEmpty,
        reason: '${mismatches.length} words collapse differently:\n'
            '${mismatches.take(15).join('\n')}',
      );
    });

    test('knows the same synonym edges, in the same order', () {
      final expected =
          (lexicalVectors['expansion'] as Map).cast<String, dynamic>();
      final actual = AnatomyTokenizer.expansionTable;

      expect(
        actual.keys.toList()..sort(),
        expected.keys.toList()..sort(),
        reason: 'the two synonym tables no longer cover the same words',
      );

      final mismatches = <String>[
        for (final entry in expected.entries)
          if (!_sameList(actual[entry.key] ?? const <String>[],
              (entry.value as List).cast<String>()))
            '${entry.key}: ${actual[entry.key]} != ${entry.value}',
      ];
      expect(
        mismatches,
        isEmpty,
        reason: '${mismatches.length} expansion lists differ:\n'
            '${mismatches.take(15).join('\n')}',
      );
    });

    test('turns every complaint the gate judges into the server\'s tokens', () {
      final cases =
          (lexicalVectors['query_tokens'] as List).cast<Map<String, dynamic>>();
      expect(cases.length, greaterThan(50));

      final mismatches = <String>[
        for (final recorded in cases)
          if (!_sameList(
            AnatomyTokenizer.tokenize(recorded['query'] as String),
            (recorded['tokens'] as List).cast<String>(),
          ))
            '"${recorded['query']}" -> '
                '${AnatomyTokenizer.tokenize(recorded['query'] as String)} '
                '!= ${recorded['tokens']}',
      ];
      expect(
        mismatches,
        isEmpty,
        reason: '${mismatches.length} queries tokenise differently:\n'
            '${mismatches.take(6).join('\n')}',
      );
    });

    test('the documents hold no invented words, only their own', () {
      // The server expanded synonyms into the corpus until P0-9 stopped it:
      // indexed translations inflate document frequency, weaken idf, and make
      // every monograph look like every other one. The offline index has to be
      // equally honest, or the two engines score different text.
      final corpusWords = AnatomyTokenizer.vocabulary;
      expect(corpusWords, isNotEmpty);
      for (final chunk in data.chunks.values) {
        final foreign =
            chunk.tokens.where((word) => !corpusWords.contains(word)).toList();
        expect(
          foreign,
          isEmpty,
          reason: '${chunk.id} is indexed on words the corpus never used: '
              '$foreign',
        );
      }
    });
  });
}

bool _sameList(List<String> a, List<String> b) =>
    a.length == b.length && a.asMap().entries.every((e) => e.value == b[e.key]);
