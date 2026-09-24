// Non-web stub — see anatomy3d_platform_view_web.dart. Mobile 3D support
// (via webview_flutter loading the same web/anatomy3d/viewer.html as a
// local asset) is follow-up work; on non-web platforms today
// Anatomy3DTapView shows a "not available on this platform yet" message
// instead of calling this.
String registerAnatomy3DPlatformView(String viewType, String src) => viewType;

Object? anatomy3DIframeFor(String viewType) => null;
