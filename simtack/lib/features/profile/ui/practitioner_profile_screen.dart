import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/theme/github_kit.dart';
import '../../../../core/theme/github_palette.dart';
import '../../../../core/theme/app_header_bar.dart';
import '../../../../core/theme/app_page.dart';
import '../../../../core/network/auth_service.dart';
import '../../../../l10n/app_localizations.dart';
import '../../dashboard/ui/practitioner_scaffold.dart';

class PractitionerProfileScreen extends StatefulWidget {
  const PractitionerProfileScreen({super.key});

  @override
  State<PractitionerProfileScreen> createState() =>
      _PractitionerProfileScreenState();
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
      // Written to this device by AuthService and forwarded to the server
      // afterwards, so editing a profile in a clinic with no signal works and
      // is not lost.
      await AuthService.instance.updateMyProfile(
        fullName: _fullNameController.text.trim(),
        role: _roleController.text.trim().isEmpty
            ? null
            : _roleController.text.trim(),
        licenseNumber: _licenseNumberController.text.trim().isEmpty
            ? null
            : _licenseNumberController.text.trim(),
        phone: _phoneController.text.trim().isEmpty
            ? null
            : _phoneController.text.trim(),
        hospitalName: _hospitalNameController.text.trim().isEmpty
            ? null
            : _hospitalNameController.text.trim(),
        dateOfBirth: _dateOfBirth,
      );
      if (!mounted) return;
      setState(() {
        _isEditing = false;
        _isSaving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content:
                Text('${AppLocalizations.of(context)!.saveChangesButton} ✓'),
            backgroundColor: GhColors.success(context)),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Failed to save: $e'),
            backgroundColor: GhColors.danger(context)),
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

  /// The console's input: 32px, one border, blue ring on focus.
  InputDecoration _inputDecoration(BuildContext context) {
    OutlineInputBorder border(Color color, [double width = 1]) =>
        OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: BorderSide(color: color, width: width),
        );

    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: GhColors.surface(context),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: border(GhColors.border(context)),
      enabledBorder: border(GhColors.border(context)),
      disabledBorder: border(GhColors.borderMuted(context)),
      focusedBorder: border(GhColors.accent(context), 2),
    );
  }

  /// A settings row: label on the left, field on the right — GitHub's own
  /// settings layout, stacked on narrow screens.
  /// A settings row: label on the left, control on the right — GitHub's own
  /// settings layout, stacked on narrow screens.
  Widget _settingsRow({
    required BuildContext context,
    required String label,
    required Widget field,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final labelText = Text(label,
            style: GhType.title.copyWith(color: GhColors.fg(context)));

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: GhColors.borderMuted(context)),
            ),
          ),
          child: constraints.maxWidth >= 560
              ? Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 200,
                      child: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: labelText,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(child: field),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    labelText,
                    const SizedBox(height: 6),
                    field,
                  ],
                ),
        );
      },
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
    return _settingsRow(
      context: context,
      label: label,
      field: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: readOnly || onTap != null,
        onTap: onTap,
        validator: validator,
        style: GhType.body.copyWith(color: GhColors.fg(context)),
        decoration: _inputDecoration(context),
      ),
    );
  }

  Widget _buildDateField(BuildContext context) {
    final value = _dateOfBirth == null
        ? 'Not set'
        : DateFormat('yyyy-MM-dd').format(_dateOfBirth!);
    return _settingsRow(
      context: context,
      label: 'Date of Birth',
      field: InkWell(
        onTap: _isEditing ? _pickDate : null,
        borderRadius: BorderRadius.circular(6),
        child: InputDecorator(
          decoration: _inputDecoration(context),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  value,
                  style: GhType.body.copyWith(
                    color: _dateOfBirth == null
                        ? GhColors.fgMuted(context)
                        : GhColors.fg(context),
                  ),
                ),
              ),
              Icon(Icons.calendar_today_outlined,
                  size: 14, color: GhColors.fgMuted(context)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildIdentity(BuildContext context) {
    final name = _fullNameController.text.trim();
    return Row(
      children: [
        GhAvatar(name: name.isEmpty ? null : name, size: 64),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                name.isEmpty ? 'Practitioner' : name,
                style:
                    GhType.sectionTitle.copyWith(color: GhColors.fg(context)),
              ),
              const SizedBox(height: 4),
              Text(
                'Practitioner Account',
                style: GhType.body.copyWith(color: GhColors.fgMuted(context)),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLoadError(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: SizedBox(
          width: 520,
          child: GhBanner(
            'Error loading profile: $_errorMessage',
            tone: GhTone.danger,
            icon: Icons.error_outline,
            actions: [
              GhButton(
                'Retry',
                icon: Icons.refresh,
                variant: GhButtonVariant.secondary,
                onPressed: _loadProfile,
              ),
            ],
          ),
        ),
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
                GhButton(
                  'Cancel',
                  icon: Icons.close,
                  variant: GhButtonVariant.header,
                  onPressed: _isSaving
                      ? null
                      : () {
                          _formKey.currentState!.reset();
                          _loadProfile();
                          setState(() => _isEditing = false);
                        },
                ),
              GhButton(
                _isSaving
                    ? 'Saving…'
                    : (_isEditing ? 'Save Changes' : 'Edit Profile'),
                icon: _isEditing ? Icons.check : Icons.edit_outlined,
                variant: _isEditing
                    ? GhButtonVariant.primary
                    : GhButtonVariant.header,
                busy: _isSaving,
                onPressed: _isEditing
                    ? _saveProfile
                    : () => setState(() => _isEditing = true),
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
                : _errorMessage != null
                    ? _buildLoadError(context)
                    : AppPage(
                        scrollable: true,
                        // A settings page, not a console: single-column fields
                        // and settings rows read better at the reading measure.
                        // This replaces the hand-picked
                        // `ConstrainedBox(maxWidth: 860)` that used to sit here.
                        maxWidth: AppContentWidth.reading,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildIdentity(context),
                            const SizedBox(height: 24),
                            GhBox(
                              header: 'Profile',
                              flush: true,
                              child: Form(
                                key: _formKey,
                                child: Column(
                                  children: [
                                    _buildField(
                                        context: context,
                                        label: 'Full Name',
                                        controller: _fullNameController,
                                        readOnly: !_isEditing,
                                        validator: (v) =>
                                            (v == null || v.trim().isEmpty)
                                                ? 'Full name is required'
                                                : null),
                                    _buildField(
                                        context: context,
                                        label: 'Role / Specialty',
                                        controller: _roleController,
                                        readOnly: !_isEditing),
                                    _buildField(
                                        context: context,
                                        label: 'License Number',
                                        controller: _licenseNumberController,
                                        readOnly: !_isEditing),
                                    _buildField(
                                        context: context,
                                        label: 'Phone',
                                        controller: _phoneController,
                                        keyboardType: TextInputType.phone,
                                        readOnly: !_isEditing),
                                    _buildField(
                                        context: context,
                                        label: 'Hospital / Clinic Name',
                                        controller: _hospitalNameController,
                                        readOnly: !_isEditing),
                                    _buildDateField(context),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}
