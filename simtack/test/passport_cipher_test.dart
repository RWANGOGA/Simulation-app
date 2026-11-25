import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:simtack/core/offline/passport_cipher.dart';
import 'package:simtack/core/offline/qr_passport.dart';

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

    test('a camera-scanned web link reaches the cipher with one prefix', () {
      // The web entry point strips `/passport/` from `Uri.base.fragment`. It
      // once wrapped the result in `passportLink` again, so the unlock page
      // received `ABP1:ABP1:…` and called every real card damaged. This is the
      // exact path a generic scanner takes.
      final sealed = sealPassport(record, phrase);
      final link = passportLink(sealed);
      final fragment = Uri.parse(link).fragment;

      final payload = passportPayloadFromFragment(fragment);
      expect(payload, sealed);
      expect(payload, isNot(contains('ABP1:ABP1:')));

      final opened = openPassport(payload!, phrase);
      expect(opened.isOpened, isTrue, reason: '${opened.failure}');
      expect(opened.record, record);
    });

    test('a malformed fragment is ignored rather than treated as a passport',
        () {
      expect(passportPayloadFromFragment('/passport/not-a-passport'), isNull);
      expect(passportPayloadFromFragment('/report/A1B2C3D4E5'), isNull);
      expect(passportPayloadFromFragment(''), isNull);
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

    test('a full twelve-point visit still prints a short link', () {
      // The compact record encoding exists so a generic camera shows a link,
      // not ten lines of base64. A visit at the intake form's twelve-point
      // maximum must still fit, at a symbol density a phone camera can read.
      final payload = passportPayloadFor(
        record: worstCaseRecord(),
        phrase: phrase,
        patientCode: 'A1B2C3D4E5F6G7H8',
      );
      expect(passportCarriesRecord(payload), isTrue);

      final bytes = utf8.encode(payload).length;
      final version = QrCode.fromData(
        data: payload,
        errorCorrectLevel: QrErrorCorrectLevel.Q,
      ).typeNumber;

      expect(
        bytes,
        lessThanOrEqualTo(passportByteCeiling),
        reason: 'a twelve-point passport is $bytes bytes',
      );
      expect(
        version,
        lessThanOrEqualTo(18),
        reason: 'a version $version symbol at EC level Q is '
            '${version * 4 + 17} modules wide; denser symbols misread when a '
            'phone camera scans another screen',
      );
    });

    test('a visit past the ceiling falls back to the honest report link', () {
      // Build a record that really is too large for one symbol, rather than a
      // realistic visit: the fallback must still be reachable and honest.
      final payload = passportPayloadFor(
        record: {
          'c': 'A1B2C3D4E5F6G7H8',
          'p': [
            for (var i = 0; i < 60; i++)
              {'r': 'Unknown region number $i', 's': 5, 'y': 'unknown $i'},
          ],
        },
        phrase: phrase,
        patientCode: 'A1B2C3D4E5F6G7H8',
      );
      expect(passportCarriesRecord(payload), isFalse);
      expect(payload, contains('#/report/'));
    });

    test('an ordinary visit is far inside that ceiling', () {
      final payload = sealPassport(record, phrase);

      expect(utf8.encode(payload).length, lessThan(260));
    });
  });
}
