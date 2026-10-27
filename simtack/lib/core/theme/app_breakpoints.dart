import 'package:flutter/widgets.dart';

/// The app's width classes — the single source of truth for every decision that
/// depends on how much room a screen has.
///
/// These are Material 3's window size classes (600 / 840 / 1200) rather than
/// numbers invented here, so a width class means the same thing as it does in
/// the platform guidance and in every other Flutter codebase a reader arrives
/// from.
///
/// Before this file the app had four private breakpoints that no two screens
/// shared: `> 600` for the console's nav, `> 700` on the welcome page,
/// `>= 560` for the profile's second column and `< 480` in reports. The same
/// window could therefore be "wide" for one screen and "narrow" for the next,
/// which is what made resizing feel arbitrary. New width-dependent code
/// branches on these; the older call sites are migrated as they are touched.
class AppBreakpoints {
  AppBreakpoints._();

  /// Below this a screen is a single column: phone, narrow browser window.
  static const double compact = 600;

  /// From here a screen may show a second column (list + detail, form + aside).
  static const double medium = 840;

  /// From here the window is large enough for a persistent side panel.
  static const double expanded = 1200;

  static bool isCompact(double width) => width < compact;

  static bool isMedium(double width) => width >= compact && width < medium;

  /// True when there is room for a second column beside the primary content.
  ///
  /// This is the predicate screens should use for "two panes or one", because
  /// it carries the reason rather than repeating a number.
  static bool hasRoomForSecondColumn(double width) => width >= medium;

  /// True when the window is wide enough for a permanent navigation rail.
  static bool hasRoomForRail(double width) => width >= compact;

  /// The width class of the nearest enclosing [MediaQuery], for the rare case
  /// where a widget cannot wrap itself in a [LayoutBuilder].
  static bool isCompactContext(BuildContext context) =>
      isCompact(MediaQuery.sizeOf(context).width);
}
