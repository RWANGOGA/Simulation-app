import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../auth/ui/login_screen.dart';
import '../../report/ui/clinical_report_screen.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
import '../../../core/theme/app_page_route.dart';
import 'qr_scan_screen.dart';

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

  // Debounces the patient-code search so we don't hammer the backend with
  // one request per keystroke.
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

  /// "34 yrs • Male" style summary for a session, or null if the backend
  /// returned no demographics for that patient.
  String? _demoLine(Map<String, dynamic> session) {
    final age = session['patient_age'];
    final gender = session['patient_gender'];
    final parts = <String>[
      if (age != null) '$age yrs',
      if (gender is String && gender.isNotEmpty) gender,
    ];
    return parts.isEmpty ? null : parts.join(' • ');
  }

  /// Signs the practitioner out and returns to the login screen. The token
  /// is wiped first, so even if the user backgrounds the app, main() won't
  /// route them straight back into the dashboard.
  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// Blueprint section 2: point the camera at the patient's QR passport.
  /// The scanner pops with the anonymous code, which opens the same report
  /// screen a manual search would. Web has no camera API in this package,
  /// so there the search field remains the entry point.
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
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        title: Text('Practitioner Dashboard', style: TextStyle(color: AppPalette.textPrimary(context), fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.tune, color: Color(0xFF6D28D9)),
            tooltip: 'Display & accessibility',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccessibilitySettingsScreen()),
              );
            },
          ),
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF6D28D9)), onPressed: _loadData),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF6D28D9)),
            tooltip: 'Log out',
            onPressed: _logout,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // STATISTICS CARDS
                if (_stats != null)
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        _buildStatCard('Total', _stats!['total'].toString(), const Color(0xFF6D28D9), Icons.people),
                        const SizedBox(width: 12),
                        _buildStatCard('High Risk', _stats!['high_risk'].toString(), const Color(0xFFDC2626), Icons.warning),
                        const SizedBox(width: 12),
                        _buildStatCard('Low Risk', _stats!['low_risk'].toString(), const Color(0xFF16A34A), Icons.check_circle),
                      ],
                    ),
                  ),

                // SEARCH & FILTER BAR
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                  child: Row(
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
                      // Camera entry point (blueprint: "Point camera to scan
                      // the patients QR code"). Hidden on web where the
                      // scanner package has no camera backend.
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(12)),
                        child: DropdownButton<String>(
                          value: _selectedRisk,
                          underline: const SizedBox(),
                          hint: Icon(Icons.filter_list, color: AppPalette.textMuted(context)),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('All')),
                            DropdownMenuItem(value: 'HIGH', child: Text('High')),
                            DropdownMenuItem(value: 'MEDIUM', child: Text('Med')),
                            DropdownMenuItem(value: 'LOW', child: Text('Low')),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedRisk = value);
                            _loadData();
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Open/Closed lifecycle filter (blueprint session history).
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(color: AppPalette.surface(context), borderRadius: BorderRadius.circular(12)),
                        child: DropdownButton<String>(
                          value: _selectedStatus,
                          underline: const SizedBox(),
                          hint: Icon(Icons.folder_open, color: AppPalette.textMuted(context)),
                          items: const [
                            DropdownMenuItem(value: null, child: Text('Any')),
                            DropdownMenuItem(value: 'open', child: Text('Open')),
                            DropdownMenuItem(value: 'closed', child: Text('Closed')),
                          ],
                          onChanged: (value) {
                            setState(() => _selectedStatus = value);
                            _loadData();
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // SESSION LIST
                Expanded(
                  child: _sessions.isEmpty
                      ? Center(child: Text('No triage sessions found.', style: TextStyle(color: AppPalette.textMuted(context))))
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
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
                              elevation: 2,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              child: ListTile(
                                contentPadding: const EdgeInsets.all(16),
                                leading: CircleAvatar(
                                  backgroundColor: riskColor.withOpacity(0.1),
                                  child: Icon(Icons.medical_services, color: riskColor, size: 24),
                                ),
                                title: Text(
                                  session['anonymous_code'] ?? 'Unknown ID',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('${session['body_region']} • ${session['pain_type']} (${session['severity']}/10)'),
                                    if (_demoLine(session) != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        _demoLine(session)!,
                                        style: const TextStyle(fontSize: 12, color: Color(0xFF6D28D9), fontWeight: FontWeight.w600),
                                      ),
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
                                      child: Text(
                                        riskLevel,
                                        style: TextStyle(fontWeight: FontWeight.bold, color: riskColor, fontSize: 12),
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      isClosed ? 'Closed' : 'Open',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: isClosed ? AppPalette.textMuted(context) : const Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ],
                                ),
                                onTap: () async {
                                  // Navigate to the detailed report screen we already built!
                                  // practitionerMode adds the Triage Decision card.
                                  await Navigator.of(context).push(
                                    AppPageRoute(
                                      builder: (_) => ClinicalReportScreen(
                                        patientId: session['anonymous_code'],
                                        practitionerMode: true,
                                      ),
                                    ),
                                  );
                                  // A decision may have been saved — refresh chips.
                                  _loadData();
                                },
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppPalette.surface(context),
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}