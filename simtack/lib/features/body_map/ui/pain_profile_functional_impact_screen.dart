import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_palette.dart';
import '../../../core/theme/app_page_route.dart';
import '../../review/ui/review_screen.dart';
import 'pain_point.dart';

class PainProfileFunctionalImpactScreen extends StatefulWidget {
  final List<PainPoint> painPoints;
  final int patientId;

  const PainProfileFunctionalImpactScreen({
    super.key,
    required this.painPoints,
    required this.patientId,
  });

  @override
  State<PainProfileFunctionalImpactScreen> createState() => _PainProfileFunctionalImpactScreenState();
}

class _PainProfileFunctionalImpactScreenState extends State<PainProfileFunctionalImpactScreen> {
  // Currently active pain point index if there are multiple, or global selection applied to points
  int _currentPointIndex = 0;

  // Static constant definitions
  static const Color primaryPurple = Color(0xFF6C25FF);
  static const Color primaryPurpleTint = Color(0xFFF3E5FF);
  static const Color normalBorderColor = Color(0xFFDEE2E6);
  static const Color alertRed = Color(0xFFDC3545);
  static const Color alertRedTint = Color(0xFFFDE8E8);

  final List<Map<String, String>> _expansionOptions = [
    {
      'id': 'Stays Small',
      'title': 'STAYS SMALL',
      'subtitle': '(Pinpoint Spot)',
      'icon': '( • )',
    },
    {
      'id': 'Spreading',
      'title': 'SPREADING',
      'subtitle': '(Grows Wider)',
      'icon': '( . ⭕ . ) --->',
    },
    {
      'id': 'Multiplying',
      'title': 'MULTIPLYING',
      'subtitle': '(New Red Spots)',
      'icon': '• ⚫ •',
    },
  ];

  final List<Map<String, String>> _triggerOptions = [
    {'id': 'Walking / Moving', 'label': 'Walking / Moving', 'emoji': '🚶‍♂️'},
    {'id': 'Deep Coughing', 'label': 'Deep Coughing', 'emoji': '😮‍💨'},
    {'id': 'Sitting Down', 'label': 'Sitting Down', 'emoji': '🪑'},
    {'id': 'Pressing the Spot', 'label': 'Pressing the Spot', 'emoji': '👉'},
  ];

  final List<Map<String, String>> _relieverOptions = [
    {'id': 'Resting Flat', 'label': 'Resting Flat', 'emoji': '🛌'},
    {'id': 'Ice / Cold Compact', 'label': 'Ice / Cold Compact', 'emoji': '🧊'},
    {'id': 'Heating Pad', 'label': 'Heating Pad', 'emoji': '🔥'},
    {'id': 'Taking Medication', 'label': 'Taking Medication', 'emoji': '💊'},
  ];

