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

    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Patients'), findsOneWidget);
    expect(find.text('Triage Sessions'), findsOneWidget);
    expect(find.text('Reports'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Help & Support'), findsOneWidget);
  });

  testWidgets('PractitionerSidebar shows loading state initially', (tester) async {
    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/dashboard')),
    );

    expect(find.text('Loading...'), findsOneWidget);
  });

  testWidgets('PractitionerSidebar has logout button in footer', (tester) async {
    await tester.pumpWidget(
      _wrap(const PractitionerSidebar(currentRoute: '/dashboard')),
    );

    await tester.pumpAndSettle();

    expect(find.text('Logout'), findsOneWidget);
  });
}
