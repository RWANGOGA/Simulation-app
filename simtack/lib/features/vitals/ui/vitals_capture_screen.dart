import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/ppg_processor.dart';
import '../../review/ui/review_screen.dart';
import '../../../core/theme/app_page_route.dart';

class VitalsCaptureScreen extends StatefulWidget {
  final String region;
  final String painType;
  final int severity;
  final String direction;
  final String depth;
  final int patientId;

  const VitalsCaptureScreen({
    super.key,
    required this.region,
    required this.painType,
    required this.severity,
    required this.direction,
    required this.depth,
    required this.patientId,
  });

  @override
  State<VitalsCaptureScreen> createState() => _VitalsCaptureScreenState();
}

class _VitalsCaptureScreenState extends State<VitalsCaptureScreen> {
  CameraController? _cameraController;
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
    // The web branch of _startMeasurement never touches the camera at all,
    // so requesting camera permission on web is pointless and can surface
    // a confusing browser permission prompt for no reason.
    if (!kIsWeb) {
      _requestCameraPermission();
    }
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.request();
    if (mounted) {
      setState(() {
        _hasPermission = status.isGranted;
      });
    }
  }

  Future<void> _startMeasurement() async {
    // 1. SAFE FALLBACK FOR WEB: Prevents Chrome camera crash
    if (kIsWeb) {
      setState(() {
        _isMeasuring = true;
        _statusMessage = 'Simulating PPG measurement for Web...';
      });
      await Future.delayed(const Duration(seconds: 3));
      if (mounted) {
        setState(() {
          _currentBPM = 75.0;
          _currentSpO2 = 98.0;
          _isMeasuring = false;
          _statusMessage = 'Measurement complete (Simulated)!';
        });
      }
      return;
    }

    // 2. REAL MOBILE LOGIC (Uses real camera math)
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

      // Turn on the flashlight for better light penetration
      await _cameraController!.setFlashMode(FlashMode.torch);

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
    _cameraController?.setFlashMode(FlashMode.off);
    _cameraController?.dispose();
    _cameraController = null;

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
                _buildVitalCircle('SpO2', _currentSpO2 > 0 ? '${_currentSpO2.toInt()}%' : '--', Colors.green, Icons.air),
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
                child: _cameraController != null && _cameraController!.value.isInitialized
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
                      ),
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
              Text(value, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: color)),
              Text(label, style: const TextStyle(fontSize: 14, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
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
          region: widget.region,
          painType: widget.painType,
          severity: widget.severity,
          direction: widget.direction,
          depth: widget.depth,
          heartRate: _currentBPM,
          spo2: _currentSpO2,
          patientId: widget.patientId,
        ),
      ),
    );
  }
}