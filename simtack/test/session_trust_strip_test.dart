import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:simtack/core/network/auth_service.dart';
import 'package:simtack/features/dashboard/ui/session_trust_strip.dart';
import 'package:simtack/l10n/app_localizations.dart';

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(body: child),
    );

Future<void> _pump(WidgetTester tester, SessionTrust trust) async {
  await tester
      .pumpWidget(_wrap(SessionTrustStrip(loadTrust: () async => trust)));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('says nothing when the server answered the sign-in',
      (tester) async {
    await _pump(tester,
        const SessionTrust(source: SessionSource.server, windowDays: 7));

    expect(find.byType(Text), findsNothing);
  });

  testWidgets('dates a cached sign-in and names the window', (tester) async {
    await _pump(
      tester,
      const SessionTrust(
        source: SessionSource.cachedCopy,
        windowDays: 7,
        daysSinceConfirmed: 3,
      ),
    );

    expect(find.textContaining('confirmed it 3 days ago'), findsOneWidget);
    expect(find.textContaining('for 7 days after that'), findsOneWidget);
  });

  testWidgets('a single day is not rendered as days', (tester) async {
    await _pump(
      tester,
      const SessionTrust(
        source: SessionSource.cachedCopy,
        windowDays: 7,
        daysSinceConfirmed: 1,
      ),
    );

    expect(find.textContaining('confirmed it 1 day ago'), findsOneWidget);
    expect(find.textContaining('1 days'), findsNothing);
  });

  testWidgets('a same-day confirmation says today', (tester) async {
    await _pump(
      tester,
      const SessionTrust(
        source: SessionSource.cachedCopy,
        windowDays: 7,
        daysSinceConfirmed: 0,
      ),
    );

    expect(find.textContaining('confirmed it today'), findsOneWidget);
  });

  testWidgets('an undated cached sign-in does not claim it was confirmed today',
      (tester) async {
    await _pump(
      tester,
      const SessionTrust(source: SessionSource.cachedCopy, windowDays: 7),
    );

    expect(find.textContaining('no server has confirmed'), findsOneWidget);
    expect(find.textContaining('today'), findsNothing);
  });

  testWidgets('a device-only account says it was never confirmed',
      (tester) async {
    await _pump(
      tester,
      const SessionTrust(source: SessionSource.deviceAccount, windowDays: 7),
    );

    expect(find.textContaining('created on this device'), findsOneWidget);
    expect(find.textContaining('this device only'), findsOneWidget);
  });
}
