import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/network/api_client.dart';
import '../../../core/theme/app_page_route.dart';
import '../../dashboard/ui/practitioner_dashboard_screen.dart';

/// Self-service signup for medical practitioners.
///
/// Required fields (mirrored by backend validation):
/// - Full name, professional email, password (8+ chars, letter + number)
/// - Role/title (dropdown) and license number (self-declared)
/// On success the account is created and the user is logged in
/// automatically, landing directly on the practitioner dashboard.
class RegisterScreen extends StatefulWidget {
  const RegisterScreen({super.key});

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  static const _roles = ['Doctor', 'Nurse', 'Clinical Officer', 'Other'];

  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _licenseController = TextEditingController();
  final _phoneController = TextEditingController();
  final _hospitalController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  String? _role = _roles.first;
  DateTime? _dateOfBirth;
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return 'Email is required.';
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    final password = value ?? '';
    if (password.length < 8) return 'At least 8 characters.';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      return 'Must contain a letter and a number.';
    }
    return null;
  }

  InputDecoration _fieldDecoration({required String label, required IconData icon}) =>
      InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: const Color(0xFF6D28D9)),
        filled: true,
        fillColor: AppPalette.inputFill(context),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: AppPalette.border(context))),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFF6D28D9), width: 2)),
      );

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 35),
      firstDate: DateTime(1930),
      lastDate: now,
      helpText: 'DATE OF BIRTH',
    );
    if (picked != null) setState(() => _dateOfBirth = picked);
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _register() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      final doctor = await ApiClient.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
        role: _role,
        licenseNumber: _licenseController.text.trim(),
        phone: _phoneController.text.trim(),
        hospitalName: _hospitalController.text.trim(),
        dateOfBirth: _dateOfBirth,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Account created. Welcome, ${doctor.fullName}!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pushReplacement(
        AppPageRoute(builder: (_) => const PractitionerDashboardScreen()),
      );
    } on ApiException catch (e) {
      if (mounted) setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _licenseController.dispose();
    _phoneController.dispose();
    _hospitalController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      appBar: AppBar(
        backgroundColor: AppPalette.scaffold(context),
        elevation: 0,
        foregroundColor: AppPalette.textPrimary(context),
        title: const Text('Create Practitioner Account'),
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0, vertical: 16.0),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Icon(Icons.medical_services_rounded, size: 56, color: Color(0xFF6D28D9)),
                    const SizedBox(height: 12),
                    Text(
                      'Join Simtack Care',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                    ),
                    const SizedBox(height: 24),
                    if (_errorMessage != null) ...[
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFEF4444)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.error_outline, color: Color(0xFFEF4444), size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(_errorMessage!,
                                  style: const TextStyle(color: Color(0xFFB91C1C), fontSize: 14)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(label: 'Full Name', icon: Icons.person_outline),
                      validator: (value) => (value == null || value.trim().length < 2)
                          ? 'Enter your full name.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _emailController,
                      keyboardType: TextInputType.emailAddress,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(label: 'Professional Email', icon: Icons.email_outlined),
                      validator: _validateEmail,
                    ),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: _role,
                      decoration: _fieldDecoration(label: 'Role / Title', icon: Icons.badge_outlined),
                      items: _roles
                          .map((role) => DropdownMenuItem(value: role, child: Text(role)))
                          .toList(),
                      onChanged: _isLoading ? null : (value) => setState(() => _role = value),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _licenseController,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(
                        label: 'License / Registration Number',
                        icon: Icons.verified_user_outlined,
                      ),
                      validator: (value) => (value == null || value.trim().isEmpty)
                          ? 'Enter your license or registration number.'
                          : null,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 6, left: 4),
                      child: Text(
                        'Self-declared for this deployment — verified out-of-band in real rollouts.',
                        style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    GestureDetector(
                      onTap: _pickDateOfBirth,
                      child: AbsorbPointer(
                        child: TextFormField(
                          decoration: _fieldDecoration(
                              label: 'Date of Birth (optional)', icon: Icons.cake_outlined),
                          controller: TextEditingController(
                            text: _dateOfBirth != null ? _formatDate(_dateOfBirth!) : '',
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _phoneController,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(label: 'Contact Phone', icon: Icons.phone_outlined),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _hospitalController,
                      textInputAction: TextInputAction.next,
                      decoration:
                          _fieldDecoration(label: 'Hospital / Facility', icon: Icons.local_hospital_outlined),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _passwordController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.next,
                      decoration: _fieldDecoration(label: 'Password', icon: Icons.lock_outline).copyWith(
                        suffixIcon: IconButton(
                          icon: Icon(
                              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                              color: AppPalette.textMuted(context)),
                          onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                        ),
                      ),
                      validator: _validatePassword,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _confirmController,
                      obscureText: _obscurePassword,
                      textInputAction: TextInputAction.done,
                      onFieldSubmitted: (_) => _register(),
                      decoration: _fieldDecoration(label: 'Confirm Password', icon: Icons.lock_outline),
                      validator: (value) =>
                          value != _passwordController.text ? 'Passwords do not match.' : null,
                    ),
                    const SizedBox(height: 32),
                    SizedBox(
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _isLoading ? null : _register,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D28D9),
                          disabledBackgroundColor: const Color(0xFFA78BFA),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          elevation: 0,
                        ),
                        child: _isLoading
                            ? const SizedBox(
                                height: 24,
                                width: 24,
                                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                            : const Text('Create Account',
                                style: TextStyle(
                                    fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                      child: const Text(
                        'Already have an account? Sign in',
                        style: TextStyle(color: Color(0xFF6D28D9), fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
