import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/offline/passport_codec.dart';

/// The bytes behind a printed passport.
///
/// These tests protect two separate promises: a record that is sealed must come
/// back exactly as it went in, and the printed form must stay small enough that
/// an ordinary camera sees a link rather than a wall of base64.
void main() {
  Map<String, dynamic> record() => {
        'c': 'A1B2C3D4E5F6G7H8',
        'i': 'v-0123456789abcdef',
        't': '2026-10-27T09:41:00.000Z',
        'k': 0.73,
        'g': 'orange',
        'e': 'urgent',
        'a': 'Go to the nearest emergency unit today.',
        'p': [
          {'r': 'Chest / Heart', 's': 9, 'y': 'Burning', 'g': 'red'},
          {'r': 'Neck / Shoulders', 's': 4, 'y': 'dull'},
        ],
      };

  group('compact passport record', () {
    test('round-trips every field exactly', () {
      final original = record();
      final decoded = decodePassportRecord(encodePassportRecord(original));

      expect(decoded, original);
    });

    test('keeps a region or pain type it has no code for', () {
      final original = {
        'c': 'P-UNKNOWN',
        'p': [
          {
            'r': 'A region from a future intake form',
            's': 6,
            'y': 'electric',
          },
        ],
      };

      expect(
        decodePassportRecord(encodePassportRecord(original)),
        original,
      );
    });

    test('keeps the spelling of a lower-case pain type', () {
      final original = {
        'c': 'P-CASE',
        'p': [
          {'r': 'Left Arm', 's': 3, 'y': 'burning'},
        ],
      };

      expect(
        decodePassportRecord(encodePassportRecord(original)),
        original,
      );
    });

    test('is far smaller than the JSON it replaced', () {
      // This is the whole reason the format exists. The old JSON record was
      // readable but its field names and punctuation dominated the payload.
      final original = record();
      final jsonBytes = utf8.encode(jsonEncode(original)).length;
      final compactBytes = encodePassportRecord(original).length;

      expect(
        compactBytes,
        lessThan(jsonBytes ~/ 2),
        reason: 'compact=$compactBytes JSON=$jsonBytes — the printed link is '
            'still dominated by the record',
      );
    });

    test('reads the JSON plaintext printed by earlier builds', () {
      // Cards already on paper cannot be reissued, so the decoder has to keep
      // understanding the format those cards were sealed with.
      final original = record();
      final legacyJson = Uint8List.fromList(utf8.encode(jsonEncode(original)));

      expect(decodePassportRecord(legacyJson), original);
    });

    test('refuses a version it does not know', () {
      expect(
        () => decodePassportRecord(Uint8List.fromList([99, 0])),
        throwsFormatException,
      );
    });

    test('refuses a truncated record instead of inventing fields', () {
      final bytes = encodePassportRecord(record());

      expect(
        () => decodePassportRecord(bytes.sublist(0, bytes.length - 2)),
        throwsFormatException,
      );
    });
  });
}
