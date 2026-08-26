import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../auth/ui/login_screen.dart';
import '../../report/ui/clinical_report_screen.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
import '../../../core/theme/app_page_route.dart';
import 'qr_scan_screen.dart';
import 'practitioner_sidebar.dart';
import 'patient_overview_pane.dart';

class PractitionerDashboardScreen extends StatefulWidget {
  const PractitionerDashboardScreen({super.key});

  @override
  State<PractitionerDashboardScreen> createState() => _PractitionerDashboardScreenState();
}

class _PractitionerDashboardScreenState extends State<PractitionerDashboardScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedRisk;
  String? _selectedStatus;

  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await ApiClient.getTriageStats();
      final sessions = await ApiClient.getTriageList(
        patientCode: _searchQuery.isEmpty ? null : _searchQuery,
        riskLevel: _selectedRisk,
        status: _selectedStatus,
      );
      setState(() {
        _stats = stats;
        _sessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading dashboard: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  String? _demoLine(Map<String, dynamic> session) {
    final age = session['patient_age'];
    final gender = session['patient_gender'];
    final parts = <String>[
      if (age != null) '$age yrs',
      if (gender is String && gender.isNotEmpty) gender,
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }

  Future<void> _scanQr() async {
    final code = await Navigator.of(context).push(
      AppPageRoute(builder: (_) => const QrScanScreen()),
    ) as String?;
    if (code == null || !mounted) return;
    await Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ClinicalReportScreen(patientId: code, practitionerMode: true),
      ),
    );
    _loadData();
  }

  void _navigateToPatientOverview() {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const PatientOverviewScreen()),
    );
  }

  String _getRiskLevel(double? score) {
    if (score == null) return 'UNKNOWN';
    if (score >= 0.7) return 'HIGH';
    if (score >= 0.4) return 'MEDIUM';
    return 'LOW';
  }

  Color _getRiskColor(String level) {
    switch (level) {
      case 'HIGH': return const Color(0xFFDC2626);
      case 'MEDIUM': return const Color(0xFFF59E0B);
      case 'LOW': return const Color(0xFF16A34A);
      default: return AppPalette.textMuted(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      body: Row(
        children: [
          const PractitionerSidebar(currentRoute: '/dashboard'),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppPalette.surface(context),
                    border: Border(bottom: BorderSide(color: AppPalette.border(context))),
                  ),
                  child: Row(
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Dashboard Overview',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.bold,
                              color: AppPalette.textPrimary(context),
                            ),
                          ),
                          Text(
                            'Monitor active triage sessions and patient risk levels.',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppPalette.textMuted(context),
                            ),
                          ),
                        ],
                      ),
                      const Spacer(),
                      IconButton(
                        icon: const Icon(Icons.refresh, color: Color(0xFF6D28D9)),
                        tooltip: 'Refresh Data',
                        onPressed: _loadData,
                      ),
                      const SizedBox(width: 8),
                      IconButton(
                        icon: const Icon(Icons.tune, color: Color(0xFF6D28D9)),
                        tooltip: 'Display & accessibility',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AccessibilitySettingsScreen()),
                          );
                        },
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF6D28D9)))
                      : _buildMainContent(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_stats != null)
            Row(
              children: [
                _buildStatCard('Total', _stats!['total'].toString(), const Color(0xFF6D28D9), Icons.people),
                const SizedBox(width: 16),
                _buildStatCard('High Risk', _stats!['high_risk'].toString(), const Color(0xFFDC2626), Icons.warning),
                const SizedBox(width: 16),
                _buildStatCard('Low Risk', _stats!['low_risk'].toString(), const Color(0xFF16A34A), Icons.check_circle),
              ],
            ),

          const SizedBox(height: 24),

          Row(
            children: [
              _buildActionCard(
                'Patient Lookup',
                'Search patients and view history',
                Icons.person_search,
                const Color(0xFF6D28D9),
                () => _navigateToPatientOverview(),
              ),
              const SizedBox(width: 16),
              _buildActionCard(
                'New Triage',
                'Start a new patient triage session',
                Icons.add_circle_outline,
                const Color(0xFF16A34A),
                () {},
              ),
            ],
          ),

          const SizedBox(height: 24),

          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search Patient ID (e.g., P-...)',
                    prefixIcon: Icon(Icons.search, color: AppPalette.textMuted(context)),
                    filled: true,
                    fillColor: AppPalette.inputFill(context),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  ),
                  onChanged: (value) {
                    setState(() => _searchQuery = value.toUpperCase());
                    _searchDebounce?.cancel();
                    _searchDebounce = Timer(const Duration(milliseconds: 400), _loadData);
                  },
                ),
              ),
              if (!kIsWeb)
                Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: IconButton.filled(
                    tooltip: 'Scan patient QR',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF6D28D9),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanQr,
                  ),
                ),
              const SizedBox(width: 12),
              _buildDropdownFilter(_selectedRisk, Icons.filter_list, ['All', 'High', 'Med', 'Low'], (value) {
                setState(() => _selectedRisk = value == 'All' ? null : value);
                _loadData();
              }),
              const SizedBox(width: 12),
              _buildDropdownFilter(_selectedStatus, Icons.folder_open, ['Any', 'Open', 'Closed'], (value) {
                setState(() => _selectedStatus = value == 'Any' ? null : value?.toLowerCase());
                _loadData();
              }),
            ],
          ),

          const SizedBox(height: 24),

          const Row(
            children: [
              Text('Active Triage Queue', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Spacer(),
              Text('View All', style: TextStyle(fontSize: 14, color: Color(0xFF6D28D9), fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 16),

          if (_sessions.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(40),
                child: Text('No triage sessions found.', style: TextStyle(color: AppPalette.textMuted(context))),
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _sessions.length,
              itemBuilder: (context, index) {
                final session = _sessions[index];
                final riskLevel = _getRiskLevel(session['risk_score']);
                final riskColor = _getRiskColor(riskLevel);
                final isClosed = session['status'] == 'closed';
                final date = DateTime.parse(session['created_at']);
                final formattedDate = DateFormat('MMM dd, HH:mm').format(date);

                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  elevation: 1,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  color: AppPalette.surface(context),
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: CircleAvatar(
                      backgroundColor: riskColor.withOpacity(0.1),
                      child: Icon(Icons.medical_services, color: riskColor, size: 24),
                    ),
                    title: Text(
                      session['anonymous_code'] ?? 'Unknown ID',
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 4),
                        Text('${session['body_region']} • ${session['pain_type']} (${session['severity']}/10)', 
                             style: TextStyle(color: AppPalette.textSecondary(context))),
                        if (_demoLine(session) != null) ...[
                          const SizedBox(height: 4),
                          Text(_demoLine(session)!, style: const TextStyle(fontSize: 12, color: Color(0xFF6D28D9), fontWeight: FontWeight.w600)),
                        ],
                        const SizedBox(height: 4),
                        Text(formattedDate, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                      ],
                    ),
                    trailing: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: riskColor.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: riskColor.withOpacity(0.3)),
                          ),
                          child: Text(riskLevel, style: TextStyle(fontWeight: FontWeight.bold, color: riskColor, fontSize: 12)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          isClosed ? 'Closed' : 'Open',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isClosed ? AppPalette.textMuted(context) : const Color(0xFFF59E0B)),
                        ),
                      ],
                    ),
                    onTap: () async {
                      await Navigator.of(context).push(
                        AppPageRoute(
                          builder: (_) => ClinicalReportScreen(
                            patientId: session['anonymous_code'],
                            practitionerMode: true,
                          ),
                        ),
                      );
                      _loadData();
                    },
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: AppPalette.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.border(context)),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color)),
                Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context), fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surface(context),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppPalette.border(context)),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 8, offset: const Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
                  child: Icon(icon, color: color, size: 24),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                      const SizedBox(height: 4),
                      Text(subtitle, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios, size: 14, color: AppPalette.textMuted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownFilter(String? currentValue, IconData icon, List<String> items, void Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(12), border: Border.all(color: AppPalette.border(context))),
      child: DropdownButton<String>(
        value: items.contains(currentValue) ? currentValue : null,
        underline: const SizedBox(),
        icon: Icon(icon, color: AppPalette.textMuted(context), size: 20),
        items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
