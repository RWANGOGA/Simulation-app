import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:simtack/core/theme/app_tokens.dart';
import 'package:simtack/core/theme/app_accent.dart';
import 'package:simtack/core/theme/app_palette.dart';
import 'package:simtack/core/theme/app_page.dart';
import 'package:simtack/core/theme/app_breakpoints.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'dart:async';
import '../../settings/ui/accessibility_settings_screen.dart';
import 'package:intl/intl.dart';
import '../../../core/storage/draft_storage.dart';
import '../../../core/storage/patient_draft_sync_service.dart';
import '../../../core/storage/triage_draft.dart';
import '../../../core/network/connectivity_service.dart';
import '../../../core/offline/sync_service.dart';
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
    _connectivitySubscription =
        ConnectivityService.instance.onConnectivityChanged.listen((result) {
      final wasOffline = !ConnectivityService.instance.isOnline;

      // Update cached result
      ConnectivityService.instance.updateCachedResult(result);

      // If we just came online, trigger sync
      if (wasOffline && ConnectivityService.instance.isOnline) {
        _syncThenLoadDrafts();
      }
    });
  }

  /// Runs at startup and whenever connectivity is restored: finishes recording
  /// any profile that was saved before the device could store it, then pushes
  /// whatever this device has recorded to the server if it can be reached.
  ///
  /// Saved drafts are deliberately NOT submitted here. Submitting a report now
  /// writes to this device and cannot fail for want of a connection, so a draft
  /// is the patient's own note-to-self — "I will finish this later" — and the
  /// banner below lists them for exactly that reason. Uploading and deleting
  /// them at launch would destroy the work the banner offers to resume.
  Future<void> _syncThenLoadDrafts() async {
    final profilesCommitted = await PatientDraftSyncService.syncAll();
    final sync = await SyncService.instance.syncNow();
    final totalSynced = profilesCommitted + sync.uploaded;

    await _loadDrafts();

    if (totalSynced > 0 && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(AppLocalizations.of(context)!
                .draftsSyncedSnackbar(totalSynced)),
            backgroundColor: AppAccent.success(context),
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
                      leading: Icon(Icons.history_edu_outlined,
                          color: AppAccent.primary(context)),
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
                style: TextStyle(color: AppAccent.primary(context)),
              ),
            ],
          ),
          style: const TextStyle(
            fontSize: 34,
            fontWeight: FontWeight.bold,
            height: 1.12,
            // Slight negative tracking is what makes a display size read as
            // set rather than typed at 34px with default spacing.
            letterSpacing: -0.6,
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          t.welcomeDescription,
          style: TextStyle(
            fontSize: 15,
            height: 1.5,
            color: AppPalette.textMuted(context),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        _statBand(context, t),
      ],
    );
  }

  /// The three product facts, set as one divided band.
  ///
  /// They used to be a `Wrap(spacing: 28)` whose items sized to their own text,
  /// so the columns had ragged left edges and the third could wrap onto a line
  /// of its own. A row of equal thirds with hairline rules between them is both
  /// tidier and honest about the fact that these are peers.
  Widget _statBand(BuildContext context, AppLocalizations t) {
    final stats = <(String, String)>[
      (t.welcomeStatRegionsValue, t.welcomeStatRegionsLabel),
      (t.welcomeStatOfflineValue, t.welcomeStatOfflineLabel),
      (t.welcomeStatSpeedValue, t.welcomeStatSpeedLabel),
    ];
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0)
              VerticalDivider(
                width: AppSpacing.xl + AppSpacing.sm,
                thickness: 1,
                color: AppPalette.border(context),
              ),
            Expanded(
              child: _welcomeStat(context, stats[i].$1, stats[i].$2),
            ),
          ],
        ],
      ),
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
        color: AppAccent.primary(context).withOpacity(0.08),
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: AppAccent.primary(context).withOpacity(0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.history_edu_outlined, color: AppAccent.primary(context)),
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

  /// The live 3D model, shared by both layouts.
  ///
  /// It used to be pasted into each layout with the same twenty-line block of
  /// comments, so the two copies could drift. Default lighting/shadow on the
  /// raw viewer is flat — no ground shadow at all (`shadowIntensity` defaults
  /// to 0) and no environment reflections, which is why the model read as a
  /// dull grey silhouette. A neutral environment, a touch more exposure and a
  /// soft grounding shadow give it real form.
  static const Widget _modelViewer = SizedBox.expand(
    child: ModelViewer(
      src: kIsWeb
          ? 'models/human_body_male.glb'
          : 'assets/models/human_body_male.glb',
      alt: '3D Human Body Model',
      autoRotate: true,
      cameraControls: true,
      backgroundColor: Colors.transparent,
      environmentImage: 'neutral',
      exposure: 1.15,
      shadowIntensity: 0.8,
      shadowSoftness: 0.9,
    ),
  );

  /// The two things a patient might want before starting: bigger type, or the
  /// clinician side of the app.
  ///
  /// These used to be an `IconButton` stacked *above* a `TextButton` in an
  /// end-aligned `Column`, which read as two unrelated controls competing in
  /// the corner. They are one row now, vertically centred, with the more
  /// consequential action first and the utility last — the order an app bar
  /// uses.
  Widget _topActions(BuildContext context, AppLocalizations t) {
    return Row(
      children: [
        const Spacer(),
        TextButton.icon(
          onPressed: () {
            Navigator.of(context).push(
              AppPageRoute(builder: (_) => const LoginScreen()),
            );
          },
          icon: const Icon(Icons.lock_outline, size: 16),
          label: Text(t.practitionerLogin),
          style: TextButton.styleFrom(
            foregroundColor: AppAccent.primary(context),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            textStyle:
                const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ),
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
      ],
    );
  }

  /// The call to action and the privacy caption, which are identical in both
  /// layouts and were previously written out twice.
  Widget _footer(BuildContext context, AppLocalizations t) {
    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            onPressed: _navigateToPatientInfo,
            // primaryFill, not primary: this is a filled surface carrying
            // white text. In the dark theme `primary` resolves to the light
            // lavender that carries *text* (#A78BFA), and white on it is
            // about 1.9:1. primaryFill is the deep violet that white sits on
            // at 7.10:1.
            style: ElevatedButton.styleFrom(
              backgroundColor: AppAccent.primaryFill,
              foregroundColor: AppAccent.onPrimary,
              disabledBackgroundColor: AppPalette.border(context),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
              ),
            ),
            child: Text(
              t.continueButton,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppAccent.onPrimary,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        SizedBox(
          width: double.infinity,
          child: Text(
            t.privacyCaption,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              color: AppPalette.textMuted(context),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      body: SafeArea(
        child: AppPage(
          maxWidth: AppContentWidth.wide,
          child: LayoutBuilder(
            builder: (context, constraints) {
              // Material 3's medium window class, not the old private 700:
              // below it there is no honest second column, and at 700 there
              // was not one either — two 340px columns with the model making
              // a postage stamp of the headline.
              final twoColumn = AppBreakpoints.hasRoomForSecondColumn(
                constraints.maxWidth,
              );
              return twoColumn
                  ? _buildWideLayout(context, t)
                  : _buildNarrowLayout(context, t);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildNarrowLayout(BuildContext context, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topActions(context, t),
        const SizedBox(height: AppSpacing.xl),
        // The header, model and banner all share one scroll region. An earlier
        // version had a fixed-height header above a fixed-height button and
        // genuinely overflowed on a short viewport; the fix still holds, it
        // just lives inside the shared page frame now instead of a 24px
        // hand-rolled padding.
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _welcomeHeader(context, t),
                const SizedBox(height: AppSpacing.xl),
                const SizedBox(
                  height: 220,
                  child: _ThreeDPlaceholder(web: _modelViewer),
                ),
                const SizedBox(height: AppSpacing.xl),
                _buildResumeDraftBanner(),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        _footer(context, t),
      ],
    );
  }

  Widget _buildWideLayout(BuildContext context, AppLocalizations t) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _topActions(context, t),
        const SizedBox(height: AppSpacing.xl),
        Expanded(
          child: Row(
            // stretch, not start: the model panel is a panel, so it should
            // fill the column beside it rather than collapse to the height of
            // its own children.
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                // Text column is wider than the visual column: a 34px
                // headline needs more measure than a 3D viewer does.
                flex: 5,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _welcomeHeader(context, t),
                            const SizedBox(height: AppSpacing.xl),
                            _buildResumeDraftBanner(),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    _footer(context, t),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xxl),
              const Expanded(
                flex: 4,
                child: _ThreeDPlaceholder(web: _modelViewer),
              ),
            ],
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
        // Flat tint, not a two-stop gradient: the old one ran 0.10 to 0.05 of
        // the same violet, which is a gradient that cannot gradient — it
        // rendered as a barely-there wash. A flat surface from the one tint
        // ramp is what the panel actually is.
        color: AppAccent.primaryTint(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppAccent.primary(context).withOpacity(0.2)),
      ),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.medical_services,
                size: 48, color: AppAccent.primary(context)),
            const SizedBox(height: AppSpacing.sm),
            Text(
              '3D body model',
              style: TextStyle(
                color: AppAccent.primary(context),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Tap below to start triage',
              style:
                  TextStyle(color: AppPalette.textMuted(context), fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}
