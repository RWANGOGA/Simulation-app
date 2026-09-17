// Resolves a BodyParts3D `part` (from atlas.json / atlas-female.json) down to
// one of the app's 14 fixed KB region strings — the same vocabulary the 2D
// AnatomyTapView system already produces via body_map_screen.dart's
// `_regionToKbName` / `_fineGrainedLabelToKbName`. Keeping this resolution
// entirely name-driven (BodyParts3D's English part names are precise and
// already carry laterality, e.g. "Left humerus", "Flexor digiti minimi
// brevis of right hand") means we don't need a hand-authored table across
// 2,234+888 parts, and don't depend on any node-hierarchy grouping (this
// dataset has none — it's a flat parts list with a `system` field and a
// per-part bounding box, confirmed by inspecting atlas.json directly).
//
// Only falls back to bounding-box geometry for the rare part whose name
// carries no recognizable region/laterality keyword.

export const KB_REGIONS = Object.freeze({
  HEAD: 'Headache / Cranial',
  NECK: 'Neck',
  CHEST: 'Chest / Heart',
  ABD_UPPER: 'Abdomen (Upper)',
  ABD_LOWER_LEFT: 'Abdomen (Lower Left)',
  ABD_LOWER_RIGHT: 'Abdomen (Lower Right)',
  HIPS: 'Hips / Groin',
  BACK_UPPER: 'Back Pain (Upper)',
  BACK_LOWER: 'Back Pain (Lower)',
  ARM_LEFT: 'Left Arm / Shoulder',
  ARM_RIGHT: 'Right Arm / Shoulder',
  LEG_LEFT: 'Left Leg / Knee',
  LEG_RIGHT: 'Right Leg / Knee',
});

// Tier 2 — specific organs/structures the app already has dedicated
// zoom-kit / KB coverage for (mirrors _fineGrainedLabelToKbName). Checked
// before the general keyword rules below, since e.g. "kidney" would
// otherwise fall through the "back" keyword to the wrong side-agnostic
// bucket, and "eye"/"ear"/"nose" need Headache/Cranial specifically rather
// than the generic head bucket's own (identical, here) target.
// Order matters: first match wins, so more specific phrases are listed
// before shorter substrings they contain (e.g. "left kidney" before
// "kidney").
const ORGAN_OVERRIDES = [
  [/\bleft kidney\b/, KB_REGIONS.BACK_LOWER],
  [/\bright kidney\b/, KB_REGIONS.BACK_LOWER],
  [/\bkidney\b/, KB_REGIONS.BACK_LOWER],
  [/\bheart\b|\bcardiac\b|\bpericardi/, KB_REGIONS.CHEST],
  [/\blung\b|\bbronch|\btrachea\b|\bpleura/, KB_REGIONS.CHEST],
  [/\bdiaphragm\b|\besophagus\b|\bsternum\b/, KB_REGIONS.CHEST],
  [/\bstomach\b|\bliver\b|\bgallbladder\b|\bpancreas\b|\bspleen\b|\bduodenum\b/, KB_REGIONS.ABD_UPPER],
  [/\bbladder\b|\bureter\b|\bprostate\b|\buterus\b|\bovary\b|\bovaries\b|\bcervix\b|\bvagina\b/, KB_REGIONS.HIPS],
  [/\beye\b|\borbit\b|\bcornea\b|\bretina\b|\biris\b|\blens\b/, KB_REGIONS.HEAD],
  [/\bear\b|\btympan|\bcochlea\b|\bauricle\b/, KB_REGIONS.HEAD],
  [/\bnose\b|\bnasal\b/, KB_REGIONS.HEAD],
  [/\bbrain\b|\bcerebr|\bcerebell/, KB_REGIONS.HEAD],
  [/\blarynx\b|\bpharynx\b|\bthyroid gland\b/, KB_REGIONS.NECK],
];

// Tier 1 — general keyword rules covering the bulk of muscles/bones/
// vessels/nerves, each part's name already stating which limb/segment (and
// side, where relevant) it belongs to.
const LATERAL_RULES = [
  // Arm / shoulder (hand+forearm+upper-arm all fold into the same KB
  // region, matching how the 2D system's "hand" zoom-kit already reports
  // back up to "Left/Right Arm / Shoulder" — see _zoomOptionsByKbName).
  [/hand\b|finger|digit|carpal|wrist/, 'ARM'],
  [/forearm|radius|ulna\b|elbow/, 'ARM'],
  [/humerus|shoulder|clavicle|scapula|deltoid|bicep|tricep|\barm\b|axilla/, 'ARM'],
  // Leg / knee (foot+lower-leg+thigh all fold into the same KB region,
  // matching the 2D system's "leg"/"foot" zoom-kits).
  [/foot\b|toe\b|tarsal|ankle|plantar|calcane/, 'LEG'],
  [/\bleg\b|thigh|femur|tibia|fibula|\bknee\b|calf|hamstring|quadricep|gastrocnemius|patella/, 'LEG'],
];

const SIDE_LEFT = /\bleft\b/;
const SIDE_RIGHT = /\bright\b/;

