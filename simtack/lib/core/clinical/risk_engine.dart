import 'dart:math' as math;

import 'clinical_data.dart';

/// The clinical fields one pain point carries. Mirrors `TriageCreate` on the
/// backend, minus the fields that never reach the scorer.
class TriageInput {
  const TriageInput({
    required this.bodyRegion,
    required this.painType,
    required this.severity,
    this.direction,
    this.heartRate,
    this.patientWeight,
    this.patientHeight,
    this.siblingRegions = const [],
  });

  final String bodyRegion;
  final String painType;
  final int severity;
  final String? direction;
  final double? heartRate;
  final double? patientWeight;
  final double? patientHeight;

  /// Body regions of the other pain points submitted in the same visit, so the
  /// score can reflect real relationships between them.
  final List<String> siblingRegions;

  factory TriageInput.fromJson(Map<String, dynamic> json) => TriageInput(
        bodyRegion: (json['body_region'] as String?) ?? '',
        painType: (json['pain_type'] as String?) ?? '',
        severity: (json['severity'] as num?)?.toInt() ?? 0,
        direction: json['direction'] as String?,
        heartRate: (json['heart_rate'] as num?)?.toDouble(),
        patientWeight: (json['patient_weight'] as num?)?.toDouble(),
        patientHeight: (json['patient_height'] as num?)?.toDouble(),
        siblingRegions: ((json['siblings'] as List?) ?? const [])
            .map((e) => e.toString())
            .toList(),
      );

  Map<String, dynamic> toJson() => {
        'body_region': bodyRegion,
        'pain_type': painType,
        'severity': severity,
        'direction': direction,
        'heart_rate': heartRate,
        'patient_weight': patientWeight,
        'patient_height': patientHeight,
        'siblings': siblingRegions,
      };
}

/// One line of the score's audit trail.
class RiskContribution {
  const RiskContribution({
    required this.factor,
    required this.shap,
    this.impact,
  });

  final String factor;
  final double shap;

  /// '+' / '-' as the server emits it. Null for the connectivity factors,
  /// which the Python implementation appends without one — kept null rather
  /// than invented so stored explanations stay identical to the server's.
  final String? impact;

  Map<String, dynamic> toJson() => {
        'factor': factor,
        'shap': shap,
        if (impact != null) 'impact': impact,
      };
}

class RiskAssessment {
  const RiskAssessment({required this.risk, required this.contributions});

  final double risk;
  final List<RiskContribution> contributions;

  String get level => RiskEngine.levelFor(risk);
  bool get isHigh => level == RiskEngine.high;
  bool get isMedium => level == RiskEngine.medium;
}

class _Finding {
  const _Finding(this.level, this.code, this.detail);

  final String level;
  final String code;
  final String detail;
}

/// Port of `app/services/triage_service.py`.
///
/// Two things this deliberately does NOT do: it does not invent weights of its
/// own (everything comes from the generated rule table), and it does not change
/// the rounding or the ordering the server uses. `test/clinical_parity_test.dart`
/// replays ~400 recorded cases against it, so a mismatch is a test failure
/// rather than a patient seeing one number offline and another on the report.
class RiskEngine {
  RiskEngine([ClinicalData? data]) : _data = data ?? ClinicalData.instance;

  final ClinicalData _data;

  static const String high = 'high';
  static const String medium = 'medium';
  static const String low = 'low';

  RiskRules get _rules => _data.rules;

