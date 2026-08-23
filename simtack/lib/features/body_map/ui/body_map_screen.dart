// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'pain_details_screen.dart';
import 'pain_point.dart';
import '../../../core/theme/app_page_route.dart';

class BodyMapScreen extends StatefulWidget {
  final int patientId;
  final String gender;
  final double weightKg;
  final double heightCm;

  const BodyMapScreen({
    super.key,
    required this.patientId,
    required this.gender,
    required this.weightKg,
    required this.heightCm,
  });

  /// Picks the body model variant matching the patient's gender.
  /// BMI (weightKg/heightCm) isn't used yet — there's only one build per
  /// gender today. Once BMI-varied versions of these models exist, branch
  /// on bmi here the same way the old slim/average/heavy logic did.
  String get modelAsset {
    final file = gender == 'Male' ? 'human_body_male.glb' : 'human_body_female.glb';
    return kIsWeb ? 'models/$file' : 'assets/models/$file';
  }

  @override
  State<BodyMapScreen> createState() => _BodyMapScreenState();
}

class _BodyMapScreenState extends State<BodyMapScreen> with SingleTickerProviderStateMixin {
  // Fixed id so we can grab the underlying <model-viewer> element directly
  // and talk to it via JS, instead of relying only on Flutter's prop diffing.
  static const String _modelViewerId = 'body-map-model-viewer';

  // Every pain location the patient has tapped so far. Tapping the same
  // spot again (within PainPoint.sameSpotThreshold) removes it — this is
  // the multi-select toggle behavior.
  final List<PainPoint> _painPoints = [];

  String _viewAngle = 'front';
  double _zoomLevel = 1.0;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    if (kIsWeb) {
      html.window.addEventListener('atomybridge-bodypart', _onBodyPartEvent);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    if (kIsWeb) {
      html.window.removeEventListener('atomybridge-bodypart', _onBodyPartEvent);
    }
    super.dispose();
  }

  // The bridge may send a plain region-name String, or a JS object shaped
  // like { part, x, y } where x/y are 0..1 fractions of the model canvas.
  //
  // IMPORTANT: we read `detail` straight off the raw JS event via js_util
  // instead of casting to html.CustomEvent first. That cast is only safe
  // for primitive-shaped details; for an object detail like { part, x, y }
  // it can throw, and since this runs inside an event-listener callback
  // the exception gets swallowed silently — setState never runs and the
  // badge just sits on its initial value forever. js_util sidesteps that.
  void _onBodyPartEvent(html.Event event) {
    final dynamic rawDetail = js_util.getProperty(event, 'detail');
    if (rawDetail == null) return;

    String? part;
    double? x;
    double? y;

    if (rawDetail is String) {
      part = rawDetail;
    } else {
      final dynamic converted = js_util.dartify(rawDetail);
      if (converted is Map) {
        final p = converted['part'];
        final rx = converted['x'];
        final ry = converted['y'];
        if (p is String) part = p;
        if (rx is num) x = rx.toDouble();
        if (ry is num) y = ry.toDouble();
      }
    }

    if (part == null || part.isEmpty) return;

    if (!kReleaseMode) {
      // Temporary breadcrumb: confirms the Dart side actually received the
      // tap. Safe to remove once you've verified markers update correctly.
      debugPrint('BodyMap: received tap -> part=$part x=$x y=$y');
    }

    _addOrRemovePainPoint(region: part, x: x, y: y);
  }

  /// Multi-select toggle: tapping a fresh spot adds a new pain point.
  /// Tapping close to an existing point removes it instead — this is how
  /// a patient "unmarks" a location without a separate delete step.
  void _addOrRemovePainPoint({required String region, double? x, double? y}) {
    final tapX = x ?? 0.5;
    final tapY = y ?? 0.5;

    final existingIndex = _painPoints.indexWhere((p) => p.isNearby(tapX, tapY));

    HapticFeedback.mediumImpact();
    setState(() {
      if (existingIndex != -1) {
        _painPoints.removeAt(existingIndex);
      } else {
        _painPoints.add(PainPoint(region: region, x: tapX, y: tapY));
      }
    });
  }

  void _removePainPointAt(int index) {
    HapticFeedback.lightImpact();
    setState(() => _painPoints.removeAt(index));
  }

  void _changeView(String angle) {
    HapticFeedback.selectionClick();
    setState(() {
      _viewAngle = angle;
    });
    _applyCameraOrbitNow(_getCameraOrbit(angle));
  }

