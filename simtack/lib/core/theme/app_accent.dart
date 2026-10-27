import 'package:flutter/material.dart';

/// Clinical and brand accents, resolved per brightness.
///
/// These used to exist only as literals in screens: 90 distinct hex values
/// across `lib/`, against 9 members on [AppPalette]. That is why screens did not
/// line up — every one of them invented its own shade.
///
/// [AppPalette] deliberately excludes accents on the grounds that they "read
/// well on both backgrounds". Measured against WCAG 2.2 they do not. On the dark
/// surface the brand violet is 2.06:1 and the teal 2.67:1, both far below the
/// 4.5:1 a label needs, and the practitioner console is brightness-aware, so
/// every violet label in dark mode was failing. Accents therefore resolve per
/// brightness.
///
/// Light values are the exact hexes already in the app, so nothing changes
/// colour where the colour was already correct.
///
/// Each accent comes in two forms: `xOn(Brightness)`, which is pure and is what
/// tests assert against, and `x(BuildContext)`, which is what screens call.
///
/// Ratios below are measured, against the surface each is meant for:
/// light `#FFFFFF`, dark `#1E293B`, AA body text 4.5:1, AA non-text 3:1.
///
/// Usage rules that follow from the numbers:
///  - [success] and [warning] are for text. [successFill] and [warningFill] are
///    for fills and icons behind dark text, never for small text: amber-500 is
///    2.15:1 on white and fails even the 3:1 non-text bar.
///  - [fieldError] is a border and icon colour only (3.76:1). Validation text
///    uses [danger].
///  - [primary] is an accent for text, icons and borders. Filled buttons use
///    [primaryFill] with [onPrimary].
class AppAccent {
  AppAccent._();

  static const Color _violetLight = Color(0xFF6D28D9);
  static const Color _violetDark = Color(0xFFA78BFA);
  static const Color _dangerLight = Color(0xFFDC2626);
  static const Color _dangerDark = Color(0xFFF87171);
  static const Color _fieldErrorLight = Color(0xFFEF4444);
  static const Color _fieldErrorDark = Color(0xFFF87171);
  static const Color _successLight = Color(0xFF15803D);
  static const Color _successDark = Color(0xFF4ADE80);
  static const Color _warningLight = Color(0xFFB45309);
  static const Color _warningDark = Color(0xFFFBBF24);
  static const Color _infoLight = Color(0xFF0F766E);
  static const Color _infoDark = Color(0xFF2DD4BF);
  static const Color _tierRedLight = Color(0xFFB91C1C);
  static const Color _tierRedDark = Color(0xFFF87171);
  static const Color _tierOrangeLight = Color(0xFFC2410C);
  static const Color _tierOrangeDark = Color(0xFFFDBA74);
  static const Color _tierYellowLight = Color(0xFFA16207);
  static const Color _tierYellowDark = Color(0xFFFDE047);
  static const Color _tierGreenLight = Color(0xFF15803D);
  static const Color _tierGreenDark = Color(0xFF4ADE80);

  /// Brand violet. Light 0xFF6D28D9 = 7.10:1, dark 0xFFA78BFA = 5.38:1.
  static Color primaryOn(Brightness brightness) =>
      brightness == Brightness.dark ? _violetDark : _violetLight;

  static Color primary(BuildContext context) =>
      primaryOn(Theme.of(context).brightness);

  /// Violet for filled surfaces, under [onPrimary]. 7.10:1 with white text, so
  /// it does not change with brightness.
  static const Color primaryFill = _violetLight;

  /// Text and icons on [primaryFill]. 7.10:1.
  static const Color onPrimary = Color(0xFFFFFFFF);

  /// Clinical danger and validation text. Light 0xFFDC2626 = 4.83:1,
  /// dark 0xFFF87171 = 5.29:1.
  static Color dangerOn(Brightness brightness) =>
      brightness == Brightness.dark ? _dangerDark : _dangerLight;

  static Color danger(BuildContext context) =>
      dangerOn(Theme.of(context).brightness);

  /// Danger behind white text. 4.83:1.
  static const Color dangerFill = _dangerLight;

  /// Invalid field borders and their icons, not text. Light 0xFFEF4444 =
  /// 3.76:1, which clears the 3:1 non-text bar and fails body text.
  static Color fieldErrorOn(Brightness brightness) =>
      brightness == Brightness.dark ? _fieldErrorDark : _fieldErrorLight;

  static Color fieldError(BuildContext context) =>
      fieldErrorOn(Theme.of(context).brightness);

