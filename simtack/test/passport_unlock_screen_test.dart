import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/offline/passport_record.dart';
import 'package:simtack/core/offline/qr_passport.dart';
import 'package:simtack/features/passport/ui/passport_unlock_screen.dart';

void main() {
  testWidgets('a generic scanner link unlocks locally with the printed phrase',
      (tester) async {
    const phrase = 'ACDEFG';
    const record = PassportRecord(
      patientCode: 'P-OPEN1234',
      tier: 'orange',
      points: [
        PassportPoint(
          bodyRegion: 'Chest / Heart',
          severity: 8,
          painType: 'crushing',
        ),
      ],
    );
    final link = passportLink(record.seal(phrase));

    await tester.pumpWidget(MaterialApp(
      home: PassportUnlockScreen(payload: link),
    ));

    expect(find.text('Unlock this passport'), findsOneWidget);

    await tester.enterText(find.byType(TextField), phrase);
    await tester.tap(find.text('Show patient record'));
    await tester.pumpAndSettle();

    expect(find.text('Record read offline'), findsOneWidget);
    expect(find.text('Patient P-OPEN1234'), findsOneWidget);
    expect(find.textContaining('Chest / Heart'), findsOneWidget);
  });

  testWidgets('a misread QR can be recovered by pasting the full code',
      (tester) async {
    const phrase = 'ACDEFG';
    const record = PassportRecord(
      patientCode: 'P-OPEN1234',
      points: [PassportPoint(bodyRegion: 'Head', severity: 2, painType: 'dull')],
    );
    final goodLink = passportLink(record.seal(phrase));
    final brokenLink = goodLink.substring(0, goodLink.length - 5);

    await tester.pumpWidget(MaterialApp(
      home: PassportUnlockScreen(payload: brokenLink),
    ));
    await tester.enterText(find.byType(TextField), phrase);
    await tester.tap(find.text('Show patient record'));
    await tester.pumpAndSettle();

    expect(find.textContaining('damaged or unreadable'), findsOneWidget);

    await tester.tap(find.text('Paste the full scanned code instead'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, goodLink);
    await tester.tap(find.text('Use this code'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, phrase);
    await tester.tap(find.text('Show patient record'));
    await tester.pumpAndSettle();

    expect(find.text('Record read offline'), findsOneWidget);
    expect(find.text('Patient P-OPEN1234'), findsOneWidget);
  });

  testWidgets('a wrong phrase stays on the entry step with a reason',
      (tester) async {
    const record = PassportRecord(
      patientCode: 'P-OPEN1234',
      points: [PassportPoint(bodyRegion: 'Head', severity: 1, painType: 'dull')],
    );
    final link = passportLink(record.seal('ABCDEF'));

    await tester.pumpWidget(MaterialApp(
      home: PassportUnlockScreen(payload: link),
    ));
    await tester.enterText(find.byType(TextField), 'ZZZZZZ');
    await tester.tap(find.text('Show patient record'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock this passport'), findsOneWidget);
    expect(find.textContaining('does not open this passport'), findsOneWidget);
    expect(find.text('Record read offline'), findsNothing);
  });
}
