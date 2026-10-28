import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

import 'package:flutter/material.dart';
import 'package:simtack/core/theme/app_tokens.dart';
import 'package:simtack/core/theme/app_accent.dart';
import 'package:simtack/core/theme/app_palette.dart';
import 'package:simtack/core/theme/app_page.dart';
import 'package:flutter/services.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'anatomy_view.dart';
import 'anatomy_view_mode.dart';
import 'pain_details_screen.dart';
import 'pain_point.dart';
import 'web_interop.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/network/api_client.dart';
import '../../../core/offline/offline_repository.dart';
import '../../../core/widgets/anatomy_insight_card.dart';
import '../../../core/widgets/flow_progress_bar.dart';
import '../../../l10n/app_localizations.dart';

class BodyMapScreen extends StatefulWidget {
  final int patientId;
  final String? patientCode;
  final String gender;
  final double weightKg;
  final double heightCm;
  final String conversationId;

  BodyMapScreen({
    super.key,
    required this.patientId,
    this.patientCode,
    required this.gender,
    required this.weightKg,
    required this.heightCm,
    String? conversationId,
  }) : conversationId = conversationId ?? _generateConversationId();

  /// Returns the patient code, generating a temporary one for offline use.
  String get effectivePatientCode =>
      patientCode ?? 'OFFLINE-${patientId.abs()}';

  /// Unpredictable conversation id.
  ///
  /// This used to be `conv_<millis>_<microseconds % 10000>`, which is a
  /// timestamp: a few thousand candidates covers an entire shift. The server
  /// scopes a conversation to the caller, so behind a shared address - a
  /// hospital's NAT, say - a guessed id still reaches another patient's
  /// history. 128 bits from a secure source makes that infeasible.
  static String _generateConversationId() {
    final random = _secureRandom();
    final id = StringBuffer('conv_');
    // 32 hex digits = 128 bits. One nibble per call rather than
    // `nextInt(1 << 32)` per word: under dart2js `1 << 32` is 0, and
    // `Random.nextInt(0)` throws — which would stop the body map from opening at
    // all on the web (see OfflineRepository._token for the same trap).
    for (var i = 0; i < 32; i++) {
      id.write(random.nextInt(16).toRadixString(16));
    }
    return id.toString();
  }

  /// `Random.secure()` throws where a platform has no cryptographic source.
  /// Falling back to a time-seeded generator is weaker, but this id is a second
  /// layer behind the server-side scope, and losing the body map outright would
  /// be worse than a guessable id.
  static Random _secureRandom() {
    try {
      return Random.secure();
    } on UnsupportedError {
      debugPrint('No secure random available; conversation ids are guessable.');
      return Random();
    }
  }

  /// Picks the body model variant matching the patient's gender.
  /// BMI (weightKg/heightCm) isn't used yet — there's only one build per
  /// gender today.
  String get modelAsset {
    final file =
        gender == 'Male' ? 'human_body_male.glb' : 'human_body_female.glb';
    return kIsWeb ? 'models/$file' : 'assets/models/$file';
  }

  @override
  State<BodyMapScreen> createState() => _BodyMapScreenState();
}

class _BodyMapScreenState extends State<BodyMapScreen> {
  // Real on-image centroid for each KB region, measured directly from the
  // front-view BodyParts3D render (not guessed) — fixes a pre-existing
  // bug where picking a region from the manual list always dropped the
  // marker at dead-center of the canvas (0.5, 0.5) regardless of which
  // region was actually picked, e.g. choosing "Left Leg / Knee" visually
  // landed the marker up near the chest/arms instead of at the leg.
  static const Map<String, (double, double)> _regionCenterPosition = {
    'Headache / Cranial': (0.513, 0.277),
    'Neck': (0.513, 0.312),
    'Chest / Heart': (0.513, 0.417),
    'Abdomen (Upper)': (0.513, 0.44),
    'Abdomen (Lower Right)': (0.46, 0.47),
    'Abdomen (Lower Left)': (0.56, 0.47),
    'Hips / Groin': (0.513, 0.5),
    'Thighs': (0.513, 0.55),
    'Back Pain (Upper)': (0.513, 0.39),
    'Back Pain (Lower)': (0.513, 0.47),
    'Left Arm / Shoulder': (0.451, 0.408),
    'Right Arm / Shoulder': (0.574, 0.41),
    'Left Leg / Knee': (0.477, 0.592),
    'Right Leg / Knee': (0.548, 0.592),
  };

