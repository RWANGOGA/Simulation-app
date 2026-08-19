import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import '../../vitals/ui/vitals_capture_screen.dart'; // <-- ADDED: Import for the next screen

class PainDetailsScreen extends StatefulWidget {
  final String region;

  const PainDetailsScreen({super.key, required this.region});

  @override
  State<PainDetailsScreen> createState() => _PainDetailsScreenState();
}

class _PainDetailsScreenState extends State<PainDetailsScreen> {
  late String _selectedRegion;
  String _painType = 'Sharp';
  int _severity = 7;
  String _swipeDirection = 'Towards Back';
  String _pinchDepth = 'Deep';

  final List<String> _painTypes = ['Sharp', 'Dull', 'Burning', 'Cramping'];
  final List<String> _directions = ['Towards Back', 'Towards Front', 'Radiating Down', 'Radiating Up'];
  final List<String> _depths = ['Superficial', 'Moderate', 'Deep'];

  @override
  void initState() {
    super.initState();
    _selectedRegion = widget.region;
  }

  // <-- REPLACED: Old _submitReport with this smooth navigation function
  void _continueToVitals() {
    HapticFeedback.mediumImpact();
    
    // Navigate to the Vitals Screen, passing all the collected clinical data
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => VitalsCaptureScreen(
          region: _selectedRegion,
          painType: _painType,
          severity: _severity,
          direction: _swipeDirection,
          depth: _pinchDepth,
        ),
      ),
    );
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
          '3. Pain Details',
          style: TextStyle(
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            fontSize: 18,
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
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selected Region Banner with Edit Button
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.03),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6D28D9).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.location_on, color: Color(0xFF6D28D9), size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pain Location',
                                style: TextStyle(fontSize: 12, color: Color(0xFF64748B), fontWeight: FontWeight.w500),
                              ),
                              Text(
                                _selectedRegion,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined, color: Color(0xFF6D28D9)),
                          onPressed: () => Navigator.of(context).pop(),
                          tooltip: 'Change location',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3D Visual Model with Gesture Callout Overlays (Swipe / Pinch)
                  Container(
                    height: 260,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Stack(
                      children: [
                        // Background 3D Body Model
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(20),
                            child: const ModelViewer(
                              src: kIsWeb ? 'models/human_body.glb' : 'assets/models/human_body.glb',
                              alt: '3D pain vector model',
                              ar: false,
                              autoRotate: false,
                              cameraControls: true,
                              backgroundColor: Color(0xFFF8FAFC),
                            ),
                          ),
                        ),

                        // Swipe Gesture Visual Badge (Top Left)
                        Positioned(
                          top: 14,
                          left: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.3)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.swipe_outlined, size: 16, color: Color(0xFF6D28D9)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Swipe = Direction',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF6D28D9),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                DropdownButton<String>(
                                  value: _swipeDirection,
                                  isDense: true,
                                  underline: const SizedBox(),
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6D28D9), size: 18),
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _swipeDirection = val);
                                  },
                                  items: _directions.map((d) {
                                    return DropdownMenuItem(value: d, child: Text(d));
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),

                        // Pinch Gesture Visual Badge (Bottom Right)
                        Positioned(
                          bottom: 14,
                          right: 14,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.95),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFF6D28D9).withOpacity(0.3)),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.06),
                                  blurRadius: 6,
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.pinch_outlined, size: 16, color: Color(0xFF6D28D9)),
                                    SizedBox(width: 4),
                                    Text(
                                      'Pinch = Depth',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                        color: Color(0xFF6D28D9),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                DropdownButton<String>(
                                  value: _pinchDepth,
                                  isDense: true,
                                  underline: const SizedBox(),
                                  icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6D28D9), size: 18),
                                  style: const TextStyle(fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                                  onChanged: (val) {
                                    if (val != null) setState(() => _pinchDepth = val);
                                  },
                                  items: _depths.map((dp) {
                                    return DropdownMenuItem(value: dp, child: Text(dp));
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  // Pain Type Chips
                  const Text(
                    'Pain Type',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E293B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: _painTypes.map((type) {
                      final isSelected = _painType == type;
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 3),
                          child: ChoiceChip(
                            label: SizedBox(
                              width: double.infinity,
                              child: Text(
                                type,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: isSelected ? Colors.white : const Color(0xFF475569),
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                HapticFeedback.selectionClick();
                                setState(() => _painType = type);
                              }
                            },
                            selectedColor: const Color(0xFF6D28D9),
                            backgroundColor: Colors.white,
                            side: BorderSide(
                              color: isSelected ? const Color(0xFF6D28D9) : const Color(0xFFCBD5E1),
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 10),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 28),

                  // Pain Intensity Slider
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Pain Intensity',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: const Color(0xFF6D28D9),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFF6D28D9).withOpacity(0.25),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Text(
                          '$_severity / 10',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 15,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: SliderTheme(
                      data: SliderThemeData(
                        activeTrackColor: const Color(0xFF6D28D9),
                        inactiveTrackColor: const Color(0xFFE2E8F0),
                        thumbColor: const Color(0xFF6D28D9),
                        overlayColor: const Color(0xFF6D28D9).withOpacity(0.15),
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
                        trackHeight: 6,
                      ),
                      child: Slider(
                        value: _severity.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        onChanged: (value) {
                          HapticFeedback.selectionClick();
                          setState(() => _severity = value.round());
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Submit Action Button
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  // <-- FIXED: Now calls _continueToVitals instead of the old submit function
                  onPressed: _continueToVitals,
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
                        'Submit & Continue to Vitals',
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

  void _showHelp() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.help_outline, color: Color(0xFF6D28D9)),
            SizedBox(width: 8),
            Text('Pain Details Guide'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• Swipe gesture specifies direction of pain (e.g. Towards Back).'),
            SizedBox(height: 8),
            Text('• Pinch gesture specifies depth (Deep, Moderate, Superficial).'),
            SizedBox(height: 8),
            Text('• Tap pain type chips (Sharp, Dull, Burning, Cramping).'),
            SizedBox(height: 8),
            Text('• Slide to set pain intensity scale from 1 to 10.'),
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
}