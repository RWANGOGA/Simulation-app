import 'package:flutter/material.dart';
import 'package:simtack/core/theme/app_tokens.dart';
import 'package:simtack/core/theme/app_accent.dart';
import 'package:simtack/core/theme/app_palette.dart';
import 'package:simtack/core/theme/app_page.dart';
import '../../../core/locale/app_languages.dart';
import '../../../core/locale/locale_controller.dart';
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
        child: AppPage(
          maxWidth: AppContentWidth.form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const FlowProgressBar(totalSteps: 6, currentStep: 1),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: FadeTransition(
                  opacity: _fadeIn,
                  child: SlideTransition(
                    position: _slideIn,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      decoration: BoxDecoration(
                        // The panel used to be a LinearGradient whose two stops
                        // were the same colour — a gradient that could not
                        // gradient. A flat fill is what it always rendered as.
                        //
                        // The fill is `primaryFill`, not `primary`: on the dark
                        // theme `primary` resolves to the light lavender
                        // (#A78BFA) that carries *text*, and white on it is about
                        // 1.9:1. `primaryFill` is the deep violet that white text
                        // sits on at 7.10:1 in both themes.
                        color: AppAccent.primaryFill,
                        borderRadius: BorderRadius.circular(AppRadius.xl),
                        boxShadow: AppShadow.soft(context),
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
                              borderRadius: BorderRadius.circular(AppRadius.lg),
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
                  padding: const EdgeInsets.only(top: AppSpacing.xl),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final option in _options)
                          Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.md),
                            child: _languageOption(
                              context,
                              code: option.flutterCode,
                              icon: option.icon,
                              label: _labelFor(t, option.flutterCode),
                            ),
                          ),
                        const SizedBox(height: AppSpacing.lg),
                        _consentCheckbox(context, t),
                      ],
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _continue,
                    // primaryFill, not primary: see the note on the hero panel.
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppAccent.primaryFill,
                      foregroundColor: AppAccent.onPrimary,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(AppRadius.md)),
                    ),
                    child: Text(
                      t.continueButton,
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: AppAccent.onPrimary),
                    ),
                  ),
                ),
              ),
            ],
          ),
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
        padding: const EdgeInsets.all(AppSpacing.lg),
        decoration: BoxDecoration(
          // Selected rows are a filled surface carrying white text, so they use
          // primaryFill for the same reason the button does.
          color:
              isSelected ? AppAccent.primaryFill : AppPalette.surface(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color:
                isSelected ? AppAccent.primaryFill : AppPalette.border(context),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            Icon(icon,
                size: 22,
                color: isSelected
                    ? AppAccent.onPrimary
                    : AppPalette.textMuted(context)),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: isSelected
                      ? AppAccent.onPrimary
                      : AppPalette.textPrimary(context),
                ),
              ),
            ),
            if (isSelected)
              const Icon(Icons.check_circle,
                  color: AppAccent.onPrimary, size: 22),
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
                  // The checkmark is white, so the box must be the deep fill.
                  activeColor: AppAccent.primaryFill,
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
              style: TextStyle(fontSize: 12, color: AppAccent.danger(context)),
            ),
          ),
      ],
    );
  }
}
