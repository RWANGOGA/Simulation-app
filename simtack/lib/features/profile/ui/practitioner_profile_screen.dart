import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_header_bar.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../../../core/theme/app_page_route.dart';
import '../../dashboard/ui/practitioner_dashboard_screen.dart';
import '../../dashboard/ui/patient_overview_pane.dart';
import '../../history/ui/practitioner_session_history_screen.dart';
import '../../settings/ui/accessibility_settings_screen.dart';

class PractitionerProfileScreen extends StatefulWidget {
  const PractitionerProfileScreen({super.key});

  @override
  State<PractitionerProfileScreen> createState() => _PractitionerProfileScreenState();
}

class _PractitionerProfileScreenState extends State<PractitionerProfileScreen> {
  bool _isLoading = true;
  bool _isSaving = false;
  bool _isEditing = false;
  String? _errorMessage;

  final _formKey = GlobalKey<FormState>();
  final _fullNameController = TextEditingController();
  final _roleController = TextEditingController();
  final _licenseNumberController = TextEditingController();
  final _phoneController = TextEditingController();
  final _hospitalNameController = TextEditingController();
  DateTime? _dateOfBirth;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void dispose() {
    _fullNameController.dispose();
    _roleController.dispose();
    _licenseNumberController.dispose();
    _phoneController.dispose();
    _hospitalNameController.dispose();
    super.dispose();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    try {
      final doctor = await AuthService.instance.getCurrentDoctor();
      if (!mounted) return;
      setState(() {
        _fullNameController.text = doctor.fullName;
        _roleController.text = doctor.role ?? '';
        _licenseNumberController.text = doctor.licenseNumber ?? '';
        _phoneController.text = doctor.phone ?? '';
        _hospitalNameController.text = doctor.hospitalName ?? '';
        _dateOfBirth = null; // date_of_birth not returned by current /me endpoint shape in Doctor model
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSaving = true);
    try {
      await ApiClient.updateDoctorProfile(
        fullName: _fullNameController.text.trim(),
        role: _roleController.text.trim().isEmpty ? null : _roleController.text.trim(),
        licenseNumber: _licenseNumberController.text.trim().isEmpty ? null : _licenseNumberController.text.trim(),
        phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
        hospitalName: _hospitalNameController.text.trim().isEmpty ? null : _hospitalNameController.text.trim(),
        dateOfBirth: _dateOfBirth,
      );
      if (!mounted) return;
      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${AppLocalizations.of(context)!.saveChangesButton} ✓'), backgroundColor: const Color(0xFF16A34A)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e'), backgroundColor: const Color(0xFFDC2626)),
      );
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final initial = _dateOfBirth ?? DateTime(now.year - 30, now.month, now.day);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null && mounted) {
      setState(() => _dateOfBirth = picked);
    }
  }

  InputDecoration _inputDecoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      filled: true,
      fillColor: AppPalette.inputFill(context),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );
  }

  Widget _buildField({
    required BuildContext context,
    required String label,
    required TextEditingController controller,
    TextInputType keyboardType = TextInputType.text,
    bool readOnly = false,
    VoidCallback? onTap,
    String? Function(String?)? validator,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: readOnly || onTap != null,
        onTap: onTap,
        decoration: _inputDecoration(context, label),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      body: Row(
        children: [
          // Reuse sidebar for consistent nav; pass a profile route indicator
          // The sidebar is always visible on desktop. We just mark it active.
          // To avoid importing PractitionerSidebar directly here (which
          // expects a route), we render a simplified left rail instead.
          _DesktopSideRail(
            isActive: true,
            onLogout: () async {
              await AuthService.instance.logout();
              if (mounted) {
                Navigator.of(context).pushAndRemoveUntil(
                  AppPageRoute(builder: (_) => const _PlaceholderLoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
          Expanded(
            child: Column(
              children: [
                AppHeaderBar(
                  title: 'Practitioner Profile',
                  subtitle: 'View and edit your account details',
                  onMenuTap: () {},
                  actions: [
                    if (_isEditing)
                      TextButton.icon(
                        onPressed: _isSaving ? null : () {
                          _formKey.currentState!.reset();
                          _loadProfile();
                          setState(() => _isEditing = false);
                        },
                        icon: const Icon(Icons.close, size: 18),
                        label: const Text('Cancel'),
                        style: TextButton.styleFrom(foregroundColor: AppPalette.textMuted(context)),
                      ),
                    ElevatedButton.icon(
                      onPressed: _isSaving ? null : _isEditing ? _saveProfile : () => setState(() => _isEditing = true),
                      icon: _isSaving
                          ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : Icon(_isEditing ? Icons.save : Icons.edit, size: 18),
                      label: Text(_isSaving ? 'Saving...' : (_isEditing ? 'Save Changes' : 'Edit Profile')),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF6D28D9),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: _isLoading
                      ? const Center(child: CircularProgressIndicator(color: Color(0xFF6D28D9)))
                      : _errorMessage != null
                          ? Center(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  children: [
                                    const Icon(Icons.error_outline, size: 48, color: Color(0xFFDC2626)),
                                    const SizedBox(height: 16),
                                    Text('Error loading profile', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context))),
                                    const SizedBox(height: 8),
                                    Text(_errorMessage!, textAlign: TextAlign.center, style: TextStyle(color: AppPalette.textMuted(context))),
                                    const SizedBox(height: 16),
                                    ElevatedButton.icon(onPressed: _loadProfile, icon: const Icon(Icons.refresh), label: const Text('Retry')),
                                  ],
                                ),
                              ),
                            )
                          : SingleChildScrollView(
                              padding: const EdgeInsets.all(24),
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 720),
                                child: Form(
                                  key: _formKey,
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Container(
                                            width: 64,
                                            height: 64,
                                            decoration: const BoxDecoration(color: Color(0xFF6D28D9), shape: BoxShape.circle),
                                            child: const Icon(Icons.person, color: Colors.white, size: 32),
                                          ),
                                          const SizedBox(width: 16),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  _fullNameController.text.trim().isEmpty ? 'Practitioner' : _fullNameController.text.trim(),
                                                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                                                ),
                                                const SizedBox(height: 4),
                                                Text(
                                                  'Practitioner Account',
                                                  style: TextStyle(fontSize: 13, color: AppPalette.textMuted(context)),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 24),
                                      _buildField(context: context, label: 'Full Name', controller: _fullNameController, readOnly: !_isEditing, validator: (v) => (v == null || v.trim().isEmpty) ? 'Full name is required' : null),
                                      _buildField(context: context, label: 'Role / Specialty', controller: _roleController, readOnly: !_isEditing),
                                      _buildField(context: context, label: 'License Number', controller: _licenseNumberController, readOnly: !_isEditing),
                                      _buildField(context: context, label: 'Phone', controller: _phoneController, keyboardType: TextInputType.phone, readOnly: !_isEditing),
                                      _buildField(context: context, label: 'Hospital / Clinic Name', controller: _hospitalNameController, readOnly: !_isEditing),
                                      InkWell(
                                        onTap: _isEditing ? _pickDate : null,
                                        child: InputDecorator(
                                          decoration: _inputDecoration(context, 'Date of Birth'),
                                          child: Text(
                                            _dateOfBirth == null ? 'Not set' : DateFormat('yyyy-MM-dd').format(_dateOfBirth!),
                                            style: TextStyle(color: _dateOfBirth == null ? AppPalette.textMuted(context) : AppPalette.textPrimary(context)),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
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
}

class _DesktopSideRail extends StatelessWidget {
  final bool isActive;
  final VoidCallback onLogout;

  const _DesktopSideRail({required this.isActive, required this.onLogout});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 260,
      decoration: BoxDecoration(
        color: AppPalette.surface(context),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 20, offset: const Offset(4, 0))],
      ),
      child: Column(
        children: [
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFFE2E8F0)),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                _NavItem(icon: Icons.dashboard_outlined, label: 'Dashboard', isActive: false, onTap: () => _navigateTo(context, '/dashboard')),
                _NavItem(icon: Icons.people_outline, label: 'Patients', isActive: false, onTap: () => _navigateTo(context, '/patients')),
                _NavItem(icon: Icons.medical_services_outlined, label: 'Triage Sessions', isActive: false, onTap: () => _navigateTo(context, '/sessions')),
                _NavItem(icon: Icons.assessment_outlined, label: 'Reports', isActive: false, onTap: () => _navigateTo(context, '/reports')),
                const Divider(height: 24, color: Color(0xFFE2E8F0)),
                _NavItem(icon: Icons.person_outline, label: 'Profile', isActive: isActive, onTap: () {}),
                _NavItem(icon: Icons.settings_outlined, label: 'Settings', isActive: false, onTap: () => _navigateTo(context, '/settings')),
                _NavItem(icon: Icons.help_outline, label: 'Help & Support', isActive: false, onTap: () => _navigateTo(context, '/help')),
              ],
            ),
          ),
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
            decoration: const BoxDecoration(color: Color(0xFF6D28D9), shape: BoxShape.circle),
            child: const Icon(Icons.medical_services, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 12),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Simtack', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
              Text('Practitioner', style: TextStyle(fontSize: 11, color: Color(0xFF64748B), fontWeight: FontWeight.w500)),
            ],
          ),
        ],
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
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: onLogout,
          icon: const Icon(Icons.logout, size: 16),
          label: const Text('Logout'),
          style: OutlinedButton.styleFrom(
            foregroundColor: const Color(0xFFDC2626),
            side: const BorderSide(color: Color(0xFFDC2626)),
            padding: const EdgeInsets.symmetric(vertical: 10),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, String route) {
    switch (route) {
      case '/dashboard':
        Navigator.of(context).pushAndRemoveUntil(AppPageRoute(builder: (_) => const PractitionerDashboardScreen()), (r) => false);
        break;
      case '/patients':
        Navigator.of(context).push(AppPageRoute(builder: (_) => const PatientOverviewScreen()));
        break;
      case '/sessions':
        Navigator.of(context).push(AppPageRoute(builder: (_) => const PractitionerSessionHistoryScreen()));
        break;
      case '/settings':
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccessibilitySettingsScreen()));
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('This screen is under construction'), backgroundColor: Color(0xFF6D28D9)));
    }
  }
}

class _NavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _NavItem({required this.icon, required this.label, required this.isActive, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: isActive ? const Color(0xFF6D28D9).withOpacity(0.10) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(icon, size: 20, color: isActive ? const Color(0xFF6D28D9) : AppPalette.textMuted(context)),
                const SizedBox(width: 12),
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
                if (isActive)
                  Container(
                    width: 4,
                    height: 20,
                    decoration: const BoxDecoration(color: Color(0xFF6D28D9), borderRadius: BorderRadius.horizontal(left: Radius.circular(2))),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PlaceholderLoginScreen extends StatelessWidget {
  const _PlaceholderLoginScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: Text('Login')));
  }
}
