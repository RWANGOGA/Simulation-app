import '../models/patient_profile.dart';

/// A patient profile saved locally for offline use.
/// Includes a local ID (negative to distinguish from server IDs) and sync status.
class PatientDraft {
  /// Local identifier (negative = offline-only, positive = synced with server)
  final int localId;
  
  /// Server-assigned patient ID (null if not yet synced)
  final int? patientId;
  
  /// Server-assigned anonymous code (null if not yet synced)
  final String? patientCode;
  
  /// The patient profile data
  final PatientProfile profile;
  
  /// When this draft was saved locally
  final DateTime savedAt;
  
  /// Whether this draft has been successfully synced to the server
  final bool isSynced;

  const PatientDraft({
    required this.localId,
    this.patientId,
    this.patientCode,
    required this.profile,
    required this.savedAt,
    this.isSynced = false,
  });

  /// Create a new offline-only draft (negative localId)
  factory PatientDraft.createOffline(PatientProfile profile) {
    return PatientDraft(
      localId: -DateTime.now().millisecondsSinceEpoch,
      profile: profile,
      savedAt: DateTime.now(),
    );
  }

  /// Create a synced draft from server response
  factory PatientDraft.fromSynced({
    required int patientId,
    required String patientCode,
    required PatientProfile profile,
    required DateTime savedAt,
  }) {
    return PatientDraft(
      localId: patientId, // Use server ID as localId once synced
      patientId: patientId,
      patientCode: patientCode,
      profile: profile,
      savedAt: savedAt,
      isSynced: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'localId': localId,
        if (patientId != null) 'patientId': patientId,
        if (patientCode != null) 'patientCode': patientCode,
        'profile': profile.toJson(),
        'savedAt': savedAt.toIso8601String(),
        'isSynced': isSynced,
      };

  factory PatientDraft.fromJson(Map<String, dynamic> json) => PatientDraft(
        localId: json['localId'] as int,
        patientId: json['patientId'] as int?,
        patientCode: json['patientCode'] as String?,
        profile: PatientProfile.fromJson(json['profile'] as Map<String, dynamic>),
        savedAt: DateTime.parse(json['savedAt'] as String),
        isSynced: json['isSynced'] as bool? ?? false,
      );

  /// Copy with updated fields
  PatientDraft copyWith({
    int? localId,
    int? patientId,
    String? patientCode,
    PatientProfile? profile,
    DateTime? savedAt,
    bool? isSynced,
  }) {
    return PatientDraft(
      localId: localId ?? this.localId,
      patientId: patientId ?? this.patientId,
      patientCode: patientCode ?? this.patientCode,
      profile: profile ?? this.profile,
      savedAt: savedAt ?? this.savedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }
}