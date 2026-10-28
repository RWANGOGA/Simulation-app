/// Whether a WebGL context can be created here.
///
/// Off the web there is no cheap synchronous probe: `model_viewer_plus` builds
/// a native `WebView` and only fails once that WebView is already on screen.
/// Reporting `true` keeps the renderer those screens already had, so this file
/// takes nothing away on Android or iOS — it only adds the guard where the
/// question can actually be answered.
///
/// On the web the real check lives in `webgl_support_web.dart`, which is the
/// implementation this file is replaced by. See `webgl_support.dart`.
bool detectWebglSupport() => true;
