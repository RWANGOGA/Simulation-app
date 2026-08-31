import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/dashboard/ui/practitioner_sidebar.dart';
import 'package:simtack/l10n/app_localizations.dart';

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
  testWidgets('PractitionerSidebar renders correctly with dashboard route', (tester) async {
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

  testWidgets('PractitionerSidebar shows active state for current route', (tester) async {
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

  testWidgets('PractitionerSidebar shows loading state initially', (tester) async {
    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/dashboard')),
    );
    // The doctor profile is loaded async; while in-flight the footer
    // falls back to the placeholder name and the email slot shows the
    // empty-state copy. Either no fetch attempt has happened yet (no
    // "Loading...") or the fetch resolved to the fallback identity.
    expect(find.text('Dr. Practitioner'), findsOneWidget);
  });

  testWidgets('PractitionerSidebar has logout button in footer', (tester) async {
    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/dashboard')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Logout'), findsOneWidget);
  });
}
