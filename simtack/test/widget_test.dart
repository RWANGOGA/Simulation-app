import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/locale/locale_controller.dart';
import 'package:simtack/features/onboarding/ui/language_screen.dart';
import 'package:simtack/features/onboarding/ui/welcome_screen.dart';
import 'package:simtack/main.dart';

void main() {
  setUp(() {
    // WelcomeScreen loads a saved draft via SharedPreferences in initState,
    // so we must seed an empty mock store before pumping the widget.
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> useTallSurface(WidgetTester tester) async {
    // The default 800x600 test viewport is too short for these screens'
    // Columns; use a phone-sized surface so the layout doesn't overflow.
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  testWidgets('AtomyBridgeApp shows LanguageScreen first when consent has not been given yet',
      (WidgetTester tester) async {
    await useTallSurface(tester);

    await tester.pumpWidget(const AtomyBridgeApp(isDoctorLoggedIn: false));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(LanguageScreen), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsNothing);
  });

  testWidgets('AtomyBridgeApp goes straight to WelcomeScreen once consent was already given',
      (WidgetTester tester) async {
    await useTallSurface(tester);

    final locale = LocaleController();
    await locale.setLanguageAndConsent(languageCode: 'en', consented: true);

    await tester.pumpWidget(AtomyBridgeApp(isDoctorLoggedIn: false, locale: locale));
    await tester.pumpAndSettle();

    expect(find.byType(MaterialApp), findsOneWidget);
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(LanguageScreen), findsNothing);
  });

  testWidgets('running under the Luganda locale does not crash with "No MaterialLocalizations found"',
      (WidgetTester tester) async {
    // Flutter's own Material/Cupertino localizations don't ship Luganda —
    // without the fallback delegates in main.dart, setting the app's
    // locale to "lg" throws the moment any framework widget (a button,
    // the drafts bottom sheet) needs its default strings. This is a
    // regression test for that exact crash.
    await useTallSurface(tester);

    final locale = LocaleController();
    await locale.setLanguageAndConsent(languageCode: 'lg', consented: true);

    final errors = <FlutterErrorDetails>[];
    final originalOnError = FlutterError.onError;
    FlutterError.onError = (details) => errors.add(details);
    addTearDown(() => FlutterError.onError = originalOnError);

    await tester.pumpWidget(AtomyBridgeApp(isDoctorLoggedIn: false, locale: locale));
    await tester.pumpAndSettle();

    expect(errors, isEmpty);
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
