import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/app_palette.dart';
import '../../../../core/theme/app_header_bar.dart';
import '../../../../core/network/api_client.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../dashboard/ui/practitioner_scaffold.dart';

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
        _dateOfBirth = null;
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
    return PractitionerScaffold(
      currentRoute: '/profile',
      contentBuilder: (context, openDrawer) => Column(
        children: [
          AppHeaderBar(
            title: 'Practitioner Profile',
            subtitle: 'View and edit your account details',
            onMenuTap: openDrawer,
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
    );
  }
}
