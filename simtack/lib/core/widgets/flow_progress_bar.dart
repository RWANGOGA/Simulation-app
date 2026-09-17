import 'package:flutter/material.dart';
import '../theme/app_palette.dart';

/// A slim step indicator for the patient-facing triage flow (Welcome →
/// Patient Info → Body Map → Pain Details → Review → Success), so a
/// patient always has a sense of how far along they are and how much is
/// left — the flow had no such indicator before, which is standard in
/// any well-designed multi-step wizard (checkout flows, onboarding,
/// tax-filing apps all do this).
///
/// Deliberately simple: a row of segments that fill in as `currentStep`
/// advances, not a full step-by-step breadcrumb with labels — the screens
/// themselves already have titles, this just answers "how much more."
class FlowProgressBar extends StatelessWidget {
  /// Total number of steps in the flow.
  final int totalSteps;

  /// 1-indexed current step (1 = first screen).
  final int currentStep;

  const FlowProgressBar({
    super.key,
    required this.totalSteps,
    required this.currentStep,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: [
          for (var i = 1; i <= totalSteps; i++) ...[
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                height: 4,
                decoration: BoxDecoration(
                  color: i <= currentStep
                      ? const Color(0xFF6D28D9)
                      : AppPalette.border(context),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            if (i != totalSteps) const SizedBox(width: 4),
          ],
        ],
      ),
    );
  }
}