  /// Weighted, clamped score plus its contributions, in the same order and
  /// with the same rounding as the server.
  RiskAssessment compute(TriageInput input) {
    final rules = _rules;
    final contributions = <RiskContribution>[];

    final severityShare =
        _round2((input.severity / 10.0) * rules.severityWeight);
    contributions.add(RiskContribution(
      factor: 'Severity ${input.severity}/10',
      shap: severityShare,
      impact: severityShare >= 0 ? '+' : '-',
    ));

    final regionShare = _regionWeight(input.bodyRegion);
    contributions.add(RiskContribution(
      factor: 'Region: ${input.bodyRegion}',
      shap: regionShare,
      impact: regionShare >= 0 ? '+' : '-',
    ));

    final painShare = _painTypeWeight(input.painType);
    contributions.add(RiskContribution(
      factor: 'Pain type: ${input.painType}',
      shap: painShare,
      impact: painShare >= 0 ? '+' : '-',
    ));

    final heartRateShare = _heartRateContribution(input.heartRate);
    if (heartRateShare != 0) {
      contributions.add(RiskContribution(
        factor: 'Heart rate ${_pyFloat(input.heartRate!)} bpm',
        shap: heartRateShare,
        impact: heartRateShare >= 0 ? '+' : '-',
      ));
    }

    if (input.siblingRegions.isNotEmpty) {
      contributions.addAll(
        _connectivityContributions(input.bodyRegion, input.siblingRegions),
      );
    }

    final bmiResult =
        _bmiContribution(input.patientWeight, input.patientHeight);
    if (bmiResult.contribution != 0) {
      contributions.add(RiskContribution(
        factor: 'BMI ${bmiResult.bmi!.toStringAsFixed(1)} (weight/height)',
        shap: bmiResult.contribution,
        impact: bmiResult.contribution >= 0 ? '+' : '-',
      ));
    }

    var total = 0.0;
    for (final contribution in contributions) {
      total += contribution.shap;
    }
    final raw = _round2(total);
    final risk = math.min(1.0, raw);

    // The cap is itself a factor. Clamping the score while returning the
    // unclamped weights made the breakdown fail to add up to the number it
    // explains - 1.30 of factors beside `risk_score: 1.00` - which is roughly one
    // triage in five. Recorded rather than dropped, because the 0..1 range is what
    // the bands, the bars and every stored row assume, and because how much was
    // discarded is clinically meaningful pressure.
    if (risk < raw) {
      contributions.add(RiskContribution(
        factor:
            'Score capped at 1.00 (findings summed to ${raw.toStringAsFixed(2)})',
        shap: _round2(risk - raw),
        impact: '-',
      ));
    }

    // Python sorts with reverse=True on a stable sort, so equal weights keep
    // the order they were added in. List.sort is not stable in Dart, hence the
    // explicit index tiebreak.
    final indexed = contributions.indexed.toList()
      ..sort((a, b) {
        final byWeight = b.$2.shap.compareTo(a.$2.shap);
        return byWeight != 0 ? byWeight : a.$1.compareTo(b.$1);
      });

    return RiskAssessment(
      risk: risk,
      contributions: [for (final entry in indexed) entry.$2],
    );
  }

  double _regionWeight(String bodyRegion) {
    final region = bodyRegion.toLowerCase();
    for (final rule in _rules.regionRules) {
      if (rule.keywords.any(region.contains)) {
        final leftWeight = rule.leftWeight;
        if (leftWeight != null && region.contains('left')) return leftWeight;
        return rule.weight;
      }
    }
    return _rules.defaultRegionWeight;
  }

  double _painTypeWeight(String painType) =>
      _rules.painTypeWeights[painType.trim().toLowerCase()] ??
      _rules.defaultPainTypeWeight;

  double _heartRateContribution(double? heartRate) {
    if (heartRate == null) return 0.0;
    final rules = _rules;
    if (heartRate > rules.heartRateCriticalAbove ||
        heartRate < rules.heartRateCriticalBelow) {
      return rules.heartRateCriticalBump;
    }
    if (heartRate > rules.heartRateHighAbove) return rules.heartRateHighBump;
    return 0.0;
  }

  _BmiResult _bmiContribution(double? weightKg, double? heightCm) {
    if (weightKg == null ||
        weightKg == 0 ||
        heightCm == null ||
        heightCm == 0 ||
        heightCm < 0) {
      return const _BmiResult(0.0, null);
    }
    final ratio = heightCm / 100.0;
    final bmi = weightKg / (ratio * ratio);
    final bump = (bmi >= _rules.bmiObeseAt || bmi < _rules.bmiUnderweightBelow)
        ? _rules.bmiBump
        : 0.0;
    return _BmiResult(bump, bmi);
  }

  List<RiskContribution> _connectivityContributions(
    String region,
    List<String> siblingRegions,
  ) {
    final contributions = <RiskContribution>[];
    final seen = <String>{};
    final connections = _data.graph[region];
    if (connections == null) return contributions;

    for (final other in siblingRegions) {
      if (other == region || seen.contains(other)) continue;
      seen.add(other);

      BodyConnection? match;
      for (final connection in connections) {
        if (connection.region == other) {
          match = connection;
          break;
        }
      }
      if (match == null) continue;

      contributions.add(RiskContribution(
        factor: 'Connected to reported $other pain: ${match.note}',
        shap: _rules.concernBumps[match.concern] ?? 0.0,
      ));
    }
    return contributions;
  }

  /// Band thresholds come from the rule table, with the documented defaults as
  /// a fallback so a caller that scores before the assets load still gets the
  /// right band instead of a crash.
  static String levelFor(double risk) {
    final rules = ClinicalData.isLoaded ? ClinicalData.instance.rules : null;
    final highBand = rules?.highBand ?? 0.7;
    final mediumBand = rules?.mediumBand ?? 0.4;
    if (risk >= highBand) return high;
    if (risk >= mediumBand) return medium;
    return low;
  }

