import 'dart:async';
import 'dart:js_interop';
import 'dart:ui_web' as ui_web;
import 'package:web/web.dart' as web;

/// Drives the browser camera directly via getUserMedia and samples frames
/// on a timer, since the `camera` package's CameraController.startImageStream
/// throws on web (it asserts Android/iOS only). This bypasses CameraController
/// for frame capture but still gives a live preview via HtmlElementView.
class WebPpgCapture {
  web.MediaStream? _stream;
  web.HTMLVideoElement? _video;
  web.HTMLCanvasElement? _canvas;
  web.CanvasRenderingContext2D? _ctx;
  Timer? _timer;

  final String viewType;
  static int _viewCounter = 0;

  WebPpgCapture() : viewType = 'ppg-video-view-${_viewCounter++}';

  Future<void> start({required void Function(double brightness) onSample}) async {
    final mediaDevices = web.window.navigator.mediaDevices;

    _video = web.HTMLVideoElement()
      ..autoplay = true
      ..muted = true
      ..setAttribute('playsinline', 'true')
      ..style.width = '100%'
      ..style.height = '100%'
      ..style.objectFit = 'cover';

    // Register the raw <video> element so Flutter can embed it via
    // HtmlElementView(viewType: this.viewType) in the widget tree.
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int _) => _video!);

    final constraints = web.MediaStreamConstraints(
      video: {'facingMode': 'environment'}.jsify()!,
      audio: false.toJS,
    );
    _stream = await mediaDevices.getUserMedia(constraints).toDart;
    _video!.srcObject = _stream;

    final metadataLoaded = Completer<void>();
    _video!.onloadedmetadata = (web.Event _) {
      if (!metadataLoaded.isCompleted) metadataLoaded.complete();
    }.toJS;
    await metadataLoaded.future;
    await _video!.play().toDart;

    // Small offscreen canvas — we only need average brightness, not full
    // resolution, so downscaling here keeps per-frame sampling cheap.
    _canvas = web.HTMLCanvasElement()
      ..width = 64
      ..height = 64;
    _ctx = _canvas!.getContext('2d') as web.CanvasRenderingContext2D;

    // ~30fps sampling.
    _timer = Timer.periodic(const Duration(milliseconds: 33), (_) {
      final video = _video;
      final ctx = _ctx;
      if (video == null || ctx == null || video.videoWidth == 0) return;

      ctx.drawImage(video, 0, 0, 64, 64);
      final imageData = ctx.getImageData(0, 0, 64, 64);
      final data = imageData.data.toDart;

      double total = 0;
      int count = 0;
      for (int i = 0; i < data.length; i += 4) {
        final r = data[i];
        final g = data[i + 1];
        final b = data[i + 2];
        total += (0.299 * r) + (0.587 * g) + (0.114 * b);
        count++;
      }

      if (count > 0) onSample(total / count);
    });
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;

    _stream?.getTracks().toDart.forEach((track) => track.stop());
    _stream = null;

    _video?.remove();
    _video = null;
  }
}
