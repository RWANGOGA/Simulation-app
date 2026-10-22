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

  /// How long a device trusts cached credentials after the server last
  /// confirmed the account.
  ///
  /// Offline sign-in exists so a practitioner can keep working through a
  /// network outage. Unbounded, though, one successful sign-in bought permanent
  /// access: deactivating the account on the server did nothing to the copy on
  /// the device, and the app went on opening patient data offline. A week is
  /// long enough for a realistic outage and short enough that a revoked account
  /// cannot keep going indefinitely.
  static const Duration offlineTrustWindow = Duration(days: 7);

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
    // Note: We use a placeholder ID; real ID assigned on sync.
    //
    // This account is local-only by nature: only a hash of the password is kept,
    // so no later step can register it on the server under the practitioner's
    // real password (see DoctorDraftSyncService). Nothing in the UI registers
    // offline — the registration screen calls the API and reports the failure —
    // so this is not reachable today, but the draft it writes must never be
    // mistaken for an account that exists server-side.
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

  /// Caches the credentials of a doctor who just signed in, so the next
  /// launch can fall back to them when the network is down. Best-effort by
  /// design: a storage failure must never turn a successful login into an
  /// error, because the user is already authenticated at that point.
  Future<void> _cacheDoctor(Doctor doctor, String password) async {
    try {
      final draft = DoctorDraft.createOffline(
        profile: doctor,
        passwordHash: DoctorDraft.hash(password),
      ).copyWith(
        doctorId: doctor.id,
        isSynced: true,
        // The server just answered, so this is the moment the copy is backed by
        // it. Nothing local may move this timestamp.
        lastVerifiedAt: DateTime.now(),
      );
      await DoctorDraftStorage.save(draft);
    } catch (_) {
      // Ignored on purpose — see doc comment above.
    }
  }

  /// Local credential cache, used only when the network itself is down.
  /// Storage failures (fresh install, corrupt preferences, unit tests with no
  /// platform channels) are treated as "no cache" rather than an error, so a
  /// broken cache can never block sign-in.
  Future<Doctor?> _cachedDoctor(String email, String password) async {
    final draft = await _findDraft(email);
    if (draft == null || !draft.verifyPassword(password)) return null;

    // The cache records what the server last said about this account. A
    // registration still awaiting approval caches `isApproved: false`, and
    // honouring it offline would walk straight around the approval gate the
    // server enforces — the one thing an offline path must not do. A row
    // written before approval was persisted has no opinion, so it is not
    // treated as a rejection.
    final approved = !draft.approvalRecorded || draft.profile.isApproved;
    if (!approved || !draft.profile.isActive) {
      throw ApiException(
        statusCode: 403,
        message: approved
            ? 'This account has been deactivated. Contact an administrator.'
            : 'This account is still waiting for administrator approval.',
      );
    }

    if (draft.isTrustExpired(DateTime.now(), offlineTrustWindow)) {
      throw ApiException(
        statusCode: 401,
        isNetworkError: true,
        message: 'Sign in once while connected to confirm this account. '
            'Offline sign-in keeps working for ${offlineTrustWindow.inDays} '
            'days after that.',
      );
    }

    await _upgradeHashIfNeeded(draft, password);
    return draft.profile;
  }

  /// What the app should open with, re-checking the stored session against the
  /// server whenever it can be reached.
  ///
  /// This used to be "is there a token on disk", which a deactivated account
  /// kept passing: the app opened on a dashboard whose every request failed, and
  /// the cached credential stayed usable offline forever. Now a rejection from
  /// the server ends the session on the device too.
  Future<bool> restoreSession() async {
    if (!await ApiClient.isLoggedIn) return false;

    try {
      final doctor = await ApiClient.getCurrentDoctor();
      await _refreshCachedProfile(doctor);
      return true;
    } on ApiException catch (error) {
      final status = error.statusCode;
      // 401 is what /auth/me returns for a token whose account was deactivated
      // or unapproved, and 403 for an account that lost its access: either way
      // the session is over on this device.
      if (status == 401 || status == 403) {
        await ApiClient.logout();
        await _revokeCachedTrust();
        return false;
      }
      if (!error.isNetworkError) {
        // A 5xx is the server's problem, not the account's — keep the session
        // and let the next call decide.
        return true;
      }

      // Offline launch: fall back to the same window offline sign-in uses, so a
      // device that has not reached the server in a week asks for a sign-in
      // instead of silently trusting a stale copy.
      final draft = await _findDraft(null);
      if (draft == null) return true;
      return !draft.isTrustExpired(DateTime.now(), offlineTrustWindow);
    }
  }

  Future<DoctorDraft?> _findDraft(String? email) async {
    try {
      return email == null
          ? await DoctorDraftStorage.loadLatest()
          : await DoctorDraftStorage.findByEmail(email);
    } catch (_) {
      // Ignored on purpose — a broken cache is treated as "no cache".
      return null;
    }
  }

  /// Replaces a legacy hash now that the plaintext is in hand. The trust anchor
  /// is deliberately untouched: verifying a password locally is not the server
  /// confirming the account.
  Future<void> _upgradeHashIfNeeded(DoctorDraft draft, String password) async {
    if (!draft.needsRehash) return;
    try {
      await DoctorDraftStorage.save(
          draft.copyWith(passwordHash: DoctorDraft.hash(password)));
    } catch (_) {
      // Ignored on purpose — the old hash still verifies next time.
    }
  }

  /// Keeps the cached copy in step with the server: profile changes (role,
  /// approval, hospital) and the timestamp that says it was confirmed.
  Future<void> _refreshCachedProfile(Doctor doctor) async {
    try {
      final draft = await DoctorDraftStorage.findByEmail(doctor.email);
      if (draft == null) return;
      await DoctorDraftStorage.save(draft.copyWith(
        profile: doctor,
        doctorId: doctor.id,
        isSynced: true,
        lastVerifiedAt: DateTime.now(),
      ));
    } catch (_) {
      // Ignored on purpose — a cache write must not fail a session.
    }
  }

  /// Marks every cached account as unverified instead of deleting it.
  ///
  /// An offline registration that has not reached the server yet keeps its
  /// payload, but no cached credential can sign in offline again until the
  /// server confirms an account. Deletion would be simpler and lossier.
  Future<void> _revokeCachedTrust() async {
    try {
      final drafts = await DoctorDraftStorage.loadAll();
      for (final draft in drafts) {
        await DoctorDraftStorage.save(draft
            .copyWith(lastVerifiedAt: DateTime.fromMillisecondsSinceEpoch(0)));
      }
    } catch (_) {
      // Ignored on purpose — see doc comment above.
    }
  }

  Future<Doctor> getCurrentDoctor() => ApiClient.getCurrentDoctor();

  Future<bool> get isLoggedIn => ApiClient.isLoggedIn;

  Future<void> logout() => ApiClient.logout();
}
