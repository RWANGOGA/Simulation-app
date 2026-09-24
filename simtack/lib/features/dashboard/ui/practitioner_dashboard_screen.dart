import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_header_bar.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../report/ui/clinical_report_screen.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
import '../../../core/theme/app_page_route.dart';
import 'qr_scan_screen.dart';
import 'patient_overview_pane.dart';
import 'practitioner_scaffold.dart';
import 'session_list_screen.dart';
import '../../onboarding/ui/welcome_screen.dart';
import '../../patient_info/ui/patient_info_screen.dart';
import '../../auth/ui/login_screen.dart';

class PractitionerDashboardScreen extends StatefulWidget {
  const PractitionerDashboardScreen({super.key});

  @override
  State<PractitionerDashboardScreen> createState() =>
      _PractitionerDashboardScreenState();
}

class _PractitionerDashboardScreenState
    extends State<PractitionerDashboardScreen> {
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
  bool _sidebarExpanded = false;

  // Debounces the patient-code search so we don't hammer the backend with
  // one request per keystroke.
  Timer? _searchDebounce;
  Timer? _backendDebounce;
  TextEditingController? _searchController;
  FocusNode? _searchFocusNode;
  OverlayEntry? _overlayEntry;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocusNode = FocusNode();
    _loadData();
  }

  @override
  void dispose() {
    _backendDebounce?.cancel();
    _searchDebounce?.cancel();
    _searchController?.dispose();
    _searchFocusNode?.dispose();
    _overlayEntry?.remove();
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
      _updatePatientCodeSuggestions(sessions);
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Error loading dashboard: $e'),
              backgroundColor: Colors.red),
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
          SnackBar(
              content: Text('Error loading more: $e'),
              backgroundColor: Colors.red),
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
        builder: (_) =>
            ClinicalReportScreen(patientId: code, practitionerMode: true),
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

  void _navigateToSessionList({String? riskLevel, String? status}) {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => SessionListScreen(
          initialRiskLevel: riskLevel,
          initialStatus: status,
        ),
      ),
    );
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

  String _safeString(dynamic value, {String fallback = 'Unknown'}) {
    if (value == null) return fallback;
    final text = value.toString().trim();
    return text.isEmpty ? fallback : text;
  }

  int _safeInt(dynamic value, {int fallback = 0}) {
    if (value is num) return value.toInt();
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) return parsed;
    }
    return fallback;
  }

  DateTime? _safeDateTime(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String) return DateTime.tryParse(value);
    return null;
  }

  String _formattedSessionDate(Map<String, dynamic> session) {
    final createdAt = _safeDateTime(session['created_at']);
    return createdAt == null ? 'Date unavailable' : DateFormat('MMM dd, HH:mm').format(createdAt);
  }

  Color _getRiskColor(String level) {
    switch (level) {
      case 'HIGH':
        return const Color(0xFFDC2626);
      case 'MEDIUM':
        return const Color(0xFFF59E0B);
      case 'LOW':
        return const Color(0xFF16A34A);
      default:
        return AppPalette.textMuted(context);
    }
  }

  String _riskDisplayLabel(BuildContext context, String level) {
    final t = AppLocalizations.of(context)!;
    switch (level) {
      case 'HIGH':
        return t.statHighRiskLabel.toUpperCase();
      case 'MEDIUM':
        return t.statMediumRiskLabel.toUpperCase();
      case 'LOW':
        return t.statLowRiskLabel.toUpperCase();
      default:
        return t.unknownLabel.toUpperCase();
    }
  }

  void _toggleSidebar() {
    setState(() => _sidebarExpanded = !_sidebarExpanded);
  }

  Widget _buildStatCard(String title, String value, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    value,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
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

  void _updatePatientCodeSuggestions(List<Map<String, dynamic>> sessions) {
    if (_overlayEntry != null) {
      _overlayEntry!.remove();
      _overlayEntry = null;
    }

    if (_searchController == null || _searchFocusNode == null) return;
    if (_searchQuery.isEmpty || !_searchFocusNode!.hasFocus) return;

    final suggestions = sessions
        .map((session) => session['anonymous_code'])
        .whereType<String>()
        .where((code) => code.toUpperCase().contains(_searchQuery.toUpperCase()))
        .toSet()
        .take(5)
        .toList();

    if (suggestions.isEmpty) return;

    final fieldBox = _searchFocusNode!.context?.findRenderObject() as RenderBox?;
    if (fieldBox == null) return;

    final overlay = Overlay.of(context);
    final position = fieldBox.localToGlobal(Offset.zero);

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        top: position.dy + fieldBox.size.height + 8,
        left: position.dx,
        width: fieldBox.size.width,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: ListView.separated(
              padding: EdgeInsets.zero,
              shrinkWrap: true,
              itemCount: suggestions.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (_, index) {
                final suggestion = suggestions[index];
                return ListTile(
                  dense: true,
                  title: Text(suggestion),
                  onTap: () {
                    _searchController!.text = suggestion;
                    _searchQuery = suggestion;
                    _overlayEntry?.remove();
                    _overlayEntry = null;
                    _loadData();
                  },
                );
              },
            ),
          ),
        ),
      ),
    );

    overlay.insert(_overlayEntry!);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
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
                        _buildStatCard(
                          'Total',
                          _safeInt(_stats!['total']).toString(),
                          const Color(0xFF6D28D9),
                          Icons.people,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'High Risk',
                          _safeInt(_stats!['high_risk']).toString(),
                          const Color(0xFFDC2626),
                          Icons.warning,
                        ),
                        const SizedBox(width: 12),
                        _buildStatCard(
                          'Low Risk',
                          _safeInt(_stats!['low_risk']).toString(),
                          const Color(0xFF16A34A),
                          Icons.check_circle,
                        ),
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
                            prefixIcon: const Icon(Icons.search, color: Color(0xFF64748B)),
                            filled: true,
                            fillColor: Colors.white,
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
                      // Open/Closed lifecycle filter (blueprint session history).
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
                            final anonymousCode = _safeString(session['anonymous_code'], fallback: 'Unknown ID');
                            final bodyRegion = _safeString(session['body_region'], fallback: 'Unknown region');
                            final painType = _safeString(session['pain_type'], fallback: 'Unknown pain type');
                            final severity = _safeInt(session['severity']);

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
                                  anonymousCode,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text('$bodyRegion • $painType ($severity/10)'),
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
                                  final patientId = _safeString(session['anonymous_code'], fallback: '').trim();
                                  if (patientId.isEmpty) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(
                                          content: Text('Patient ID is unavailable.'),
                                          backgroundColor: Colors.orange,
                                        ),
                                      );
                                    }
                                    return;
                                  }

                                  await Navigator.of(context).push(
                                    AppPageRoute(
                                      builder: (_) => ClinicalReportScreen(
                                        patientId: patientId,
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
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon,
      Color color, VoidCallback onTap) {
    // Same fixed-width-inside-Wrap reasoning as _buildStatCard above.
    // The colored left accent is a separate Container inside a ClipRRect,
    // not a Border side — Flutter's Border.paint refuses a borderRadius on
    // a border whose sides aren't all the same color.
    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(14),
          child: Container(
            decoration: BoxDecoration(
              color: AppPalette.surface(context),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: AppPalette.border(context)),
              boxShadow: [
                BoxShadow(
                    color: Colors.black.withOpacity(0.02),
                    blurRadius: 8,
                    offset: const Offset(0, 2))
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(width: 4, color: color),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                  color: color.withOpacity(0.1),
                                  borderRadius: BorderRadius.circular(10)),
                              child: Icon(icon, color: color, size: 24),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(title,
                                      style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.bold,
                                          color:
                                              AppPalette.textPrimary(context))),
                                  const SizedBox(height: 4),
                                  Text(subtitle,
                                      style: TextStyle(
                                          fontSize: 12,
                                          color:
                                              AppPalette.textMuted(context))),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_forward_ios,
                                size: 14, color: AppPalette.textMuted(context)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDropdownFilter(String? currentValue, IconData icon,
      List<String> items, void Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
          color: AppPalette.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppPalette.border(context))),
      child: DropdownButton<String>(
        value: items.contains(currentValue) ? currentValue : null,
        underline: const SizedBox(),
        icon: Icon(icon, color: AppPalette.textMuted(context), size: 20),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        border: Border(top: BorderSide(color: AppPalette.border(context))),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.02),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  AppPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                ),
                icon: const Icon(Icons.home_outlined, size: 20, color: Color(0xFF6D28D9)),
                label: const Text('Home',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF6D28D9))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF6D28D9)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  AppPageRoute(builder: (_) => const PatientInfoScreen()),
                ),
                icon: const Icon(Icons.add_circle_outline, size: 20, color: Color(0xFF16A34A)),
                label: const Text('New Patient',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF16A34A))),
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Color(0xFF16A34A)),
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}