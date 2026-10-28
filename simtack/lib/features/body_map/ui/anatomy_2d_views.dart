/// The flat (image + ID map) renderer's four camera angles and the translation
/// from what its ID map can resolve to what the rest of the app expects.
///
/// The ID map distinguishes seven coarse regions. `body_graph.json` — which the
/// risk engine, the anatomy knowledge base and every stored session key on —
/// uses 34 finer ones. Taps arriving from the flat view therefore have to be
/// translated, and the translation is lossy by nature: `left upper limb` cannot
/// tell a wrist from a shoulder. That is why [AnatomyViewMode] exposes the
/// distinction instead of presenting the two renderers as interchangeable.
library;

/// One pre-rendered angle. Front/back/left/right renders and their matching
/// invisible ID maps both exist for every angle, from real BodyParts3D data.
enum Anatomy2DAngle {
  front,
  back,
  left,
  right;

  /// The picture the patient sees.
  String get visibleAsset => 'assets/anatomy/body_visible_$name.png';

  /// The same body with each region painted a flat identifying colour, never
  /// drawn — only sampled at the tap point. Kept as a separate image so the
  /// visible one can look like anatomy rather than a paint-by-numbers chart.
  String get idmapAsset => 'assets/anatomy/body_idmap_$name.png';
}

/// One colour table shared by all four angles: a colour identifies the same
/// limb in every view, so the table is not per-angle.
const String anatomy2DColorsAsset = 'assets/anatomy/region_id_colors.json';

/// The only seven labels `region_id_colors.json` can produce.
const Set<String> anatomy2DRawLabels = {
  'head',
  'neck',
  'trunk',
  'left upper limb',
  'right upper limb',
  'left lower limb',
  'right lower limb',
};

/// Angle-independent labels. A limb is the same limb whichever side the camera
/// is on, because the ID map was painted with one shared colour table.
const Map<String, String> _commonRegions = {
  'head': 'Headache / Cranial',
  'neck': 'Neck',
  'left upper limb': 'Left Arm / Shoulder',
  'right upper limb': 'Right Arm / Shoulder',
  'left lower limb': 'Left Leg / Knee',
  'right lower limb': 'Right Leg / Knee',
};

/// The trunk is the one region that means something different depending on
/// which side of the body was photographed — the ID map cannot tell frontal
/// from dorsal torso, so the angle has to supply what the colour cannot.
const Map<Anatomy2DAngle, String> _trunkRegions = {
  Anatomy2DAngle.front: 'Chest / Heart',
  Anatomy2DAngle.back: 'Back Pain (Upper)',
  // A side view shows the flank, which body_graph files under the upper
  // abdomen rather than the chest.
  Anatomy2DAngle.left: 'Abdomen (Upper)',
  Anatomy2DAngle.right: 'Abdomen (Upper)',
};

/// Translates an ID-map label into one of the region strings the rest of the
/// app is keyed on.
///
/// Returns null for a label this table does not know, rather than guessing —
/// an unknown colour is a miss the caller should report, not a region to file
/// a patient's pain under.
String? backendRegionFor2D({
  required String idmapLabel,
  required Anatomy2DAngle angle,
}) {
  final label = idmapLabel.trim().toLowerCase();
  if (label == 'trunk') return _trunkRegions[angle];
  return _commonRegions[label];
}
