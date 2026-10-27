import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'package:simtack/core/network/api_client.dart';
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
/// When Unit 3 lands the encrypted payload, test 4 flips: the printed data
/// starts with `ABP1`, the offline sentence becomes the true one, and the
/// encryption ban in test 5 is lifted in the same commit that implements the
/// cipher — not before.

Widget _wrap(Widget child) => MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: child,
    );

TriageResult _result() => TriageResult(
      id: 1,
      bodyRegion: 'Head',
      painType: 'Throbbing',
      severity: 4,
      riskScore: 0.4,
      createdAt: DateTime.utc(2026, 1, 1),
    );

void main() {
  group('what a passport payload carries', () {
    test('the printed passport is a link, and a link carries no record', () {
      expect(passportPayload('P-TEST1234'), contains('#/report/P-TEST1234'));
      expect(passportCarriesRecord(passportPayload('P-TEST1234')), isFalse);
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

    test('a prefixed passport blob does', () {
      // Positive case, so the gate above is a real decision and not a function
      // that always answers "no" — which would pass every other test here
      // while telling patients nothing about their own record.
      expect(passportCarriesRecord('ABP1dGVzdA'), isTrue);
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
    testWidgets('a URL payload is described as needing the network',
        (tester) async {
      await tester.pumpWidget(_wrap(SuccessScreen(
        patientId: 'P-TEST1234',
        allResults: [_result()],
      )));
      await tester.pump();

      expect(find.byType(QrImageView), findsWidgets);

      // Invariant rather than a snapshot: whatever passportPayload says about
      // these bytes, that is the caption the screen is allowed to show. When
      // the encrypted passport lands, nothing here has to be edited for it to
      // keep catching a screen that claims the wrong thing.
      final carriesRecord =
          passportCarriesRecord(passportPayload('P-TEST1234'));
      expect(
        find.text('Needs internet to open the report'),
        carriesRecord ? findsNothing : findsOneWidget,
      );
      expect(
        find.textContaining('opens without internet'),
        carriesRecord ? findsWidgets : findsNothing,
      );

      // Named as what it is: a code identifying the patient's passport.
      expect(find.text('Patient passport code'), findsWidgets);
      // And nothing on the screen may claim the code is encrypted.
      expect(find.textContaining(RegExp('encrypted', caseSensitive: false)),
          findsNothing);
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
          reason: 'These messages claim the passport is encrypted or offline '
              'while the payload is a plain URL: ${offenders.values}. The '
              'claim belongs in the paper only after the AES-GCM payload '
              'exists.');
    });
  });
}
