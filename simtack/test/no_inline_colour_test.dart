import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/theme/app_tokens.dart';

/// What this guards, and why it is a ratchet rather than a plain zero.
///
/// A one-time cleanup of inline colours always regrows, because the shortest way
/// to make a screen look right on a Friday afternoon is a new hex. The plan's
/// step B3 is therefore a build-time check, not a convention, and it works the
/// way the other guards in this repo work: the number may only go down.
///
/// Measured on the run that introduced it: 331 colour literals across 21 files
/// became 0 (415 exist in `lib/` if the theme files, where literals belong, are
/// counted).
///
/// Two things are deliberately outside the pattern rather than allowlisted,
/// because neither is a widget colour and a list of exceptions invites more:
/// `PdfColor.fromInt(0xFF0F172A)` in the report exporter (a PDF is printed on
/// white paper and has no brightness) and `0xFFFFFFFF` as a bit mask in
/// `DoctorDraft.hash`. Anchoring on the `Color` constructor excludes both.

/// Counts `Color(0x......)` and `Color.fromARGB(...)` in [source].
int _colourLiterals(String source) {
  final hex = RegExp(r'\bColor\(\s*0x[0-9A-Fa-f]{8}\s*\)').allMatches(source);
  final argb = RegExp(r'\bColor\.fromARGB\(').allMatches(source);
  return hex.length + argb.length;
}

/// Material's named hues are the other way to write "a colour I picked".
///
/// `Colors.red` is #F44336 at every brightness: 3.5:1 on white, so it fails AA
/// for text, and it cannot follow the theme into dark mode. The same is true of
/// every entry in Material's swatch, which is why the semantic accent colours
/// live in `AppAccent`/`GhColors` and resolve per brightness instead.
///
/// `Colors.white`, `Colors.black` and `Colors.transparent` stay legal and are
/// not matched here: none of them is a semantic claim, and the scrim behind
/// label text on the body map genuinely wants pure black at an alpha.
int _materialColourLiterals(String source) => RegExp(
      r'\bColors\.(?:red|pink|purple|deepPurple|indigo|blue|lightBlue|cyan|'
      r'teal|green|lightGreen|lime|yellow|amber|orange|deepOrange|brown|'
      r'grey|blueGrey)(?:Accent)?(?:\[\d+\])?(?![A-Za-z])',
    ).allMatches(source).length;

/// Every Dart file that is expected to speak in tokens rather than numbers.
List<File> _uiSources() => Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) {
      final path = f.path.replaceAll(r'\', '/');
      // The theme files are where literals are supposed to live; the l10n
      // output is generated.
      return !path.startsWith('lib/core/theme/') &&
          !path.startsWith('lib/l10n/');
    }).toList();

void main() {
  test('no screen resolves a colour from an inline literal', () {
    final offenders = <String, int>{};

    for (final file in _uiSources()) {
      final count = _colourLiterals(file.readAsStringSync());
      if (count == 0) continue;
      offenders[file.path.replaceAll(r'\', '/')] = count;
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These files resolve colour from an inline literal again: '
          '$offenders. A literal cannot adapt to brightness, which is how the '
          'brand violet ended up at 2.06:1 in dark mode, and it is why 90 '
          'distinct hexes existed for 12 jobs. Use AppPalette for slate and '
          'AppAccent for clinical accents.',
    );
  });

  test('no screen names a Material swatch colour', () {
    final offenders = <String, int>{};

    for (final file in _uiSources()) {
      final count = _materialColourLiterals(file.readAsStringSync());
      if (count == 0) continue;
      offenders[file.path.replaceAll(r'\', '/')] = count;
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These files reach for a fixed Material hue again: $offenders. '
          'Five snackbars used `Colors.red` (#F44336, 3.5:1 on white, and '
          'unchanged in dark mode) where the rest of their screen already used '
          'a brightness-aware token. Use AppAccent on the patient side and '
          'GhColors on the practitioner side.',
    );
  });

  test('no radius repeats a value the scale already defines', () {
    // AppRadius existed with zero references while 131 sites outside the theme
    // hardcoded a number. This is the strict version of that fix: only the four
    // scale values are named here, so 6/10/14 remain legal and are counted by
    // the ratchet below.
    final scale = <double, String>{
      AppRadius.sm: 'sm',
      AppRadius.md: 'md',
      AppRadius.lg: 'lg',
      AppRadius.xl: 'xl',
    };
    final offenders = <String, List<String>>{};

    for (final file in _uiSources()) {
      final hits = RegExp(r'BorderRadius\.circular\(\s*([0-9]+)(?:\.0)?\s*\)')
          .allMatches(file.readAsStringSync())
          .where((m) => scale.containsKey(double.parse(m.group(1)!)))
          .map((m) => m.group(1)!)
          .toList();
      if (hits.isEmpty) continue;
      offenders[file.path.replaceAll(r'\', '/')] = hits;
    }

    expect(
      offenders,
      isEmpty,
      reason: 'These files hardcode a radius that AppRadius already names: '
          '$offenders. Write AppRadius.sm/md/lg/xl instead of the number, so '
          'the corner is a decision and not a coincidence.',
    );
  });

  test('off-scale radii and font sizes do not grow', () {
    // Not a clean-up, a ratchet. Folding the 224 fontSize values into the
    // TextTheme and the leftover radii (2/4/6/10/14/20/999) into the scale is
    // real work that this pass did not do, and the honest version of "we will
    // get to it" is a number that cannot go up. Both ceilings are the count
    // measured in the run that introduced them: 54 numeric radii (down from 131
    // on the commit before) and 224 fontSize literals (unchanged — no screen
    // folded its sizes, and the new pager takes its size from the TextTheme so
    // this pass did not add one either).
    var radii = 0;
    var fonts = 0;

    for (final file in _uiSources()) {
      final source = file.readAsStringSync();
      radii +=
          RegExp(r'BorderRadius\.circular\(\s*[0-9]').allMatches(source).length;
      fonts += RegExp(r'fontSize:\s*[0-9]').allMatches(source).length;
    }

    expect(radii, lessThanOrEqualTo(54),
        reason: '$radii hardcoded radii: the count was 54 when the scale was '
            'adopted (131 before). Add AppRadius members deliberately instead '
            'of adding a number, then lower this ceiling.');
    expect(fonts, lessThanOrEqualTo(224),
        reason: '$fonts hardcoded font sizes: the count was 224. Sizes belong '
            'in the TextTheme ramp; if one is genuinely missing, add it there '
            'and lower this ceiling.');
  });
}
