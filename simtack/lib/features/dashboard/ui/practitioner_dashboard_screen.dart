import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/github_palette.dart';
import '../../../core/theme/github_kit.dart';
import '../../../core/theme/app_header_bar.dart';
import '../../../core/theme/app_page.dart';
import '../../../core/offline/offline_repository.dart';
import '../../report/ui/clinical_report_screen.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
import '../../../core/theme/app_page_route.dart';
import 'qr_scan_screen.dart';
import 'patient_overview_pane.dart';
import 'practitioner_scaffold.dart';
import '../../onboarding/ui/welcome_screen.dart';
import '../../patient_info/ui/patient_info_screen.dart';

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
      final stats = await OfflineRepository.instance.getTriageStats();
      final recent =
          await OfflineRepository.instance.getTriageList(limit: 5, offset: 0);
      final sessions = await OfflineRepository.instance.getTriageList(
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
          SnackBar(
              content: Text('Error loading dashboard: $e'),
              backgroundColor: GhColors.danger(context)),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final moreSessions = await OfflineRepository.instance.getTriageList(
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
              backgroundColor: GhColors.danger(context)),
        );
      }
    }
  }

  Future<void> _refreshStats() async {
    try {
      final stats = await OfflineRepository.instance.getTriageStats();
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

  /// Clinical risk → Primer tone. One mapping for the whole console, so the
  /// dashboard, the session list and the report cannot disagree about what
  /// "medium" looks like.
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return PractitionerScaffold(
      currentRoute: '/dashboard',
      footer: _buildFooter(context),
      contentBuilder: (context, openDrawer) => Column(
        children: [
          AppHeaderBar(
            title: t.dashboardTitle,
            subtitle: t.dashboardSubtitle,
            onMenuTap: openDrawer,
            actions: [
              AppHeaderIconButton(
                icon: Icons.refresh,
                tooltip: t.refreshDataTooltip,
                onPressed: () async {
                  await _loadData();
                  await _refreshStats();
                },
              ),
              AppHeaderIconButton(
                icon: Icons.tune,
                tooltip: t.displayAccessibilityTooltip,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                        builder: (_) => const AccessibilitySettingsScreen()),
                  );
                },
              ),
            ],
          ),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: GhColors.accent(context),
                    ),
                  )
                : _buildMainContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    final t = AppLocalizations.of(context)!;
    return RefreshIndicator(
      onRefresh: () async {
        await _loadData();
        await _refreshStats();
      },
      child: AppPage(
        scrollable: true,
        // A console, not prose: this screen reads as a workspace, so it gets
        // the full measure. The cap is what stops a 1920px monitor from
        // stretching four stat tiles and a session list into a kilometre of
        // whitespace.
        maxWidth: AppContentWidth.wide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (_stats != null)
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  GhStatTile(
                    label: t.statTotalLabel,
                    value: _stats!['total'].toString(),
                    icon: Icons.people_outline,
                    tone: GhTone.accent,
                    onTap: () => _navigateToSessionList(),
                  ),
                  GhStatTile(
                    label: t.statHighRiskLabel,
                    value: _stats!['high_risk'].toString(),
                    icon: Icons.warning_amber_outlined,
                    tone: GhTone.danger,
                    onTap: () => _navigateToSessionList(riskLevel: 'HIGH'),
                  ),
                  GhStatTile(
                    label: t.statMediumRiskLabel,
                    value: _stats!['medium_risk'].toString(),
                    icon: Icons.trending_up,
                    tone: GhTone.attention,
                    onTap: () => _navigateToSessionList(riskLevel: 'MEDIUM'),
                  ),
                  GhStatTile(
                    label: t.statLowRiskLabel,
                    value: _stats!['low_risk'].toString(),
                    icon: Icons.check_circle_outline,
                    tone: GhTone.success,
                    onTap: () => _navigateToSessionList(riskLevel: 'LOW'),
                  ),
                ],
              ),

            const SizedBox(height: 24),

            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _buildActionCard(
                  t.patientLookupTitle,
                  t.actionPatientLookupSubtitle,
                  Icons.person_search,
                  GhTone.accent,
                  () => _navigateToPatientOverview(),
                ),
                _buildActionCard(
                  t.actionNewTriageTitle,
                  t.actionNewTriageSubtitle,
                  Icons.add_circle_outline,
                  GhTone.success,
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
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GhTextField(
                  width: 260,
                  hint: t.searchPatientIdHint,
                  prefixIcon: Icons.search,
                  onChanged: (value) {
                    setState(() => _searchQuery = value.toUpperCase());
                    _searchDebounce?.cancel();
                    _searchDebounce =
                        Timer(const Duration(milliseconds: 400), () {
                      _loadData();
                    });
                  },
                ),
                if (!kIsWeb)
                  GhButton(
                    'Scan QR',
                    icon: Icons.qr_code_scanner,
                    onPressed: _scanQr,
                  ),
                _buildDropdownFilter(_selectedRisk, Icons.filter_list,
                    ['All', 'High', 'Med', 'Low'], (value) {
                  setState(() => _selectedRisk = value == 'All' ? null : value);
                  _loadData();
                }),
                _buildDropdownFilter(_selectedStatus, Icons.folder_open,
                    ['Any', 'Open', 'Closed'], (value) {
                  setState(() => _selectedStatus =
                      value == 'Any' ? null : value?.toLowerCase());
                  _loadData();
                }),
              ],
            ),

            const SizedBox(height: 24),

            GhSectionHeader(
              t.navTriageSessions,
              actions: [
                GhButton(
                  t.viewAllButton,
                  variant: GhButtonVariant.link,
                  onPressed: _navigateToSessionList,
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (_sessions.isEmpty)
              GhBox(
                child: GhEmptyState(
                  icon: Icons.inbox_outlined,
                  message: t.noTriageSessionsFoundMessage,
                ),
              )
            else
              _buildSessionList(),

            if (_hasMore && _sessions.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Center(
                  child: GhButton(
                    _isLoadingMore ? t.loadingEllipsis : t.loadMoreButton,
                    variant: GhButtonVariant.secondary,
                    busy: _isLoadingMore,
                    onPressed: _isLoadingMore ? null : _loadMore,
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
    final t = AppLocalizations.of(context)!;
    final recent = _recentSessions.take(5).toList();

    return GhBox(
      header: t.recentActivityTitle,
      headerActions: [
        GhButton(
          t.seeAllButton,
          variant: GhButtonVariant.link,
          onPressed: _navigateToSessionList,
        ),
      ],
      flush: true,
      child: Column(
        children: [
          for (var index = 0; index < recent.length; index++)
            _buildRecentSessionItem(
              recent[index],
              showDivider: index < recent.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildRecentSessionItem(Map<String, dynamic> session,
      {bool showDivider = true}) {
    final t = AppLocalizations.of(context)!;
    final riskLevel = _getRiskLevel(session['risk_score']);
    final tone = _riskTone(riskLevel);
    final date = DateTime.parse(session['created_at']);
    final formattedDate = DateFormat('MMM dd, HH:mm').format(date);

    return GhActionRow(
      icon: Icons.monitor_heart_outlined,
      tone: tone,
      title: session['anonymous_code'] ?? t.unknownLabel,
      subtitle:
          '${session['body_region']} • ${session['pain_type']} • $formattedDate',
      showDivider: showDivider,
      trailing: _buildStateLabels(session, riskLevel),
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
    );
  }

  /// The risk and status pills that trail every session row. GitHub reads
  /// state as a coloured label, not as a tinted avatar, so the row's colour
  /// budget is spent on these two pills only.
  Widget _buildStateLabels(Map<String, dynamic> session, String riskLevel) {
    final t = AppLocalizations.of(context)!;
    final isClosed = session['status'] == 'closed';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GhLabel(_riskDisplayLabel(context, riskLevel),
            tone: _riskTone(riskLevel)),
        const SizedBox(width: 6),
        GhLabel(
          isClosed ? t.statusClosedLabel : t.statusOpenLabel,
          tone: isClosed ? GhTone.done : GhTone.success,
        ),
      ],
    );
  }

  Widget _buildSessionList() {
    return GhBox(
      flush: true,
      child: Column(
        children: [
          for (var index = 0; index < _sessions.length; index++)
            _buildSessionRow(
              _sessions[index],
              showDivider: index < _sessions.length - 1,
            ),
        ],
      ),
    );
  }

  Widget _buildSessionRow(Map<String, dynamic> session,
      {required bool showDivider}) {
    final t = AppLocalizations.of(context)!;
    final riskLevel = _getRiskLevel(session['risk_score']);
    final date = DateTime.parse(session['created_at']);
    final formattedDate = DateFormat('MMM dd, HH:mm').format(date);
    final demo = _demoLine(session);

    return GhActionRow(
      icon: Icons.monitor_heart_outlined,
      tone: _riskTone(riskLevel),
      title: session['anonymous_code'] ?? t.unknownIdLabel,
      subtitle: [
        '${session['body_region']} • ${session['pain_type']} (${session['severity']}/10)',
        if (demo != null) demo,
        formattedDate,
      ].join(' • '),
      showDivider: showDivider,
      trailing: _buildStateLabels(session, riskLevel),
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
    );
  }

  Widget _buildActionCard(String title, String subtitle, IconData icon,
      GhTone tone, VoidCallback onTap) {
    // Fixed width inside the Wrap above, same reasoning as the stat tiles:
    // a Row cannot shrink a fixed-width child, a Wrap reflows it.
    final color = tone.color(context);

    return SizedBox(
      width: 280,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          hoverColor: GhColors.surfaceHover(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: GhColors.surface(context),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: GhColors.border(context)),
            ),
            child: Row(
              children: [
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: tone.subtle(context),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: color.withOpacity(0.28)),
                  ),
                  child: Icon(icon, size: 16, color: color),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        overflow: TextOverflow.ellipsis,
                        style: GhType.bodyStrong.copyWith(
                          color: GhColors.fg(context),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        overflow: TextOverflow.ellipsis,
                        style: GhType.meta.copyWith(
                          color: GhColors.fgMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right,
                    size: 16, color: GhColors.fgMuted(context)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// A filter control drawn as a GitHub select: a bordered 32px button whose
  /// label is the current choice.
  Widget _buildDropdownFilter(String? currentValue, IconData icon,
      List<String> items, void Function(String?) onChanged) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: GhColors.defaultButtonBg(context),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: GhColors.border(context)),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: items.contains(currentValue) ? currentValue : null,
          isDense: true,
          borderRadius: BorderRadius.circular(6),
          dropdownColor: GhColors.surface(context),
          style: GhType.body.copyWith(color: GhColors.fg(context)),
          icon: Icon(icon, size: 14, color: GhColors.fgMuted(context)),
          hint: Text(items.first,
              style: GhType.body.copyWith(color: GhColors.fg(context))),
          items: items
              .map((e) => DropdownMenuItem<String>(
                    value: e,
                    child: Text(e,
                        style:
                            GhType.body.copyWith(color: GhColors.fg(context))),
                  ))
              .toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      decoration: BoxDecoration(
        color: GhColors.surface(context),
        border: Border(top: BorderSide(color: GhColors.border(context))),
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: GhButton(
                'Home',
                icon: Icons.home_outlined,
                variant: GhButtonVariant.secondary,
                expanded: true,
                onPressed: () => Navigator.of(context).pushAndRemoveUntil(
                  AppPageRoute(builder: (_) => const WelcomeScreen()),
                  (route) => false,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: GhButton(
                'New Patient',
                icon: Icons.add_circle_outline,
                variant: GhButtonVariant.primary,
                expanded: true,
                onPressed: () => Navigator.of(context).push(
                  AppPageRoute(builder: (_) => const PatientInfoScreen()),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
  int _offset = 0;
  String? _selectedRisk;
  String? _selectedStatus;
  static const int _limit = 20;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    _selectedRisk = widget.initialRiskLevel;
    _selectedStatus = widget.initialStatus;
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() => _isLoading = true);
    try {
      final sessions = await OfflineRepository.instance.getTriageList(
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
          SnackBar(
              content: Text('Error loading sessions: $e'),
              backgroundColor: GhColors.danger(context)),
        );
      }
    }
  }

  Future<void> _loadMore() async {
    if (_isLoadingMore || !_hasMore) return;
    setState(() => _isLoadingMore = true);
    try {
      final more = await OfflineRepository.instance.getTriageList(
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

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: GhColors.canvas(context),
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: GhColors.headerBg(context),
              border: Border(
                bottom: BorderSide(color: Colors.black.withOpacity(0.28)),
              ),
            ),
            child: Row(
              children: [
                AppHeaderIconButton(
                  icon: Icons.arrow_back,
                  tooltip: t.allTriageSessionsTitle,
                  onPressed: () => Navigator.of(context).pop(),
                  compact: true,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    t.allTriageSessionsTitle,
                    overflow: TextOverflow.ellipsis,
                    style: GhType.headerTitle.copyWith(
                      color: GhColors.headerFg(context),
                    ),
                  ),
                ),
                AppHeaderIconButton(
                  icon: Icons.filter_list,
                  tooltip: t.filterSessionsTitle,
                  onPressed: () => _showFilterSheet(),
                ),
              ],
            ),
          ),
          if (_isLoading)
            Expanded(
              child: Center(
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: GhColors.accent(context),
                ),
              ),
            )
          else ...[
            if (_selectedRisk != null || _selectedStatus != null)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: GhColors.surface(context),
                  border: Border(
                    bottom: BorderSide(color: GhColors.border(context)),
                  ),
                ),
                child: Row(
                  children: [
                    if (_selectedRisk != null)
                      _filterPill(context, _selectedRisk!, () {
                        setState(() => _selectedRisk = null);
                        _loadSessions();
                      }),
                    if (_selectedStatus != null) ...[
                      const SizedBox(width: 8),
                      _filterPill(context, _selectedStatus!, () {
                        setState(() => _selectedStatus = null);
                        _loadSessions();
                      }),
                    ],
                    const Spacer(),
                    GhButton(
                      t.clearAllButton,
                      variant: GhButtonVariant.link,
                      onPressed: () {
                        setState(() {
                          _selectedRisk = null;
                          _selectedStatus = null;
                        });
                        _loadSessions();
                      },
                    ),
                  ],
                ),
              ),
            Expanded(
              child: RefreshIndicator(
                onRefresh: _loadSessions,
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    if (_sessions.isEmpty)
                      GhBox(
                        child: GhEmptyState(
                          icon: Icons.inbox_outlined,
                          message: t.noSessionsFoundMessage,
                        ),
                      )
                    else
                      GhBox(
                        flush: true,
                        child: Column(
                          children: [
                            for (var index = 0;
                                index < _sessions.length;
                                index++)
                              _sessionRow(
                                context,
                                t,
                                _sessions[index],
                                showDivider: index < _sessions.length - 1,
                              ),
                          ],
                        ),
                      ),
                    if (_hasMore)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Center(
                          child: GhButton(
                            t.loadMoreButton,
                            variant: GhButtonVariant.secondary,
                            busy: _isLoadingMore,
                            onPressed: _isLoadingMore ? null : _loadMore,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _sessionRow(
      BuildContext context, AppLocalizations t, Map<String, dynamic> session,
      {required bool showDivider}) {
    final riskLevel = _getRiskLevel(session['risk_score']);
    final date = DateTime.parse(session['created_at']);
    final formattedDate = DateFormat('MMM dd, yyyy, HH:mm').format(date);

    return GhActionRow(
      icon: Icons.monitor_heart_outlined,
      tone: _riskTone(riskLevel),
      title: session['anonymous_code'] ?? t.unknownLabel,
      subtitle:
          '${session['body_region']} • ${session['pain_type']} • $formattedDate',
      showDivider: showDivider,
      trailing: GhLabel(
        _riskDisplayLabel(context, riskLevel),
        tone: _riskTone(riskLevel),
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
    );
  }

  /// An applied filter, shown as a label with the small dismiss cross that
  /// GitHub puts next to a filter chip.
  Widget _filterPill(BuildContext context, String value, VoidCallback onClear) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        GhLabel(value, tone: GhTone.neutral),
        InkWell(
          onTap: onClear,
          borderRadius: BorderRadius.circular(999),
          child: Padding(
            padding: const EdgeInsets.all(3),
            child:
                Icon(Icons.close, size: 12, color: GhColors.fgMuted(context)),
          ),
        ),
      ],
    );
  }

  /// A selectable pill for the filter sheet — the GitHub equivalent of a
  /// `ChoiceChip`, with the accent ring reserved for the current choice.
  Widget _choicePill(BuildContext context,
      {required String label,
      required bool selected,
      required VoidCallback onTap}) {
    return Material(
      color: selected
          ? GhColors.accentSubtle(context)
          : GhColors.defaultButtonBg(context),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: selected
                  ? GhColors.accent(context).withOpacity(0.45)
                  : GhColors.border(context),
            ),
          ),
          child: Text(
            label,
            style: GhType.meta.copyWith(
              color: selected ? GhColors.accent(context) : GhColors.fg(context),
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }

  void _showFilterSheet() {
    final t = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: GhColors.surface(context),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(6))),
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.filterSessionsTitle,
                  style: GhType.sectionTitle
                      .copyWith(color: GhColors.fg(context))),
              const SizedBox(height: 20),
              Text(t.riskLevelLabel.toUpperCase(),
                  style: GhType.meta.copyWith(
                      color: GhColors.fgMuted(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['All', 'HIGH', 'MEDIUM', 'LOW'].map((level) {
                  final isSelected = _selectedRisk == level ||
                      (_selectedRisk == null && level == 'All');
                  return _choicePill(
                    context,
                    label: level,
                    selected: isSelected,
                    onTap: () => setSheetState(
                        () => _selectedRisk = level == 'All' ? null : level),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              Text(t.statusLabel.toUpperCase(),
                  style: GhType.meta.copyWith(
                      color: GhColors.fgMuted(context),
                      fontWeight: FontWeight.w600,
                      fontSize: 11,
                      letterSpacing: 0.6)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: ['Any', 'open', 'closed'].map((status) {
                  final isSelected = _selectedStatus == status ||
                      (_selectedStatus == null && status == 'Any');
                  return _choicePill(
                    context,
                    label: status,
                    selected: isSelected,
                    onTap: () => setSheetState(() =>
                        _selectedStatus = status == 'Any' ? null : status),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),
              GhButton(
                t.applyFiltersButton,
                variant: GhButtonVariant.primary,
                expanded: true,
                onPressed: () {
                  setState(() {});
                  Navigator.pop(context);
                  _loadSessions();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
