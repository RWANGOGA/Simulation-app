import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_page_route.dart';
import 'dashboard_shared.dart';
import 'shap_explanation_screen.dart';

class BodyMapTimelineScreen extends StatefulWidget {
  final Map<String, dynamic> session;
  final List<Map<String, dynamic>> allSessions;

  const BodyMapTimelineScreen({super.key, required this.session, required this.allSessions});

  @override
  State<BodyMapTimelineScreen> createState() => _BodyMapTimelineScreenState();
}

class _BodyMapTimelineScreenState extends State<BodyMapTimelineScreen> {
  int _tab = 0; // 0 = Current, 1 = Timeline

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final region = session['body_region'] as String?;
    final pos = regionPosition[region] ?? const Offset(0.5, 0.5);
    final level = riskLevel((session['risk_score'] as num?)?.toDouble());
    final dotColor = riskColor(level);
    final createdAt = DateTime.tryParse(session['created_at'] as String? ?? '');

    final patientHistory = widget.allSessions.where((s) => s['anonymous_code'] == session['anonymous_code']).toList()
      ..sort((a, b) => (b['created_at'] as String).compareTo(a['created_at'] as String));

    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
        title: const Text('Body Map & Timeline', style: TextStyle(fontWeight: FontWeight.bold)),
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
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('3. BODY MAP & TIMELINE', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DashboardPalette.primary, letterSpacing: 0.5)),
                        ),
                        const SizedBox(height: 16),
                        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                          _tabChip('Current', 0),
                          const SizedBox(width: 10),
                          _tabChip('Timeline', 1),
                        ]),
                        const SizedBox(height: 20),
                        if (_tab == 0) ...[
                          SizedBox(
                            height: 220,
                            child: LayoutBuilder(builder: (context, constraints) {
                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  const Icon(Icons.accessibility_new, size: 190, color: Color(0xFFCBD5E1)),
                                  Positioned(
                                    left: pos.dx * constraints.maxWidth - 10,
                                    top: pos.dy * constraints.maxHeight - 10,
                                    child: Container(
                                      width: 20,
                                      height: 20,
                                      decoration: BoxDecoration(
                                        color: dotColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(color: Colors.white, width: 3),
                                        boxShadow: [BoxShadow(color: dotColor.withValues(alpha: 0.5), blurRadius: 8)],
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            }),
                          ),
                          const SizedBox(height: 10),
                          Text(region ?? '', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 10),
                          Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                            _legendDot('High', DashboardPalette.danger),
                            const SizedBox(width: 12),
                            _legendDot('Medium', DashboardPalette.warning),
                            const SizedBox(width: 12),
                            _legendDot('Low', DashboardPalette.success),
                          ]),
                          if (createdAt != null) ...[
                            const SizedBox(height: 10),
                            Text(DateFormat('dd MMM yyyy, HH:mm').format(createdAt), style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                          ],
                        ] else ...[
                          if (patientHistory.length <= 1)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 30),
                              child: Text('No other sessions for this patient in the current list.', style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                            )
                          else
                            ...List.generate(patientHistory.length, (i) {
                              final s = patientHistory[i];
                              final sLevel = riskLevel((s['risk_score'] as num?)?.toDouble());
                              final date = DateTime.tryParse(s['created_at'] as String? ?? '');
                              return Column(children: [
                                if (i > 0) const Divider(height: 1),
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Row(children: [
                                    Container(width: 10, height: 10, decoration: BoxDecoration(color: riskColor(sLevel), shape: BoxShape.circle)),
                                    const SizedBox(width: 10),
                                    Expanded(child: Text('${s['body_region']}', style: const TextStyle(fontSize: 13))),
                                    Text(date != null ? DateFormat('dd MMM yyyy').format(date) : '', style: const TextStyle(fontSize: 12, color: Color(0xFF94A3B8))),
                                  ]),
                                ),
                              ]);
                            }),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  DashboardNextButton(
                    label: 'Next: SHAP Explanation',
                    onPressed: () {
                      Navigator.of(context).push(
                        AppPageRoute(builder: (_) => ShapExplanationScreen(session: session, allSessions: widget.allSessions)),
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

  Widget _tabChip(String label, int index) {
    final active = _tab == index;
    return GestureDetector(
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: active ? DashboardPalette.primary.withValues(alpha: 0.1) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: active ? DashboardPalette.primary : const Color(0xFF94A3B8))),
      ),
    );
  }

  Widget _legendDot(String label, Color color) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
      const SizedBox(width: 5),
      Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8))),
    ]);
  }
}
