import 'package:flutter/material.dart';

/// Design-system palette from the practitioner dashboard mock's "Shared UI
/// Component Library" panel — kept separate from the rest of the app,
/// which uses the app-wide purple (#6D28D9) from AppTheme.
class DashboardPalette {
  static const primary = Color(0xFF6C35F5);
  static const secondary = Color(0xFF008FA6);
  static const success = Color(0xFF26A745);
  static const warning = Color(0xFFFFC107);
  static const danger = Color(0xFFDC3545);
  static const neutral = Color(0xFF6C757D);
}

// Approximate on-screen position of each body region on the simplified
// silhouette used in the Body Map screen, as a fraction of the icon's own
// bounding box. Front/back regions collapse to the same point since the
// silhouette is a single generic glyph, not a full 3D model — that's a
// known simplification of the mock's detailed anatomical figure.
const Map<String, Offset> regionPosition = {
  'Headache / Cranial': Offset(0.5, 0.06),
  'Chest / Heart': Offset(0.5, 0.28),
  'Abdomen (Upper)': Offset(0.5, 0.40),
  'Abdomen (Lower Right)': Offset(0.40, 0.50),
  'Abdomen (Lower Left)': Offset(0.60, 0.50),
  'Back Pain (Upper)': Offset(0.5, 0.28),
  'Back Pain (Lower)': Offset(0.5, 0.45),
  'Right Arm / Shoulder': Offset(0.15, 0.26),
  'Left Arm / Shoulder': Offset(0.85, 0.26),
  'Right Leg / Knee': Offset(0.35, 0.80),
  'Left Leg / Knee': Offset(0.65, 0.80),
};

String riskLevel(double? score) {
  if (score == null) return 'UNKNOWN';
  if (score >= 0.7) return 'HIGH';
  if (score >= 0.4) return 'MEDIUM';
  return 'LOW';
}

Color riskColor(String level) {
  switch (level) {
    case 'HIGH':
      return DashboardPalette.danger;
    case 'MEDIUM':
      return DashboardPalette.warning;
    case 'LOW':
      return DashboardPalette.success;
    default:
      return DashboardPalette.neutral;
  }
}

String riskTitleCase(String level) =>
    level == 'UNKNOWN' ? 'Unknown' : '${level[0]}${level.substring(1).toLowerCase()}';

/// A right-arrow "Next: ..." button shared by every step of the practitioner
/// review flow (Patient Overview -> Body Map & Timeline -> SHAP Explanation
/// -> Triage Decision), pinned to the bottom of each screen.
class DashboardNextButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;

  const DashboardNextButton({super.key, required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: DashboardPalette.primary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const SizedBox(width: 8),
            const Icon(Icons.arrow_forward, size: 18),
          ],
        ),
      ),
    );
  }
}