  /// Low-risk text. Light 0xFF15803D = 5.02:1. The previous 0xFF16A34A is
  /// 3.30:1 on white and failed AA at the 12-14px sizes it was used at, so the
  /// text shade moved one step darker inside the same hue; the fill did not.
  static Color successOn(Brightness brightness) =>
      brightness == Brightness.dark ? _successDark : _successLight;

  static Color success(BuildContext context) =>
      successOn(Theme.of(context).brightness);

  /// Low-risk fills and icons. 3.30:1 on white, above the 3:1 non-text bar.
  static const Color successFill = Color(0xFF16A34A);

  /// Medium-risk and warning text. Light 0xFFB45309 = 5.02:1, dark
  /// 0xFFFBBF24 = 8.76:1. 0xFFF59E0B is 2.15:1 on white and cannot carry text.
  static Color warningOn(Brightness brightness) =>
      brightness == Brightness.dark ? _warningDark : _warningLight;

  static Color warning(BuildContext context) =>
      warningOn(Theme.of(context).brightness);

  /// Warning fills and icons behind dark text.
  static const Color warningFill = Color(0xFFF59E0B);

  /// Informational teal. Light 0xFF0F766E = 5.47:1, dark 0xFF2DD4BF = 7.86:1.
  static Color infoOn(Brightness brightness) =>
      brightness == Brightness.dark ? _infoDark : _infoLight;

  static Color info(BuildContext context) =>
      infoOn(Theme.of(context).brightness);

  /// Teal behind white text. 5.47:1.
  static const Color infoFill = _infoLight;

  /// The four SATS triage categories, in the colours the scale publishes.
  ///
  /// This is the one place in the app where a colour is the clinical answer
  /// rather than decoration: a Red patient means "resuscitation", and the hue is
  /// how a triage officer reads that across a room. So the four are named by tier
  /// instead of being borrowed from [danger]/[warning]/[success], whose shades
  /// serve the score bands, and each resolves per brightness because the
  /// practitioner console is brightness-aware.
  ///
  /// Measured, on white / on the dark surface: red 6.47 / 5.29, orange 5.18 /
  /// 8.67, yellow 4.92 / 11.10, green 5.02 / 8.40. All four clear the 4.5:1 an
  /// AA label needs, which is what test/app_theme_test.dart pins.
  ///
  /// An unknown tier resolves to null in both forms: a payload from an older
  /// backend that names a fifth category must not be given a colour, because the
  /// colour would read as a clinical decision the scale never made.
  static Color? triageTierOn(Brightness brightness, String tier) {
    final pair = switch (tier) {
      'red' => (_tierRedLight, _tierRedDark),
      'orange' => (_tierOrangeLight, _tierOrangeDark),
      'yellow' => (_tierYellowLight, _tierYellowDark),
      'green' => (_tierGreenLight, _tierGreenDark),
      _ => null,
    };
    if (pair == null) return null;
    return brightness == Brightness.dark ? pair.$2 : pair.$1;
  }

  /// The SATS colour for [tier] against the ambient brightness, or null when the
  /// tier is not one of the four. Callers fall back to a muted slate tone rather
  /// than guessing a colour for a category they did not receive.
  static Color? triageTier(BuildContext context, String tier) =>
      triageTierOn(Theme.of(context).brightness, tier);

  /// The calm informational panel this class was originally written for: a
  /// surface, not a colour for text. Kept under the name the screens already
  /// call, folded into the tint family so there is one teal ramp.
  static Color infoSurface(BuildContext context) =>
      _isDark(context) ? const Color(0xFF134E4A) : const Color(0xFFF0FDFA);

  /// Violet tint behind [primary] text: selected rows, brand panels.
  ///
  /// The tints below are the soft backgrounds that carry a status message, with
  /// the text on them in the matching accent. They were among the last literals
  /// screens invented by hand (`0xFFFEF2F2`, `0xFFFFFBEB`, `0xFFE6F4F1`), and a
  /// hand-picked tint has no inverse for dark mode, which is why those panels
  /// stayed pale cream on a dark background.
  static Color primaryTint(BuildContext context) =>
      _isDark(context) ? const Color(0xFF2E1065) : const Color(0xFFEDE9FE);

  static Color dangerTint(BuildContext context) =>
      _isDark(context) ? const Color(0xFF450A0A) : const Color(0xFFFEF2F2);

  static Color warningTint(BuildContext context) =>
      _isDark(context) ? const Color(0xFF451A03) : const Color(0xFFFFFBEB);

  static Color infoTint(BuildContext context) =>
      _isDark(context) ? const Color(0xFF042F2E) : const Color(0xFFE6F4F1);

  static Color successTint(BuildContext context) =>
      _isDark(context) ? const Color(0xFF052E16) : const Color(0xFFF0FDF4);

  static bool _isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;
}
