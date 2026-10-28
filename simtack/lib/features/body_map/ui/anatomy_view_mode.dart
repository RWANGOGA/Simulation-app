import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/platform/webgl_support.dart';

/// Which renderer the anatomy view should use.
///
/// The two renderers are not equivalent, and the difference is deliberately
/// visible rather than hidden: the 3D viewer resolves a tap to one of the 34
/// region strings in `body_graph.json` (`Left Wrist`, `Left Armpit`), while the
/// flat view's ID map only distinguishes seven coarse regions
/// (`left upper limb`). Anything that shows this switch is therefore also
/// telling the patient that the flat view is the less precise one.
enum AnatomyViewMode {
  /// Follow the platform: 3D where it can run, flat everywhere else. This is
  /// the default so that no screen is left with no body at all — the failure
  /// this replaces was a literal "isn't available on this platform" box.
  auto,

  /// Force the flat image + ID-map hit test.
  flat,

  /// Force the Three.js viewer. Ignored where it cannot run; see [renders3D].
  solid;

  static const String prefsKey = 'anatomy.view_mode';

  /// Whether the 3D viewer can actually run on this platform.
  ///
  /// A capability check, not a size check: the viewer is a real
  /// `HtmlElementView` iframe reading ~58MB of geometry from `web/anatomy3d/`,
  /// and that directory is not in the pubspec asset bundle. Guessing from
  /// window width would be wrong in both directions — a phone is "wide" in
  /// landscape and still cannot host an iframe.
  ///
  /// Two conditions, because there are two independent ways to fail. The
  /// iframe only exists on the web; and inside `web/anatomy3d/` the very first
  /// thing `viewer.js` does is `new THREE.WebGLRenderer`, which throws where no
  /// WebGL context can be created. Being on the web is not enough — a browser
  /// with its GPU process sandboxed or its hardware acceleration off is on the
  /// web and still cannot draw a triangle.
  static bool get platformCanRender3D => kIsWeb && detectWebglSupport();

  /// Resolves this mode against what the platform can do.
  ///
  /// An explicit [solid] request silently becomes flat on a platform that
  /// cannot host the viewer, because the alternative is the placeholder box
  /// this whole type exists to delete. The UI is expected to hide the 3D
  /// option entirely when [platformCanRender3D] is false, so reaching that
  /// fallback means the stored preference followed the user across devices.
  bool renders3D() => switch (this) {
        AnatomyViewMode.auto => platformCanRender3D,
        AnatomyViewMode.flat => false,
        AnatomyViewMode.solid => platformCanRender3D,
      };

  /// Tolerant decode: an unknown or missing value is [auto], so a preference
  /// written by a future build cannot leave an existing install with no
  /// renderer selected.
  static AnatomyViewMode fromName(String? name) {
    for (final mode in values) {
      if (mode.name == name) return mode;
    }
    return AnatomyViewMode.auto;
  }
}

/// Reads and writes the persisted [AnatomyViewMode].
///
/// Kept separate from the enum so the widget tree does not import
/// `shared_preferences` directly, and so tests can drive the mode without
/// touching platform channels.
class AnatomyViewModeStore {
  const AnatomyViewModeStore._();

  static Future<AnatomyViewMode> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return AnatomyViewMode.fromName(
          prefs.getString(AnatomyViewMode.prefsKey));
    } catch (_) {
      // A missing or unreadable store is not an error worth surfacing: the
      // default (`auto`) is a working renderer on every platform.
      return AnatomyViewMode.auto;
    }
  }

  static Future<void> save(AnatomyViewMode mode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(AnatomyViewMode.prefsKey, mode.name);
    } catch (_) {
      // Persisting is a convenience. A failure here must not break the
      // current session's already-applied mode.
    }
  }
}
