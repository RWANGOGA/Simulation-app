import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/auth/ui/login_screen.dart';
import 'package:simtack/features/dashboard/ui/practitioner_dashboard_screen.dart';

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

/// A MockClient that handles the full login + dashboard data flow,
/// so that navigating to PractitionerDashboardScreen doesn't crash
/// on unmocked network calls.
MockClient _fullFlowClient() => MockClient((request) async {
  final path = request.url.path;

  if (path.endsWith('/auth/login')) {
    return http.Response(
      jsonEncode({'access_token': 'nav.test.token', 'token_type': 'bearer'}),
      200,
    );
  }
  if (path.endsWith('/auth/me')) {
    return http.Response(
      jsonEncode({'id': 1, 'email': 'doc@test.com', 'full_name': 'Dr. Nav', 'is_active': true}),
      200,
    );
  }
  // Dashboard data endpoints (called by PractitionerDashboardScreen.initState)
  if (path.endsWith('/triage/stats')) {
    return http.Response(
      jsonEncode({'total': 0, 'high_risk': 0, 'medium_risk': 0, 'low_risk': 0}),
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

  group('LoginScreen rendering', () {
    testWidgets('renders title, email, password, and Sign In button', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.text('Practitioner Portal'), findsOneWidget);
      expect(find.text('Sign In'), findsOneWidget);
      expect(find.byType(TextField), findsNWidgets(2));
    });
  });

  group('LoginScreen validation', () {
    testWidgets('shows validation error when both fields are empty', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter both email and password.'), findsOneWidget);
      // No network call should have been made
      expect(await ApiClient.tokenStorage.read(), isNull);
    });

    testWidgets('shows validation error when only email is filled', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'doc@test.com');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Please enter both email and password.'), findsOneWidget);
    });
  });

  group('LoginScreen failed login', () {
    testWidgets('shows backend error message on 401', (tester) async {
      ApiClient.httpClient = MockClient((request) async {
        return http.Response(jsonEncode({'detail': 'Incorrect email or password'}), 401);
      });

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'doc@test.com');
      await tester.enterText(find.byType(TextField).last, 'wrongpass');
      await tester.tap(find.text('Sign In'));
      await tester.pumpAndSettle();

      expect(find.text('Incorrect email or password'), findsOneWidget);
      // Should still be on the login screen
      expect(find.byType(LoginScreen), findsOneWidget);
    });
  });

  group('LoginScreen navigation', () {
    testWidgets('successful login navigates to PractitionerDashboardScreen', (tester) async {
      ApiClient.httpClient = _fullFlowClient();

      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'doc@test.com');
      await tester.enterText(find.byType(TextField).last, 'correctpass');
      await tester.tap(find.text('Sign In'));

      // Let the login request + navigation complete
      await tester.pumpAndSettle(const Duration(seconds: 2));

      // pushReplacement should have replaced LoginScreen with the dashboard
      expect(find.byType(PractitionerDashboardScreen), findsOneWidget);
      expect(find.byType(LoginScreen), findsNothing);
    });
  });
}
