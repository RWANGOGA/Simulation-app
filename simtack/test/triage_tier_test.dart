import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/clinical/clinical_data.dart';
import 'package:simtack/core/clinical/risk_engine.dart';
import 'package:simtack/core/network/api_client.dart';

import 'support/clinical_assets.dart';

/// The four SATS categories, on the device.
///
/// `test/clinical_parity_test.dart` proves the offline engine reproduces every
/// category the server recorded in the golden fixture. This file pins the same
/// rules as a readable table, because the two things that would silently move a
/// borderline patient one category — an inclusive anchor and a red flag that
/// outranks a calm score — are the kind of thing a paragraph in the paper gets
/// wrong and a table of numbers does not.
///
/// The anchors mirror `Backend-fastapi/tests/test_triage_tier.py` exactly; if the
/// two tables ever disagree, the parity test goes red first.
void main() {
  late RiskEngine engine;

  setUpAll(() async {
    final data = await loadClinicalDataForTest();
    engine = RiskEngine(data);
  });

  tearDownAll(() => ClinicalData.resetForTest());

  TriageInput point({
    String bodyRegion = 'Left Leg',
    String painType = 'Dull',
    int severity = 3,
    double? heartRate,
  }) =>
      TriageInput(
        bodyRegion: bodyRegion,
        painType: painType,
        severity: severity,
        heartRate: heartRate,
      );

  String tierOf(TriageInput input, double risk) =>
      engine.triageTier(input, risk: risk)['tier'] as String;

  group('the anchors', () {
    // Both score anchors are inclusive: 0.40 is Urgent and 0.70 in a region whose
    // referred pain matters is Very Urgent.
    const anchors = <List<Object?>>[
      [0.0, 'Left Leg', 'Dull', 3, null, 'green'],
      [0.39, 'Left Leg', 'Dull', 3, null, 'green'],
      [0.40, 'Left Leg', 'Dull', 3, null, 'yellow'],
      [0.69, 'Left Leg', 'Dull', 3, null, 'yellow'],
      // 0.70 on its own is not enough for orange: a bad total for a leg is not a
      // very urgent patient until the region says it is.
      [0.70, 'Left Leg', 'Dull', 3, null, 'yellow'],
      [0.70, 'Chest / Heart', 'Dull', 3, null, 'orange'],
      [1.0, 'Abdomen (Upper)', 'Dull', 3, null, 'orange'],
      // An urgent red flag outranks a score that has not reached 0.70.
      [0.50, 'Left Leg', 'Dull', 10, null, 'orange'],
      [0.20, 'Left Leg', 'Dull', 3, 110.0, 'orange'],
      // An emergency flag outranks any score, including a calm one.
      [0.05, 'Chest / Heart', 'Crushing', 4, null, 'red'],
      [0.20, 'Left Leg', 'Dull', 3, 130.0, 'red'],
      [0.20, 'Left Leg', 'Dull', 3, 45.0, 'red'],
      [1.0, 'Headache / Cranial', 'Dull', 10, null, 'red'],
    ];

    for (final anchor in anchors) {
      final risk = anchor[0] as double;
      final heartRate = anchor[4] as double?;
      final expected = anchor[5] as String;
      test('${anchor[1]} ${anchor[3]}/10 at $risk is $expected', () {
        expect(
          tierOf(
            point(
              bodyRegion: anchor[1] as String,
              painType: anchor[2] as String,
              severity: anchor[3] as int,
              heartRate: heartRate,
            ),
            risk,
          ),
          expected,
        );
      });
    }
  });

  test('the critical rates are exclusive, not rounded', () {
    // "< 50" and "> 120" decide the score bump, the red flag and the tier from the
    // same two numbers, so a `>=` in one of them would move a category at exactly
    // the rate a triage form is likely to record.
    expect(tierOf(point(heartRate: 50.0), 0.45), 'yellow');
    expect(tierOf(point(heartRate: 49.9), 0.45), 'red');
    // 120 is high without being critical, which is still an urgent flag.
    expect(tierOf(point(heartRate: 120.0), 0.45), 'orange');
    expect(tierOf(point(heartRate: 120.1), 0.45), 'red');
  });

  test('a zero heart rate is no measurement at all', () {
    // The field is reachable from a stored session, and a failed capture reported
    // as 0 bpm used to add the critical bump to the score while the tier refused
    // to call it an emergency. One input, two answers, in the same record.
    final withZero = engine.compute(point(heartRate: 0.0));
    final withoutAny = engine.compute(point());

    expect(withZero.risk, withoutAny.risk);
    expect(engine.escalation(point(heartRate: 0.0))['level'], 'routine');
    expect(tierOf(point(heartRate: 0.0), withZero.risk), 'green');
  });

  test('every category names the rules that decided it', () {
    // `decided_by` is what makes a category disputable: a clinician who disagrees
    // with `chest_pain_crushing` can say so about a named rule rather than about
    // a colour.
    const inputs = <List<Object?>>[
      ['Left Leg', 'Dull', 3, null],
      ['Chest / Heart', 'Crushing', 4, null],
      ['Headache / Cranial', 'Dull', 3, 130.0],
      ['Left Leg', 'Sharp', 10, null],
    ];

    for (final row in inputs) {
      final result = engine.triageTier(
        point(
          bodyRegion: row[0] as String,
          painType: row[1] as String,
          severity: row[2] as int,
          heartRate: row[3] as double?,
        ),
        risk: 0.55,
      );
      final codes = (result['decided_by'] as List).cast<String>();

      expect(codes, isNotEmpty, reason: '$row decided a category by nothing');
      expect(
        codes,
        everyElement(anyOf(
          contains('score_'),
          contains('heart_rate'),
          contains('pain_'),
          contains('chest_'),
          contains('radiat'),
        )),
        reason: '$row produced codes that name no rule: $codes',
      );
      expect(
        result['category'],
        ClinicalData.instance.rules.tierCategories[result['tier']],
      );
      expect(result['scale'], 'SATS');
    }
  });

  test('deriving a category never moves the score beside it', () {
    final input = point(bodyRegion: 'Chest / Heart', painType: 'Crushing');
    final before = engine.compute(input).risk;

    engine.triageTier(input, risk: before);

    expect(engine.compute(input).risk, before);
  });

  group('TriageTier on the wire', () {
    test('the scale runs most urgent first', () {
      // Clients draw this as a strip and the agreement weights read it as an
      // ordinal axis, so the order is part of the contract rather than a detail.
      expect(TriageTier.order, const ['red', 'orange', 'yellow', 'green']);
    });

    test('parses the shape the server sends', () {
      final tier = TriageTier.tryParse(const {
        'tier': 'orange',
        'scale': 'SATS',
        'category': 'very_urgent',
        'decided_by': ['pain_maximum'],
      });

      expect(tier, isNotNull);
      expect(tier!.tier, TriageTier.orange);
      expect(tier.category, 'very_urgent');
      expect(tier.decidedBy, const ['pain_maximum']);
      expect(tier.toJson()['tier'], 'orange');
    });

    test('refuses a category the scale does not define', () {
      // A payload from an older backend, or a hand-edited offline row, must not be
      // rendered as a triage decision with an invented colour beside it.
      for (final raw in [
        null,
        'black',
        'RED',
        '',
        const {'scale': 'SATS'},
        const {'tier': 'purple', 'scale': 'SATS'},
      ]) {
        expect(TriageTier.tryParse(raw), isNull, reason: '$raw parsed anyway');
      }
    });

    test('tolerates a tier sent without its explanation', () {
      final tier =
          TriageTier.tryParse(const {'tier': 'green', 'scale': 'SATS'});

      expect(tier, isNotNull);
      expect(tier!.decidedBy, isEmpty);
    });
  });
}
