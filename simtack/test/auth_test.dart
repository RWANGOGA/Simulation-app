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

  // ---------------------------------------------------------------
  // Expired-session pipeline: 401 -> refresh -> retry once -> login
  // ---------------------------------------------------------------
  group('ApiClient expired-session handling', () {
    tearDown(() => ApiClient.onSessionExpired = null);

    test('refreshes once and retries the request that got a 401', () async {
      final storage = FakeTokenStorage();
      await storage.write('stale.token');
      await storage.writeRefreshToken('good.refresh.token');
      ApiClient.tokenStorage = storage;

      var meCalls = 0;
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          expect(request.body, contains('refresh_token=good.refresh.token'));
          return http.Response(
            jsonEncode({'access_token': 'fresh.token', 'token_type': 'bearer'}),
            200,
          );
        }
        if (request.url.path.endsWith('/auth/me')) {
          meCalls++;
          // Only the token minted by /auth/refresh may succeed.
          if (request.headers['Authorization'] == 'Bearer fresh.token') {
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
          return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
        }
        return http.Response('Not found', 404);
      });

      final doctor = await ApiClient.getCurrentDoctor();

      expect(doctor.email, doctorEmail);
      expect(meCalls, 2, reason: 'original attempt + one retry, never a loop');
      expect(await storage.read(), 'fresh.token');
    });

    test('clears the session and notifies the app when the refresh fails',
        () async {
      final storage = FakeTokenStorage();
      await storage.write('stale.token');
      await storage.writeRefreshToken('dead.refresh.token');
      ApiClient.tokenStorage = storage;

      var expiredCallbacks = 0;
      ApiClient.onSessionExpired = () => expiredCallbacks++;

      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return http.Response(
              jsonEncode({'detail': 'Invalid or expired refresh token'}), 401);
        }
        return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
      });

      await expectLater(
        ApiClient.getCurrentDoctor(),
        throwsA(isA<ApiException>()
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );

      expect(expiredCallbacks, 1, reason: 'app is sent to login exactly once');
      expect(await storage.read(), isNull);
      expect(await storage.readRefreshToken(), isNull);
    });

    test('gives up without a refresh call when no refresh token is stored',
        () async {
      final storage = FakeTokenStorage();
      await storage.write('stale.token');
      ApiClient.tokenStorage = storage;

      var refreshCalls = 0;
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          refreshCalls++;
        }
        return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
      });

      await expectLater(
        ApiClient.getCurrentDoctor(),
        throwsA(isA<ApiException>()),
      );
      expect(refreshCalls, 0);
    });

    test('a 401 on login is a bad password, not an expired session', () async {
      final storage = FakeTokenStorage();
      await storage.writeRefreshToken('good.refresh.token');
      ApiClient.tokenStorage = storage;

      var refreshCalls = 0;
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) refreshCalls++;
        return http.Response(
            jsonEncode({'detail': 'Incorrect email or password'}), 401);
      });

      await expectLater(
        ApiClient.login(email: doctorEmail, password: 'WrongPassword!'),
        throwsA(isA<ApiException>().having(
            (e) => e.message, 'message', 'Incorrect email or password')),
      );
      expect(refreshCalls, 0, reason: 'never refresh on a failed sign-in');
    });

    test('a 401 on a request carrying no token is not an expired session',
        () async {
      // The intake endpoints are called by patients who have no account at all.
      // A 401 there says "not authenticated", which is the truth and nobody's
      // problem — signing the device out of a session it never had threw the
      // patient off the screen they were on, and did it again on every retry of
      // the upload queue because the token was already gone.
      final storage = FakeTokenStorage();
      ApiClient.tokenStorage = storage;

      var expiredCallbacks = 0;
      ApiClient.onSessionExpired = () => expiredCallbacks++;

      ApiClient.httpClient = MockClient((request) async {
        expect(request.headers.containsKey('Authorization'), isFalse);
        return http.Response(jsonEncode({'detail': 'Not authenticated'}), 401);
      });

      await expectLater(
        ApiClient.getCurrentDoctor(),
        throwsA(isA<ApiException>()
            .having((e) => e.isUnauthorized, 'isUnauthorized', isTrue)),
      );
      expect(expiredCallbacks, 0,
          reason: 'a session that does not exist cannot expire');
    });

    test('an automatic refresh persists the rotated refresh token', () async {
      // The backend spends the refresh token it is given and hands back a
      // replacement. Losing the replacement would break the next refresh.
      final storage = FakeTokenStorage();
      await storage.write('stale.token');
      await storage.writeRefreshToken('spent.refresh.token');
      ApiClient.tokenStorage = storage;

      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/refresh')) {
          return http.Response(
            jsonEncode({
              'access_token': 'fresh.token',
              'refresh_token': 'rotated.refresh.token',
              'token_type': 'bearer',
            }),
            200,
          );
        }
        if (request.headers['Authorization'] == 'Bearer fresh.token') {
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
        return http.Response(jsonEncode({'detail': 'Token expired'}), 401);
      });

      await ApiClient.getCurrentDoctor();

      expect(await storage.read(), 'fresh.token');
      expect(await storage.readRefreshToken(), 'rotated.refresh.token',
          reason: 'the spent token must be replaced, not kept');
    });

    test('an explicit refresh also persists the rotated refresh token',
        () async {
      final storage = FakeTokenStorage();
      await storage.writeRefreshToken('spent.refresh.token');
      ApiClient.tokenStorage = storage;

      ApiClient.httpClient = MockClient((request) async {
        expect(request.body, contains('refresh_token=spent.refresh.token'));
        return http.Response(
          jsonEncode({
            'access_token': 'fresh.token',
            'refresh_token': 'rotated.refresh.token',
            'token_type': 'bearer',
          }),
          200,
        );
      });

      await ApiClient.refreshAccessToken();

      expect(await storage.read(), 'fresh.token');
      expect(await storage.readRefreshToken(), 'rotated.refresh.token');
    });
  });
}
