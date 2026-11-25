/// The compact bytes that travel inside a printed passport.
///
/// The first version of the passport encrypted the record as JSON. That was
/// easy to read and easy to test, but it was also roughly 250–400 bytes before
/// base64, and a QR symbol that large shows up in an ordinary phone camera as
/// ten lines of what looks like noise. The record contains almost no free text
/// — a few known body regions, four pain types, four triage categories — so the
/// names were being printed over and over.
///
/// This encoding replaces those names with one-byte dictionary indexes and
/// drops JSON punctuation entirely. A full twelve-point visit is about 60
/// bytes, so the printed link stays short enough to look like a link instead of
/// a wall of code. Unknown values are kept verbatim rather than refused: a card
/// printed by a newer app must still be readable by an older one, and a typo in
/// a region name must not make the record unreadable.
///
/// Compatibility is one-way by design: [decodePassportRecord] also accepts the
/// old JSON plaintext, because cards already printed cannot be reissued.
library;

import 'dart:convert';
import 'dart:typed_data';

/// First byte of every compact plaintext. A JSON record starts with `{`, so the
/// two formats cannot be mistaken for one another.
const int passportRecordVersion = 2;

/// The body regions the intake form offers, in the order the 2D and 3D maps
/// use. Unknown regions are written as text after an escape marker.
///
/// **Append only.** The index is what a printed card carries, so reordering
/// this list would make every existing passport decode into the wrong region.
/// Older builds also escape names they do not know, which is why adding a name
/// here is backward compatible but renaming one is not.
const List<String> passportRegionCodes = [
  'Abdomen (Lower Right)',
  'Abdomen (Lower Left)',
  'Abdomen (Upper)',
  'Chest / Heart',
  'Headache / Cranial',
  'Back Pain (Lower)',
  'Back Pain (Upper)',
  'Right Arm / Shoulder',
  'Left Arm / Shoulder',
  'Right Leg / Knee',
  'Left Leg / Knee',
  // Server-side names that reach a passport from the analysis endpoint.
  'Neck',
  'Neck / Shoulders',
  'Back (Lumbar)',
  'Left Arm',
  'Right Arm',
  'Left Leg',
  'Right Leg',
  'Joint (Knee)',
  'Flank / Kidney',
  'Head',
];

/// Pain types offered by the pain-details screen, in display order. The
/// lower-case spellings are here because the server and older stored sessions
/// use them, and a one-byte code is worth more than normalising on read.
const List<String> passportPainCodes = [
  'Sharp',
  'Dull',
  'Burning',
  'Cramping',
  'sharp',
  'dull',
  'burning',
  'cramping',
];

/// SATS categories, most urgent first (mirrors `TriageTier.order`).
const List<String> passportTierCodes = ['red', 'orange', 'yellow', 'green'];

/// Escalation levels the server returns.
const List<String> passportEscalationCodes = [
  'emergency',
  'urgent',
  'routine',
];

const int _noValue = 0xFF;
const int _escape = 0xFF;

// Flag bits in the second byte.
const int _hasVisit = 1 << 0;
const int _hasCreated = 1 << 1;
const int _hasRisk = 1 << 2;
const int _hasTier = 1 << 3;
const int _hasEscalation = 1 << 4;
const int _hasAction = 1 << 5;
const int _createdIsText = 1 << 6;

/// Encodes [record] into the compact bytes that are encrypted into a passport.
///
/// The field names are the same as [jsonEncode] used to produce, so a decoded
/// record is indistinguishable from a JSON one to every caller.
Uint8List encodePassportRecord(Map<String, dynamic> record) {
  final out = BytesBuilder(copy: false)
    ..addByte(passportRecordVersion);

  final visitId = record['i'];
  final createdAt = record['t'];
  final riskScore = record['k'];
  final tier = record['g'];
  final escalation = record['e'];
  final action = record['a'];

  final createdText = createdAt is String && DateTime.tryParse(createdAt) == null;

  var flags = 0;
  if (visitId is String && visitId.isNotEmpty) flags |= _hasVisit;
  if (createdAt is String && createdAt.isNotEmpty) {
    flags |= _hasCreated;
    if (createdText) flags |= _createdIsText;
  }
  if (riskScore is num) flags |= _hasRisk;
  if (tier is String && tier.isNotEmpty) flags |= _hasTier;
  if (escalation is String && escalation.isNotEmpty) {
    flags |= _hasEscalation;
  }
  if (action is String && action.isNotEmpty) flags |= _hasAction;
  out.addByte(flags);

  _writeString(out, (record['c'] as String?) ?? '');

  if ((flags & _hasVisit) != 0) _writeString(out, visitId as String);

  if ((flags & _hasCreated) != 0) {
    if (createdText) {
      _writeString(out, createdAt);
    } else {
      final millis =
          DateTime.parse(createdAt as String).toUtc().millisecondsSinceEpoch;
      out.add(_uint64(millis));
    }
  }

  if ((flags & _hasRisk) != 0) {
    // Kept as text rather than a rounded fixed-point number so a decoded record
    // is exactly the map that was sealed. Scores are two decimal places in the
    // product, so this costs at most a handful of bytes.
    _writeString(out, jsonEncode(riskScore));
  }

  if ((flags & _hasTier) != 0) _writeCode(out, passportTierCodes, tier as String);
  if ((flags & _hasEscalation) != 0) {
    _writeCode(out, passportEscalationCodes, escalation as String);
  }
  if ((flags & _hasAction) != 0) _writeString(out, action as String);

  final points = record['p'];
  final rows = points is List ? points : const [];
  if (rows.length > 255) {
    throw const FormatException('A passport cannot carry more than 255 points');
  }
  out.addByte(rows.length);

  for (final row in rows) {
    if (row is! Map) {
      throw const FormatException('A passport point must be a map');
    }
    _writeCode(out, passportRegionCodes, (row['r'] as String?) ?? '');
    out.addByte(((row['s'] as num?)?.toInt() ?? 0).clamp(0, 255).toInt());
    _writeCode(out, passportPainCodes, (row['y'] as String?) ?? '');
    final pointTier = row['g'];
    if (pointTier is String && pointTier.isNotEmpty) {
      _writeCode(out, passportTierCodes, pointTier);
    } else {
      out.addByte(_noValue);
    }
  }

  return out.takeBytes();
}

