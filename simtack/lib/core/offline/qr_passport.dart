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

import 'passport_cipher.dart';

/// Prefix of a self-contained, encrypted passport payload:
/// `ABP1:base64url(salt | IV | ciphertext | tag)` over the clinical record.
///
/// Aliased from the cipher rather than written out again, so the sentence "the
/// code carries the record" and the bytes that make it true cannot drift apart.
const String passportPayloadPrefix = passportPrefix;

/// The most bytes a passport payload may print as.
///
/// Measured with the encoder the app actually prints with: error correction
/// level Q (25%), which leaves room for the centred Simtack logo. 700 bytes
/// lands near QR version 28, about 129 modules on a side, at a 220px display
/// size. Past that a phone camera at arm's length over a printed card starts
/// failing to resolve the symbol, and an unreadable passport helps nobody — so
/// the app prints the URL code instead and says so on the card.
const int passportByteCeiling = 700;

/// True when [payload] carries the clinical record itself, so a station can
/// read it with no network. False when it is only a pointer to a server that
/// holds the record.
///
/// Deliberately a test on the payload and not a flag passed down from the
/// screen: a flag can be set wrongly by the caller, which is the same bug in a
/// different place. The bytes either contain the record or they do not.
/// Marker for the self-contained web passport link.
const String passportRouteMarker = '#/passport/';

/// Builds the QR payload for a sealed visit.
///
/// A plain `ABP1:` string is only meaningful to this app's own scanner. A
/// generic camera app would show the ciphertext and stop. Wrapping the same
/// envelope in a fragment URL means any scanner opens a page that asks for the
/// phrase and decrypts locally — no server call is involved in reading it.
String passportLink(String sealedPayload) =>
    '$reportBaseUrl$passportRouteMarker$sealedPayload';

/// Extracts the raw `ABP1:` envelope from either payload shape, or null when
/// this is a plain report link / unrelated QR.
String? passportEnvelope(String payload) {
  if (payload.startsWith('$passportPayloadPrefix:')) return payload;
  final index = payload.indexOf(passportRouteMarker);
  if (index < 0) return null;
  final candidate = payload.substring(index + passportRouteMarker.length);
  return candidate.startsWith('$passportPayloadPrefix:') ? candidate : null;
}

bool passportCarriesRecord(String payload) =>
    passportEnvelope(payload) != null;

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
/// Two families exist, and the payload itself says which one it is:
///
///  * `https://…#/passport/ABP1:…` — the same encrypted record wrapped in a
///    web link so an ordinary camera app opens an unlock page instead of
///    showing ciphertext. The page decrypts locally with the printed phrase;
///    no database or API request is involved in reading the card.
///  * `https://…#/report/<code>` — a pointer to the hosted report. Used for
///    visits too large for the symbol budget, and by every code printed before
///    the encrypted passport existed.
///
/// Never guess between the two from a flag passed down from a screen: a flag can
/// be set wrongly, which is exactly how "no internet required" survived on a
/// plain URL.
String passportPayload(String patientCode) =>
    '$reportBaseUrl/#/report/$patientCode';

/// The payload for one finished visit: the encrypted record when it fits the
/// symbol, the report link when it does not.
///
/// [phrase] is generated by the caller and printed beside the code. It is never
/// sent anywhere — no server holds it, so no server can open a passport, which
/// is the point and the limitation, both of which belong in the threat model.
String passportPayloadFor({
  required Map<String, dynamic> record,
  required String phrase,
  required String patientCode,
}) {
  final sealed = sealPassport(record, phrase);
  if (sealed.length > passportByteCeiling) {
    // Too much clinical record for one readable symbol. Falling back is visible
    // to the patient because the hint under the code is derived from whatever
    // this returns, so the card cannot promise offline reading it cannot do.
    return passportPayload(patientCode);
  }
  return passportLink(sealed);
}
