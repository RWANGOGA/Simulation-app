// Registers the 3D anatomy viewer (a static HTML/Three.js page served from
// web/anatomy3d/, same pattern as web/models/*.glb already used for
// ModelViewer's src) as a Flutter Web platform view, so it can be shown via
// HtmlElementView. Kept in its own conditional-import file because
// dart:ui_web has no counterpart on non-web platforms.
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;

// Tracked per viewType so Anatomy3DTapView can send messages INTO the
// iframe later (e.g. to sync pain-point markers) — the view factory only
// gets called once per platform view, so this is the one place the actual
// iframe element is ever produced.
final Map<String, web.HTMLIFrameElement> anatomy3DIframes = {};

String registerAnatomy3DPlatformView(String viewType, String src) {
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = web.HTMLIFrameElement()
      ..src = src
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'fullscreen';
    anatomy3DIframes[viewType] = iframe;
    return iframe;
  });
  return viewType;
}

web.HTMLIFrameElement? anatomy3DIframeFor(String viewType) =>
    anatomy3DIframes[viewType];
