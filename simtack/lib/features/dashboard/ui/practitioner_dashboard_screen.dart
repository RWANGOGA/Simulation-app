import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_header_bar.dart';
import '../../../core/network/api_client.dart';
import '../../report/ui/clinical_report_screen.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
import '../../../core/theme/app_page_route.dart';
import 'qr_scan_screen.dart';
import 'practitioner_sidebar.dart';
import 'patient_overview_pane.dart';
import '../../onboarding/ui/welcome_screen.dart';

class PractitionerDashboardScreen extends StatefulWidget {
  const PractitionerDashboardScreen({super.key});

  @override
  State<PractitionerDashboardScreen> createState() => _PractitionerDashboardScreenState();
}

class _PractitionerDashboardScreenState extends State<PractitionerDashboardScreen> {
  Map<String, dynamic>? _stats;
  List<Map<String, dynamic>> _sessions = [];
  List<Map<String, dynamic>> _recentSessions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _searchQuery = '';
  String? _selectedRisk;
  String? _selectedStatus;
  int _offset = 0;
  static const int _limit = 10;
  bool _hasMore = true;

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
      final recent = await ApiClient.getTriageList(limit: 5, offset: 0);
      final sessions = await ApiClient.getTriageList(
        limit: _limit,
        offset: 0,
        patientCode: _searchQuery.isEmpty ? null : _searchQuery,
        riskLevel: _selectedRisk,
        status: _selectedStatus,
      );
      setState(() {
        _stats = stats;
        _recentSessions = recent;
        _sessions = sessions;
        _offset = sessions.length;
        _hasMore = sessions.length >= _limit;
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

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final moreSessions = await ApiClient.getTriageList(
        limit: _limit,
        offset: _offset,
        patientCode: _searchQuery.isEmpty ? null : _searchQuery,
        riskLevel: _selectedRisk,
        status: _selectedStatus,
      );
      setState(() {
        _sessions.addAll(moreSessions);
        _offset += moreSessions.length;
        _hasMore = moreSessions.length >= _limit;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading more: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _refreshStats() async {
    try {
      final stats = await ApiClient.getTriageStats();
      if (mounted) setState(() => _stats = stats);
    } catch (e) {
      // Silent fail for stats refresh
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

  void _navigateToNewTriage() {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  void _navigateToSessionList() {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const SessionListScreen()),
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
    return PractitionerScaffold(
      currentRoute: '/dashboard',
      contentBuilder: (context, openDrawer) => Column(
        children: [
          AppHeaderBar(
            title: 'Dashboard Overview',
            subtitle: 'Monitor active triage sessions and patient risk levels.',
            onMenuTap: openDrawer,
            actions: [
              AppHeaderIconButton(
                icon: Icons.refresh,
                tooltip: 'Refresh Data',
                onPressed: () async {
                  await _loadData();
                  await _refreshStats();
                },
              ),
              AppHeaderIconButton(
                icon: Icons.tune,
                tooltip: 'Display & accessibility',
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccessibilitySettingsScreen()),
                  );
                },
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: Color(0xFF6D28D9)))
                : _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return RefreshIndicator(
      onRefresh: () async {
        await _loadData();
        await _refreshStats();
      },
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_stats != null)
              Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  _buildStatCard('Total', _stats!['total'].toString(), const Color(0xFF6D28D9), Icons.people),
                  _buildStatCard('High Risk', _stats!['high_risk'].toString(), const Color(0xFFDC2626), Icons.warning),
                  _buildStatCard('Medium Risk', _stats!['medium_risk'].toString(), const Color(0xFFF59E0B), Icons.trending_up),
                  _buildStatCard('Low Risk', _stats!['low_risk'].toString(), const Color(0xFF16A34A), Icons.check_circle),
                ],
              ),

            const SizedBox(height: 24),

            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: [
                _buildActionCard(
                  'Patient Lookup',
                  'Search patients and view history',
                  Icons.person_search,
                  const Color(0xFF6D28D9),
                  () => _navigateToPatientOverview(),
                ),
                _buildActionCard(
                  'New Triage',
                  'Start a new patient triage session',
                  Icons.add_circle_outline,
                  const Color(0xFF16A34A),
                  () => _navigateToNewTriage(),
                ),
              ],
            ),

            const SizedBox(height: 24),

            _buildRecentSessionsSection(),

            const SizedBox(height: 24),

            // Wrap, not Row: the search field + QR button + two dropdown
            // filters have a combined minimum width that can exceed a
            // narrow window on its own, before the sidebar even takes its
            // share — a plain Row can't shrink the fixed-width filters,
            // so it overflows outright rather than squeezing gracefully.
            Wrap(
              spacing: 12,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 260,
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
                      _searchDebounce = Timer(const Duration(milliseconds: 400), () {
                        _loadData();
                      });
                    },
                  ),
                ),
                if (!kIsWeb)
                  IconButton.filled(
                    tooltip: 'Scan patient QR',
                    style: IconButton.styleFrom(
                      backgroundColor: const Color(0xFF6D28D9),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: const Icon(Icons.qr_code_scanner),
                    onPressed: _scanQr,
                  ),
                _buildDropdownFilter(_selectedRisk, Icons.filter_list, ['All', 'High', 'Med', 'Low'], (value) {
                  setState(() => _selectedRisk = value == 'All' ? null : value);
                  _loadData();
                }),
                _buildDropdownFilter(_selectedStatus, Icons.folder_open, ['Any', 'Open', 'Closed'], (value) {
                  setState(() => _selectedStatus = value == 'Any' ? null : value?.toLowerCase());
                  _loadData();
                }),
              ],
            ),

            const SizedBox(height: 24),

            Row(
              children: [
                Text('Triage Sessions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                const Spacer(),
                TextButton(
                  onPressed: _navigateToSessionList,
                  child: const Text('View All', style: TextStyle(fontSize: 14, color: Color(0xFF6D28D9), fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 16),

            if (_sessions.isEmpty)
              Center(
                child: Padding(
                  padding: const EdgeInsets.all(40),
                  child: Column(
                    children: [
                      Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          color: const Color(0xFF6D28D9).withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.inbox_outlined, size: 32, color: Color(0xFF6D28D9)),
                      ),
                      const SizedBox(height: 16),
                      Text('No triage sessions found.', style: TextStyle(color: AppPalette.textMuted(context))),
                    ],
                  ),
                ),
              )
            else
              _buildSessionList(),

            if (_hasMore && _sessions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Center(
                  child: TextButton.icon(
                    onPressed: _isLoadingMore ? null : _loadMore,
                    icon: _isLoadingMore
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.expand_more),
                    label: Text(_isLoadingMore ? 'Loading...' : 'Load More'),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRecentSessionsSection() {
    if (_recentSessions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Recent Activity', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
            const Spacer(),
            TextButton(
              onPressed: _navigateToSessionList,
              child: const Text('See All', style: TextStyle(fontSize: 14, color: Color(0xFF6D28D9), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppPalette.surface(context),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppPalette.border(context)),
          ),
          child: Column(
            children: _recentSessions.take(5).map((session) => _buildRecentSessionItem(session)).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildRecentSessionItem(Map<String, dynamic> session) {
    final riskLevel = _getRiskLevel(session['risk_score']);
    final riskColor = _getRiskColor(riskLevel);
    final date = DateTime.parse(session['created_at']);
    final formattedDate = DateFormat('MMM dd, HH:mm').format(date);

    return InkWell(
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
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: riskColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(Icons.medical_services, color: riskColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    session['anonymous_code'] ?? 'Unknown',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Color(0xFF1E293B)),
                  ),
                  Text(
                    '${session['body_region']} • ${session['pain_type']}',
                    style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: riskColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(riskLevel, style: TextStyle(fontWeight: FontWeight.bold, color: riskColor, fontSize: 11)),
                ),
                const SizedBox(height: 4),
                Text(formattedDate, style: TextStyle(fontSize: 10, color: AppPalette.textMuted(context))),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionList() {
    return ListView.builder(
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
              backgroundColor: riskColor.withValues(alpha: 0.1),
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
                    color: riskColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: riskColor.withValues(alpha: 0.3)),
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
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    // A fixed minimum width inside a Wrap (see the call site) instead of
    // Expanded inside a Row — on a narrow window the fixed-width sidebar
    // can leave almost no room for 4 Expanded cards, squeezing each one
    // toward zero width and wrapping their text one letter per line. Wrap
    // lets cards that don't fit drop to a new line instead of collapsing.
    return SizedBox(
      width: 180,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [color.withValues(alpha: 0.10), color.withValues(alpha: 0.03)],
          ),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.25)),
          boxShadow: [BoxShadow(color: color.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: color), overflow: TextOverflow.ellipsis),
                  Text(label, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context), fontWeight: FontWeight.w600), overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon, Color color, VoidCallback onTap) {
    // Same fixed-width-inside-Wrap reasoning as _buildStatCard above.
    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppPalette.surface(context),
              borderRadius: BorderRadius.circular(14),
              border: Border(
                left: BorderSide(color: color, width: 4),
                top: BorderSide(color: AppPalette.border(context)),
                right: BorderSide(color: AppPalette.border(context)),
                bottom: BorderSide(color: AppPalette.border(context)),
              ),
              boxShadow: [BoxShadow(color: color.withValues(alpha: 0.10), blurRadius: 10, offset: const Offset(0, 3))],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
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

class SessionListScreen extends StatefulWidget {
  const SessionListScreen({super.key});

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  int _offset = 0;
  String? _selectedRisk;
  String? _selectedStatus;
  static const int _limit = 20;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await ApiClient.getTriageList(
        limit: _limit,
        offset: 0,
        riskLevel: _selectedRisk,
        status: _selectedStatus,
      );
      setState(() {
        _sessions = sessions;
        _offset = sessions.length;
        _hasMore = sessions.length >= _limit;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading sessions: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final more = await ApiClient.getTriageList(
        limit: _limit,
        offset: _offset,
        riskLevel: _selectedRisk,
        status: _selectedStatus,
      );
      setState(() {
        _sessions.addAll(more);
        _offset += more.length;
        _hasMore = more.length >= _limit;
        _isLoadingMore = false;
      });
    } catch (e) {
      setState(() => _isLoadingMore = false);
    }
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
        title: Text('All Triage Sessions', style: TextStyle(color: AppPalette.textPrimary(context), fontWeight: FontWeight.bold)),
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppPalette.textPrimary(context)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.filter_list, color: Color(0xFF6D28D9)),
            onPressed: () => _showFilterSheet(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Color(0xFF6D28D9)))
          : Column(
              children: [
                if (_selectedRisk != null || _selectedStatus != null)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    color: AppPalette.surface(context),
                    child: Row(
                      children: [
                        if (_selectedRisk != null)
                          Chip(
                            label: Text(_selectedRisk!),
                            onDeleted: () {
                              setState(() => _selectedRisk = null);
                              _loadSessions();
                            },
                          ),
                        if (_selectedStatus != null) ...[
                          const SizedBox(width: 8),
                          Chip(
                            label: Text(_selectedStatus!),
                            onDeleted: () {
                              setState(() => _selectedStatus = null);
                              _loadSessions();
                            },
                          ),
                        ],
                        const Spacer(),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _selectedRisk = null;
                              _selectedStatus = null;
                            });
                            _loadSessions();
                          },
                          child: const Text('Clear All'),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _sessions.isEmpty
                      ? Center(child: Text('No sessions found.', style: TextStyle(color: AppPalette.textMuted(context))))
                      : RefreshIndicator(
                          onRefresh: _loadSessions,
                          child: ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _sessions.length + (_hasMore ? 1 : 0),
                            itemBuilder: (context, index) {
                              if (index >= _sessions.length) {
                                return Center(
                                  child: Padding(
                                    padding: const EdgeInsets.all(16),
                                    child: _isLoadingMore
                                        ? const CircularProgressIndicator()
                                        : TextButton(
                                            onPressed: _loadMore,
                                            child: const Text('Load More'),
                                          ),
                                  ),
                                );
                              }

                              final session = _sessions[index];
                              final riskLevel = _getRiskLevel(session['risk_score']);
                              final riskColor = _getRiskColor(riskLevel);
                              final date = DateTime.parse(session['created_at']);
                              final formattedDate = DateFormat('MMM dd, yyyy, HH:mm').format(date);

                              return Card(
                                margin: const EdgeInsets.only(bottom: 12),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.all(16),
                                  leading: CircleAvatar(
                                    backgroundColor: riskColor.withValues(alpha: 0.1),
                                    child: Icon(Icons.medical_services, color: riskColor),
                                  ),
                                  title: Text(
                                    session['anonymous_code'] ?? 'Unknown',
                                    style: const TextStyle(fontWeight: FontWeight.bold),
                                  ),
                                  subtitle: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      const SizedBox(height: 4),
                                      Text('${session['body_region']} • ${session['pain_type']}'),
                                      Text(formattedDate, style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context))),
                                    ],
                                  ),
                                  trailing: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: riskColor.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(riskLevel, style: TextStyle(color: riskColor, fontWeight: FontWeight.bold, fontSize: 11)),
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
                                    _loadSessions();
                                  },
                                ),
                              );
                            },
                          ),
                        ),
                ),
              ],
            ),
    );
  }

  void _showFilterSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.surface(context),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Filter Sessions', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 24),
              const Text('Risk Level', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['All', 'HIGH', 'MEDIUM', 'LOW'].map((level) {
                  final isSelected = _selectedRisk == level || (_selectedRisk == null && level == 'All');
                  return ChoiceChip(
                    label: Text(level),
                    selected: isSelected,
                    onSelected: (selected) {
                      setSheetState(() => _selectedRisk = level == 'All' ? null : level);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              const Text('Status', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: ['Any', 'open', 'closed'].map((status) {
                  final isSelected = _selectedStatus == status || (_selectedStatus == null && status == 'Any');
                  return ChoiceChip(
                    label: Text(status),
                    selected: isSelected,
                    onSelected: (selected) {
                      setSheetState(() => _selectedStatus = status == 'Any' ? null : status);
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {});
                    Navigator.pop(context);
                    _loadSessions();
                  },
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6D28D9)),
                  child: const Text('Apply Filters'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
