// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'package:flutter/foundation.dart' show kIsWeb, kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'pain_details_screen.dart';
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

  String _selectedRegion = 'Abdomen (Lower Right)';
  String _viewAngle = 'front';
  double _zoomLevel = 1.0;
  late AnimationController _pulseController;

  // Marker position as a fraction of the canvas (0..1). Null = use the
  // default centered marker. Set when a tap on the model gives us real
  // coordinates.
  Offset? _markerFraction;

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
      // tap. Safe to remove once you've verified the badge updates.
      debugPrint('BodyMap: received tap -> part=$part x=$x y=$y');
    }

    HapticFeedback.mediumImpact();
    setState(() {
      _selectedRegion = part!;
      if (x != null && y != null) {
        _markerFraction = Offset(x, y);
      }
    });
  }

  void _changeView(String angle) {
    HapticFeedback.selectionClick();
    setState(() {
      _viewAngle = angle;
      // A button-driven view change is a hard reset of where we're looking,
      // so drop any tap-based marker position back to center.
      _markerFraction = null;
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

  void _selectPresetRegion(String region) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedRegion = region;
      _markerFraction = null;
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
                                  _markerFraction = null;
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

                    // Pain Hotspot Pulse Overlay
                    // Uses _markerFraction (set by a tap on the model) when
                    // available, otherwise falls back to dead-center.
                    Positioned(
                      left: (_markerFraction?.dx ?? 0.5) * constraints.maxWidth - 22,
                      top: (_markerFraction?.dy ?? 0.5) * constraints.maxHeight - 22,
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

                    // Selected Region Badge Header (Top Right Overlay)
                    Positioned(
                      top: 16,
                      right: 16,
                      child: GestureDetector(
                        onTap: _showRegionPickerModal,
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
                                _selectedRegion,
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

          // Navigation CTA Button
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () {
                    HapticFeedback.selectionClick();
                    _navigateToPainDetails();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D28D9),
                    elevation: 3,
                    shadowColor: const Color(0xFF6D28D9).withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Continue to Pain Details',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      SizedBox(width: 8),
                      Icon(Icons.arrow_forward, color: Colors.white, size: 20),
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
                    final isSelected = item == _selectedRegion;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        Icons.location_on_outlined,
                        color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFF94A3B8),
                      ),
                      title: Text(
                        item,
                        style: TextStyle(
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFF334155),
                        ),
                      ),
                      trailing: isSelected
                          ? const Icon(Icons.check_circle, color: Color(0xFF6D28D9))
                          : null,
                      onTap: () {
                        _selectPresetRegion(item);
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
            Text('• Tap on body parts to place or adjust pain hotspot.'),
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
          region: _selectedRegion,
          patientId: widget.patientId,
          modelAsset: widget.modelAsset,
          markerX: _markerFraction?.dx,
          markerY: _markerFraction?.dy,
        ),
      ),
    );
  }
}
