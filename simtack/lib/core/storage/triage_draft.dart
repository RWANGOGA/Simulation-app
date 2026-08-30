import '../../features/body_map/ui/pain_point.dart';

class TriageDraft {
  final List<PainPoint> painPoints;
  final int patientId;
  final DateTime savedAt;

  const TriageDraft({
    required this.painPoints,
    required this.patientId,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'painPoints': painPoints.map((p) => p.toJson()).toList(),
        'patientId': patientId,
        'savedAt': savedAt.toIso8601String(),
      };

  factory TriageDraft.fromJson(Map<String, dynamic> json) => TriageDraft(
        painPoints: (json['painPoints'] as List)
            .map((p) => PainPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        patientId: json['patientId'] as int,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}