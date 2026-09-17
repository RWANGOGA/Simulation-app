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

  // Listens for `window.postMessage`, NOT a same-window CustomEvent. The 3D
  // viewer runs inside an <iframe> (Anatomy3DTapView), which has its own
  // separate `window` from this page — a CustomEvent dispatched inside the
  // iframe never reaches a listener registered on the parent window's
  // `window` object at all; postMessage is the mechanism actually designed
  // to cross that boundary. (An earlier version of this listener used
  // `addEventListener('atomybridge-bodypart', ...)`, matching a dispatch
  // the iframe side has since been fixed to no longer use, for exactly
  // this reason — every tap resolved correctly inside the iframe, but
  // nothing outside it ever found out.)
  static void registerBodyPartListener(BodyPartCallback onBodyPart) {
    void listener(web.Event event) {
      final messageEvent = event as web.MessageEvent;
      final converted = messageEvent.data.dartify();
      if (converted is! Map) return;
      if (converted['type'] != 'atomybridge-bodypart') return;

      final p = converted['part'];
      final rx = converted['x'];
      final ry = converted['y'];
      final pn = converted['partName'];

      String? part;
      double? x;
      double? y;
      String? partName;
      if (p is String) part = p;
      if (rx is num) x = rx.toDouble();
      if (ry is num) y = ry.toDouble();
      if (pn is String) partName = pn;

      if (part != null && part.isNotEmpty) {
        onBodyPart(part, x, y, partName);
      }
    }

    final jsListener = listener.toJS;
    _listeners[onBodyPart] = jsListener;
    web.window.addEventListener('message', jsListener);
  }

  static void unregisterBodyPartListener(BodyPartCallback onBodyPart) {
    final listener = _listeners.remove(onBodyPart);
    if (listener != null) {
      web.window.removeEventListener('message', listener);
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
