import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

// `part` is always one of the backend's 14 fixed KB region strings (the
// resolved region — unchanged contract). `partName`, when present, is the
// precise anatomical structure that was actually tapped in the 3D view
// (e.g. "Distal phalanx of left index finger"). `hitX/hitY/hitZ` is the
// real 3D point in the viewer's own world-space that was tapped — used to
// place a marker as an actual object in that scene (so it rotates
// correctly with the body) rather than a flat 2D overlay positioned only
// for the camera angle at tap time. The 2D tap view never sends any of
// partName/hitX/hitY/hitZ, so they're null there.
typedef BodyPartTap = ({
  String part,
  double? x,
  double? y,
  String? partName,
  double? hitX,
  double? hitY,
  double? hitZ,
});
typedef BodyPartCallback = void Function(BodyPartTap tap);

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
      if (p is! String || p.isEmpty) return;

      double? asDouble(Object? v) => v is num ? v.toDouble() : null;

      onBodyPart((
        part: p,
        x: asDouble(converted['x']),
        y: asDouble(converted['y']),
        partName: converted['partName'] is String
            ? converted['partName'] as String
            : null,
        hitX: asDouble(converted['hx']),
        hitY: asDouble(converted['hy']),
        hitZ: asDouble(converted['hz']),
      ));
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

  /// Sends a message INTO the embedded 3D viewer's iframe — the reverse
  /// direction of [registerBodyPartListener]. Used to push the current
  /// list of marked pain points into the scene so it can draw/update/
  /// remove the actual 3D marker objects at each point's real position.
  static void postToIframe(
      web.HTMLIFrameElement iframe, Map<String, Object?> message) {
    final win = iframe.contentWindow;
    if (win == null) return;
    win.postMessage(message.jsify(), '*'.toJS);
  }
}
