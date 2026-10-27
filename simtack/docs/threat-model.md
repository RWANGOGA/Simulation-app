# Threat model

Written for the examiner's security questions. Every control below names the
file that actually implements it and the test that holds it to the claim; where a
control does not reach an asset, that is stated as a residual risk rather than
papered over. Nothing here asserts a property the code does not implement — that
honesty is the point of this file.

Scope is the two places this app holds something worth protecting on a device:
the clinical record at rest, and the patient's passport QR. Server-side concerns
(Postgres, the FastAPI auth surface) are out of scope here.

## Assets, adversaries, controls

| Asset | Adversary & scenario | Control that protects it | Implementing file | Test that pins it | Residual risk (stated) |
| --- | --- | --- | --- | --- | --- |
| The device's whole clinical store (every patient, visit, outbox entry) | Someone with the unlocked device, or a raw read of app storage (`shared_preferences`), tries to read records in the clear. | The JSON document is sealed with AES-256-GCM under a random 256-bit data key; the key is kept in the platform keystore, apart from the ciphertext. A fresh IV per write. | `lib/core/offline/local_envelope.dart`, wired in at startup by `lib/main.dart` and applied by `lib/core/offline/local_database.dart` | `test/local_envelope_test.dart` (round-trip, wrong key, tamper, malformed), `test/local_database_encryption_test.dart` (never writes plaintext, migration clears plaintext, unreadable blob quarantined) | **Web has no keystore.** On web the platform store is just browser storage beside the data, so encryption there protects nothing; the app therefore stores web plaintext and says so rather than faking it. A device-rooted or keystore-extracted adversary also defeats it — at-rest encryption guards the file, not a live, unlocked session. |
| A migrated clinic's records (device upgrading from the pre-encryption build) | A crash or a bad write during the plaintext→encrypted migration strands or silently drops a patient's history. | Migration keeps the plaintext original until the encrypted copy has been written **and** read back and authenticated under the key; only then is the plaintext removed. Anything that will not open is quarantined under a timestamped key, never overwritten or guessed. | `lib/core/offline/local_database.dart` (`_openEncrypted`) | `test/local_database_encryption_test.dart` ("migrated and the plaintext is removed", "unreadable envelope is quarantined") | A quarantined blob is recoverable by hand, not automatically — a device that loses its key opens clean and the old data sits in a `_corrupt_` entry until someone retrieves it deliberately. |
| The clinical record printed as a patient's passport QR | A clinic worker photographs/screenshots the code, or it is read by anyone who scans it, hoping to expose the patient's data. | The record is sealed with AES-256-GCM (`ABP1:`); it only opens with the six-character phrase printed on the same card. GCM cannot tell a wrong phrase from a tampered blob, so both fail with no plaintext. | `lib/core/offline/passport_cipher.dart`, `passport_record.dart`, `qr_passport.dart` | `test/passport_cipher_test.dart`, `test/qr_claim_accuracy_test.dart` | **The phrase is a capability, not a strong secret:** six characters from a 19-symbol alphabet is ~26 bits, and it travels *with* the card. Anyone holding the card and the phrase can open the record — that is the design intent (offline, no account). A sealed payload also has no forward secrecy: capture the bytes and the phrase later and the record opens. When a visit is too large to fit a readable symbol the app falls back to a plain report link, which carries nothing offline. |
| The practitioner's session token | Stolen device or dumped storage used to act as a signed-in clinician. | Token held in the platform keystore; offline access is time-bounded and a cached session is never shown as server-confirmed. | `lib/core/network/api_client.dart` (`SecureTokenStorage`), `auth_service.dart` | `test/offline_auth_test.dart`, `test/offline_trust_test.dart` | Same rooted-device caveat as the data key. On web the token degrades to browser storage — the reason the trust window and trust strip are mandatory there (see `docs/design-standard.md`). |

## Non-goals and honest limits

- **This is not protection against a live attacker on an unlocked, signed-in
  device.** At-rest encryption stops someone reading the stored file; it cannot
  stop malware running as the app, and it does not lock a session.
- **No key recovery or rotation is implemented.** If the platform keystore entry
  is lost, the encrypted store is unrecoverable by design — the bytes are set
  aside rather than guessed back. Losing the passport phrase likewise means the
  sealed QR cannot be opened.
- **No independent security review.** This table records what the code does and
  what it claims; it is not an external audit, and the crypto primitives are used
  rather than verified against a formal model.
