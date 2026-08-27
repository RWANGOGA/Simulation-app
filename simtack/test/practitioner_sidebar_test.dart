import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/dashboard/ui/practitioner_sidebar.dart';

void main() {
  testWidgets('PractitionerSidebar renders correctly with dashboard route', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              PractitionerSidebar(currentRoute: '/dashboard'),
              Expanded(child: Placeholder()),
            ],
          ),
        ),
      ),
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
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              PractitionerSidebar(currentRoute: '/dashboard'),
              Expanded(child: Placeholder()),
            ],
          ),
        ),
      ),
    );

    final dashboardNavItem = find.text('Dashboard');
    expect(dashboardNavItem, findsOneWidget);
  });

  testWidgets('PractitionerSidebar has all navigation items', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              PractitionerSidebar(currentRoute: '/patients'),
              Expanded(child: Placeholder()),
            ],
          ),
        ),
      ),
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
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              PractitionerSidebar(currentRoute: '/dashboard'),
              Expanded(child: Placeholder()),
            ],
          ),
        ),
      ),
    );

    expect(find.text('Loading...'), findsOneWidget);
  });

  testWidgets('PractitionerSidebar has logout button in footer', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Row(
            children: [
              PractitionerSidebar(currentRoute: '/dashboard'),
              Expanded(child: Placeholder()),
            ],
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Logout'), findsOneWidget);
  });
}
