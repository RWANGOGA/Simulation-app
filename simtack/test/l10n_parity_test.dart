import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:simtack/core/locale/app_languages.dart';

/// Guards the translation files themselves.
///
/// Nothing used to stop a string being added to `app_en.arb` alone: the app
/// silently fell back to English at runtime and every screen still looked
/// fine, so the gap only surfaced when a Luganda or Kiswahili speaker hit it.
/// These tests turn that silent fallback into a build failure.
///
/// The one thing they cannot judge is translation *quality*. They can and do
/// insist that a "translation" is not simply the English text, because that is
/// the state three of the four locales are in today: see [_englishCeiling].

const _arbDir = 'lib/l10n';
const _templateLocale = 'en';
const _templatePath = '$_arbDir/app_$_templateLocale.arb';

/// How many messages per locale are still the English text verbatim.
///
/// This is a ceiling, not a target: the numbers were measured, not chosen.
/// They exist so the gap cannot quietly widen — adding a new English string
/// and copying it into a locale fails the build until someone either raises
/// the ceiling on purpose (a reviewed "ship English for now" decision) or
/// supplies the translation. Whenever a locale improves, lower its number.
const _englishCeiling = <String, int>{
  // 35 = 32 + the three session-trust notices (cached copy with a date, cached
  // copy with no date, device-only account). They ship as English on purpose:
  // the sentence states whether a server vouched for this account and for how
  // long offline access lasts, so a guessed Luganda/Kiswahili/Lusoga wording is
  // a wrong security claim rather than a missing translation. Translating all
  // three with a reviewer and lowering these numbers is the follow-up.
  //
  // 37 = 35 + the two pager chevrons (Previous / Next). Kiswahili got real
  // translations (Iliyotangulia / Inayofuata) and did not move; the other three
  // are bare navigation words that no reviewer has confirmed, and an unlabeled
  // icon button is worse for a screen-reader user than a familiar English word.
  //
  // 39 = 37 + the two passport captions. Luganda previously read "Paasipoota ya
  // QR Ekusike" — a real translation of "Encrypted QR Passport", which was a
  // false claim, so the wording had to go rather than be re-translated. The two
  // replacement sentences state what the network is needed for, and a guessed
  // Luganda rendering of a connectivity promise is the same class of error as
  // the one being fixed. Retranslate both with a reviewer and lower this number.
  // Kiswahili, Runyankole and Lusoga did not move: those strings were already
  // English there.
  //
  // 45 / 279 / 263 / 279 = +6 each, the four SATS category names (Red, Orange,
  // Yellow, Green) and the two labels beside them. A triage category is not a
  // label to improvise: "Orange" means "very urgent" to whoever reads the chart
  // after you, and a plausible-sounding Lusoga word for it invented by a
  // developer is the same class of error as the mistranslated passport caption
  // above. They ship in English until a reviewer confirms the clinical wording,
  // then these numbers drop.
  //
  // 47 / 281 / 265 / 281 = +2 each, the two unlock-phrase sentences printed on
  // the sealed passport (qrPassportKeyLabel / qrPassportKeyHint). They tell a
  // patient to hand a key to a health worker; a guessed rendering of that
  // instruction is the same class of error as the mistranslated connectivity
  // promise above, so they ship in English until a reviewer confirms the
  // wording, then these numbers drop.
  'lg': 47,
  'nyn': 281,
  'sw': 265,
  'xog': 281,
};

Map<String, dynamic> _read(String path) =>
    jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;

/// Message key -> value, dropping the `@`-prefixed metadata and `@@locale`.
Map<String, String> _messages(String path) => {
      for (final entry in _read(path).entries)
        if (!entry.key.startsWith('@')) entry.key: entry.value as String,
    };

List<String> _locales() {
  final found = Directory(_arbDir)
      .listSync()
      .whereType<File>()
      .map((file) => file.uri.pathSegments.last)
      .where((name) => name.startsWith('app_') && name.endsWith('.arb'))
      .map((name) => name.substring('app_'.length, name.length - '.arb'.length))
      .toList()
    ..sort();
  return found;
}

String _pathFor(String locale) => '$_arbDir/app_$locale.arb';

/// ICU placeholder names, e.g. `{count}` in `{count, plural, ...}`. Numeric
/// plural selectors such as `=1{1 factor}` are deliberately not matched.
Set<String> _placeholders(String message) =>
    RegExp(r'\{([A-Za-z_][A-Za-z0-9_]*)[,}]')
        .allMatches(message)
        .map((match) => match.group(1)!)
        .toSet();

