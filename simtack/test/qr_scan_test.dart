import 'package:flutter_test/flutter_test.dart';
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
        QrScanScreen.extractPatientCode('http://localhost:5000/#/report/P-BH8TJWGBGBH5'),
        'P-BH8TJWGBGBH5',
      );
    });

    test('accepts a plain code payload', () {
      expect(QrScanScreen.extractPatientCode('P-1234AB'), 'P-1234AB');
    });

    test('returns null for an unrelated QR', () {
      expect(QrScanScreen.extractPatientCode('https://example.com/menu'), isNull);
      expect(QrScanScreen.extractPatientCode(''), isNull);
    });
  });
}