  String _getCameraOrbit([String? angle]) {
    final radius = (105 / _zoomLevel).round();
    // The female source model was exported facing the opposite way from the
    // male one, so every angle needs a 180° correction for that model only.
    final flip = widget.gender == 'Female';
    final int baseDeg;
    switch (angle ?? _viewAngle) {
      case 'back':
        baseDeg = 180;
        break;
      case 'left':
        baseDeg = -90;
        break;
      case 'right':
        baseDeg = 90;
        break;
      case 'front':
      default:
        baseDeg = 0;
    }
    final deg = flip ? baseDeg + 180 : baseDeg;
    return '${deg}deg 75deg $radius%';
  }

  // Bypasses the normal Flutter -> platform-view prop pipeline: sets the
  // camera-orbit attribute straight on the <model-viewer> element and then
  // calls jumpCameraToGoal() so the camera snaps immediately instead of
  // animating in behind the button press.
  void _applyCameraOrbitNow(String orbit) {
    if (!kIsWeb) return;
    final el = html.document.getElementById(_modelViewerId);
    if (el == null) return;
    el.setAttribute('camera-orbit', orbit);
    try {
      js_util.callMethod(el, 'jumpCameraToGoal', []);
    } catch (_) {
      // Older model-viewer builds may not expose this — the attribute
      // change above still applies, just with the default animation.
    }
  }

