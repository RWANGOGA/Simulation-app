// Registers the 3D anatomy viewer (a static HTML/Three.js page served from
// web/anatomy3d/, same pattern as web/models/*.glb already used for
// ModelViewer's src) as a Flutter Web platform view, so it can be shown via
// HtmlElementView. Kept in its own conditional-import file because
// dart:ui_web has no counterpart on non-web platforms.
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;

String registerAnatomy3DPlatformView(String viewType, String src) {
  ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
    final iframe = web.HTMLIFrameElement()
      ..src = src
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'fullscreen';
    return iframe;
  });
  return viewType;
}