  // Every pain location the patient has tapped so far. Tapping the same
  // spot again (within PainPoint.sameSpotThreshold) removes it — this is
  // the multi-select toggle behavior.
  final List<PainPoint> _painPoints = [];

  // A brief floating label near the tap point naming exactly what was
  // touched (e.g. "Left ear" / "Distal phalanx of left index finger"),
  // shown for a moment right where the patient tapped, then cleared. This
  // replaced an earlier confirmation bottom sheet that interrupted every
  // single tap with a "Confirm & Describe Pain" modal and its own
  // re-pick-from-a-short-list step — reported directly as breaking the
  // flow and undoing the 3D view's own precision (e.g. tapping the ear
  // only offered to re-file it under the broad "Headache / Cranial" from a
  // 4-item list). Tapping now adds the location immediately; PainDetails
  // (the next screen) is still where symptom description/quality get
  // captured per point, same as before.
  ({String text, double x, double y})? _tapLabel;
  Timer? _tapLabelTimer;

  // The 3D body view (Anatomy3DTapView) is a real iframe, a browser
  // element that keeps receiving taps for its own screen area even while
  // a Flutter bottom sheet or dialog is drawn visually on top of it — the
  // same root cause as the Locations button once being unreachable while
  // it floated over the iframe (see the AppBar move for that one). A
  // sheet sliding up from the bottom overlaps the iframe's area too, so
  // the same fix applies: stop the iframe from accepting touches at all
  // for as long as any sheet or dialog is open on top of it. A count,
  // not a bool: the region picker sheet opens from inside the locations
  // sheet, so a bool would wrongly re-enable the iframe when the inner
  // one closes while the outer one is still open. Every
  // showModalBottomSheet/showDialog call in this screen increments this
  // before opening and decrements it once it closes.
  int _openOverlayCount = 0;

  // Which renderer the body is drawn with. Starts at `auto` (3D where the
  // platform can host it, the flat image everywhere else) and is replaced by
  // the stored preference once that has been read, so the very first frame
  // always has a working renderer rather than a blank box.
  AnatomyViewMode _viewMode = AnatomyViewMode.auto;

  // One in-flight AI request per region. Keyed by region label so
  // re-tapping the same region (toggle-off then on) does not re-fetch
  // when an answer is already loading.
  final Map<String, Future<AnatomyInsight>> _anatomyFutures = {};

  // Patient answers to suggested anatomy questions, keyed by region.
  final Map<String, Map<String, String>> _questionAnswers = {};

  @override
  void initState() {
    super.initState();
    AnatomyViewModeStore.load().then((mode) {
      if (!mounted) return;
      setState(() => _viewMode = mode);
    });
  }

  @override
  void dispose() {
    _tapLabelTimer?.cancel();
    super.dispose();
  }

  /// Applies a renderer choice and remembers it, so a patient who prefers the
  /// flat view — or whose device struggles with the 3D one — does not have to
  /// pick it again on every visit.
  void _setViewMode(AnatomyViewMode mode) {
    if (mode == _viewMode) return;
    setState(() => _viewMode = mode);
    AnatomyViewModeStore.save(mode);
  }

