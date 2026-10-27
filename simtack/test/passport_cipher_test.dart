import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:simtack/core/offline/passport_cipher.dart';

/// The printed passport, as bytes and as cryptography.
///
/// These tests exist because the app used to print a plain URL under a caption
/// that said "Encrypted" and "No internet required". A payload is what decides
/// those sentences, so the payload is what is tested: it opens with the right
/// phrase, refuses everything else without leaking plaintext, and stays small
/// enough that a phone camera can actually resolve the symbol it is printed as.
void main() {
  const phrase = 'KQMTWD';
  final record = <String, dynamic>{
    'c': 'A1B2C3D4E5',
    'i': 'v-7f3a91c2',
    'p': [
      {'r': 'Chest / Heart', 's': 7, 'y': 'crushing'},
      {'r': 'Left Arm', 's': 4, 'y': 'aching'},
    ],
    'k': 0.65,
    'g': 'red',
  };

  group('sealing and opening', () {
    test('a passport opened with the printed phrase returns the record', () {
      final payload = sealPassport(record, phrase);

      expect(payload, startsWith('ABP1:'));
      // The claim the caption makes: the bytes carry the record rather than
      // pointing at a server that does.
      expect(payload, isNot(contains('http')));

      final opened = openPassport(payload, phrase);
      expect(opened.isOpened, isTrue, reason: '${opened.failure}');
      expect(opened.record, record);
    });

    test('a phrase typed in lower case or with spaces still opens it', () {
      // The phrase is read aloud off a card and typed on a phone. Failing on
      // case would make the record unrecoverable for a reason that has nothing
      // to do with the key.
      final payload = sealPassport(record, phrase);

      expect(openPassport(payload, 'kqmtwd').isOpened, isTrue);
      expect(openPassport(payload, 'K Q M T W D').isOpened, isTrue);
    });

    test('a wrong phrase is refused, and hands back nothing', () {
      final payload = sealPassport(record, phrase);
      final opened = openPassport(payload, 'KQMTWE');

      expect(opened.isOpened, isFalse);
      expect(opened.failure, PassportFailure.authenticationFailed);
      expect(opened.record, isNull);
    });

    test('an altered byte fails the tag instead of decrypting to garbage', () {
      // The point of GCM over a bare cipher: a station must never see a partly
      // readable record whose severity was edited by someone with a pen.
      final payload = sealPassport(record, phrase);
      final encoded = payload.substring('ABP1:'.length);
      final bytes = base64Url.decode(base64Padded(encoded));
      // Flip one bit in the ciphertext, past the salt and the IV.
      bytes[20] ^= 0x01;
      final tampered = 'ABP1:${base64Url.encode(bytes).replaceAll('=', '')}';

      final opened = openPassport(tampered, phrase);

      expect(opened.isOpened, isFalse);
      expect(opened.failure, PassportFailure.authenticationFailed);
      expect(jsonEncode(opened.record ?? {}), isNot(contains('Chest')));
    });

    test('a truncated or unparseable envelope is malformed, not unencrypted',
        () {
      final payload = sealPassport(record, phrase);

      expect(
        openPassport(payload.substring(0, 30), phrase).failure,
        PassportFailure.malformed,
      );
      expect(
        openPassport('ABP1:not-base64-at-all!!!', phrase).failure,
        PassportFailure.malformed,
      );
    });

    test('a legacy URL code is a different flow, not a failed passport', () {
      // The practitioner's scanner meets both families in the real world and has
      // to say which one it found rather than report a break-in for a link.
      final opened = openPassport(
        'https://rwangoga.github.io/Simulation-app/#/report/A1B2C3D4E5',
        phrase,
      );

      expect(opened.failure, PassportFailure.notAPassport);
    });

    test('sealing the same visit twice prints different bytes', () {
      // Fresh salt and IV per print, so two copies of one patient's card do not
      // reveal that they hold the same record.
      expect(sealPassport(record, phrase), isNot(sealPassport(record, phrase)));
      expect(
          openPassport(sealPassport(record, phrase), phrase).isOpened, isTrue);
    });
  });

  group('the printed phrase', () {
    test('is six characters from the unambiguous alphabet', () {
      for (var i = 0; i < 50; i++) {
        final generated = generatePassportPhrase();
        expect(generated.length, passportPhraseLength);
        expect(
          generated,
          matches(RegExp(r'^[ACDEFGHJKMNPQRTUWXY]+$')),
          reason: 'contains a character that blurs when printed small',
        );
      }
    });

    test('is not the same phrase twice in a row', () {
      final phrases =
          List.generate(200, (_) => generatePassportPhrase()).toSet();
      expect(phrases.length, greaterThan(190));
    });
  });

  group('the symbol a camera has to resolve', () {
    /// The largest record a passport is expected to carry: one patient, one
    /// visit, every pain point the intake form allows, each with the longest
    /// region and type names in the clinical data.
    Map<String, dynamic> worstCaseRecord() => {
          'c': 'A1B2C3D4E5F6G7H8',
          'i': 'v-0123456789abcdef',
          't': '2026-10-27T09:41:00Z',
          'k': 0.73,
          'g': 'orange',
          'e': 'urgent',
          'p': [
            for (final region in const [
              'Headache / Cranial',
              'Neck / Shoulders',
              'Chest / Heart',
              'Abdomen (Upper)',
              'Abdomen (Lower)',
              'Back (Lumbar)',
              'Left Arm',
              'Right Arm',
              'Left Leg',
              'Right Leg',
              'Joint (Knee)',
              'Flank / Kidney',
            ])
              {
                'r': region,
                's': 10,
                'y': 'burning',
              },
          ],
        };

    test('carries a full visit in a scannable symbol', () {
      final payload = sealPassport(worstCaseRecord(), phrase);
      final bytes = utf8.encode(payload).length;
      // Measured against the encoder the app actually prints with, not a table
      // quoted from a paper: this is the version qr_flutter would choose.
      final version = QrCode.fromData(
        data: payload,
        errorCorrectLevel: QrErrorCorrectLevel.M,
      ).typeNumber;

      // 12 points is more than any visit in the dataset; it is the ceiling, not
      // the average. Above it the app falls back to the URL code.
      expect(
        bytes,
        lessThanOrEqualTo(1000),
        reason: 'a worst-case passport of 12 pain points is $bytes bytes, '
            'which prints as QR version $version',
      );
      expect(
        version,
        lessThanOrEqualTo(30),
        reason: 'a version $version symbol at EC level M is '
            '${version * 4 + 17} modules wide, which a phone cannot resolve '
            'from a printed card at arm length.',
      );
    });

    test('an ordinary visit is far inside that ceiling', () {
      final payload = sealPassport(record, phrase);

      expect(utf8.encode(payload).length, lessThan(400));
    });
  });
}
