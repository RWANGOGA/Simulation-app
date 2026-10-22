import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/network/auth_service.dart';
import 'package:simtack/core/storage/doctor_draft.dart';
import 'package:simtack/core/storage/doctor_draft_storage.dart';

/// In-memory token storage so tests never touch platform secure storage.
class FakeTokenStorage implements TokenStorage {
  String? _token;

  @override
  Future<void> write(String value) async => _token = value;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> writeRefreshToken(String value) async {}
  @override
  Future<String?> readRefreshToken() async => null;
  @override
  Future<void> delete() async => _token = null;
}

Doctor _doctor({
  int id = 7,
  String email = 'doctor@example.com',
  bool isActive = true,
  bool isApproved = true,
}) =>
    Doctor(
      id: id,
      email: email,
      fullName: 'Dr Test',
      isActive: isActive,
      isApproved: isApproved,
      accessLevel: 'practitioner',
    );

Map<String, dynamic> _doctorJson({
  int id = 7,
  String email = 'doctor@example.com',
  bool isActive = true,
  bool isApproved = true,
}) =>
    {
      'id': id,
      'email': email,
      'full_name': 'Dr Test',
      'is_active': isActive,
      'is_approved': isApproved,
      'access_level': 'practitioner',
    };

/// The network is down for every request.
http.Client _offline() =>
    MockClient((_) async => throw http.ClientException('connection refused'));

/// A cache entry as the app would have written it after a sign-in.
Future<DoctorDraft> _cacheSignedIn({
  required String password,
  DateTime? verifiedAt,
  bool isActive = true,
  bool isApproved = true,
  String? passwordHash,
}) async {
  final draft = DoctorDraft(
    localId: 7,
    doctorId: 7,
    profile: _doctor(isActive: isActive, isApproved: isApproved),
    passwordHash: passwordHash ?? DoctorDraft.hash(password),
    savedAt: verifiedAt ?? DateTime.now(),
    isSynced: true,
    lastVerifiedAt: verifiedAt ?? DateTime.now(),
  );
  await DoctorDraftStorage.save(draft);
  return draft;
}

