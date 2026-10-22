import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/auth/ui/register_screen.dart';
import 'package:simtack/features/auth/ui/login_screen.dart';
import 'package:simtack/features/dashboard/ui/practitioner_dashboard_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

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

/// MockClient covering register -> auto-login -> dashboard data flow.
///
/// [approved] mirrors the server contract: a new account is inert until an
/// administrator approves it, so only an approved account gets logged in.
MockClient _registerFlowClient({bool approved = true}) =>
    MockClient((request) async {
      final path = request.url.path;
      if (path.endsWith('/auth/register')) {
        return http.Response(
          jsonEncode({
            'id': 42,
            'email': 'newdoc@test.com',
            'full_name': 'Dr. New',
            'role': 'Doctor',
            'license_number': 'LIC-1',
            'is_active': true,
            'is_approved': approved,
            'access_level': approved ? 'admin' : 'practitioner',
          }),
          201,
        );
      }
      if (path.endsWith('/auth/login')) {
        return http.Response(
          jsonEncode(
              {'access_token': 'reg.test.token', 'token_type': 'bearer'}),
          200,
        );
      }
      if (path.endsWith('/auth/me')) {
        return http.Response(
          jsonEncode({
            'id': 42,
            'email': 'newdoc@test.com',
            'full_name': 'Dr. New',
            'is_active': true,
            // login() resolves the signed-in doctor through /auth/me, so the
            // approval state has to be here as well as in the register body.
            'is_approved': approved,
            'access_level': approved ? 'admin' : 'practitioner',
          }),
          200,
        );
      }
      if (path.endsWith('/triage/stats')) {
        return http.Response(
          jsonEncode(
              {'total': 0, 'high_risk': 0, 'medium_risk': 0, 'low_risk': 0}),
          200,
        );
      }
      if (path.endsWith('/triage/list')) {
        return http.Response(jsonEncode([]), 200);
      }
      return http.Response('Not found', 404);
    });

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

  testWidgets('renders all required practitioner fields', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Create Practitioner Account'), findsOneWidget);
    expect(find.text('Join Simtack Care'), findsOneWidget);
    // name, email, license, DOB (picker), phone, hospital, invite code, password, confirm
    expect(find.byType(TextFormField), findsNWidgets(9));
    expect(find.text('Doctor'), findsWidgets); // dropdown default
    expect(find.text('Create Account'), findsOneWidget);
  });

  testWidgets('empty form shows validation errors and makes no network call',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.text('Enter your full name.'), findsOneWidget);
    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Enter your license or registration number.'),
        findsOneWidget);
    expect(find.text('At least 8 characters required.'), findsOneWidget);
    expect(await ApiClient.tokenStorage.read(), isNull);
  });

  testWidgets('rejects mismatched password confirmation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
    await tester.pumpAndSettle();

    // fields: name, email, license, DOB(picker), phone, hospital, invite code, password, confirm
    await tester.enterText(find.byType(TextFormField).at(7), 'Passw0rd1');
    await tester.enterText(find.byType(TextFormField).at(8), 'Different1');

    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle();

    expect(find.text('Passwords do not match.'), findsOneWidget);
  });

  testWidgets('successful registration logs in and opens the dashboard',
      (tester) async {
    // Make the surface tall so the submit button is reachable.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    ApiClient.httpClient = _registerFlowClient();

    await tester.pumpWidget(const MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: RegisterScreen(),
    ));
    await tester.pumpAndSettle();

    // Field order: 0 name, 1 email, 2 license, 3 DOB (picker, skipped),
    // 4 phone, 5 hospital, 6 invite code (left blank — open registration),
    // 7 password, 8 confirm.
    await tester.enterText(find.byType(TextFormField).at(0), 'Dr. New');
    await tester.enterText(find.byType(TextFormField).at(1), 'newdoc@test.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'LIC-1');
    await tester.enterText(find.byType(TextFormField).at(4), '+256700111222');
    await tester.enterText(find.byType(TextFormField).at(5), 'Mulago Hospital');
    await tester.enterText(find.byType(TextFormField).at(7), 'Passw0rd1');
    await tester.enterText(find.byType(TextFormField).at(8), 'Passw0rd1');

    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    // register -> auto-login stored a token, dashboard replaced the form
    expect(await ApiClient.tokenStorage.read(), 'reg.test.token');
    expect(find.byType(PractitionerDashboardScreen), findsOneWidget);
    expect(find.byType(RegisterScreen), findsNothing);
  });

  testWidgets('unapproved registration creates the account without signing in',
      (tester) async {
    // Registration is open, so the account exists immediately — but it stays
    // inert until an administrator approves it. Jumping to the dashboard here
    // would land the user on a screen where every request is refused.
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    ApiClient.httpClient = _registerFlowClient(approved: false);

    final navigatorKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      navigatorKey: navigatorKey,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(body: Center(child: Text('Sign In'))),
    ));
    navigatorKey.currentState!
        .push(MaterialPageRoute(builder: (_) => const RegisterScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), 'Dr. New');
    await tester.enterText(find.byType(TextFormField).at(1), 'newdoc@test.com');
    await tester.enterText(find.byType(TextFormField).at(2), 'LIC-1');
    await tester.enterText(find.byType(TextFormField).at(7), 'Passw0rd1');
    await tester.enterText(find.byType(TextFormField).at(8), 'Passw0rd1');

    await tester.ensureVisible(find.text('Create Account'));
    await tester.tap(find.text('Create Account'));
    await tester.pumpAndSettle(const Duration(seconds: 2));

    expect(find.textContaining('administrator must approve'), findsOneWidget);
    // No token, no dashboard: the pending account is not signed in.
    expect(await ApiClient.tokenStorage.read(), isNull);
    expect(find.byType(PractitionerDashboardScreen), findsNothing);
    // Sent back to the caller instead of being stranded on a dead form.
    expect(find.byType(RegisterScreen), findsNothing);
    expect(find.text('Sign In'), findsOneWidget);
  });

  testWidgets('login screen exposes the create-account entry point',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.text('Create an account'), findsOneWidget);
    await tester.tap(find.text('Create an account'));
    await tester.pumpAndSettle();
    expect(find.byType(RegisterScreen), findsOneWidget);
  });
}
