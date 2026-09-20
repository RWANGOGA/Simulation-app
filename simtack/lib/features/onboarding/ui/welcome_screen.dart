import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../../../core/theme/app_palette.dart';
import '../../settings/ui/accessibility_settings_screen.dart';
import 'package:intl/intl.dart';
import '../../../core/storage/draft_storage.dart';
import '../../../core/storage/draft_sync_service.dart';
import '../../../core/storage/patient_draft_sync_service.dart';
import '../../../core/storage/doctor_draft_sync_service.dart';
import '../../../core/storage/triage_draft.dart';
import '../../../core/network/connectivity_service.dart';
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

  late final StreamSubscription<ConnectivityResult> _connectivitySubscription;

  @override
  void initState() {
    super.initState();
    _initConnectivityListener();
    _syncThenLoadDrafts();
  }

  @override
  void dispose() {
    _connectivitySubscription.cancel();
    super.dispose();
  }

  void _initConnectivityListener() {
    _connectivitySubscription = ConnectivityService.instance.onConnectivityChanged.listen((result) {
      final wasOffline = !ConnectivityService.instance.isOnline;
      
      // Update cached result
      ConnectivityService.instance.updateCachedResult(result);
      
      // If we just came online, trigger sync
      if (wasOffline && ConnectivityService.instance.isOnline) {
        _syncThenLoadDrafts();
      }
    });
  }

