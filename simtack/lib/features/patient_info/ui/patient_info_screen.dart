import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/network/api_client.dart';
import '../../body_map/ui/body_map_screen.dart';
import '../../../core/theme/app_page_route.dart';

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

  String _formatDob(DateTime dob) =>
      '${dob.year.toString().padLeft(4, '0')}-'
      '${dob.month.toString().padLeft(2, '0')}-'
      '${dob.day.toString().padLeft(2, '0')}';

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 30),
      firstDate: DateTime(1900),
      lastDate: now,
      helpText: 'DATE OF BIRTH',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  InputDecoration _fieldDecoration({
    required String label,
    IconData? icon,
    String? helper,
  }) =>
      InputDecoration(
        labelText: label,
        prefixIcon: icon != null ? Icon(icon, color: const Color(0xFF6D28D9)) : null,
        helperText: helper,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 2),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)),
          onPressed: () => Navigator.of(context).pop(),
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
                const Text(
                  'Patient Profile',
                  style: TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
                const SizedBox(height: 4),
                const Text(
                  'This helps us build your body map',
                  style: TextStyle(fontSize: 15, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 24),

                Expanded(
                  child: ListView(
                    children: [
                      _buildGenderSelector(),
                      const SizedBox(height: 20),
                      _buildNumberField(
                        controller: _ageController,
                        label: 'Age',
                        suffix: 'years',
                        min: 0,
                        max: 120,
                      ),
                      const SizedBox(height: 16),
                      _buildNumberField(
                        controller: _weightController,
                        label: 'Weight',
                        suffix: 'kg',
                        min: 20,
                        max: 300,
                      ),
                      const SizedBox(height: 16),
                      _buildNumberField(
                        controller: _heightController,
                        label: 'Height',
                        suffix: 'cm',
                        min: 50,
                        max: 250,
                      ),

                      // ----- Optional personal details -----
                      const SizedBox(height: 28),
                      const Text(
                        'CONTACT & IDENTITY (OPTIONAL)',
                        style: TextStyle(
                          fontSize: 12,
                          letterSpacing: 1.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF64748B),
                        ),
                      ),
                      const SizedBox(height: 4),
                      const Text(
                        'Add these so the practitioner can identify and reach you. '
                        'Skip them to stay fully anonymous.',
                        style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _nameController,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          label: 'Full Name',
                          icon: Icons.person_outline,
                        ),
                      ),
                      const SizedBox(height: 16),
                      GestureDetector(
                        onTap: _pickDateOfBirth,
                        child: AbsorbPointer(
                          child: TextFormField(
                            decoration: _fieldDecoration(
                              label: 'Date of Birth',
                              icon: Icons.cake_outlined,
                            ),
                            controller: TextEditingController(
                              text: _dateOfBirth != null ? _formatDob(_dateOfBirth!) : '',
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
                          label: 'Contact Phone',
                          icon: Icons.phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _addressController,
                        textInputAction: TextInputAction.next,
                        maxLines: 2,
                        decoration: _fieldDecoration(
                          label: 'Address',
                          icon: Icons.home_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nextOfKinNameController,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          label: 'Next of Kin Name',
                          icon: Icons.family_restroom,
                          helper: 'Useful when reporting for a child or dependent',
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _nextOfKinPhoneController,
                        keyboardType: TextInputType.phone,
                        textInputAction: TextInputAction.next,
                        decoration: _fieldDecoration(
                          label: 'Next of Kin Phone',
                          icon: Icons.contact_phone_outlined,
                        ),
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _hospitalController,
                        textInputAction: TextInputAction.done,
                        decoration: _fieldDecoration(
                          label: 'Hospital / Clinic Name',
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
                            child: CircularProgressIndicator(color: Colors.white, strokeWidth: 3),
                          )
                        : const Text(
                            'Continue',
                            style: TextStyle(
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
    return Row(
      children: [
        Expanded(child: _buildGenderOption('Female')),
        const SizedBox(width: 12),
        Expanded(child: _buildGenderOption('Male')),
      ],
    );
  }

  Widget _buildGenderOption(String value) {
    final isSelected = _gender == value;
    return GestureDetector(
      onTap: () => setState(() => _gender = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6D28D9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFFE2E8F0),
            width: 2,
          ),
        ),
        child: Text(
          value,
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: isSelected ? Colors.white : const Color(0xFF1E293B),
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
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFE2E8F0)),
        ),
      ),
      validator: (value) {
        if (value == null || value.isEmpty) return '$label is required';
        final parsed = num.tryParse(value);
        if (parsed == null) return 'Enter a valid number';
        if (parsed < min || parsed > max) return '$label must be between $min and $max';
        return null;
      },
    );
  }

  Future<void> _onContinue() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      final patient = await ApiClient.createPatient(PatientProfile(
        age: int.parse(_ageController.text),
        gender: _gender,
        weight: double.parse(_weightController.text),
        height: double.parse(_heightController.text),
        fullName: _nameController.text,
        dateOfBirth: _dateOfBirth,
        phone: _phoneController.text,
        address: _addressController.text,
        nextOfKinName: _nextOfKinNameController.text,
        nextOfKinPhone: _nextOfKinPhoneController.text,
        hospitalName: _hospitalController.text,
      ));

      if (!mounted) return;
      Navigator.of(context).push(
        AppPageRoute(
          builder: (_) => BodyMapScreen(
            patientId: patient.id,
            gender: _gender,
            weightKg: double.parse(_weightController.text),
            heightCm: double.parse(_heightController.text),
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not save profile: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
}
