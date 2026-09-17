import 'package:flutter/material.dart';
import '../../../core/locale/app_languages.dart';
import '../../../core/locale/locale_controller.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/widgets/flow_progress_bar.dart';
import '../../../l10n/app_localizations.dart';
import 'welcome_screen.dart';

/// Blueprint §1: the very first thing a patient sees. Picks the app's
/// language and captures data-processing consent before anything else
/// runs — shown once; LocaleController persists both so later launches
/// skip straight past it (see AtomyBridgeApp's routing in main.dart).
class LanguageScreen extends StatefulWidget {
  final LocaleController localeController;

  const LanguageScreen({super.key, required this.localeController});

  @override
  State<LanguageScreen> createState() => _LanguageScreenState();
}

class _LanguageScreenState extends State<LanguageScreen>
    with SingleTickerProviderStateMixin {
  String _selectedCode = 'en';
  bool _consented = false;
  bool _showConsentError = false;

  static const _options = AppLanguages.pickerOptions;

  // A brief fade + rise on first paint — this is literally the first
  // frame anyone ever sees of the app, and it was previously a hard cut
  // to a flat page with no sense of arrival.
  late final AnimationController _introController;
  late final Animation<double> _fadeIn;
  late final Animation<Offset> _slideIn;

  @override
  void initState() {
    super.initState();
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
    _fadeIn = CurvedAnimation(parent: _introController, curve: Curves.easeOut);
    _slideIn = Tween<Offset>(begin: const Offset(0, 0.06), end: Offset.zero)
        .animate(CurvedAnimation(
            parent: _introController, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _introController.dispose();
    super.dispose();
  }

  String _labelFor(AppLocalizations t, String code) {
    switch (code) {
      case 'lg':
        return t.languageLuganda;
      case 'nyn':
        return t.languageRunyankole;
      case 'xog':
        return t.languageLusoga;
      case 'sw':
        return t.languageKiswahili;
      case LocaleController.signLanguageCode:
        return t.languageSignLanguage;
      default:
        return t.languageEnglish;
    }
  }

  Future<void> _continue() async {
    if (!_consented) {
      setState(() => _showConsentError = true);
      return;
    }
    await widget.localeController.setLanguageAndConsent(
      languageCode: _selectedCode,
      consented: true,
    );
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      AppPageRoute(builder: (_) => const WelcomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    // This screen renders in the device's current locale until the patient
    // picks one — AppLocalizations.of falls back to English/system if
    // "lg" support isn't active yet, which is exactly what we want here.
    final t = AppLocalizations.of(context)!;

    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const FlowProgressBar(totalSteps: 6, currentStep: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
              child: FadeTransition(
                opacity: _fadeIn,
                child: SlideTransition(
                  position: _slideIn,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [Color(0xFF6D28D9), Color(0xFF8B5CF6)],
                      ),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFF6D28D9).withOpacity(0.25),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.18),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(Icons.medical_services_rounded,
                              size: 30, color: Colors.white),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          t.chooseLanguageTitle,
                          style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                              height: 1.2),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          t.chooseLanguageSubtitle,
                          style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withOpacity(0.85)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final option in _options)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _languageOption(
                            context,
                            code: option.flutterCode,
                            icon: option.icon,
                            label: _labelFor(t, option.flutterCode),
                          ),
                        ),
                      const SizedBox(height: 16),
                      _consentCheckbox(context, t),
                    ],
                  ),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _continue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D28D9),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    t.continueButton,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                        color: Colors.white),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _languageOption(BuildContext context,
      {required String code, required IconData icon, required String label}) {
    final isSelected = _selectedCode == code;
    return GestureDetector(
      onTap: () => setState(() => _selectedCode = code),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF6D28D9)
              : AppPalette.surface(context),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? const Color(0xFF6D28D9)
                : AppPalette.border(context),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color:
                    isSelected ? Colors.white : AppPalette.textMuted(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? Colors.white
                      : AppPalette.textPrimary(context),
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.white, size: 22),
          ],
        ),
      ),
    );
  }

  Widget _consentCheckbox(BuildContext context, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() {
            _consented = !_consented;
            if (_consented) _showConsentError = false;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Checkbox(
                  value: _consented,
                  activeColor: const Color(0xFF6D28D9),
                  onChanged: (value) => setState(() {
                    _consented = value ?? false;
                    if (_consented) _showConsentError = false;
                  }),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(
                      t.consentText,
                      style: TextStyle(
                          fontSize: 13,
                          color: AppPalette.textSecondary(context)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (_showConsentError)
          Padding(
            padding: const EdgeInsets.only(left: 12),
            child: Text(
              t.consentRequiredError,
              style: const TextStyle(fontSize: 12, color: Color(0xFFDC2626)),
            ),
          ),
      ],
    );
  }
}
