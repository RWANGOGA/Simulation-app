import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:simtack/core/network/api_client.dart';
import 'package:simtack/core/offline/passport_cipher.dart';
import 'package:simtack/core/offline/passport_record.dart';
import 'package:simtack/core/offline/qr_passport.dart';
import 'package:simtack/features/success/ui/success_screen.dart';
import 'package:simtack/l10n/app_localizations.dart';

/// The patient's passport QR code used to be captioned "Encrypted QR Passport"
/// and "No internet required to view" while the payload was a plain report URL.
/// Neither was true: there was no encryption anywhere in the path, and opening
/// the report needed the network. A patient who believed the caption would hand
/// a clinic a code that does not carry their record, in a clinic with no
/// connection.
///
/// So this file does not test the wording, it tests the *agreement* between the
/// wording and the bytes. Which caption is lawful is derived from the payload by
/// [passportHint], and the sentence level is policed here, because a string that
/// promises encryption is a security claim no reviewer will re-check by hand.
///
/// Unit 3 sealed the passport, so there are now two payload families and this
/// file checks both: a `ABP1:` blob that carries the record and may claim it
/// opens offline, and the `https://…/#/report/…` link that carries nothing and
/// must not. What decides the sentence is still the bytes, never the wish — the
/// screen falls back to the URL family whenever a visit is too large to fit a
/// readable symbol (see [passportByteCeiling]), so both branches stay live.

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    );

TriageResult _result({int severity = 4}) => TriageResult(
      id: 1,
      bodyRegion: 'Head',
      painType: 'Throbbing',
      severity: severity,
      riskScore: 0.4,
      createdAt: DateTime.utc(2026, 1, 1),
    );

/// An over-sized visit: enough points that sealing would exceed the byte
/// ceiling, forcing the URL fallback the app must still caption honestly.
List<TriageResult> _tooBigToSeal() => [
      for (var i = 0; i < 40; i++)
        TriageResult(
          id: i,
          bodyRegion: 'A long body region name used to bloat the payload $i',
          painType: 'a long pain descriptor that keeps growing the record',
          severity: 10,
          riskScore: 0.9,
          createdAt: DateTime.utc(2026, 1, 1),
        ),
    ];

