import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/network/api_client.dart';
import '../../report/ui/clinical_report_screen.dart';

class PractitionerSessionHistoryScreen extends StatefulWidget {
  const PractitionerSessionHistoryScreen({super.key});

  @override
  State<PractitionerSessionHistoryScreen> createState() => _PractitionerSessionHistoryScreenState();
}

class _PractitionerSessionHistoryScreenState extends State<PractitionerSessionHistoryScreen> {
  List<Map<String, dynamic>> _items = [];
  int _offset = 0;
  static const int _limit = 20;
  bool _isLoading = true;
  bool _isFetchingMore = false;
  bool _hasMore = true;

  String? _selectedRisk;
  String? _selectedStatus;

  @override
  void initState() {
    super.initState();
    _loadHistory(reset: true);
  }

  Future<void> _loadHistory({bool reset = false}) async {
    if (reset) {
      setState(() {
        _isLoading = true;
        _offset = 0;
        _items = [];
        _hasMore = true;
      });
    } else {
      setState(() => _isFetchingMore = true);
    }

    try {
      final result = await ApiClient.getTriageList(
        limit: _limit,
        offset: reset ? 0 : _offset,
        riskLevel: _selectedRisk,
        status: _selectedStatus,
      );

      if (mounted) {
        setState(() {
          if (reset) {
            _items = result;
          } else {
            _items.addAll(result);
          }
          _offset = _items.length;
          _hasMore = result.length >= _limit;
          _isLoading = false;
          _isFetchingMore = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isFetchingMore = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading history: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _applyFilters(String? risk, String? status) {
    setState(() {
      _selectedRisk = risk;
      _selectedStatus = status;
    });
    _loadHistory(reset: true);
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
        title: const Text('Session History', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Filter Bar
          Container(
            padding: const EdgeInsets.all(16),
            color: AppPalette.surface(context),
            child: Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedRisk,
                    decoration: InputDecoration(
                      hintText: 'Risk Level',
                      filled: true,
                      fillColor: AppPalette.inputFill(context),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All Risks')),
                      DropdownMenuItem(value: 'HIGH', child: Text('High Risk')),
                      DropdownMenuItem(value: 'MEDIUM', child: Text('Medium Risk')),
                      DropdownMenuItem(value: 'LOW', child: Text('Low Risk')),
                    ],
                    onChanged: (val) => _applyFilters(val, _selectedStatus),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _selectedStatus,
                    decoration: InputDecoration(
                      hintText: 'Status',
                      filled: true,
                      fillColor: AppPalette.inputFill(context),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      DropdownMenuItem(value: null, child: Text('All Status')),
                      DropdownMenuItem(value: 'open', child: Text('Open')),
                      DropdownMenuItem(value: 'closed', child: Text('Closed')),
                    ],
                    onChanged: (val) => _applyFilters(_selectedRisk, val),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          
          // Paginated List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _items.isEmpty
                    ? Center(child: Text('No sessions found.', style: TextStyle(color: AppPalette.textMuted(context))))
                    : ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _items.length + (_isFetchingMore ? 1 : 0) + (_hasMore ? 1 : 0),
                        itemBuilder: (context, index) {
                          // Loading indicator at the bottom
                          if (index == _items.length && _isFetchingMore) {
                            return const Padding(
                              padding: EdgeInsets.all(16),
                              child: Center(child: CircularProgressIndicator()),
                            );
                          }
                          // "Load More" button at the bottom
                          if (index == _items.length && _hasMore) {
                            return Padding(
                              padding: const EdgeInsets.all(16),
                              child: Center(
                                child: ElevatedButton(
                                  onPressed: () => _loadHistory(reset: false),
                                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF6D28D9)),
                                  child: const Text('Load More', style: TextStyle(color: Colors.white)),
                                ),
                              ),
                            );
                          }

                          final session = _items[index];
                          final riskLevel = _getRiskLevel(session['risk_score'] as double?);
                          final riskColor = _getRiskColor(riskLevel);
                          final date = DateTime.parse(session['created_at'] as String);
                          final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(date);

                          return Card(
                            margin: const EdgeInsets.only(bottom: 12),
                            elevation: 1,
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
                                  Text('${session['body_region']} • ${session['pain_type']}'),
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
                                    session['status'] == 'closed' ? 'Closed' : 'Open',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: session['status'] == 'closed' ? AppPalette.textMuted(context) : const Color(0xFFF59E0B),
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                Navigator.of(context).push(
                                  AppPageRoute(
                                    builder: (_) => ClinicalReportScreen(
                                      patientId: session['anonymous_code'] ?? '',
                                      practitionerMode: true,
                                    ),
                                  ),
                                );
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