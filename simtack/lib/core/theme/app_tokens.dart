import 'package:flutter/material.dart';

/// Small, shared design tokens — spacing/radius/shadow scale plus a second
/// accent color — so new UI work pulls from the same handful of values
/// instead of every screen picking its own padding numbers and shadow
/// blurs. Not a full design system, just enough consistency that things
/// built at different times read as one product.
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
  static List<BoxShadow> soft(BuildContext context) => [
        BoxShadow(
          color: Colors.black.withOpacity(0.05),
          blurRadius: 12,
          offset: const Offset(0, 4),
        ),
      ];

  /// A slightly stronger shadow for floating/overlaid elements (badges,
  /// FABs) that need to read as sitting above everything else.
  static List<BoxShadow> floating(BuildContext context) => [
        BoxShadow(
          color: Colors.black.withOpacity(0.10),
          blurRadius: 16,
          offset: const Offset(0, 6),
        ),
      ];
}

/// A calm secondary accent, distinct from the purple brand/action color —
/// for informational surfaces (hints, tips, non-urgent status) so not
/// every piece of UI in the app reads as "purple button." Chosen as a
/// soft teal: reads as calm/reassuring (a common cue in health-adjacent
/// products) without competing with the purple for attention on actual
/// calls to action, and passes contrast on both light and dark surfaces.
class AppAccent {
  static Color info(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF5EEAD4)
          : const Color(0xFF0D9488);

  static Color infoSurface(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF134E4A)
          : const Color(0xFFF0FDFA);
}
