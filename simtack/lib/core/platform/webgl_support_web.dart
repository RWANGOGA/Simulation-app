import 'package:web/web.dart' as web;

/// Cached result: the answer cannot change within a page's lifetime, and each
/// probe creates a canvas and asks the browser for a context.
bool? _supported;

/// Whether a WebGL context can be created here.
///
/// This asks the browser directly — a detached canvas, then `getContext` for
/// `webgl2` and `webgl`. It is the question `<model-viewer>` and the Three.js
/// anatomy viewer both need answered *before* they mount, because a renderer
/// that cannot get a context throws inside its own constructor: `model-viewer`
/// then removes its element and leaves an empty box, and the platform view
/// Flutter was managing goes with it. Nothing catches that after the fact, so
/// it has to be avoided beforehand.
///
/// A hard `false` is a real state, not a theoretical one: a browser with
/// hardware acceleration off, a driver blocklist, or a sandboxed GPU process
/// reports `GL_VENDOR = Disabled` and fails every attempt.
bool detectWebglSupport() {
  final cached = _supported;
  if (cached != null) return cached;

  var supported = false;
  try {
    final canvas = web.HTMLCanvasElement();
    // `webgl2` first: a context that answers for webgl2 supports both, and
    // asking for it avoids handing back a legacy context.
    supported = canvas.getContext('webgl2') != null ||
        canvas.getContext('webgl') != null;
  } catch (_) {
    // Some browsers throw from `getContext` rather than returning null when
    // the GPU process is unavailable.
    supported = false;
  }
  return _supported = supported;
}