/// The cache write after a sign-in is deliberately fire-and-forget (a slow
/// local store must never delay a successful login), so a test cannot read it
/// on the next line.
Future<DoctorDraft?> _waitForCache(String email) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final draft = await DoctorDraftStorage.findByEmail(email);
    if (draft != null) return draft;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return null;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late http.Client originalClient;
  late TokenStorage originalStorage;
  late FakeTokenStorage tokens;

  setUp(() {
    originalClient = ApiClient.httpClient;
    originalStorage = ApiClient.tokenStorage;
    tokens = FakeTokenStorage();
    ApiClient.tokenStorage = tokens;
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    ApiClient.httpClient = originalClient;
    ApiClient.tokenStorage = originalStorage;
  });

  group('offline sign-in', () {
    test('works while the cached copy is inside the trust window', () async {
      await _cacheSignedIn(password: 'Secret123');
      ApiClient.httpClient = _offline();

      final doctor = await AuthService.instance
          .login(email: 'doctor@example.com', password: 'Secret123');

      expect(doctor.email, 'doctor@example.com');
    });

    test('stops working once the server has not confirmed for too long',
        () async {
      await _cacheSignedIn(
        password: 'Secret123',
        verifiedAt: DateTime.now()
            .subtract(AuthService.offlineTrustWindow + const Duration(days: 1)),
      );
      ApiClient.httpClient = _offline();

      await expectLater(
        AuthService.instance
            .login(email: 'doctor@example.com', password: 'Secret123'),
        throwsA(isA<ApiException>().having((e) => e.message, 'message',
            contains('Sign in once while connected'))),
      );
    });

    test('a pending registration cannot sign in offline', () async {
      // Registration caches the account before an administrator approves it;
      // honouring that offline would walk around the approval gate.
      await _cacheSignedIn(password: 'Secret123', isApproved: false);
      ApiClient.httpClient = _offline();

      await expectLater(
        AuthService.instance
            .login(email: 'doctor@example.com', password: 'Secret123'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 403)
            .having((e) => e.message, 'message', contains('approval'))),
      );
    });

    test('a deactivated account cannot sign in offline', () async {
      await _cacheSignedIn(password: 'Secret123', isActive: false);
      ApiClient.httpClient = _offline();

      await expectLater(
        AuthService.instance
            .login(email: 'doctor@example.com', password: 'Secret123'),
        throwsA(isA<ApiException>()
            .having((e) => e.message, 'message', contains('deactivated'))),
      );
    });

    test('a wrong password gets no cache bypass', () async {
      await _cacheSignedIn(password: 'Secret123');
      ApiClient.httpClient = _offline();

      await expectLater(
        AuthService.instance
            .login(email: 'doctor@example.com', password: 'WrongPass'),
        throwsA(isA<ApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', isTrue)),
      );
    });

    test('a server rejection never falls back to the cache', () async {
      await _cacheSignedIn(password: 'Secret123');
      ApiClient.httpClient = MockClient((_) async => http.Response(
          jsonEncode({'detail': 'Incorrect email or password'}), 401));

      await expectLater(
        AuthService.instance
            .login(email: 'doctor@example.com', password: 'Secret123'),
        throwsA(isA<ApiException>()
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', contains('Incorrect'))),
      );
    });

    test('a legacy hash still verifies and is upgraded in place', () async {
      // The old scheme: unsalted 32-bit rolling hash.
      int legacy = 0;
      for (final unit in 'Secret123'.codeUnits) {
        legacy = (legacy * 31 + unit) & 0xFFFFFFFF;
      }
      final signedInAt = DateTime.now().subtract(const Duration(days: 2));
      await _cacheSignedIn(
        password: 'Secret123',
        passwordHash: legacy.toRadixString(16),
        verifiedAt: signedInAt,
      );
      ApiClient.httpClient = _offline();

      await AuthService.instance
          .login(email: 'doctor@example.com', password: 'Secret123');

      final stored = await DoctorDraftStorage.findByEmail('doctor@example.com');
      expect(stored!.passwordHash, startsWith('pbkdf2-sha256'));
      expect(stored.verifyPassword('Secret123'), isTrue);
      // A local verification is not the server confirming the account.
      expect(stored.lastVerifiedAt, signedInAt);
    });
  });

  group('online sign-in', () {
    test('records the moment the server confirmed the account', () async {
      // ApiClient.login reads the freshly issued token and then asks /auth/me
      // for the profile, so both routes have to answer.
      ApiClient.httpClient = MockClient((request) async {
        if (request.url.path.endsWith('/auth/login')) {
          return http.Response(
              jsonEncode({'access_token': 'token', 'refresh_token': 'refresh'}),
              200);
        }
        if (request.url.path.endsWith('/auth/me')) {
          return http.Response(jsonEncode(_doctorJson()), 200);
        }
        return http.Response('{}', 404);
      });

      await AuthService.instance
          .login(email: 'doctor@example.com', password: 'Secret123');

      final stored = await _waitForCache('doctor@example.com');
      expect(stored, isNotNull);
      expect(stored!.lastVerifiedAt, isNotNull);
      expect(DateTime.now().difference(stored.trustAnchor).inMinutes, 0);
      expect(stored.passwordHash, startsWith('pbkdf2-sha256'));
    });
  });

  group('restoring a stored session', () {
    test('without a token there is nothing to restore', () async {
      ApiClient.httpClient = _offline();

      expect(await AuthService.instance.restoreSession(), isFalse);
    });

    test('a live session refreshes the cached copy', () async {
      await tokens.write('token');
      final stale = DateTime.now().subtract(const Duration(days: 30));
      await _cacheSignedIn(password: 'Secret123', verifiedAt: stale);
      ApiClient.httpClient = MockClient(
          (_) async => http.Response(jsonEncode(_doctorJson()), 200));

      expect(await AuthService.instance.restoreSession(), isTrue);

      final stored = await DoctorDraftStorage.findByEmail('doctor@example.com');
      expect(stored!.trustAnchor.isAfter(stale), isTrue);
    });

    test('a revoked account ends the session and the cached trust', () async {
      await tokens.write('token');
      await _cacheSignedIn(password: 'Secret123');
      ApiClient.httpClient = MockClient((_) async => http.Response(
          jsonEncode({'detail': 'Could not validate credentials'}), 401));

      expect(await AuthService.instance.restoreSession(), isFalse);

      expect(await tokens.read(), isNull);
      final stored = await DoctorDraftStorage.findByEmail('doctor@example.com');
      // Kept, not deleted: the row survives, but it can no longer be used
      // offline until the server confirms an account again.
      expect(stored, isNotNull);
      expect(
          stored!
              .isTrustExpired(DateTime.now(), AuthService.offlineTrustWindow),
          isTrue);
    });

    test('offline, a fresh cached copy still opens the app', () async {
      await tokens.write('token');
      await _cacheSignedIn(password: 'Secret123');
      ApiClient.httpClient = _offline();

      expect(await AuthService.instance.restoreSession(), isTrue);
    });

    test('offline, a stale cached copy asks for a sign-in', () async {
      await tokens.write('token');
      await _cacheSignedIn(
        password: 'Secret123',
        verifiedAt: DateTime.now()
            .subtract(AuthService.offlineTrustWindow + const Duration(days: 1)),
      );
      ApiClient.httpClient = _offline();

      expect(await AuthService.instance.restoreSession(), isFalse);
    });
  });

  group('practitioner profile', () {
    test('offline, the signed-in practitioner is still readable', () async {
      // No token and no server: this is a device that has never been online.
      ApiClient.httpClient = _offline();
      final doctor = await AuthService.instance.register(
        email: 'clinic@example.com',
        password: 'Secret123',
        fullName: 'Dr Clinic',
      );

      final shown = await AuthService.instance.getCurrentDoctor();

      // The profile screen renders this; an error here leaves the
      // practitioner unable to see who they are signed in as.
      expect(shown.email, doctor.email);
      expect(shown.fullName, 'Dr Clinic');
    });

    test(
        'offline, an edited profile is saved on the device with a pending push',
        () async {
      await _cacheSignedIn(password: 'Secret123');
      await tokens.write('token');
      ApiClient.httpClient = _offline();

      final saved = await AuthService.instance.updateMyProfile(
        fullName: 'Dr Renamed',
        hospitalName: 'Mulago',
      );

      expect(saved.fullName, 'Dr Renamed');
      final draft = await DoctorDraftStorage.findByEmail('doctor@example.com');
      expect(draft!.profile.fullName, 'Dr Renamed');
      expect(draft.profile.hospitalName, 'Mulago');
      // Still owed to the server, so a later `/auth/me` must not revert it.
      expect(draft.pendingProfile, {
        'full_name': 'Dr Renamed',
        'hospital_name': 'Mulago',
      });
    });

    test(
        'the pending edit is sent and cleared the next time the server answers',
        () async {
      await _cacheSignedIn(password: 'Secret123');
      await tokens.write('token');
      ApiClient.httpClient = _offline();
      await AuthService.instance
          .updateMyProfile(fullName: 'Dr Renamed', hospitalName: 'Mulago');

      var patched = <String, dynamic>{};
      // The server that accepted the edit answers /auth/me with it, which is
      // what keeps the flush and the read in step.
      var serverProfile = _doctorJson();
      ApiClient.httpClient = MockClient((request) async {
        final path = request.url.path;
        if (request.method == 'PATCH' && path.endsWith('/auth/me')) {
          patched = jsonDecode(request.body) as Map<String, dynamic>;
          serverProfile = {...serverProfile, ...patched};
          return http.Response(jsonEncode(serverProfile), 200);
        }
        if (path.endsWith('/auth/me')) {
          return http.Response(jsonEncode(serverProfile), 200);
        }
        return http.Response('Not found', 404);
      });

      final doctor = await AuthService.instance.getCurrentDoctor();

      // The edit wins over the server's stale name, and is not left queued.
      expect(patched['full_name'], 'Dr Renamed');
      expect(patched['hospital_name'], 'Mulago');
      expect(doctor.fullName, 'Dr Renamed');
      final draft = await DoctorDraftStorage.findByEmail('doctor@example.com');
      expect(draft!.pendingProfile, isNull);
      expect(draft.profile.fullName, 'Dr Renamed');
    });
  });

  group('password hashing', () {
    test('the same salt reproduces the stored value', () {
      final first = DoctorDraft.hash('Secret123', salt: 'fixed-salt');
      final second = DoctorDraft.hash('Secret123', salt: 'fixed-salt');

      expect(first, second);
    });

    test('two accounts with the same password do not share a hash', () {
      final first = DoctorDraft.hash('Secret123');
      final second = DoctorDraft.hash('Secret123');

      expect(first, isNot(second));
    });

    test('a stored value carries its own salt and cost', () {
      final parts = DoctorDraft.hash('Secret123').split(r'$');

      expect(parts, hasLength(4));
      expect(parts.first, 'pbkdf2-sha256');
      expect(int.parse(parts[1]), greaterThan(1000));
      expect(parts[2], hasLength(32));
    });

    test('a legacy hash is flagged for rehashing', () {
      final draft = DoctorDraft(
        localId: 1,
        profile: _doctor(),
        passwordHash: 'deadbeef',
        savedAt: DateTime.now(),
      );

      expect(draft.needsRehash, isTrue);
      expect(draft.verifyPassword('Secret123'), isFalse);
    });
  });

  group('trust window', () {
    test('falls back to savedAt for caches written before verification dates',
        () {
      final savedAt = DateTime.now().subtract(const Duration(days: 9));
      final draft = DoctorDraft(
        localId: 1,
        profile: _doctor(),
        passwordHash: DoctorDraft.hash('Secret123'),
        savedAt: savedAt,
      );

      expect(draft.trustAnchor, savedAt);
      expect(
          draft.isTrustExpired(DateTime.now(), AuthService.offlineTrustWindow),
          isTrue);
    });

    test('a fresh verification overrides an old savedAt', () {
      final draft = DoctorDraft(
        localId: 1,
        profile: _doctor(),
        passwordHash: DoctorDraft.hash('Secret123'),
        savedAt: DateTime.now().subtract(const Duration(days: 30)),
        lastVerifiedAt: DateTime.now(),
      );

      expect(
          draft.isTrustExpired(DateTime.now(), AuthService.offlineTrustWindow),
          isFalse);
    });
  });
}
