/// Encrypting the device's own clinical store at rest.
///
/// The passport in `passport_cipher.dart` is keyed by a phrase a human reads off
/// a card, so its key can only ever be a weak capability. This store is the
/// opposite case: a whole clinic's worth of visits sitting in a file on one
/// device, keyed by a full 256-bit random key that the user never sees and never
/// types. The key lives in the platform keystore (`flutter_secure_storage`); the
/// ciphertext lives where it always did, in `shared_preferences`.
///
/// Envelope form: `ABL1:base64url(iv | ciphertext | tag)` over the JSON document.
/// AES-256-GCM again, for the same reason as the passport: it authenticates, so a
/// edited document fails the tag and is never handed back as half-readable
/// plaintext. There is no salt because there is nothing to stretch — the stored
/// key is already high-entropy. The IV is fresh per write; a 96-bit random IV
/// under one key would need on the order of 2^48 rewrites before reuse became
/// plausible, which is far more than a device persists a document.
///
/// The one place this cannot deliver what it promises is a host with no keystore:
/// see `docs/threat-model.md` and the web note in `docs/design-standard.md`. There
/// the caller falls back to the plaintext document and says so, rather than
/// encrypting with a key stored beside the ciphertext and calling that security.
library;

import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:pointycastle/export.dart';

import 'passport_cipher.dart' show base64Padded;

/// Version marker of an at-rest envelope, and the AAD that binds it, so a blob
/// from a future format is recognised rather than decrypted into nonsense.
const String documentPrefix = 'ABL1';
const String _separator = ':';

const int _keyBytes = 32; // AES-256.
const int _ivBytes = 12; // GCM's standard nonce length.
const int _tagBits = 128;

/// The keystore that holds the data key. Abstracted for the same reason the auth
/// token's storage is (`api_client.dart`): unit tests have no platform keystore,
/// so they inject an in-memory fake instead of calling into a plugin.
abstract class DataKeyStore {
  /// The stored key, or null when this device has never created one.
  Future<Uint8List?> read();

  /// Persists [key] so the next launch can open what this one wrote.
  Future<void> write(Uint8List key);
}

/// The production keystore: the OS keychain / Keystore / EncryptedSharedPreferences
/// behind `flutter_secure_storage`. The key is stored base64 because that API
/// carries strings.
class SecureDataKeyStore implements DataKeyStore {
  const SecureDataKeyStore();

  static const FlutterSecureStorage _storage =
      FlutterSecureStorage(aOptions: AndroidOptions());
  static const String _keyName = 'offline_db_data_key_v1';

  @override
  Future<Uint8List?> read() async {
    final encoded = await _storage.read(key: _keyName);
    if (encoded == null || encoded.isEmpty) return null;
    return base64.decode(encoded);
  }

  @override
  Future<void> write(Uint8List key) =>
      _storage.write(key: _keyName, value: base64.encode(key));
}

/// A fresh 256-bit data key. [Random.secure] because this key is the whole
/// protection on a file that no longer has any other secret in it.
Uint8List newDataKey() {
  final random = Random.secure();
  return Uint8List.fromList(
      List.generate(_keyBytes, (_) => random.nextInt(256)));
}

/// Encrypts [document] under [key] into the bytes written to disk.
String sealDocument(Map<String, dynamic> document, Uint8List key) {
  final random = Random.secure();
  final iv =
      Uint8List.fromList(List.generate(_ivBytes, (_) => random.nextInt(256)));

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      true,
      AEADParameters(KeyParameter(key), _tagBits, iv,
          Uint8List.fromList(utf8.encode('$documentPrefix$_separator'))),
    );

  final clear = Uint8List.fromList(utf8.encode(jsonEncode(document)));
  final body = cipher.process(clear);
  final envelope = Uint8List.fromList([...iv, ...body]);

  return '$documentPrefix$_separator'
      '${base64Url.encode(envelope).replaceAll('=', '')}';
}

/// Why an on-disk document could not be opened. Distinct because the caller's
/// recovery differs: a plaintext document is a different storage family, a
/// malformed envelope is a broken write, and a failed tag means the key and the
/// bytes no longer belong together.
enum DocumentFailure { notEncrypted, malformed, authenticationFailed }

/// The outcome of [openDocument]: the document, or the reason there is none.
class DocumentOpening {
  final Map<String, dynamic>? record;
  final DocumentFailure? failure;

  const DocumentOpening.opened(Map<String, dynamic> this.record)
      : failure = null;

  const DocumentOpening.rejected(DocumentFailure this.failure) : record = null;

  bool get isOpened => record != null;
}

/// Opens an on-disk envelope under [key]. Never returns plaintext that did not
/// authenticate: like the passport, the decrypt path only yields a document once
/// the tag checks, and everything else comes back as a typed rejection.
DocumentOpening openDocument(String payload, Uint8List key) {
  if (!payload.startsWith('$documentPrefix$_separator')) {
    return const DocumentOpening.rejected(DocumentFailure.notEncrypted);
  }

  final encoded = payload.substring(documentPrefix.length + _separator.length);
  final Uint8List envelope;
  try {
    envelope = base64Url.decode(base64Padded(encoded));
  } catch (_) {
    return const DocumentOpening.rejected(DocumentFailure.malformed);
  }
  if (envelope.length < _ivBytes + _tagBits ~/ 8) {
    return const DocumentOpening.rejected(DocumentFailure.malformed);
  }

  final iv = envelope.sublist(0, _ivBytes);
  final body = envelope.sublist(_ivBytes);

  final cipher = GCMBlockCipher(AESEngine())
    ..init(
      false,
      AEADParameters(KeyParameter(key), _tagBits, iv,
          Uint8List.fromList(utf8.encode('$documentPrefix$_separator'))),
    );

  final Uint8List clear;
  try {
    clear = cipher.process(body);
  } catch (_) {
    // Rotated/absent key or edited bytes are one event to GCM. The caller must
    // not read this as "wrong password" and invite a retry that can never work.
    return const DocumentOpening.rejected(DocumentFailure.authenticationFailed);
  }

  try {
    final decoded = jsonDecode(utf8.decode(clear));
    if (decoded is! Map<String, dynamic>) {
      return const DocumentOpening.rejected(DocumentFailure.malformed);
    }
    return DocumentOpening.opened(decoded);
  } catch (_) {
    return const DocumentOpening.rejected(DocumentFailure.malformed);
  }
}
