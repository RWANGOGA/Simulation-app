class TriageDraft {
  final String region;
  final String painType;
  final int severity;
  final String direction;
  final String depth;
  final double heartRate;
  final double spo2;
  final int patientId;
  final DateTime savedAt;

  const TriageDraft({
    required this.region,
    required this.painType,
    required this.severity,
    required this.direction,
    required this.depth,
    required this.heartRate,
    required this.spo2,
    required this.patientId,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'region': region,
        'painType': painType,
        'severity': severity,
        'direction': direction,
        'depth': depth,
        'heartRate': heartRate,
        'spo2': spo2,
        'patientId': patientId,
        'savedAt': savedAt.toIso8601String(),
      };

  factory TriageDraft.fromJson(Map<String, dynamic> json) => TriageDraft(
        region: json['region'] as String,
        painType: json['painType'] as String,
        severity: json['severity'] as int,
        direction: json['direction'] as String,
        depth: json['depth'] as String,
        heartRate: (json['heartRate'] as num).toDouble(),
        spo2: (json['spo2'] as num).toDouble(),
        patientId: json['patientId'] as int,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
