import 'package:flutter/material.dart';

import 'app_breakpoints.dart';
import 'app_tokens.dart';

/// The three content widths the app is allowed to have.
///
/// A width is a *role*, not a number to be re-picked per screen: text that is
/// meant to be read gets a measure narrow enough to read, a form gets a column
/// narrow enough to fill, and a console gets everything the window has.
class AppContentWidth {
  AppContentWidth._();

  /// A single centred form: sign in, registration, a settings page.
  static const double form = 560;

  /// Prose and stacked cards — the patient flow. Past roughly 75 characters a
  /// line the eye loses its place on the return sweep, so reading material does
  /// not grow with the window.
  static const double reading = 760;

  /// Two-column consoles and dashboards, where the content genuinely uses the
  /// extra pixels instead of stretching a paragraph across them.
  static const double wide = 1200;
}

/// A page body: responsive gutters, a centred measure, and nothing else.
///
/// This exists because the patient flow had no shared page frame at all. Every
/// screen repeated `Scaffold > SafeArea > Padding(all: 24) > Column`, which
/// looked acceptable at phone size and fell apart on anything wider: the text
/// ran the full width of a browser window with a ragged gap underneath, because
/// nothing in the tree said how wide the content was allowed to be. That is a
/// layout bug you cannot fix screen by screen without re-introducing it on the
/// next screen, so it is fixed once here.
///
/// Gutters come from [AppSpacing] rather than from fresh literals, and widen
/// with the window:
///
/// | width            | gutter |
/// |------------------|--------|
/// | compact (< 600)  | 16     |
/// | medium (>= 600)  | 24     |
/// | large (>= 1200)  | 32     |
///
/// Use [AppPage] for the body of a page. Set [scrollable] when the screen has no
/// scroll view of its own; leave it false and place [AppPage] inside the
/// screen's existing [SingleChildScrollView] when the screen already scrolls, so
/// the scroll controller stays owned by the screen.
class AppPage extends StatelessWidget {
  const AppPage({
    super.key,
    required this.child,
    this.maxWidth = AppContentWidth.reading,
    this.padding,
    this.verticalPadding = AppSpacing.xl,
    this.alignment = Alignment.topCenter,
    this.scrollable = false,
  });

  final Widget child;

  /// The measure this content is allowed to reach. Defaults to the reading
  /// width; forms pass [AppContentWidth.form] and consoles [AppContentWidth.wide].
  final double maxWidth;

  /// Overrides the whole inset. Leave null to get the responsive horizontal
  /// gutter and the standard vertical padding.
  final EdgeInsetsGeometry? padding;

  /// The top and bottom inset when [padding] is null. Bars and header strips
  /// pass a smaller value than the page default, because they are chrome rather
  /// than content and should not carry a page's breathing room.
  final double verticalPadding;

  final AlignmentGeometry alignment;

  /// Wraps the page in a [SingleChildScrollView]. Exists so this widget can
  /// replace the `SingleChildScrollView(padding: ..., child: ...)` pair that the
  /// patient flow repeated on every screen, one-for-one — a swap that keeps the
  /// widget tree's shape, and therefore its indentation and parenthesis count,
  /// identical to what was there before.
  final bool scrollable;

  /// The horizontal inset for a window of [width]. Exposed because a screen with
  /// its own scroll view sometimes needs the same number (to inset a divider or
  /// a sticky footer that must line up with the content above it).
  static double gutterFor(double width) {
    if (AppBreakpoints.isCompact(width)) return AppSpacing.lg;
    if (width < AppBreakpoints.expanded) return AppSpacing.xl;
    return AppSpacing.xxl;
  }

  /// The same measure and gutter as [AppPage], shrink-wrapped for a bar that
  /// hugs an edge — typically a `Scaffold.bottomNavigationBar` holding the
  /// primary button.
  ///
  /// [AppPage] cannot do this itself: it is a full-height [Align], so putting it
  /// in a bottom bar makes the bar swallow the whole screen. Without it, the
  /// button spans the window while the content above it stays at the reading
  /// measure, which is the mismatch that made these screens look unfinished on
  /// a desktop-sized viewport.
  static Widget bar(
    Widget child, {
    double maxWidth = AppContentWidth.reading,
    EdgeInsets padding = const EdgeInsets.symmetric(vertical: AppSpacing.lg),
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gutter = gutterFor(constraints.maxWidth);
        return Padding(
          padding: EdgeInsets.symmetric(horizontal: gutter).add(padding),
          child: Center(
            // heightFactor: 1 keeps the bar as short as its child. Width is
            // left to expand so a `width: double.infinity` button can claim the
            // full measure.
            heightFactor: 1,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final page = LayoutBuilder(
      builder: (context, constraints) {
        final gutter = gutterFor(constraints.maxWidth);
        return Align(
          alignment: alignment,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: Padding(
              padding: padding ??
                  EdgeInsets.symmetric(
                    horizontal: gutter,
                    vertical: verticalPadding,
                  ),
              child: child,
            ),
          ),
        );
      },
    );
    return scrollable ? SingleChildScrollView(child: page) : page;
  }
}
