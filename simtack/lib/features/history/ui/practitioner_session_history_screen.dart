import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/github_kit.dart';
import '../../../core/theme/github_palette.dart';
import '../../../core/theme/app_page.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/app_header_bar.dart';
import '../../../core/offline/offline_repository.dart';
import '../../report/ui/clinical_report_screen.dart';
import '../../dashboard/ui/practitioner_scaffold.dart';

class PractitionerSessionHistoryScreen extends StatefulWidget {
  const PractitionerSessionHistoryScreen({super.key});

  @override
  State<PractitionerSessionHistoryScreen> createState() =>
      _PractitionerSessionHistoryScreenState();
}

class _PractitionerSessionHistoryScreenState
    extends State<PractitionerSessionHistoryScreen> {
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
      final result = await OfflineRepository.instance.getTriageList(
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
          SnackBar(
              content: Text('Error loading history: $e'),
              backgroundColor: GhColors.danger(context)),
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

  /// Score → tone. One mapping for the whole console, matching the dashboard.
  GhTone _riskTone(String level) {
    switch (level) {
      case 'HIGH':
        return GhTone.danger;
      case 'MEDIUM':
        return GhTone.attention;
      case 'LOW':
        return GhTone.success;
      default:
        return GhTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PractitionerScaffold(
      currentRoute: '/sessions',
      contentBuilder: (context, openDrawer) => Column(
        children: [
          AppHeaderBar(
            title: 'Session History',
            subtitle: 'Review and filter previous triage sessions.',
            onMenuTap: openDrawer,
          ),
          Expanded(
            child: Column(
              children: [
                _buildFilterBar(),
                Expanded(
                  child: _isLoading
                      ? Center(
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: GhColors.accent(context),
                          ),
                        )
                      : _items.isEmpty
                          ? const GhEmptyState(
                              icon: Icons.inbox_outlined,
                              message: 'No sessions found.',
                            )
                          : _buildList(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// The filter row: two GitHub selects sitting on the panel above the list, so
  /// they read as controls on a toolbar rather than as form fields.
  Widget _buildFilterBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: GhColors.surface(context),
        border: Border(bottom: BorderSide(color: GhColors.border(context))),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          GhSelect(
            icon: Icons.filter_list,
            value: _selectedRisk,
            options: const [
              GhOption('All Risks'),
              GhOption('High Risk', 'HIGH'),
              GhOption('Medium Risk', 'MEDIUM'),
              GhOption('Low Risk', 'LOW'),
            ],
            onChanged: (value) => _applyFilters(value, _selectedStatus),
          ),
          GhSelect(
            icon: Icons.folder_open,
            value: _selectedStatus,
            options: const [
              GhOption('All Status'),
              GhOption('Open', 'open'),
              GhOption('Closed', 'closed'),
            ],
            onChanged: (value) => _applyFilters(_selectedRisk, value),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    // The ListView stays the scroll owner so the rows remain lazily built; the
    // frame around it supplies the gutter and the console measure, which keeps
    // this list lined up with the header above it.
    return AppPage(
      maxWidth: AppContentWidth.wide,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          GhBox(
            flush: true,
            child: Column(
              children: [
                for (var index = 0; index < _items.length; index++)
                  _sessionRow(
                    _items[index],
                    isLast: index == _items.length - 1,
                  ),
              ],
            ),
          ),
          if (_isFetchingMore)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GhColors.accent(context),
                ),
              ),
            )
          else if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: GhButton(
                  'Load More',
                  icon: Icons.expand_more,
                  variant: GhButtonVariant.secondary,
                  onPressed: () => _loadHistory(reset: false),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _sessionRow(Map<String, dynamic> session, {required bool isLast}) {
    final riskLevel = _getRiskLevel(session['risk_score'] as double?);
    final tone = _riskTone(riskLevel);
    // This list holds raw JSON rather than TriageResult, so the red flag is read
    // straight off the payload. `is Map` instead of a cast: a malformed row must
    // not break the queue.
    final escalation = session['escalation'];
    final escalationLevel = escalation is Map ? escalation['level'] : null;
    final isRedFlag = escalationLevel == 'emergency';
    final isUrgent = escalationLevel == 'urgent';
    final isClosed = session['status'] == 'closed';
    final date = DateTime.parse(session['created_at'] as String);
    final formattedDate = DateFormat('dd MMM yyyy, HH:mm').format(date);

    return GhActionRow(
      icon: isRedFlag ? Icons.emergency_outlined : Icons.monitor_heart_outlined,
      tone: isRedFlag ? GhTone.danger : tone,
      showDivider: !isLast,
      title: session['anonymous_code'] ?? 'Unknown ID',
      subtitle:
          '${session['body_region']} • ${session['pain_type']} • $formattedDate',
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isRedFlag)
            const GhLabel('RED FLAG', tone: GhTone.danger)
          else if (isUrgent)
            const GhLabel('SEE TODAY', tone: GhTone.attention),
          const SizedBox(width: 6),
          GhLabel(riskLevel, tone: tone),
          const SizedBox(width: 6),
          GhLabel(
            isClosed ? 'Closed' : 'Open',
            tone: isClosed ? GhTone.done : GhTone.success,
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
    );
  }
}
