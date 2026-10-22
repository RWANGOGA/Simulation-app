import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

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

  /// When the *server* last confirmed this account — a successful sign-in,
  /// registration, or `/auth/me`.
  ///
  /// Null for caches written before this was recorded, and for accounts created
  /// offline that never reached the server. Both fall back to [savedAt] in
  /// [trustAnchor], so upgrading does not sign anybody out on day one.
  final DateTime? lastVerifiedAt;

  /// Whether this draft has been successfully synced to the server
  final bool isSynced;

  /// Whether the stored profile actually records the server's approval
  /// decision.
  ///
  /// Approval and access level used to be dropped on the way to disk, so every
  /// cached profile reloaded as "not approved". Caches written since then carry
  /// the flag; an older row has no opinion, and offline sign-in treats "no
  /// opinion" as the old behaviour rather than inventing a rejection.
  final bool approvalRecorded;

  /// Profile fields edited on this device that the server has not accepted yet.
  ///
  /// Non-null means the copy here is *newer* than the server's, so the next
  /// `/auth/me` must refresh only the trust fields and leave the profile alone —
  /// otherwise an edit made in a clinic with no signal would be silently
  /// reverted the moment the device reconnected.
  final Map<String, dynamic>? pendingProfile;

  const DoctorDraft({
    required this.localId,
    this.doctorId,
    required this.profile,
    required this.passwordHash,
    required this.savedAt,
    this.isSynced = false,
    this.lastVerifiedAt,
    this.approvalRecorded = true,
    this.pendingProfile,
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
    DateTime? lastVerifiedAt,
  }) {
    return DoctorDraft(
      localId: doctorId, // Use server ID as localId once synced
      doctorId: doctorId,
      profile: profile,
      passwordHash: passwordHash,
      savedAt: savedAt,
      isSynced: true,
      lastVerifiedAt: lastVerifiedAt,
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
          // Approval and access level were the two fields this map used to
          // drop, which silently turned every cached practitioner back into an
          // unapproved one on reload.
          'is_approved': profile.isApproved,
          'access_level': profile.accessLevel,
          'role': profile.role,
          'license_number': profile.licenseNumber,
          'phone': profile.phone,
          'hospital_name': profile.hospitalName,
        },
        'passwordHash': passwordHash,
        'savedAt': savedAt.toIso8601String(),
        'isSynced': isSynced,
        if (lastVerifiedAt != null)
          'lastVerifiedAt': lastVerifiedAt!.toIso8601String(),
        if (pendingProfile != null) 'pendingProfile': pendingProfile,
      };

  factory DoctorDraft.fromJson(Map<String, dynamic> json) {
    final rawProfile = json['profile'] as Map<String, dynamic>;
    return DoctorDraft(
      localId: json['localId'] as int,
      doctorId: json['doctorId'] as int?,
      profile: Doctor.fromJson(rawProfile),
      passwordHash: json['passwordHash'] as String,
      savedAt: DateTime.parse(json['savedAt'] as String),
      isSynced: json['isSynced'] as bool? ?? false,
      lastVerifiedAt: json['lastVerifiedAt'] == null
          ? null
          : DateTime.parse(json['lastVerifiedAt'] as String),
      // Absent means the row predates approval being persisted, not that the
      // account was rejected.
      approvalRecorded: rawProfile.containsKey('is_approved'),
      pendingProfile:
          (json['pendingProfile'] as Map?)?.cast<String, dynamic>(),
    );
  }

  /// The moment this device's copy was last backed by the server. Anything
  /// older than the trust window must be re-confirmed online.
  DateTime get trustAnchor => lastVerifiedAt ?? savedAt;

  /// True for an account this device created because no server could be
  /// reached. It has never existed anywhere else and never will: only a hash of
  /// the password is kept, so a server copy could not be signed in to.
  ///
  /// That makes the device the authority for it, which is why
  /// [AuthService._cachedDoctor] skips the approval gate and the trust window
  /// for these — both exist to bound what a *copy of a server account* is
  /// allowed to do, and there is no copy here. It also means such an account can
  /// never be mistaken for one the server knows about.
  bool get isDeviceAccount => !isSynced;

  bool isTrustExpired(DateTime now, Duration window) =>
      now.difference(trustAnchor) > window;

  /// Copy with updated fields
  DoctorDraft copyWith({
    int? localId,
    int? doctorId,
    Doctor? profile,
    String? passwordHash,
    DateTime? savedAt,
    bool? isSynced,
    DateTime? lastVerifiedAt,
    bool? approvalRecorded,
    Map<String, dynamic>? pendingProfile,
    bool clearPendingProfile = false,
  }) {
    return DoctorDraft(
      localId: localId ?? this.localId,
      doctorId: doctorId ?? this.doctorId,
      profile: profile ?? this.profile,
      passwordHash: passwordHash ?? this.passwordHash,
      savedAt: savedAt ?? this.savedAt,
      isSynced: isSynced ?? this.isSynced,
      lastVerifiedAt: lastVerifiedAt ?? this.lastVerifiedAt,
      approvalRecorded: approvalRecorded ?? this.approvalRecorded,
      // `null` here has to mean "unchanged" like every other field, so clearing
      // needs its own flag.
      pendingProfile:
          clearPendingProfile ? null : (pendingProfile ?? this.pendingProfile),
    );
  }

  /// Marker for the current hash format. A value without it is a legacy hash
  /// and is upgraded on the next sign-in that has the plaintext in hand.
  static const _hashPrefix = 'pbkdf2-sha256';
  static const _hashIterations = 20000;

  /// Salted, iterated password hash (PBKDF2-HMAC-SHA256).
  ///
  /// This used to be a single unsalted 32-bit rolling hash held in plain shared
  /// preferences: two different passwords collide by construction under that
  /// scheme, and the stored value carried nothing binding it to an account, so
  /// anything able to read the file could sign in offline without the password.
  /// Offline sign-in unlocks the same patient data as an online one, so the bar
  /// is "cannot be derived from the file on the device".
  ///
  /// The salt is random per call; pass [salt] only to recompute a value that is
  /// already stored.
  static String hash(
    String password, {
    String? salt,
    int iterations = _hashIterations,
  }) {
    final usedSalt = salt ?? _randomSalt();
    final derived = _pbkdf2(password, usedSalt, iterations);
    return [_hashPrefix, '$iterations', usedSalt, derived].join(r'$');
  }

  static String _randomSalt() {
    final random = Random.secure();
    return List<int>.generate(16, (_) => random.nextInt(256)).map(_hex).join();
  }

  static String _hex(int byte) => byte.toRadixString(16).padLeft(2, '0');

  /// One-block PBKDF2 (the derived key is 32 bytes, so no further blocks are
  /// needed). The salt is used in its hex form, which is what makes a stored
  /// value reproducible from its own record.
  static String _pbkdf2(String password, String salt, int iterations) {
    final hmac = Hmac(sha256, utf8.encode(password));
    var block = hmac.convert([...utf8.encode(salt), 0, 0, 0, 1]).bytes;
    final derived = List<int>.from(block);
    for (var round = 1; round < iterations; round++) {
      block = hmac.convert(block).bytes;
      for (var i = 0; i < derived.length; i++) {
        derived[i] ^= block[i];
      }
    }
    return derived.map(_hex).join();
  }

  /// True when the stored hash is from the old scheme.
  bool get needsRehash {
    final parts = passwordHash.split(r'$');
    return parts.length != 4 || parts.first != _hashPrefix;
  }

  /// Verify a plain password against stored hash
  bool verifyPassword(String password) {
    final parts = passwordHash.split(r'$');
    if (parts.length != 4 || parts.first != _hashPrefix) {
      // Legacy value: still honoured so an existing cache is not lost, then
      // replaced on the next successful sign-in (see [needsRehash]).
      return _legacyHash(password) == passwordHash;
    }
    final iterations = int.tryParse(parts[1]);
    if (iterations == null || iterations <= 0) return false;
    final candidate = hash(password, salt: parts[2], iterations: iterations);
    return _constantTimeEquals(candidate, passwordHash);
  }

  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var difference = 0;
    for (var i = 0; i < a.length; i++) {
      difference |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return difference == 0;
  }

  static String _legacyHash(String password) {
    int hash = 0;
    for (int i = 0; i < password.length; i++) {
      hash = (hash * 31 + password.codeUnitAt(i)) & 0xFFFFFFFF;
    }
    return hash.toRadixString(16);
  }
}