import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Full-screen camera scanner for the patient's QR clinical passport
/// (blueprint section 2 — "Point camera to scan the patient's QR code").
///
/// The patient app encodes a deep link ("<base>/#/report/P-XXXX") into the
/// QR, so all this screen has to do is find the anonymous patient code
/// inside whatever string the camera decodes, then pop with that code.
class QrScanScreen extends StatefulWidget {
  const QrScanScreen({super.key});

  /// Extracts the patient anonymous code from any payload shape the app
  /// might produce:
  ///   * deep-link URL -> "https://rwangoga.github.io/Simulation-app/#/report/P-770043"
  ///   * localhost URL -> "http://localhost:5000/#/report/P-770043"
  ///   * plain code    -> "P-770043"
  /// Returns null when the payload contains no code (wrong QR).
  static String? extractPatientCode(String payload) {
    // Codes are generated as "P-" + uppercase Base36, so a single regex
    // covers every format above without URL parsing.
    final match = RegExp(r'P-[A-Z0-9]{4,}').firstMatch(payload);
    return match?.group(0);
  }

  @override
  State<QrScanScreen> createState() => _QrScanScreenState();
}

class _QrScanScreenState extends State<QrScanScreen> {
  final MobileScannerController _controller = MobileScannerController();

  // The camera fires a detection callback for every frame; without this
  // guard we would pop the route several times over.
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null || raw.isEmpty) continue;
      final code = QrScanScreen.extractPatientCode(raw);
      if (code == null) continue; // right QR family only — ignore other codes
      _handled = true;
      _controller.stop();
      Navigator.of(context).pop(code);
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text('Scan Patient QR', style: TextStyle(color: Colors.white)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on, color: Colors.white),
            tooltip: 'Toggle torch',
            onPressed: () => _controller.toggleTorch(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
            errorBuilder: (context, error, child) {
              // Permission denied / no camera — say why instead of a blank screen.
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    error.errorCode == MobileScannerErrorCode.permissionDenied
                        ? 'Camera permission denied. Allow camera access in system settings to scan patient QR codes.'
                        : 'Could not start the camera (${error.errorCode}).',
                    style: const TextStyle(color: Colors.white),
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            },
          ),
          // Viewfinder frame + hint, purely visual guidance.
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFF6D28D9), width: 3),
              ),
            ),
          ),
          const Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: const Text(
              'Point the camera at the patient\'s QR passport',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
          ),
        ],
      ),
    );
  }
}
