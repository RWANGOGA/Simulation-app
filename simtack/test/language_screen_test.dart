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

  Widget wrap(LocaleController controller) => MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: LanguageScreen(localeController: controller),
      );

  testWidgets('renders the three language options and the consent checkbox', (tester) async {
    await tester.pumpWidget(wrap(LocaleController()));
    await tester.pumpAndSettle();

    expect(find.text('English'), findsOneWidget);
    expect(find.text('Luganda'), findsOneWidget);
    expect(find.text('Sign Language'), findsOneWidget);
    expect(find.byType(Checkbox), findsOneWidget);
    expect(find.text('Continue'), findsOneWidget);
  });

  testWidgets('tapping Continue without consent shows an error and does not navigate', (tester) async {
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
}
