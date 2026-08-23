import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/ppg_processor.dart';
import '../core/web_ppg_capture.dart';
import '../../body_map/ui/pain_point.dart';
import '../../review/ui/review_screen.dart';
import '../../../core/theme/app_page_route.dart';

class VitalsCaptureScreen extends StatefulWidget {
  // All pain locations the patient marked, each already carrying its own
  // painType/severity/direction/depth from the Pain Details wizard. Vitals
  // (heart rate / signal quality) are captured once per visit and apply
  // to all of them, not per-location.
  final List<PainPoint> painPoints;
  final int patientId;

  const VitalsCaptureScreen({
    super.key,
    required this.painPoints,
    required this.patientId,
  });

  @override
  State<VitalsCaptureScreen> createState() => _VitalsCaptureScreenState();
}

class _VitalsCaptureScreenState extends State<VitalsCaptureScreen> {
  CameraController? _cameraController;
  WebPpgCapture? _webCapture;
  PPGProcessor? _ppgProcessor;
  bool _isMeasuring = false;
  bool _hasPermission = false;
  double _currentBPM = 0;
  double _currentSpO2 = 0;
  String _statusMessage = 'Tap "Start Measurement"';

  @override
  void initState() {
    super.initState();
    _ppgProcessor = PPGProcessor();
    // Web now uses the real camera path too (via camera_web), so we
    // request permission here regardless of platform — the browser's
    // own getUserMedia prompt handles the web case.
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    if (kIsWeb) {
      // permission_handler doesn't back web; the browser's getUserMedia
      // prompt (triggered by CameraController.initialize()) is the real
      // permission gate on web, so just assume granted here and let
      // _startMeasurement's try/catch surface any denial.
      if (mounted) setState(() => _hasPermission = true);
      return;
    }
    var status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _hasPermission = status.isGranted;
      });
    }
  }

  Future<void> _startMeasurement() async {
    if (kIsWeb) {
      await _startWebMeasurement();
      return;
    }
    await _startMobileMeasurement();
  }

  /// Web: CameraController.startImageStream() throws on web (the `camera`
  /// package asserts Android/iOS only), so we bypass it entirely and drive
  /// getUserMedia + canvas frame sampling directly via WebPpgCapture.
  Future<void> _startWebMeasurement() async {
    try {
      _webCapture = WebPpgCapture();
      await _webCapture!.start(
        onSample: (double brightness) {
          if (!mounted) return;
          _ppgProcessor?.processSample(brightness);
          if (_ppgProcessor != null && _ppgProcessor!.isReady) {
            setState(() {
              _currentBPM = _ppgProcessor!.currentBPM;
              _currentSpO2 = _ppgProcessor!.currentSpO2;
              _isMeasuring = true;
              _statusMessage = 'Measuring... Keep finger steady';
            });
          }
        },
      );

      if (mounted) {
        setState(() {
          _isMeasuring = true;
          _statusMessage = 'Measuring... Keep finger steady over the camera';
        });
      }

      // Auto-stop after 15 seconds.
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _isMeasuring) _stopMeasurement();
      });
    } catch (e) {
      await _webCapture?.stop();
      _webCapture = null;
      if (mounted) {
        setState(() {
          _isMeasuring = false;
          _statusMessage =
              'Camera error: $e. Check that camera access is allowed for this site.';
        });
      }
    }
  }

  Future<void> _startMobileMeasurement() async {
    if (!_hasPermission) {
      // Previously this just silently returned, leaving the patient tapping
      // a button that appeared to do nothing. Now we re-request and explain
      // what's needed if it's still denied.
      final status = await Permission.camera.request();
      if (!status.isGranted) {
        if (mounted) {
          setState(() {
            _statusMessage =
                'Camera permission is needed to measure your heart rate. Please allow camera access and try again.';
          });
        }
        return;
      }
      if (mounted) setState(() => _hasPermission = true);
    }

    try {
      final cameras = await availableCameras();
      final backCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        backCamera,
        ResolutionPreset.low, // Low resolution is faster and better for PPG
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.yuv420,
      );

      await _cameraController!.initialize();

      try {
        await _cameraController!.setFlashMode(FlashMode.torch);
      } catch (_) {
        // Some devices don't support torch — non-fatal, measurement can
        // proceed without it.
      }

      if (mounted) {
        setState(() {
          _statusMessage = 'Measuring... Keep finger steady';
        });
      }

      _cameraController!.startImageStream((CameraImage image) {
        // Guard against frames arriving after the widget has been disposed
        // (e.g. the patient backs out mid-measurement) — calling setState
        // on a disposed widget throws.
        if (!mounted) return;
        if (_ppgProcessor != null) {
          _ppgProcessor!.processFrame(image);
          if (_ppgProcessor!.isReady) {
            setState(() {
              _currentBPM = _ppgProcessor!.currentBPM;
              _currentSpO2 = _ppgProcessor!.currentSpO2;
              _isMeasuring = true;
              _statusMessage = 'Measuring... Keep finger steady';
            });
          }
        }
      });

      // Auto-stop after 15 seconds to save battery
      Future.delayed(const Duration(seconds: 15), () {
        if (mounted && _isMeasuring) _stopMeasurement();
      });
    } catch (e) {
      // Previously a mid-setup failure here (e.g. camera initialize()
      // succeeding but setFlashMode or startImageStream throwing) could
      // leave the torch on and the camera resource held indefinitely.
      // Clean up explicitly before surfacing the error.
      try {
        await _cameraController?.setFlashMode(FlashMode.off);
      } catch (_) {
        // Best-effort — controller may already be in a bad state.
      }
      await _cameraController?.dispose();
      _cameraController = null;

      if (mounted) {
        setState(() {
          _isMeasuring = false;
          _statusMessage = 'Camera error: $e';
        });
      }
    }
  }

  void _stopMeasurement() {
    if (kIsWeb) {
      _webCapture?.stop();
      _webCapture = null;
    } else {
      _cameraController?.setFlashMode(FlashMode.off);
      _cameraController?.dispose();
      _cameraController = null;
    }

    if (mounted) {
      setState(() {
        _isMeasuring = false;
        _statusMessage = 'Measurement complete!';
      });
    }
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _webCapture?.stop();
    _ppgProcessor?.reset();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '4. Vitals Capture',
          style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),

            // The Two Circles with REAL calculated values
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildVitalCircle('Signal Quality', _currentSpO2 > 0 ? _signalQualityLabel(_currentSpO2) : '--', Colors.teal, Icons.graphic_eq),
                _buildVitalCircle('BPM', _currentBPM > 0 ? '${_currentBPM.toInt()}' : '--', const Color(0xFF6D28D9), Icons.favorite),
              ],
            ),

            const SizedBox(height: 40),

            // Camera Preview
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: const Color(0xFFF8FAFC),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: kIsWeb
                    ? (_webCapture != null
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: HtmlElementView(viewType: _webCapture!.viewType),
                          )
                        : const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.fingerprint, size: 64, color: Color(0xFF6D28D9)),
                                SizedBox(height: 16),
                                Text('Camera Ready', style: TextStyle(color: Color(0xFF64748B))),
                              ],
                            ),
                          ))
                    : (_cameraController != null && _cameraController!.value.isInitialized
                        ? ClipRRect(
                            borderRadius: BorderRadius.circular(16),
                            child: CameraPreview(_cameraController!),
                          )
                        : const Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.fingerprint, size: 64, color: Color(0xFF6D28D9)),
                                SizedBox(height: 16),
                                Text('Camera Ready', style: TextStyle(color: Color(0xFF64748B))),
                              ],
                            ),
                          )),
              ),
            ),

            const SizedBox(height: 30),

            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _isMeasuring ? const Color(0xFF16A34A) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Place your finger gently over the back camera and flash',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Color(0xFF64748B)),
            ),

            const SizedBox(height: 20),

            // Start/Next Button
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton(
                onPressed: _currentBPM > 0 ? _goToReview : (_isMeasuring ? null : _startMeasurement),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF6D28D9),
                  disabledBackgroundColor: const Color(0xFFCBD5E1),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _currentBPM > 0 ? 'Next: Review & Submit' : (_isMeasuring ? 'Measuring...' : 'Start Measurement'),
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // _currentSpO2 is a perfusion-quality proxy derived from PPG signal
  // strength, not a true pulse-oximetry SpO2 reading (a single RGB camera
  // can't measure blood oxygen without a second/infrared wavelength).
  // Shown as a qualitative signal-quality label so it's never mistaken for
  // a clinical SpO2 percentage.
  String _signalQualityLabel(double proxyValue) {
    if (proxyValue >= 97) return 'Excellent';
    if (proxyValue >= 94) return 'Good';
    return 'Weak';
  }

  Widget _buildVitalCircle(String label, String value, Color color, IconData icon) {
    return Column(
      children: [
        Container(
          width: 120,
          height: 120,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: color, width: 4),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: color, size: 28),
              const SizedBox(height: 8),
              Text(
                value,
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color),
                textAlign: TextAlign.center,
              ),
              Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
            ],
          ),
        ),
      ],
    );
  }

  void _goToReview() {
    _stopMeasurement();
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ReviewScreen(
          painPoints: widget.painPoints,
          heartRate: _currentBPM,
          spo2: _currentSpO2,
          patientId: widget.patientId,
        ),
      ),
    );
  }
}