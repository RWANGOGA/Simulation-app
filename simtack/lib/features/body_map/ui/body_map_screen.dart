import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;

import 'package:flutter/material.dart';
import '../../../core/theme/app_palette.dart';
import 'package:flutter/services.dart';
import 'anatomy_3d_tap_view.dart';
import 'pain_details_screen.dart';
import 'pain_point.dart';
import '../../../core/theme/app_page_route.dart';
import '../../../core/network/api_client.dart';
import '../../../core/widgets/anatomy_insight_card.dart';
import '../../../core/widgets/flow_progress_bar.dart';
import '../../../l10n/app_localizations.dart';

class BodyMapScreen extends StatefulWidget {
  final int patientId;
  final String patientCode;
  final String gender;
  final double weightKg;
  final double heightCm;
  final String conversationId;

  BodyMapScreen({
    super.key,
    required this.patientId,
    required this.patientCode,
    required this.gender,
    required this.weightKg,
    required this.heightCm,
    String? conversationId,
  }) : conversationId = conversationId ?? _generateConversationId();

  static String _generateConversationId() {
    return 'conv_${DateTime.now().millisecondsSinceEpoch}_${(DateTime.now().microsecond % 10000).toString().padLeft(4, '0')}';
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

class _BodyMapScreenState extends State<BodyMapScreen>
    with SingleTickerProviderStateMixin {
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

  // One in-flight AI request per region. Keyed by region label so
  // re-tapping the same region (toggle-off then on) does not re-fetch
  // when an answer is already loading.
  final Map<String, Future<AnatomyInsight>> _anatomyFutures = {};

  // Patient answers to suggested anatomy questions, keyed by region.
  final Map<String, Map<String, String>> _questionAnswers = {};

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _tapLabelTimer?.cancel();
    super.dispose();
  }

  /// Called by [Anatomy3DTapView], which already resolves a tap all the way
  /// down to one of the backend's 14 fixed KB region strings itself (see
  /// assets/anatomy3d/region-map.js) — no further mapping needed here,
  /// unlike the old 2D system this replaced. [partName] is the precise
  /// structure tapped. Adds (or, on a repeat tap of the same spot, removes)
  /// the location immediately and fires its AI insight request — no
  /// confirmation step in between; a brief label naming the tapped
  /// structure shows right at the tap point instead.
  void _handleBodyPartReceived(
      String region, double x, double y, String? partName) {
    if (!kReleaseMode) {
      debugPrint(
          'BodyMap: received tap -> region=$region partName=$partName x=$x y=$y');
    }
    _addOrRemovePainPoint(region: region, x: x, y: y);
    _requestAnatomyInsight(region);

    _tapLabelTimer?.cancel();
    setState(() {
      _tapLabel = (text: partName ?? region, x: x, y: y);
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
    String? symptomDescription,
    List<String>? tags,
  }) {
    final tapX = x ?? 0.5;
    final tapY = y ?? 0.5;

    final existingIndex = _painPoints.indexWhere((p) => p.isNearby(tapX, tapY));

    HapticFeedback.mediumImpact();
    setState(() {
      if (existingIndex != -1) {
        _painPoints.removeAt(existingIndex);
      } else {
        _painPoints.add(PainPoint(
          region: region,
          x: tapX,
          y: tapY,
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
    final future = ApiClient.askAnatomy(
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
          icon: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)),
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
          IconButton(
            icon: const Icon(Icons.help_outline, color: Color(0xFF6D28D9)),
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
                              const Color(0xFF6D28D9).withOpacity(0.06),
                            ],
                          ),
                        ),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Anatomy3DTapView(
                                gender: widget.gender,
                                onRegionTapped: _handleBodyPartReceived,
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
                                          const Icon(Icons.threed_rotation,
                                              size: 16,
                                              color: Color(0xFF6D28D9)),
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
                            // Pain hotspot pulses, positioned as fractions
                            // of this same box — matches the normalized x/y
                            // the 3D viewer reports (fraction of its own
                            // canvas), same convention the 2D system used.
                            for (final point in _painPoints)
                              Positioned(
                                left: point.x * constraints.maxWidth - 22,
                                top: point.y * constraints.maxHeight - 22,
                                child: IgnorePointer(
                                  child: AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      return Container(
                                        width:
                                            32 + (12 * _pulseController.value),
                                        height:
                                            32 + (12 * _pulseController.value),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFFEF4444)
                                              .withOpacity(0.35 *
                                                  (1 - _pulseController.value)),
                                          border: Border.all(
                                            color: const Color(0xFFEF4444),
                                            width: 2,
                                          ),
                                        ),
                                        child: Center(
                                          child: Container(
                                            width: 14,
                                            height: 14,
                                            decoration: const BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: Color(0xFFDC2626),
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            // Names exactly what was just tapped, right at
                            // the tap point, then fades — the replacement
                            // for the old confirmation modal's "Detected:
                            // ..." line, without stopping to ask anything.
                            if (_tapLabel != null)
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
                                        color: const Color(0xFF1E293B)
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

                    // Selected Locations Badge (Top Right Overlay)
                    // Now shows a count instead of a single region name,
                    // and opens the manage-list sheet instead of a picker
                    // that would overwrite the current selection.
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: _showSelectedLocationsSheet,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6D28D9),
                            borderRadius: BorderRadius.circular(24),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFF6D28D9).withOpacity(0.3),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.location_on,
                                  color: Colors.white, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _painPoints.isEmpty
                                    ? t.tapABodyPartLabel
                                    : t.locationsSelectedLabel(
                                        _painPoints.length),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down,
                                  color: Colors.white, size: 18),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),

          // Marked Locations Report — every tapped region's full AI insight,
          // appended in order into ONE continuously-scrolling panel instead
          // of separate side-scrolling cards. The earlier horizontal
          // carousel (one narrow 280px card per region, swipe sideways to
          // see the next) was reported as scattering related information
          // across the screen instead of collecting it — tap the eye, then
          // the ear, then a foot, and each result landed in its own
          // disconnected card. This is the single organized place all of
          // that now lives, appended as each location is confirmed.
          // With nothing marked yet, this panel only has one line of hint
          // text — giving it a fixed 40% flex share regardless left the 3D
          // body squeezed into a sliver at the top. It now takes just
          // enough height for that hint, and only claims real flexible
          // space once there's an actual list of locations worth scrolling.
          _painPoints.isEmpty
              ? Container(
                  decoration: BoxDecoration(
                    color: AppPalette.surface(context),
                    border: Border(
                      top: BorderSide(color: AppPalette.border(context)),
                    ),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFF6D28D9).withOpacity(0.1),
                        ),
                        child: const Icon(Icons.front_hand_outlined,
                            color: Color(0xFF6D28D9), size: 22),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Your pain report will appear here',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppPalette.textPrimary(context),
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              t.noLocationsMarkedHint,
                              style: TextStyle(
                                fontSize: 12,
                                color: AppPalette.textMuted(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                )
              : Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppPalette.scaffold(context),
                      border: Border(
                        top: BorderSide(color: AppPalette.border(context)),
                      ),
                    ),
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 14, 12, 8),
                      itemCount: _painPoints.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 10),
                      itemBuilder: (context, i) {
                        final point = _painPoints[i];
                        // A left accent stripe needs a different color than
                        // the rest of the border, and Flutter can't paint a
                        // rounded border whose sides aren't a single
                        // uniform color — so the accent is its own thin
                        // Container in a Row instead of a BorderSide, with
                        // the outer border kept uniform.
                        return Container(
                          decoration: BoxDecoration(
                            color: AppPalette.surface(context),
                            borderRadius: BorderRadius.circular(16),
                            border:
                                Border.all(color: AppPalette.border(context)),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withOpacity(0.04),
                                blurRadius: 8,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          clipBehavior: Clip.antiAlias,
                          // IntrinsicHeight resolves the stripe's height
                          // against the Column's — without it, Row's
                          // stretch cross-axis alignment has no bounded
                          // height to stretch to inside a ListView item
                          // (whose height is otherwise unbounded), and
                          // layout fails with "BoxConstraints forces an
                          // infinite height".
                          child: IntrinsicHeight(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Container(
                                    width: 4, color: const Color(0xFF6D28D9)),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            12, 10, 4, 0),
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 24,
                                              height: 24,
                                              alignment: Alignment.center,
                                              decoration: const BoxDecoration(
                                                shape: BoxShape.circle,
                                                color: Color(0xFF6D28D9),
                                              ),
                                              child: Text(
                                                '${i + 1}',
                                                style: const TextStyle(
                                                  color: Colors.white,
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
                                              icon: const Icon(Icons.close,
                                                  size: 18),
                                              color:
                                                  AppPalette.textMuted(context),
                                              tooltip: t.removeTooltip,
                                              onPressed: () =>
                                                  _removePainPointAt(i),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(
                                            4, 0, 4, 4),
                                        child: AnatomyInsightCard(
                                          region: point.region,
                                          future: _anatomyFutures[point.region],
                                          initialAnswers:
                                              _questionAnswers[point.region],
                                          onAnswersChanged: (answers) {
                                            setState(() {
                                              _questionAnswers[point.region] =
                                                  answers;
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

          // Navigation CTA Button — disabled until at least one location
          // is marked, since there's nothing to carry into Pain Details
          // otherwise.
          Container(
            padding: const EdgeInsets.all(20),
            color: AppPalette.surface(context),
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: _painPoints.isEmpty
                      ? null
                      : () {
                          HapticFeedback.selectionClick();
                          _navigateToPainDetails();
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D28D9),
                    disabledBackgroundColor: const Color(0xFFCBD5E1),
                    elevation: 3,
                    shadowColor: const Color(0xFF6D28D9).withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        _painPoints.isEmpty
                            ? t.tapBodyToMarkPain
                            : t.continueToPainDetailsButton(_painPoints.length),
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward,
                          color: Colors.white, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showSelectedLocationsSheet() {
    final t = AppLocalizations.of(context)!;
    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.surface(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Text(
                        t.painLocationsSheetTitle,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_painPoints.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 16),
                        child: Text(
                          t.noLocationsMarkedHint,
                          style:
                              TextStyle(color: AppPalette.textMuted(context)),
                        ),
                      ),
                    ConstrainedBox(
                      constraints: BoxConstraints(
                          maxHeight:
                              MediaQuery.of(sheetContext).size.height * 0.4),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _painPoints.length,
                        itemBuilder: (context, index) {
                          final point = _painPoints[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on,
                                color: Color(0xFF6D28D9)),
                            title: Text(point.region),
                            trailing: IconButton(
                              icon: const Icon(Icons.close,
                                  color: Color(0xFFEF4444)),
                              tooltip: t.removeTooltip,
                              onPressed: () {
                                _removePainPointAt(index);
                                sheetSetState(() {});
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const Divider(height: 24),
                    ListTile(
                      leading: const Icon(Icons.add_circle_outline,
                          color: Color(0xFF6D28D9)),
                      title: Text(
                        t.addAnotherLocationLabel,
                        style: const TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF6D28D9)),
                      ),
                      onTap: () {
                        Navigator.of(sheetContext).pop();
                        _showRegionPickerModal();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showRegionPickerModal() {
    final t = AppLocalizations.of(context)!;
    final regions = [
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

    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.surface(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
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
                  itemCount: regions.length,
                  itemBuilder: (context, index) {
                    final item = regions[index];
                    final alreadyAdded =
                        _painPoints.any((p) => p.region == item);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        alreadyAdded
                            ? Icons.check_circle
                            : Icons.location_on_outlined,
                        color: alreadyAdded
                            ? const Color(0xFF6D28D9)
                            : AppPalette.textMuted(context),
                      ),
                      title: Text(
                        item,
                        style: TextStyle(
                          fontWeight: alreadyAdded
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: alreadyAdded
                              ? const Color(0xFF6D28D9)
                              : AppPalette.textSecondary(context),
                        ),
                      ),
                      onTap: () {
                        if (!alreadyAdded) {
                          _addRegionManually(item);
                        }
                        Navigator.of(context).pop();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showHelp() {
    final t = AppLocalizations.of(context)!;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.help_outline, color: Color(0xFF6D28D9)),
            const SizedBox(width: 8),
            Text(t.bodyMapHelpTitle),
          ],
        ),
        content: Column(
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
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(t.gotItButton,
                style: const TextStyle(
                    color: Color(0xFF6D28D9), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
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
          patientCode: widget.patientCode,
          modelAsset: widget.modelAsset,
        ),
      ),
    );
  }
}
