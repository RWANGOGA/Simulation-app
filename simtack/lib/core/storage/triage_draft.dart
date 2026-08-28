import '../../features/body_map/ui/pain_point.dart';

class TriageDraft {
  final List<PainPoint> painPoints;
  final double heartRate;
  final double spo2;
  final int patientId;
  final DateTime savedAt;

  const TriageDraft({
    required this.painPoints,
    required this.heartRate,
    required this.spo2,
    required this.patientId,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'painPoints': painPoints.map((p) => p.toJson()).toList(),
        'heartRate': heartRate,
        'spo2': spo2,
        'patientId': patientId,
        'savedAt': savedAt.toIso8601String(),
      };

  factory TriageDraft.fromJson(Map<String, dynamic> json) => TriageDraft(
        painPoints: (json['painPoints'] as List)
            .map((p) => PainPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        heartRate: (json['heartRate'] as num).toDouble(),
        spo2: (json['spo2'] as num).toDouble(),
        patientId: json['patientId'] as int,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}