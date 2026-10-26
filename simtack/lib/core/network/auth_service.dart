import 'dart:async';

import 'api_client.dart';
import '../storage/doctor_draft_storage.dart';
import '../storage/doctor_draft.dart';

/// How the session on this device was established.
///
/// Sign-in from the local cache hands back the same [Doctor] a server sign-in
/// hands back, so nothing downstream could tell that no server had confirmed
/// the account. That is not a cosmetic gap: a revoked account that has not been
/// seen online for six days, and an account the server checked ten seconds ago,
/// were indistinguishable in the UI. The practitioner area states which of these
/// it is on every screen it shows.
enum SessionSource {
  /// No practitioner is signed in.
  none,

  /// The server answered for this account on this device.
  server,

  /// A copy of a server account, verified against a locally stored hash while
  /// the network was out, still inside [AuthService.offlineTrustWindow].
  cachedCopy,

  /// Registered on this device with no server. Never confirmed by one, and not
  /// eligible for confirmation: only a hash of the password is kept.
  deviceAccount,
}

/// What may honestly be said about the current session's trust in the server.
///
/// [daysSinceConfirmed] is null for a device account because there is no
/// confirmation to count from, which is a different claim from "confirmed
/// today" and must not be collapsed into zero.
class SessionTrust {
  const SessionTrust({
    required this.source,
    required this.windowDays,
    this.daysSinceConfirmed,
  });

  final SessionSource source;

  /// How long offline access lasts once the server has confirmed the account.
  final int windowDays;

  /// Days since a server last answered for this account.
  final int? daysSinceConfirmed;

