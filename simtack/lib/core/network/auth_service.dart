import 'dart:async';
import 'dart:io';

import 'api_client.dart';

/// Thin service layer over [ApiClient] that adds user-friendly error
/// messages for network-level failures (unreachable server, timeout).
/// UI code should depend on this rather than calling [ApiClient] directly
/// for auth flows, so that connection errors surface as readable
/// [ApiException]s instead of raw [SocketException] / [TimeoutException].
class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  Future<Doctor> login({required String email, required String password}) async {
    try {
      return await ApiClient.login(email: email, password: password);
    } on SocketException {
      throw ApiException(message: 'Cannot reach the server. Check your connection.');
    } on TimeoutException {
      throw ApiException(message: 'The request timed out. Please try again.');
    }
  }

  Future<Doctor> getCurrentDoctor() => ApiClient.getCurrentDoctor();

  Future<bool> get isLoggedIn => ApiClient.isLoggedIn;

  Future<void> logout() => ApiClient.logout();
}
