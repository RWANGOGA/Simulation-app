import 'package:flutter/material.dart';
import '../../../l10n/app_localizations.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_page_route.dart';
import '../../auth/ui/login_screen.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/network/api_client.dart';
import 'practitioner_dashboard_screen.dart';
import 'patient_overview_pane.dart';
import 'reports_screen.dart';

/// Shared shell for the practitioner screens: sidebar sits fixed in a Row on
/// wide screens, but on narrow screens a fixed 260px sidebar alongside
/// content leaves almost no room to render anything usably — so instead it
/// becomes a slide-out Drawer, opened via the menu button `contentBuilder`
/// receives in place of the fixed sidebar.
class PractitionerScaffold extends StatelessWidget {
  final String currentRoute;
  final Widget Function(BuildContext context, VoidCallback? openDrawer) contentBuilder;

  const PractitionerScaffold({
    super.key,
    required this.currentRoute,
    required this.contentBuilder,
  });

  static const double _breakpoint = 900;

  @override
  Widget build(BuildContext context) {
    final isWide = MediaQuery.of(context).size.width >= _breakpoint;
    if (isWide) {
      return Scaffold(
        backgroundColor: AppPalette.scaffold(context),
        body: Row(
          children: [
            PractitionerSidebar(currentRoute: currentRoute),
            Expanded(child: contentBuilder(context, null)),
          ],
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      drawer: Drawer(
        width: 260,
        child: PractitionerSidebar(currentRoute: currentRoute),
      ),
      body: Builder(
        builder: (innerContext) => contentBuilder(
          innerContext,
          () => Scaffold.of(innerContext).openDrawer(),
        ),
      ),
    );
  }
}

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
  Doctor? _doctor;
  bool _isLoadingUser = true;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  Future<void> _loadUserData() async {
    try {
      final doctor = await AuthService.instance.getCurrentDoctor();
      if (mounted) {
        setState(() {
          _doctor = doctor;
          _isLoadingUser = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoadingUser = false);
      }
    }
  }

  void _navigateTo(String route) {
    Widget screen;
    switch (route) {
      case '/dashboard':
        screen = const PractitionerDashboardScreen();
        break;
      case '/patients':
        screen = const PatientOverviewScreen();
        break;
      case '/reports':
        screen = const ReportsScreen();
        break;
      default:
        // Triage Sessions / Settings / Help have no screen yet.
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppLocalizations.of(context)!.comingSoonMessage)),
        );
        return;
    }
    Navigator.of(context).pushAndRemoveUntil(
      AppPageRoute(builder: (_) => screen),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 20,
            offset: const Offset(4, 0),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
                    ),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Color(0x406D28D9), blurRadius: 10, offset: Offset(0, 3)),
                    ],
                  ),
                  child: const Icon(
                    Icons.medical_services,
                    color: Colors.white,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Simtack',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    Text(
                      AppLocalizations.of(context)!.sidebarRoleLabel,
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _buildNavItem(context, Icons.dashboard_outlined, AppLocalizations.of(context)!.navDashboard, '/dashboard'),
                _buildNavItem(context, Icons.people_outline, AppLocalizations.of(context)!.navPatients, '/patients'),
                _buildNavItem(context, Icons.medical_services_outlined, AppLocalizations.of(context)!.navTriageSessions, '/sessions'),
                _buildNavItem(context, Icons.assessment_outlined, AppLocalizations.of(context)!.navReports, '/reports'),
                const Divider(height: 24, color: Color(0xFFE2E8F0)),
                _buildNavItem(context, Icons.settings_outlined, AppLocalizations.of(context)!.navSettings, '/settings'),
                _buildNavItem(context, Icons.help_outline, AppLocalizations.of(context)!.navHelpSupport, '/help'),
              ],
            ),
          ),

          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildNavItem(BuildContext context, IconData icon, String label, String route) {
    final isActive = widget.currentRoute == route;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _navigateTo(route),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF6D28D9).withOpacity(0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: Border(
                left: BorderSide(
                  color: isActive ? const Color(0xFF6D28D9) : Colors.transparent,
                  width: 3,
                ),
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFF6D28D9).withOpacity(0.15) : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 18, color: isActive ? const Color(0xFF6D28D9) : AppPalette.textMuted(context)),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                      color: isActive ? const Color(0xFF6D28D9) : AppPalette.textPrimary(context),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppPalette.subtleFill(context),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Color(0xFF6D28D9),
                child: Icon(Icons.person, color: Colors.white, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _isLoadingUser
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppLocalizations.of(context)!.loadingEllipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                          ),
                          const Text(
                            '',
                            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                          ),
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _doctor?.fullName ?? AppLocalizations.of(context)!.unknownLabel,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1E293B)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            _doctor?.email ?? '',
                            style: TextStyle(fontSize: 11, color: AppPalette.textMuted(context)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () async {
                await AuthService.instance.logout();
                if (context.mounted) {
                  Navigator.of(context).pushAndRemoveUntil(
                    AppPageRoute(builder: (_) => const LoginScreen()),
                    (route) => false,
                  );
                }
              },
              icon: const Icon(Icons.logout, size: 16),
              label: Text(AppLocalizations.of(context)!.logoutButton),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
