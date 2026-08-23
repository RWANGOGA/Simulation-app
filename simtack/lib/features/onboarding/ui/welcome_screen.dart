import 'package:flutter/material.dart';
import '../../../core/storage/draft_storage.dart';
import '../../../core/storage/triage_draft.dart';
import '../../patient_info/ui/patient_info_screen.dart';
import '../../review/ui/review_screen.dart';
import '../../../core/theme/app_page_route.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String _selectedLanguage = 'English';
  TriageDraft? _draft;

  final List<_LanguageOption> _languages = const [
    _LanguageOption('English', null),
    _LanguageOption('Uganda Sign Language', Icons.back_hand_outlined),
    _LanguageOption('Luganda', null),
    _LanguageOption('Lusoga', null),
  ];

  @override
  void initState() {
    super.initState();
    _loadDraft();
  }

  Future<void> _loadDraft() async {
    final draft = await DraftStorage.load();
    if (mounted) setState(() => _draft = draft);
  }

  void _resumeDraft() {
    final draft = _draft;
    if (draft == null || draft.painPoints.isEmpty) return;
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ReviewScreen(
          painPoints: draft.painPoints,
          heartRate: draft.heartRate,
          spo2: draft.spo2,
          patientId: draft.patientId,
        ),
      ),
    );
  }

  Widget _buildResumeDraftBanner() {
    final draft = _draft;
    if (draft == null || draft.painPoints.isEmpty) return const SizedBox.shrink();

    final first = draft.painPoints.first;
    final extraCount = draft.painPoints.length - 1;
    final subtitle = extraCount > 0
        ? '${first.region} · ${first.painType} (+$extraCount more)'
        : '${first.region} · ${first.painType}';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF6D28D9).withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_edu_outlined, color: Color(0xFF6D28D9)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'You have a saved draft',
                  style: TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                Text(
                  subtitle,
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _resumeDraft,
            child: const Text('Resume'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top-right language pill
              Align(
                alignment: Alignment.centerRight,
                child: _buildLanguagePill(),
              ),
              const SizedBox(height: 24),

              // Header
              const Text(
                'Welcome',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF1E293B),
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Choose your language',
                style: TextStyle(
                  fontSize: 15,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 24),

              _buildResumeDraftBanner(),

              // Language Selector
              ..._languages.map((lang) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _buildLanguageOption(lang),
                  )),

              const Spacer(),

              // Continue Button
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => _navigateToPatientInfo(),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D28D9),
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Privacy caption
              const Center(
                child: Text(
                  'Your data stays on this device.\nYou are in control.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLanguagePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _selectedLanguage,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: Color(0xFF1E293B),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(Icons.keyboard_arrow_down, size: 16, color: Color(0xFF64748B)),
        ],
      ),
    );
  }

  Widget _buildLanguageOption(_LanguageOption option) {
    final isSelected = _selectedLanguage == option.name;
    return GestureDetector(
      onTap: () {
        setState(() => _selectedLanguage = option.name);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? const Color(0xFF6D28D9) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFFE2E8F0),
            width: 2,
          ),
        ),
        child: Row(
          children: [
            if (option.icon != null) ...[
              Icon(
                option.icon,
                size: 20,
                color: isSelected ? Colors.white : const Color(0xFF64748B),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Text(
                option.name,
                textAlign: option.icon == null ? TextAlign.center : TextAlign.start,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: isSelected ? Colors.white : const Color(0xFF1E293B),
                ),
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle,
                color: Colors.white,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }

  void _navigateToPatientInfo() {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const PatientInfoScreen()),
    );
  }
}

class _LanguageOption {
  final String name;
  final IconData? icon;
  const _LanguageOption(this.name, this.icon);
}