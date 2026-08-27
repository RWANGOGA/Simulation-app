import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html; // For web downloads
import '../../../core/network/api_client.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// --- CONFIGURATION ---
const String kReportBaseUrl = 'http://10.16.10.85:5000'; 

class SuccessScreen extends StatefulWidget {
  final String patientId;
  final TriageResult triageResult;

  const SuccessScreen({
    super.key,
    required this.patientId,
    required this.triageResult,
  });

  @override
  State<SuccessScreen> createState() => _SuccessScreenState();
}

class _SuccessScreenState extends State<SuccessScreen> {
  final GlobalKey _qrKey = GlobalKey();
  bool _isProcessing = false;

  String get _reportUrl => '$kReportBaseUrl/#/report/${widget.patientId}';

  Future<void> _captureAndShare({required bool isSave}) async {
    setState(() => _isProcessing = true);
    
    try {
      // Capture the QR Widget as an image
      RenderRepaintBoundary boundary = _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 3.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      Uint8List? imageBytes = byteData?.buffer.asUint8List();

      if (imageBytes == null) throw Exception('Could not capture image');

      if (isSave) {
        // SAVE LOGIC: Different for Web vs Mobile
        if (kIsWeb) {
          // Web: Trigger browser download
          final blob = html.Blob([imageBytes], 'image/png');
          final url = html.Url.createObjectUrlFromBlob(blob);
          final anchor = html.AnchorElement(href: url)
            ..setAttribute('download', '${widget.patientId}_QR.png')
            ..click();
          html.Url.revokeObjectUrl(url);
        } else {
          // Mobile: Use share_plus to save
          await Share.shareXFiles(
            [XFile.fromData(imageBytes, name: '${widget.patientId}_QR.png', mimeType: 'image/png')],
            subject: 'Patient QR Code - ${widget.patientId}',
          );
        }
      } else {
        // SHARE LOGIC: Share the URL link
        await Share.share(
          'Clinical Report for Patient ${widget.patientId}:\n$_reportUrl',
          subject: 'AtomyBridge Clinical Report',
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'), 
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
        print('DEBUG ERROR: $e'); // Print to console for debugging
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final riskScore = widget.triageResult.riskScore;
    final hasScore = riskScore != null;
    final isHighRisk = hasScore && riskScore >= 0.7;
    final riskColor = isHighRisk ? const Color(0xFFDC2626) : const Color(0xFF16A34A);
    final riskLabel = hasScore
        ? '${widget.triageResult.riskLevel} Risk (${(riskScore * 100).toInt()}%)'
        : 'Risk Assessment Pending';

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Success Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle, color: Color(0xFF16A34A), size: 48),
              ),

              const SizedBox(height: 16),

              const Text(
                'Report Submitted!',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
              ),

              const SizedBox(height: 24),

              // Patient ID & Timestamp Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFE2E8F0)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Patient ID', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        Text(widget.patientId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ],
                    ),
                    Column(crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('Timestamp', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        Text(DateTime.now().toString().substring(0, 16), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF475569))),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // QR CODE SECTION
              RepaintBoundary(
                key: _qrKey,
                child: Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFF6D28D9), width: 2),
                    boxShadow: [BoxShadow(color: const Color(0xFF6D28D9).withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))],
                  ),
                  child: Column(
                    children: [
                      const Text('Encrypted QR Passport', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9), letterSpacing: 1)),
                      const SizedBox(height: 12),
                      QrImageView(
                        data: _reportUrl, 
                        version: QrVersions.auto,
                        size: 180.0,
                        backgroundColor: Colors.white,
                      ),
                      const SizedBox(height: 12),
                      const Text('No internet required to view', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                      const Text('Show this QR code to the health worker', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                    ],
                  ),
                ),
              ),

              const Spacer(),

              // Risk Summary
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: riskColor.withOpacity(0.1), borderRadius: BorderRadius.circular(8)),
                child: Row(
                  children: [
                    Icon(isHighRisk ? Icons.warning_amber_rounded : Icons.check_circle_outline, color: riskColor, size: 20),
                    const SizedBox(width: 8),
                    Text('AI Assessment: $riskLabel', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: riskColor)),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // SAVE & SHARE BUTTONS
              Row(
                children: [
                  // SAVE BUTTON
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: _isProcessing ? null : () => _captureAndShare(isSave: true),
                      icon: _isProcessing 
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) 
                        : const Icon(Icons.download, size: 20),
                      label: const Text('Save', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6D28D9),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  // SHARE BUTTON
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isProcessing ? null : () => _captureAndShare(isSave: false),
                      icon: const Icon(Icons.share, size: 20),
                      label: const Text('Share', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF6D28D9),
                        side: const BorderSide(color: Color(0xFF6D28D9), width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),
              
              const SizedBox(height: 20),

              // Return Home Text Button
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Start New Triage', style: TextStyle(color: Color(0xFF64748B), fontSize: 14)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}