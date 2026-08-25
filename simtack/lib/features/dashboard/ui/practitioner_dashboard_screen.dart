import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_card.dart';
import '../../../core/theme/app_page_route.dart';
import '../../auth/ui/login_screen.dart';
import 'dashboard_shared.dart';
import 'patient_overview_screen.dart';

class PractitionerDashboardScreen extends StatefulWidget {
  final Doctor doctor;

  const PractitionerDashboardScreen({super.key, required this.doctor});

  @override
  State<PractitionerDashboardScreen> createState() => _PractitionerDashboardScreenState();
}

class _PractitionerDashboardScreenState extends State<PractitionerDashboardScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String? _selectedRisk;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final stats = await ApiClient.getTriageStats();
      final sessions = await ApiClient.getTriageList(
        patientCode: _searchQuery.isEmpty ? null : _searchQuery,
        riskLevel: _selectedRisk,
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
          SnackBar(content: Text('Error loading dashboard: $e'), backgroundColor: DashboardPalette.danger),
        );
      }
    }
  }

  void _debouncedSearch() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), _loadData);
  }

  void _openSession(Map<String, dynamic> session) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => PatientOverviewScreen(
          session: session,
          allSessions: _sessions,
        ),
      ),
    );
  }

  void _comingSoon(String feature) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$feature — coming soon')));
  }

  Future<void> _logout() async {
    await ApiClient.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F5F9),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildSidebar(),
          Expanded(
            child: Column(
              children: [
                _buildTopBar(),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator())
                      : Align(
                          alignment: Alignment.topCenter,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(20),
                              child: _buildSessionHistoryCard(),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // --- SIDEBAR ---
  Widget _buildSidebar() {
    const items = [
      ('Dashboard', Icons.dashboard_outlined, true),
      ('Patients', Icons.people_outline, false),
      ('Triage Sessions', Icons.assignment_outlined, false),
      ('Risk Scores', Icons.speed_outlined, false),
      ('Explanations', Icons.psychology_outlined, false),
      ('Reports', Icons.description_outlined, false),
      ('Settings', Icons.settings_outlined, false),
      ('Users', Icons.group_outlined, false),
      ('Audit Logs', Icons.history_edu_outlined, false),
    ];

    return Container(
      width: 220,
      color: Colors.white,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 24, 20, 20),
              child: Row(
                children: [
                  const Icon(Icons.medical_services_rounded, color: DashboardPalette.primary, size: 24),
                  const SizedBox(width: 10),
                  Text(
                    'Simtack Triage',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey.shade900),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: items
                    .map((item) => _sidebarTile(
                          item.$1,
                          item.$2,
                          item.$3,
                          () {
                            if (!item.$3) _comingSoon(item.$1);
                          },
                        ))
                    .toList(),
              ),
            ),
            const Divider(height: 1),
            _sidebarTile('Logout', Icons.logout_rounded, false, _logout, color: DashboardPalette.danger),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _sidebarTile(String label, IconData icon, bool active, VoidCallback onTap, {Color? color}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
      child: Material(
        color: active ? DashboardPalette.primary.withValues(alpha: 0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(10),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                Icon(icon, size: 19, color: color ?? (active ? DashboardPalette.primary : const Color(0xFF64748B))),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    color: color ?? (active ? DashboardPalette.primary : const Color(0xFF334155)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // --- TOP BAR ---
  Widget _buildTopBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      child: Row(
        children: [
          const Text('Dashboard', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
          const Spacer(),
          IconButton(
            tooltip: 'Notifications',
            icon: const Icon(Icons.notifications_none_rounded, color: Color(0xFF64748B)),
            onPressed: () => _comingSoon('Notifications'),
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh, color: Color(0xFF64748B)),
            onPressed: _loadData,
          ),
          const SizedBox(width: 8),
          CircleAvatar(
            radius: 16,
            backgroundColor: DashboardPalette.primary,
            child: Text(
              widget.doctor.fullName.isNotEmpty ? widget.doctor.fullName[0].toUpperCase() : 'D',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Text('Dr. ${widget.doctor.fullName}', style: const TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF1E293B))),
          const SizedBox(width: 2),
          const Icon(Icons.expand_more, size: 18, color: Color(0xFF64748B)),
        ],
      ),
    );
  }

  // --- 6. SESSION HISTORY ---
  Widget _buildSessionHistoryCard() {
    return AppCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('6. SESSION HISTORY', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: DashboardPalette.primary, letterSpacing: 0.5)),
          const SizedBox(height: 14),
          if (_stats != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Row(children: [
                _statChip('Total', _stats!['total'].toString(), DashboardPalette.primary),
                const SizedBox(width: 10),
                _statChip('High', _stats!['high_risk'].toString(), DashboardPalette.danger),
                const SizedBox(width: 10),
                _statChip('Low', _stats!['low_risk'].toString(), DashboardPalette.success),
              ]),
            ),
          Row(
            children: [
              Expanded(
                child: TextField(
                  decoration: InputDecoration(
                    hintText: 'Search Patient ID (e.g., P-...)',
                    hintStyle: const TextStyle(fontSize: 13),
                    isDense: true,
                    prefixIcon: const Icon(Icons.search, size: 18, color: Color(0xFF94A3B8)),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    filled: true,
                    fillColor: const Color(0xFFF8FAFC),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  ),
                  onChanged: (value) {
                    _searchQuery = value.toUpperCase();
                    _debouncedSearch();
                  },
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(color: const Color(0xFFF8FAFC), borderRadius: BorderRadius.circular(10)),
                child: DropdownButton<String?>(
                  value: _selectedRisk,
                  underline: const SizedBox(),
                  hint: const Icon(Icons.filter_list, size: 18, color: Color(0xFF94A3B8)),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'HIGH', child: Text('High', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'MEDIUM', child: Text('Med', style: TextStyle(fontSize: 13))),
                    DropdownMenuItem(value: 'LOW', child: Text('Low', style: TextStyle(fontSize: 13))),
                  ],
                  onChanged: (value) {
                    setState(() => _selectedRisk = value);
                    _loadData();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (_sessions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: Text('No sessions found.', style: TextStyle(color: Color(0xFF94A3B8)))),
            )
          else
            ...List.generate(_sessions.length, (index) {
              final s = _sessions[index];
              final level = riskLevel((s['risk_score'] as num?)?.toDouble());
              final color = riskColor(level);
              final date = DateTime.tryParse(s['created_at'] as String? ?? '');
              final status = s['status'] as String? ?? 'Open';
              return Column(
                children: [
                  if (index > 0) const Divider(height: 1),
                  InkWell(
                    onTap: () => _openSession(s),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: color.withValues(alpha: 0.1),
                            child: Icon(Icons.medical_services, color: color, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(s['anonymous_code'] as String? ?? 'Unknown', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5)),
                                const SizedBox(height: 2),
                                Text(
                                  '${s['body_region']} • ${date != null ? DateFormat('dd MMM yyyy, HH:mm').format(date) : '--'}',
                                  style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
                                ),
                              ],
                            ),
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: color.withValues(alpha: 0.3)),
                                ),
                                child: Text(riskTitleCase(level), style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 11)),
                              ),
                              const SizedBox(height: 4),
                              Text(status, style: TextStyle(fontSize: 10.5, color: status == 'Open' ? DashboardPalette.secondary : DashboardPalette.neutral, fontWeight: FontWeight.w600)),
                            ],
                          ),
                          const SizedBox(width: 4),
                          const Icon(Icons.chevron_right, color: Color(0xFFCBD5E1)),
                        ],
                      ),
                    ),
                  ),
                ],
              );
            }),
        ],
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(color: color.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(value, style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 17)),
          Text(label, style: TextStyle(fontSize: 10, color: color)),
        ]),
      ),
    );
  }
}