/// Decodes [bytes] into the record map used by [PassportRecord.fromMap].
///
/// Accepts both this compact format and the JSON plaintext printed by earlier
/// builds. Throws [FormatException] when neither can be read.
Map<String, dynamic> decodePassportRecord(Uint8List bytes) {
  if (bytes.isEmpty) throw const FormatException('Empty passport record');

  // A JSON record is `{...}`; the compact format starts with a version byte.
  if (_looksLikeJson(bytes)) {
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is Map<String, dynamic>) return decoded;
    throw const FormatException('Passport JSON is not an object');
  }

  final reader = _Reader(bytes);
  final version = reader.uint8();
  if (version != passportRecordVersion) {
    throw FormatException('Unsupported passport record version $version');
  }

  final flags = reader.uint8();
  final record = <String, dynamic>{'c': reader.string()};

  if ((flags & _hasVisit) != 0) record['i'] = reader.string();
  if ((flags & _hasCreated) != 0) {
    if ((flags & _createdIsText) != 0) {
      record['t'] = reader.string();
    } else {
      record['t'] = DateTime.fromMillisecondsSinceEpoch(
        reader.uint64(),
        isUtc: true,
      ).toIso8601String();
    }
  }
  if ((flags & _hasRisk) != 0) {
    final raw = reader.string();
    final score = num.tryParse(raw);
    if (score == null) throw const FormatException('Bad risk score');
    record['k'] = score;
  }
  if ((flags & _hasTier) != 0) {
    record['g'] = _readCode(reader, passportTierCodes);
  }
  if ((flags & _hasEscalation) != 0) {
    record['e'] = _readCode(reader, passportEscalationCodes);
  }
  if ((flags & _hasAction) != 0) record['a'] = reader.string();

  final count = reader.uint8();
  final points = <Map<String, dynamic>>[];
  for (var i = 0; i < count; i++) {
    final point = <String, dynamic>{
      'r': _readCode(reader, passportRegionCodes),
      's': reader.uint8(),
      'y': _readCode(reader, passportPainCodes),
    };
    final tierCode = reader.uint8();
    if (tierCode != _noValue) {
      if (tierCode >= passportTierCodes.length) {
        throw const FormatException('Unknown passport tier code');
      }
      point['g'] = passportTierCodes[tierCode];
    }
    points.add(point);
  }
  record['p'] = points;

  if (!reader.isAtEnd) {
    throw const FormatException('Trailing bytes in passport record');
  }
  return record;
}

bool _looksLikeJson(Uint8List bytes) {
  for (final byte in bytes) {
    if (byte == 0x20 || byte == 0x0A || byte == 0x0D || byte == 0x09) continue;
    return byte == 0x7B; // {
  }
  return false;
}

/// Writes a dictionary value as one byte, or an escape marker plus the text.
void _writeCode(BytesBuilder out, List<String> codes, String value) {
  final index = codes.indexOf(value);
  if (index >= 0 && index < _escape) {
    out.addByte(index);
    return;
  }
  out.addByte(_escape);
  _writeString(out, value);
}

String _readCode(_Reader reader, List<String> codes) {
  final index = reader.uint8();
  if (index == _escape) return reader.string();
  if (index >= codes.length) {
    throw const FormatException('Unknown passport dictionary code');
  }
  return codes[index];
}

/// Writes a string with a one-byte length, or a 0xFF marker followed by a
/// two-byte length when the text is longer than 254 bytes. A referral action
/// sentence from the server can exceed one byte's range; truncating clinical
/// instructions to fit would be worse than spending two extra bytes.
void _writeString(BytesBuilder out, String value) {
  final bytes = utf8.encode(value);
  if (bytes.length < 255) {
    out.addByte(bytes.length);
  } else {
    out.addByte(0xFF);
    out.add((ByteData(2)..setUint16(0, bytes.length)).buffer.asUint8List());
  }
  out.add(bytes);
}

Uint8List _uint64(int value) {
  final data = ByteData(8)..setUint64(0, value);
  return data.buffer.asUint8List();
}

class _Reader {
  _Reader(this.bytes);

  final Uint8List bytes;
  int offset = 0;

  bool get isAtEnd => offset >= bytes.length;

  int uint8() {
    if (isAtEnd) throw const FormatException('Truncated passport record');
    return bytes[offset++];
  }

  int uint64() {
    if (offset + 8 > bytes.length) {
      throw const FormatException('Truncated passport timestamp');
    }
    final value = ByteData.sublistView(bytes, offset, offset + 8).getUint64(0);
    offset += 8;
    return value;
  }

  String string() {
    var length = uint8();
    if (length == 0xFF) length = uint16();
    if (offset + length > bytes.length) {
      throw const FormatException('Truncated passport text');
    }
    final value = utf8.decode(bytes.sublist(offset, offset + length));
    offset += length;
    return value;
  }

  int uint16() {
    if (offset + 2 > bytes.length) {
      throw const FormatException('Truncated passport text length');
    }
    final value = ByteData.sublistView(bytes, offset, offset + 2).getUint16(0);
    offset += 2;
    return value;
  }
}
