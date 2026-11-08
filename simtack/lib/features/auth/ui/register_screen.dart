import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/theme/app_page.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/github_kit.dart';
import '../../../core/theme/github_palette.dart';
import '../../dashboard/ui/practitioner_dashboard_screen.dart';

/// Self-service signup for medical practitioners, in Primer.
///
/// Required fields (mirrored by backend validation):
/// - Full name, professional email, password (exactly 8 chars, letter + number)
/// - Role/title (dropdown) and license number (self-declared)
///
/// On success against a server the account exists but is inert: an administrator
/// has to approve it before clinical records can be read. Only the very first
/// account on an empty deployment is approved on creation, and only that one
/// lands straight on the practitioner dashboard.
///
/// With no server reachable the account is created on this device instead and
/// opens straight away — see [AuthService.register]. That is the only way the
/// practitioner side works in a clinic that has no backend at all.
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
  final _inviteCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  // Held rather than rebuilt inside `build`: a controller created per frame is
  // never disposed, and the date field needs a stable one to write into.
  final _dateOfBirthController = TextEditingController();
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
    if (password.length < 8) return 'At least 8 characters required.';
    if (!RegExp(r'[A-Za-z]').hasMatch(password) ||
        !RegExp(r'\d').hasMatch(password)) {
      return 'Must contain a letter and a number.';
    }
    return null;
  }

  /// Primer's input: 6px radius, one-pixel border, blue ring on focus. The
  /// label lives above the field (see [_field]) rather than floating into the
  /// border, so the form does not reflow as it is filled in.
  InputDecoration _fieldDecoration({required IconData icon}) => InputDecoration(
        isDense: true,
        prefixIcon: Icon(icon, size: 16, color: GhColors.fgMuted(context)),
        prefixIconConstraints:
            const BoxConstraints(minWidth: 34, minHeight: 32),
        filled: true,
        fillColor: GhColors.surface(context),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: _border(GhColors.border(context)),
        enabledBorder: _border(GhColors.border(context)),
        focusedBorder: _border(GhColors.accent(context), 2),
        errorBorder: _border(GhColors.danger(context)),
        focusedErrorBorder: _border(GhColors.danger(context), 2),
        errorStyle: GhType.meta.copyWith(color: GhColors.danger(context)),
      );

  OutlineInputBorder _border(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: color, width: width),
      );

  /// A labelled control. Nine copies of "label, gap, input" is exactly the
  /// repetition that makes a form drift, so the pattern is written once.
  Widget _field({
    required String label,
    required Widget child,
    String? help,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: GhType.bodyStrong.copyWith(color: GhColors.fg(context)),
        ),
        const SizedBox(height: 6),
        child,
        if (help != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(
              help,
              style: GhType.meta.copyWith(color: GhColors.fgMuted(context)),
            ),
          ),
      ],
    );
  }

  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 35),
      firstDate: DateTime(1930),
      lastDate: now,
      helpText: 'DATE OF BIRTH',
    );
    if (picked != null) {
      setState(() {
        _dateOfBirth = picked;
        _dateOfBirthController.text = _formatDate(picked);
      });
    }
  }

  String _formatDate(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _register() async {
    setState(() => _errorMessage = null);
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);
    try {
      // Through the service, not the API client, so a device with no connection
      // can still create an account (see AuthService.register).
      final doctor = await AuthService.instance.register(
        email: _emailController.text.trim(),
        password: _passwordController.text,
        fullName: _nameController.text.trim(),
        role: _role,
        licenseNumber: _licenseController.text.trim(),
        phone: _phoneController.text.trim(),
        hospitalName: _hospitalController.text.trim(),
        dateOfBirth: _dateOfBirth,
        inviteCode: _inviteCodeController.text.trim(),
      );
      if (!mounted) return;

      // A negative id means the device created the account because no server
      // answered. It is fully usable here, and it is not a server account, so
      // say so rather than letting someone believe it exists elsewhere.
      if (doctor.id < 0) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Account created on this device. Everything works offline; '
              'register again while connected to also create a server account.',
            ),
            backgroundColor: GhColors.attention(context),
            duration: const Duration(seconds: 6),
          ),
        );
        Navigator.of(context).pushReplacement(
          AppPageRoute(builder: (_) => const PractitionerDashboardScreen()),
        );
        return;
      }

      // A new account is inert until an administrator approves it. Sending
      // the user to the dashboard here would land them on a screen where
      // every request 401s, so send them back to sign-in with the reason.
      if (!doctor.isApproved) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Account created. An administrator must approve it before you '
              'can sign in.',
            ),
            backgroundColor: GhColors.attention(context),
            duration: const Duration(seconds: 6),
          ),
        );
        Navigator.of(context).pop();
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Account created. Welcome, ${doctor.fullName}!'),
          backgroundColor: GhColors.success(context),
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
    _inviteCodeController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _dateOfBirthController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: GhColors.canvasInset(context),
      body: SafeArea(
        child: AppPage(
          maxWidth: AppContentWidth.form,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context),
                const SizedBox(height: 16),
                if (_errorMessage != null) ...[
                  GhBanner(
                    _errorMessage!,
                    tone: GhTone.danger,
                    icon: Icons.error_outline,
                  ),
                  const SizedBox(height: 16),
                ],
                // One Form around both boxes so a single validate() reaches
                // all nine fields; the boxes are grouping for the eye only.
                Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildDetailsBox(context),
                      const SizedBox(height: 16),
                      _buildSecurityBox(context),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                GhButton(
                  'Create Account',
                  variant: GhButtonVariant.primary,
                  expanded: true,
                  busy: _isLoading,
                  onPressed: _isLoading ? null : _register,
                ),
                const SizedBox(height: 12),
                Center(
                  child: GhButton(
                    'Already have an account? Sign in',
                    variant: GhButtonVariant.link,
                    onPressed:
                        _isLoading ? null : () => Navigator.of(context).pop(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            Icon(
              Icons.medical_services_outlined,
              size: 20,
              color: GhColors.fgMuted(context),
            ),
            const SizedBox(width: 8),
            Text(
              'Join Simtack Care',
              style: GhType.sectionTitle.copyWith(color: GhColors.fg(context)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Create Practitioner Account',
          style: GhType.meta.copyWith(color: GhColors.fgMuted(context)),
        ),
      ],
    );
  }

  Widget _buildDetailsBox(BuildContext context) {
    return GhBox(
      header: 'Practitioner details',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          _field(
            label: 'Full Name',
            child: TextFormField(
              controller: _nameController,
              textInputAction: TextInputAction.next,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
              decoration: _fieldDecoration(icon: Icons.person_outline),
              validator: (value) => (value == null || value.trim().length < 2)
                  ? 'Enter your full name.'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Professional Email',
            child: TextFormField(
              controller: _emailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
              decoration: _fieldDecoration(icon: Icons.email_outlined),
              validator: _validateEmail,
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Role / Title',
            child: DropdownButtonFormField<String>(
              value: _role,
              isDense: true,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
              decoration: _fieldDecoration(icon: Icons.badge_outlined),
              items: _roles
                  .map((role) =>
                      DropdownMenuItem(value: role, child: Text(role)))
                  .toList(),
              onChanged:
                  _isLoading ? null : (value) => setState(() => _role = value),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: 'License / Registration Number',
            help: 'Self-declared for this deployment — verified out-of-band in '
                'real rollouts.',
            child: TextFormField(
              controller: _licenseController,
              textInputAction: TextInputAction.next,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
              decoration: _fieldDecoration(icon: Icons.verified_user_outlined),
              validator: (value) => (value == null || value.trim().isEmpty)
                  ? 'Enter your license or registration number.'
                  : null,
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Date of Birth (optional)',
            child: GestureDetector(
              onTap: _pickDateOfBirth,
              child: AbsorbPointer(
                child: TextFormField(
                  controller: _dateOfBirthController,
                  style: GhType.body.copyWith(color: GhColors.fg(context)),
                  decoration:
                      _fieldDecoration(icon: Icons.cake_outlined).copyWith(
                    hintText: 'YYYY-MM-DD',
                    hintStyle:
                        GhType.body.copyWith(color: GhColors.fgMuted(context)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Contact Phone',
            child: TextFormField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              textInputAction: TextInputAction.next,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
              decoration: _fieldDecoration(icon: Icons.phone_outlined),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Hospital / Facility',
            child: TextFormField(
              controller: _hospitalController,
              textInputAction: TextInputAction.next,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
              decoration: _fieldDecoration(icon: Icons.local_hospital_outlined),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSecurityBox(BuildContext context) {
    return GhBox(
      header: 'Account security',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Only required when the deployment has set an invite code (see
          // Settings.INVITE_CODE); a blank submission is fine otherwise — the
          // backend is the source of truth.
          _field(
            label: 'Invite Code (if required)',
            child: TextFormField(
              controller: _inviteCodeController,
              textInputAction: TextInputAction.next,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
              decoration: _fieldDecoration(icon: Icons.vpn_key_outlined),
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Password',
            help: 'At least 8 characters, including a letter and a number.',
            child: TextFormField(
              controller: _passwordController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.next,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
              decoration: _fieldDecoration(icon: Icons.lock_outline).copyWith(
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    size: 16,
                    color: GhColors.fgMuted(context),
                  ),
                  tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                  splashRadius: 16,
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
                suffixIconConstraints:
                    const BoxConstraints(minWidth: 34, minHeight: 32),
              ),
              validator: _validatePassword,
            ),
          ),
          const SizedBox(height: 12),
          _field(
            label: 'Confirm Password',
            child: TextFormField(
              controller: _confirmController,
              obscureText: _obscurePassword,
              textInputAction: TextInputAction.done,
              style: GhType.body.copyWith(color: GhColors.fg(context)),
              onFieldSubmitted: (_) => _register(),
              decoration: _fieldDecoration(icon: Icons.lock_outline),
              validator: (value) => value != _passwordController.text
                  ? 'Passwords do not match.'
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
