// ignore_for_file: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;

typedef BodyPartCallback = void Function(String part, double? x, double? y);

class WebInterop {
  static final Map<BodyPartCallback, html.EventListener> _listeners = {};

  static void registerBodyPartListener(BodyPartCallback onBodyPart) {
    void listener(html.Event event) {
      final dynamic rawDetail = js_util.getProperty(event, 'detail');
      if (rawDetail == null) return;

      String? part;
      double? x;
      double? y;

      if (rawDetail is String) {
        part = rawDetail;
      } else {
        final dynamic converted = js_util.dartify(rawDetail);
        if (converted is Map) {
          final p = converted['part'];
          final rx = converted['x'];
          final ry = converted['y'];
          if (p is String) part = p;
          if (rx is num) x = rx.toDouble();
          if (ry is num) y = ry.toDouble();
        }
      }

      if (part != null && part.isNotEmpty) {
        onBodyPart(part, x, y);
      }
    }

    _listeners[onBodyPart] = listener;
    html.window.addEventListener('atomybridge-bodypart', listener);
  }

  static void unregisterBodyPartListener(BodyPartCallback onBodyPart) {
    final listener = _listeners.remove(onBodyPart);
    if (listener != null) {
      html.window.removeEventListener('atomybridge-bodypart', listener);
    }
  }

  static void applyCameraOrbit(String elementId, String orbit) {
    final el = html.document.getElementById(elementId);
    if (el == null) return;
    el.setAttribute('camera-orbit', orbit);
    try {
      js_util.callMethod(el, 'jumpCameraToGoal', []);
    } catch (_) {
      // Ignored if unsupported in older model-viewer builds
    }
  }
}
