import 'package:flutter/material.dart';

import 'app_accent.dart';
import 'app_palette.dart';

/// The practitioner-side colour vocabulary.
///
/// It used to carry a separate GitHub Primer palette, which made the patient
/// and practitioner halves of the app look like two different products. The
/// token *names* are kept because every dense console widget is written in
/// terms of them, but each value now resolves to the same patient-side tokens
/// in [AppPalette] and [AppAccent]. Shapes, borders and type sizes stay in the
/// GitHub/Primer idiom — that is what makes a dense list scannable — while the
/// colours are shared with the patient experience.
///
/// Everything resolves against ambient brightness, and no screen holds a hex
/// literal of its own.
class GhColors {
  GhColors._();

  // ── Canvas and surfaces ────────────────────────────────────────────────
  /// Page background.
  static Color canvas(BuildContext context) => AppPalette.scaffold(context);

  /// Recessed background, used behind boxes for contrast.
  static Color canvasInset(BuildContext context) => AppPalette.inputFill(context);

  /// Box / panel body.
  static Color surface(BuildContext context) => AppPalette.surface(context);

  /// Box headers, table headers, count pills.
  static Color surfaceSubtle(BuildContext context) =>
      AppPalette.raisedSurface(context);

  /// Row hover.
  static Color surfaceHover(BuildContext context) =>
      AppPalette.subtleFill(context);

  // ── Borders ────────────────────────────────────────────────────────────
  /// Default 1px border.
  static Color border(BuildContext context) => AppPalette.border(context);

  /// Hairline between rows inside a box.
  static Color borderMuted(BuildContext context) => AppPalette.divider(context);

  // ── Foreground ─────────────────────────────────────────────────────────
  /// Primary text.
  static Color fg(BuildContext context) => AppPalette.textPrimary(context);

  /// Secondary text: timestamps, captions, placeholders.
  static Color fgMuted(BuildContext context) => AppPalette.textMuted(context);

  /// Text on a filled (emphasis) background.
  static const Color fgOnEmphasis = AppAccent.onPrimary;

  // ── Semantic hues ──────────────────────────────────────────────────────
  /// Links, selection, focus — the patient brand violet.
  static Color accent(BuildContext context) => AppAccent.primary(context);

  /// Selected-row fill.
  static Color accentSubtle(BuildContext context) =>
      AppAccent.primaryTint(context);

  static Color success(BuildContext context) => AppAccent.success(context);

  static Color successSubtle(BuildContext context) =>
      AppAccent.successTint(context);

  static Color attention(BuildContext context) => AppAccent.warning(context);

  static Color attentionSubtle(BuildContext context) =>
      AppAccent.warningTint(context);

  static Color danger(BuildContext context) => AppAccent.danger(context);

  static Color dangerSubtle(BuildContext context) =>
      AppAccent.dangerTint(context);

  /// A completed/closed state: informational teal, never a second green.
  static Color done(BuildContext context) => AppAccent.info(context);

  static Color doneSubtle(BuildContext context) => AppAccent.infoTint(context);

  static Color neutral(BuildContext context) => AppPalette.textMuted(context);

  static Color neutralSubtle(BuildContext context) =>
      AppPalette.subtleFill(context);

  // ── Chrome ─────────────────────────────────────────────────────────────
  /// The global navigation bar, in the patient brand violet.
  static Color headerBg(BuildContext context) => AppAccent.primaryFill;

  static Color headerFg(BuildContext context) => AppAccent.onPrimary;

  static Color headerFgMuted(BuildContext context) =>
      headerFg(context).withOpacity(0.72);

  /// Translucent pill behind header actions, so icons stay legible on any
  /// shade of the bar.
  static Color headerActionBg(BuildContext context) =>
      headerFg(context).withOpacity(0.12);

  // ── Controls ───────────────────────────────────────────────────────────
  /// Primary (create/confirm) button.
  static Color primaryBg(BuildContext context) => AppAccent.primaryFill;

  static Color primaryHover(BuildContext context) =>
      AppAccent.primaryFill.withOpacity(0.88);

  /// Default button fill.
  static Color defaultButtonBg(BuildContext context) =>
      AppPalette.surface(context);

  /// The 2px indicator under the selected tab.
  static Color underline(BuildContext context) => AppAccent.primary(context);

  /// Colour behind risk/danger emphasis filled buttons.
  static Color dangerBg(BuildContext context) => AppAccent.dangerFill;
}

/// The six states a label, counter or dot can carry.
///
/// Screens pick a *meaning* (`GhTone.danger`) and the palette decides what that
/// meaning looks like on the current brightness — including a clinical mapping
/// such as high risk → danger, which is why the mapping lives in one place
/// instead of being re-derived per screen.
enum GhTone {
  accent,
  success,
  attention,
  danger,
  done,
  neutral;

  Color color(BuildContext context) {
    switch (this) {
      case GhTone.accent:
        return GhColors.accent(context);
      case GhTone.success:
        return GhColors.success(context);
      case GhTone.attention:
        return GhColors.attention(context);
      case GhTone.danger:
        return GhColors.danger(context);
      case GhTone.done:
        return GhColors.done(context);
      case GhTone.neutral:
        return GhColors.neutral(context);
    }
  }

  Color subtle(BuildContext context) {
    switch (this) {
      case GhTone.accent:
        return GhColors.accentSubtle(context);
      case GhTone.success:
        return GhColors.successSubtle(context);
      case GhTone.attention:
        return GhColors.attentionSubtle(context);
      case GhTone.danger:
        return GhColors.dangerSubtle(context);
      case GhTone.done:
        return GhColors.doneSubtle(context);
      case GhTone.neutral:
        return GhColors.neutralSubtle(context);
    }
  }
}

/// Type scale for the practitioner console.
///
/// GitHub runs almost everything at 12/14/16 with few weights, which is what
/// lets a screen hold four kinds of metadata without shouting. Sizes only — the
/// colour always comes from [GhColors] at the call site, because the same
/// header is `fg` in a box and `headerFg` on the dark bar.
class GhType {
  GhType._();

  /// Page title on the dark bar.
  static const TextStyle headerTitle = TextStyle(
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// Secondary line under a page title.
  static const TextStyle headerSubtitle = TextStyle(fontSize: 12);

  /// Box header, section title.
  static const TextStyle title = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// Section heading sitting *above* a box (16px, the GitHub "h2").
  static const TextStyle sectionTitle = TextStyle(
    fontSize: 16,
    fontWeight: FontWeight.w600,
  );

  /// Row label, button label, form label.
  static const TextStyle body = TextStyle(fontSize: 14);

  /// Emphasised row label (unread / selected).
  static const TextStyle bodyStrong = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w600,
  );

  /// Metadata: timestamps, counts, captions.
  static const TextStyle meta = TextStyle(fontSize: 12);

  /// A stat tile's number.
  static const TextStyle statValue = TextStyle(
    fontSize: 28,
    fontWeight: FontWeight.w600,
    height: 1.15,
    letterSpacing: -0.5,
  );

  /// Identifier strings (patient codes): GitHub sets these in mono, and a
  /// slightly wider tracking reads the same way without shipping a font.
  static const TextStyle code = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.4,
  );
}
