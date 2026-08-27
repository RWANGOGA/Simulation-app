import 'dart:math';
import 'package:camera/camera.dart';

class PPGProcessor {
  final List<double> _signalBuffer = [];
  // Sliding window of brightness samples. How many real seconds this spans
  // depends on the actual camera frame rate, which is measured from sample
  // timestamps rather than assumed, since actual capture rate varies by
  // device/browser.
  final int _bufferSize = 256;

  // Timestamps of the most recent samples, used to estimate the real fps.
  final List<int> _recentSampleTimesMs = [];
  static const int _timingWindow = 32;

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
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    _recentSampleTimesMs.add(nowMs);
    if (_recentSampleTimesMs.length > _timingWindow) {
      _recentSampleTimesMs.removeAt(0);
    }

    if (_signalBuffer.length >= _bufferSize) {
      _signalBuffer.removeAt(0);
    }

    _signalBuffer.add(brightness);

    // Calculate vitals once we have enough data
    if (_signalBuffer.length >= _bufferSize && !_isProcessing) {
      _calculateVitals();
    }
  }

  /// Real sampling rate in frames per second, measured from the timestamps
  /// of the last [_timingWindow] samples. Returns null until enough timing
  /// data exists (e.g. right after starting the measurement).
  double? get _measuredFps {
    if (_recentSampleTimesMs.length < 8) return null;
    final spanMs = _recentSampleTimesMs.last - _recentSampleTimesMs.first;
    if (spanMs <= 0) return null;
    final fps = (_recentSampleTimesMs.length - 1) * 1000.0 / spanMs;
    // Guard against pathological clock jumps; no camera runs outside this.
    if (fps < 5 || fps > 240) return null;
    return fps;
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

    // 2. SpO2 ESTIMATE from the Perfusion Index (signal quality).
    // A single RGB camera cannot do true pulse-oximetry (that needs a
    // second, infrared wavelength), so this is a deterministic perfusion-
    // based estimate — never a random number, and always labeled as an
    // estimate in the UI.
    double perfusionIndex = (stdDev / mean) * 1000;
    _currentSpO2 = _estimateSpo2(perfusionIndex);

    // 3. BPM via peak detection, using the MEASURED frame rate.
    final fps = _measuredFps;
    if (fps == null) {
      // Not enough timing data yet — skip this round rather than guess.
      _isProcessing = false;
      return;
    }

    int peaks = 0;
    double threshold = mean + (stdDev * 0.5); // Dynamic threshold

    for (int i = 1; i < _signalBuffer.length - 1; i++) {
      if (_signalBuffer[i] > threshold && _signalBuffer[i] > _signalBuffer[i - 1] && _signalBuffer[i] > _signalBuffer[i + 1]) {
        peaks++;
      }
    }

    // The buffer covers bufferSize/fps real seconds; scale the counted
    // peaks in that window up to beats per minute.
    if (peaks > 0) {
      final windowSeconds = _bufferSize / fps;
      _currentBPM = (peaks * 60 / windowSeconds).roundToDouble();
      // Sanity check: human heart rate is between 40 and 200
      if (_currentBPM < 40 || _currentBPM > 200) {
        _currentBPM = 0; // Discard noisy reading
      }
    }

    _isProcessing = false;
  }

  /// Deterministic mapping from perfusion quality to an SpO2 estimate,
  /// smoothed against the previous value so the reading doesn't flicker.
  /// Higher perfusion (stronger pulse signal) => better oxygenation
  /// estimate. Clamped to a physiological 85–100% range.
  double _estimateSpo2(double perfusionIndex) {
    double target;
    if (perfusionIndex > 5.0) {
      target = 98;
    } else if (perfusionIndex > 2.0) {
      target = 96;
    } else {
      target = 92;
    }
    if (_currentSpO2 <= 0) return target;
    final smoothed = _currentSpO2 + (target - _currentSpO2) * 0.4;
    return smoothed.clamp(85.0, 100.0);
  }

  double get currentBPM => _currentBPM;
  double get currentSpO2 => _currentSpO2;
  bool get isReady => _currentBPM > 40 && _currentBPM < 200;

  void reset() {
    _signalBuffer.clear();
    _recentSampleTimesMs.clear();
    _currentBPM = 0;
    _currentSpO2 = 0;
  }
}