void main() {
  final english = _messages(_templatePath);
  final locales = _locales();
  final translated = [
    for (final locale in locales)
      if (locale != _templateLocale) locale
  ];

  group('ARB parity', () {
    test('there is at least one translation to check', () {
      expect(translated, isNotEmpty);
      expect(english, isNotEmpty);
    });

    test('every locale defines exactly the keys the template defines', () {
      for (final locale in translated) {
        final messages = _messages(_pathFor(locale));

        final missing =
            (english.keys.toSet()..removeAll(messages.keys)).toList()..sort();
        final orphaned =
            (messages.keys.toSet()..removeAll(english.keys)).toList()..sort();

        expect(
          missing,
          isEmpty,
          reason: '$locale is missing: ${missing.join(', ')}. Add them to '
              '${_pathFor(locale)}, or the app will fall back to English for '
              'those strings.',
        );
        expect(
          orphaned,
          isEmpty,
          reason: '$locale defines keys the template does not: '
              '${orphaned.join(', ')}. Nothing renders them, so they are dead '
              'strings (usually a rename that only landed in some files).',
        );
      }
    });

    test('no locale ships a blank message', () {
      for (final locale in locales) {
        final empty = _messages(_pathFor(locale))
            .entries
            .where((entry) => entry.value.trim().isEmpty)
            .map((entry) => entry.key)
            .toList()
          ..sort();
        expect(empty, isEmpty,
            reason: '$locale has blank messages: ${empty.join(', ')}');
      }
    });

    test('translations keep the placeholders the English text uses', () {
      for (final locale in translated) {
        final messages = _messages(_pathFor(locale));
        for (final entry in english.entries) {
          final expected = _placeholders(entry.value);
          if (expected.isEmpty) continue;

          final actual = _placeholders(messages[entry.key]!);
          final dropped = expected.difference(actual);
          // Extra placeholders are just as broken: the generated signature
          // comes from the template, so the caller cannot supply them.
          final invented = actual.difference(expected);

          expect(
            dropped,
            isEmpty,
            reason: '$locale.${entry.key} drops ${dropped.join(', ')} — the '
                'value will render the placeholder name instead of the value.',
          );
          expect(
            invented,
            isEmpty,
            reason: '$locale.${entry.key} uses ${invented.join(', ')}, which '
                'the English text never passes.',
          );
        }
      }
    });

    test('each file declares the locale its name claims', () {
      for (final locale in locales) {
        expect(
          _read(_pathFor(locale))['@@locale'],
          locale,
          reason: '${_pathFor(locale)} declares the wrong @@locale, so flutter '
              'will generate a class that never gets selected.',
        );
      }
    });

    test('only the template carries @ metadata', () {
      // gen-l10n reads descriptions and placeholder types from the template
      // only; a copy elsewhere looks authoritative and silently diverges.
      for (final locale in translated) {
        final stray = _read(_pathFor(locale))
            .keys
            .where((key) => key.startsWith('@') && key != '@@locale')
            .toList()
          ..sort();
        expect(stray, isEmpty,
            reason:
                '$locale has metadata that is never read: ${stray.join(', ')}');
      }
    });
  });

  group('generated localisations', () {
    test('the committed output covers every key, so it is not stale', () {
      // The generated classes are checked in, so they can drift from the ARBs
      // whenever someone edits a translation and forgets to regenerate. A key
      // nothing references yet compiles either way and would only fail on the
      // device of the person who speaks that language.
      for (final locale in locales) {
        final generated = File('lib/l10n/app_localizations_$locale.dart');
        expect(
          generated.existsSync(),
          isTrue,
          reason: '${generated.path} is missing. Run: flutter gen-l10n',
        );

        final source = generated.readAsStringSync();
        final stale = [
          for (final key in _messages(_pathFor(locale)).keys)
            if (!source.contains(key)) key,
        ]..sort();

        expect(
          stale,
          isEmpty,
          reason: '${generated.path} is out of date for: ${stale.join(', ')}. '
              'Run: flutter gen-l10n',
        );
      }
    });
  });

  group('coverage', () {
    test('the picker and the ARB files offer the same languages', () {
      final offered = AppLanguages.pickerOptions
          .where((language) => !language.isSignLanguage)
          .map((language) => language.flutterCode)
          .toSet();

      expect(
        offered.difference(locales.toSet()),
        isEmpty,
        reason:
            'These languages are offered in the picker with no ARB file, so '
            'picking them leaves the whole app in English.',
      );
      expect(
        locales.toSet().difference(offered),
        isEmpty,
        reason: 'These ARB files are never offered, so their translations are '
            'unreachable.',
      );
    });

    test('English fallback does not grow', () {
      for (final locale in translated) {
        final messages = _messages(_pathFor(locale));
        final untranslated = [
          for (final entry in messages.entries)
            if (english[entry.key] == entry.value) entry.key,
        ]..sort();

        final ceiling = _englishCeiling[locale];
        expect(ceiling, isNotNull, reason: 'No ceiling recorded for $locale.');
        expect(
          untranslated.length,
          lessThanOrEqualTo(ceiling!),
          reason: '$locale has ${untranslated.length} messages that are still '
              'the English text (ceiling: $ceiling). Either translate them or '
              'raise the ceiling deliberately. Currently: '
              '${untranslated.take(10).join(', ')}'
              '${untranslated.length > 10 ? ' …' : ''}',
        );
      }
    });

    test('every locale with a ceiling still exists', () {
      expect(_englishCeiling.keys.toSet(), translated.toSet());
    });
  });
}
