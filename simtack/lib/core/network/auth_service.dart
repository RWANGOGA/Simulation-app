import 'dart:async';
import 'dart:io';

import 'api_client.dart';
import 'connectivity_service.dart';
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

  Future<Doctor> login({required String email, required String password}) async {
    // Try online first
    final isOnline = await ConnectivityService.instance.checkOnline();
    if (isOnline) {
      try {
        final doctor = await ApiClient.login(email: email, password: password);
        // Cache successful login locally
        await _cacheDoctor(doctor, password);
        return doctor;
      } on SocketException {
        // Fall through to offline
      } on TimeoutException {
        // Fall through to offline
      }
    }

    // Offline mode: check local cache
    final draft = await DoctorDraftStorage.findByEmail(email);
    if (draft != null && draft.verifyPassword(password)) {
      return draft.profile;
    }

    throw ApiException(message: 'Invalid credentials or no internet connection.');
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
    final isOnline = await ConnectivityService.instance.checkOnline();
    
    if (isOnline) {
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
        await _cacheDoctor(doctor, password);
        return doctor;
      } on SocketException {
        // Fall through to offline
      } on TimeoutException {
        // Fall through to offline
      }
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

  Future<void> _cacheDoctor(Doctor doctor, String password) async {
    final draft = DoctorDraft.createOffline(
      profile: doctor,
      passwordHash: DoctorDraft.hash(password),
    ).copyWith(doctorId: doctor.id, isSynced: true);
    await DoctorDraftStorage.save(draft);
  }

  Future<Doctor> getCurrentDoctor() => ApiClient.getCurrentDoctor();

  Future<bool> get isLoggedIn => ApiClient.isLoggedIn;

  Future<void> logout() => ApiClient.logout();
}
