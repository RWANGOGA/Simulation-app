// A guard for a bug class that no other test in this suite can see.
//
// `flutter test` runs on the Dart VM, where `1 << 32` is 4294967296. Compiled
// for the web, the same expression is **0** — dart2js gives `int` the shift
// semantics of a 32-bit JS integer. Anything built on it therefore looks fine in
// CI and breaks only once deployed. The first time this bit, it took down
// patient intake on the live site: `Random.nextInt(1 << 32)` became
// `Random.nextInt(0)`, which throws
// `RangeError: max must be in range 0 < max ≤ 2^32, was 0`, inside the write that
// records the patient. See OfflineRepository._token.
//
// CI does not run `flutter test --platform chrome`, so the only cheap way to
// keep this from coming back is to read the source and refuse the expression.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no lib/ file shifts by 32 or more bits', () {
    // `<< 32`, `<< 33`, ... `<< 49`. Anything at or past the int32 width folds
    // to 0 on the web, so it is never what the author meant.
    final tooWide = RegExp(r'<<\s*(3[2-9]|4[0-9])\b');
    final offenders = <String>[];

    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        final line = lines[i].trimLeft();
        // The rule is about code. These comments quote the forbidden expression
        // precisely to explain it, and a guard that fails on its own
        // documentation gets deleted rather than obeyed.
        if (line.startsWith('//') || line.startsWith('*')) continue;
        if (tooWide.hasMatch(line)) {
          offenders.add('${file.path}:${i + 1}: ${line.trim()}');
        }
      }
    }

    expect(offenders, isEmpty,
        reason: 'A shift of 32+ bits is 0 under dart2js '
            'and 2^n on the Dart VM, so code that depends on it cannot be tested '
            'from the VM. Use a range that means the same thing on both — 1 << 30 '
            'is the widest — or build the value from smaller parts.');
  });
}
