import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:simtack/core/network/api_client.dart';
import 'test_doctor_credentials.dart';

/// In-memory stand-in for secure storage, so tests never touch platform channels.
class FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<void> write(String value) async => _token = value;
  @override
  Future<String?> read() async => _token;
  String? _refreshToken;
  @override
  Future<void> writeRefreshToken(String value) async => _refreshToken = value;
  @override
  Future<String?> readRefreshToken() async => _refreshToken;
  @override
  Future<void> delete() async {
    _token = null;
    _refreshToken = null;
  }
}

void main() {
  group('ApiException.fromResponse', () {
    test('parses a plain string detail (401-style)', () {
      final ex = ApiException.fromResponse(
        401,
        jsonEncode({'detail': 'Incorrect email or password'}),
      );
      expect(ex.statusCode, 401);
      expect(ex.isUnauthorized, isTrue);
      expect(ex.message, 'Incorrect email or password');
    });

    test('parses a list of validation errors (422-style)', () {
      final ex = ApiException.fromResponse(
        422,
        jsonEncode({
          'detail': [
            {
              'loc': ['body', 'username'],
              'msg': 'field required',
              'type': 'value_error.missing'
            },
          ],
        }),
      );
      expect(ex.statusCode, 422);
      expect(ex.message, 'field required');
    });

    test('falls back gracefully on malformed body', () {
      final ex = ApiException.fromResponse(500, 'not json');
      expect(ex.statusCode, 500);
      expect(ex.message, contains('500'));
    });
  });

  final defaultClient = ApiClient.httpClient;
  final defaultStorage = ApiClient.tokenStorage;

  tearDown(() {
    ApiClient.httpClient = defaultClient;
    ApiClient.tokenStorage = defaultStorage;
  });

  group('ApiClient.login', () {
    test('stores token and returns Doctor on success', () async {
      final storage = FakeTokenStorage();
      ApiClient.tokenStorage = storage;
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          expect(request.method, 'POST');
          expect(request.headers['Content-Type'],
              contains('x-www-form-urlencoded'));
          final body = Uri.splitQueryString(request.body);
          expect(body['username'], doctorEmail);
          expect(body['password'], doctorPassword);
          return http.Response(
            jsonEncode({
              'access_token': 'fake.jwt.token',
              'refresh_token': 'fake.refresh.token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/me')) {
          expect(request.headers['Authorization'], 'Bearer fake.jwt.token');
          return http.Response(
            jsonEncode({
              'id': 1,
              'email': doctorEmail,
              'full_name': 'Dr. Jonan',
              'is_active': true,
            }),
            200,
          );
        }
        return http.Response('Not found', 404);
      });

      final doctor =
          await ApiClient.login(email: doctorEmail, password: doctorPassword);

      expect(doctor.email, doctorEmail);
      expect(doctor.fullName, 'Dr. Jonan');
      expect(await storage.read(), 'fake.jwt.token');
      expect(await storage.readRefreshToken(), 'fake.refresh.token');
      expect(await ApiClient.isLoggedIn, isTrue);
    });

    test('refreshes the access token with the stored refresh token', () async {
      final storage = FakeTokenStorage();
      await storage.writeRefreshToken('fake.refresh.token');
      ApiClient.tokenStorage = storage;
      ApiClient.httpClient = MockClient((request) async {
        expect(request.url.path, endsWith('/auth/refresh'));
        expect(request.body, contains('refresh_token=fake.refresh.token'));
        return http.Response(
          jsonEncode({'access_token': 'new.jwt.token', 'token_type': 'bearer'}),
          200,
        );
      });

      await ApiClient.refreshAccessToken();

      expect(await storage.read(), 'new.jwt.token');
      expect(await storage.readRefreshToken(), 'fake.refresh.token');
    });

    test('throws ApiException with backend detail on invalid credentials',
        () async {
      final storage = FakeTokenStorage();
      ApiClient.tokenStorage = storage;
      ApiClient.httpClient = MockClient((request) async {
        return http.Response(
          jsonEncode({'detail': 'Incorrect email or password'}),
          401,
        );
      });

      expect(
        () => ApiClient.login(email: doctorEmail, password: 'WrongPassword!'),
        throwsA(isA<ApiException>()
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
      expect(await storage.read(), isNull);
    });

    test('logout clears the stored token', () async {
      final storage = FakeTokenStorage();
      await storage.write('some.token');
      ApiClient.tokenStorage = storage;

      expect(await ApiClient.isLoggedIn, isTrue);
      await ApiClient.logout();
      expect(await ApiClient.isLoggedIn, isFalse);
    });
  });
}
