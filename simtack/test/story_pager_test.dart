import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simtack/core/widgets/story_pager.dart';
import 'package:simtack/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

void main() {
  group('StoryPager', () {
    testWidgets('one page at a time, and every item is reachable',
        (tester) async {
      await tester.pumpWidget(_wrap(StoryPager(
        count: 4,
        itemBuilder: (context, index) =>
            Center(child: Text('Point ${index + 1}')),
      )));

      // Only the current item is built into the viewport; the others exist one
      // either side, so reaching the last one is what has to be proven.
      expect(find.text('Point 1'), findsOneWidget);
      expect(find.text('Point 4'), findsNothing);

      for (var i = 2; i <= 4; i++) {
        // A fling, not a bare drag: PageScrollPhysics commits a page on distance
        // *or* velocity, and a slow 300px drag is under half the page width, so
        // it would spring back in the test without proving anything about the
        // widget. A real swipe carries the velocity a fling synthesises here.
        await tester.fling(find.byType(PageView), const Offset(-300, 0), 3000);
        await tester.pumpAndSettle();
        expect(find.text('Point $i'), findsOneWidget,
            reason: 'swiping forward should land on item $i, and the clinician '
                'has no other way to it');
      }

      await tester.fling(find.byType(PageView), const Offset(300, 0), 3000);
      await tester.pumpAndSettle();
      expect(find.text('Point 3'), findsOneWidget);
    });

    testWidgets('the rail has one segment per item and the counter moves',
        (tester) async {
      await tester.pumpWidget(_wrap(StoryPager(
        count: 3,
        itemBuilder: (context, index) => Text('Item $index'),
      )));

      expect(find.text('1 / 3'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3'), findsOneWidget);
    });

    testWidgets('nothing advances on a timer', (tester) async {
      await tester.pumpWidget(_wrap(StoryPager(
        count: 3,
        itemBuilder: (context, index) => Text('Item $index'),
      )));

      // A stories surface moves by itself. This one must not: the reader is
      // comparing findings, and a page that turns while you read it loses the
      // finding you were weighing.
      await tester.pump(const Duration(seconds: 30));
      expect(find.text('Item 0'), findsOneWidget);
      expect(find.text('1 / 3'), findsOneWidget);
    });

    testWidgets('there is no invisible tap-to-advance zone', (tester) async {
      await tester.pumpWidget(_wrap(StoryPager(
        count: 3,
        itemBuilder: (context, index) => Text('Item $index'),
      )));

      // Tapping the right half advances in WhatsApp. Here a tap on the card
      // means nothing, and a user who cannot swipe must not have to discover an
      // undocumented hot zone: the visible chevron is the control.
      await tester.tapAt(
          tester.getCenter(find.byType(PageView)) + const Offset(120, 0));
      await tester.pumpAndSettle();
      expect(find.text('Item 0'), findsOneWidget);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      expect(find.text('Item 1'), findsOneWidget);
    });

    testWidgets('the chevrons stop at the ends instead of wrapping',
        (tester) async {
      await tester.pumpWidget(_wrap(StoryPager(
        count: 2,
        itemBuilder: (context, index) => Text('Item $index'),
      )));

      // Disabled, not hidden: a control that disappears on arrival shifts the
      // layout under someone who is mid-reach for it.
      final previous = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_left));
      expect(previous.onPressed, isNull);

      await tester.tap(find.byIcon(Icons.chevron_right));
      await tester.pumpAndSettle();
      final next = tester.widget<IconButton>(
          find.widgetWithIcon(IconButton, Icons.chevron_right));
      expect(next.onPressed, isNull);
    });

    testWidgets('zero items renders no pager at all', (tester) async {
      await tester.pumpWidget(_wrap(StoryPager(
        count: 0,
        itemBuilder: (context, index) => const SizedBox.shrink(),
      )));

      expect(find.byType(PageView), findsNothing);
      expect(find.byType(StoryPager), findsOneWidget);
    });
  });
}
