// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'pain_details_screen.dart';

class BodyMapScreen extends StatefulWidget {
  const BodyMapScreen({super.key});

  @override
  State<BodyMapScreen> createState() => _BodyMapScreenState();
}

class _BodyMapScreenState extends State<BodyMapScreen> with SingleTickerProviderStateMixin {
  String _selectedRegion = 'Abdomen (Lower Right)';
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

  void _onBodyPartEvent(html.Event event) {
    final part = (event as html.CustomEvent).detail as String?;
    if (part == null) return;
    HapticFeedback.mediumImpact();
    setState(() {
      _selectedRegion = part;
    });
  }

  void _changeView(String angle) {
    HapticFeedback.selectionClick();
    setState(() {
      _viewAngle = angle;
    });
  }

  String _getCameraOrbit() {
    switch (_viewAngle) {
      case 'back':
        return '180deg 75deg 105%';
      case 'left':
        return '-90deg 75deg 105%';
      case 'right':
        return '90deg 75deg 105%';
      case 'front':
      default:
        return '0deg 75deg 105%';
    }
  }

  void _selectPresetRegion(String region) {
    HapticFeedback.lightImpact();
    setState(() {
      _selectedRegion = region;
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
            child: Stack(
              children: [
                // 3D Model Viewer
                Positioned.fill(
                  child: ModelViewer(
                    src: kIsWeb ? 'models/human_body.glb' : 'assets/models/human_body.glb',
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
                          },
                        ),
                        const SizedBox(height: 8),
                        _buildOverlayTool(
                          icon: Icons.remove,
                          tooltip: 'Zoom Out',
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setState(() => _zoomLevel = (_zoomLevel - 0.15).clamp(0.7, 2.0));
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Pain Hotspot Pulse Overlay (Centered visual feedback)
                Center(
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
      MaterialPageRoute(
        builder: (_) => PainDetailsScreen(region: _selectedRegion),
      ),
    );
  }
}