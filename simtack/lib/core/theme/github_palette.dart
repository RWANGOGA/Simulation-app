import 'package:flutter/material.dart';

/// GitHub Primer tokens — the practitioner side's colour language.
///
/// The patient side keeps [AppPalette]'s purple/teal, and that separation is
/// deliberate: a patient answering a triage question should not feel like they
/// opened a code repository. Practitioners live in this app all day, and the
/// console idiom they already read fluently — dark chrome, one-pixel borders,
/// six-pixel radii, state labels, counters — is what makes a dense list of
/// sessions scannable at a glance.
///
/// Every value resolves against the ambient brightness, so the practitioner
/// area still follows the app's light/dark switch, and no screen has to hold a
/// hex literal of its own. The hexes are Primer's published scale values.
class GhColors {
  GhColors._();

  static bool _dark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  // ── Canvas and surfaces ────────────────────────────────────────────────
  /// Page background (Primer `canvas.default`).
  static Color canvas(BuildContext context) =>
      _dark(context) ? const Color(0xFF0D1117) : const Color(0xFFFFFFFF);

  /// Recessed background, used behind boxes for contrast (`canvas.inset`).
  static Color canvasInset(BuildContext context) =>
      _dark(context) ? const Color(0xFF010409) : const Color(0xFFF6F8FA);

  /// Box / panel body (`canvas.default` on top of the page).
  static Color surface(BuildContext context) =>
      _dark(context) ? const Color(0xFF161B22) : const Color(0xFFFFFFFF);

  /// Box headers, table headers, count pills (`canvas.subtle`).
  static Color surfaceSubtle(BuildContext context) =>
      _dark(context) ? const Color(0xFF161B22) : const Color(0xFFF6F8FA);

  /// Row hover (`neutral.muted` with alpha in Primer; flattened here).
  static Color surfaceHover(BuildContext context) =>
      _dark(context) ? const Color(0xFF1C2128) : const Color(0xFFF3F4F6);

  // ── Borders ────────────────────────────────────────────────────────────
  /// Default 1px border (`border.default`).
  static Color border(BuildContext context) =>
      _dark(context) ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);

  /// Hairline between rows inside a box (`border.muted`).
  static Color borderMuted(BuildContext context) =>
      _dark(context) ? const Color(0xFF21262D) : const Color(0xFFD8DEE4);

  // ── Foreground ─────────────────────────────────────────────────────────
  /// Primary text (`fg.default`).
  static Color fg(BuildContext context) =>
      _dark(context) ? const Color(0xFFE6EDF3) : const Color(0xFF1F2328);

  /// Secondary text: timestamps, captions, placeholders (`fg.muted`).
  static Color fgMuted(BuildContext context) =>
      _dark(context) ? const Color(0xFF8B949E) : const Color(0xFF656D76);

  /// Text on a filled (emphasis) background.
  static const Color fgOnEmphasis = Color(0xFFFFFFFF);

  // ── Semantic hues ──────────────────────────────────────────────────────
  /// Links, selection, focus (`accent.fg`).
  static Color accent(BuildContext context) =>
      _dark(context) ? const Color(0xFF2F81F7) : const Color(0xFF0969DA);

  /// Selected-row fill (`accent.subtle`).
  static Color accentSubtle(BuildContext context) =>
      _dark(context) ? const Color(0xFF121D2F) : const Color(0xFFDDF4FF);

  static Color success(BuildContext context) =>
      _dark(context) ? const Color(0xFF3FB950) : const Color(0xFF1A7F37);

  static Color successSubtle(BuildContext context) =>
      _dark(context) ? const Color(0xFF12261E) : const Color(0xFFDAFBE1);

  static Color attention(BuildContext context) =>
      _dark(context) ? const Color(0xFFD29922) : const Color(0xFF9A6700);

  static Color attentionSubtle(BuildContext context) =>
      _dark(context) ? const Color(0xFF272115) : const Color(0xFFFFF8C5);

  static Color danger(BuildContext context) =>
      _dark(context) ? const Color(0xFFF85149) : const Color(0xFFCF222E);

  static Color dangerSubtle(BuildContext context) =>
      _dark(context) ? const Color(0xFF25171C) : const Color(0xFFFFEBE9);

  static Color done(BuildContext context) =>
      _dark(context) ? const Color(0xFFA371F7) : const Color(0xFF8250DF);

  static Color doneSubtle(BuildContext context) =>
      _dark(context) ? const Color(0xFF221A2E) : const Color(0xFFFBEFFF);

  static Color neutral(BuildContext context) =>
      _dark(context) ? const Color(0xFF8B949E) : const Color(0xFF6E7681);

  static Color neutralSubtle(BuildContext context) =>
      _dark(context) ? const Color(0xFF21262D) : const Color(0xFFEFF2F5);

  // ── Chrome ─────────────────────────────────────────────────────────────
  /// The dark global navigation bar that every GitHub page hangs from.
  static Color headerBg(BuildContext context) =>
      _dark(context) ? const Color(0xFF161B22) : const Color(0xFF24292F);

  static Color headerFg(BuildContext context) =>
      _dark(context) ? const Color(0xFFE6EDF3) : const Color(0xFFFFFFFF);

  static Color headerFgMuted(BuildContext context) =>
      headerFg(context).withOpacity(0.72);

  /// Translucent pill behind header actions, so icons stay legible on any
  /// shade of the bar.
  static Color headerActionBg(BuildContext context) =>
      headerFg(context).withOpacity(0.12);

  // ── Controls ───────────────────────────────────────────────────────────
  /// Primary (create/confirm) button — GitHub's green (`btn-primary`).
  static Color primaryBg(BuildContext context) =>
      _dark(context) ? const Color(0xFF238636) : const Color(0xFF1F883D);

  static Color primaryHover(BuildContext context) =>
      _dark(context) ? const Color(0xFF2EA043) : const Color(0xFF1A7F37);

  /// Default button fill (`btn-bg`).
  static Color defaultButtonBg(BuildContext context) =>
      _dark(context) ? const Color(0xFF21262D) : const Color(0xFFF6F8FA);

  /// The 2px indicator under the selected tab in an underline nav.
  static Color underline(BuildContext context) =>
      _dark(context) ? const Color(0xFFF78166) : const Color(0xFFFD8C73);

  /// Colour behind risk/danger emphasis filled buttons.
  static Color dangerBg(BuildContext context) =>
      _dark(context) ? const Color(0xFFDA3633) : const Color(0xFFCF222E);
}

/// The six states a Primer label, counter or dot can carry.
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
