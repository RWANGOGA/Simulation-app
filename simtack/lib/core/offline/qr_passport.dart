/// What a printed patient passport actually contains, and what that entitles a
/// clinic station to do with it.
///
/// This exists because the app once captioned every QR code "Encrypted QR
/// Passport" and "No internet required to view" while the payload was
/// `reportBaseUrl/#/report/<code>` — a plain URL with no record and no
/// encryption in it. Both sentences were claims about the payload, so the
/// payload is what decides them. Nothing in the UI may assert offline
/// availability or confidentiality without going through this file first.
library;

import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;

/// Prefix of a self-contained, encrypted passport payload (see Unit 3:
/// `v1 | IV | ciphertext | tag` over the clinical record, base64url-encoded).
const String passportPayloadPrefix = 'ABP1';

/// True when [payload] carries the clinical record itself, so a station can
/// read it with no network. False when it is only a pointer to a server that
/// holds the record.
///
/// Deliberately a test on the payload and not a flag passed down from the
/// screen: a flag can be set wrongly by the caller, which is the same bug in a
/// different place. The bytes either contain the record or they do not.
bool passportCarriesRecord(String payload) =>
    payload.startsWith(passportPayloadPrefix);

/// The hint a patient should be shown under [payload].
///
/// Kept as one function so the two screens that print a passport — the success
/// screen and the practitioner's patient overview — cannot disagree about what
/// the code does, which is how the "no internet required" line survived for as
/// long as it did: it was written twice.
String passportHint({
  required String payload,
  required String offlinePassport,
  required String needsInternet,
}) =>
    passportCarriesRecord(payload) ? offlinePassport : needsInternet;

/// Where the hosted web report lives.
///
/// Moved here from `success_screen.dart`, where it was one of two independent
/// definitions of the same URL — the practitioner's patient overview built its
/// own and hardcoded the GitHub Pages address. Two definitions of a payload is
/// how one screen can start printing an encrypted passport while the other keeps
/// printing a link under the same caption.
String get reportBaseUrl {
  if (kIsWeb) {
    // On web, link into the very deployment the patient is already using
    // (localhost dev server, staging, GitHub Pages, ...) — Uri.base carries the
    // right origin AND base path (e.g. /Simulation-app/). Fragment and query are
    // dropped so the current route is never nested into the link.
    final base = Uri.base;
    final url = '${base.origin}${base.path}';
    return url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }
  if (kDebugMode) {
    // Debug builds on a physical device cannot resolve "localhost". To test QR
    // scanning from a phone, temporarily swap in the dev machine's LAN IP, e.g.
    // 'http://192.168.x.x:5000'.
    return 'http://localhost:5000';
  }
  // Release builds on real devices: the public web deployment.
  return 'https://rwangoga.github.io/Simulation-app';
}

/// The exact bytes printed into a patient's passport QR code.
///
/// Today this is a link to the hosted report, which is why every caption about a
/// passport has to be derived from [passportCarriesRecord] rather than written
/// next to the widget. Once the record is encrypted into the payload here, the
/// offline wording becomes true by construction — no screen has to remember to
/// change, and no test has to trust that it did.
String passportPayload(String patientCode) =>
    '$reportBaseUrl/#/report/$patientCode';
