import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_page_route.dart';
import 'dashboard_shared.dart';
import 'triage_decision_screen.dart';

class ShapExplanationScreen extends StatelessWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> allSessions;

  const ShapExplanationScreen({super.key, required this.session, required this.allSessions});

  @override
  Widget build(BuildContext context) {
    final score = (session['risk_score'] as num?)?.toDouble();
    final level = riskLevel(score);
    final color = riskColor(level);

    List<Map<String, dynamic>> factors = [];
    final raw = session['shap_explanation'] as String?;
    if (raw != null && raw.isNotEmpty) {
      try {
        factors = (jsonDecode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
        factors.sort((a, b) => ((b['shap'] as num?) ?? 0).compareTo((a['shap'] as num?) ?? 0));
      } catch (_) {}
    }
    final maxShap = factors.isEmpty
        ? 1.0
        : factors.map((f) => ((f['shap'] as num?) ?? 0).toDouble()).reduce((a, b) => a > b ? a : b);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
        title: const Text('SHAP Explanation', style: TextStyle(fontWeight: FontWeight.bold)),
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
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('4. TRIAGE DATA & SHAP EXPLANATION', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DashboardPalette.primary, letterSpacing: 0.5)),
                        const SizedBox(height: 20),
                        const Text('Triage Risk Score', style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                        Text(score?.toStringAsFixed(2) ?? '--', style: TextStyle(fontSize: 36, fontWeight: FontWeight.bold, color: color)),
                        Text('${riskTitleCase(level)} Risk', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
                        const SizedBox(height: 24),
                        const Text('Top Factors Contributing', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B))),
                        const SizedBox(height: 12),
                        if (factors.isEmpty)
                          const Text('No factor breakdown available.', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)))
                        else
                          ...factors.map((factor) {
                            final label = factor['factor'] as String? ?? '';
                            final shap = (factor['shap'] as num?)?.toDouble() ?? 0.0;
                            final isConnection = label.startsWith('Connected to reported');
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                children: [
                                  Expanded(
                                    flex: 3,
                                    child: Text(
                                      label,
                                      style: TextStyle(fontSize: 12.5, color: isConnection ? DashboardPalette.primary : const Color(0xFF475569), fontWeight: isConnection ? FontWeight.w600 : FontWeight.normal),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: ClipRRect(
                                      borderRadius: BorderRadius.circular(4),
                                      child: LinearProgressIndicator(
                                        value: (shap / maxShap).clamp(0.0, 1.0),
                                        minHeight: 8,
                                        backgroundColor: const Color(0xFFF1F5F9),
                                        valueColor: AlwaysStoppedAnimation(isConnection ? DashboardPalette.primary : const Color(0xFF94A3B8)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  SizedBox(width: 36, child: Text(shap.toStringAsFixed(2), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF334155)))),
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  DashboardNextButton(
                    label: 'Next: Triage Decision',
                    onPressed: () {
                      Navigator.of(context).push(
                        AppPageRoute(builder: (_) => TriageDecisionScreen(session: session, allSessions: allSessions)),
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
