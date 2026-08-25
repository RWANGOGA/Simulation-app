import 'dart:async';
import 'dart:io';
import 'core.dart';
import 'auth.dart'; 

class Doctor {
  final int id;
  final String email;
  final String fullName;
  final bool isActive;

  Doctor({required this.id, required this.email, required this.fullName, required this.isActive});

  factory Doctor.fromJson(Map<String, dynamic> json) => Doctor(
        id: json['id'] as int,
        email: json['email'] as String,
        fullName: json['full_name'] as String,
        isActive: json['is_active'] as bool,
      );
}
class AuthService {
  AuthService({ApiClient? api}) : _api = api ?? ApiClient.instance;
  static final AuthService instance = AuthService();

  final ApiClient _api;

  Future<Doctor> login({required String email, required String password}) async {
    try {
      final data = await _api.postForm('/auth/login', {
        'username': email,
        'password': password,
      });

      final token = data['access_token'] as String?;
      if (token == null) {
        throw ApiException(message: 'Login response was missing an access token.');
      }
      await _api.saveToken(token);
      return getCurrentDoctor();
    } on SocketException {
      throw ApiException(message: 'Cannot reach the server. Check your connection.');
    } on TimeoutException {
      throw ApiException(message: 'The request timed out. Please try again.');
    }
  }

  Future<Doctor> getCurrentDoctor() async {
    final data = await _api.get('/auth/me');
    return Doctor.fromJson(data as Map<String, dynamic>);
  }

  Future<bool> get isLoggedIn => _api.isLoggedIn;
  Future<void> logout() => _api.clearToken();
}