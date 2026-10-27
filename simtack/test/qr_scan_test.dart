import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/offline/passport_cipher.dart';
import 'package:simtack/core/offline/passport_record.dart';
import 'package:simtack/features/dashboard/ui/qr_scan_screen.dart';

void main() {
  group('QrScanScreen.extractPatientCode', () {
    test('extracts the code from a production deep-link QR', () {
      expect(
        QrScanScreen.extractPatientCode(
          'https://rwangoga.github.io/Simulation-app/#/report/P-770043',
        ),
        'P-770043',
      );
    });

    test('extracts the code from a localhost debug QR', () {
      expect(
        QrScanScreen.extractPatientCode(
            'http://localhost:5000/#/report/P-BH8TJWGBGBH5'),
        'P-BH8TJWGBGBH5',
      );
    });

    test('accepts a plain code payload', () {
      expect(QrScanScreen.extractPatientCode('P-1234AB'), 'P-1234AB');
    });

    test('returns null for an unrelated QR', () {
      expect(
          QrScanScreen.extractPatientCode('https://example.com/menu'), isNull);
      expect(QrScanScreen.extractPatientCode(''), isNull);
    });
  });

  group('the two families the camera meets', () {
    const record = PassportRecord(
      patientCode: 'P-770043',
      tier: 'orange',
      points: [
        PassportPoint(
            bodyRegion: 'Chest / Heart', severity: 7, painType: 'crushing'),
      ],
    );

    test('a legacy link resolves to a code with no phrase and no record', () {
      final outcome = QrScanScreen.openScanned(
          'https://example.test/#/report/P-770043', '');
      expect(outcome.hasCode, isTrue);
      expect(outcome.code, 'P-770043');
      expect(outcome.isOffline, isFalse);
      expect(outcome.online, isTrue);
    });

    test('a sealed passport opens with the phrase and hands back the record',
        () {
      final phrase = generatePassportPhrase();
      final sealed = record.seal(phrase);
      expect(QrScanScreen.isSealedPassport(sealed), isTrue);

      final outcome = QrScanScreen.openScanned(sealed, phrase);
      expect(outcome.isOffline, isTrue);
      expect(outcome.code, 'P-770043');
      expect(outcome.record?.tier, 'orange');
      expect(outcome.record?.points.single.bodyRegion, 'Chest / Heart');
    });

    test('a wrong phrase is refused with a reason, and yields nothing', () {
      final sealed = record.seal(generatePassportPhrase());
      final outcome = QrScanScreen.openScanned(sealed, 'ZZZZZZ');

      expect(outcome.hasCode, isFalse);
      expect(outcome.isOffline, isFalse);
      expect(outcome.failure, PassportFailure.authenticationFailed);
      expect(outcome.record, isNull);
    });

    test('tampered ciphertext fails the tag, never a partly readable record',
        () {
      final phrase = generatePassportPhrase();
      final sealed = record.seal(phrase);
      final bytes =
          base64Url.decode(base64Padded(sealed.substring('ABP1:'.length)));
      bytes[20] ^= 0x01;
      final tampered = 'ABP1:${base64Url.encode(bytes).replaceAll('=', '')}';

      final outcome = QrScanScreen.openScanned(tampered, phrase);

      expect(outcome.failure, PassportFailure.authenticationFailed);
      expect(outcome.record, isNull);
      expect(
          jsonEncode(outcome.record?.toMap() ?? {}), isNot(contains('Chest')));
    });

    test('an unrelated QR is unrecognised, not reported as a broken passport',
        () {
      final outcome = QrScanScreen.openScanned('https://example.com/menu', '');
      expect(outcome.hasCode, isFalse);
      expect(outcome.failure, isNull);
    });
  });
}