// Auto-sync runs at startup and whenever connectivity is restored.
  Future<void> _syncThenLoadDrafts() async {
    final triageSynced = await DraftSyncService.syncAll();
    final patientSynced = await PatientDraftSyncService.syncAll();
    final doctorSynced = await DoctorDraftSyncService.syncAll();
    final totalSynced = triageSynced + patientSynced + doctorSynced;

    await _loadDrafts();

    if (totalSynced > 0 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .draftsSyncedSnackbar(totalSynced)),
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
          patientCode: draft.patientCode,
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
                      leading: const Icon(Icons.history_edu_outlined,
                          color: Color(0xFF6D28D9)),
                      title: Text(
                        _draftSubtitle(draft),
                        style: TextStyle(
                            fontSize: 13,
                            color: AppPalette.textPrimary(context)),
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline,
                            size: 20, color: AppPalette.textMuted(context)),
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

  /// Two-tone headline, description, and a stats row, styled after a
  /// reference the user shared directly (a landing-page hero: a big
  /// headline with one phrase picked out in the accent color, a supporting
  /// sentence underneath, product visual on the other side) — the earlier
  /// version was just "Welcome" / "Let's get started" as two plain lines,
  /// reported as boring next to that reference.
  ///
  /// No badge here: an earlier version had a small "AI-powered triage"
  /// pill above the headline — reported directly as unwanted, so it's
  /// removed for good, not just hidden. The stats row fills the space a
  /// badge (or, before that, empty vertical gap the user also flagged
  /// directly) would have — three real facts about the app instead of a
  /// label.
  ///
  /// welcomeHeadlinePrefix/welcomeHeadlineHighlight/welcomeDescription/
  /// welcomeStat* are real English copy grounded in what the app actually
  /// does (README: AI assisted, offline first triage with a 3D body map
  /// and explainable risk insights) — added as new translation keys in
  /// app_en.arb rather than editing generated files directly;
  /// `flutter gen-l10n` auto-filled the English text into the other four
  /// locales for just these new keys (confirmed by inspection, not
  /// assumed), so non-English users still get everything else on this
  /// screen properly translated and only these new lines in English until
  /// real translations are written. welcomeTitle/welcomeSubtitle/
  /// welcomeBadge (now removed) are left in the arb files unused rather
  /// than deleted, in case anything ever wants them again.
  Widget _welcomeHeader(BuildContext context, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: t.welcomeHeadlinePrefix,
                style: TextStyle(color: AppPalette.textPrimary(context)),
              ),
              TextSpan(
                text: t.welcomeHeadlineHighlight,
                style: const TextStyle(color: Color(0xFF6D28D9)),
              ),
            ],
          ),
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            height: 1.15,
          ),
        ),
        const SizedBox(height: 14),
        Text(
          t.welcomeDescription,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: AppPalette.textMuted(context),
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 28,
          runSpacing: 16,
          children: [
            _welcomeStat(
                context, t.welcomeStatRegionsValue, t.welcomeStatRegionsLabel),
            _welcomeStat(
                context, t.welcomeStatOfflineValue, t.welcomeStatOfflineLabel),
            _welcomeStat(
                context, t.welcomeStatSpeedValue, t.welcomeStatSpeedLabel),
          ],
        ),
      ],
    );
  }

  Widget _welcomeStat(BuildContext context, String value, String label) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 19,
            fontWeight: FontWeight.bold,
            color: AppPalette.textPrimary(context),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: AppPalette.textMuted(context)),
        ),
      ],
    );
  }

  Widget _buildResumeDraftBanner() {
    if (_drafts.isEmpty) return const SizedBox.shrink();
    final draft = _drafts.first;
    if (draft.painPoints.isEmpty) return const SizedBox.shrink();

    final title =
        AppLocalizations.of(context)!.savedDraftBanner(_drafts.length);

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
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppPalette.textPrimary(context)),
                ),
                Text(
                  _draftSubtitle(draft),
                  style: TextStyle(
                      fontSize: 12, color: AppPalette.textMuted(context)),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: _drafts.length == 1
                ? () => _resumeDraft(draft)
                : _showDraftPicker,
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
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 700;
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: isWide
                  ? _buildWideLayout(context, t)
                  : _buildNarrowLayout(context, t),
            );
          },
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.centerRight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.lock_outline,
                        size: 16, color: Color(0xFF6D28D9)),
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
        // The header grew substantially taller (badge + multi-line
        // headline + a full paragraph, versus the old two short lines),
        // and only the resume-draft banner used to be scrollable — on a
        // shorter viewport (a laptop browser window, or this exact 800x600
        // default test surface) the fixed-height header now genuinely
        // doesn't always fit above the fixed-height button/caption at the
        // bottom. Pulling the header and 3D model into the same scrollable
        // region as the banner fixes that generally, not just for this one
        // new header.
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _welcomeHeader(context, t),
                const SizedBox(height: 24),
                SizedBox(
                  height: 220,
                  child: _ThreeDPlaceholder(
                    web: SizedBox.expand(
                      child: ModelViewer(
                        src: kIsWeb
                            ? 'models/human_body_male.glb'
                            : 'assets/models/human_body_male.glb',
                        alt: '3D Human Body Model',
                        autoRotate: true,
                        cameraControls: true,
                        backgroundColor: Colors.transparent,
                        // Default lighting/shadow was flat and boring — no
                        // ground shadow at all (shadowIntensity defaults to
                        // 0) and no environment reflections, which is why
                        // the model read as a dull gray silhouette. This
                        // gives it real form: an evenly-lit neutral
                        // environment, a touch more exposure, and a soft
                        // grounding shadow.
                        environmentImage: 'neutral',
                        exposure: 1.15,
                        shadowIntensity: 0.8,
                        shadowSoftness: 0.9,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                _buildResumeDraftBanner(),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
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
    );
  }

  Widget _buildWideLayout(BuildContext context, AppLocalizations t) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 4,
                  children: [
                    IconButton(
                      tooltip: t.displayAccessibilityTooltip,
                      icon: Icon(Icons.tune,
                          color: AppPalette.textMuted(context)),
                      onPressed: () {
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => const AccessibilitySettingsScreen(),
                          ),
                        );
                      },
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.of(context).push(
                          AppPageRoute(builder: (_) => const LoginScreen()),
                        );
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.lock_outline,
                              size: 16, color: Color(0xFF6D28D9)),
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
              // Same reasoning as the narrow layout: the header grew
              // substantially taller, and a fixed-height header above a
              // fixed-height button/caption can overflow on a shorter
              // viewport — this is genuinely where that happened (a plain
              // 800x600 window). Scrolling the header along with the
              // banner fixes it generally.
              Expanded(
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _welcomeHeader(context, t),
                      const SizedBox(height: 24),
                      _buildResumeDraftBanner(),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
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
        const SizedBox(width: 32),
        Expanded(
          child: _ThreeDPlaceholder(
            web: SizedBox.expand(
              child: ModelViewer(
                src: kIsWeb
                    ? 'models/human_body_male.glb'
                    : 'assets/models/human_body_male.glb',
                alt: '3D Human Body Model',
                autoRotate: true,
                cameraControls: true,
                backgroundColor: Colors.transparent,
                // Default lighting/shadow was flat and boring — no ground
                // shadow at all (shadowIntensity defaults to 0) and no
                // environment reflections, which is why the model read as
                // a dull gray silhouette. This gives it real form: an
                // evenly-lit neutral environment, a touch more exposure,
                // and a soft grounding shadow.
                environmentImage: 'neutral',
                exposure: 1.15,
                shadowIntensity: 0.8,
                shadowSoftness: 0.9,
              ),
            ),
          ),
        ),
      ],
    );
  }

  void _navigateToPatientInfo() {
    Navigator.of(context).push(
      AppPageRoute(builder: (_) => const PatientInfoScreen()),
    );
  }
}

/// Renders the live 3D model on web, and a static placeholder elsewhere.
///
/// On mobile, `model_viewer_plus` instantiates a `webview_flutter` platform
/// view that has no default stub in widget tests, so we gate it behind
/// `kIsWeb` to keep the welcome screen testable.
class _ThreeDPlaceholder extends StatelessWidget {
  final Widget web;
  const _ThreeDPlaceholder({required this.web});

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) return web;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF6D28D9).withOpacity(0.10),
            const Color(0xFF8B5CF6).withOpacity(0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.2)),
      ),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.medical_services, size: 48, color: Color(0xFF6D28D9)),
            SizedBox(height: 8),
            Text(
              '3D body model',
              style: TextStyle(
                color: Color(0xFF6D28D9),
                fontWeight: FontWeight.w600,
              ),
            ),
            SizedBox(height: 4),
            Text(
              'Tap below to start triage',
              style: TextStyle(color: Color(0xFF64748B), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
