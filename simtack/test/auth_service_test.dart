import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/network/auth_service.dart';

/// In-memory token storage so tests never touch platform secure storage.
class FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<void> write(String value) async => _token = value;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> delete() async => _token = null;
}

void main() {
  final defaultClient = ApiClient.httpClient;
  final defaultStorage = ApiClient.tokenStorage;

  setUp(() {
    ApiClient.tokenStorage = FakeTokenStorage();
  });

  tearDown(() {
    ApiClient.httpClient = defaultClient;
    ApiClient.tokenStorage = defaultStorage;
  });

  // ---------------------------------------------------------------
  // login()
  // ---------------------------------------------------------------
  group('AuthService.login', () {
    test('returns Doctor and stores token on success', () async {
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          expect(request.method, 'POST');
          return http.Response(
            jsonEncode({'access_token': 'test.jwt.token', 'token_type': 'bearer'}),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/me')) {
          expect(request.headers['Authorization'], 'Bearer test.jwt.token');
          return http.Response(
            jsonEncode({'id': 1, 'email': 'doc@test.com', 'full_name': 'Dr. Test', 'is_active': true}),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final doctor = await AuthService.instance.login(email: 'doc@test.com', password: 'pass123');

      expect(doctor.email, 'doc@test.com');
      expect(doctor.fullName, 'Dr. Test');
      expect(await ApiClient.tokenStorage.read(), 'test.jwt.token');
      expect(await AuthService.instance.isLoggedIn, isTrue);
    });

    test('throws ApiException with isUnauthorized on 401', () async {
      ApiClient.httpClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Incorrect email or password'}), 401);
      });

      expect(
        () => AuthService.instance.login(email: 'doc@test.com', password: 'wrong'),
        throwsA(isA<ApiException>()
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)
            .having((e) => e.message, 'message', 'Incorrect email or password')),
      );
      // Token must NOT be stored on failure
      expect(await ApiClient.tokenStorage.read(), isNull);
    });

    test('wraps SocketException into a friendly ApiException', () async {
      ApiClient.httpClient = MockClient((request) async {
        throw SocketException('Connection refused');
      });

      expect(
        () => AuthService.instance.login(email: 'doc@test.com', password: 'pass'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('Cannot reach the server'))),
      );
    });

    test('wraps TimeoutException into a friendly ApiException', () async {
      ApiClient.httpClient = MockClient((request) async {
        throw TimeoutException('Operation timed out');
      });

      expect(
        () => AuthService.instance.login(email: 'doc@test.com', password: 'pass'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('timed out'))),
      );
    });
  });

  // ---------------------------------------------------------------
  // isLoggedIn
  // ---------------------------------------------------------------
  group('AuthService.isLoggedIn', () {
    test('returns false when no token is stored', () async {
      expect(await AuthService.instance.isLoggedIn, isFalse);
    });

    test('returns true when a token is stored', () async {
      await ApiClient.tokenStorage.write('some.token');
      expect(await AuthService.instance.isLoggedIn, isTrue);
    });
  });

  // ---------------------------------------------------------------
  // logout()
  // ---------------------------------------------------------------
  group('AuthService.logout', () {
    test('clears the stored token so isLoggedIn becomes false', () async {
      await ApiClient.tokenStorage.write('some.token');
      expect(await AuthService.instance.isLoggedIn, isTrue);

      await AuthService.instance.logout();
      expect(await AuthService.instance.isLoggedIn, isFalse);
    });

    test('is safe to call even when already logged out', () async {
      await AuthService.instance.logout();
      expect(await AuthService.instance.isLoggedIn, isFalse);
    });
  });

  // ---------------------------------------------------------------
  // getCurrentDoctor()
  // ---------------------------------------------------------------
  group('AuthService.getCurrentDoctor', () {
    test('delegates to ApiClient and returns the Doctor', () async {
      ApiClient.tokenStorage = FakeTokenStorage()..write('stored.token');
      ApiClient.httpClient = MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer stored.token');
        return http.Response(
          jsonEncode({'id': 7, 'email': 'a@b.com', 'full_name': 'Dr. A', 'is_active': true}),
          200,
        );
      });

      final doctor = await AuthService.instance.getCurrentDoctor();
      expect(doctor.id, 7);
      expect(doctor.fullName, 'Dr. A');
    });
  });
}
