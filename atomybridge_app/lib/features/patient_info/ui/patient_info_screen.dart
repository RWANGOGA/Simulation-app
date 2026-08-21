import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../../body_map/ui/body_map_screen.dart';

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
  String _gender = 'Female';
  bool _isSubmitting = false;

  @override
  void dispose() {
    _ageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    super.dispose();
  }

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
                  style: TextStyle(
                    fontSize: 15,
                    color: Color(0xFF64748B),
                  ),
                ),
                const SizedBox(height: 24),

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

                const Spacer(),

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
      ));

      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
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
