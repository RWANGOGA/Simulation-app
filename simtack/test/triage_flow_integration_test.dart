import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/features/body_map/ui/pain_details_screen.dart';
import 'package:simtack/features/body_map/ui/pain_point.dart';
import 'package:simtack/features/success/ui/success_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';
import 'package:webview_flutter_platform_interface/webview_flutter_platform_interface.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

class FakeWebViewPlatform extends WebViewPlatform with MockPlatformInterfaceMixin {
  @override
  PlatformWebViewController createPlatformWebViewController(PlatformWebViewControllerCreationParams params) {
    return FakeWebViewController(params);
  }

  @override
  PlatformWebViewWidget createPlatformWebViewWidget(PlatformWebViewWidgetCreationParams params) {
    return FakeWebViewWidget(params);
  }

  @override
  PlatformNavigationDelegate createPlatformNavigationDelegate(PlatformNavigationDelegateCreationParams params) {
    return FakeNavigationDelegate(params);
  }
}

class FakeWebViewController extends PlatformWebViewController {
  FakeWebViewController(super.params) : super.implementation();
  @override
  Future<void> loadRequest(LoadRequestParams params) async {}
  @override
  Future<void> setJavaScriptMode(JavaScriptMode javaScriptMode) async {}
  @override
  Future<void> setBackgroundColor(Color color) async {}
  @override
  Future<void> setPlatformNavigationDelegate(PlatformNavigationDelegate handler) async {}
  @override
  Future<void> addJavaScriptChannel(JavaScriptChannelParams javaScriptChannelParams) async {}
}

class FakeWebViewWidget extends PlatformWebViewWidget {
  FakeWebViewWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox();
}

class FakeNavigationDelegate extends PlatformNavigationDelegate {
  FakeNavigationDelegate(super.params) : super.implementation();
  @override
  Future<void> setOnNavigationRequest(NavigationRequestCallback onNavigationRequest) async {}
  @override
  Future<void> setOnPageStarted(PageEventCallback onPageStarted) async {}
  @override
  Future<void> setOnPageFinished(PageEventCallback onPageFinished) async {}
  @override
  Future<void> setOnProgress(ProgressCallback onProgress) async {}
  @override
  Future<void> setOnWebResourceError(WebResourceErrorCallback onWebResourceError) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  WebViewPlatform.instance = FakeWebViewPlatform();
  late http.Client defaultClient;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    defaultClient = ApiClient.httpClient;
  });

  tearDown(() {
    ApiClient.httpClient = defaultClient;
  });

  testWidgets('full wizard flow moves seamlessly without blocking', (WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() => tester.view.resetPhysicalSize());

    // Mock API client for backend submission
    ApiClient.httpClient = MockClient((request) async {
      return http.Response(
        jsonEncode({
          'id': 10,
          'patient_id': 5,
          'anonymous_code': 'P-TEST-123',
          'body_region': 'Chest / Heart',
          'pain_type': 'Sharp',
          'severity': 8,
          'created_at': DateTime.now().toIso8601String(),
        }),
        201,
      );
    });

    final points = [
      PainPoint(region: 'Chest / Heart', x: 0.5, y: 0.4, severity: 8, painType: 'Sharp'),
    ];

    // 1. Render PainDetailsScreen
    await tester.pumpWidget(_wrap(PainDetailsScreen(
      painPoints: points,
      patientId: 5,
      modelAsset: 'assets/models/human_body_female.glb',
    )));
    await tester.pump();

    expect(find.text('Chest / Heart'), findsOneWidget);
    expect(find.text('Next: Measure Vitals'), findsOneWidget);

    // 2. Tap Next -> Should transition to PainProfileFunctionalImpactScreen
    await tester.tap(find.text('Next: Measure Vitals'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('4 & 5. PAIN PROFILE & FUNCTIONAL IMPACT'), findsOneWidget);
    expect(find.text('SECTION A: PAIN EXPANSION BEHAVIOR'), findsOneWidget);

    // 3. Select expansion, trigger, reliever, and limitation
    await tester.tap(find.text('SPREADING'));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Walking / Moving'));
    await tester.pump(const Duration(milliseconds: 200));

    await tester.tap(find.text('Resting Flat'));
    await tester.pump(const Duration(milliseconds: 200));

    final cannotSleepFinder = find.text('CANNOT SLEEP');
    await tester.ensureVisible(cannotSleepFinder);
    await tester.tap(cannotSleepFinder);
    await tester.pump(const Duration(milliseconds: 200));

    // 4. Tap PROCEED TO REVIEW & SUBMIT -> Should transition to ReviewScreen
    final proceedBtn = find.text('PROCEED TO REVIEW & SUBMIT');
    await tester.tap(proceedBtn);
    await tester.pumpAndSettle();

    expect(find.textContaining('Review & Submit'), findsOneWidget);
    expect(find.text('Chest / Heart'), findsOneWidget);
    expect(find.text('Spreading'), findsOneWidget);
    expect(find.text('Walking / Moving'), findsOneWidget);

    // 5. Tap Submit -> Submits successfully without error
    await tester.tap(find.text('Submit'));
    await tester.pump();
    await tester.runAsync(() async => await Future.delayed(const Duration(milliseconds: 100)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    expect(find.byType(SuccessScreen), findsOneWidget);
  });
}
