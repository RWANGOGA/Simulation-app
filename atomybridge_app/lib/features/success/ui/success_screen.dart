import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:universal_html/html.dart' as html; // For web downloads
import 'package:url_launcher/url_launcher.dart';
import '../../../core/network/api_client.dart';
import '../../history/ui/patient_history_screen.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;

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
      RenderRepaintBoundary boundary =
          _qrKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
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
          html.AnchorElement(href: url)
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
        // SHARE LOGIC
        if (kIsWeb) {
          // Web has no native share tray on plain HTTP LAN addresses
          // (Web Share API requires HTTPS or localhost). Show our own
          // "choose an app" sheet instead, so the experience still
          // feels like the native share tray.
          if (mounted) await _showWebShareSheet(context);
        } else {
          // Mobile: real native OS share tray, handled entirely by share_plus.
          await Share.share(
            'Clinical Report for Patient ${widget.patientId}:\n$_reportUrl',
            subject: 'AtomyBridge Clinical Report',
          );
        }
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
        debugPrint('DEBUG ERROR: $e');
      }
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // --- WEB SHARE FALLBACK ---
  // A bottom sheet listing common apps, since browsers over plain HTTP
  // can't invoke the OS-level share tray. Each option deep-links out to
  // the relevant app/service using url_launcher.
  Future<void> _showWebShareSheet(BuildContext context) async {
    final message = 'Clinical Report for Patient ${widget.patientId}: $_reportUrl';

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Share Report',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _shareOption(
                      icon: Icons.chat,
                      label: 'WhatsApp',
                      color: const Color(0xFF25D366),
                      onTap: () => _launchAndClose(
                        sheetContext,
                        'https://wa.me/?text=${Uri.encodeComponent(message)}',
                      ),
                    ),
                    _shareOption(
                      icon: Icons.email,
                      label: 'Email',
                      color: const Color(0xFF6D28D9),
                      onTap: () => _launchAndClose(
                        sheetContext,
                        'mailto:?subject=${Uri.encodeComponent('AtomyBridge Clinical Report')}&body=${Uri.encodeComponent(message)}',
                      ),
                    ),
                    _shareOption(
                      icon: Icons.sms,
                      label: 'SMS',
                      color: const Color(0xFF0EA5E9),
                      onTap: () => _launchAndClose(
                        sheetContext,
                        'sms:?body=${Uri.encodeComponent(message)}',
                      ),
                    ),
                    _shareOption(
                      icon: Icons.copy,
                      label: 'Copy Link',
                      color: const Color(0xFF64748B),
                      onTap: () async {
                        await Clipboard.setData(ClipboardData(text: message));
                        if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Link copied to clipboard')),
                          );
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _shareOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(8.0),
        child: Column(
          children: [
            CircleAvatar(
              radius: 26,
              backgroundColor: color.withValues(alpha: 0.1),
              child: Icon(icon, color: color, size: 26),
            ),
            const SizedBox(height: 6),
            Text(label, style: const TextStyle(fontSize: 12, color: Color(0xFF475569))),
          ],
        ),
      ),
    );
  }

  Future<void> _launchAndClose(BuildContext sheetContext, String url) async {
    final uri = Uri.parse(url);
    Navigator.of(sheetContext).pop();
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open: $e'), backgroundColor: Colors.red),
        );
      }
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
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            children: [
              const SizedBox(height: 20),

              // Success Icon
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF16A34A).withValues(alpha: 0.1),
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Patient ID', style: TextStyle(fontSize: 11, color: Color(0xFF64748B))),
                        Text(widget.patientId, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
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
                    boxShadow: [BoxShadow(color: const Color(0xFF6D28D9).withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, 4))],
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

              const SizedBox(height: 24),

              // Risk Summary
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: riskColor.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
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

              const SizedBox(height: 16),

              // --- VIEW MY HISTORY BUTTON ---
              SizedBox(
                width: double.infinity,
                height: 54,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PatientHistoryScreen(patientId: widget.patientId),
                      ),
                    );
                  },
                  icon: const Icon(Icons.history, color: Color(0xFF6D28D9), size: 22),
                  label: const Text(
                    'View My Triage History',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF6D28D9)),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0xFF6D28D9), width: 2),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // --- START NEW TRIAGE ---
              TextButton(
                onPressed: () => Navigator.of(context).popUntil((route) => route.isFirst),
                child: const Text('Start New Triage', style: TextStyle(color: Color(0xFF64748B), fontSize: 14, fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}