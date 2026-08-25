import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../auth/ui/login_screen.dart';
import '../../report/ui/clinical_report_screen.dart';
import '../../../core/theme/app_page_route.dart';

class PatientHistoryScreen extends StatefulWidget {
  final String patientId;

  const PatientHistoryScreen({super.key, required this.patientId});

  @override
  State<PatientHistoryScreen> createState() => _PatientHistoryScreenState();
}

class _PatientHistoryScreenState extends State<PatientHistoryScreen> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    setState(() => _isLoading = true);
    try {
      // Fetch only the sessions for this specific patient
      final sessions = await ApiClient.getTriageList(patientCode: widget.patientId);
      setState(() {
        _history = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading history: $e'), backgroundColor: Colors.red),
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

  /// Profile tab: shows the signed-in practitioner's account details and
  /// the logout action (previously this tab was completely inert).
  void _showProfileSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        Doctor? doctor;
        String? error;
        var loaded = false;

        Future<void> fetch() async {
          try {
            doctor = await ApiClient.getCurrentDoctor();
          } catch (e) {
            error = 'Could not load account details.';
          }
          loaded = true;
        }

        return FutureBuilder(
          future: fetch(),
          builder: (context, _) {
            if (!loaded) {
              return const Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE2E8F0),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Color(0xFFEDE9FE),
                    child: Icon(Icons.person, size: 30, color: Color(0xFF6D28D9)),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    doctor?.fullName ?? 'Practitioner',
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  Text(
                    doctor?.email ?? error ?? '',
                    style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        await AuthService.instance.logout();
                        if (!sheetContext.mounted) return;
                        Navigator.of(sheetContext).pushAndRemoveUntil(
                          AppPageRoute(builder: (_) => const LoginScreen()),
                          (route) => false,
                        );
                      },
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFDC2626),
                        side: const BorderSide(color: Color(0xFFFCA5A5)),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.logout, size: 18),
                      label: const Text('Log out', style: TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Color _getRiskColor(String level) {
    switch (level) {
      case 'HIGH': return const Color(0xFFDC2626);
      case 'MEDIUM': return const Color(0xFFF59E0B);
      case 'LOW': return const Color(0xFF16A34A);
      default: return const Color(0xFF64748B);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text('My Triage History', style: TextStyle(color: Color(0xFF1E293B), fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.refresh, color: Color(0xFF6D28D9)), onPressed: _loadHistory),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? const Center(child: Text('No past history found.', style: TextStyle(color: Color(0xFF64748B))))
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _history.length,
                  itemBuilder: (context, index) {
                    final session = _history[index];
                    final riskLevel = _getRiskLevel(session['risk_score']);
                    final riskColor = _getRiskColor(riskLevel);
                    final date = DateTime.parse(session['created_at']);
                    final formattedDate = DateFormat('dd MMM yyyy, HH:mm a').format(date);

                    return Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      elevation: 1,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      child: ListTile(
                        contentPadding: const EdgeInsets.all(16),
                        title: Text(
                          session['body_region'] ?? 'Unknown Location',
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Color(0xFF1E293B)),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Text(
                            formattedDate,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                          ),
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                        onTap: () {
                          Navigator.of(context).push(
                            AppPageRoute(
                              builder: (_) => ClinicalReportScreen(patientId: widget.patientId),
                            ),
                          );
                        },
                      ),
                    );
                  },
                ),
      // Bottom Navigation Bar (Matching Blueprint)
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: 2, // Highlight the History tab
        type: BottomNavigationBarType.fixed,
        selectedItemColor: const Color(0xFF6D28D9),
        unselectedItemColor: const Color(0xFF94A3B8),
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.home_outlined), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.add_circle_outline), label: 'New'),
          BottomNavigationBarItem(icon: Icon(Icons.history), label: 'History'),
          BottomNavigationBarItem(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
        onTap: (index) {
          if (index == 0) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else if (index == 1) {
            Navigator.of(context).popUntil((route) => route.isFirst);
          } else if (index == 3) {
            _showProfileSheet();
          }
        },
      ),
    );
  }
}