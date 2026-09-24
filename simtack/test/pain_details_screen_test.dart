import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:simtack/features/body_map/ui/pain_details_screen.dart';
import 'package:simtack/features/body_map/ui/pain_point.dart';
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

  group('PainDetailsScreen Widget Tests', () {
    testWidgets('renders pain point location, pain type chips, and intensity slider', (WidgetTester tester) async {
      final points = [
        PainPoint(region: 'Chest / Heart', x: 0.5, y: 0.4, severity: 8, painType: 'Sharp'),
      ];

      await tester.pumpWidget(_wrap(PainDetailsScreen(
          painPoints: points,
          patientId: 1,
          modelAsset: 'assets/models/human_body_female.glb',
        )));
      await tester.pump();

      expect(find.text('Chest / Heart'), findsOneWidget);
      expect(find.text('Pain Type'), findsOneWidget);
      expect(find.text('Sharp'), findsWidgets);
      expect(find.text('Dull'), findsOneWidget);
      expect(find.text('Burning'), findsOneWidget);
      expect(find.text('Cramping'), findsOneWidget);
      expect(find.text('8 / 10'), findsOneWidget);
      expect(find.text('Next: Measure Vitals'), findsOneWidget);
    });

    testWidgets('wizarded multi-location navigation cycles through points', (WidgetTester tester) async {
      final points = [
        PainPoint(region: 'Chest / Heart', x: 0.5, y: 0.4, severity: 8, painType: 'Sharp'),
        PainPoint(region: 'Right Leg / Knee', x: 0.7, y: 0.8, severity: 4, painType: 'Dull'),
      ];

      await tester.pumpWidget(_wrap(PainDetailsScreen(
          painPoints: points,
          patientId: 1,
          modelAsset: 'assets/models/human_body_female.glb',
        )));
      await tester.pump();

      expect(find.text('Chest / Heart'), findsOneWidget);
      expect(find.text('Next Location'), findsOneWidget);

      await tester.tap(find.text('Next Location'));
      await tester.pump();

      expect(find.text('Right Leg / Knee'), findsOneWidget);
      expect(find.text('Next: Measure Vitals'), findsOneWidget);
    });
  });
}
