import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_page_route.dart';
import '../../auth/ui/login_screen.dart';
import '../../../core/network/auth_service.dart';
import 'practitioner_dashboard_screen.dart';
import 'patient_overview_pane.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
// 🌟 ADDED: Import for the new Session History screen
import '../../history/ui/practitioner_session_history_screen.dart';
import '../../profile/ui/practitioner_profile_screen.dart';

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

  @override
  void initState() {
    super.initState();
    _loadDoctor();
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
          // ── Logo & Brand ─────────────────────────────────────────────
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),

          // ── Navigation Menu ─────────────────────────────────────────
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
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
                  icon: Icons.medical_services_outlined,
                  label: 'Triage Sessions',
                  route: '/sessions',
                ),
                _buildNavItem(
                  context,
                  icon: Icons.assessment_outlined,
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
                const Divider(height: 24, color: Color(0xFFE2E8F0)),
                _buildNavItem(
                  context,
                  icon: Icons.person_outline,
                  label: 'Profile',
                  route: '/profile',
                  onTap: () => _navigateToProfile(context),
                ),
                _buildNavItem(
                  context,
                  icon: Icons.settings_outlined,
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

          // ── User Profile & Logout ────────────────────────────────────
          _buildFooter(context),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: const BoxDecoration(
              color: Color(0xFF6D28D9),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.medical_services,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Simtack',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              Text(
                'Practitioner',
                style: TextStyle(
                  fontSize: 11,
                  color: Color(0xFF64748B),
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            if (Scaffold.maybeOf(context)?.isDrawerOpen ?? false) {
              Navigator.of(context).pop();
            }
            onTap?.call();
            if (onTap == null) _navigateToRoute(context, route);
          },
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isActive
                  ? const Color(0xFF6D28D9).withOpacity(0.10)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isActive
                      ? const Color(0xFF6D28D9)
                      : AppPalette.textMuted(context),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: isActive
                          ? FontWeight.w600
                          : FontWeight.w500,
                      color: isActive
                          ? const Color(0xFF6D28D9)
                          : AppPalette.textPrimary(context),
                    ),
                  ),
                ),
                if (isActive)
                  Container(
                    width: 4,
                    height: 20,
                    decoration: const BoxDecoration(
                      color: Color(0xFF6D28D9),
                      borderRadius: BorderRadius.horizontal(
                        left: Radius.circular(2),
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
    final displayName = _doctorName?.trim().isNotEmpty == true ? _doctorName!.trim() : 'Dr. Practitioner';
    final displayEmail = _doctorEmail?.trim().isNotEmpty == true ? _doctorEmail!.trim() : 'doctor@simtack.com';
    final displayHospital = _hospitalName?.trim().isNotEmpty == true ? _hospitalName!.trim() : null;

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
                child: Icon(
                  Icons.person,
                  color: Colors.white,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (displayHospital != null)
                      Text(
                        displayHospital,
                        style: TextStyle(
                          fontSize: 11,
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                    Text(
                      displayEmail,
                      style: TextStyle(
                        fontSize: 11,
                        color: AppPalette.textMuted(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),
          // Logout button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(Icons.logout, size: 16),
              label: const Text('Logout'),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFFDC2626),
                side: const BorderSide(color: Color(0xFFDC2626)),
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
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
          AppPageRoute(builder: (_) => const PractitionerSessionHistoryScreen()),
        );
        break;
      case '/settings':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const AccessibilitySettingsScreen(),
          ),
        );
        break;
      case '/profile':
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => const PractitionerProfileScreen(),
          ),
        );
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This screen is under construction'),
            backgroundColor: Color(0xFF6D28D9),
          ),
        );
    }
  }

  void _navigateToProfile(BuildContext context) {
    _navigateToRoute(context, '/profile');
  }

  void _scanQR(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('QR Scanner - Coming soon'),
        backgroundColor: Color(0xFF6D28D9),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Logout'),
        content: const Text('Are you sure you want to logout?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Logout'),
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