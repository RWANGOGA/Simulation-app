import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import 'package:flutter/services.dart';
import '../../../core/network/api_client.dart';
import '../../../core/models/patient_profile.dart';
import '../../../core/storage/patient_draft_storage.dart';
import '../../../core/storage/patient_draft.dart';
import '../../../core/network/connectivity_service.dart';
import '../../body_map/ui/body_map_screen.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/widgets/flow_progress_bar.dart';
import '../../../l10n/app_localizations.dart';

class PatientInfoScreen extends StatefulWidget {
  const PatientInfoScreen({super.key});

  @override
  State<PatientInfoScreen> createState() => _PatientInfoScreenState();
}

class _PatientInfoScreenState extends State<PatientInfoScreen> {
  final _formKey = GlobalKey<FormState>();
  final _ageController = TextEditingController();
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  // Optional personal details — stored so the practitioner sees them on
  // the clinical report and whenever the QR passport is scanned.
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _addressController = TextEditingController();
  final _nextOfKinNameController = TextEditingController();
  final _nextOfKinPhoneController = TextEditingController();
  final _hospitalController = TextEditingController();
  DateTime? _dateOfBirth;
  String _gender = 'Female';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    _addressController.dispose();
    _nextOfKinNameController.dispose();
    _nextOfKinPhoneController.dispose();
    _hospitalController.dispose();
    super.dispose();
  }

  int _calculateAge(DateTime dob) {
    final now = DateTime.now();
    int age = now.year - dob.year;
    if (now.month < dob.month ||
        (now.month == dob.month && now.day < dob.day)) {
      age--;
    }
    return age;
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: AppLocalizations.of(context)!.dateOfBirthHelpText,
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _ageController.text = _calculateAge(picked).toString();
      });
    }
  }

  InputDecoration _fieldDecoration({
    required String label,
    IconData? icon,
    String? helper,
  }) =>
      InputDecoration(
        labelText: label,
        prefixIcon:
            icon != null ? Icon(icon, color: const Color(0xFF6D28D9)) : null,
        helperText: helper,
        filled: true,
        fillColor: AppPalette.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppPalette.border(context)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppPalette.border(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(20),
          child: FlowProgressBar(totalSteps: 6, currentStep: 2),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t.patientProfileTitle,
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  t.patientProfileSubtitle,
                  style: TextStyle(
                      fontSize: 15, color: AppPalette.textMuted(context)),
                ),
                const SizedBox(height: 24),
                Expanded(
                  child: ListView(
                    children: [
                      _buildGenderSelector(),
                      const SizedBox(height: 20),
                      _buildNumberField(
                        controller: _ageController,
                        label: t.ageLabel,
                        suffix: t.yearsSuffix,
                        min: 0,
                        max: 120,
                      ),
                      const SizedBox(height: 16),
                      _buildNumberField(
                        controller: _weightController,
                        label: t.weightLabel,
                        suffix: t.kgSuffix,
                        min: 20,
                        max: 300,
                      ),
                      const SizedBox(height: 16),
                      _buildNumberField(
                        controller: _heightController,
                        label: t.heightLabel,
                        suffix: t.cmSuffix,
                        min: 50,
                        max: 250,
                      ),

                      // ----- Optional personal details -----
                      const SizedBox(height: 28),
                      Text(
                        t.contactIdentityOptionalTitle,
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                          color: AppPalette.textMuted(context),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        t.contactIdentityHint,
                        style: TextStyle(
                            fontSize: 13, color: AppPalette.textMuted(context)),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          label: t.fullNameLabel,
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _pickDateOfBirth,
                        child: AbsorbPointer(
                          child: TextFormField(
                            decoration: _fieldDecoration(
                              label: t.ageLabel,
                              icon: Icons.cake_outlined,
                            ),
                            controller: TextEditingController(
                              text: _dateOfBirth != null
                                  ? '${_calculateAge(_dateOfBirth!)} ${t.yearsSuffix}'
                                  : '',
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _phoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          label: t.contactPhoneLabel,
                          icon: Icons.phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        textInputAction: TextInputAction.next,
                        maxLines: 2,
                        decoration: _fieldDecoration(
                          label: t.addressLabel,
                          icon: Icons.home_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nextOfKinNameController,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          label: t.nextOfKinNameLabel,
                          icon: Icons.family_restroom,
                          helper: t.nextOfKinNameHelper,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nextOfKinPhoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          label: t.nextOfKinPhoneLabel,
                          icon: Icons.contact_phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hospitalController,
                        textInputAction: TextInputAction.done,
                        decoration: _fieldDecoration(
                          label: t.hospitalClinicNameLabel,
                          icon: Icons.local_hospital_outlined,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _onContinue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF6D28D9),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 3),
                          )
                        : Text(
                            t.continueButton,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
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

  Widget _buildGenderSelector() {
    final t = AppLocalizations.of(context)!;
    return Row(
      children: [
        Expanded(child: _buildGenderOption('Female', t.genderFemale)),
        const SizedBox(width: 12),
        Expanded(child: _buildGenderOption('Male', t.genderMale)),
      ],
    );
  }

  // `value` is the English literal stored in state and sent to the backend;
  // `label` is only what's shown on screen, so the locale never affects the
  // stored gender value.
  Widget _buildGenderOption(String value, String label) {
    final isSelected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6D28D9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6D28D9)
                : AppPalette.border(context),
            width: 2,
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : AppPalette.textPrimary(context),
          ),
        ),
      ),
    );
  }

  Widget _buildNumberField({
    required TextEditingController controller,
    required String label,
    required String suffix,
    required num min,
    required num max,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        filled: true,
        fillColor: AppPalette.inputFill(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: AppPalette.border(context)),
        ),
      ),
      validator: (value) {
        final t = AppLocalizations.of(context)!;
        if (value == null || value.isEmpty) return t.fieldRequiredError(label);
        final parsed = num.tryParse(value);
        if (parsed == null) return t.enterValidNumberError;
        if (parsed < min || parsed > max)
          return t.fieldRangeError(label, '$min', '$max');
        return null;
      },
    );
  }

  Future<void> _onContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    
    // Build the patient profile
    final profile = PatientProfile(
      age: int.parse(_ageController.text),
      gender: _gender,
      weight: double.parse(_weightController.text),
      height: double.parse(_heightController.text),
      fullName: _nameController.text.trim().isEmpty ? null : _nameController.text.trim(),
      dateOfBirth: _dateOfBirth,
      phone: _phoneController.text.trim().isEmpty ? null : _phoneController.text.trim(),
      address: _addressController.text.trim().isEmpty ? null : _addressController.text.trim(),
      nextOfKinName: _nextOfKinNameController.text.trim().isEmpty ? null : _nextOfKinNameController.text.trim(),
      nextOfKinPhone: _nextOfKinPhoneController.text.trim().isEmpty ? null : _nextOfKinPhoneController.text.trim(),
      hospitalName: _hospitalController.text.trim().isEmpty ? null : _hospitalController.text.trim(),
    );

    // Always save locally first (offline-first)
    final localDraft = PatientDraft.createOffline(profile);
    await PatientDraftStorage.save(localDraft);

    // Use local IDs for navigation (negative = offline)
    int patientId = localDraft.localId;
    String? patientCode;

    // If online, try to sync to backend
    final isOnline = await ConnectivityService.instance.checkOnline();
    if (isOnline) {
      try {
        final result = await ApiClient.createPatient(profile);
        patientId = result.id;
        patientCode = result.anonymousCode;
        
        // Update local draft with server response
        final syncedDraft = localDraft.copyWith(
          patientId: result.id,
          patientCode: result.anonymousCode,
          isSynced: true,
        );
        await PatientDraftStorage.save(syncedDraft);
      } catch (_) {
        // Sync failed, keep local draft for later sync
        // patientCode remains null, will be generated on review submission
      }
    }

    if (!mounted) return;
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => BodyMapScreen(
          patientId: patientId,
          patientCode: patientCode,
          gender: _gender,
          weightKg: double.parse(_weightController.text),
          heightCm: double.parse(_heightController.text),
        ),
      ),
    );
    
    if (mounted) setState(() => _isSubmitting = false);
  }
}
