import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/theme/app_header_bar.dart';
import '../../../core/theme/app_page.dart';
import '../../../core/theme/app_tokens.dart';
import '../../../core/theme/github_kit.dart';
import '../../../core/theme/github_palette.dart';
import '../../dashboard/ui/practitioner_scaffold.dart';
import '../data/admin_repository.dart';

/// The administrator console.
///
/// This is the one practitioner screen that is about the system rather than a
/// patient: accounts and approvals, the audit trail, and how triage volume is
/// spread across risk bands, tiers and regions. It is guarded twice — the
/// sidebar only offers the link to an administrator, and every server route
/// re-checks the role — so hiding the link is convenience, not security.
///
/// The console reads through [AdminRepository], which keeps the last successful
/// snapshot in the encrypted local document. With no connection it opens on that
/// snapshot and says how old it is; with no snapshot it says so and offers a
/// retry. Account changes always require the server, because a locally-approved
/// account that the server has never seen is not an approval.
class AdminConsoleScreen extends StatefulWidget {
  const AdminConsoleScreen({super.key});

  @override
  State<AdminConsoleScreen> createState() => _AdminConsoleScreenState();
}

class _AdminConsoleScreenState extends State<AdminConsoleScreen> {
  static const _tabs = [
    'Overview',
    'Users',
    'Patients',
    'Activity',
    'Sessions'
  ];
  static const _tabIcons = [
    Icons.space_dashboard_outlined,
    Icons.people_outline,
    Icons.person_search_outlined,
    Icons.history,
    Icons.monitor_heart_outlined,
  ];

  int _tab = 0;
  bool _checkingAccess = true;
  bool _isAdmin = false;
  String? _accessError;
  Doctor? _currentDoctor;

  AdminSnapshot? _overview;
  AdminSnapshot? _users;
  AdminSnapshot? _patients;
  AdminSnapshot? _activity;
  AdminSnapshot? _sessions;

  bool _overviewLoading = false;
  bool _usersLoading = false;
  bool _patientsLoading = false;
  bool _activityLoading = false;
  bool _sessionsLoading = false;

  String? _overviewError;
  String? _usersError;
  String? _patientsError;
  String? _activityError;
  String? _sessionsError;

  int _usersPage = 1;
  int _patientsPage = 1;
  int _activityPage = 1;
  int _sessionsPage = 1;

  final TextEditingController _userSearch = TextEditingController();
  final TextEditingController _patientSearch = TextEditingController();
  Timer? _searchDebounce;
  String? _userStatus;
  String? _patientHasSessions;

  String? _activityAction;
  String? _activityOutcome;

  String? _sessionRisk;
  String? _sessionStatus;

  @override
  void initState() {
    super.initState();
    _checkAccess();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _userSearch.dispose();
    _patientSearch.dispose();
    super.dispose();
  }

