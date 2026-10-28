import 'package:flutter/material.dart';

import '../platform/webgl_support.dart';

/// The still front figure every 3D view falls back to.
///
/// Cropped from `body_visible_front.png` — the flat body map's visible layer —
/// to the figure's bounding box. The source plate is 800x1000 with the body
/// occupying roughly the middle third, so dropping it into a hero-sized box
/// produced a small, pale figure in a large field of white margin, which read
/// as an empty panel. Same body, framed for a panel.
const String kBodyStillFront = 'assets/anatomy/body_still_front.png';

/// A body shown in 3D where that is possible, and as a still image where it is
/// not.
///
/// Three screens mounted `ModelViewer` unconditionally: the welcome hero, the
/// practitioner overview card and the pain-details editor. On a browser without
/// a WebGL context, `<model-viewer>` throws while constructing its renderer —
/// `Error creating WebGL context` — removes its own element, and leaves an
/// empty box. Flutter then reports `Node cannot be found in the current page`
/// as the platform view it was managing disappears. The body was simply gone,
/// with nothing shown and nothing said.
///
/// The fix is to never mount the renderer the browser has already told us it
/// cannot run. [viewer] is only built when a context is actually available, so
/// the failure does not happen instead of being handled after it does.
class Body3DFallback extends StatelessWidget {
  const Body3DFallback({
    super.key,
    required this.viewer,
    this.still = kBodyStillFront,
    this.stillFit = BoxFit.contain,
    this.stillAlignment = Alignment.center,
    this.stillBackground = Colors.white,
    this.canRender3D,
  });

  /// The configured 3D viewer, built only where WebGL is available.
  ///
  /// Taking the widget rather than its parameters is deliberate: every call
  /// site keeps its own `ModelViewer` configuration — camera orbit, exposure,
  /// shadow, background — untouched, and this type owns exactly one decision.
  final Widget viewer;

  /// Image shown instead of [viewer].
  final String still;

  final BoxFit stillFit;
  final Alignment stillAlignment;

  /// Painted behind [still].
  ///
  /// The figure is drawn on a white plate, so it needs a plate to sit on rather
  /// than floating as a white rectangle on whatever colour the page happens to
  /// be. White by default, because that is the colour of the plate itself.
  final Color stillBackground;

  /// Overrides the platform probe. `null` asks [detectWebglSupport].
  ///
  /// The welcome hero passes an override because it has a second, unrelated
  /// reason to skip the live model off the web; see `welcome_screen.dart`.
  final bool? canRender3D;

  /// Key on the still image, so a test can tell which branch ran.
  static const Key stillKey = ValueKey('body3d-still');

  @override
  Widget build(BuildContext context) {
    if (canRender3D ?? detectWebglSupport()) return viewer;
    return ColoredBox(
      color: stillBackground,
      child: Image.asset(
        still,
        key: stillKey,
        fit: stillFit,
        alignment: stillAlignment,
      ),
    );
  }
}