  /// Manually add a region from the picker list (no tap coordinates yet,
  /// so it drops in at the center of the canvas). Used as a fallback for
  /// regions that are awkward to tap precisely, or for accessibility.
  void _addRegionManually(String region) {
    HapticFeedback.lightImpact();
    setState(() {
      _painPoints.add(PainPoint(region: region, x: 0.5, y: 0.5));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          'Body Map - Select Pain',
          style: TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
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
            child: LayoutBuilder(
              builder: (context, constraints) {
                return Stack(
                  children: [
                    // 3D Model Viewer
                    Positioned.fill(
                      child: ModelViewer(
                        id: _modelViewerId,
                        src: widget.modelAsset,
                        alt: 'OpenHuman 3D body model for pain mapping',
                        ar: false,
                        autoRotate: false,
                        cameraControls: true,
                        cameraOrbit: _getCameraOrbit(),
                        backgroundColor: const Color(0xFFF1F5F9),
                      ),
                    ),

                    // Floating Camera & Controls Toolbar (Left Overlay)
                    Positioned(
                      left: 16,
                      top: 24,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.92),
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.08),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildOverlayTool(
                              icon: Icons.center_focus_strong_outlined,
                              tooltip: 'Reset View',
                              onTap: () {
                                HapticFeedback.lightImpact();
                                setState(() {
                                  _viewAngle = 'front';
                                  _zoomLevel = 1.0;
                                });
                                _applyCameraOrbitNow(_getCameraOrbit('front'));
                              },
                            ),
                            const SizedBox(height: 8),
                            _buildOverlayTool(
                              icon: Icons.sync,
                              tooltip: 'Rotate Model',
                              onTap: () {
                                final angles = ['front', 'right', 'back', 'left'];
                                final currentIndex = angles.indexOf(_viewAngle);
                                _changeView(angles[(currentIndex + 1) % angles.length]);
                              },
                            ),
                            const SizedBox(height: 8),
                            _buildOverlayTool(
                              icon: Icons.add,
                              tooltip: 'Zoom In',
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _zoomLevel = (_zoomLevel + 0.15).clamp(0.7, 2.0));
                                _applyCameraOrbitNow(_getCameraOrbit());
                              },
                            ),
                            const SizedBox(height: 8),
                            _buildOverlayTool(
                              icon: Icons.remove,
                              tooltip: 'Zoom Out',
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() => _zoomLevel = (_zoomLevel - 0.15).clamp(0.7, 2.0));
                                _applyCameraOrbitNow(_getCameraOrbit());
                              },
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Pain Hotspot Pulses — one per marked location, all
                    // shown at once. Previously there was only ever one
                    // marker (overwritten on every tap); now each tap adds
                    // to the list and every pulse in _painPoints renders.
                    for (final point in _painPoints)
                      Positioned(
                        left: point.x * constraints.maxWidth - 22,
                        top: point.y * constraints.maxHeight - 22,
                        child: IgnorePointer(
                          child: AnimatedBuilder(
                            animation: _pulseController,
                            builder: (context, child) {
                              return Container(
                                width: 32 + (12 * _pulseController.value),
                                height: 32 + (12 * _pulseController.value),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: const Color(0xFFEF4444).withOpacity(0.35 * (1 - _pulseController.value)),
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
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
                              const Icon(Icons.location_on, color: Colors.white, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                _painPoints.isEmpty
                                    ? 'Tap a body part'
                                    : '${_painPoints.length} location${_painPoints.length == 1 ? '' : 's'} selected',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_drop_down, color: Colors.white, size: 18),
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

          // Bottom View Angle Selectors
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.04),
                  blurRadius: 8,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildViewButton('Front', 'front'),
                _buildViewButton('Back', 'back'),
                _buildViewButton('Left', 'left'),
                _buildViewButton('Right', 'right'),
              ],
            ),
          ),

          // Navigation CTA Button — disabled until at least one location
          // is marked, since there's nothing to carry into Pain Details
          // otherwise.
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
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
                            ? 'Tap the body to mark pain'
                            : 'Continue to Pain Details (${_painPoints.length})',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, color: Colors.white, size: 20),
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

  Widget _buildOverlayTool({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Tooltip(
          message: tooltip,
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: Icon(
              icon,
              color: const Color(0xFF6D28D9),
              size: 22,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewButton(String label, String angle) {
    final isSelected = _viewAngle == angle;
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          child: ElevatedButton(
            onPressed: () => _changeView(angle),
            style: ElevatedButton.styleFrom(
              backgroundColor: isSelected ? const Color(0xFF6D28D9) : const Color(0xFFF1F5F9),
              foregroundColor: isSelected ? Colors.white : const Color(0xFF475569),
              elevation: isSelected ? 2 : 0,
              side: BorderSide(
                color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFFE2E8F0),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Shows every currently-marked location with a remove button, plus an
  /// "Add another location" entry point into the same preset-region list
  /// the old single-select picker used (now additive instead of
  /// overwriting the selection).
  void _showSelectedLocationsSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
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
                padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Text(
                        'Pain Locations',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_painPoints.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 16),
                        child: Text(
                          'No locations marked yet. Tap anywhere on the body to add one.',
                          style: TextStyle(color: Color(0xFF64748B)),
                        ),
                      ),
                    ConstrainedBox(
                      constraints: BoxConstraints(maxHeight: MediaQuery.of(sheetContext).size.height * 0.4),
                      child: ListView.builder(
                        shrinkWrap: true,
                        itemCount: _painPoints.length,
                        itemBuilder: (context, index) {
                          final point = _painPoints[index];
                          return ListTile(
                            dense: true,
                            leading: const Icon(Icons.location_on, color: Color(0xFF6D28D9)),
                            title: Text(point.region),
                            trailing: IconButton(
                              icon: const Icon(Icons.close, color: Color(0xFFEF4444)),
                              tooltip: 'Remove',
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
                      leading: const Icon(Icons.add_circle_outline, color: Color(0xFF6D28D9)),
                      title: const Text(
                        'Add another location',
                        style: TextStyle(fontWeight: FontWeight.w600, color: Color(0xFF6D28D9)),
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
      backgroundColor: Colors.white,
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
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  'Select Pain Location',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF1E293B),
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
                    final alreadyAdded = _painPoints.any((p) => p.region == item);
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        alreadyAdded ? Icons.check_circle : Icons.location_on_outlined,
                        color: alreadyAdded ? const Color(0xFF6D28D9) : const Color(0xFF94A3B8),
                      ),
                      title: Text(
                        item,
                        style: TextStyle(
                          fontWeight: alreadyAdded ? FontWeight.bold : FontWeight.normal,
                          color: alreadyAdded ? const Color(0xFF6D28D9) : const Color(0xFF334155),
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
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF6D28D9)),
            SizedBox(width: 8),
            Text('How to use Body Map'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• 3D Body (OpenHuman model): Rotate & inspect in 360°.'),
            SizedBox(height: 8),
            Text('• Tap on body parts to mark pain locations — tap as many as you need.'),
            SizedBox(height: 8),
            Text('• Tap the same spot again to remove that marker.'),
            SizedBox(height: 8),
            Text('• Use camera tools on the left overlay to zoom in/out or reset.'),
            SizedBox(height: 8),
            Text('• Toggle Front, Back, Left, or Right views with bottom tabs.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Got it', style: TextStyle(color: Color(0xFF6D28D9), fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _navigateToPainDetails() {
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => PainDetailsScreen(
          painPoints: _painPoints,
          patientId: widget.patientId,
          modelAsset: widget.modelAsset,
        ),
      ),
    );
  }
}