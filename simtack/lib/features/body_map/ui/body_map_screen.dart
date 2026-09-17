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

  // Holds the most recent detected tap until the user confirms or changes
  // the region in the confirmation bottom sheet. partName is the precise
  // BodyParts3D structure that was actually tapped (e.g. "Distal phalanx of
  // left index finger"), shown to the patient alongside the coarser region
  // — see Anatomy3DTapView / region-map.js for how it's resolved.
  ({String region, double x, double y, String? partName})? _pendingTap;

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
    super.dispose();
  }

  /// Called by [Anatomy3DTapView], which already resolves a tap all the way
  /// down to one of the backend's 14 fixed KB region strings itself (see
  /// assets/anatomy3d/region-map.js) — no further mapping needed here,
  /// unlike the old 2D system this replaced. [partName] is the precise
  /// structure tapped, shown to the patient alongside the region. Shows the
  /// result immediately, no confirmation delay — matching the direct
  /// tap-and-see behavior the 2D system also used.
  void _handleBodyPartReceived(
      String region, double x, double y, String? partName) {
    if (!kReleaseMode) {
      debugPrint(
          'BodyMap: received tap -> region=$region partName=$partName x=$x y=$y');
    }
    setState(() {
      _pendingTap = (region: region, x: x, y: y, partName: partName);
    });
    _showRegionConfirmationSheet();
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
                        color: AppPalette.subtleFill(context),
                        child: Stack(
                          children: [
                            Positioned.fill(
                              child: Anatomy3DTapView(
                                gender: widget.gender,
                                onRegionTapped: _handleBodyPartReceived,
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
          Expanded(
            flex: 2,
            child: Container(
              decoration: BoxDecoration(
                color: AppPalette.surface(context),
                border: Border(
                  top: BorderSide(color: AppPalette.border(context)),
                ),
              ),
              child: _painPoints.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          t.noLocationsMarkedHint,
                          textAlign: TextAlign.center,
                          style:
                              TextStyle(color: AppPalette.textMuted(context)),
                        ),
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                      itemCount: _painPoints.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 4),
                      itemBuilder: (context, i) {
                        final point = _painPoints[i];
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Row(
                              children: [
                                Container(
                                  width: 22,
                                  height: 22,
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
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    point.region,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: AppPalette.textPrimary(context),
                                    ),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  color: AppPalette.textMuted(context),
                                  tooltip: t.removeTooltip,
                                  onPressed: () => _removePainPointAt(i),
                                ),
                              ],
                            ),
                            AnatomyInsightCard(
                              region: point.region,
                              future: _anatomyFutures[point.region],
                              initialAnswers: _questionAnswers[point.region],
                              onAnswersChanged: (answers) {
                                setState(() {
                                  _questionAnswers[point.region] = answers;
                                });
                              },
                            ),
                          ],
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

  /// Shows every currently-marked location with a remove button, plus an
  /// interactive symptom description field & quick quality tags so patients
  /// can describe their symptoms right after tapping a body part.
  void _showRegionConfirmationSheet() {
    if (_pendingTap == null) return;
    final detected = _pendingTap!.region;
    final detectedPartName = _pendingTap!.partName;
    final regions = [
      'Headache / Cranial',
      'Neck',
      'Chest / Heart',
      'Abdomen (Upper)',
      'Abdomen (Lower Right)',
      'Abdomen (Lower Left)',
      'Hips / Groin',
      'Thighs',
      'Back Pain (Upper)',
      'Back Pain (Lower)',
      'Right Arm / Shoulder',
      'Left Arm / Shoulder',
      'Right Leg / Knee',
      'Left Leg / Knee',
    ];

    final availableTags = [
      'Sharp',
      'Dull',
      'Burning',
      'Throbbing',
      'Pressure',
      'Constant',
      'Intermittent'
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: AppPalette.surface(context),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        String selectedRegion = detected;
        final symptomController = TextEditingController();
        final Set<String> selectedTags = {};

        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
              ),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        child: Row(
                          children: [
                            const Icon(Icons.pin_drop_rounded,
                                color: Color(0xFF6D28D9), size: 24),
                            const SizedBox(width: 8),
                            Text(
                              'Confirm & Describe Pain',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                                color: AppPalette.textPrimary(context),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          detectedPartName != null
                              ? 'Detected: $detectedPartName ($detected)'
                              : 'Detected Region: $detected',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppPalette.textMuted(context),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                            maxHeight:
                                MediaQuery.of(sheetContext).size.height * 0.25),
                        child: ListView.builder(
                          shrinkWrap: true,
                          itemCount: regions.length,
                          itemBuilder: (context, index) {
                            final item = regions[index];
                            final isSelected = selectedRegion == item;
                            return ListTile(
                              dense: true,
                              leading: Icon(
                                isSelected
                                    ? Icons.check_circle
                                    : Icons.location_on_outlined,
                                color: isSelected
                                    ? const Color(0xFF6D28D9)
                                    : AppPalette.textMuted(context),
                              ),
                              title: Text(
                                item,
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? const Color(0xFF6D28D9)
                                      : AppPalette.textSecondary(context),
                                ),
                              ),
                              onTap: () {
                                sheetSetState(() {
                                  selectedRegion = item;
                                });
                              },
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'Describe Your Symptoms (Optional)',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textPrimary(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextField(
                        controller: symptomController,
                        maxLines: 2,
                        decoration: InputDecoration(
                          hintText:
                              'e.g. Sharp pain when taking a deep breath, throbbing behind eyes...',
                          hintStyle: TextStyle(
                              color: AppPalette.textMuted(context),
                              fontSize: 13),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide:
                                BorderSide(color: AppPalette.border(context)),
                          ),
                          contentPadding: const EdgeInsets.all(12),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Symptom Tags',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppPalette.textSecondary(context),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: availableTags.map((tag) {
                          final isSelected = selectedTags.contains(tag);
                          return FilterChip(
                            label: Text(tag,
                                style: TextStyle(
                                    fontSize: 12,
                                    color: isSelected
                                        ? Colors.white
                                        : AppPalette.textPrimary(context))),
                            selected: isSelected,
                            selectedColor: const Color(0xFF6D28D9),
                            onSelected: (selected) {
                              sheetSetState(() {
                                if (selected) {
                                  selectedTags.add(tag);
                                } else {
                                  selectedTags.remove(tag);
                                }
                              });
                            },
                          );
                        }).toList(),
                      ),
                      const Divider(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: TextButton(
                              onPressed: () {
                                Navigator.of(sheetContext).pop();
                                setState(() => _pendingTap = null);
                              },
                              child: const Text('Cancel',
                                  style: TextStyle(color: Color(0xFF64748B))),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: () {
                                final textSymptom =
                                    symptomController.text.trim();
                                final tagsList = selectedTags.toList();
                                final combinedComplaint = [
                                  if (textSymptom.isNotEmpty) textSymptom,
                                  if (tagsList.isNotEmpty)
                                    'Quality: ${tagsList.join(", ")}',
                                ].join('. ');

                                Navigator.of(sheetContext).pop();
                                final confirmed = _pendingTap!;
                                _pendingTap = null;
                                _addOrRemovePainPoint(
                                  region: selectedRegion,
                                  x: confirmed.x,
                                  y: confirmed.y,
                                  symptomDescription: textSymptom.isNotEmpty
                                      ? textSymptom
                                      : null,
                                  tags: tagsList,
                                );
                                _requestAnatomyInsight(selectedRegion,
                                    complaint: combinedComplaint);
                              },
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF6D28D9),
                                foregroundColor: Colors.white,
                              ),
                              child: const Text('Confirm & Map'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
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
