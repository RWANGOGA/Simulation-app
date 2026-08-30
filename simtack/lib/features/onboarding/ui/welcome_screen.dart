import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
import 'package:intl/intl.dart';
import '../../../core/storage/draft_storage.dart';
import '../../../core/storage/draft_sync_service.dart';
import '../../../core/storage/triage_draft.dart';
import '../../../l10n/app_localizations.dart';
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
  // Every offline draft saved on this device, newest first. The banner
  // shows the most recent one; when there are several, "Choose" opens a
  // picker so none of them are hidden behind the latest.
  List<TriageDraft> _drafts = [];

  @override
  void initState() {
    super.initState();
    _syncThenLoadDrafts();
  }

  // Auto-sync runs once, at startup, before the drafts are loaded for
  // display — any draft that syncs successfully disappears from the
  // banner/picker entirely rather than briefly flashing then vanishing.
  Future<void> _syncThenLoadDrafts() async {
    final syncedCount = await DraftSyncService.syncAll();
    await _loadDrafts();
    if (syncedCount > 0 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!.draftsSyncedSnackbar(syncedCount)),
            backgroundColor: const Color(0xFF16A34A),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    }
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
    final t = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.surface(context),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Text(
                  t.savedDraftsTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppPalette.textPrimary(context),
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
                        style: TextStyle(fontSize: 13, color: AppPalette.textPrimary(context)),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline, size: 20, color: AppPalette.textMuted(context)),
                        tooltip: t.deleteDraftTooltip,
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

    final title = AppLocalizations.of(context)!.savedDraftBanner(_drafts.length);

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
                Text(
                  title,
                  style: TextStyle(fontWeight: FontWeight.bold, color: AppPalette.textPrimary(context)),
                ),
                Text(
                  _draftSubtitle(draft),
                  style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _drafts.length == 1 ? () => _resumeDraft(draft) : _showDraftPicker,
            child: Text(_drafts.length == 1
                ? AppLocalizations.of(context)!.resumeButton
                : AppLocalizations.of(context)!.chooseButton),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 🚪 Top-right actions: Accessibility + Practitioner Login.
              // Language is chosen once, earlier, on LanguageScreen.
              Align(
                alignment: Alignment.centerRight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    // Display & accessibility: enlarge/reduce text, dark mode.
                    IconButton(
                      tooltip: t.displayAccessibilityTooltip,
                      icon: Icon(Icons.tune, color: AppPalette.textMuted(context)),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AccessibilitySettingsScreen(),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 8),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          AppPageRoute(builder: (_) => const LoginScreen()),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline, size: 16, color: Color(0xFF6D28D9)),
                          const SizedBox(width: 4),
                          Text(
                            t.practitionerLogin,
                            style: const TextStyle(
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
              Text(
                t.welcomeTitle,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: AppPalette.textPrimary(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                t.welcomeSubtitle,
                style: TextStyle(
                  fontSize: 15,
                  color: AppPalette.textMuted(context),
                ),
              ),
              const SizedBox(height: 24),

              // Scrollable middle: the draft banner can grow past short
              // viewports without pushing the footer off-screen.
              Expanded(
                child: SingleChildScrollView(
                  child: _buildResumeDraftBanner(),
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
                  child: Text(
                    t.continueButton,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // Privacy caption
              Center(
                child: Text(
                  t.privacyCaption,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppPalette.textMuted(context),
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

  void _navigateToPatientInfo() {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const PatientInfoScreen()),
    );
  }
}