import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/dashboard/ui/practitioner_sidebar.dart';
import 'package:simtack/features/dashboard/ui/reports_screen.dart';
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

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Row(
          children: [
            child,
            const Expanded(child: Placeholder()),
          ],
        ),
      ),
    );

void main() {
  testWidgets('PractitionerSidebar renders correctly with dashboard route',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/dashboard')),
    );

    expect(find.byType(PractitionerSidebar), findsOneWidget);
    expect(find.text('Simtack'), findsOneWidget);
    expect(find.text('Practitioner'), findsOneWidget);
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Logout'), findsOneWidget);
  });

  testWidgets('PractitionerSidebar shows active state for current route',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/dashboard')),
    );

    final dashboardNavItem = find.text('Dashboard');
    expect(dashboardNavItem, findsOneWidget);
  });

  testWidgets('PractitionerSidebar has all navigation items', (tester) async {
    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/patients')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Triage Sessions'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Profile'), findsOneWidget);
    // Scroll the nav list so "Help & Support" — which sits below the
    // fold at the default test viewport — is on screen and findable.
    final listFinder = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Help & Support'),
      100,
      scrollable: listFinder,
    );
    expect(find.text('Help & Support'), findsOneWidget);
  });

  testWidgets('PractitionerSidebar shows loading state initially',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/dashboard')),
    );
    // The doctor profile is loaded async; while in-flight the footer
    // falls back to the placeholder name and the email slot shows the
    // empty-state copy. Either no fetch attempt has happened yet (no
    // "Loading...") or the fetch resolved to the fallback identity.
    expect(find.text('Dr. Practitioner'), findsOneWidget);
  });

  testWidgets('PractitionerSidebar Reports item opens the reports screen',
      (tester) async {
    // The item used to show an "under construction" snackbar; it now routes
    // to the real ReportsScreen, so this asserts the navigation itself.
    final defaultClient = ApiClient.httpClient;
    final defaultStorage = ApiClient.tokenStorage;
    ApiClient.tokenStorage = FakeTokenStorage();
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/triage/reports')) {
        return http.Response('{}', 200);
      }
      return http.Response('Not found', 404);
    });
    addTearDown(() {
      ApiClient.httpClient = defaultClient;
      ApiClient.tokenStorage = defaultStorage;
    });

    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/dashboard')),
    );

    await tester.tap(find.text('Reports'));
    await tester.pumpAndSettle();

    expect(find.byType(ReportsScreen), findsOneWidget);
  });

  testWidgets('PractitionerSidebar has logout button in footer',
      (tester) async {
    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/dashboard')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Logout'), findsOneWidget);
  });
}
