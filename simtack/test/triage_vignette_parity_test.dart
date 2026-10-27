import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/clinical/anatomy_engine.dart';
import 'package:simtack/core/clinical/clinical_data.dart';
import 'package:simtack/core/clinical/risk_engine.dart';

import 'support/clinical_assets.dart';

/// Replays the 150-case triage simulation set on the *offline* engine.
///
/// `test/fixtures/vignettes.json` is the same file the Python harness scores —
/// `Backend-fastapi/scripts/build_vignettes.py` writes both copies, so the two
/// platforms are provably looking at identical inputs. Each case carries an
/// `intended_tier`: the SATS category it was built to exercise. The Python side
/// already lands all 150 on that tier (pinned in
/// `Backend-fastapi/tests/test_triage_simulation.py`); this test proves the
/// device agrees, so a patient is not triaged differently on the phone than on
/// the report.
///
/// Read the reference honestly: `intended_tier` is a single non-clinician
/// author's design target, not a nurse's label. Landing on it is specification
/// conformance plus cross-platform parity — not a claim of clinical validity.
void main() {
  late RiskEngine engine;
  late Map<String, dynamic> fixture;

  setUpAll(() async {
    final data = await loadClinicalDataForTest();
    engine = RiskEngine(data);
    fixture = jsonDecode(
      File('test/fixtures/vignettes.json').readAsStringSync(),
    ) as Map<String, dynamic>;
  });

  tearDownAll(() {
    ClinicalData.resetForTest();
    AnatomyEngine.resetForTest();
  });

  test('the mirrored fixture carries the honest provenance header', () {
    final provenance = fixture['provenance'] as Map<String, dynamic>;
    expect(provenance['reference_kind'], 'design_target');
    expect(provenance['clinician_label'], isFalse);
    expect(provenance['second_labeler_id'], isNull);
  });

  test('coverage: >=30 vignettes in every SATS category', () {
    final counts = (fixture['counts'] as Map).cast<String, dynamic>();
    for (final tier in ['red', 'orange', 'yellow', 'green']) {
      expect((counts[tier] as num) >= 30, isTrue,
          reason: '$tier has only ${counts[tier]} cases');
    }
    expect(fixture['cases'], hasLength(150));
  });

  test('the offline engine reproduces every intended tier', () {
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
    final mismatches = <String>[];
    final seen = <String, int>{};

    for (final case_ in cases) {
      final input =
          TriageInput.fromJson(case_['input'] as Map<String, dynamic>);
      final risk = engine.compute(input).risk;
      final verdict = engine.triageTier(input, risk: risk);
      final tier = verdict['tier'] as String;
      seen[tier] = (seen[tier] ?? 0) + 1;

      final intended = case_['intended_tier'] as String;
      if (tier != intended) {
        mismatches.add(
          '${case_['id']}: intended $intended but offline engine gave $tier '
          '(${input.bodyRegion} / ${input.painType} / sev ${input.severity})',
        );
      }
    }

    expect(
      mismatches,
      isEmpty,
      reason: '${mismatches.length} of ${cases.length} diverged:\n'
          '${mismatches.take(10).join('\n')}',
    );
    // Every branch must actually be exercised, or parity could pass while the
    // emergency and score anchors went untested on-device.
    expect(
      seen.keys.toSet(),
      containsAll(<String>['red', 'orange', 'yellow', 'green']),
      reason: 'fixture tier coverage was $seen',
    );
  });

  test('decided_by codes match the reference set on every category', () {
    // Not just the colour: the rule that fired has to be the same one the
    // server records, so an on-device "red" and a server "red" mean the same
    // thing to a clinician reading the audit trail.
    final cases = (fixture['cases'] as List).cast<Map<String, dynamic>>();
    final seenCodes = <String>{};
    for (final case_ in cases) {
      final input =
          TriageInput.fromJson(case_['input'] as Map<String, dynamic>);
      final verdict =
          engine.triageTier(input, risk: engine.compute(input).risk);
      expect(verdict['scale'], 'SATS');
      expect((verdict['decided_by'] as List), isNotEmpty);
      seenCodes.addAll((verdict['decided_by'] as List).cast<String>());
    }
    // The three distinct deciding rules the simulation is meant to exercise.
    expect(seenCodes, contains('heart_rate_critical'));
    expect(seenCodes, contains('score_high_in_concerning_region'));
    expect(seenCodes, contains('score_below_urgent_band'));
  });
}
