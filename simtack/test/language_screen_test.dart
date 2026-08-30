import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/locale/locale_controller.dart';
import 'package:simtack/features/onboarding/ui/language_screen.dart';
import 'package:simtack/features/onboarding/ui/welcome_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  Future<void> useTallSurface(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
  }

  Widget wrap(LocaleController controller) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LanguageScreen(localeController: controller),
      );

  testWidgets('renders every language option and the consent checkbox', (tester) async {
    await useTallSurface(tester);
    await tester.pumpWidget(wrap(LocaleController()));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Luganda'), findsOneWidget);
    expect(find.text('Runyankore'), findsOneWidget);
    expect(find.text('Lusoga'), findsOneWidget);
    expect(find.text('Kiswahili'), findsOneWidget);
    expect(find.text('Sign Language'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('tapping Continue without consent shows an error and does not navigate', (tester) async {
    await useTallSurface(tester);
    final controller = LocaleController();
    await tester.pumpWidget(wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(find.text('Please accept to continue'), findsOneWidget);
    expect(controller.hasConsented, isFalse);
    expect(find.byType(LanguageScreen), findsOneWidget);
  });

  testWidgets('accepting consent and continuing persists the choice and opens WelcomeScreen', (tester) async {
    await useTallSurface(tester);
    final controller = LocaleController();
    await tester.pumpWidget(wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Luganda'));
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(controller.hasConsented, isTrue);
    expect(controller.locale?.languageCode, 'lg');
    expect(find.byType(WelcomeScreen), findsOneWidget);
    expect(find.byType(LanguageScreen), findsNothing);
  });

  testWidgets('choosing Sign Language records it without setting a text locale', (tester) async {
    await useTallSurface(tester);
    final controller = LocaleController();
    await tester.pumpWidget(wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Sign Language'));
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(controller.isSignLanguage, isTrue);
    expect(controller.locale, isNull);
  });

  testWidgets('choosing Kiswahili persists the sw locale', (tester) async {
    await useTallSurface(tester);
    final controller = LocaleController();
    await tester.pumpWidget(wrap(controller));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Kiswahili'));
    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    expect(controller.hasConsented, isTrue);
    expect(controller.locale?.languageCode, 'sw');
    expect(find.byType(WelcomeScreen), findsOneWidget);
  });
}
