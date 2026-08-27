import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:simtack/core/locale/luganda_fallback_delegates.dart';
import 'package:simtack/features/onboarding/ui/welcome_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

void main() {
  group('WelcomeScreen Widget Tests', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    Widget wrap({Locale? locale}) => MaterialApp(
          locale: locale,
          localizationsDelegates: const [
            ...AppLocalizations.localizationsDelegates,
            LugandaMaterialLocalizationsDelegate(),
            LugandaCupertinoLocalizationsDelegate(),
          ],
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WelcomeScreen(),
        );

    testWidgets('renders title, subtitle, and continue button', (WidgetTester tester) async {
      // Language is now chosen once, earlier, on LanguageScreen (see
      // language_screen_test.dart) — WelcomeScreen no longer has its own
      // language picker.
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('Welcome'), findsOneWidget);
      expect(find.text("Let's get started"), findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Practitioner Login'), findsOneWidget);
    });

    testWidgets('renders in Luganda when that locale is active', (WidgetTester tester) async {
      await tester.pumpWidget(wrap(locale: const Locale('lg')));
      await tester.pumpAndSettle();

      expect(find.text('Tukwaniriza'), findsOneWidget);
      expect(find.text('Tutandike'), findsOneWidget);
      expect(find.text('Weyongereyo'), findsOneWidget);
      expect(find.text("Okuyingira kw'Omusawo"), findsOneWidget);
      // The old hardcoded English strings must not leak through.
      expect(find.text('Welcome'), findsNothing);
      expect(find.text('Continue'), findsNothing);
    });
  });
}
