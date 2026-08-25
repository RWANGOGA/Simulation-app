import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_page_route.dart';
import '../../success/ui/success_screen.dart' show kReportBaseUrl;
import 'body_map_timeline_screen.dart';
import 'dashboard_shared.dart';

class PatientOverviewScreen extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> allSessions;

  const PatientOverviewScreen({super.key, required this.session, required this.allSessions});

  @override
  Widget build(BuildContext context) {
    final code = session['anonymous_code'] as String? ?? 'Unknown';
    final level = riskLevel((session['risk_score'] as num?)?.toDouble());
    final color = riskColor(level);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
        title: const Text('Patient Overview', style: TextStyle(fontWeight: FontWeight.bold)),
      ),
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppCard(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      children: [
                        const Text('2. PATIENT OVERVIEW', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DashboardPalette.primary, letterSpacing: 0.5)),
                        const SizedBox(height: 20),
                        Row(
                          children: [
                            const CircleAvatar(
                              radius: 20,
                              backgroundColor: Color(0xFFF1F5F9),
                              child: Icon(Icons.person_outline, color: Color(0xFF64748B), size: 22),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Patient ID', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                                  Text(code, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                                ],
                              ),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: color.withValues(alpha: 0.3)),
                              ),
                              child: Text(riskTitleCase(level), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 12)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 28),
                        QrImageView(
                          data: '$kReportBaseUrl/#/report/$code',
                          size: 200,
                          backgroundColor: Colors.white,
                        ),
                        const SizedBox(height: 14),
                        const Text(
                          "This patient's report QR — scan to open it on another device",
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  DashboardNextButton(
                    label: 'Next: Body Map & Timeline',
                    onPressed: () {
                      Navigator.of(context).push(
                        AppPageRoute(
                          builder: (_) => BodyMapTimelineScreen(session: session, allSessions: allSessions),
                        ),
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
