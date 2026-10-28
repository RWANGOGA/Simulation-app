import 'package:flutter/material.dart';
import '../../../core/network/api_client.dart';
import '../../../core/network/auth_service.dart';
import '../../../core/theme/app_page.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/github_kit.dart';
import '../../../core/theme/github_palette.dart';
import '../../dashboard/ui/practitioner_dashboard_screen.dart';
import '../../onboarding/ui/welcome_screen.dart';
import '../../patient_info/ui/patient_info_screen.dart';
import 'register_screen.dart';

/// GitHub's sign-in box is about 340px wide. 400 keeps a long address on one
/// line without the form sprawling across a desktop window — and it is below
/// [AppContentWidth.form], because a sign-in is narrower than a form.
const double _authBoxWidth = 400;

/// The practitioner console's front door, in Primer.
///
/// This used to be laid out as a patient hero — a purple glyph over a
/// full-window form — even though it is the screen a clinician opens ten times
/// a day. A sign-in box with two labelled fields and one action is what makes
/// it unambiguous; the two patient entry points sit *below* the box as
/// secondary actions, because starting a triage is not the same commitment as
/// signing in.
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
          backgroundColor: GhColors.success(context),
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
      // `canvas.inset` rather than the canvas itself: a sign-in box needs a
      // recessed ground to read as a box. Primer uses the same pairing on its
      // own authentication pages.
      backgroundColor: GhColors.canvasInset(context),
      body: SafeArea(
        child: AppPage(
          maxWidth: AppContentWidth.form,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Centred when there is room, scrollable when there is not — the
              // minHeight forces the box to the middle of a tall window while
              // still letting a short one scroll instead of overflowing.
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: SizedBox(
                      width: _authBoxWidth,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildBrand(context),
                          const SizedBox(height: 20),
                          _buildSignInBox(context),
                          const SizedBox(height: 16),
                          _buildPatientEntryPoints(context),
                          const SizedBox(height: 20),
                          _buildCreateAccountRow(context),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  /// Wordmark and purpose, not a decorative glyph. The icon carries the same
  /// muted weight as the rest of the chrome so the only coloured thing on the
  /// screen is the button that signs you in.
  Widget _buildBrand(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.medical_services_outlined,
              size: 20,
              color: GhColors.fgMuted(context),
            ),
            const SizedBox(width: 8),
            Text(
              'Practitioner Portal',
              style: GhType.sectionTitle.copyWith(color: GhColors.fg(context)),
            ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          'Simtack Care',
          style: GhType.meta.copyWith(color: GhColors.fgMuted(context)),
        ),
      ],
    );
  }

  Widget _buildSignInBox(BuildContext context) {
    return GhBox(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_errorMessage != null) ...[
            GhBanner(
              _errorMessage!,
              tone: GhTone.danger,
              icon: Icons.error_outline,
            ),
            const SizedBox(height: 12),
          ],
          GhTextField(
            controller: _emailController,
            label: 'Email address',
            hint: 'you@hospital.org',
            prefixIcon: Icons.mail_outline,
            keyboardType: TextInputType.emailAddress,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: 12),
          GhTextField(
            controller: _passwordController,
            label: 'Password',
            hint: 'Your password',
            prefixIcon: Icons.lock_outline,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _login(),
            suffix: IconButton(
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
          ),
          const SizedBox(height: 16),
          GhButton(
            'Sign In',
            variant: GhButtonVariant.primary,
            expanded: true,
            busy: _isLoading,
            onPressed: _isLoading ? null : _login,
          ),
        ],
      ),
    );
  }

  /// Starting a patient is a different job from signing in, so these sit
  /// outside the box as secondary buttons rather than competing with Sign In.
  Widget _buildPatientEntryPoints(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        GhButton(
          'Register Patient',
          icon: Icons.person_add_alt_1,
          variant: GhButtonVariant.secondary,
          expanded: true,
          onPressed: _isLoading
              ? null
              : () => Navigator.of(context).push(
                    AppPageRoute(builder: (_) => const WelcomeScreen()),
                  ),
        ),
        const SizedBox(height: 8),
        GhButton(
          'Quick Patient Entry',
          icon: Icons.fast_forward,
          variant: GhButtonVariant.secondary,
          expanded: true,
          onPressed: _isLoading
              ? null
              : () => Navigator.of(context).push(
                    AppPageRoute(builder: (_) => const PatientInfoScreen()),
                  ),
        ),
      ],
    );
  }

  /// A [Wrap] rather than a [Row]: on a 320px device the prompt and the link
  /// together are wider than the box, and a Row would overflow.
  Widget _buildCreateAccountRow(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'New practitioner?',
          style: GhType.body.copyWith(color: GhColors.fgMuted(context)),
        ),
        const SizedBox(width: 4),
        GhButton(
          'Create an account',
          variant: GhButtonVariant.link,
          onPressed: _isLoading
              ? null
              : () => Navigator.of(context).push(
                    AppPageRoute(builder: (_) => const RegisterScreen()),
                  ),
        ),
      ],
    );
  }
}
