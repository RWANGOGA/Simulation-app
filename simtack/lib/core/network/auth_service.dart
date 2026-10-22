import 'dart:async';

import 'api_client.dart';
import '../storage/doctor_draft_storage.dart';
import '../storage/doctor_draft.dart';

/// Thin service layer over [ApiClient] that adds user-friendly error
/// messages for network-level failures (unreachable server, timeout).
/// UI code should depend on this rather than calling [ApiClient] directly
/// for auth flows, so that connection errors surface as readable
/// [ApiException]s instead of raw [SocketException] / [TimeoutException].
/// Supports offline-first login/registration with local credential caching.
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  Future<Doctor> login(
      {required String email, required String password}) async {
    // No connectivity pre-flight: ApiClient already bounds every request and
    // reports transport failures itself, so checking first only added a
    // second round-trip to /health on every single sign-in.
    try {
      final doctor = await ApiClient.login(email: email, password: password);
      // Fire-and-forget: the cache only matters on the *next* launch, so a
      // slow or unavailable local store must never delay a sign-in that has
      // already succeeded (shared_preferences can block indefinitely when
      // its platform channel is not answering, and awaiting it here would
      // leave the Sign In button spinning forever).
      unawaited(_cacheDoctor(doctor, password));
      return doctor;
    } on ApiException catch (error) {
      // Only a transport failure may fall back to the local cache. If the
      // server actively rejected the credentials, honouring a stale local
      // hash would let a changed or revoked password keep working.
      if (!error.isNetworkError) rethrow;
      final cached = await _cachedDoctor(email, password);
      if (cached != null) return cached;
      // Nothing cached for this account — surface the real reason (offline
      // or timed out) instead of a vague "invalid credentials" message.
      rethrow;
    }
  }

  Future<Doctor> register({
    required String email,
    required String password,
    required String fullName,
    String? role,
    String? licenseNumber,
    String? phone,
    String? hospitalName,
    DateTime? dateOfBirth,
    String? inviteCode,
  }) async {
    try {
      final doctor = await ApiClient.register(
        email: email,
        password: password,
        fullName: fullName,
        role: role,
        licenseNumber: licenseNumber,
        phone: phone,
        hospitalName: hospitalName,
        dateOfBirth: dateOfBirth,
        inviteCode: inviteCode,
      );
      unawaited(_cacheDoctor(doctor, password));
      return doctor;
    } on ApiException catch (error) {
      // Registration is only safe to fake locally while the network is the
      // thing that failed; a rejection from the server must be shown as-is.
      if (!error.isNetworkError) rethrow;
    }

    // Offline mode: create local draft
    // Note: We use a placeholder ID; real ID assigned on sync
    final doctor = Doctor(
      id: -DateTime.now().millisecondsSinceEpoch,
      email: email,
      fullName: fullName,
      isActive: true,
      role: role,
      licenseNumber: licenseNumber,
      phone: phone,
      hospitalName: hospitalName,
    );

    final draft = DoctorDraft.createOffline(
      profile: doctor,
      passwordHash: DoctorDraft.hash(password),
    );
    await DoctorDraftStorage.save(draft);

    return doctor;
  }

  /// Local credential cache, used only when the network itself is down.
  /// Storage failures (fresh install, corrupt preferences, unit tests with no
  /// platform channels) are treated as "no cache" rather than an error, so a
  /// broken cache can never block sign-in.
  Future<Doctor?> _cachedDoctor(String email, String password) async {
    try {
      final draft = await DoctorDraftStorage.findByEmail(email);
      if (draft != null && draft.verifyPassword(password)) {
        return draft.profile;
      }
    } catch (_) {
      // Ignored on purpose — see doc comment above.
    }
    return null;
  }

  /// Caches the credentials of a doctor who just signed in, so the next
  /// launch can fall back to them when the network is down. Best-effort by
  /// design: a storage failure must never turn a successful login into an
  /// error, because the user is already authenticated at that point.
  Future<void> _cacheDoctor(Doctor doctor, String password) async {
    try {
      final draft = DoctorDraft.createOffline(
        profile: doctor,
        passwordHash: DoctorDraft.hash(password),
      ).copyWith(doctorId: doctor.id, isSynced: true);
      await DoctorDraftStorage.save(draft);
    } catch (_) {
      // Ignored on purpose — see doc comment above.
    }
  }

  Future<Doctor> getCurrentDoctor() => ApiClient.getCurrentDoctor();

  Future<bool> get isLoggedIn => ApiClient.isLoggedIn;

  Future<void> logout() => ApiClient.logout();
}
