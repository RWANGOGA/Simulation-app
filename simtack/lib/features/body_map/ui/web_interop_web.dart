import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

// `part` is always one of the backend's 14 fixed KB region strings (the
// resolved region — unchanged contract). `partName`, when present, is the
// precise anatomical structure that was actually tapped in the 3D view
// (e.g. "Distal phalanx of left index finger"), for showing the patient a
// more specific label than the coarse region alone; the 2D tap view never
// sends it, so it's null there.
typedef BodyPartCallback = void Function(
    String part, double? x, double? y, String? partName);

class WebInterop {
  static final Map<BodyPartCallback, JSFunction> _listeners = {};

  static void registerBodyPartListener(BodyPartCallback onBodyPart) {
    void listener(web.Event event) {
      final detail = (event as web.CustomEvent).detail;
      if (detail == null) return;

      final converted = detail.dartify();
      String? part;
      double? x;
      double? y;
      String? partName;

      if (converted is String) {
        part = converted;
      } else if (converted is Map) {
        final p = converted['part'];
        final rx = converted['x'];
        final ry = converted['y'];
        final pn = converted['partName'];
        if (p is String) part = p;
        if (rx is num) x = rx.toDouble();
        if (ry is num) y = ry.toDouble();
        if (pn is String) partName = pn;
      }

      if (part != null && part.isNotEmpty) {
        onBodyPart(part, x, y, partName);
      }
    }

    final jsListener = listener.toJS;
    _listeners[onBodyPart] = jsListener;
    web.window.addEventListener('atomybridge-bodypart', jsListener);
  }

  static void unregisterBodyPartListener(BodyPartCallback onBodyPart) {
    final listener = _listeners.remove(onBodyPart);
    if (listener != null) {
      web.window.removeEventListener('atomybridge-bodypart', listener);
    }
  }

  static void applyCameraOrbit(String elementId, String orbit) {
    final el = web.document.getElementById(elementId);
    if (el == null) return;
    el.setAttribute('camera-orbit', orbit);
    try {
      el.callMethod('jumpCameraToGoal'.toJS);
    } catch (_) {
      // Ignored if unsupported in older model-viewer builds
    }
  }
}
