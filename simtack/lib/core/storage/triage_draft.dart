import '../../features/body_map/ui/pain_point.dart';

class TriageDraft {
  final List<PainPoint> painPoints;
  final int patientId;
  final String? patientCode;
  final DateTime savedAt;

  const TriageDraft({
    required this.painPoints,
    required this.patientId,
    this.patientCode,
    required this.savedAt,
  });

  Map<String, dynamic> toJson() => {
        'painPoints': painPoints.map((p) => p.toJson()).toList(),
        'patientId': patientId,
        if (patientCode != null) 'patientCode': patientCode,
        'savedAt': savedAt.toIso8601String(),
      };

  factory TriageDraft.fromJson(Map<String, dynamic> json) => TriageDraft(
        painPoints: (json['painPoints'] as List)
            .map((p) => PainPoint.fromJson(p as Map<String, dynamic>))
            .toList(),
        patientId: json['patientId'] as int,
        patientCode: json['patientCode'] as String?,
        savedAt: DateTime.parse(json['savedAt'] as String),
      );
}
