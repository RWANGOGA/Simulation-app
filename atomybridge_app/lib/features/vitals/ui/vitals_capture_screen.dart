import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:permission_handler/permission_handler.dart';
import '../core/ppg_processor.dart';
import '../../review/ui/review_screen.dart'; // We'll create this next

class VitalsCaptureScreen extends StatefulWidget {
  final String region;
  final String painType;
  final int severity;
  final String direction;
  final String depth;

  const VitalsCaptureScreen({
    super.key,
    required this.region,
    required this.painType,
    required this.severity,
    required this.direction,
    required this.depth,
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
    _requestCameraPermission();
  }

  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.request();
    setState(() {
      _hasPermission = status.isGranted;
    });
  }

  Future<void> _startMeasurement() async {
    if (!_hasPermission) return;

    final cameras = await availableCameras();
    final backCamera = cameras.firstWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );

    _cameraController = CameraController(
      backCamera,
      ResolutionPreset.medium,
      enableAudio: false,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    await _cameraController!.initialize();
    
    // Start processing frames
    _cameraController!.startImageStream((CameraImage image) {
      if (_ppgProcessor != null) {
        _ppgProcessor!.processFrame(image);
        
        // Update UI with real-time values
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

    // Auto-stop after 10 seconds
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted) {
        _stopMeasurement();
      }
    });
  }

  void _stopMeasurement() {
    _cameraController?.dispose();
    _cameraController = null;
    
    setState(() {
      _isMeasuring = false;
      _statusMessage = 'Measurement complete!';
    });
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
          '4. Vitals Capture (PPG)',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          children: [
            const SizedBox(height: 20),
            
            // The Two Circles with REAL values
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildVitalCircle('SpO2', _currentSpO2 > 0 ? '${_currentSpO2.toInt()}%' : '--', Colors.green, Icons.air),
                _buildVitalCircle('BPM', _currentBPM > 0 ? '${_currentBPM.toInt()}' : '--', const Color(0xFF6D28D9), Icons.favorite),
              ],
            ),
            
            const SizedBox(height: 40),

            // Camera Preview or Placeholder
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
                            Icon(Icons.camera_alt, size: 64, color: Color(0xFF6D28D9)),
                            SizedBox(height: 16),
                            Text(
                              'Camera Preview',
                              style: TextStyle(color: Color(0xFF64748B)),
                            ),
                          ],
                        ),
                      ),
              ),
            ),

            const SizedBox(height: 30),

            // Status Message
            Text(
              _statusMessage,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: _isMeasuring ? const Color(0xFF16A34A) : const Color(0xFF64748B),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Place your finger over the back camera and flash',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
              ),
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
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  _currentBPM > 0 ? 'Next: Review & Submit' : (_isMeasuring ? 'Measuring...' : 'Start Measurement'),
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
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
              Text(
                value,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: color,
                ),
              ),
              Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  void _goToReview() {
    _stopMeasurement();
    
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (_) => ReviewScreen(
          region: widget.region,
          painType: widget.painType,
          severity: widget.severity,
          direction: widget.direction,
          depth: widget.depth,
          heartRate: _currentBPM,
          spo2: _currentSpO2,
        ),
      ),
    );
  }
}