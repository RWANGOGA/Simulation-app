// Coverage for BodyMapScreen — previously untested (confirmed by grepping
// the whole test/ directory for "BodyMapScreen(" before writing this: zero
// hits). Focuses on everything reachable without a live 3D tap, since the
// actual 3D view (Anatomy3DTapView) only activates on kIsWeb — under
// `flutter test`'s VM target it renders a plain "not available on this
// platform yet" placeholder (see anatomy_3d_tap_view.dart), so these tests
// exercise the manual "Add another location" picker instead. That path
// converges on the exact same downstream code a real 3D tap would drive —
// _addRegionManually -> _painPoints -> the consolidated report panel — so
// it's a faithful stand-in for verifying that panel's behavior, which is
// today's actual new work (replacing the old horizontal card carousel with
// one appended vertical list, per direct user feedback that the old layout
// "scattered" each tapped region's info across separate disconnected
// cards).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/body_map/ui/body_map_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  final defaultClient = ApiClient.httpClient;

  setUp(() {
    // Every /anatomy/ask call gets a minimal but valid canned response, so
    // AnatomyInsightCard's FutureBuilder resolves instead of hanging —
    // mirrors the same MockClient pattern triage_flow_integration_test.dart
    // already uses for this app's ApiClient.
    ApiClient.httpClient = MockClient((request) async {
      if (request.url.path.endsWith('/anatomy/ask')) {
        return http.Response(
          '{"region":"test","complaint":"","llm_used":false,"cached":false,'
          '"summary":"Test summary","structures":[],"likely_conditions":[],'
          '"red_flags":[],"suggested_questions":[],"disclaimer":"",'
          '"sources":[],"citations":[]}',
          200,
          headers: {'content-type': 'application/json'},
        );
      }
      return http.Response('{}', 200);
    });
  });

  tearDown(() {
    ApiClient.httpClient = defaultClient;
  });

  Widget buildScreen() => _wrap(BodyMapScreen(
        patientId: 1,
        patientCode: 'TEST-CODE',
        gender: 'Female',
        weightKg: 60,
        heightCm: 165,
      ));

  /// Needs a tall viewport: the default 800x600 test surface cuts off the
  /// bottom of these sheets, putting "Add another location" and the lower
  /// region-list items below the visible/tappable area — a test-harness
  /// sizing issue, not a real bug in the sheets themselves.
  Future<void> useTallViewport(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  /// A modal bottom sheet's enter transition doesn't reliably finish within
  /// one 400ms pump (confirmed directly: a single 400ms pump left the sheet
  /// still mid-animation, with its content rendering below the visible
  /// area; several smaller pumps totaling ~900ms settles it). Popping one
  /// sheet and immediately pushing another (as "Add another location"
  /// does) compounds this, so this is used after every sheet-opening tap.
  Future<void> settleModalTransition(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  /// Opens the "Selected Locations" management sheet, then "Add another
  /// location", then taps [region] in the picker list — the same code path
  /// _addRegionManually drives, independent of the 3D view.
  Future<void> addRegionManually(WidgetTester tester, String region) async {
    await tester.tap(find.byIcon(Icons.location_on));
    await settleModalTransition(tester);
    await tester.tap(find.text('Add another location'));
    await settleModalTransition(tester);
    await tester.tap(find.text(region));
    await settleModalTransition(tester);
  }

  testWidgets('shows the empty-state hint and a disabled Continue button with no locations marked',
      (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Tap the body to mark pain'), findsOneWidget);
    final continueButton = tester.widget<ElevatedButton>(find.widgetWithText(
        ElevatedButton, 'Tap the body to mark pain'));
    expect(continueButton.onPressed, isNull,
        reason: 'Continue must stay disabled until at least one location is marked');
  });

  testWidgets(
      'adding a location appends it to one consolidated report panel, not a separate scattered card',
      (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(buildScreen());
    await tester.pump(const Duration(milliseconds: 400));

    await addRegionManually(tester, 'Chest / Heart');

    // The region now appears both as the numbered header in the report
    // panel and as the AnatomyInsightCard's own title — this only proves
    // out once per added location, confirming it landed in the single
    // panel rather than duplicating across separate UI pieces.
    expect(find.text('Chest / Heart'), findsWidgets);
    expect(find.text('AI insight: Chest / Heart'), findsOneWidget);

    // Continue button should now be enabled and reflect the count.
    final continueButton = tester.widget<ElevatedButton>(find.widgetWithText(
        ElevatedButton, 'Continue to Pain Details (1)'));
    expect(continueButton.onPressed, isNotNull);
  });

  testWidgets(
      'marking two different locations appends both to the same panel (multi-select), and removing one leaves the other',
      (tester) async {
    await useTallViewport(tester);
    await tester.pumpWidget(buildScreen());
    await tester.pump(const Duration(milliseconds: 400));

    await addRegionManually(tester, 'Chest / Heart');
    await addRegionManually(tester, 'Left Leg / Knee');

    expect(find.text('AI insight: Chest / Heart'), findsOneWidget);
    expect(find.text('AI insight: Left Leg / Knee'), findsOneWidget);
    expect(
        tester.widget<ElevatedButton>(find.widgetWithText(
            ElevatedButton, 'Continue to Pain Details (2)')),
        isNotNull);

    // Remove the first one via the report panel's own inline close button
    // (the new affordance added alongside the consolidated panel) rather
    // than the separate "Selected Locations" sheet.
    await tester.tap(find.byIcon(Icons.close).first);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('AI insight: Chest / Heart'), findsNothing);
    expect(find.text('AI insight: Left Leg / Knee'), findsOneWidget);
    expect(
        tester.widget<ElevatedButton>(find.widgetWithText(
            ElevatedButton, 'Continue to Pain Details (1)')),
        isNotNull);
  });

  testWidgets('3D view placeholder renders without crashing on a non-web test target',
      (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text("The 3D body view isn't available on this platform yet."),
        findsOneWidget);
  });

  testWidgets('help dialog opens and can be dismissed', (tester) async {
    await tester.pumpWidget(buildScreen());
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byIcon(Icons.help_outline));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.tap(find.text('Got it'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(AlertDialog), findsNothing);
  });
}
