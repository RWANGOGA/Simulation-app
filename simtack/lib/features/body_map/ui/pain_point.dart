/// A single pain location a patient has marked on the body map.
///
/// `region`, `x`, and `y` are fixed once the patient taps the model.
/// `painType` / `severity` / `direction` / `depth` are filled in on the
/// Pain Details screen, one location at a time, and default to sensible
/// starting values so the UI never shows an empty field.
class PainPoint {
  final String region;
  final double x; // 0..1 fraction of the model canvas
  final double y; // 0..1 fraction of the model canvas

  // Which image these x/y fractions were measured against: null for the
  // whole-body view, or a zoom-kit name (e.g. "hand") for a close-up. The
  // same 0..1 point means a completely different screen position on a
  // different image, so a marker must only ever be drawn on the view it
  // was tapped on — mixing them up used to show, e.g., a stale whole-body
  // "Left Arm / Shoulder" marker floating off to one side of the hand
  // close-up, at that region's whole-body fraction, wherever that happened
  // to fall on the hand image instead.
  final String? viewKey;

  String painType;
  int severity;
  String direction;
  String depth;
  String? symptomDescription;
  List<String> tags;
  Map<String, String> questionAnswers;

  PainPoint({
    required this.region,
    required this.x,
    required this.y,
    this.viewKey,
    this.painType = 'Sharp',
    this.severity = 5,
    this.direction = 'Towards Back',
    this.depth = 'Moderate',
    this.symptomDescription,
    List<String>? tags,
    Map<String, String>? questionAnswers,
  })  : tags = tags ?? [],
        questionAnswers = questionAnswers ?? {};

  /// Two taps are treated as "the same spot" (and thus a toggle-off) if
  /// they land within this fraction of each other on the model canvas.
  static const double sameSpotThreshold = 0.06;

  bool isNearby(double otherX, double otherY) {
    final dx = x - otherX;
    final dy = y - otherY;
    return (dx * dx + dy * dy) < (sameSpotThreshold * sameSpotThreshold);
  }

  // Added so PainPoint can round-trip through offline draft storage
  // (TriageDraft now holds a List<PainPoint>).
  Map<String, dynamic> toJson() => {
        'region': region,
        'x': x,
        'y': y,
        'viewKey': viewKey,
        'painType': painType,
        'severity': severity,
        'direction': direction,
        'depth': depth,
        'symptomDescription': symptomDescription,
        'tags': tags,
        'questionAnswers': questionAnswers,
      };

  factory PainPoint.fromJson(Map<String, dynamic> json) => PainPoint(
        region: json['region'] as String,
        x: (json['x'] as num).toDouble(),
        y: (json['y'] as num).toDouble(),
        viewKey: json['viewKey'] as String?,
        painType: json['painType'] as String,
        severity: json['severity'] as int,
        direction: json['direction'] as String,
        depth: json['depth'] as String,
        symptomDescription: json['symptomDescription'] as String?,
        tags: (json['tags'] as List<dynamic>?)?.map((e) => e as String).toList() ?? [],
        questionAnswers: (json['questionAnswers'] as Map<String, dynamic>?)
                ?.map((k, v) => MapEntry(k, v as String)) ??
            {},
      );
}