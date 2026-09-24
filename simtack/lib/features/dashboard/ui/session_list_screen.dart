import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/network/api_client.dart';
import '../../report/ui/clinical_report_screen.dart';

class SessionListScreen extends StatefulWidget {
  final String? initialRiskLevel;
  final String? initialStatus;

  const SessionListScreen({
    super.key,
    this.initialRiskLevel,
    this.initialStatus,
  });

  @override
  State<SessionListScreen> createState() => _SessionListScreenState();
}

class _SessionListScreenState extends State<SessionListScreen> {
  List<Map<String, dynamic>> _sessions = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  String _searchQuery = '';
  String? _selectedRisk;
  String? _selectedStatus;
  int _offset = 0;
  static const int _limit = 20;
  bool _hasMore = true;

  Timer? _searchDebounce;
  TextEditingController? _searchController;

  @override
  void initState() {
    super.initState();
    _selectedRisk = widget.initialRiskLevel;
    _selectedStatus = widget.initialStatus;
    _loadData();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController?.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await ApiClient.getTriageList(
        limit: _limit,
        offset: 0,
        patientCode: _searchQuery.isEmpty ? null : _searchQuery,
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

  String _getRiskLevel(double? score) {
    if (score == null) return 'UNKNOWN';
    if (score >= 0.7) return 'HIGH';
    if (score >= 0.4) return 'MEDIUM';
    return 'LOW';
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

  String _formattedSessionDate(Map<String, dynamic> session) {
    final createdAt = DateTime.tryParse(session['created_at']?.toString() ?? '');
    return createdAt == null ? 'Date unavailable' : DateFormat('MMM dd, HH:mm').format(createdAt);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session List'),
        backgroundColor: Colors.white,
        elevation: 0,
        foregroundColor: const Color(0xFF1E293B),
      ),
      body: Column(
        children: [
          // SEARCH & FILTER BAR
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _searchController,
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

          // SESSION LIST
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _sessions.isEmpty
                    ? const Center(child: Text('No triage sessions found.', style: TextStyle(color: Color(0xFF64748B))))
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _sessions.length + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          if (index == _sessions.length) {
                            return _isLoadingMore
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: Center(child: CircularProgressIndicator()),
                                  )
                                : const SizedBox.shrink();
                          }
                          final session = _sessions[index];
                          final riskLevel = _getRiskLevel(session['risk_score']);
                          final riskColor = _getRiskColor(riskLevel);
                          final isClosed = session['status'] == 'closed';

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
                                  const SizedBox(height: 4),
                                  Text(_formattedSessionDate(session), style: const TextStyle(fontSize: 12, color: Color(0xFF64748B))),
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
    );
  }
}