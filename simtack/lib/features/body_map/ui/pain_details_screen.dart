import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:model_viewer_plus/model_viewer_plus.dart';
import 'package:pointer_interceptor/pointer_interceptor.dart';
import 'pain_point.dart';
import '../../vitals/ui/vitals_capture_screen.dart'; // <-- Import for the next screen
import '../../../core/theme/app_page_route.dart';
import '../../../core/theme/app_card.dart';

class PainDetailsScreen extends StatefulWidget {
  final List<PainPoint> painPoints;
  final int patientId;
  final String modelAsset;

  const PainDetailsScreen({
    super.key,
    required this.painPoints,
    required this.patientId,
    required this.modelAsset,
  });

  @override
  State<PainDetailsScreen> createState() => _PainDetailsScreenState();
}

class _PainDetailsScreenState extends State<PainDetailsScreen> with SingleTickerProviderStateMixin {
  // Wizard position: which pain point (from Body Map) we're currently
  // filling in details for. Each point keeps its own painType/severity/
  // direction/depth — e.g. "much" pain on the nose, "low" pain on the
  // knee, captured and stored independently rather than one shared set
  // of fields applied to every location.
  int _currentIndex = 0;
  late AnimationController _pulseController;

  final List<String> _painTypes = ['Sharp', 'Dull', 'Burning', 'Cramping'];
  final List<String> _directions = ['Towards Back', 'Towards Front', 'Radiating Down', 'Radiating Up'];
  final List<String> _depths = ['Superficial', 'Moderate', 'Deep'];

  PainPoint get _currentPoint => widget.painPoints[_currentIndex];
  bool get _isLastPoint => _currentIndex == widget.painPoints.length - 1;

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

  void _goToPreviousPoint() {
    if (_currentIndex == 0) return;
    HapticFeedback.selectionClick();
    setState(() => _currentIndex--);
  }

  void _goToNextPointOrVitals() {
    HapticFeedback.mediumImpact();
    if (!_isLastPoint) {
      setState(() => _currentIndex++);
      return;
    }

    // All locations have their details filled in — hand the whole list
    // forward. Vitals (heart rate / signal quality) are captured once per
    // visit, not per pain location, so this only happens after the last
    // point.
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => VitalsCaptureScreen(
          painPoints: widget.painPoints,
          patientId: widget.patientId,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final point = _currentPoint;

    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.painPoints.length > 1
              ? '3. Pain Details (${_currentIndex + 1} of ${widget.painPoints.length})'
              : '3. Pain Details',
          style: const TextStyle(
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
          // Location progress dots — lets the patient see how many
          // locations still need details and jump back to a previous one.
          if (widget.painPoints.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(widget.painPoints.length, (i) {
                  final isActive = i == _currentIndex;
                  final isDone = i < _currentIndex;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _currentIndex = i);
                    },
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 22 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: isActive
                            ? const Color(0xFF6D28D9)
                            : (isDone ? const Color(0xFF6D28D9).withOpacity(0.4) : const Color(0xFFE2E8F0)),
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              // Keying on the region string resets scroll position when
              // moving between points, rather than freezing the previous
              // point's scroll offset.
              key: ValueKey('pain-point-scroll-$_currentIndex'),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Selected Region Banner
                  AppCard(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                                point.region,
                                style: const TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF1E293B),
                                ),
                              ),
                            ],
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
                          color: Colors.black.withOpacity(0.04),
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

                              // Every marked location shows here (dimmed for
                              // the ones not currently being edited), so the
                              // patient always has visual context for how
                              // many locations they're working through.
                              for (int i = 0; i < widget.painPoints.length; i++)
                                Positioned(
                                  left: widget.painPoints[i].x * constraints.maxWidth - 22,
                                  top: widget.painPoints[i].y * constraints.maxHeight - 22,
                                  child: IgnorePointer(
                                    child: i == _currentIndex
                                        ? AnimatedBuilder(
                                            animation: _pulseController,
                                            builder: (context, child) {
                                              return Container(
                                                width: 32 + (12 * _pulseController.value),
                                                height: 32 + (12 * _pulseController.value),
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  color: const Color(0xFFEF4444)
                                                      .withOpacity(0.35 * (1 - _pulseController.value)),
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
                                          )
                                        : Container(
                                            width: 18,
                                            height: 18,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              color: const Color(0xFFDC2626).withOpacity(0.35),
                                              border: Border.all(
                                                color: const Color(0xFFDC2626).withOpacity(0.5),
                                                width: 1.5,
                                              ),
                                            ),
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
                                          value: point.direction,
                                          isDense: true,
                                          underline: const SizedBox(),
                                          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6D28D9), size: 18),
                                          style: const TextStyle(
                                              fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                                          onChanged: (val) {
                                            if (val != null) {
                                              HapticFeedback.selectionClick();
                                              setState(() => point.direction = val);
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
                                          value: point.depth,
                                          isDense: true,
                                          underline: const SizedBox(),
                                          icon: const Icon(Icons.arrow_drop_down, color: Color(0xFF6D28D9), size: 18),
                                          style: const TextStyle(
                                              fontSize: 12, color: Color(0xFF1E293B), fontWeight: FontWeight.bold),
                                          onChanged: (val) {
                                            if (val != null) {
                                              HapticFeedback.selectionClick();
                                              setState(() => point.depth = val);
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

                  // Pain Type Chips — bound to this point specifically.
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
                      final isSelected = point.painType == type;
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
                                setState(() => point.painType = type);
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

                  // Pain Intensity Slider — this is the "much on the nose,
                  // low on the knee" part: each point has its own severity,
                  // set here independently per location.
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
                          '${point.severity} / 10',
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
                        value: point.severity.toDouble(),
                        min: 1,
                        max: 10,
                        divisions: 9,
                        onChanged: (value) {
                          HapticFeedback.selectionClick();
                          setState(() => point.severity = value.round());
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Bottom navigation: Back / Next (or Next: Measure Vitals on the
          // final point).
          Container(
            padding: const EdgeInsets.all(20),
            color: Colors.white,
            child: SafeArea(
              child: Row(
                children: [
                  if (_currentIndex > 0) ...[
                    SizedBox(
                      height: 54,
                      child: OutlinedButton(
                        onPressed: _goToPreviousPoint,
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Color(0xFF6D28D9)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                        ),
                        child: const Icon(Icons.arrow_back, color: Color(0xFF6D28D9)),
                      ),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton(
                        onPressed: _goToNextPointOrVitals,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF6D28D9),
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
                              _isLastPoint ? 'Next: Measure Vitals' : 'Next Location',
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
                ],
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
            Text('• If you marked more than one location, you\'ll fill in details for each one in turn.'),
            SizedBox(height: 8),
            Text('• Use the Direction dropdown to specify where the pain moves (e.g. Towards Back).'),
            SizedBox(height: 8),
            Text('• Use the Depth dropdown to specify how deep the pain feels (Deep, Moderate, Superficial).'),
            SizedBox(height: 8),
            Text('• Tap pain type chips (Sharp, Dull, Burning, Cramping).'),
            SizedBox(height: 8),
            Text('• Slide to set pain intensity scale from 1 to 10 — each location can be different.'),
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