import 'package:flutter/material.dart';

/// Small, shared design tokens — the spacing, radius and shadow scales.
///
/// Colour lives in two neighbours, split by what they resolve against:
/// [AppPalette] for slate surfaces and text, [AppAccent] for the clinical and
/// brand accents. The teal pair that used to be a class of its own in this file
/// moved into [AppAccent] as `info` and `infoSurface`: an accent scale carrying
/// only `info` is how every screen ended up hardcoding the other eleven.
class AppSpacing {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

class AppRadius {
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
}

class AppShadow {
  /// A soft, low shadow for cards/panels sitting just above the
  /// background — used in place of the many one-off
  /// `BoxShadow(color: Colors.black.withOpacity(0.0X), ...)` literals that
  /// had drifted to slightly different blur/opacity values screen to
  /// screen.
  ///
  /// Brightness-aware, because a shadow tuned for a white sheet is invisible
  /// under a dark one: on the dark surface the same black at 5% separates
  /// nothing, so the dark values are deliberately heavier. These two pairs are
  /// the only shadows the app is meant to use.
  static List<BoxShadow> soft(BuildContext context) => [
        BoxShadow(
          color: Colors.black.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.30 : 0.05,
          ),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// A slightly stronger shadow for floating/overlaid elements (badges,
  /// FABs) that need to read as sitting above everything else.
  static List<BoxShadow> floating(BuildContext context) => [
        BoxShadow(
          color: Colors.black.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.45 : 0.10,
          ),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];

  /// Hairline shadow for the sticky bottom action bars, so a scrolling list
  /// visibly passes *under* the bar instead of colliding with it.
  static List<BoxShadow> bar(BuildContext context) => [
        BoxShadow(
          color: Colors.black.withOpacity(
            Theme.of(context).brightness == Brightness.dark ? 0.40 : 0.06,
          ),
          blurRadius: 8,
          offset: const Offset(0, -2),
        ),
      ];
}
