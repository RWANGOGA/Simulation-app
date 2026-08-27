import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/features/dashboard/ui/practitioner_dashboard_screen.dart';
import 'package:simtack/features/dashboard/ui/practitioner_sidebar.dart';
import 'package:simtack/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  testWidgets('PractitionerDashboardScreen renders with sidebar', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(const PractitionerDashboardScreen()),
    );

    await tester.pump();

    expect(find.byType(PractitionerSidebar), findsOneWidget);
  });

  testWidgets('PractitionerDashboardScreen has top header', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(const PractitionerDashboardScreen()),
    );

    await tester.pump();

    expect(find.text('Dashboard Overview'), findsOneWidget);
  });

  testWidgets('PractitionerDashboardScreen has Row layout with sidebar', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(const PractitionerDashboardScreen()),
    );

    await tester.pump();

    final rowFinder = find.byType(Row);
    expect(rowFinder, findsWidgets);
  });

  testWidgets('PractitionerDashboardScreen shows sidebar', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      _wrap(const PractitionerDashboardScreen()),
    );

    await tester.pump();
    await tester.pump();

    expect(find.byType(PractitionerSidebar), findsOneWidget);
  });
}