  final List<Map<String, String>> _limitationOptions = [
    {'id': 'Cannot Sleep', 'label': 'CANNOT SLEEP', 'emoji': '🛌'},
    {'id': 'Cannot Walk', 'label': 'CANNOT WALK', 'emoji': '🚶‍♂️'},
    {'id': 'Cannot Shower', 'label': 'CANNOT SHOWER', 'emoji': '🚿'},
    {'id': 'Cannot Eat', 'label': 'CANNOT EAT', 'emoji': '🥣'},
    {'id': 'Cannot Dress', 'label': 'CANNOT DRESS', 'emoji': '👕'},
    {'id': 'Cannot Concentrate', 'label': 'CANNOT CONCENTRATE', 'emoji': '🧠'},
  ];

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
            color: Color(0xFF1E293B),
            fontWeight: FontWeight.bold,
            fontSize: 15,
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
      body: Column(
        children: [
          // Step Progress Bar
          Container(
            width: double.infinity,
            color: AppPalette.surface(context),
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Row(
              children: [
                const Text(
                  'Step Progress: ',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF64748B),
                  ),
                ),
                Expanded(
                  child: Row(
                    children: List.generate(6, (index) {
                      final isCompletedOrCurrent = index <= 4;
                      return Expanded(
                        child: Container(
                          height: 8,
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          decoration: BoxDecoration(
                            color: isCompletedOrCurrent
                                ? primaryPurple
                                : normalBorderColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // Location Selector Tab Bar if multiple pain points marked
          if (widget.painPoints.length > 1)
            Container(
              height: 48,
              color: AppPalette.surface(context),
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                itemCount: widget.painPoints.length,
                itemBuilder: (context, i) {
                  final isSelected = i == _currentPointIndex;
                  return GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      setState(() => _currentPointIndex = i);
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSelected ? primaryPurple : AppPalette.subtleFill(context),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Text(
                        'Spot ${i + 1}: ${widget.painPoints[i].region}',
                        style: TextStyle(
                          color: isSelected ? Colors.white : AppPalette.textPrimary(context),
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // SECTION A: PAIN EXPANSION BEHAVIOR
                  _buildSectionHeader(
                    'SECTION A: PAIN EXPANSION BEHAVIOR',
                    'Does your pain stay in one tiny spot, or is it growing larger?',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: _expansionOptions.map((opt) {
                      final isSelected = _currentPoint.expansionBehavior == opt['id'];
                      return Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.selectionClick();
                              setState(() => _currentPoint.expansionBehavior = opt['id']!);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              constraints: const BoxConstraints(minHeight: 110, minWidth: 85),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: isSelected ? primaryPurpleTint : AppPalette.surface(context),
                                border: Border.all(
                                  color: isSelected ? primaryPurple : normalBorderColor,
                                  width: isSelected ? 2 : 1,
                                ),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: isSelected
                                    ? [
                                        BoxShadow(
                                          color: primaryPurple.withOpacity(0.15),
                                          blurRadius: 8,
                                          offset: const Offset(0, 3),
                                        ),
                                      ]
                                    : [],
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    opt['icon']!,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? primaryPurple : const Color(0xFF475569),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    opt['title']!,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: isSelected ? primaryPurple : const Color(0xFF1E293B),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    opt['subtitle']!,
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: isSelected
                                          ? primaryPurple.withOpacity(0.8)
                                          : const Color(0xFF64748B),
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),

                  // SECTION B: ACTIONS & TRIGGERS
                  _buildSectionHeader(
                    'SECTION B: ACTIONS & TRIGGERS',
                    'What changes your pain? Tap to select.',
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Column 1: MAKES IT WORSE (Triggers)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                '👎 MAKES IT WORSE (Triggers)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: alertRed,
                                ),
                              ),
                            ),
                            ..._triggerOptions.map((trig) {
                              final isSelected = _currentPoint.triggers.contains(trig['id']);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GestureDetector(
                                  onTap: () => _toggleTrigger(trig['id']!),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    constraints: const BoxConstraints(minHeight: 52, minWidth: 85),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isSelected ? alertRedTint : AppPalette.surface(context),
                                      border: Border.all(
                                        color: isSelected ? alertRed : normalBorderColor,
                                        width: isSelected ? 2 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(trig['emoji']!, style: const TextStyle(fontSize: 16)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            trig['label']!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                              color: isSelected ? alertRed : const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),

                      // Column 2: MAKES IT BETTER (Relievers)
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                '👍 MAKES IT BETTER (Relievers)',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: primaryPurple,
                                ),
                              ),
                            ),
                            ..._relieverOptions.map((rel) {
                              final isSelected = _currentPoint.relievers.contains(rel['id']);
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: GestureDetector(
                                  onTap: () => _toggleReliever(rel['id']!),
                                  child: AnimatedContainer(
                                    duration: const Duration(milliseconds: 150),
                                    constraints: const BoxConstraints(minHeight: 52, minWidth: 85),
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
                                    decoration: BoxDecoration(
                                      color: isSelected ? primaryPurple : AppPalette.surface(context),
                                      border: Border.all(
                                        color: isSelected ? primaryPurple : normalBorderColor,
                                        width: isSelected ? 2 : 1,
                                      ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Row(
                                      children: [
                                        Text(rel['emoji']!, style: const TextStyle(fontSize: 16)),
                                        const SizedBox(width: 6),
                                        Expanded(
                                          child: Text(
                                            rel['label']!,
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                                              color: isSelected ? Colors.white : const Color(0xFF1E293B),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // SECTION C: DAILY LIFE LIMITATIONS
                  _buildSectionHeader(
                    'SECTION C: DAILY LIFE LIMITATIONS',
                    'What is this pain completely preventing you from doing right now?',
                  ),
                  const SizedBox(height: 12),
                  GridView.builder(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: 2,
                      mainAxisExtent: 90,
                      crossAxisSpacing: 10,
                      mainAxisSpacing: 10,
                    ),
                    itemCount: _limitationOptions.length,
                    itemBuilder: (context, idx) {
                      final item = _limitationOptions[idx];
                      final isSelected = _currentPoint.dailyLimitations.contains(item['id']);
                      return GestureDetector(
                        onTap: () => _toggleLimitation(item['id']!),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 150),
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: isSelected ? alertRedTint : AppPalette.surface(context),
                            border: Border.all(
                              color: isSelected ? alertRed : normalBorderColor,
                              width: isSelected ? 2 : 1,
                            ),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  if (isSelected)
                                    const Padding(
                                      padding: EdgeInsets.only(right: 4),
                                      child: Text('🚫', style: TextStyle(fontSize: 14)),
                                    ),
                                  Text(item['emoji']!, style: const TextStyle(fontSize: 20)),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                item['label']!,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? alertRed : const Color(0xFF1E293B),
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Touch Target Info Card
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: primaryPurpleTint.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: primaryPurple.withOpacity(0.2)),
                    ),
                    child: const Row(
                      children: [
                        Text('💡 ', style: TextStyle(fontSize: 16)),
                        Expanded(
                          child: Text(
                            'Touch Target Optimization: Every action bar and card uses a minimum size of 85dp x 85dp to ensure effortless touch feedback',
                            style: TextStyle(
                              fontSize: 11,
                              color: Color(0xFF4C1D95),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Action Button
          Container(
            padding: const EdgeInsets.all(16),
            color: AppPalette.surface(context),
            child: SafeArea(
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
                  child: const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        'PROCEED TO REVIEW & SUBMIT',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                          letterSpacing: 0.5,
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

  Widget _buildSectionHeader(String title, String subtitle) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: primaryPurple,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 2),
        Container(height: 2, width: double.infinity, color: primaryPurple.withOpacity(0.2)),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: TextStyle(
            fontSize: 13,
            color: AppPalette.textPrimary(context),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
