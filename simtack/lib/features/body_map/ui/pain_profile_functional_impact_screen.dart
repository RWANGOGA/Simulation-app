import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_page_route.dart';
import '../../review/ui/review_screen.dart';
import 'pain_point.dart';

class PainProfileFunctionalImpactScreen extends StatefulWidget {
  final List<PainPoint> painPoints;
  final int patientId;
  final String? patientCode;

  const PainProfileFunctionalImpactScreen({
    super.key,
    required this.painPoints,
    required this.patientId,
    this.patientCode,
  });

  @override
  State<PainProfileFunctionalImpactScreen> createState() {
    return _PainProfileFunctionalImpactScreenState();
  }
}

class _PainProfileFunctionalImpactScreenState
    extends State<PainProfileFunctionalImpactScreen> {
  int _currentPointIndex = 0;

  static const Color primaryPurple = Color(0xFF6C25FF);

  PainPoint get _currentPoint => widget.painPoints.isNotEmpty
      ? widget.painPoints[_currentPointIndex]
      : PainPoint(region: 'General', x: 0.5, y: 0.5);

  void _toggleTrigger(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_currentPoint.triggers.contains(id)) {
        _currentPoint.triggers.remove(id);
      } else {
        _currentPoint.triggers.add(id);
      }
    });
  }

  void _toggleReliever(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_currentPoint.relievers.contains(id)) {
        _currentPoint.relievers.remove(id);
      } else {
        _currentPoint.relievers.add(id);
      }
    });
  }

  void _toggleLimitation(String id) {
    HapticFeedback.selectionClick();
    setState(() {
      if (_currentPoint.dailyLimitations.contains(id)) {
        _currentPoint.dailyLimitations.remove(id);
      } else {
        _currentPoint.dailyLimitations.add(id);
      }
    });
  }

  void _proceedToReview() {
    HapticFeedback.mediumImpact();
    Navigator.of(context).push(
      AppPageRoute(
        builder: (_) => ReviewScreen(
          painPoints: widget.painPoints,
          patientId: widget.patientId,
          patientCode: widget.patientCode,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppPalette.scaffold(context),
      appBar: AppBar(
        backgroundColor: AppPalette.surface(context),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: primaryPurple),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: const Text(
          '4 & 5. PAIN PROFILE & FUNCTIONAL IMPACT',
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1E293B),
          ),
        ),
        centerTitle: true,
        actions: const [
          Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.shield_outlined, color: primaryPurple),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section A: PAIN EXPANSION BEHAVIOR
            _buildSectionHeader(
              'SECTION A: PAIN EXPANSION BEHAVIOR',
              'Does your pain stay in one tiny spot, or is it growing larger?',
            ),
            const SizedBox(height: 16),
            // Section B: ACTIONS & TRIGGERS
            _buildSectionHeader(
              'SECTION B: ACTIONS & TRIGGERS',
              'What changes your pain? Tap to select.',
            ),
            const SizedBox(height: 16),
            // Section C: DAILY LIFE LIMITATIONS
            _buildSectionHeader(
              'SECTION C: DAILY LIFE LIMITATIONS',
              'What is this pain completely preventing you from doing right now?',
            ),
            const SizedBox(height: 32),
            // Bottom Action Button
            SafeArea(
              child: SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _proceedToReview,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryPurple,
                    elevation: 3,
                    shadowColor: primaryPurple.withOpacity(0.4),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'PROCEED TO REVIEW & SUBMIT',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward, color: Color(0xFF1E293B), size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
        const SizedBox(height: 2),
        Text(subtitle, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      ],
    );
  }
}