import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import '../../vitals/ui/vitals_capture_screen.dart'; // <-- Import for the next screen
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/app_card.dart';

class PainDetailsScreen extends StatefulWidget {
  final String region;
  final int patientId;
  final String modelAsset;
  // Exact tap position (0..1 fractions of the model canvas) carried over
  // from the Body Map screen, so the pain marker shows in the same spot
  // instead of resetting to center. Null falls back to center.
  final double? markerX;
  final double? markerY;

  const PainDetailsScreen({
    super.key,
    required this.region,
    required this.patientId,
    required this.modelAsset,
    this.markerX,
    this.markerY,
  });

  @override
  State<PainDetailsScreen> createState() => _PainDetailsScreenState();
}

class _PainDetailsScreenState extends State<PainDetailsScreen> with SingleTickerProviderStateMixin {
  late String _selectedRegion;
  String _painType = 'Sharp';
  int _severity = 7;
  String _swipeDirection = 'Towards Back';
  String _pinchDepth = 'Deep';
  late AnimationController _pulseController;

  final List<String> _painTypes = ['Sharp', 'Dull', 'Burning', 'Cramping'];
  final List<String> _directions = ['Towards Back', 'Towards Front', 'Radiating Down', 'Radiating Up'];
  final List<String> _depths = ['Superficial', 'Moderate', 'Deep'];

  @override
  void initState() {
    super.initState();
    _selectedRegion = widget.region;
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

  void _continueToVitals() {
    HapticFeedback.mediumImpact();

    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => VitalsCaptureScreen(
          region: _selectedRegion,
          painType: _painType,
          severity: _severity,
          direction: _swipeDirection,
          depth: _pinchDepth,
          patientId: widget.patientId,
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
                  AppCard(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF6D28D9).withValues(alpha: 0.1),
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
                        // Wrapped in PointerInterceptor too — it sits directly
                        // above the model viewer's overall stacking context on
                        // web and was at risk of the same tap-swallowing issue
                        // as the dropdowns below.
                        PointerInterceptor(
                          child: IconButton(
                            icon: const Icon(Icons.edit_outlined, color: Color(0xFF6D28D9)),
                            onPressed: () => Navigator.of(context).pop(),
                            tooltip: 'Change location',
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),

                  // 3D Visual Model with Direction / Depth selectors
                  Container(
                    height: 260,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          return Stack(
                            children: [
                              // Background 3D Body Model
                              // NOTE: camera-controls is enabled here, so the model already
                              // owns drag (rotate) and pinch (zoom) gestures. Direction/Depth
                              // are deliberately plain dropdowns rather than gestures on the
                              // model itself, to avoid fighting the model's own controls.
                              Positioned.fill(
                                child: ModelViewer(
                                  src: widget.modelAsset,
                                  alt: '3D pain vector model',
                                  ar: false,
                                  autoRotate: false,
                                  cameraControls: true,
                                  backgroundColor: const Color(0xFFF8FAFC),
                                ),
                              ),

                              // Pain location marker — same pulsing dot from the
                              // Body Map screen, carried over to the exact spot
                              // the user tapped (falls back to center if this
                              // screen was reached without coordinates).
                              Positioned(
                                left: (widget.markerX ?? 0.5) * constraints.maxWidth - 22,
                                top: (widget.markerY ?? 0.5) * constraints.maxHeight - 22,
                                child: IgnorePointer(
                                  child: AnimatedBuilder(
                                    animation: _pulseController,
                                    builder: (context, child) {
                                      return Container(
                                        width: 32 + (12 * _pulseController.value),
                                        height: 32 + (12 * _pulseController.value),
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: const Color(0xFFEF4444)
                                              .withValues(alpha: 0.35 * (1 - _pulseController.value)),
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

                              // Direction Selector (Top Left)
                              // Wrapped in PointerInterceptor: on Flutter Web,
                              // model-viewer is a platform view that captures
                              // pointer events for its own drag-to-rotate
                              // gesture, which can swallow taps meant for
                              // Flutter widgets sitting visually on top of it.
                              // PointerInterceptor claims this region back so
                              // the dropdown actually opens.
                              Positioned(
                                top: 14,
                                left: 14,
                                child: PointerInterceptor(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF6D28D9).withValues(alpha: 0.3)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
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
                                            Icon(Icons.north_east_outlined, size: 16, color: Color(0xFF6D28D9)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Direction',
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
                                          style: const TextStyle(
                                              fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                                          onChanged: (val) {
                                            if (val != null) {
                                              HapticFeedback.selectionClick();
                                              setState(() => _swipeDirection = val);
                                            }
                                          },
                                          items: _directions.map((d) {
                                            return DropdownMenuItem(value: d, child: Text(d));
                                          }).toList(),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),

                              // Depth Selector (Bottom Right)
                              Positioned(
                                bottom: 14,
                                right: 14,
                                child: PointerInterceptor(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.white.withValues(alpha: 0.95),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: const Color(0xFF6D28D9).withValues(alpha: 0.3)),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withValues(alpha: 0.06),
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
                                            Icon(Icons.layers_outlined, size: 16, color: Color(0xFF6D28D9)),
                                            SizedBox(width: 4),
                                            Text(
                                              'Depth',
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
                                          style: const TextStyle(
                                              fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                                          onChanged: (val) {
                                            if (val != null) {
                                              HapticFeedback.selectionClick();
                                              setState(() => _pinchDepth = val);
                                            }
                                          },
                                          items: _depths.map((dp) {
                                            return DropdownMenuItem(value: dp, child: Text(dp));
                                          }).toList(),
                                        ),
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
                              color: const Color(0xFF6D28D9).withValues(alpha: 0.25),
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
                        overlayColor: const Color(0xFF6D28D9).withValues(alpha: 0.15),
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
                  onPressed: _continueToVitals,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF6D28D9),
                    elevation: 3,
                    shadowColor: const Color(0xFF6D28D9).withValues(alpha: 0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'Next: Measure Vitals',
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
            Text('• Use the Direction dropdown to specify where the pain moves (e.g. Towards Back).'),
            SizedBox(height: 8),
            Text('• Use the Depth dropdown to specify how deep the pain feels (Deep, Moderate, Superficial).'),
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
