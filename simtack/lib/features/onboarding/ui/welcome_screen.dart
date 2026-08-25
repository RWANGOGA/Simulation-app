import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/storage/draft_storage.dart';
import '../../../core/storage/triage_draft.dart';
import '../../patient_info/ui/patient_info_screen.dart';
import '../../review/ui/review_screen.dart';
import '../../../core/theme/app_page_route.dart';

import '../../auth/ui/login_screen.dart';

class WelcomeScreen extends StatefulWidget {
  const WelcomeScreen({super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  String _selectedLanguage = 'English';

  // Every offline draft saved on this device, newest first. The banner
  // shows the most recent one; when there are several, "Choose" opens a
  // picker so none of them are hidden behind the latest.
  List<TriageDraft> _drafts = [];

  final List<_LanguageOption> _languages = const [
    _LanguageOption('English', null),
    _LanguageOption('Uganda Sign Language', Icons.back_hand_outlined),
    _LanguageOption('Luganda', null),
    _LanguageOption('Lusoga', null),
  ];

  @override
  void initState() {
    super.initState();
    _loadDrafts();
  }

  Future<void> _loadDrafts() async {
    final drafts = await DraftStorage.loadAll();
    if (mounted) setState(() => _drafts = drafts);
  }

  void _resumeDraft(TriageDraft draft) {
    if (draft.painPoints.isEmpty) return;
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

  Future<void> _deleteDraft(TriageDraft draft) async {
    await DraftStorage.remove(draft);
    await _loadDrafts();
  }

  String _draftSubtitle(TriageDraft draft) {
    final first = draft.painPoints.first;
    final extraCount = draft.painPoints.length - 1;
    final base = extraCount > 0
        ? '${first.region} · ${first.painType} (+$extraCount more)'
        : '${first.region} · ${first.painType}';
    final savedOn = DateFormat('d MMM, HH:mm').format(draft.savedAt);
    return '$base · saved $savedOn';
  }

  /// Lets the patient pick which of several saved drafts to resume.
  void _showDraftPicker() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(
                  'Saved drafts',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: _drafts.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final draft = _drafts[index];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      leading: const Icon(Icons.history_edu_outlined, color: Color(0xFF6D28D9)),
                      title: Text(
                        _draftSubtitle(draft),
                        style: const TextStyle(fontSize: 13, color: Color(0xFF1E293B)),
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20, color: Color(0xFF94A3B8)),
                        tooltip: 'Delete draft',
                        onPressed: () async {
                          await _deleteDraft(draft);
                          if (!sheetContext.mounted) return;
                          if (_drafts.isEmpty) {
                            Navigator.of(sheetContext).pop();
                          } else {
                            setSheetState(() {});
                          }
                        },
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _resumeDraft(draft);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumeDraftBanner() {
    if (_drafts.isEmpty) return const SizedBox.shrink();
    final draft = _drafts.first;
    if (draft.painPoints.isEmpty) return const SizedBox.shrink();

    final title = _drafts.length == 1
        ? 'You have a saved draft'
        : 'You have ${_drafts.length} saved drafts';

    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF6D28D9).withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFF6D28D9).withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.history_edu_outlined, color: Color(0xFF6D28D9)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1E293B)),
                ),
                Text(
                  _draftSubtitle(draft),
                  style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _drafts.length == 1 ? () => _resumeDraft(draft) : _showDraftPicker,
            child: Text(_drafts.length == 1 ? 'Resume' : 'Choose'),
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
              // 🚪 Top-right actions: Language Pill + Practitioner Login
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    _buildLanguagePill(),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(builder: (_) => const LoginScreen()),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.lock_outline, size: 16, color: Color(0xFF6D28D9)),
                          SizedBox(width: 4),
                          Text(
                            'Practitioner Login',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF6D28D9),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
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

              // Scrollable middle: the draft banner + language list can grow
              // past short viewports without pushing the footer off-screen.
              // Wrapping these in Expanded is what fixed the RenderFlex
              // overflow the fixed-height Spacer used to cause on small
              // screens.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildResumeDraftBanner(),

                      // Language Selector
                      ..._languages.map((lang) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _buildLanguageOption(lang),
                          )),
                    ],
                  ),
                ),
              ),

              // Spacer removed — the Expanded above absorbs leftover space,
              // keeping the footer pinned to the bottom on tall screens.
              const SizedBox(height: 16),

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