  /// Whether anything needs to be said at all.
  bool get needsNotice =>
      source == SessionSource.cachedCopy ||
      source == SessionSource.deviceAccount;
}

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

  SessionSource _sessionSource = SessionSource.none;

  /// How the session now on this device was obtained.
  SessionSource get sessionSource => _sessionSource;

  /// What to tell a practitioner about how current their access is.
  ///
  /// Reads the cached account rather than trusting a timestamp kept in memory,
  /// so the answer is the same whether the session started this launch or was
  /// restored from disk.
  Future<SessionTrust> sessionTrust({DateTime? now}) async {
    final moment = now ?? DateTime.now();
    final window = offlineTrustWindow.inDays;
    switch (_sessionSource) {
      case SessionSource.server:
      case SessionSource.none:
        return SessionTrust(source: _sessionSource, windowDays: window);
      case SessionSource.deviceAccount:
        return SessionTrust(
            source: SessionSource.deviceAccount, windowDays: window);
      case SessionSource.cachedCopy:
        final draft = await _findDraft(null);
        return SessionTrust(
          source: SessionSource.cachedCopy,
          windowDays: window,
          daysSinceConfirmed: draft == null
              ? null
              : moment.difference(draft.trustAnchor).inDays,
        );
    }
  }

  /// Whether a practitioner is signed in on this device right now.
  ///
  /// This exists so an expired token can be told apart from a 401 that has
  /// nothing to do with the practitioner: a patient filling in an assessment
  /// holds no session, so nothing about their flow may be torn down when the
  /// server rejects a request they made. Kept here rather than derived from the
  /// token because the handler has to consult it *after* `ApiClient` has already
  /// deleted the token. `ApiClient.logout()` deliberately does not touch it —
  /// that path is how a rejected session is cleared, and the caller decides what
  /// the app does next.
  bool _hasActiveSession = false;

  bool get hasActiveSession => _hasActiveSession;

  /// Called once the app has acted on an expiry, so the second 401 from the same
  /// dead session does not send the user to the login screen twice.
  void noteSessionEnded() {
    _hasActiveSession = false;
    _noteSource(SessionSource.none);
  }

  Future<Doctor> login(
      {required String email, required String password}) async {
    final doctor = await _login(email: email, password: password);
    _hasActiveSession = true;
    return doctor;
  }

  /// Set once the outcome of a sign-in is known, before the caller is handed a
  /// doctor, so a screen cannot render a session whose source it has not seen.
  void _noteSource(SessionSource source) => _sessionSource = source;

  Future<Doctor> _login(
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
      _noteSource(SessionSource.server);
      return doctor;
    } on ApiException catch (error) {
      // Only a transport failure may fall back to the local cache. If the
      // server actively rejected the credentials, honouring a stale local
      // hash would let a changed or revoked password keep working.
      if (!error.isNetworkError) rethrow;
      final cached = await _cachedAccount(email, password);
      if (cached != null) {
        _noteSource(cached.isDeviceAccount
            ? SessionSource.deviceAccount
            : SessionSource.cachedCopy);
        return cached.profile;
      }
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
    final doctor = await _register(
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
    _hasActiveSession = true;
    return doctor;
  }

  Future<Doctor> _register({
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
      _noteSource(SessionSource.server);
      return doctor;
    } on ApiException catch (error) {
      // Registration is only safe to do on the device while the network is the
      // thing that failed; a rejection from the server (email already taken,
      // invite code wrong, password too weak) is an answer about the account and
      // must be shown as-is.
      if (!error.isNetworkError) rethrow;
    }

    // No server was reachable, so this account exists on this device only.
    //
    // Refusing here would leave a clinic with no backend unable to use the app
    // at all, which is exactly what the offline mode exists to prevent. So the
    // device becomes the authority for its own account. Approval is not
    // something a device can grant, but there is no administrator to ask and no
    // server-side record for the gate to protect — the gate exists so a stranger
    // cannot read a *server's* patient records.
    //
    // The row is stamped as a device account (isSynced stays false), which is
    // what keeps it from ever being treated as a server account: it can sign in
    // here, and it can never pretend to a server session. It also cannot be
    // uploaded later, because only a hash of the password is kept (see
    // DoctorDraft.hash) and a server copy could never be signed in to. A
    // practitioner who wants a server account registers once while connected.
    final doctor = Doctor(
      id: -DateTime.now().millisecondsSinceEpoch,
      email: email,
      fullName: fullName,
      isActive: true,
      role: role,
      licenseNumber: licenseNumber,
      phone: phone,
      hospitalName: hospitalName,
      isApproved: true,
    );

    final draft = DoctorDraft.createOffline(
      profile: doctor,
      passwordHash: DoctorDraft.hash(password),
    );
    await DoctorDraftStorage.save(draft);
    _noteSource(SessionSource.deviceAccount);

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
  ///
  /// Hands back the whole draft rather than just the profile: whether this is a
  /// copy of a server account or an account the device made itself changes what
  /// may be claimed about it on screen.
  Future<DoctorDraft?> _cachedAccount(String email, String password) async {
    final draft = await _findDraft(email);
    if (draft == null || !draft.verifyPassword(password)) return null;

    // An account created on this device never had a server to confirm it, so
    // neither the approval gate nor the trust window applies. The window exists
    // to bound how long a *copy* of a server account stays trusted; there is no
    // copy here, and expiring it would lock a practitioner out of a clinic that
    // has no backend after their first week.
    if (draft.isDeviceAccount) {
      if (!draft.profile.isActive) {
        throw ApiException(
          statusCode: 403,
          message:
              'This account has been deactivated. Contact an administrator.',
        );
      }
      return draft;
    }

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
    return draft;
  }

  /// What the app should open with, re-checking the stored session against the
  /// server whenever it can be reached.
  ///
  /// This used to be "is there a token on disk", which a deactivated account
  /// kept passing: the app opened on a dashboard whose every request failed, and
  /// the cached credential stayed usable offline forever. Now a rejection from
  /// the server ends the session on the device too.
  Future<bool> restoreSession() async {
    final restored = await _restoreSession();
    _hasActiveSession = restored;
    return restored;
  }

  Future<bool> _restoreSession() async {
    if (await ApiClient.isLoggedIn) {
      try {
        final doctor = await ApiClient.getCurrentDoctor();
        await _refreshCachedProfile(doctor);
        _noteSource(SessionSource.server);
        return true;
      } on ApiException catch (error) {
        final status = error.statusCode;
        // 401 is what /auth/me returns for a token whose account was deactivated
        // or unapproved, and 403 for an account that lost its access: either way
        // the session is over on this device.
        if (status == 401 || status == 403) {
          await ApiClient.logout();
          await _revokeCachedTrust();
          _noteSource(SessionSource.none);
          return false;
        }
        if (!error.isNetworkError) {
          // A 5xx is the server's problem, not the account's — keep the session
          // and let the next call decide. It is kept on the strength of a token
          // on this device, which is not a confirmation, so it is reported the
          // same way a cached sign-in is.
          _noteSource(SessionSource.cachedCopy);
          return true;
        }

        // Offline launch: fall back to the same window offline sign-in uses, so a
        // device that has not reached the server in a week asks for a sign-in
        // instead of silently trusting a stale copy.
        final draft = await _findDraft(null);
        if (draft != null &&
            draft.isTrustExpired(DateTime.now(), offlineTrustWindow)) {
          return false;
        }
        _noteSource(SessionSource.cachedCopy);
        return true;
      }
    }

    // No server session. An account created on this device still has to open
    // its dashboard: asking the server about it would make the app unusable on
    // a device that has never had a connection, which is the point of it.
    final device = await _deviceAccount();
    if (device == null) return false;
    _noteSource(SessionSource.deviceAccount);
    return true;
  }

  /// The signed-in-by-default account on a device with no server: an active
  /// device account, newest first.
  Future<DoctorDraft?> _deviceAccount() async {
    try {
      for (final draft in await DoctorDraftStorage.loadAll()) {
        if (draft.isDeviceAccount && draft.profile.isActive) return draft;
      }
    } catch (_) {
      // Ignored on purpose — a broken cache is treated as "no account".
    }
    return null;
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
        // A profile edit still waiting for the server is newer than this
        // answer, so only the trust fields are refreshed here. Overwriting the
        // profile would revert an edit made where there was no signal.
        profile: draft.pendingProfile == null ? doctor : draft.profile,
        doctorId: doctor.id,
        isSynced: true,
        lastVerifiedAt: DateTime.now(),
      ));
    } catch (_) {
      // Ignored on purpose — a cache write must not fail a session.
    }
  }

  /// Sends a profile edit that was made while the server was unreachable.
  ///
  /// Returns the draft to use: the updated one when the server accepted the
  /// edit (which also clears the marker), the original when it is still out of
  /// reach. Nothing is thrown, because an unreachable server is not an error
  /// here — the edit is safe on the device either way.
  Future<DoctorDraft> _flushPendingProfile(DoctorDraft draft) async {
    final pending = draft.pendingProfile;
    if (pending == null || draft.isDeviceAccount) return draft;

    try {
      final doctor = await ApiClient.updateDoctorProfile(
        fullName: pending['full_name'] as String?,
        role: pending['role'] as String?,
        licenseNumber: pending['license_number'] as String?,
        phone: pending['phone'] as String?,
        hospitalName: pending['hospital_name'] as String?,
        dateOfBirth:
            DateTime.tryParse((pending['date_of_birth'] as String?) ?? ''),
      );
      final saved = draft.copyWith(
        profile: doctor,
        doctorId: doctor.id,
        isSynced: true,
        lastVerifiedAt: DateTime.now(),
        clearPendingProfile: true,
      );
      await DoctorDraftStorage.save(saved);
      return saved;
    } catch (_) {
      // Still unreachable: the edit stays on the device and is tried again the
      // next time the server answers.
      return draft;
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
        await DoctorDraftStorage.save(draft.copyWith(
            lastVerifiedAt: DateTime.fromMillisecondsSinceEpoch(0)));
      }
    } catch (_) {
      // Ignored on purpose — see doc comment above.
    }
  }

  /// Who is signed in, preferring the server's copy and falling back to the
  /// device's own.
  ///
  /// This used to be a plain `/auth/me` call. Screens render the practitioner's
  /// name, role and hospital from it, so on a device with no connection that
  /// made the profile screen show an error instead of the person using it — the
  /// one thing an offline-first app cannot do.
  Future<Doctor> getCurrentDoctor() async {
    if (await ApiClient.isLoggedIn) {
      // An edit made offline is sent before the read, otherwise `/auth/me`
      // would answer with the copy this device has already moved past.
      final cached = await _findDraft(null);
      if (cached != null && cached.pendingProfile != null) {
        await _flushPendingProfile(cached);
      }
      try {
        final doctor = await ApiClient.getCurrentDoctor();
        await _refreshCachedProfile(doctor);
        return doctor;
      } on ApiException catch (error) {
        if (!error.isNetworkError) rethrow;
      }
    }

    final draft = await _findDraft(null) ?? await _deviceAccount();
    if (draft == null) {
      throw ApiException(
        statusCode: 401,
        isNetworkError: true,
        message: 'Sign in to continue.',
      );
    }
    return draft.profile;
  }

  /// Saves the signed-in practitioner's own profile.
  ///
  /// The device is written first and unconditionally: a clinic with no
  /// connection is the normal case, and refusing the edit (or losing it) because
  /// the server was out of reach is exactly what this app must not do. The
  /// fields still owed to the server ride on the cached account
  /// ([DoctorDraft.pendingProfile]) and are sent the next time it answers.
  Future<Doctor> updateMyProfile({
    String? fullName,
    String? role,
    String? licenseNumber,
    String? phone,
    String? hospitalName,
    DateTime? dateOfBirth,
  }) async {
    final draft = await _findDraft(null) ?? await _deviceAccount();
    if (draft == null) {
      throw ApiException(
        statusCode: 401,
        isNetworkError: true,
        message: 'Sign in to continue.',
      );
    }

    // A null field means "left alone", which is how the API treats it too.
    String? trimmed(String? value) {
      final text = value?.trim();
      return (text == null || text.isEmpty) ? null : text;
    }

    final current = draft.profile;
    final edited = Doctor(
      id: current.id,
      email: current.email,
      fullName: trimmed(fullName) ?? current.fullName,
      isActive: current.isActive,
      role: trimmed(role) ?? current.role,
      licenseNumber: trimmed(licenseNumber) ?? current.licenseNumber,
      phone: trimmed(phone) ?? current.phone,
      hospitalName: trimmed(hospitalName) ?? current.hospitalName,
      isApproved: current.isApproved,
      accessLevel: current.accessLevel,
    );

    final pending = <String, dynamic>{
      // An edit replaces the whole set: anything already waiting and left out
      // of this form is what the practitioner just cleared.
      if (trimmed(fullName) != null) 'full_name': trimmed(fullName),
      if (trimmed(role) != null) 'role': trimmed(role),
      if (trimmed(licenseNumber) != null)
        'license_number': trimmed(licenseNumber),
      if (trimmed(phone) != null) 'phone': trimmed(phone),
      if (trimmed(hospitalName) != null) 'hospital_name': trimmed(hospitalName),
      if (dateOfBirth != null)
        'date_of_birth': '${dateOfBirth.year.toString().padLeft(4, '0')}-'
            '${dateOfBirth.month.toString().padLeft(2, '0')}-'
            '${dateOfBirth.day.toString().padLeft(2, '0')}',
    };

    final localCopy = draft.copyWith(
      profile: edited,
      savedAt: DateTime.now(),
      pendingProfile: pending,
    );
    await DoctorDraftStorage.save(localCopy);

    // An account that exists only on this device has no server to tell.
    if (draft.isDeviceAccount) return edited;
    if (!await ApiClient.isLoggedIn) return edited;

    final flushed = await _flushPendingProfile(localCopy);
    return flushed.profile;
  }

  Future<bool> get isLoggedIn => ApiClient.isLoggedIn;

  Future<void> logout() async {
    _hasActiveSession = false;
    _noteSource(SessionSource.none);
    await ApiClient.logout();
  }
}