const NON_LATERAL_RULES = [
  [/\bhip\b|pelvis|pelvic|groin|glute/, KB_REGIONS.HIPS],
  [/\bskull\b|cranial|cranium|scalp|\bface\b|\bjaw\b|mandible|maxilla|zygomatic/, KB_REGIONS.HEAD],
  [/\bcervical\b|\bneck\b/, KB_REGIONS.NECK], // note: NOT "cervix" (reproductive) — \bcervical\b won't match "cervix"
  [/\blumbar\b/, KB_REGIONS.BACK_LOWER],
  [/\bthoracic\b|\bscapular region\b/, KB_REGIONS.BACK_UPPER],
  [/\bchest\b|thorax|\brib\b|pector/, KB_REGIONS.CHEST],
  [/\babdomen\b|abdominal/, KB_REGIONS.ABD_UPPER],
];

function classifyLateralKeyword(name) {
  const lower = name.toLowerCase();
  for (const [re, bucket] of LATERAL_RULES) {
    if (re.test(lower)) {
      if (SIDE_LEFT.test(lower)) return bucket === 'ARM' ? KB_REGIONS.ARM_LEFT : KB_REGIONS.LEG_LEFT;
      if (SIDE_RIGHT.test(lower)) return bucket === 'ARM' ? KB_REGIONS.ARM_RIGHT : KB_REGIONS.LEG_RIGHT;
      // Matched an arm/leg keyword but no explicit side in the name — fall
      // through to the geometric x-position fallback below rather than
      // guessing.
      return null;
    }
  }
  return null;
}

function classifyNonLateral(name) {
  const lower = name.toLowerCase();
  for (const [re, region] of NON_LATERAL_RULES) {
    if (re.test(lower)) return region;
  }
  return null;
}

/**
 * Geometric fallback, used for any part whose name carries no recognizable
 * keyword — in practice this means the whole-body skin/integumentary mesh
 * ("Skin" / "skin of body"), which is a SINGLE part spanning the entire
 * figure (confirmed directly in atlas.json: its own bounding box covers
 * y=0..1.73, i.e. feet to head-top). Because one part can span the whole
 * body, classification here MUST use the actual 3D point the ray hit
 * (`hitPoint`), never the part's own aggregate bounds — using the part's
 * bounds was the original bug: every tap on the skin resolved to the same
 * region (the skin mesh's own center, near the hips) regardless of where
 * on the body was actually tapped.
 *
 * Bands are calibrated against real measured landmarks in this dataset
 * (not guessed): top of head y=1.73; clavicle (shoulder line) y=1.41;
 * sternum/stomach (chest-to-abdomen transition) y=1.09-1.31; hip bone
 * (pelvis) y=0.93; sacrum (lower spine/back) y=0.93, z=-0.063 confirming
 * negative z = posterior. Torso half-width tops out around 0.17 (hip
 * bone/scapula) while the upper arm/hand sit at 0.19-0.24 — arms hang at
 * the sides in this pose (not a T-pose), so an x-distance check alongside
 * the y-band is what separates "arm" from "chest/abdomen" at the same
 * height, mirroring the existing 2D system's own left/right x-position
 * split technique (see body_map_screen.dart's `_resolveKbName`).
 */
function classifyByGeometry([hx, hy, hz], overallBounds) {
  const [min, max] = overallBounds;
  const height = max[1] - min[1];
  const fracY = (hy - min[1]) / height; // 0 = feet, 1 = top of head
  const isLeft = hx > 0; // confirmed: "Left humerus" etc. have positive x
  const isBack = hz < 0; // confirmed: sacrum/vertebrae sit at negative z

  // Arm/hand: outside the torso's own width, at shoulder-to-hip height.
  if (fracY > 0.44 && fracY < 0.83 && Math.abs(hx) > 0.185) {
    return isLeft ? KB_REGIONS.ARM_LEFT : KB_REGIONS.ARM_RIGHT;
  }

  if (fracY > 0.87) return KB_REGIONS.HEAD;
  if (fracY > 0.80) return KB_REGIONS.NECK;
  if (fracY > 0.66) return isBack ? KB_REGIONS.BACK_UPPER : KB_REGIONS.CHEST;
  if (fracY > 0.58) return isBack ? KB_REGIONS.BACK_LOWER : KB_REGIONS.ABD_UPPER;
  if (fracY > 0.50) return isBack ? KB_REGIONS.BACK_LOWER : (isLeft ? KB_REGIONS.ABD_LOWER_LEFT : KB_REGIONS.ABD_LOWER_RIGHT);
  if (fracY > 0.44) return KB_REGIONS.HIPS;
  return isLeft ? KB_REGIONS.LEG_LEFT : KB_REGIONS.LEG_RIGHT;
}

/**
 * Resolve one atlas `part` (hit at 3D point `hitPoint`, in the same
 * coordinate space as `part.bounds`) to a KB region string. `overallBounds`
 * is `[minXYZ, maxXYZ]` across every part in the currently-loaded atlas —
 * compute it once per model load, not per tap. `hitPoint` matters (rather
 * than just using `part.bounds`) because several parts — most importantly
 * the whole-body skin — span far more than one region.
 */
export function resolveKbRegion(part, hitPoint, overallBounds) {
  const name = part.name || '';
  for (const [re, region] of ORGAN_OVERRIDES) {
    if (re.test(name.toLowerCase())) return region;
  }
  const lateral = classifyLateralKeyword(name);
  if (lateral) return lateral;
  const nonLateral = classifyNonLateral(name);
  if (nonLateral) return nonLateral;
  return classifyByGeometry(hitPoint, overallBounds);
}
