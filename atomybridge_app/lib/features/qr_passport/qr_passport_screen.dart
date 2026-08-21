import 'dart:io';
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';

import '../../core/network/api_client.dart';

class QrPassportScreen extends StatelessWidget {
  final TriageResult result;

  const QrPassportScreen({super.key, required this.result});

  @override
  Widget build(BuildContext context) {
    final screenshotController = ScreenshotController();
    final theme = Theme.of(context);
    final formattedTime = DateFormat('d MMM yyyy, h:mm a').format(result.createdAt!);
    final patientLabel = result.patientId != null ? 'P-${result.patientId}' : 'Not linked';

    return Scaffold(
      appBar: AppBar(title: const Text('QR Clinical Passport')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: Screenshot(
                  controller: screenshotController,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (result.qrData != null)
                          QrImageView(
                            data: result.qrData!,
                            version: QrVersions.auto,
                            size: 220,
                            eyeStyle: const QrEyeStyle(
                              eyeShape: QrEyeShape.square,
                              color: Color(0xFF1E293B),
                            ),
                            dataModuleStyle: const QrDataModuleStyle(
                              dataModuleShape: QrDataModuleShape.square,
                              color: Color(0xFF1E293B),
                            ),
                          )
                        else
                          const SizedBox(
                            height: 220,
                            child: Center(child: Text('QR code unavailable')),
                          ),
                        const SizedBox(height: 24),
                        _InfoRow(label: 'Patient ID', value: patientLabel, theme: theme),
                        const SizedBox(height: 8),
                        _InfoRow(label: 'Triage Time', value: formattedTime, theme: theme),
                        const SizedBox(height: 8),
                        _RiskBadge(riskLevel: result.riskLevel),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.lock_outline, size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Encrypted • No internet required. Show this code to the health worker.',
                      style: theme.textTheme.bodyLarge?.copyWith(fontSize: 13, color: const Color(0xFF64748B)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.save_alt),
                      label: const Text('Save'),
                      onPressed: () => _saveToDevice(context, screenshotController, patientLabel),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.share),
                      label: const Text('Share'),
                      onPressed: () => _share(context, screenshotController, patientLabel),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _saveToDevice(
    BuildContext context,
    ScreenshotController controller,
    String patientLabel,
  ) async {
    final image = await controller.capture();
    if (image == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/passport_$patientLabel.png');
    await file.writeAsBytes(image);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Saved to device')),
      );
    }
  }

  Future<void> _share(
    BuildContext context,
    ScreenshotController controller,
    String patientLabel,
  ) async {
    final image = await controller.capture();
    if (image == null) return;
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/passport_$patientLabel.png');
    await file.writeAsBytes(image);
    await Share.shareXFiles([XFile(file.path)], text: 'My triage QR passport');
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeData theme;

  const _InfoRow({required this.label, required this.value, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label, style: theme.textTheme.bodyLarge?.copyWith(fontSize: 13, color: const Color(0xFF64748B))),
        Text(value, style: theme.textTheme.titleLarge),
      ],
    );
  }
}

class _RiskBadge extends StatelessWidget {
  final String riskLevel;

  const _RiskBadge({required this.riskLevel});

  Color get _color {
    switch (riskLevel) {
      case 'HIGH RISK':
        return const Color(0xFFDC3545); // Danger
      case 'MEDIUM RISK':
        return const Color(0xFFFFC107); // Warning
      default:
        return const Color(0xFF28A745); // Success
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: _color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        riskLevel,
        style: TextStyle(color: _color, fontWeight: FontWeight.w600, fontSize: 13),
      ),
    );
  }
}