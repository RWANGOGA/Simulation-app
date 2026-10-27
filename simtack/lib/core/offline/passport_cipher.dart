/// The encrypted patient passport: what goes into a printed QR, and what it
/// takes to read one back.
///
/// A passport exists so a clinic station with no network and no account can
/// learn what was already measured. That is only true if the code carries the
/// record, so the payload here is the record itself — AES-256-GCM over the
/// clinical essentials, keyed by a short phrase printed under the code.
///
/// Two properties are worth stating exactly, because a paper tends to overstate
/// both:
///
///  * The phrase is a capability, not a strong secret. Six characters from a
///    19-symbol alphabet is roughly 26 bits, so it keeps a printed card lying on
///    a desk from being read by whoever finds it; it is not a defence against an
///    attacker who captures the code and brute-forces it offline. PBKDF2 at
///    [_pbkdf2Rounds] rounds slows that down and does not prevent it. The
///    residual risk belongs in the threat model rather than being hidden by the
///    word "encrypted".
///  * AES-GCM authenticates as well as conceals. A wrong phrase and a altered
///    byte are the same event to the receiver — the tag fails and nothing is
///    returned. There is no partial or unverified plaintext path, by
///    construction: the decrypt API only hands back a record once the tag
///    checks.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// Version marker of a self-contained passport payload. Also what makes the
/// "this code carries the record" claim in qr_passport.dart testable: the bytes
/// either start with it or they do not.
const String passportPrefix = 'ABP1';

/// Separator between [passportPrefix] and the base64url envelope.
const String _separator = ':';

const int _keyBytes = 32; // AES-256.
const int _saltBytes = 16;
const int _ivBytes = 12; // GCM's standard nonce length.
const int _tagBits = 128;

/// Key-stretching rounds. Deliberately the same cost as the offline credential
/// hash in `lib/core/storage/doctor_draft.dart`, so the two stretches on the
/// device are one decision rather than two numbers that drift apart.
const int _pbkdf2Rounds = 20000;

/// Length of the printed phrase.
const int passportPhraseLength = 6;

/// Phrase alphabet: uppercase, with every character that blurs when printed
/// small or read aloud removed — no `0/O`, no `1/I/L`, no `2/Z`, no `5/S`, no
/// `8/B`, no `V`. 19 symbols, so 6 characters carry about 26 bits.
const String _phraseAlphabet = 'ACDEFGHJKMNPQRTUWXY';

/// A fresh out-of-band phrase, to be printed under the code and read to nobody
/// else. Generated on the patient's device; the server never sees it, which is
/// why the server cannot open a passport either.
String generatePassportPhrase() {
  final random = Random.secure();
  return List.generate(
    passportPhraseLength,
    (_) => _phraseAlphabet[random.nextInt(_phraseAlphabet.length)],
  ).join();
}

/// Normalises a phrase before deriving from it. Printed characters get read
/// aloud, retyped in bad light, and typed on a phone keyboard that shifts case:
/// lower-case input must open an upper-case phrase or the record is unrecoverable
/// for a reason that has nothing to do with the key.
String normalisePassportPhrase(String phrase) =>
    phrase.toUpperCase().replaceAll(RegExp(r'[^A-Z]'), '');

Uint8List _deriveKey(String phrase, Uint8List salt) {
  final derivator = PBKDF2KeyDerivator(HMac(SHA256Digest(), 64))
    ..init(Pbkdf2Parameters(salt, _pbkdf2Rounds, _keyBytes));
  return derivator.process(Uint8List.fromList(utf8.encode(phrase)));
}

/// Why a payload could not be opened. Separated because the UI has to say
/// different things: a legacy code is a different flow, a malformed envelope is
/// a broken print, and a failed tag is either the wrong phrase or an altered
/// code — which the cipher cannot tell apart and the screen must not pretend to.
enum PassportFailure { notAPassport, malformed, authenticationFailed }

/// The outcome of [openPassport]: a record, or the reason there is none.
class PassportOpening {
  final Map<String, dynamic>? record;
  final PassportFailure? failure;

  const PassportOpening.opened(Map<String, dynamic> this.record)
      : failure = null;

  const PassportOpening.rejected(PassportFailure this.failure) : record = null;

  bool get isOpened => record != null;
}

/// Encrypts [record] into the bytes a passport QR prints:
/// `ABP1:base64url(salt | iv | ciphertext | tag)`.
///
/// A fresh salt and IV per sealing, so two prints of the same visit never share
/// a ciphertext and a repeated code does not leak that the visit is repeated.
String sealPassport(Map<String, dynamic> record, String phrase) {
  final random = Random.secure();
  final salt =
      Uint8List.fromList(List.generate(_saltBytes, (_) => random.nextInt(256)));
  final iv =
      Uint8List.fromList(List.generate(_ivBytes, (_) => random.nextInt(256)));

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(
        KeyParameter(_deriveKey(normalisePassportPhrase(phrase), salt)),
        _tagBits,
        iv,
        Uint8List.fromList(utf8.encode('$passportPrefix$_separator')),
      ),
    );

  final clear = Uint8List.fromList(utf8.encode(jsonEncode(record)));
  final body = Uint8List.fromList([...cipher.process(clear)]);
  final envelope = Uint8List.fromList([...salt, ...iv, ...body]);

  return '$passportPrefix$_separator${base64Url.encode(envelope).replaceAll('=', '')}';
}

/// Opens a printed passport. Returns [PassportOpening.rejected] rather than
/// throwing, because the caller is a scan result from a camera and every branch
/// of it needs a different sentence on screen.
///
/// Never returns plaintext that did not authenticate.
PassportOpening openPassport(String payload, String phrase) {
  if (!payload.startsWith('$passportPrefix$_separator')) {
    return const PassportOpening.rejected(PassportFailure.notAPassport);
  }

  final encoded = payload.substring(passportPrefix.length + _separator.length);
  final Uint8List envelope;
  try {
    envelope = base64Url.decode(base64Padded(encoded));
  } catch (_) {
    return const PassportOpening.rejected(PassportFailure.malformed);
  }
  if (envelope.length < _saltBytes + _ivBytes + _tagBits ~/ 8) {
    return const PassportOpening.rejected(PassportFailure.malformed);
  }

  final salt = envelope.sublist(0, _saltBytes);
  final iv = envelope.sublist(_saltBytes, _saltBytes + _ivBytes);
  final body = envelope.sublist(_saltBytes + _ivBytes);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(
        KeyParameter(_deriveKey(normalisePassportPhrase(phrase), salt)),
        _tagBits,
        iv,
        Uint8List.fromList(utf8.encode('$passportPrefix$_separator')),
      ),
    );

  final Uint8List clear;
  try {
    clear = cipher.process(body);
  } catch (_) {
    // Wrong phrase or edited bytes: GCM cannot tell them apart and neither can
    // anyone reading the screen, so the message must not claim one.
    return const PassportOpening.rejected(PassportFailure.authenticationFailed);
  }

  try {
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic>) {
      return const PassportOpening.rejected(PassportFailure.malformed);
    }
    return PassportOpening.opened(decoded);
  } catch (_) {
    // Authenticated, but not JSON: a code from a future format. Say malformed
    // rather than opening a record whose shape is guesswork.
    return const PassportOpening.rejected(PassportFailure.malformed);
  }
}

/// base64url tolerates unpadded input, and the envelope is written without
/// padding to save QR bytes. Restores the padding the decoder wants.
String base64Padded(String encoded) {
  final remainder = encoded.length % 4;
  if (remainder == 0) return encoded;
  return encoded + '=' * (4 - remainder);
}
