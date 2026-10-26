import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/theme/app_accent.dart';
import 'package:simtack/core/theme/app_theme.dart';
import 'package:simtack/core/theme/app_palette.dart';

/// WCAG 2.2 contrast ratio between two opaque colours.
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

/// AA body text, and AA for large text and non-text indicators.
const _bodyText = 4.5;
const _nonText = 3.0;

void main() {
  testWidgets(
      'lightTheme sets Inter as the default font, applied to plain Text widgets',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme,
      // A Text widget with no fontFamily of its own — this is how nearly
      // every screen in the app builds its TextStyles, so this proves the
      // font actually cascades rather than just being declared and unused.
      home: const Scaffold(body: Text('Hello', style: TextStyle(fontSize: 16))),
    ));

    final textWidget = tester.widget<Text>(find.text('Hello'));
    final resolvedFont = DefaultTextStyle.of(tester.element(find.text('Hello')))
        .style
        .fontFamily;

    expect(textWidget.style?.fontFamily,
        isNull); // confirms the widget itself set nothing
    expect(resolvedFont, 'Inter'); // yet the ambient default is Inter
  });

  testWidgets('darkTheme also sets Inter as the default font',
      (WidgetTester tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.darkTheme,
      home: const Scaffold(body: Text('Hello')),
    ));

    expect(
        Theme.of(tester.element(find.text('Hello')))
            .textTheme
            .bodyMedium
            ?.fontFamily,
        'Inter');
  });

  group('accent contrast', () {
    // The two surfaces accents sit on. Checked against AppPalette below so these
    // constants cannot drift from it silently.
    const lightSurface = Color(0xFFFFFFFF);
    const darkSurface = Color(0xFF1E293B);

    testWidgets('AppPalette surfaces are the ones the ratios assume',
        (tester) async {
      // One pump per test on purpose: MaterialApp animates between themes, so a
      // tree that starts empty is the only tree whose first frame is final.
      late Color light;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.lightTheme,
        home: Builder(builder: (context) {
          light = AppPalette.surface(context);
          return const SizedBox.shrink();
        }),
      ));
      expect(light, lightSurface);
    });

    testWidgets('AppPalette dark surface is the one the ratios assume',
        (tester) async {
      late Color dark;
      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.darkTheme,
        home: Builder(builder: (context) {
          dark = AppPalette.surface(context);
          return const SizedBox.shrink();
        }),
      ));
      expect(dark, darkSurface);
    });

    test('every accent clears AA against the surface it sits on', () {
      final textAccents = <String, Color Function(Brightness)>{
        'primary': AppAccent.primaryOn,
        'danger': AppAccent.dangerOn,
        'success': AppAccent.successOn,
        'warning': AppAccent.warningOn,
        'info': AppAccent.infoOn,
      };

      for (final entry in textAccents.entries) {
        for (final brightness in Brightness.values) {
          final accent = entry.value(brightness);
          final surface =
              brightness == Brightness.dark ? darkSurface : lightSurface;
          final ratio = _ratio(accent, surface);

          expect(ratio, greaterThanOrEqualTo(_bodyText),
              reason: '${entry.key} is ${ratio.toStringAsFixed(2)}:1 on the '
                  '$brightness surface, below the AA body-text bar of 4.5. An '
                  'accent that does not adapt is how violet labels ended up at '
                  '2.06:1 in dark mode.');
        }
      }
    });

    test('non-text accents clear AA for indicators, not for text', () {
      expect(_ratio(AppAccent.fieldErrorOn(Brightness.light), lightSurface),
          greaterThanOrEqualTo(_nonText));
      expect(_ratio(AppAccent.successFill, lightSurface),
          greaterThanOrEqualTo(_nonText));
      expect(_ratio(AppAccent.primaryFill, AppAccent.onPrimary),
          greaterThanOrEqualTo(_bodyText));
      expect(_ratio(AppAccent.dangerFill, lightSurface),
          greaterThanOrEqualTo(_bodyText));

      // amber-500 is 2.15:1 on white: below even the 3:1 non-text bar. Pinned as
      // a fact so nobody promotes it to a text colour on the strength of its hue
      // looking readable — the text shade of the same hue does clear AA.
      expect(_ratio(AppAccent.warningFill, lightSurface), lessThan(_nonText));
      expect(_ratio(AppAccent.warningOn(Brightness.light), lightSurface),
          greaterThanOrEqualTo(_bodyText));
    });

    test('the brand violet changes with brightness', () {
      // The one thing that must not be true: a single violet for both.
      expect(AppAccent.primaryOn(Brightness.light),
          isNot(AppAccent.primaryOn(Brightness.dark)));
      // And the light value is the hex the app has always used.
      expect(AppAccent.primaryOn(Brightness.light), const Color(0xFF6D28D9));
    });
  });
}
