import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../auth/ui/login_screen.dart';
import '../../report/ui/clinical_report_screen.dart';
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

  // Sidebar state
  bool _sidebarExpanded = false;

  // Autocomplete state
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  final GlobalKey _searchFieldKey = GlobalKey();
  List<String> _patientCodeSuggestions = [];
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  // Debounces the patient-code search so we don't hammer the backend
  Timer? _backendDebounce;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _backendDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _removeOverlay();
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
      _updatePatientCodeSuggestions(sessions);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading dashboard: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _updatePatientCodeSuggestions(List<Map<String, dynamic>> sessions) {
    final codes = <String>{};
    for (final s in sessions) {
      final code = s['anonymous_code'];
      if (code is String && code.isNotEmpty) codes.add(code);
    }
    _patientCodeSuggestions = codes.toList()..sort();
  }

  void _filterSessions(String query) {
    setState(() => _searchQuery = query.toUpperCase());
    _backendDebounce?.cancel();
    _backendDebounce = Timer(const Duration(milliseconds: 400), _loadData);
  }

  void _selectPatientCode(String code) {
    _searchController.text = code;
    _filterSessions(code);
    _removeOverlay();
    _searchFocusNode.unfocus();
  }

  void _showOverlay() {
    _removeOverlay();
    if (_patientCodeSuggestions.isEmpty) return;

    final query = _searchController.text.toUpperCase();
    final filtered = query.isEmpty
        ? _patientCodeSuggestions
        : _patientCodeSuggestions.where((c) => c.contains(query)).toList();

    if (filtered.isEmpty) return;

    final renderBox = _searchFieldKey.currentContext?.findRenderObject() as RenderBox?;
    final fieldWidth = renderBox?.size.width ?? 300;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        width: fieldWidth,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 48),
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: filtered.length > 5 ? 5 : filtered.length,
                itemBuilder: (context, index) {
                  final code = filtered[index];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.person_outline, color: Color(0xFF6D28D9), size: 20),
                    title: Text(
                      code,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    onTap: () => _selectPatientCode(code),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
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

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
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

  String _getRiskLevel(double? score) {
    if (score == null) return 'UNKNOWN';
    if (score >= 0.7) return 'HIGH';
    if (score >= 0.4) return 'MEDIUM';
    return 'LOW';
  }

  double? _riskScore(Map<String, dynamic> session) {
    final score = session['risk_score'];
    return score is num ? score.toDouble() : null;
  }

  String _formattedSessionDate(Map<String, dynamic> session) {
    final createdAt = DateTime.tryParse(session['created_at']?.toString() ?? '');
    return createdAt == null ? 'Date unavailable' : DateFormat('MMM dd, HH:mm').format(createdAt);
  }

  Color _getRiskColor(String level) {
    switch (level) {
      case 'HIGH': return const Color(0xFFDC2626);
      case 'MEDIUM': return const Color(0xFFF59E0B);
      case 'LOW': return const Color(0xFF16A34A);
      default: return const Color(0xFF64748B);
    }
  }

  void _toggleSidebar() {
    setState(() => _sidebarExpanded = !_sidebarExpanded);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            _sidebarExpanded ? Icons.menu_open : Icons.menu,
            color: const Color(0xFF6D28D9),
          ),
          tooltip: _sidebarExpanded ? 'Collapse sidebar' : 'Expand sidebar',
          onPressed: _toggleSidebar,
        ),
        title: const Text('Practitioner Dashboard', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF6D28D9)), onPressed: _loadData),
          IconButton(
            icon: const Icon(Icons.logout, color: Color(0xFF6D28D9)),
            tooltip: 'Log out',
            onPressed: _logout,
          ),
        ],
      ),
      body: Row(
        children: [
          // SIDEBAR
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            width: _sidebarExpanded ? 240 : 0,
            child: _sidebarExpanded ? _buildSidebar() : null,
          ),

          // MAIN CONTENT
          Expanded(
            child: _isLoading
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
                              child: CompositedTransformTarget(
                                link: _layerLink,
                                child: TextField(
                                  key: _searchFieldKey,
                                  controller: _searchController,
                                  focusNode: _searchFocusNode,
                                  decoration: InputDecoration(
                                    hintText: 'Search Patient ID (e.g., P-...)',
                                    prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                                    suffixIcon: _searchController.text.isNotEmpty
                                        ? IconButton(
                                            icon: const Icon(Icons.clear, color: Color(0xFF64748B)),
                                            onPressed: () {
                                              _searchController.clear();
                                              _filterSessions('');
                                              _removeOverlay();
                                            },
                                          )
                                        : null,
                                    filled: true,
                                    fillColor: Colors.white,
                                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                                    contentPadding: const EdgeInsets.symmetric(vertical: 0),
                                  ),
                                  onChanged: (value) {
                                    _filterSessions(value);
                                    if (value.isNotEmpty) {
                                      _showOverlay();
                                    } else {
                                      _removeOverlay();
                                    }
                                  },
                                  onTap: () {
                                    if (_searchController.text.isNotEmpty) {
                                      _showOverlay();
                                    }
                                  },
                                  onEditingComplete: () {
                                    _removeOverlay();
                                    _searchFocusNode.unfocus();
                                  },
                                ),
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                              child: DropdownButton<String>(
                                value: _selectedRisk,
                                underline: const SizedBox(),
                                hint: const Icon(Icons.filter_list, color: Color(0xFF64748B)),
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
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                              child: DropdownButton<String>(
                                value: _selectedStatus,
                                underline: const SizedBox(),
                                hint: const Icon(Icons.folder_open, color: Color(0xFF64748B)),
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
                            ? const Center(child: Text('No triage sessions found.', style: TextStyle(color: Color(0xFF64748B))))
                            : ListView.builder(
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                itemCount: _sessions.length,
                                itemBuilder: (context, index) {
                                  final session = _sessions[index];
                                  final riskLevel = _getRiskLevel(_riskScore(session));
                                  final riskColor = _getRiskColor(riskLevel);
                                  final isClosed = session['status'] == 'closed';
                                  final formattedDate = _formattedSessionDate(session);

                                  return Card(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    elevation: 2,
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.all(16),
                                      leading: CircleAvatar(
                                        backgroundColor: riskColor.withValues(alpha: 0.1),
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
                                          Text(formattedDate, style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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
                                              color: isClosed ? const Color(0xFF64748B) : const Color(0xFFF59E0B),
                                            ),
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
                      ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSidebar() {
    final highRisk = _stats?['high_risk'] ?? 0;
    final mediumRisk = _stats?['medium_risk'] ?? 0;
    final lowRisk = _stats?['low_risk'] ?? 0;
    final total = _stats?['total'] ?? 0;

    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(right: BorderSide(color: Color(0xFFE2E8F0), width: 1)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
          // Sidebar Header
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF6D28D9).withValues(alpha: 0.05),
              border: const Border(bottom: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: const Row(
              children: [
                Icon(Icons.dashboard, color: Color(0xFF6D28D9), size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Dashboard',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Quick Stats
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'OVERVIEW',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF64748B),
                    letterSpacing: 1.5,
                  ),
                ),
                const SizedBox(height: 12),
                _sidebarStatRow('Total Patients', total.toString(), const Color(0xFF6D28D9), Icons.people_outline),
                const SizedBox(height: 8),
                _sidebarStatRow('High Risk', highRisk.toString(), const Color(0xFFDC2626), Icons.warning_amber_outlined),
                const SizedBox(height: 8),
                _sidebarStatRow('Medium Risk', mediumRisk.toString(), const Color(0xFFF59E0B), Icons.error_outline),
                const SizedBox(height: 8),
                _sidebarStatRow('Low Risk', lowRisk.toString(), const Color(0xFF16A34A), Icons.check_circle_outline),
              ],
            ),
          ),

          const Divider(color: Color(0xFFE2E8F0)),

          // Recent Patients
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: const Text(
              'RECENT PATIENTS',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: Color(0xFF64748B),
                letterSpacing: 1.5,
              ),
            ),
          ),

          SizedBox(
            height: 300,
            child: _sessions.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: Text(
                        'No patients yet',
                        style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemCount: _sessions.length > 10 ? 10 : _sessions.length,
                    itemBuilder: (context, index) {
                      final session = _sessions[index];
                      final riskLevel = _getRiskLevel(_riskScore(session));
                      final riskColor = _getRiskColor(riskLevel);
                      final code = session['anonymous_code'] ?? 'Unknown';

                      return InkWell(
                        onTap: () async {
                          await Navigator.of(context).push(
                            AppPageRoute(
                              builder: (_) => ClinicalReportScreen(
                                patientId: code,
                                practitionerMode: true,
                              ),
                            ),
                          );
                          _loadData();
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                          child: Row(
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: riskColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      code,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: Color(0xFF1E293B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      session['body_region'] ?? '',
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Color(0xFF64748B),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),

          // Sidebar Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: const BoxDecoration(
              border: Border(top: BorderSide(color: Color(0xFFE2E8F0))),
            ),
            child: Row(
              children: [
                const Icon(Icons.help_outline, size: 16, color: Color(0xFF94A3B8)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_sessions.length} total sessions',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _sidebarStatRow(String label, String value, Color color, IconData icon) {
    return Row(
      children: [
        Icon(icon, size: 18, color: color),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))],
        ),
        child: Column(
          children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 8),
            Text(value, style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: color)),
            Text(label, style: const TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }
}
