import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'package:web/web.dart' as web;

typedef BodyPartCallback = void Function(String part, double? x, double? y);

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

      if (converted is String) {
        part = converted;
      } else if (converted is Map) {
        final p = converted['part'];
        final rx = converted['x'];
        final ry = converted['y'];
        if (p is String) part = p;
        if (rx is num) x = rx.toDouble();
        if (ry is num) y = ry.toDouble();
      }

      if (part != null && part.isNotEmpty) {
        onBodyPart(part, x, y);
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
