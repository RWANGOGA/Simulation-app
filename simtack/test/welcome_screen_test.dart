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

    testWidgets('renders the badge, headline, description, and continue button',
        (WidgetTester tester) async {
      // Language is now chosen once, earlier, on LanguageScreen (see
      // language_screen_test.dart) — WelcomeScreen no longer has its own
      // language picker.
      //
      // welcomeTitle/welcomeSubtitle ("Welcome" / "Let's get started") are
      // no longer shown on screen — replaced by a badge + two-tone
      // headline + description, styled after a landing-page reference the
      // user shared directly. Those two old keys are left in the arb files
      // unused rather than deleted, in case anything else ever wants the
      // short version.
      await tester.pumpWidget(wrap());
      await tester.pumpAndSettle();

      expect(find.text('AI-powered triage'), findsOneWidget);
      // Text.rich/RichText matches on its combined plain text, so the two
      // TextSpans (normal-color prefix + accent-color highlight) are found
      // as one string here.
      expect(
          find.text(
              'Point to where it hurts. Understand your risk in minutes.'),
          findsOneWidget);
      expect(
          find.textContaining(
              'AtomyBridge Care turns where it hurts into a clear'),
          findsOneWidget);
      expect(find.text('Continue'), findsOneWidget);
      expect(find.text('Practitioner Login'), findsOneWidget);
    });

    testWidgets(
        'renders in Luganda when that locale is active, with the new welcome copy falling back to English',
        (WidgetTester tester) async {
      await tester.pumpWidget(wrap(locale: const Locale('lg')));
      await tester.pumpAndSettle();

      // Genuinely translated strings still work correctly in Luganda.
      expect(find.text('Weyongereyo'), findsOneWidget);
      expect(find.text("Okuyingira kw'Omusawo"), findsOneWidget);
      // The four new welcome-copy keys have no Luganda translation yet —
      // `flutter gen-l10n` auto-fills the template (English) text for
      // them, confirmed directly by inspecting the generated
      // app_localizations_lg.dart rather than assumed. This is the
      // intended graceful fallback, not a bug: every other string on this
      // screen is properly translated, only these four are English for
      // now.
      expect(find.text('AI-powered triage'), findsOneWidget);
      // The pre-existing hardcoded English CTA/login strings must not
      // leak through untranslated now that they ARE translated.
      expect(find.text('Continue'), findsNothing);
      expect(find.text('Practitioner Login'), findsNothing);
    });
  });
}
