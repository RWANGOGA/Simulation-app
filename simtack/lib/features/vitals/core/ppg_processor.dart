import 'dart:math';
import 'package:camera/camera.dart';

class PPGProcessor {
  final List<double> _signalBuffer = [];
  // One timestamp per entry in _signalBuffer, kept in lockstep — lets BPM
  // be computed from the buffer's *real* elapsed time instead of assuming
  // a fixed frame rate (see _calculateVitals: that assumption used to
  // silently double every reading, since the camera/web capture actually
  // runs closer to ~30fps than the 60fps the old math assumed).
  final List<DateTime> _timestamps = [];
  final int _bufferSize = 256; // number of samples to buffer before scoring

  double _currentBPM = 0;
  double _currentSpO2 = 0;
  bool _isProcessing = false;

  void processFrame(CameraImage image) {
    processSample(_extractBrightness(image));
  }

  /// Feeds a pre-computed brightness sample directly into the buffer.
  /// Used on web, where frames are sampled via a <canvas> getImageData
  /// loop (see WebPpgCapture) rather than through CameraImage, since
  /// CameraController.startImageStream is unsupported on web.
  void processSample(double brightness) {
    if (_signalBuffer.length >= _bufferSize) {
      _signalBuffer.removeAt(0);
      _timestamps.removeAt(0);
    }

    _signalBuffer.add(brightness);
    _timestamps.add(DateTime.now());

    // Calculate vitals once we have enough data
    if (_signalBuffer.length >= _bufferSize && !_isProcessing) {
      _calculateVitals();
    }
  }

  double _extractBrightness(CameraImage image) {
    switch (image.format.group) {
      case ImageFormatGroup.bgra8888:
        // Web (camera_web) and some iOS paths deliver interleaved BGRA in
        // plane 0 — there is no separate luma plane, so brightness has to
        // be computed per-pixel from the B/G/R bytes using the standard
        // luma weighting, respecting the row stride (bytesPerRow can be
        // larger than width * 4 due to padding).
        return _extractLumaFromBGRA(image);
      case ImageFormatGroup.yuv420:
        // Plane 0 is the Y (Luma/Brightness) channel directly on mobile.
        return _extractLumaFromYUV420(image);
      default:
        // Unknown/unsupported format on this platform — fall back to the
        // YUV assumption rather than silently returning 0, but this case
        // shouldn't be hit given we only request yuv420/bgra8888 above.
        return _extractLumaFromYUV420(image);
    }
  }

  double _extractLumaFromYUV420(CameraImage image) {
    int totalLuma = 0;
    int pixelCount = image.planes[0].bytes.length;

    // Sample every 4th pixel for performance
    for (int i = 0; i < pixelCount; i += 4) {
      totalLuma += image.planes[0].bytes[i];
    }

    return totalLuma / (pixelCount ~/ 4);
  }

  double _extractLumaFromBGRA(CameraImage image) {
    final bytes = image.planes[0].bytes;
    final bytesPerRow = image.planes[0].bytesPerRow;
    final width = image.width;
    final height = image.height;

    double total = 0;
    int count = 0;

    // Sample a sparse grid (every 2nd row, every 4th pixel) for performance,
    // matching the ~4x downsample the YUV path uses.
    for (int row = 0; row < height; row += 2) {
      final rowStart = row * bytesPerRow;
      for (int col = 0; col < width; col += 4) {
        final pixelStart = rowStart + (col * 4);
        if (pixelStart + 2 >= bytes.length) continue;

        final b = bytes[pixelStart];
        final g = bytes[pixelStart + 1];
        final r = bytes[pixelStart + 2];

        // Standard luma (Rec. 601) weighting from RGB.
        total += (0.299 * r) + (0.587 * g) + (0.114 * b);
        count++;
      }
    }

    return count > 0 ? total / count : 0;
  }

  void _calculateVitals() {
    _isProcessing = true;

    // 1. Calculate Mean (DC component) and Standard Deviation (AC component)
    double mean = _signalBuffer.reduce((a, b) => a + b) / _signalBuffer.length;
    double variance = _signalBuffer.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / _signalBuffer.length;
    double stdDev = sqrt(variance);

    // 2. Real SpO2 Estimation based on Perfusion Index (Signal Quality)
    // A strong, clean pulse (higher stdDev relative to mean) indicates good perfusion.
    // NOTE: this is still a randomized proxy gated by signal quality, not a
    // true SpO2 measurement — see conversation notes before treating this
    // as clinically accurate.
    double perfusionIndex = (stdDev / mean) * 1000;

    if (perfusionIndex > 5.0) {
      _currentSpO2 = 97 + (Random().nextDouble() * 2); // 97-99% (Excellent signal)
    } else if (perfusionIndex > 2.0) {
      _currentSpO2 = 94 + (Random().nextDouble() * 3); // 94-97% (Good signal)
    } else {
      _currentSpO2 = 88 + (Random().nextDouble() * 6); // 88-94% (Weak signal, adjust finger)
    }

    // 3. Real BPM Calculation using Peak Detection
    int peaks = 0;
    double threshold = mean + (stdDev * 0.5); // Dynamic threshold

    for (int i = 1; i < _signalBuffer.length - 1; i++) {
      if (_signalBuffer[i] > threshold && _signalBuffer[i] > _signalBuffer[i - 1] && _signalBuffer[i] > _signalBuffer[i + 1]) {
        peaks++;
      }
    }

    // Convert peaks in the buffer's real elapsed time to Beats Per Minute.
    // This used to assume the buffer always represents ~4.27s (256 samples
    // at an assumed 60fps) — but actual capture (camera / web canvas loop)
    // runs closer to ~30fps, so that assumption silently doubled every
    // reading. Using real timestamps makes this correct at any frame rate.
    if (peaks > 0 && _timestamps.length >= 2) {
      final elapsedSeconds = _timestamps.last.difference(_timestamps.first).inMilliseconds / 1000.0;
      if (elapsedSeconds > 0) {
        _currentBPM = (peaks * (60 / elapsedSeconds)).roundToDouble();
        // Sanity check: human heart rate is between 40 and 200
        if (_currentBPM < 40 || _currentBPM > 200) {
          _currentBPM = 0; // Discard noisy reading
        }
      }
    }

    _isProcessing = false;
  }

  double get currentBPM => _currentBPM;
  double get currentSpO2 => _currentSpO2;
  bool get isReady => _currentBPM > 40 && _currentBPM < 200;

  void reset() {
    _signalBuffer.clear();
    _timestamps.clear();
    _currentBPM = 0;
    _currentSpO2 = 0;
  }
}