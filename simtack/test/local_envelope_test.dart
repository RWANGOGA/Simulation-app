import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/offline/local_envelope.dart';
import 'package:simtack/core/offline/passport_cipher.dart' show base64Padded;

/// The at-rest envelope on its own, away from the store that uses it.
///
/// These are the properties `local_database.dart` relies on when it says a
/// clinic's records are encrypted on the device: it round-trips, it is
/// authenticated so a byte change yields nothing rather than a partly readable
/// document, and the same document seals to different bytes each time so the
/// store's rewrite count is not visible from the file.
void main() {
  Uint8List key() {
    final bytes = Uint8List(32);
    for (var i = 0; i < 32; i++) {
      bytes[i] = i;
    }
    return bytes;
  }

  final document = <String, dynamic>{
    'version': 1,
    'patients': [
      {'code': 'P-ABC123', 'name': 'Amina'}
    ],
    'sessions': <Map<String, dynamic>>[],
    'outbox': <Map<String, dynamic>>[],
  };

  group('sealing and opening', () {
    test('a sealed document opens back to the same content', () {
      final sealed = sealDocument(document, key());

      expect(sealed, startsWith('ABL1:'));
      // On disk it is ciphertext, not the JSON it wraps.
      expect(sealed, isNot(contains('Amina')));

      final opened = openDocument(sealed, key());
      expect(opened.isOpened, isTrue, reason: '${opened.failure}');
      expect(jsonEncode(opened.record), jsonEncode(document));
    });

    test('the wrong key is refused and hands back no plaintext', () {
      final sealed = sealDocument(document, key());
      final other = Uint8List(32)..fillRange(0, 32, 9);

      final opened = openDocument(sealed, other);

      expect(opened.isOpened, isFalse);
      expect(opened.failure, DocumentFailure.authenticationFailed);
      expect(opened.record, isNull);
    });

    test('an altered byte fails the tag rather than decrypting to garbage', () {
      final sealed = sealDocument(document, key());
      final bytes =
          base64Url.decode(base64Padded(sealed.substring('ABL1:'.length)));
      bytes[bytes.length - 1] ^= 0x01; // flip a bit inside the ciphertext/tag
      final tampered = 'ABL1:${base64Url.encode(bytes).replaceAll('=', '')}';

      final opened = openDocument(tampered, key());

      expect(opened.failure, DocumentFailure.authenticationFailed);
      expect(jsonEncode(opened.record ?? {}), isNot(contains('Amina')));
    });

    test('a plaintext document is a different family, not a failed envelope',
        () {
      // The migration path relies on this: a `shared_preferences` value that is
      // just JSON is the legacy store, not a corrupt encrypted one.
      final opened = openDocument(jsonEncode(document), key());
      expect(opened.failure, DocumentFailure.notEncrypted);
    });

    test('a truncated or unparseable envelope is malformed', () {
      final sealed = sealDocument(document, key());

      expect(
        openDocument(sealed.substring(0, 6), key()).failure,
        DocumentFailure.malformed,
      );
      expect(
        openDocument('ABL1:not-base64-at-all!!!', key()).failure,
        DocumentFailure.malformed,
      );
    });

    test('the same document seals to different bytes each time', () {
      // Fresh IV per write, so how many times the store was saved is not
      // readable off the file, and two saves of one visit do not look alike.
      expect(
          sealDocument(document, key()), isNot(sealDocument(document, key())));
      expect(
          openDocument(sealDocument(document, key()), key()).isOpened, isTrue);
    });
  });

  group('the data key', () {
    test('is 32 bytes and different every time it is generated', () {
      final keys = List.generate(50, (_) => newDataKey());
      for (final k in keys) {
        expect(k.length, 32);
      }
      final distinct = keys.map(base64.encode).toSet();
      expect(distinct.length, greaterThan(45));
    });
  });
}
