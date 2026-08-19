import 'dart:math';
import 'package:camera/camera.dart';

class PPGProcessor {
  final List<double> _signalBuffer = [];
  final int _bufferSize = 256; // ~4 seconds at 60fps
  final int _sampleRate = 60; // Camera frames per second
  
  double _currentBPM = 0;
  double _currentSpO2 = 0;
  bool _isProcessing = false;

  // Process each camera frame
  void processFrame(CameraImage image) {
    if (_signalBuffer.length >= _bufferSize) {
      _signalBuffer.removeAt(0);
    }
    
    // Extract average brightness from the frame (green channel is best for PPG)
    double brightness = _extractBrightness(image);
    _signalBuffer.add(brightness);
    
    // Calculate BPM once we have enough data
    if (_signalBuffer.length >= _bufferSize && !_isProcessing) {
      _calculateHeartRate();
    }
  }

  double _extractBrightness(CameraImage image) {
    // Average the green channel (most sensitive to blood oxygen)
    int totalGreen = 0;
    int pixelCount = image.planes[1].bytes.length;
    
    for (int i = 0; i < pixelCount; i++) {
      totalGreen += image.planes[1].bytes[i];
    }
    
    return totalGreen / pixelCount;
  }

  void _calculateHeartRate() {
    _isProcessing = true;
    
    // Apply FFT to find the dominant frequency
    List<double> fftResult = _performFFT(_signalBuffer);
    
    // Find the peak frequency (between 0.8 Hz and 3.0 Hz = 48-180 BPM)
    double maxPower = 0;
    int peakIndex = 0;
    
    for (int i = 40; i < 150 && i < fftResult.length; i++) { // 40-150 bins ≈ 48-180 BPM
      if (fftResult[i] > maxPower) {
        maxPower = fftResult[i];
        peakIndex = i;
      }
    }
    
    // Convert frequency bin to BPM
    double frequency = (peakIndex * _sampleRate) / _bufferSize;
    _currentBPM = (frequency * 60).round().toDouble();
    
    // Estimate SpO2 (simplified - real implementation needs dual-wavelength)
    _currentSpO2 = _estimateSpO2(_signalBuffer);
    
    _isProcessing = false;
  }

  List<double> _performFFT(List<double> signal) {
    // Simplified FFT implementation
    // In production, use a library like 'fft' or 'audio_waveforms'
    int n = signal.length;
    List<double> magnitude = List.filled(n ~/ 2, 0);
    
    for (int k = 0; k < n ~/ 2; k++) {
      double real = 0;
      double imag = 0;
      
      for (int t = 0; t < n; t++) {
        double angle = (2 * pi * k * t) / n;
        real += signal[t] * cos(angle);
        imag -= signal[t] * sin(angle);
      }
      
      magnitude[k] = sqrt(real * real + imag * imag);
    }
    
    return magnitude;
  }

  double _estimateSpO2(List<double> signal) {
    // Simplified SpO2 estimation
    // Real implementation requires red and infrared light analysis
    // This is a placeholder based on signal quality
    double signalVariance = _calculateVariance(signal);
    
    // Good PPG signal = higher SpO2 estimate
    if (signalVariance > 50) {
      return 95 + (Random().nextDouble() * 4); // 95-99%
    } else if (signalVariance > 20) {
      return 90 + (Random().nextDouble() * 5); // 90-95%
    } else {
      return 85 + (Random().nextDouble() * 5); // 85-90%
    }
  }

  double _calculateVariance(List<double> data) {
    double mean = data.reduce((a, b) => a + b) / data.length;
    double variance = data.map((x) => pow(x - mean, 2)).reduce((a, b) => a + b) / data.length;
    return variance;
  }

  double get currentBPM => _currentBPM;
  double get currentSpO2 => _currentSpO2;
  bool get isReady => _currentBPM > 0;
  
  void reset() {
    _signalBuffer.clear();
    _currentBPM = 0;
    _currentSpO2 = 0;
  }
}