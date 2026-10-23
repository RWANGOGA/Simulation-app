import 'package:flutter/material.dart';
import '../../../core/offline/local_database.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/github_kit.dart';
import '../../../core/theme/github_palette.dart';
import '../../auth/ui/login_screen.dart';
import '../../../core/network/auth_service.dart';
import 'practitioner_dashboard_screen.dart';
import 'patient_overview_pane.dart';
import 'reports_screen.dart';
import 'qr_scan_screen.dart';
import '../../report/ui/clinical_report_screen.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
import '../../history/ui/practitioner_session_history_screen.dart';
import '../../profile/ui/practitioner_profile_screen.dart';

/// The practitioner console's left navigation, in GitHub's sidebar idiom:
/// a white rail separated by a one-pixel border, small section captions, and
/// current-page rows tinted with the accent colour.
///
/// The colours come from `GhColors` rather than `AppPalette` on purpose — this
/// rail is the practitioner's workspace, and it is meant to read as console
/// chrome, not as a patient-facing card.
class PractitionerSidebar extends StatefulWidget {
  final String currentRoute;

  const PractitionerSidebar({
    super.key,
    required this.currentRoute,
  });

  @override
  State<PractitionerSidebar> createState() => _PractitionerSidebarState();
}

class _PractitionerSidebarState extends State<PractitionerSidebar> {
  String? _doctorName;
  String? _doctorEmail;
  String? _hospitalName;
  int? _pendingSync;

  @override
  void initState() {
    super.initState();
    _loadDoctor();
    _loadPendingSync();
  }

  Future<void> _loadDoctor() async {
    try {
      final doctor = await AuthService.instance.getCurrentDoctor();
      if (mounted) {
        setState(() {
          _doctorName = doctor.fullName;
          _doctorEmail = doctor.email;
          _hospitalName = doctor.hospitalName;
        });
      }
    } catch (_) {
      // Keep fallbacks if the fetch fails
    }
  }

