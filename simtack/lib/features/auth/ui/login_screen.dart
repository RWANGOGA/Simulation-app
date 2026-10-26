import 'package:flutter/material.dart';
import 'package:simtack/core/theme/app_tokens.dart';
import 'package:simtack/core/theme/app_accent.dart';
import 'package:simtack/core/theme/app_palette.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/theme/app_page_route.dart';
import '../../dashboard/ui/practitioner_dashboard_screen.dart';
import '../../onboarding/ui/welcome_screen.dart';
import '../../patient_info/ui/patient_info_screen.dart';
import 'register_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;
  bool _obscurePassword = true;

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _errorMessage = 'Please enter both email and password.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final doctor =
          await AuthService.instance.login(email: email, password: password);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Login Successful! Welcome, ${doctor.fullName}.'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.of(context).pushReplacement(
        AppPageRoute(builder: (_) => const PractitionerDashboardScreen()),
      );
    } on ApiException catch (e) {
      setState(() => _errorMessage = e.message);
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.medical_services_rounded,
                    size: 80, color: AppAccent.primary(context)),
                const SizedBox(height: 24),
                Text(
                  'Practitioner Portal',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      color: AppPalette.textPrimary(context)),
                ),
                const SizedBox(height: 8),
                Text(
                  'Simtack Care',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      fontSize: 16,
                      color: AppPalette.textMuted(context),
                      fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 48),
                if (_errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppAccent.dangerTint(context),
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      border: Border.all(color: AppAccent.fieldError(context)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.error_outline,
                            color: AppAccent.fieldError(context), size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_errorMessage!,
                              style: TextStyle(
                                  color: AppAccent.danger(context),
                                  fontSize: 14)),
                        ),
                      ],
                    ),
                  ),
                if (_errorMessage != null) const SizedBox(height: 16),
                TextField(
                  controller: _emailController,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: 'Email Address',
                    prefixIcon: Icon(Icons.email_outlined,
                        color: AppAccent.primary(context)),
                    filled: true,
                    fillColor: AppPalette.inputFill(context),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide:
                            BorderSide(color: AppPalette.border(context))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(
                            color: AppAccent.primary(context), width: 2)),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _passwordController,
                  obscureText: _obscurePassword,
                  onSubmitted: (_) => _login(),
                  decoration: InputDecoration(
                    labelText: 'Password',
                    prefixIcon: Icon(Icons.lock_outline,
                        color: AppAccent.primary(context)),
                    suffixIcon: IconButton(
                      icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_outlined
                              : Icons.visibility_off_outlined,
                          color: AppPalette.textMuted(context)),
                      onPressed: () =>
                          setState(() => _obscurePassword = !_obscurePassword),
                    ),
                    filled: true,
                    fillColor: AppPalette.inputFill(context),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide:
                            BorderSide(color: AppPalette.border(context))),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        borderSide: BorderSide(
                            color: AppAccent.primary(context), width: 2)),
                  ),
                ),
                const SizedBox(height: 32),
                SizedBox(
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _login,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppAccent.primary(context),
                      disabledBackgroundColor: AppAccent.primary(context),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
                      elevation: 0,
                    ),
                    child: _isLoading
                        ? const SizedBox(
                            height: 24,
                            width: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Text('Sign In',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: Colors.white)),
                  ),
                ),
                const SizedBox(height: 24),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('New practitioner?',
                        style: TextStyle(
                            fontSize: 14,
                            color: AppPalette.textMuted(context))),
                    TextButton(
                      onPressed: _isLoading
                          ? null
                          : () => Navigator.of(context).push(
                                AppPageRoute(
                                    builder: (_) => const RegisterScreen()),
                              ),
                      child: Text('Create an account',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppAccent.primary(context))),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                _buildDividerWithText('Or'),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).push(
                              AppPageRoute(
                                  builder: (_) => const WelcomeScreen()),
                            ),
                    icon: Icon(Icons.person_add_alt_1,
                        color: AppAccent.primary(context)),
                    label: Text('Register Patient',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppAccent.primary(context))),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppAccent.primary(context)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _isLoading
                        ? null
                        : () => Navigator.of(context).push(
                              AppPageRoute(
                                  builder: (_) => const PatientInfoScreen()),
                            ),
                    icon: Icon(Icons.fast_forward,
                        color: AppAccent.success(context)),
                    label: Text('Quick Patient Entry',
                        style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: AppAccent.success(context))),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: AppAccent.success(context)),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
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

  Widget _buildDividerWithText(String text) {
    return Row(
      children: [
        Expanded(
            child: Divider(color: AppPalette.border(context), thickness: 1)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(text,
              style: TextStyle(
                  color: AppPalette.textMuted(context), fontSize: 14)),
        ),
        Expanded(
            child: Divider(color: AppPalette.border(context), thickness: 1)),
      ],
    );
  }
}