  /// Red-flag screen, ported rule for rule from `escalation_for`.
  ///
  /// Runs beside the score rather than replacing it, and reports every finding
  /// that fired so a clinician can audit the verdict.
  Map<String, dynamic> escalation(TriageInput input) {
    final rules = _rules;
    final region = input.bodyRegion.trim().toLowerCase();
    final painType = input.painType.trim().toLowerCase();
    final direction = (input.direction ?? '').trim().toLowerCase();
    final severity = input.severity;

    final isChest = region.contains('chest') || region.contains('heart');
    final isHead = region.contains('head') || region.contains('cranial');

    final findings = <_Finding>[];

    if (isChest) {
      if (rules.concerningChestPainTypes.any(painType.contains)) {
        findings.add(_Finding(
          rules.emergencyLevel,
          'chest_pain_crushing',
          '${_titleCase(painType)} chest pain',
        ));
      }
      if (direction.contains('radiat')) {
        findings.add(_Finding(
          rules.emergencyLevel,
          'chest_pain_radiating',
          'Chest pain that spreads to another area',
        ));
      }
      if (severity >= 8) {
        findings.add(_Finding(
          rules.emergencyLevel,
          'chest_pain_severe',
          'Chest pain rated $severity/10',
        ));
      }
    }

    final heartRate = input.heartRate;
    if (heartRate != null && heartRate != 0) {
      final rate = heartRate.toDouble();
      if (rate > rules.heartRateCriticalAbove ||
          rate < rules.heartRateCriticalBelow) {
        findings.add(_Finding(
          rules.emergencyLevel,
          'heart_rate_critical',
          'Heart rate ${_pyGeneral(rate)} bpm',
        ));
      } else if (rate > rules.heartRateHighAbove) {
        findings.add(_Finding(
          rules.urgentLevel,
          'heart_rate_high',
          'Heart rate ${_pyGeneral(rate)} bpm',
        ));
      }
    }

    if (severity >= 10) {
      if (rules.highConcernRegionKeywords.any(region.contains)) {
        findings.add(_Finding(
          rules.emergencyLevel,
          'pain_maximum_high_concern_region',
          '${region.isEmpty ? 'Reported region' : region} rated 10/10',
        ));
      } else {
        findings.add(_Finding(
          rules.urgentLevel,
          'pain_maximum',
          'Pain rated 10/10',
        ));
      }
    } else if (severity >= 8 && isHead) {
      findings.add(_Finding(
        rules.urgentLevel,
        'head_pain_severe',
        'Head pain rated $severity/10',
      ));
    }

    // Emergencies first, each group keeping the order the rules fired in.
    final ordered = [
      ...findings.where((f) => f.level == rules.emergencyLevel),
      ...findings.where((f) => f.level != rules.emergencyLevel),
    ];

    var level = rules.routineLevel;
    if (findings.any((f) => f.level == rules.emergencyLevel)) {
      level = rules.emergencyLevel;
    } else if (findings.isNotEmpty) {
      level = rules.urgentLevel;
    }

    return {
      'level': level,
      'action': rules.actionByLevel[level] ?? '',
      'triggers': [
        for (final finding in ordered)
          {'code': finding.code, 'detail': finding.detail},
      ],
    };
  }

  static bool isEmergency(Map<String, dynamic> escalation) {
    final level = ClinicalData.isLoaded
        ? ClinicalData.instance.rules.emergencyLevel
        : 'emergency';
    return escalation['level'] == level;
  }

  static bool isUrgent(Map<String, dynamic> escalation) {
    final level = ClinicalData.isLoaded
        ? ClinicalData.instance.rules.urgentLevel
        : 'urgent';
    return escalation['level'] == level;
  }
}

class _BmiResult {
  const _BmiResult(this.contribution, this.bmi);

  final double contribution;
  final double? bmi;
}

/// Python's `round(x, 2)`: both platforms then round the same IEEE double to
/// two decimals. Half-way ties are impossible for the weights involved (all
/// multiples of 0.01), so half-up here matches half-even there.
double _round2(double value) {
  if (!value.isFinite) return value;
  return (value * 100).roundToDouble() / 100;
}

/// Python's `str()` of a float: 121.0 -> "121.0", 121.5 -> "121.5".
String _pyFloat(double value) => value.toString();

/// Python's `f"{value:g}"`: drops the trailing ".0" for whole numbers.
String _pyGeneral(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e16) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// Python's `str.title()`: every letter run starts upper-case, the rest lower.
String _titleCase(String value) {
  final lowered = value.toLowerCase();
  return lowered.replaceAllMapped(
    RegExp(r'(^|[^a-z0-9])([a-z])'),
    (match) => '${match[1]}${match[2]!.toUpperCase()}',
  );
}