  Future<void> _checkAccess() async {
    try {
      final doctor = await AuthService.instance.getCurrentDoctor();
      if (!mounted) return;
      setState(() {
        _currentDoctor = doctor;
        _isAdmin = doctor.isAdmin;
        _checkingAccess = false;
      });
      if (doctor.isAdmin) await _loadOverview();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _accessError = _messageFor(error);
        _checkingAccess = false;
      });
    }
  }

  // ── Loading ─────────────────────────────────────────────────────────────

  Future<void> _loadOverview() async {
    setState(() {
      _overviewLoading = true;
      _overviewError = null;
    });
    try {
      final snapshot = await AdminRepository.instance.loadOverview();
      if (!mounted) return;
      setState(() {
        _overview = snapshot;
        _overviewLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _overviewError = _messageFor(error);
        _overviewLoading = false;
      });
    }
  }

  Future<void> _loadUsers({int page = 1}) async {
    setState(() {
      _usersLoading = true;
      _usersError = null;
      _usersPage = page;
    });
    try {
      final snapshot = await AdminRepository.instance.loadUsers(
        page: page,
        query: _userSearch.text,
        status: _userStatus,
      );
      if (!mounted) return;
      setState(() {
        _users = snapshot;
        _usersLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _usersError = _messageFor(error);
        _usersLoading = false;
      });
    }
  }

  Future<void> _loadPatients({int page = 1}) async {
    setState(() {
      _patientsLoading = true;
      _patientsError = null;
      _patientsPage = page;
    });
    try {
      final snapshot = await AdminRepository.instance.loadPatients(
        page: page,
        query: _patientSearch.text,
        hasSessions: _patientHasSessions == null
            ? null
            : _patientHasSessions == 'true',
      );
      if (!mounted) return;
      setState(() {
        _patients = snapshot;
        _patientsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _patientsError = _messageFor(error);
        _patientsLoading = false;
      });
    }
  }

  Future<void> _loadActivity({int page = 1}) async {
    setState(() {
      _activityLoading = true;
      _activityError = null;
      _activityPage = page;
    });
    try {
      final snapshot = await AdminRepository.instance.loadActivity(
        page: page,
        action: _activityAction,
        outcome: _activityOutcome,
      );
      if (!mounted) return;
      setState(() {
        _activity = snapshot;
        _activityLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _activityError = _messageFor(error);
        _activityLoading = false;
      });
    }
  }

  Future<void> _loadSessions({int page = 1}) async {
    setState(() {
      _sessionsLoading = true;
      _sessionsError = null;
      _sessionsPage = page;
    });
    try {
      final snapshot = await AdminRepository.instance.loadSessions(
        page: page,
        riskLevel: _sessionRisk,
        status: _sessionStatus,
      );
      if (!mounted) return;
      setState(() {
        _sessions = snapshot;
        _sessionsLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _sessionsError = _messageFor(error);
        _sessionsLoading = false;
      });
    }
  }

  void _onTabSelected(int index) {
    setState(() => _tab = index);
    switch (index) {
      case 1:
        if (_users == null) _loadUsers();
        break;
      case 2:
        if (_patients == null) _loadPatients();
        break;
      case 3:
        if (_activity == null) _loadActivity();
        break;
      case 4:
        if (_sessions == null) _loadSessions();
        break;
      default:
        if (_overview == null) _loadOverview();
    }
  }

  void _refreshCurrent() {
    switch (_tab) {
      case 1:
        _loadUsers(page: _usersPage);
        break;
      case 2:
        _loadPatients(page: _patientsPage);
        break;
      case 3:
        _loadActivity(page: _activityPage);
        break;
      case 4:
        _loadSessions(page: _sessionsPage);
        break;
      default:
        _loadOverview();
    }
  }

  // ── Account changes ─────────────────────────────────────────────────────

  Future<void> _changeUser(
    Doctor user, {
    bool? isApproved,
    bool? isActive,
    String? accessLevel,
    required String successMessage,
    String? confirmTitle,
    String? confirmBody,
  }) async {
    if (confirmTitle != null) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(confirmTitle),
          content: Text(confirmBody ?? ''),
          actions: [
            GhButton(
              'Cancel',
              variant: GhButtonVariant.secondary,
              onPressed: () => Navigator.of(dialogContext).pop(false),
            ),
            GhButton(
              'Confirm',
              variant: GhButtonVariant.primary,
              onPressed: () => Navigator.of(dialogContext).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }

    try {
      await AdminRepository.instance.updateUser(
        user.id,
        isApproved: isApproved,
        isActive: isActive,
        accessLevel: accessLevel,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(successMessage),
          backgroundColor: GhColors.success(context),
        ),
      );
      await _loadUsers(page: _usersPage);
      await _loadOverview();
    } on ApiException catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error.isNetworkError
                ? 'Account changes need a connection. The console is showing '
                    'the last synced snapshot.'
                : error.message,
          ),
          backgroundColor: GhColors.danger(context),
        ),
      );
    }
  }

  Future<void> _showUserDetail(int id, String email) async {
    _showDetailLoading();
    try {
      final snapshot = await AdminRepository.instance.loadUserDetail(id);
      if (!mounted) return;
      Navigator.of(context).pop(); // dismiss the loading dialog
      final data = snapshot.data;
      final recent = _list(data['recent_activity']);
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${data['full_name'] ?? email}'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (snapshot.fromCache) _cachedBanner(snapshot),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      _fact(dialogContext, 'Email', email),
                      _fact(
                        dialogContext,
                        'Access',
                        '${data['access_level'] ?? 'practitioner'}',
                      ),
                      _fact(
                        dialogContext,
                        'Status',
                        data['is_approved'] == true ? 'Approved' : 'Pending',
                      ),
                      _fact(
                        dialogContext,
                        'Role',
                        '${data['role'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'License',
                        '${data['license_number'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Phone',
                        '${data['phone'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Hospital',
                        '${data['hospital_name'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Joined',
                        _time(data['created_at']),
                      ),
                      _fact(
                        dialogContext,
                        'Actions',
                        _count(data['audit_count']),
                      ),
                      _fact(
                        dialogContext,
                        'Denied',
                        _count(data['denied_count']),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  const GhSectionHeader(
                    'Recent activity',
                    subtitle: 'Actions performed by this account.',
                  ),
                  const SizedBox(height: 8),
                  GhBox(
                    flush: true,
                    child: Column(
                      children: [
                        for (final entry in recent)
                          _activityRow(
                            dialogContext,
                            entry,
                            showBorder: entry != recent.last,
                          ),
                        if (recent.isEmpty)
                          const GhEmptyState(
                            icon: Icons.history,
                            message: 'No activity recorded for this account.',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            GhButton('Close', onPressed: () => Navigator.of(dialogContext).pop()),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageFor(error)),
          backgroundColor: GhColors.danger(context),
        ),
      );
    }
  }

  Future<void> _showPatientDetail(int id, String code) async {
    _showDetailLoading();
    try {
      final snapshot = await AdminRepository.instance.loadPatient(id);
      if (!mounted) return;
      Navigator.of(context).pop();
      final data = snapshot.data;
      final sessions = _list(data['sessions']);
      final audit = _list(data['audit']);
      showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text('${data['full_name'] ?? code}'),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (snapshot.fromCache) _cachedBanner(snapshot),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 20,
                    runSpacing: 12,
                    children: [
                      _fact(dialogContext, 'Code', code),
                      _fact(
                        dialogContext,
                        'Age',
                        '${data['age'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Gender',
                        '${data['gender'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Phone',
                        '${data['phone'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Hospital',
                        '${data['hospital_name'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Language',
                        '${data['preferred_language'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Date of birth',
                        '${data['date_of_birth'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Next of kin',
                        '${data['next_of_kin_name'] ?? '—'}',
                      ),
                      _fact(
                        dialogContext,
                        'Registered',
                        _time(data['created_at']),
                      ),
                    ],
                  ),
                  if (data['address'] != null) ...[
                    const SizedBox(height: 16),
                    _fact(dialogContext, 'Address', '${data['address']}'),
                  ],
                  if (data['notes'] != null) ...[
                    const SizedBox(height: 12),
                    _fact(dialogContext, 'Notes', '${data['notes']}'),
                  ],
                  const SizedBox(height: 20),
                  GhSectionHeader(
                    'Triage sessions',
                    subtitle: '${_count(data['session_count'])} recorded on this record.',
                  ),
                  const SizedBox(height: 8),
                  GhBox(
                    flush: true,
                    child: Column(
                      children: [
                        for (final session in sessions)
                          _sessionRow(
                            dialogContext,
                            session,
                            showBorder: session != sessions.last,
                          ),
                        if (sessions.isEmpty)
                          const GhEmptyState(
                            icon: Icons.monitor_heart_outlined,
                            message: 'No sessions recorded for this patient.',
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  const GhSectionHeader(
                    'Access history',
                    subtitle: 'Who opened this patient record and when.',
                  ),
                  const SizedBox(height: 8),
                  GhBox(
                    flush: true,
                    child: Column(
                      children: [
                        for (final entry in audit)
                          _activityRow(
                            dialogContext,
                            entry,
                            showBorder: entry != audit.last,
                          ),
                        if (audit.isEmpty)
                          const GhEmptyState(
                            icon: Icons.history,
                            message: 'No access recorded for this patient.',
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            GhButton('Close', onPressed: () => Navigator.of(dialogContext).pop()),
          ],
        ),
      );
    } catch (error) {
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_messageFor(error)),
          backgroundColor: GhColors.danger(context),
        ),
      );
    }
  }

  void _showDetailLoading() {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: SizedBox(
          height: 96,
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────

  String _messageFor(Object error) {
    if (error is ApiException) {
      if (error.statusCode == 403) {
        return 'Administrator access is required for this screen.';
      }
      if (error.isNetworkError) {
        return 'No connection, and no snapshot has been saved on this device '
            'yet. Connect once to load the console.';
      }
      return error.message;
    }
    return error.toString();
  }

  static Map<String, dynamic> _map(Object? value) =>
      value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

  static List<Map<String, dynamic>> _list(Object? value) => value is List
      ? value
          .whereType<Map>()
          .map((row) => Map<String, dynamic>.from(row))
          .toList()
      : const [];

  static int _int(Object? value) =>
      value is num ? value.toInt() : int.tryParse('$value') ?? 0;

  static String _count(Object? value) =>
      NumberFormat.decimalPattern().format(_int(value));

  static String _time(Object? iso) {
    final parsed = DateTime.tryParse(iso?.toString() ?? '');
    if (parsed == null) return '—';
    return DateFormat('d MMM yyyy, HH:mm').format(parsed.toLocal());
  }

  static String _shortDate(Object? iso) {
    final text = iso?.toString() ?? '';
    return text.length >= 5 ? text.substring(5) : text;
  }

  GhTone _riskTone(String? level) {
    switch (level) {
      case 'high':
      case 'red':
      case 'emergency':
        return GhTone.danger;
      case 'medium':
      case 'orange':
      case 'urgent':
        return GhTone.attention;
      case 'yellow':
        return GhTone.done;
      case 'low':
      case 'green':
      case 'routine':
        return GhTone.success;
      default:
        return GhTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return PractitionerScaffold(
      currentRoute: '/admin',
      contentBuilder: (context, openDrawer) => Column(
        children: [
          AppHeaderBar(
            title: 'Administration',
            subtitle: 'Accounts, activity and triage oversight',
            onMenuTap: openDrawer,
            actions: [
              AppHeaderIconButton(
                icon: Icons.refresh,
                tooltip: 'Refresh',
                onPressed: _isAdmin ? _refreshCurrent : null,
              ),
            ],
          ),
          Expanded(
            child: _checkingAccess
                ? const Center(child: CircularProgressIndicator())
                : _buildBody(context),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_accessError != null) {
      return AppPage(
        maxWidth: AppContentWidth.wide,
        child: GhBanner(
          _accessError!,
          tone: GhTone.danger,
          icon: Icons.lock_outline,
          actions: [
            GhButton('Retry', onPressed: _checkAccess),
          ],
        ),
      );
    }

    if (!_isAdmin) {
      return const AppPage(
        maxWidth: AppContentWidth.wide,
        child: GhEmptyState(
          icon: Icons.admin_panel_settings_outlined,
          message: 'Administrator access is required to open the console.\n'
              'Ask an administrator to approve or promote this account.',
        ),
      );
    }

    return SingleChildScrollView(
      child: AppPage(
        maxWidth: AppContentWidth.wide,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GhUnderlineTabs(
              labels: _tabs,
              icons: _tabIcons,
              selectedIndex: _tab,
              onSelected: _onTabSelected,
            ),
            const SizedBox(height: 16),
            _buildTab(context),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(BuildContext context) {
    switch (_tab) {
      case 1:
        return _buildUsers(context);
      case 2:
        return _buildPatients(context);
      case 3:
        return _buildActivity(context);
      case 4:
        return _buildSessions(context);
      default:
        return _buildOverview(context);
    }
  }

  // ── Overview ────────────────────────────────────────────────────────────

  Widget _buildOverview(BuildContext context) {
    if (_overviewLoading && _overview == null) {
      return const _LoadingBlock(label: 'Loading system overview…');
    }
    if (_overviewError != null && _overview == null) {
      return _ErrorBlock(message: _overviewError!, onRetry: _loadOverview);
    }
    if (_overview == null) return const SizedBox.shrink();

    final snapshot = _overview!;
    final data = snapshot.data;
    final users = _map(data['users']);
    final patients = _map(data['patients']);
    final triage = _map(data['triage']);
    final activity = _map(data['activity']);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (snapshot.fromCache) _cachedBanner(snapshot),
        if (snapshot.fromCache) const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            GhStatTile(
              label: 'Accounts',
              value: _count(users['total']),
              icon: Icons.people_outline,
              caption: '${_count(users['pending'])} awaiting approval',
              tone: _int(users['pending']) > 0
                  ? GhTone.attention
                  : GhTone.success,
            ),
            GhStatTile(
              label: 'Patients',
              value: _count(patients['total']),
              icon: Icons.person_search_outlined,
            ),
            GhStatTile(
              label: 'Triage points',
              value: _count(triage['total']),
              icon: Icons.monitor_heart_outlined,
              caption: '${_count(triage['today'])} today',
            ),
            GhStatTile(
              label: 'High risk',
              value: _count(triage['high_risk']),
              icon: Icons.warning_amber_outlined,
              tone: GhTone.danger,
            ),
            GhStatTile(
              label: 'Audit events',
              value: _count(activity['total']),
              icon: Icons.history,
              caption: '${_count(activity['denied'])} denied',
              tone: _int(activity['denied']) > 0
                  ? GhTone.attention
                  : GhTone.accent,
            ),
            GhStatTile(
              label: 'Open cases',
              value: _count(triage['open']),
              icon: Icons.folder_open_outlined,
              caption: '${_count(triage['closed'])} closed',
              tone: GhTone.done,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _section(
          context,
          title: 'Triage distribution',
          subtitle: 'Tier and red-flag counts are derived on read, not stored.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _tierRow(context, _map(triage['by_tier'])),
              const SizedBox(height: 12),
              _bandRow(context, triage),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _section(
          context,
          title: 'Triage volume · last 14 days',
          subtitle: 'Daily submissions read straight from the sessions table.',
          child: _trendBars(context, _list(triage['trend'])),
        ),
        const SizedBox(height: 24),
        _section(
          context,
          title: 'Top reported regions',
          subtitle: 'Where the system is being used, by pain point.',
          child: _regionBars(context, _list(triage['by_region'])),
        ),
        const SizedBox(height: 24),
        _section(
          context,
          title: 'System activity',
          subtitle: 'Every recorded event, grouped by kind and outcome.',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _breakdown(context, 'Actions', _map(activity['by_action'])),
              const SizedBox(height: 12),
              _breakdown(context, 'Outcomes', _map(activity['by_outcome'])),
              const SizedBox(height: 12),
              _breakdown(context, 'Actors', _map(activity['by_actor_type'])),
            ],
          ),
        ),
        const SizedBox(height: 24),
        _section(
          context,
          title: 'Recent activity',
          subtitle: 'Newest entries from the patient-data audit trail.',
          child: _recentActivity(context, _list(activity['recent'])),
        ),
        const SizedBox(height: 24),
        _section(
          context,
          title: 'System',
          subtitle: 'Snapshot provenance.',
          child: Wrap(
            spacing: 24,
            runSpacing: 8,
            children: [
              _fact(context, 'Environment', '${data['environment'] ?? '—'}'),
              _fact(context, 'API version', '${data['version'] ?? '—'}'),
              _fact(context, 'Generated', _time(data['generated_at'])),
              _fact(
                context,
                'Snapshot',
                snapshot.fromCache ? 'Cached' : 'Live',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tierRow(BuildContext context, Map<String, dynamic> tiers) {
    const order = ['red', 'orange', 'yellow', 'green'];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final tier in order)
          _metric(
            context,
            label: tier.toUpperCase(),
            value: _count(tiers[tier]),
            tone: _riskTone(tier),
          ),
      ],
    );
  }

  Widget _bandRow(BuildContext context, Map<String, dynamic> triage) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _metric(
          context,
          label: 'HIGH RISK',
          value: _count(triage['high_risk']),
          tone: GhTone.danger,
        ),
        _metric(
          context,
          label: 'MEDIUM RISK',
          value: _count(triage['medium_risk']),
          tone: GhTone.attention,
        ),
        _metric(
          context,
          label: 'LOW RISK',
          value: _count(triage['low_risk']),
          tone: GhTone.success,
        ),
        _metric(
          context,
          label: 'EMERGENCY FLAGS',
          value: _count(_map(triage['by_escalation'])['emergency']),
          tone: GhTone.danger,
        ),
        _metric(
          context,
          label: 'URGENT FLAGS',
          value: _count(_map(triage['by_escalation'])['urgent']),
          tone: GhTone.attention,
        ),
      ],
    );
  }

  Widget _metric(
    BuildContext context, {
    required String label,
    required String value,
    required GhTone tone,
  }) {
    return SizedBox(
      width: 150,
      child: GhBox(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GhType.meta.copyWith(
                color: tone.color(context),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              style: GhType.statValue.copyWith(color: GhColors.fg(context)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trendBars(BuildContext context, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const GhEmptyState(
        icon: Icons.show_chart,
        message: 'No daily volume is available yet.',
      );
    }
    final maxCount = rows
        .map((row) => _int(row['count']))
        .fold<int>(1, (max, count) => count > max ? count : max);
    return GhBox(
      child: SizedBox(
        height: 132,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (final row in rows)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text(
                        _count(row['count']),
                        style: GhType.meta.copyWith(
                          color: GhColors.fgMuted(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        height: 78 * (_int(row['count']) / maxCount).clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                          color: GhColors.accent(context),
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _shortDate(row['date']),
                        style: GhType.meta.copyWith(
                          color: GhColors.fgMuted(context),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _breakdown(
    BuildContext context,
    String title,
    Map<String, dynamic> values,
  ) {
    final entries = values.entries.toList()
      ..sort((a, b) => _int(b.value).compareTo(_int(a.value)));
    if (entries.isEmpty) {
      return _fact(context, title, 'None recorded');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          title.toUpperCase(),
          style: GhType.meta.copyWith(
            color: GhColors.fgMuted(context),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final entry in entries.take(12))
              GhLabel(
                '${entry.key} · ${_count(entry.value)}',
                tone: entry.key == 'denied'
                    ? GhTone.danger
                    : GhTone.neutral,
              ),
          ],
        ),
      ],
    );
  }

  Widget _regionBars(BuildContext context, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const GhEmptyState(
        icon: Icons.map_outlined,
        message: 'No triage points have been recorded yet.',
      );
    }
    final maxCount = rows
        .map((row) => _int(row['count']))
        .fold<int>(1, (max, count) => count > max ? count : max);

    return GhBox(
      flush: true,
      child: Column(
        children: [
          for (final row in rows)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 170,
                    child: Text(
                      '${row['region'] ?? 'Unknown'}',
                      overflow: TextOverflow.ellipsis,
                      style: GhType.body.copyWith(color: GhColors.fg(context)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: Container(
                        height: 8,
                        color: GhColors.surfaceSubtle(context),
                        alignment: Alignment.centerLeft,
                        child: FractionallySizedBox(
                          widthFactor: (_int(row['count']) / maxCount)
                              .clamp(0.02, 1.0),
                          child: Container(color: GhColors.accent(context)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 44,
                    child: Text(
                      _count(row['count']),
                      textAlign: TextAlign.right,
                      style: GhType.meta.copyWith(
                        color: GhColors.fgMuted(context),
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

  Widget _recentActivity(
    BuildContext context,
    List<Map<String, dynamic>> entries,
  ) {
    if (entries.isEmpty) {
      return const GhEmptyState(
        icon: Icons.history,
        message: 'The audit trail is empty.',
      );
    }
    return GhBox(
      flush: true,
      child: Column(
        children: [
          for (final entry in entries)
            _activityRow(context, entry, showBorder: entry != entries.last),
        ],
      ),
    );
  }

  // ── Users ───────────────────────────────────────────────────────────────

  Widget _buildUsers(BuildContext context) {
    final snapshot = _users;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GhTextField(
              controller: _userSearch,
              hint: 'Search email, name or hospital',
              prefixIcon: Icons.search,
              width: 300,
              onChanged: (_) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(
                  const Duration(milliseconds: 350),
                  () => _loadUsers(),
                );
              },
            ),
            GhSelect(
              value: _userStatus,
              options: const [
                GhOption('All accounts'),
                GhOption('Pending approval', 'pending'),
                GhOption('Approved', 'approved'),
                GhOption('Inactive', 'inactive'),
                GhOption('Administrators', 'admin'),
              ],
              onChanged: (value) {
                setState(() => _userStatus = value);
                _loadUsers();
              },
            ),
            GhButton(
              'Refresh',
              icon: Icons.refresh,
              onPressed: () => _loadUsers(page: _usersPage),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_usersLoading && snapshot == null)
          const _LoadingBlock(label: 'Loading accounts…')
        else if (_usersError != null && snapshot == null)
          _ErrorBlock(
            message: _usersError!,
            onRetry: () => _loadUsers(page: _usersPage),
          )
        else if (snapshot == null)
          const SizedBox.shrink()
        else ...[
          if (snapshot.fromCache) _cachedBanner(snapshot),
          if (snapshot.fromCache) const SizedBox(height: 12),
          GhBox(
            header: 'Accounts',
            flush: true,
            headerActions: [
              GhCounter(
                _count(_map(snapshot.data['counts'])['total']),
                tone: GhTone.neutral,
              ),
            ],
            child: _userList(context, _list(snapshot.data['items'])),
          ),
          const SizedBox(height: 12),
          _pagination(
            snapshot.data,
            onPrevious: _usersPage > 1
                ? () => _loadUsers(page: _usersPage - 1)
                : null,
            onNext: _usersPage < _totalPages(snapshot.data)
                ? () => _loadUsers(page: _usersPage + 1)
                : null,
          ),
        ],
      ],
    );
  }

  Widget _userList(BuildContext context, List<Map<String, dynamic>> users) {
    if (users.isEmpty) {
      return const GhEmptyState(
        icon: Icons.people_outline,
        message: 'No accounts match this filter.',
      );
    }
    return Column(
      children: [
        for (final user in users)
          _userRow(context, user, showBorder: user != users.last),
      ],
    );
  }

  Widget _userRow(
    BuildContext context,
    Map<String, dynamic> user, {
    required bool showBorder,
  }) {
    final id = _int(user['id']);
    final isApproved = user['is_approved'] == true;
    final isActive = user['is_active'] != false;
    final isAdmin = user['is_admin'] == true;
    final isSelf = _currentDoctor?.id == id;
    final name = '${user['full_name'] ?? 'Unnamed account'}';
    final email = '${user['email'] ?? ''}';
    final hospital = user['hospital_name']?.toString();
    final role = user['role']?.toString();

    final actions = <Widget>[
      GhButton(
        'Details',
        icon: Icons.open_in_new,
        variant: GhButtonVariant.secondary,
        onPressed: () => _showUserDetail(id, email),
      ),
      if (!isApproved)
        GhButton(
          'Approve',
          variant: GhButtonVariant.primary,
          onPressed: () => _changeUser(
            _doctorFrom(user),
            isApproved: true,
            successMessage: 'Approved $email.',
          ),
        ),
      if (isApproved && isActive && !isSelf)
        GhButton(
          'Deactivate',
          variant: GhButtonVariant.danger,
          onPressed: () => _changeUser(
            _doctorFrom(user),
            isActive: false,
            successMessage: 'Deactivated $email.',
            confirmTitle: 'Deactivate account?',
            confirmBody:
                '$email will be signed out on the next request and cannot '
                'sign in again until reactivated.',
          ),
        ),
      if (isApproved && !isActive)
        GhButton(
          'Reactivate',
          onPressed: () => _changeUser(
            _doctorFrom(user),
            isActive: true,
            successMessage: 'Reactivated $email.',
          ),
        ),
      if (isApproved && !isAdmin)
        GhButton(
          'Make admin',
          onPressed: () => _changeUser(
            _doctorFrom(user),
            accessLevel: 'admin',
            successMessage: 'Promoted $email to administrator.',
            confirmTitle: 'Grant administrator access?',
            confirmBody:
                '$email will be able to approve accounts and read the audit '
                'trail.',
          ),
        ),
      if (isAdmin && !isSelf)
        GhButton(
          'Make practitioner',
          variant: GhButtonVariant.secondary,
          onPressed: () => _changeUser(
            _doctorFrom(user),
            accessLevel: 'practitioner',
            successMessage: 'Removed administrator access from $email.',
          ),
        ),
    ];

    return _adminRow(
      context,
      showBorder: showBorder,
      leading: GhAvatar(name: name, size: 32),
      title: name,
      subtitle: [
        email,
        if (hospital != null && hospital.isNotEmpty) hospital,
        if (role != null && role.isNotEmpty) role,
      ].join(' · '),
      labels: [
        GhLabel(
          isAdmin ? 'Administrator' : 'Practitioner',
          tone: isAdmin ? GhTone.done : GhTone.neutral,
        ),
        GhLabel(
          isApproved ? 'Approved' : 'Pending',
          tone: isApproved ? GhTone.success : GhTone.attention,
        ),
        if (!isActive) const GhLabel('Inactive', tone: GhTone.danger),
        if (isSelf) const GhLabel('You', tone: GhTone.accent),
      ],
      trailing: actions,
    );
  }

  Doctor _doctorFrom(Map<String, dynamic> user) => Doctor(
        id: _int(user['id']),
        email: '${user['email'] ?? ''}',
        fullName: '${user['full_name'] ?? ''}',
        isActive: user['is_active'] != false,
        role: user['role']?.toString(),
        licenseNumber: user['license_number']?.toString(),
        phone: user['phone']?.toString(),
        hospitalName: user['hospital_name']?.toString(),
        isApproved: user['is_approved'] == true,
        accessLevel: '${user['access_level'] ?? 'practitioner'}',
      );

  // ── Activity ────────────────────────────────────────────────────────────

  Widget _buildPatients(BuildContext context) {
    final snapshot = _patients;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GhTextField(
              controller: _patientSearch,
              hint: 'Search code, name, phone or hospital',
              prefixIcon: Icons.search,
              width: 320,
              onChanged: (_) {
                _searchDebounce?.cancel();
                _searchDebounce = Timer(
                  const Duration(milliseconds: 350),
                  () => _loadPatients(),
                );
              },
            ),
            GhSelect(
              value: _patientHasSessions,
              options: const [
                GhOption('All patients'),
                GhOption('With sessions', 'true'),
                GhOption('No sessions', 'false'),
              ],
              onChanged: (value) {
                setState(() => _patientHasSessions = value);
                _loadPatients();
              },
            ),
            GhButton(
              'Refresh',
              icon: Icons.refresh,
              onPressed: () => _loadPatients(page: _patientsPage),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_patientsLoading && snapshot == null)
          const _LoadingBlock(label: 'Loading patient register…')
        else if (_patientsError != null && snapshot == null)
          _ErrorBlock(
            message: _patientsError!,
            onRetry: () => _loadPatients(page: _patientsPage),
          )
        else if (snapshot == null)
          const SizedBox.shrink()
        else ...[
          if (snapshot.fromCache) _cachedBanner(snapshot),
          if (snapshot.fromCache) const SizedBox(height: 12),
          GhBox(
            header: 'Patient register',
            flush: true,
            headerActions: [
              GhCounter(
                _count(_map(snapshot.data['pagination'])['total']),
                tone: GhTone.neutral,
              ),
            ],
            child: _patientList(context, _list(snapshot.data['items'])),
          ),
          const SizedBox(height: 12),
          _pagination(
            snapshot.data,
            onPrevious: _patientsPage > 1
                ? () => _loadPatients(page: _patientsPage - 1)
                : null,
            onNext: _patientsPage < _totalPages(snapshot.data)
                ? () => _loadPatients(page: _patientsPage + 1)
                : null,
          ),
        ],
      ],
    );
  }

  Widget _patientList(BuildContext context, List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      return const GhEmptyState(
        icon: Icons.person_search_outlined,
        message: 'No patients match this filter.',
      );
    }
    return Column(
      children: [
        for (final row in rows)
          _patientRow(context, row, showBorder: row != rows.last),
      ],
    );
  }

  Widget _patientRow(
    BuildContext context,
    Map<String, dynamic> row, {
    required bool showBorder,
  }) {
    final id = _int(row['id']);
    final code = '${row['anonymous_code'] ?? ''}';
    final name = '${row['full_name'] ?? 'Anonymous patient'}';
    final detail = [
      code,
      if (row['age'] != null) '${row['age']} yrs',
      if (row['gender'] != null) '${row['gender']}',
      if (row['phone'] != null) '${row['phone']}',
    ].join(' · ');
    final sessions = _int(row['session_count']);
    final risk = row['last_risk_score'];
    final riskValue = risk is num ? risk.toDouble() : null;

    return _adminRow(
      context,
      showBorder: showBorder,
      leading: GhAvatar(name: name, size: 32),
      title: name,
      subtitle: detail,
      labels: [
        GhLabel(
          '$sessions session${sessions == 1 ? '' : 's'}',
          tone: sessions > 0 ? GhTone.done : GhTone.neutral,
        ),
        if (riskValue != null)
          GhLabel(
            'Risk ${riskValue.toStringAsFixed(2)}',
            tone: riskValue >= 0.7
                ? GhTone.danger
                : riskValue >= 0.4
                    ? GhTone.attention
                    : GhTone.success,
          ),
      ],
      trailing: [
        GhButton(
          'Details',
          icon: Icons.open_in_new,
          variant: GhButtonVariant.secondary,
          onPressed: () => _showPatientDetail(id, code),
        ),
      ],
    );
  }

  Widget _buildActivity(BuildContext context) {
    final snapshot = _activity;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GhSelect(
              value: _activityAction,
              options: const [
                GhOption('All actions'),
                GhOption('Read', 'read'),
                GhOption('List', 'list'),
                GhOption('Aggregate', 'aggregate'),
                GhOption('Create', 'create'),
                GhOption('Update', 'update'),
                GhOption('Delete', 'delete'),
              ],
              onChanged: (value) {
                setState(() => _activityAction = value);
                _loadActivity();
              },
            ),
            GhSelect(
              value: _activityOutcome,
              options: const [
                GhOption('All outcomes'),
                GhOption('Allowed', 'allowed'),
                GhOption('Denied', 'denied'),
              ],
              onChanged: (value) {
                setState(() => _activityOutcome = value);
                _loadActivity();
              },
            ),
            GhButton(
              'Refresh',
              icon: Icons.refresh,
              onPressed: () => _loadActivity(page: _activityPage),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_activityLoading && snapshot == null)
          const _LoadingBlock(label: 'Loading activity…')
        else if (_activityError != null && snapshot == null)
          _ErrorBlock(
            message: _activityError!,
            onRetry: () => _loadActivity(page: _activityPage),
          )
        else if (snapshot == null)
          const SizedBox.shrink()
        else ...[
          if (snapshot.fromCache) _cachedBanner(snapshot),
          if (snapshot.fromCache) const SizedBox(height: 12),
          GhBox(
            header: 'Audit trail',
            flush: true,
            headerActions: [
              GhCounter(
                _count(_map(snapshot.data['pagination'])['total']),
                tone: GhTone.neutral,
              ),
            ],
            child: _activityList(context, _list(snapshot.data['items'])),
          ),
          const SizedBox(height: 12),
          _pagination(
            snapshot.data,
            onPrevious: _activityPage > 1
                ? () => _loadActivity(page: _activityPage - 1)
                : null,
            onNext: _activityPage < _totalPages(snapshot.data)
                ? () => _loadActivity(page: _activityPage + 1)
                : null,
          ),
        ],
      ],
    );
  }

  Widget _activityList(
    BuildContext context,
    List<Map<String, dynamic>> entries,
  ) {
    if (entries.isEmpty) {
      return const GhEmptyState(
        icon: Icons.history,
        message: 'No activity matches this filter.',
      );
    }
    return Column(
      children: [
        for (final entry in entries)
          _activityRow(
            context,
            entry,
            showBorder: entry != entries.last,
          ),
      ],
    );
  }

  Widget _activityRow(
    BuildContext context,
    Map<String, dynamic> entry, {
    required bool showBorder,
  }) {
    final outcome = '${entry['outcome'] ?? 'allowed'}';
    final actor = entry['actor_label']?.toString();
    final actorType = '${entry['actor_type'] ?? 'anonymous'}';
    final detail = entry['detail']?.toString();
    final resource = '${entry['resource_type'] ?? 'resource'}';
    final resourceId = entry['resource_id']?.toString();

    return _adminRow(
      context,
      showBorder: showBorder,
      leading: Icon(
        outcome == 'denied' ? Icons.block : Icons.history,
        size: 18,
        color: outcome == 'denied'
            ? GhColors.danger(context)
            : GhColors.fgMuted(context),
      ),
      title: '${entry['action'] ?? 'action'} · $resource'
          '${resourceId == null ? '' : ' #$resourceId'}',
      subtitle: [
        actor ?? actorType,
        _time(entry['created_at']),
        if (detail != null && detail.isNotEmpty) detail,
      ].join(' · '),
      labels: [
        GhLabel(
          outcome,
          tone: outcome == 'denied' ? GhTone.danger : GhTone.success,
        ),
      ],
      trailing: const [],
    );
  }

  // ── Sessions ────────────────────────────────────────────────────────────

  Widget _buildSessions(BuildContext context) {
    final snapshot = _sessions;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GhSelect(
              value: _sessionRisk,
              options: const [
                GhOption('All risk levels'),
                GhOption('High risk', 'high'),
                GhOption('Medium risk', 'medium'),
                GhOption('Low risk', 'low'),
              ],
              onChanged: (value) {
                setState(() => _sessionRisk = value);
                _loadSessions();
              },
            ),
            GhSelect(
              value: _sessionStatus,
              options: const [
                GhOption('All statuses'),
                GhOption('Open', 'open'),
                GhOption('Closed', 'closed'),
              ],
              onChanged: (value) {
                setState(() => _sessionStatus = value);
                _loadSessions();
              },
            ),
            GhButton(
              'Refresh',
              icon: Icons.refresh,
              onPressed: () => _loadSessions(page: _sessionsPage),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (_sessionsLoading && snapshot == null)
          const _LoadingBlock(label: 'Loading sessions…')
        else if (_sessionsError != null && snapshot == null)
          _ErrorBlock(
            message: _sessionsError!,
            onRetry: () => _loadSessions(page: _sessionsPage),
          )
        else if (snapshot == null)
          const SizedBox.shrink()
        else ...[
          if (snapshot.fromCache) _cachedBanner(snapshot),
          if (snapshot.fromCache) const SizedBox(height: 12),
          GhBox(
            header: 'Triage sessions',
            flush: true,
            headerActions: [
              GhCounter(
                _count(_map(snapshot.data['pagination'])['total']),
                tone: GhTone.neutral,
              ),
            ],
            child: _sessionList(context, _list(snapshot.data['items'])),
          ),
          const SizedBox(height: 12),
          _pagination(
            snapshot.data,
            onPrevious: _sessionsPage > 1
                ? () => _loadSessions(page: _sessionsPage - 1)
                : null,
            onNext: _sessionsPage < _totalPages(snapshot.data)
                ? () => _loadSessions(page: _sessionsPage + 1)
                : null,
          ),
        ],
      ],
    );
  }

  Widget _sessionList(
    BuildContext context,
    List<Map<String, dynamic>> sessions,
  ) {
    if (sessions.isEmpty) {
      return const GhEmptyState(
        icon: Icons.monitor_heart_outlined,
        message: 'No sessions match this filter.',
      );
    }
    return Column(
      children: [
        for (final session in sessions)
          _sessionRow(context, session, showBorder: session != sessions.last),
      ],
    );
  }

  Widget _sessionRow(
    BuildContext context,
    Map<String, dynamic> session, {
    required bool showBorder,
  }) {
    final risk = '${session['risk_level'] ?? 'unknown'}';
    final tier = '${session['tier'] ?? 'green'}';
    final escalation = '${session['escalation'] ?? 'routine'}';
    final status = '${session['status'] ?? 'open'}';
    final code = session['patient_code']?.toString();

    return _adminRow(
      context,
      showBorder: showBorder,
      leading: GhDot(tone: _riskTone(risk), size: 9),
      title: '${session['body_region'] ?? 'Unknown region'} · '
          '${session['pain_type'] ?? 'pain'} · ${session['severity'] ?? '?'}/10',
      subtitle: [
        code ?? 'anonymous',
        if (session['visit_id'] != null) 'visit ${session['visit_id']}',
        _time(session['created_at']),
      ].join(' · '),
      labels: [
        GhLabel(risk.toUpperCase(), tone: _riskTone(risk)),
        GhLabel(tier.toUpperCase(), tone: _riskTone(tier)),
        GhLabel(
          escalation,
          tone: _riskTone(escalation),
        ),
        GhLabel(
          status,
          tone: status == 'closed' ? GhTone.neutral : GhTone.done,
        ),
      ],
      trailing: const [],
    );
  }

  // ── Shared pieces ───────────────────────────────────────────────────────

  Widget _section(
    BuildContext context, {
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GhSectionHeader(title, subtitle: subtitle),
        const SizedBox(height: 10),
        child,
      ],
    );
  }

  Widget _fact(BuildContext context, String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label.toUpperCase(),
          style: GhType.meta.copyWith(
            color: GhColors.fgMuted(context),
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: GhType.bodyStrong.copyWith(color: GhColors.fg(context)),
        ),
      ],
    );
  }

  Widget _cachedBanner(AdminSnapshot snapshot) {
    final at = snapshot.cachedAt;
    return GhBanner(
      at == null
          ? 'Showing the last saved snapshot. Connect to refresh.'
          : 'Showing the snapshot saved ${_time(at.toIso8601String())}. '
              'Connect to refresh.',
      tone: GhTone.attention,
      icon: Icons.cloud_off_outlined,
      actions: [
        GhButton('Retry', onPressed: _refreshCurrent),
      ],
    );
  }

  int _totalPages(Map<String, dynamic> data) {
    final pagination = _map(data['pagination']);
    final pages = _int(pagination['total_pages']);
    return pages < 1 ? 1 : pages;
  }

  Widget _pagination(
    Map<String, dynamic> data, {
    required VoidCallback? onPrevious,
    required VoidCallback? onNext,
  }) {
    final pagination = _map(data['pagination']);
    final page = _int(pagination['page']);
    final pages = _totalPages(data);
    final total = _int(pagination['total']);

    return Row(
      children: [
        Expanded(
          child: Text(
            '${_count(total)} result(s) · page $page of $pages',
            style: GhType.meta.copyWith(color: GhColors.fgMuted(context)),
          ),
        ),
        GhButton(
          'Previous',
          icon: Icons.chevron_left,
          variant: GhButtonVariant.secondary,
          onPressed: onPrevious,
        ),
        const SizedBox(width: 8),
        GhButton(
          'Next',
          icon: Icons.chevron_right,
          variant: GhButtonVariant.secondary,
          onPressed: onNext,
        ),
      ],
    );
  }

  Widget _adminRow(
    BuildContext context, {
    required Widget leading,
    required String title,
    required String subtitle,
    required List<Widget> labels,
    required List<Widget> trailing,
    required bool showBorder,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: showBorder
            ? Border(bottom: BorderSide(color: GhColors.borderMuted(context)))
            : null,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 640;
          final text = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading,
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      style: GhType.bodyStrong.copyWith(
                        color: GhColors.fg(context),
                      ),
                    ),
                    if (subtitle.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          subtitle,
                          style: GhType.meta.copyWith(
                            color: GhColors.fgMuted(context),
                          ),
                        ),
                      ),
                    if (labels.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: labels,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );

          if (stacked) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                text,
                if (trailing.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Wrap(spacing: 6, runSpacing: 6, children: trailing),
                ],
              ],
            );
          }

          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: text),
              if (trailing.isNotEmpty) ...[
                const SizedBox(width: 12),
                Wrap(spacing: 6, runSpacing: 6, children: trailing),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _LoadingBlock extends StatelessWidget {
  const _LoadingBlock({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 48),
      child: Column(
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 12),
          Text(
            label,
            style: GhType.meta.copyWith(color: GhColors.fgMuted(context)),
          ),
        ],
      ),
    );
  }
}

class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return GhBanner(
      message,
      tone: GhTone.danger,
      icon: Icons.error_outline,
      actions: [
        GhButton('Retry', onPressed: onRetry),
      ],
    );
  }
}