void main() {
  group('what a passport payload carries', () {
    test('the report link is the fallback, and a link carries no record', () {
      expect(passportPayload('P-TEST1234'), contains('#/report/P-TEST1234'));
      expect(passportCarriesRecord(passportPayload('P-TEST1234')), isFalse);
    });

    test('a sealed record is a passport and carries the record', () {
      final phrase = generatePassportPhrase();
      final sealed = PassportRecord.fromResults(
        patientCode: 'P-TEST1234',
        results: [_result()],
      ).seal(phrase);

      expect(sealed, startsWith(passportPayloadPrefix));
      expect(passportCarriesRecord(sealed), isTrue);
      // The offline sentence is only lawful for bytes that actually hold it.
      expect(openPassport(sealed, phrase).record?['c'], 'P-TEST1234');
    });

    test('only qr_passport.dart builds a passport link', () {
      // The two definitions that lived here before (one in the success screen,
      // one hardcoded to GitHub Pages in the patient overview) are what let a
      // passport change shape on one screen only, under the same caption.
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('/l10n/'))
          .where((f) => f.readAsLinesSync().any((line) =>
              line.contains('#/report/') &&
              !line.trimLeft().startsWith('//') &&
              !line.contains('deep-link') &&
              !f.path.endsWith('core/offline/qr_passport.dart')))
          .map((f) => f.path)
          .toList();

      expect(offenders, isEmpty,
          reason: 'These files build their own report link: $offenders. Use '
              'passportPayload() so a passport has one shape everywhere.');
    });

    test('a visit too large to seal falls back to the link, not a broken blob',
        () {
      // The seal must never print a symbol a camera cannot resolve; over the
      // ceiling it hands back the URL family, which passportCarriesRecord then
      // reads as "no record" so the screen says it needs the internet.
      final payload = PassportRecord.fromResults(
        patientCode: 'P-TEST1234',
        results: _tooBigToSeal(),
      ).seal(generatePassportPhrase());

      expect(passportCarriesRecord(payload), isFalse);
      // The fallback is the report link family (http/https), whose exact host
      // differs between the debug and deployment base URL.
      expect(payload, startsWith('http'));
    });

    test('the caption follows the payload, never the other way round', () {
      const offline = 'OFFLINE';
      const online = 'NEEDS INTERNET';

      expect(
        passportHint(
            payload: 'https://example.test/#/report/P-1',
            offlinePassport: offline,
            needsInternet: online),
        online,
      );
      expect(
        passportHint(
            payload: 'ABP1dGVzdA',
            offlinePassport: offline,
            needsInternet: online),
        offline,
      );
    });
  });

  group('the success screen says what the code does', () {
    testWidgets('a sealed visit claims the record travels inside the code',
        (tester) async {
      // One pain point seals to well under passportByteCeiling, so the printed
      // bytes carry the record and the offline sentence is the true one.
      final sealed = PassportRecord.fromResults(
        patientCode: 'P-TEST1234',
        results: [_result()],
      ).seal(generatePassportPhrase());
      expect(passportCarriesRecord(sealed), isTrue,
          reason: 'a one-point record must seal for this widget test to mean '
              'anything; if the shape grew, this is the line to re-measure.');

      await tester.pumpWidget(_wrap(SuccessScreen(
        patientId: 'P-TEST1234',
        allResults: [_result()],
      )));
      await tester.pump();

      expect(find.byType(QrImageView), findsWidgets);
      expect(
        find.text('The record travels inside this code, so it opens without '
            'internet'),
        findsOneWidget,
      );
      expect(find.text('Needs internet to open the report'), findsNothing);

      // The unlock phrase is printed only because the bytes are sealed. It sits
      // in a SelectableText.rich so a patient can copy it, so the label and the
      // six letters are reached through that span, not a Text.data field.
      final rendered = _selectableText(tester);
      expect(rendered, contains('Unlock phrase'));
      expect(
        RegExp(r'[ACDEFGHJKMNPQRTUWXY]{6}').hasMatch(rendered),
        isTrue,
        reason: 'a sealed card must print its six-character unlock phrase',
      );
    });

    testWidgets('a visit that cannot seal is described as needing the network',
        (tester) async {
      await tester.pumpWidget(_wrap(SuccessScreen(
        patientId: 'P-TEST1234',
        allResults: _tooBigToSeal(),
      )));
      await tester.pump();

      // The URL fallback is honest: no offline claim, no printed key.
      expect(find.text('Needs internet to open the report'), findsOneWidget);
      expect(
        find.textContaining('opens without internet'),
        findsNothing,
      );
      // The URL family prints no key, so the phrase block never appears.
      expect(_selectableText(tester), isNot(contains('Unlock phrase')));
    });

    test('nothing on the passport path claims the word "encrypted"', () {
      // The cipher exists now, but the caption names what the code is rather
      // than advertising a primitive a reader cannot verify from a card. This
      // matches the standalone word only, so a display string is caught while
      // internal identifiers on the encryption path (`_openEncrypted`,
      // `notEncrypted`) are not mistaken for a claim.
      final offenders = Directory('lib')
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.dart'))
          .where((f) => !f.path.contains('/l10n/'))
          .where((f) => f.readAsLinesSync().any((line) =>
              RegExp(r'\bencrypted\b', caseSensitive: false).hasMatch(line) &&
              !line.trimLeft().startsWith('//')))
          .map((f) => f.path)
          .toList();
      expect(offenders, isEmpty, reason: 'claims on screen: $offenders');
    });
  });

  group('translation files', () {
    test('no locale promises encryption it does not do', () {
      final offenders = <String, String>{};

      for (final file in Directory('lib/l10n')
          .listSync()
          .whereType<File>()
          .where((f) => f.path.endsWith('.arb'))) {
        final messages =
            jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
        for (final entry in messages.entries) {
          if (entry.key.startsWith('@') || entry.value is! String) continue;
          // "Paasipoota ya QR Ekusike" was the Luganda for the same false
          // caption, which is why this scans every locale and not just English.
          if (RegExp(r'encrypted|ekusike', caseSensitive: false)
                  .hasMatch(entry.value as String) ||
              RegExp(r'no internet required', caseSensitive: false)
                  .hasMatch(entry.value as String)) {
            offenders[entry.key] = '${file.path}: ${entry.value}';
          }
        }
      }

      expect(offenders, isEmpty,
          reason: 'These messages claim the passport is encrypted in words no '
              'caption uses: ${offenders.values}. The offline sentence is now '
              'lawful for a sealed payload, but the word "encrypted" is still '
              'not something a printed card can prove to its reader.');
    });
  });
}

/// The seal's salt and IV are random per call, so two seals of one record
/// differ; the phrase is what makes the bytes readable, never the shape.
String _selectableText(WidgetTester tester) => tester
    .widgetList<SelectableText>(find.byType(SelectableText))
    .map((s) => s.textSpan?.toPlainText() ?? s.data ?? '')
    .join('\n');
