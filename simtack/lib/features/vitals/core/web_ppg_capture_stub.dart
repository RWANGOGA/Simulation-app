// Non-web fallback: this class is never actually used on mobile (the
// mobile path in VitalsCaptureScreen uses CameraController directly), but
// the file must exist and compile so the conditional import resolves on
// all platforms.
class WebPpgCapture {
  final String viewType = '';

  Future<void> start({required void Function(double brightness) onSample}) async {
    throw UnsupportedError('WebPpgCapture is only available on web.');
  }

  Future<void> stop() async {}
}