  /// How many records the device still owes the server (or would, if there
  /// were one). Shown as a status line so a practitioner knows their work is
  /// safe before they close the app.
  Future<void> _loadPendingSync() async {
    try {
      final db = await LocalDatabase.open();
      final pending = await db.read((db) => db.pendingUploadCount);
      if (mounted) setState(() => _pendingSync = pending);
    } catch (_) {
      // The status line simply stays hidden if the store cannot be read.
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 264,
      decoration: BoxDecoration(
        color: GhColors.surface(context),
        border: Border(
          right: BorderSide(color: GhColors.border(context)),
        ),
      ),
      child: Column(
        children: [
          _buildHeader(context),
          const GhRule(),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _sectionLabel(context, 'Workspace'),
                _buildNavItem(
                  context,
                  icon: Icons.dashboard_outlined,
                  label: 'Dashboard',
                  route: '/dashboard',
                ),
                _buildNavItem(
                  context,
                  icon: Icons.people_outline,
                  label: 'Patients',
                  route: '/patients',
                ),
                _buildNavItem(
                  context,
                  icon: Icons.monitor_heart_outlined,
                  label: 'Triage Sessions',
                  route: '/sessions',
                ),
                _buildNavItem(
                  context,
                  icon: Icons.insert_chart_outlined,
                  label: 'Reports',
                  route: '/reports',
                ),
                _buildNavItem(
                  context,
                  icon: Icons.qr_code_scanner,
                  label: 'Scan QR',
                  route: '/scan',
                  onTap: () => _scanQR(context),
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: GhRule(),
                ),
                _sectionLabel(context, 'Account'),
                _buildNavItem(
                  context,
                  icon: Icons.person_outline,
                  label: 'Profile',
                  route: '/profile',
                  onTap: () => _navigateToProfile(context),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.tune,
                  label: 'Settings',
                  route: '/settings',
                ),
                _buildNavItem(
                  context,
                  icon: Icons.help_outline,
                  label: 'Help & Support',
                  route: '/help',
                ),
              ],
            ),
          ),
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
      child: Text(
        label.toUpperCase(),
        style: GhType.meta.copyWith(
          color: GhColors.fgMuted(context),
          fontWeight: FontWeight.w600,
          fontSize: 11,
          letterSpacing: 0.6,
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: GhColors.headerBg(context),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Icon(
              Icons.monitor_heart_outlined,
              size: 16,
              color: GhColors.headerFg(context),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Simtack',
                  overflow: TextOverflow.ellipsis,
                  style: GhType.bodyStrong.copyWith(
                    color: GhColors.fg(context),
                  ),
                ),
                Text(
                  'Practitioner',
                  overflow: TextOverflow.ellipsis,
                  style: GhType.meta.copyWith(
                    color: GhColors.fgMuted(context),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem(
    BuildContext context, {
    required IconData icon,
    required String label,
    required String route,
    VoidCallback? onTap,
  }) {
    final isActive = widget.currentRoute == route;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      child: Material(
        color: isActive ? GhColors.accentSubtle(context) : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          borderRadius: BorderRadius.circular(6),
          hoverColor: GhColors.surfaceHover(context),
          onTap: () {
            if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
              Navigator.of(context).pop();
            }
            onTap?.call();
            if (onTap == null) _navigateToRoute(context, route);
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isActive
                      ? GhColors.accent(context)
                      : GhColors.fgMuted(context),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: GhType.body.copyWith(
                      color: isActive
                          ? GhColors.accent(context)
                          : GhColors.fg(context),
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    final displayName = _doctorName?.trim().isNotEmpty == true
        ? _doctorName!.trim()
        : 'Dr. Practitioner';
    final displayEmail = _doctorEmail?.trim().isNotEmpty == true
        ? _doctorEmail!.trim()
        : 'doctor@simtack.com';
    final displayHospital =
        _hospitalName?.trim().isNotEmpty == true ? _hospitalName!.trim() : null;
    final pending = _pendingSync;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: GhColors.surfaceSubtle(context),
        border: Border(top: BorderSide(color: GhColors.border(context))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              GhAvatar(name: displayName, size: 28),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      overflow: TextOverflow.ellipsis,
                      style: GhType.meta.copyWith(
                        color: GhColors.fg(context),
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                    Text(
                      displayHospital ?? displayEmail,
                      overflow: TextOverflow.ellipsis,
                      style: GhType.meta.copyWith(
                        color: GhColors.fgMuted(context),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (pending != null) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                GhDot(
                  size: 7,
                  tone: pending == 0 ? GhTone.success : GhTone.attention,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    pending == 0
                        ? 'Everything saved on this device'
                        : '$pending waiting to sync',
                    overflow: TextOverflow.ellipsis,
                    style: GhType.meta.copyWith(
                      color: GhColors.fgMuted(context),
                      fontSize: 11,
                    ),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 10),
          GhButton(
            'Logout',
            icon: Icons.logout,
            variant: GhButtonVariant.secondary,
            expanded: true,
            onPressed: () => _logout(context),
          ),
        ],
      ),
    );
  }

  void _navigateToRoute(BuildContext context, String route) {
    switch (route) {
      case '/dashboard':
        Navigator.of(context).pushAndRemoveUntil(
          AppPageRoute(builder: (_) => const PractitionerDashboardScreen()),
          (route) => false,
        );
        break;
      case '/patients':
        Navigator.of(context).push(
          AppPageRoute(builder: (_) => const PatientOverviewScreen()),
        );
        break;
      case '/sessions':
        Navigator.of(context).push(
          AppPageRoute(
              builder: (_) => const PractitionerSessionHistoryScreen()),
        );
        break;
      case '/reports':
        Navigator.of(context).push(
          AppPageRoute(builder: (_) => const ReportsScreen()),
        );
        break;
      case '/settings':
        Navigator.of(context).push(
          AppPageRoute(builder: (_) => const AccessibilitySettingsScreen()),
        );
        break;
      case '/profile':
        Navigator.of(context).push(
          AppPageRoute(builder: (_) => const PractitionerProfileScreen()),
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$route is not built yet'),
            backgroundColor: GhColors.attention(context),
          ),
        );
    }
  }

  void _navigateToProfile(BuildContext context) {
    _navigateToRoute(context, '/profile');
  }

  Future<void> _scanQR(BuildContext context) async {
    final code = await Navigator.of(context).push<String>(
      AppPageRoute(builder: (_) => const QrScanScreen()),
    );
    if (code == null || !context.mounted) return;
    await Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ClinicalReportScreen(
          patientId: code,
          practitionerMode: true,
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          GhButton(
            'Cancel',
            variant: GhButtonVariant.secondary,
            onPressed: () => Navigator.of(dialogContext).pop(false),
          ),
          GhButton(
            'Logout',
            variant: GhButtonVariant.danger,
            onPressed: () => Navigator.of(dialogContext).pop(true),
          ),
        ],
      ),
    );

    if (confirmed == true && context.mounted) {
      await AuthService.instance.logout();
      if (context.mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          AppPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }
}
