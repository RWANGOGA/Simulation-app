import 'dart:convert';

/// Reads a JSON array of objects out of a stored string, tolerating anything
/// that is not one.
///
/// The draft keys are written by whatever build of the app ran last, and a
/// build can be newer or older than the value it finds: a single unfinished
/// report from before the slot held a list, a document truncated by a failed
/// write, a browser extension or a hand-edited `localStorage`. Casting the
/// decoded value straight to `List` threw a `TypeError` on every one of those,
/// and a `TypeError` is an `Error`, not an `Exception` — so the `catch`
/// blocks around each entry never saw it and the whole read failed instead of
/// skipping the bad rows. On the intake screen that meant the form could never
/// be submitted again, because the write it belongs to starts with a read.
///
/// Returns an empty list when nothing can be understood, and drops entries that
/// are not objects. A single object is accepted and wrapped, since that is
/// exactly what the pre-list version of the app stored.
List<Map<String, dynamic>> decodeStoredObjects(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return const [];
  }
  if (decoded is Map<String, dynamic>) return [decoded];
  if (decoded is Map) {
    // jsonDecode always hands back Map<String, dynamic>, but a caller that
    // passed an already-decoded map should not be punished for the key type.
    return [decoded.map((key, value) => MapEntry(key.toString(), value))];
  }
  if (decoded is! List) return const [];
  return [
    for (final entry in decoded)
      if (entry is Map<String, dynamic>)
        entry
      else if (entry is Map)
        entry.map((key, value) => MapEntry(key.toString(), value)),
  ];
}