  /// Only the flat renderer reports misses (the 3D viewer swallows its own),
  /// and a miss is the one case where the patient tapped the body and nothing
  /// happened, so it has to say why.
  void _showMiss(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ));
  }

  /// Called by [AnatomyView], which hands over a tap already resolved to one
  /// of the region strings `body_graph.json` is keyed on — the 3D viewer does
  /// that in `region-map.js`, and the flat renderer's seven coarse ID-map
  /// labels are translated by [backendRegionFor2D] before reaching here, so
  /// nothing downstream has to care which renderer produced the tap.
  ///
  /// [flatViewKey] is the flat angle the tap came from, or null for the 3D
  /// viewer. It is stored on the point because a fraction of the front image
  /// and the same fraction of the back image are different places on a body.
  ///
  /// `tap.partName` is the precise structure tapped; `tap.hitX/hitY/hitZ` is
  /// the real 3D point on the body, stored on the PainPoint so a marker can be
  /// drawn as an actual object in the 3D scene (rotates correctly with the
  /// body) instead of a flat overlay that only lined up at the camera angle
  /// from the moment of the tap. Adds (or, on a repeat tap of the same spot,
  /// removes) the location immediately and fires its AI insight request — no
  /// confirmation step in between; a brief label naming the tapped structure
  /// shows right at the tap point instead.
  void _handleBodyPartReceived(BodyPartTap tap, String? flatViewKey) {
    final region = tap.part;
    final x = tap.x ?? 0.5;
    final y = tap.y ?? 0.5;
    if (!kReleaseMode) {
      debugPrint(
          'BodyMap: received tap -> region=$region partName=${tap.partName} x=$x y=$y view=$flatViewKey hit=(${tap.hitX},${tap.hitY},${tap.hitZ})');
    }
    _addOrRemovePainPoint(
      region: region,
      x: x,
      y: y,
      hitX: tap.hitX,
      hitY: tap.hitY,
      hitZ: tap.hitZ,
      viewKey: flatViewKey,
    );
    _requestAnatomyInsight(region);

    // Show the resolved, human-meaningful region (e.g. "Right Hand"), not
    // the raw BodyParts3D mesh name in tap.partName — an exterior tap
    // almost always hits the single outer "Skin" mesh itself, so
    // tap.partName is "Skin" for nearly every tap regardless of where on
    // the body it landed, which is not useful shown to a patient. region
    // is what the geometry/keyword classifier actually resolved that tap
    // to, and is what the pain point and AI insight below are keyed on
    // too, so the label now matches what's actually being recorded.
    _tapLabelTimer?.cancel();
    setState(() {
      _tapLabel = (text: region, x: x, y: y);
    });
    _tapLabelTimer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      setState(() => _tapLabel = null);
    });
  }

  /// Multi-select toggle: tapping a fresh spot adds a new pain point.
  /// Tapping close to an existing point removes it instead — this is how
  /// a patient "unmarks" a location without a separate delete step.
  void _addOrRemovePainPoint({
    required String region,
    double? x,
    double? y,
    double? hitX,
    double? hitY,
    double? hitZ,
    String? viewKey,
    String? symptomDescription,
    List<String>? tags,
  }) {
    final tapX = x ?? 0.5;
    final tapY = y ?? 0.5;

    // The viewKey has to be part of "the same spot" as well as the distance:
    // the same fraction on the front image and on the back image are opposite
    // sides of the patient. Without this, tapping the chest in the front view
    // and then the back view at a similar height would silently remove the
    // first point instead of adding the second.
    final existingIndex = _painPoints.indexWhere(
      (p) => p.viewKey == viewKey && p.isNearby(tapX, tapY),
    );

    HapticFeedback.mediumImpact();
    setState(() {
      if (existingIndex != -1) {
        _painPoints.removeAt(existingIndex);
      } else {
        _painPoints.add(PainPoint(
          region: region,
          x: tapX,
          y: tapY,
          viewKey: viewKey,
          hitX: hitX,
          hitY: hitY,
          hitZ: hitZ,
          symptomDescription: symptomDescription,
          tags: tags,
        ));
      }
    });
  }

  void _removePainPointAt(int index) {
    HapticFeedback.lightImpact();
    final removed = _painPoints[index];
    setState(() {
      _painPoints.removeAt(index);
      // If no other point still references this region, drop the cached
      // AI insight so it doesn't keep showing for a region the user
      // un-marked.
      if (!_painPoints.any((p) => p.region == removed.region)) {
        _anatomyFutures.remove(removed.region);
      }
    });
  }

  /// Manually add a region from the picker list. Places the marker at that
  /// region's real measured position on the body image (see
  /// [_regionCenterPosition]) instead of always dropping it dead-center —
  /// used as a fallback for regions that are awkward to tap precisely, or
  /// for accessibility.
  void _addRegionManually(String region) {
    HapticFeedback.lightImpact();
    final position = _regionCenterPosition[region] ?? (0.5, 0.5);
    setState(() {
      _painPoints
          .add(PainPoint(region: region, x: position.$1, y: position.$2));
    });
    _requestAnatomyInsight(region);
  }

  /// Fires a background /anatomy/ask request for the given region and complaint.
  /// The future is stored per-region so the FutureBuilder in the insight
  /// panel can show loading → ready transitions without rebuilding the
  /// whole screen. Multiple regions load in parallel.
  void _requestAnatomyInsight(String region, {String complaint = ''}) {
    if (_anatomyFutures.containsKey(region)) return;
    final future = OfflineRepository.instance.askAnatomy(
      region: region,
      complaint: complaint,
      topK: 3,
      conversationId: widget.conversationId,
    );
    setState(() {
      _anatomyFutures[region] = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppAccent.primary(context)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          t.bodyMapSelectPainTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppPalette.textPrimary(context),
          ),
        ),
        centerTitle: true,
        actions: [
          // Was a floating pill overlaid on top of the 3D view further
          // down (inside the same Stack as Anatomy3DTapView). That view
          // is a real iframe (a Flutter Web platform view), and a real
          // browser iframe can swallow every tap within its rectangle
          // regardless of what a Flutter widget paints visually on top of
          // it, so the pill looked present but never actually opened the
          // sheet. Living here in the AppBar instead, it is genuine
          // Flutter canvas with no iframe anywhere near it, so the tap is
          // guaranteed to reach it.
          Badge(
            label: Text('${_painPoints.length}'),
            isLabelVisible: _painPoints.isNotEmpty,
            backgroundColor: AppAccent.danger(context),
            child: IconButton(
              icon: Icon(Icons.location_on, color: AppAccent.primary(context)),
              tooltip: _painPoints.isEmpty
                  ? t.tapABodyPartLabel
                  : t.locationsSelectedLabel(_painPoints.length),
              onPressed: _openSelectedLocationsScreen,
            ),
          ),
          IconButton(
            icon: Icon(Icons.help_outline, color: AppAccent.primary(context)),
            onPressed: _showHelp,
          ),
        ],
        bottom: const PreferredSize(
          preferredSize: Size.fromHeight(20),
          child: FlowProgressBar(totalSteps: 6, currentStep: 3),
        ),
      ),
      body: Column(
        children: [
          // 3D Canvas Area
          Expanded(
            flex: 3,
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // Real interactive 3D body (BodyParts3D geometry) — tap
                    // anywhere on the model, rotate/zoom with drag/scroll
                    // directly on it (built into the embedded viewer, no
                    // separate toolbar needed the way the old 2D
                    // front/back/left/right + zoom buttons were). Reports
                    // taps already resolved to one of the backend's 14 KB
                    // region strings, plus the precise structure name
                    // (partName) for display — see anatomy_3d_tap_view.dart.
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              AppPalette.subtleFill(context),
                              AppAccent.primary(context).withOpacity(0.06),
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: IgnorePointer(
                                ignoring: _openOverlayCount > 0,
                                child: AnatomyView(
                                  gender: widget.gender,
                                  mode: _viewMode,
                                  onModeChanged: _setViewMode,
                                  onRegionTapped: _handleBodyPartReceived,
                                  onMiss: _showMiss,
                                  tapLabel:
                                      _viewMode.renders3D() ? null : _tapLabel,
                                  // Markers in either coordinate system; the
                                  // renderer draws the ones it can place. The
                                  // 3D viewer draws points carrying real hit
                                  // coordinates inside the scene itself (see
                                  // viewer.js's setMarkers) so they stay
                                  // attached through rotation; the flat view
                                  // draws points carrying a matching viewKey.
                                  // A point from the manual picker has neither
                                  // and is simply skipped by both rather than
                                  // drawn at a guessed spot.
                                  markers: [
                                    for (var i = 0; i < _painPoints.length; i++)
                                      (
                                        id: '$i',
                                        x: _painPoints[i].hitX,
                                        y: _painPoints[i].hitY,
                                        z: _painPoints[i].hitZ,
                                        viewKey: _painPoints[i].viewKey,
                                      ),
                                  ],
                                ),
                              ),
                            ),
                            // A gentle nudge for first-time patients — fades
                            // once at least one location is marked, since
                            // the badge/panel below take over from there.
                            if (_painPoints.isEmpty)
                              Positioned(
                                left: 0,
                                right: 0,
                                bottom: 16,
                                child: Center(
                                  child: IgnorePointer(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 16, vertical: 10),
                                      decoration: BoxDecoration(
                                        color: AppPalette.surface(context)
                                            .withOpacity(0.92),
                                        borderRadius: BorderRadius.circular(20),
                                        boxShadow: [
                                          BoxShadow(
                                            color:
                                                Colors.black.withOpacity(0.08),
                                            blurRadius: 10,
                                            offset: const Offset(0, 3),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.threed_rotation,
                                              size: 16,
                                              color:
                                                  AppAccent.primary(context)),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Rotate to look around, tap where it hurts',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                              color: AppPalette.textSecondary(
                                                  context),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            // Names exactly what was just tapped, right at
                            // the tap point, then fades — the replacement
                            // for the old confirmation modal's "Detected:
                            // ..." line, without stopping to ask anything.
                            // The flat renderer draws its own label, inside the
                            // letterboxed image rectangle it measured. Drawing
                            // this one over it as well would either double the
                            // label or place it at a box fraction while the dots
                            // use an image fraction.
                            if (_tapLabel != null && _viewMode.renders3D())
                              AnimatedPositioned(
                                duration: const Duration(milliseconds: 200),
                                left: (_tapLabel!.x * constraints.maxWidth)
                                        .clamp(0, constraints.maxWidth) -
                                    90,
                                top: _tapLabel!.y * constraints.maxHeight - 56,
                                width: 180,
                                child: IgnorePointer(
                                  child: AnimatedOpacity(
                                    key: ValueKey(_tapLabel),
                                    opacity: 1,
                                    duration: const Duration(milliseconds: 150),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 6),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: AppPalette.textPrimary(context)
                                            .withOpacity(0.92),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        _tapLabel!.text,
                                        textAlign: TextAlign.center,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Navigation CTA Button — disabled until at least one location
          // is marked, since there's nothing to carry into Pain Details
          // otherwise.
          Container(
            width: double.infinity,
            color: AppPalette.surface(context),
            child: SafeArea(
              top: false,
              child: AppPage.bar(
                SizedBox(
                  width: double.infinity,
                  height: 54,
                  child: ElevatedButton(
                    onPressed: _painPoints.isEmpty
                        ? null
                        : () {
                            HapticFeedback.selectionClick();
                            _navigateToPainDetails();
                          },
                    // Flat deep fill instead of elevation 3 plus a violet
                    // glow, and primaryFill rather than primary so the white
                    // label clears 7.10:1 in both themes.
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppAccent.primaryFill,
                      foregroundColor: AppAccent.onPrimary,
                      disabledBackgroundColor: AppPalette.border(context),
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _painPoints.isEmpty
                              ? t.tapBodyToMarkPain
                              : t.continueToPainDetailsButton(
                                  _painPoints.length),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppAccent.onPrimary,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        const Icon(Icons.arrow_forward,
                            color: AppAccent.onPrimary, size: 20),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // A bottom sheet floating over the 3D body previously covered this, but
  // the 3D view is a real iframe (a Flutter Web platform view) and kept
  // swallowing every tap meant for the sheet regardless of what was
  // drawn on top of it — attempting to gate that with IgnorePointer (see
  // _openOverlayCount, still used by _showHelp below) did not reliably
  // stop it either. A dedicated page sidesteps the problem entirely:
  // pushing a new route removes the previous screen, iframe included,
  // from what can actually receive touches, so there is nothing left
  // for it to swallow.
  void _openSelectedLocationsScreen() {
    Navigator.of(context)
        .push(
      AppPageRoute(
        builder: (_) => _SelectedLocationsPage(
          painPoints: _painPoints,
          anatomyFutureFor: (region) => _anatomyFutures[region],
          initialAnswersFor: (region) => _questionAnswers[region],
          onRemove: _removePainPointAt,
          onAnswersChanged: (region, answers) =>
              _questionAnswers[region] = answers,
          onAddRegion: _addRegionManually,
        ),
      ),
    )
        .then((_) {
      // The pushed page mutates the same _painPoints/_questionAnswers
      // objects directly, so this screen's own state is already correct
      // underneath — it just needs a rebuild to show it (the badge count,
      // the Continue button) now that it's visible again.
      if (mounted) setState(() {});
    });
  }

  void _showHelp() {
    final t = AppLocalizations.of(context)!;
    setState(() => _openOverlayCount++);
    showDialog(
      context: context,
      builder: (dialogContext) => PointerInterceptor(
        child: AlertDialog(
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg)),
          title: Row(
            children: [
              Icon(Icons.help_outline, color: AppAccent.primary(context)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  t.bodyMapHelpTitle,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppPalette.textPrimary(context),
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(t.bodyMapHelpBullet1),
                const SizedBox(height: 8),
                Text(t.bodyMapHelpBullet2),
                const SizedBox(height: 8),
                Text(t.bodyMapHelpBullet3),
                const SizedBox(height: 8),
                Text(t.bodyMapHelpBullet4),
                const SizedBox(height: 8),
                Text(t.bodyMapHelpBullet5),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                t.gotItButton,
                style: TextStyle(
                  color: AppAccent.primary(context),
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ),
          ],
        ),
      ),
    ).whenComplete(() {
      if (mounted) setState(() => _openOverlayCount--);
    });
  }

  void _navigateToPainDetails() {
    for (final point in _painPoints) {
      final answers = _questionAnswers[point.region];
      if (answers != null && answers.isNotEmpty) {
        point.questionAnswers.addAll(answers);
      }
    }
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => PainDetailsScreen(
          painPoints: _painPoints,
          patientId: widget.patientId,
          patientCode: widget.effectivePatientCode,
          modelAsset: widget.modelAsset,
        ),
      ),
    );
  }
}

/// A dedicated page for reviewing and managing marked pain locations, in
/// place of a bottom sheet — see the comment on
/// _BodyMapScreenState._openSelectedLocationsScreen for why a sheet
/// could not reliably be dismissed or interacted with here (the 3D body
/// view behind it is a real iframe that kept eating its taps). This page
/// reads and mutates the same painPoints list and per-region maps that
/// BodyMapScreen owns (passed down by reference, not copied), so the
/// caller sees the same changes once this page is popped.
class _SelectedLocationsPage extends StatefulWidget {
  const _SelectedLocationsPage({
    required this.painPoints,
    required this.anatomyFutureFor,
    required this.initialAnswersFor,
    required this.onRemove,
    required this.onAnswersChanged,
    required this.onAddRegion,
  });

  final List<PainPoint> painPoints;
  final Future<AnatomyInsight>? Function(String region) anatomyFutureFor;
  final Map<String, String>? Function(String region) initialAnswersFor;
  final void Function(int index) onRemove;
  final void Function(String region, Map<String, String> answers)
      onAnswersChanged;
  final void Function(String region) onAddRegion;

  @override
  State<_SelectedLocationsPage> createState() => _SelectedLocationsPageState();
}

class _SelectedLocationsPageState extends State<_SelectedLocationsPage> {
  static const _regionOptions = [
    'Abdomen (Lower Right)',
    'Abdomen (Lower Left)',
    'Abdomen (Upper)',
    'Chest / Heart',
    'Headache / Cranial',
    'Back Pain (Lower)',
    'Back Pain (Upper)',
    'Right Arm / Shoulder',
    'Left Arm / Shoulder',
    'Right Leg / Knee',
    'Left Leg / Knee',
  ];

  void _openRegionPicker() {
    final t = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return PointerInterceptor(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Text(
                    t.selectPainLocationTitle,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppPalette.textPrimary(context),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: ListView.builder(
                    shrinkWrap: true,
                    itemCount: _regionOptions.length,
                    itemBuilder: (context, index) {
                      final item = _regionOptions[index];
                      final alreadyAdded =
                          widget.painPoints.any((p) => p.region == item);
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          alreadyAdded
                              ? Icons.check_circle
                              : Icons.location_on_outlined,
                          color: alreadyAdded
                              ? AppAccent.primary(context)
                              : AppPalette.textMuted(context),
                        ),
                        title: Text(
                          item,
                          style: TextStyle(
                            fontWeight: alreadyAdded
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: alreadyAdded
                                ? AppAccent.primary(context)
                                : AppPalette.textSecondary(context),
                          ),
                        ),
                        onTap: () {
                          if (!alreadyAdded) {
                            widget.onAddRegion(item);
                            setState(() {});
                          }
                          Navigator.of(sheetContext).pop();
                        },
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final t = AppLocalizations.of(context)!;
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: AppAccent.primary(context)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          t.painLocationsSheetTitle,
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: AppPalette.textPrimary(context),
          ),
        ),
      ),
      body: SafeArea(
        child: widget.painPoints.isEmpty
            ? AppPage(
                child: Text(
                  t.noLocationsMarkedHint,
                  style: TextStyle(color: AppPalette.textMuted(context)),
                ),
              )
            : AppPage(
                scrollable: true,
                child: ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  padding: EdgeInsets.zero,
                  itemCount: widget.painPoints.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(height: AppSpacing.md),
                  itemBuilder: (context, index) {
                    final point = widget.painPoints[index];
                    return Container(
                      decoration: BoxDecoration(
                        color: AppPalette.scaffold(context),
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                        border: Border.all(color: AppPalette.border(context)),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                                width: 4, color: AppAccent.primary(context)),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(12, 10, 4, 0),
                                    child: Row(
                                      children: [
                                        Container(
                                          width: 24,
                                          height: 24,
                                          alignment: Alignment.center,
                                          decoration: const BoxDecoration(
                                            shape: BoxShape.circle,
                                            // A filled marker carries a number
                                            // in white, so it needs the fill
                                            // token: `primary` resolves to
                                            // lavender #A78BFA in dark mode,
                                            // where white text is 1.9:1.
                                            color: AppAccent.primaryFill,
                                          ),
                                          child: Text(
                                            '${index + 1}',
                                            style: const TextStyle(
                                              color: AppAccent.onPrimary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            point.region,
                                            style: TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.bold,
                                              color: AppPalette.textPrimary(
                                                  context),
                                            ),
                                          ),
                                        ),
                                        IconButton(
                                          icon:
                                              const Icon(Icons.close, size: 18),
                                          color: AppPalette.textMuted(context),
                                          tooltip: t.removeTooltip,
                                          onPressed: () {
                                            widget.onRemove(index);
                                            setState(() {});
                                          },
                                        ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding:
                                        const EdgeInsets.fromLTRB(4, 0, 4, 4),
                                    child: AnatomyInsightCard(
                                      region: point.region,
                                      future:
                                          widget.anatomyFutureFor(point.region),
                                      initialAnswers: widget
                                          .initialAnswersFor(point.region),
                                      onAnswersChanged: (answers) {
                                        widget.onAnswersChanged(
                                            point.region, answers);
                                      },
                                      selectedCondition:
                                          point.symptomDescription,
                                      onConditionSelected: (condition) {
                                        setState(() {
                                          point.symptomDescription = condition;
                                        });
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: AppPage.bar(
          OutlinedButton.icon(
            onPressed: _openRegionPicker,
            icon: Icon(Icons.add_circle_outline,
                color: AppAccent.primary(context)),
            label: Text(
              t.addAnotherLocationLabel,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppAccent.primary(context)),
            ),
          ),
        ),
      ),
    );
  }
}
