import 'package:flutter/material.dart';

import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/app_palette.dart';
import '../../auth/ui/login_screen.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
import '../../dashboard/ui/practitioner_sidebar.dart';

class PractitionerProfileScreen extends StatefulWidget {
  const PractitionerProfileScreen({super.key});

  @override
  State<PractitionerProfileScreen> createState() => _PractitionerProfileScreenState();
}

class _PractitionerProfileScreenState extends State<PractitionerProfileScreen> {
  Doctor? _doctor;
  bool _isLoading = true;
  String? _error;

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
          _doctor = doctor;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load profile.';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _logout() async {
    await AuthService.instance.logout();
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      AppPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      body: Row(
        children: [
          const PractitionerSidebar(currentRoute: '/profile'),
          Expanded(
            child: Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  decoration: BoxDecoration(
                    color: AppPalette.surface(context),
                    border: Border(bottom: BorderSide(color: AppPalette.border(context))),
                  ),
                  child: Row(
                    children: [
                      Text(
                        'My Profile',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF6D28D9)))
                      : _error != null
                          ? Center(
                              child: Text(
                                _error!,
                                style: const TextStyle(color: Color(0xFFDC2626)),
                              ),
                            )
                      : SingleChildScrollView(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            children: [
                              _buildIdentityCard(),
                              const SizedBox(height: 24),
                              _buildProfessionalCard(),
                              const SizedBox(height: 24),
                              _buildActions(),
                            ],
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

  Widget _buildIdentityCard() {
    final initials = _doctor?.fullName.isNotEmpty == true
        ? _doctor!.fullName.trim().split(' ').take(2).map((w) => w[0]).join().toUpperCase()
        : '?';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        children: [
          CircleAvatar(
            radius: 40,
            backgroundColor: const Color(0xFF6D28D9),
            child: Text(
              initials,
              style: const TextStyle(fontSize: 28, color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            _doctor?.fullName ?? 'Unknown',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            _doctor?.email ?? '',
            style: TextStyle(fontSize: 14, color: AppPalette.textMuted(context)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildProfessionalCard() {
    final fields = <String, String?>{
      'Role': _doctor?.role,
      'License Number': _doctor?.licenseNumber,
      'Phone': _doctor?.phone,
      'Hospital': _doctor?.hospitalName,
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppPalette.border(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Professional Details',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
          ),
          const SizedBox(height: 16),
          ...fields.entries.map((entry) {
            final value = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 140,
                    child: Text(
                      entry.key,
                      style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context), fontWeight: FontWeight.w500),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      value?.isNotEmpty == true ? value! : 'Not set',
                      style: TextStyle(fontSize: 14, color: AppPalette.textPrimary(context)),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _buildActions() {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const AccessibilitySettingsScreen()),
              );
            },
            icon: const Icon(Icons.tune, size: 18),
            label: const Text('Display & Accessibility'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppPalette.surface(context),
              foregroundColor: const Color(0xFF6D28D9),
              side: BorderSide(color: AppPalette.border(context)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _logout,
            icon: const Icon(Icons.logout, size: 18),
            label: const Text('Sign out'),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFFDC2626),
              side: const BorderSide(color: Color(0xFFDC2626)),
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ),
      ],
    );
  }
}
