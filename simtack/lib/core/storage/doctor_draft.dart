import '../network/api_client.dart';

/// A practitioner account saved locally for offline use.
/// Includes a local ID (negative = offline-only, positive = synced with server).
class DoctorDraft {
  /// Local identifier (negative = offline-only, positive = synced with server)
  final int localId;

  /// Server-assigned doctor ID (null if not yet synced)
  final int? doctorId;

  /// The doctor profile data
  final Doctor profile;

  /// Hashed password for local validation (NOT the plain password)
  final String passwordHash;

  /// When this draft was saved locally
  final DateTime savedAt;

  /// Whether this draft has been successfully synced to the server
  final bool isSynced;

  const DoctorDraft({
    required this.localId,
    this.doctorId,
    required this.profile,
    required this.passwordHash,
    required this.savedAt,
    this.isSynced = false,
  });

  /// Create a new offline-only draft (negative localId)
  factory DoctorDraft.createOffline({
    required Doctor profile,
    required String passwordHash,
  }) {
    return DoctorDraft(
      localId: -DateTime.now().millisecondsSinceEpoch,
      profile: profile,
      passwordHash: passwordHash,
      savedAt: DateTime.now(),
    );
  }

  /// Create a synced draft from server response
  factory DoctorDraft.fromSynced({
    required int doctorId,
    required Doctor profile,
    required String passwordHash,
    required DateTime savedAt,
  }) {
    return DoctorDraft(
      localId: doctorId, // Use server ID as localId once synced
      doctorId: doctorId,
      profile: profile,
      passwordHash: passwordHash,
      savedAt: savedAt,
      isSynced: true,
    );
  }

  Map<String, dynamic> toJson() => {
        'localId': localId,
        if (doctorId != null) 'doctorId': doctorId,
        'profile': {
          'id': profile.id,
          'email': profile.email,
          'full_name': profile.fullName,
          'is_active': profile.isActive,
          'role': profile.role,
          'license_number': profile.licenseNumber,
          'phone': profile.phone,
          'hospital_name': profile.hospitalName,
        },
        'passwordHash': passwordHash,
        'savedAt': savedAt.toIso8601String(),
        'isSynced': isSynced,
      };

  factory DoctorDraft.fromJson(Map<String, dynamic> json) => DoctorDraft(
        localId: json['localId'] as int,
        doctorId: json['doctorId'] as int?,
        profile: Doctor.fromJson(json['profile'] as Map<String, dynamic>),
        passwordHash: json['passwordHash'] as String,
        savedAt: DateTime.parse(json['savedAt'] as String),
        isSynced: json['isSynced'] as bool? ?? false,
      );

  /// Copy with updated fields
  DoctorDraft copyWith({
    int? localId,
    int? doctorId,
    Doctor? profile,
    String? passwordHash,
    DateTime? savedAt,
    bool? isSynced,
  }) {
    return DoctorDraft(
      localId: localId ?? this.localId,
      doctorId: doctorId ?? this.doctorId,
      profile: profile ?? this.profile,
      passwordHash: passwordHash ?? this.passwordHash,
      savedAt: savedAt ?? this.savedAt,
      isSynced: isSynced ?? this.isSynced,
    );
  }

  /// Simple hash for local password validation (not cryptographically secure)
  /// In production, use proper bcrypt/argon2, but this works for offline demo
  static String hash(String password) {
    int hash = 0;
    for (int i = 0; i < password.length; i++) {
      hash = (hash * 31 + password.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }

  /// Verify a plain password against stored hash
  bool verifyPassword(String password) {
    return passwordHash == hash(password);
  }
}