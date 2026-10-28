import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simtack/core/theme/app_breakpoints.dart';
import 'package:simtack/core/theme/app_page.dart';
import 'package:simtack/core/theme/github_kit.dart';
import 'package:simtack/features/auth/ui/login_screen.dart';
import 'package:simtack/features/auth/ui/register_screen.dart';

/// What this guards.
///
/// The console's screens had no page frame: each one opened with
/// `SingleChildScrollView(padding: EdgeInsets.all(24))` and no width limit, so
/// at 1440px the content ran the full window, and at 380px the gutter was still
/// 24 while every other screen had moved to 16. Both failures are invisible in
/// a `flutter test` run that only asserts on strings, which is exactly how they
/// survived this long.
///
/// So these tests measure geometry rather than text. They are the substitute for
/// looking at the screen: they cannot tell you whether it looks good, but they
/// do fail if a form starts stretching with the window or a page overflows its
/// viewport, which are the two things that were actually wrong.
///
/// Widths are the Material 3 window classes rather than round numbers, so a
/// regression at a class boundary is caught at that boundary: 380 (compact),
/// 900 (medium), 1440 (expanded).

const _compact = Size(380, 700);
const _medium = Size(900, 800);
const _expanded = Size(1440, 900);

/// The sizes every screen in this file must survive.
const _allSizes = <String, Size>{
  'compact': _compact,
  'medium': _medium,
  'expanded': _expanded,
};

Future<void> _pumpAt(WidgetTester tester, Size size, Widget child) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(child);
  await tester.pumpAndSettle();
}

/// A child that claims all the width it is offered, so the frame's measure can
/// be read back as a number instead of inferred from a widget's internals.
const _probe = ValueKey('page-width-probe');

Widget _probePage({double maxWidth = AppContentWidth.reading}) => MaterialApp(
      home: Scaffold(
        body: AppPage(
          maxWidth: maxWidth,
          child:
              const SizedBox(key: _probe, width: double.infinity, height: 10),
        ),
      ),
    );

void main() {
  group('AppPage applies the frame', () {
    testWidgets('gutters widen with the window class', (tester) async {
      // 16 / 24 / 32 — the three values from AppSpacing, chosen by which window
      // class the viewport falls in. Read off the frame's own Padding rather
      // than inferred from the child: once the measure is narrower than the
      // window, the leftover space is *centring*, not gutter, and subtracting
      // the two conflates them.
      const expected = <String, double>{
        'compact': 16,
        'medium': 24,
        'expanded': 32,
      };

      for (final entry in _allSizes.entries) {
        await _pumpAt(tester, entry.value, _probePage());

        final padding = tester
            .widget<Padding>(
              find
                  .descendant(
                      of: find.byType(AppPage), matching: find.byType(Padding))
                  .first,
            )
            .padding as EdgeInsets;

        expect(
          padding.left,
          expected[entry.key],
          reason: 'At ${entry.value.width}px (${entry.key}) the gutter should '
              'be ${expected[entry.key]}px, got ${padding.left}. A phone-sized '
              'window paying a desktop gutter is what made the narrow layouts '
              'feel cramped.',
        );
        expect(padding.right, padding.left);
      }
    });

    testWidgets('content grows with the window, then stops at the measure',
        (tester) async {
      // The measure bounds the box *including* its own gutters, so the text
      // width is `maxWidth - 2 * gutter`. What matters here is the shape of the
      // curve, not the arithmetic: more window means more content width, until
      // the cap, after which more window changes nothing.
      await _pumpAt(tester, const Size(900, 800), _probePage(maxWidth: 1200));
      final atNineHundred = tester.getSize(find.byKey(_probe)).width;

      await _pumpAt(tester, const Size(1440, 900), _probePage(maxWidth: 1200));
      final atFourteenForty = tester.getSize(find.byKey(_probe)).width;

      await _pumpAt(tester, const Size(2000, 900), _probePage(maxWidth: 1200));
      final atTwoThousand = tester.getSize(find.byKey(_probe)).width;

      expect(atNineHundred, lessThan(atFourteenForty),
          reason:
              'below the measure, a wider window must give the content more '
              'room');
      expect(
        atTwoThousand,
        atFourteenForty,
        reason: 'a 2000px window gave the content $atTwoThousand px after a '
            '1440px window gave it $atFourteenForty px. Past the measure the '
            'content is supposed to stop growing, which is the entire point of '
            'having a measure.',
      );
      expect(atTwoThousand, lessThanOrEqualTo(1200));
    });
  });

  group('practitioner sign-in', () {
    for (final entry in _allSizes.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await _pumpAt(
            tester, entry.value, const MaterialApp(home: LoginScreen()));

        expect(
          tester.takeException(),
          isNull,
          reason: 'LoginScreen overflowed at ${entry.value.width}x'
              '${entry.value.height}. The error that would have been thrown '
              'here is the yellow-and-black stripe a user sees instead of the '
              'sign-in button.',
        );
        expect(find.text('Practitioner Portal'), findsOneWidget);
        expect(find.text('Sign In'), findsOneWidget);
      });
    }

    testWidgets('the sign-in box keeps its width instead of stretching',
        (tester) async {
      // This is the defect the Primer rewrite fixed. The old screen was a
      // `Column(crossAxisAlignment: stretch)` under a `Center`, so on a desktop
      // the two fields spanned the entire window and the page read as a
      // marketing hero rather than a login.
      await _pumpAt(tester, _expanded, const MaterialApp(home: LoginScreen()));
      final box = tester.getSize(find.byType(GhBox));
      expect(
        box.width,
        400,
        reason: 'The sign-in box stretched to ${box.width}px on a 1440px '
            'window. A 400px box is the whole point of the rewrite.',
      );
    });
  });

  group('practitioner registration', () {
    for (final entry in _allSizes.entries) {
      testWidgets('renders without overflow at ${entry.key}', (tester) async {
        await _pumpAt(
          tester,
          entry.value,
          const MaterialApp(home: RegisterScreen()),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'RegisterScreen overflowed at ${entry.value.width}x'
              '${entry.value.height}.',
        );
        // Nine fields across two boxes; the count is pinned because the tests
        // that fill the form address the fields by index.
        expect(find.byType(TextFormField), findsNWidgets(9));
      });
    }

    testWidgets('the form stops at the page measure', (tester) async {
      await _pumpAt(
          tester, _expanded, const MaterialApp(home: RegisterScreen()));
      // The measure is 560 and the box sits inside the gutter, so the form can
      // never be wider than that however wide the window gets.
      expect(
        tester.getSize(find.byType(GhBox).first).width,
        lessThanOrEqualTo(AppContentWidth.form),
      );
    });
  });

  test('the console breakpoint is the shared one, not a private number', () {
    // The four breakpoints this replaced were 600 (console nav), 700 (welcome),
    // 560 (profile) and 480 (reports). A screen branching on its own literal is
    // the reason the same window could be "wide" for one page and "narrow" for
    // the next.
    expect(AppBreakpoints.hasRoomForRail(599), isFalse);
    expect(AppBreakpoints.hasRoomForRail(600), isTrue);
    expect(AppBreakpoints.hasRoomForSecondColumn(839), isFalse);
    expect(AppBreakpoints.hasRoomForSecondColumn(840), isTrue);
    // A pane is narrower than the window, so it needs its own threshold — but
    // a named one, not a fresh literal at the call site.
    expect(AppBreakpoints.hasRoomForSidePanel(699), isFalse);
    expect(AppBreakpoints.hasRoomForSidePanel(700), isTrue);
  });
}
