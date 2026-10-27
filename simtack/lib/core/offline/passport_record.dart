/// What goes inside an encrypted passport, in the compact field names the byte
/// budget is measured against.
///
/// Deliberately not the whole [TriageResult]: a printed symbol carries the
/// essentials a station needs to act on, and every extra field is QR density a
/// phone camera has to resolve. The SHAP breakdown, the questionnaire answers
/// and the patient's own details stay on the server — a passport is a referral
/// card, not a copy of the record.
///
/// The field names are short for the same reason. They are documented here once
/// so the reader of a decrypted record is not guessing what `g` meant.
library;

import '../network/api_client.dart';
import 'qr_passport.dart';

/// One pain point as a passport carries it.
class PassportPoint {
  const PassportPoint({
    required this.bodyRegion,
    required this.severity,
    required this.painType,
    this.tier,
  });

  final String bodyRegion;
  final int severity;
  final String painType;

  /// The SATS category of this point. The visit's own category is derived from
  /// the most urgent point, which is how a station acts on a triage category.
  final String? tier;

  Map<String, dynamic> toMap() => {
        'r': bodyRegion,
        's': severity,
        'y': painType,
        if (tier != null) 'g': tier,
      };

  factory PassportPoint.fromMap(Map<String, dynamic> map) => PassportPoint(
        bodyRegion: (map['r'] as String?) ?? '',
        severity: (map['s'] as num?)?.toInt() ?? 0,
        painType: (map['y'] as String?) ?? '',
        tier: map['g'] as String?,
      );
}

/// The clinical essentials of one finished visit.
class PassportRecord {
  const PassportRecord({
    required this.patientCode,
    required this.points,
    this.visitId,
    this.createdAt,
    this.riskScore,
    this.tier,
    this.escalationLevel,
    this.escalationAction,
  });

  final String patientCode;
  final List<PassportPoint> points;
  final String? visitId;
  final String? createdAt;

  /// The visit's headline numbers: the highest score, the most urgent category,
  /// and the red-flag verdict that outranks both.
  final double? riskScore;
  final String? tier;
  final String? escalationLevel;
  final String? escalationAction;

  /// Builds the record from what the patient's device just submitted.
  ///
  /// The worst point wins on every axis rather than the last one submitted: a
  /// visit with one Red and three Greens is a Red patient, and a card that
  /// averaged them would send that patient to the back of the queue.
  factory PassportRecord.fromResults({
    required String patientCode,
    required List<TriageResult> results,
  }) {
    if (results.isEmpty) {
      return PassportRecord(patientCode: patientCode, points: const []);
    }

    final first = results.first;
    final worstScore =
        results.map((r) => r.riskScore ?? 0.0).reduce((a, b) => a >= b ? a : b);
    final worstTier = _worstTier(results);

    // The red-flag instruction the same way the category is chosen: the most
    // dangerous finding of the visit speaks for it, and nothing above routine is
    // ever dropped because another point was calmer.
    TriageEscalation? flag;
    for (final result in results) {
      final escalation = result.escalation;
      if (escalation == null) continue;
      if (escalation.isEmergency) {
        flag = escalation;
        break;
      }
      if (escalation.isUrgent && flag == null) flag = escalation;
    }

    return PassportRecord(
      patientCode: patientCode,
      visitId: first.visitId,
      createdAt: first.createdAt.toUtc().toIso8601String(),
      riskScore: worstScore,
      tier: worstTier,
      escalationLevel: flag?.level,
      escalationAction: flag?.action,
      points: [
        for (final r in results)
          PassportPoint(
            bodyRegion: r.bodyRegion,
            severity: r.severity,
            painType: r.painType,
            tier: r.tier?.tier,
          ),
      ],
    );
  }

  static String? _worstTier(List<TriageResult> results) {
    String? worst;
    for (final result in results) {
      final tier = result.tier?.tier;
      if (tier == null) continue;
      final rank = TriageTier.order.indexOf(tier);
      if (rank < 0) continue;
      if (worst == null || rank < TriageTier.order.indexOf(worst)) worst = tier;
    }
    return worst;
  }

  Map<String, dynamic> toMap() => {
        'c': patientCode,
        if (visitId != null) 'i': visitId,
        if (createdAt != null) 't': createdAt,
        if (riskScore != null) 'k': riskScore,
        if (tier != null) 'g': tier,
        if (escalationLevel != null) 'e': escalationLevel,
        if (escalationAction != null) 'a': escalationAction,
        'p': [for (final point in points) point.toMap()],
      };

  /// Tolerant by design: the passport is read by a device that may be a version
  /// behind the one that printed it, and a station with a printed card cannot
  /// update the app before it acts on what is written on it.
  factory PassportRecord.fromMap(Map<String, dynamic> map) {
    final raw = map['p'];
    return PassportRecord(
      patientCode: (map['c'] as String?) ?? '',
      visitId: map['i'] as String?,
      createdAt: map['t'] as String?,
      riskScore: (map['k'] as num?)?.toDouble(),
      tier: TriageTier.order.contains(map['g']) ? map['g'] as String : null,
      escalationLevel: map['e'] as String?,
      escalationAction: map['a'] as String?,
      points: [
        if (raw is List)
          for (final point in raw)
            if (point is Map<String, dynamic>) PassportPoint.fromMap(point),
      ],
    );
  }

  /// Encodes this record into the bytes a passport QR prints, falling back to
  /// the hosted report link when the visit is too large for a readable symbol
  /// (see [passportByteCeiling]).
  String seal(String phrase) => passportPayloadFor(
        record: toMap(),
        phrase: phrase,
        patientCode: patientCode,
      );
}
