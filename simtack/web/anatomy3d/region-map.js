// Resolves a BodyParts3D `part` (from atlas.json / atlas-female.json) down
// to one of the app's KB region strings. Keeping this resolution entirely
// name-driven (BodyParts3D's English part names are precise and already
// carry laterality, e.g. "Left humerus", "Flexor digiti minimi brevis of
// right hand") means we don't need a hand-authored table across
// 2,234+888 parts, and don't depend on any node-hierarchy grouping (this
// dataset has none — it's a flat parts list with a `system` field and a
// per-part bounding box, confirmed by inspecting atlas.json directly).
//
// Originally the arm collapsed to one "Arm / Shoulder" region and the leg
// to one "Leg / Knee" region, regardless of whether a finger, elbow, or
// shoulder was tapped — reported directly as the wrong behavior: tapping a
// finger, an armpit, or a knuckle all showed "Shoulder", undoing the 3D
// view's own precision. The arm and leg are now split into real
// joint-based regions (Shoulder/Elbow/Wrist/Hand/Armpit and
// Thigh/Knee/Shin or Calf/Ankle/Foot), each backed by its own written
// medical content in the backend KB (Backend-fastapi/app/data/
// anatomy_kb.json) — not just a label change.
//
// Only falls back to bounding-box geometry for the rare part whose name
// carries no recognizable region/laterality keyword — in practice, this is
// almost entirely the whole-body skin mesh, which IS the primary tap
// surface (a patient touches their visible skin, not a named organ), so
// the geometric bands below matter as much as the keyword rules.

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

  SHOULDER_LEFT: 'Left Shoulder',
  SHOULDER_RIGHT: 'Right Shoulder',
  ARMPIT_LEFT: 'Left Armpit',
  ARMPIT_RIGHT: 'Right Armpit',
  ELBOW_LEFT: 'Left Elbow',
  ELBOW_RIGHT: 'Right Elbow',
  WRIST_LEFT: 'Left Wrist',
  WRIST_RIGHT: 'Right Wrist',
  HAND_LEFT: 'Left Hand',
  HAND_RIGHT: 'Right Hand',

  THIGH_LEFT: 'Left Thigh',
  THIGH_RIGHT: 'Right Thigh',
  KNEE_LEFT: 'Left Knee',
  KNEE_RIGHT: 'Right Knee',
  SHIN_LEFT: 'Left Shin / Calf',
  SHIN_RIGHT: 'Right Shin / Calf',
  ANKLE_LEFT: 'Left Ankle',
  ANKLE_RIGHT: 'Right Ankle',
  FOOT_LEFT: 'Left Foot',
  FOOT_RIGHT: 'Right Foot',
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
// vessels/nerves, each part's name already stating which limb segment (and
// side, where relevant) it belongs to. Order matters within each arm/leg
// group: more distal/specific terms first, since e.g. "forearm" muscles
// often have "flexor"/"extensor" names that don't literally say "wrist" or
// "elbow" — grouped by the joint they actually act on/near.
const LATERAL_RULES = [
  // Arm chain, wrist-to-shoulder (checked in this order — first match wins
  // — so "hand" terms are claimed before broader "arm" terms would catch
  // them too).
  [/\bhand\b|finger|digit|carpal(?!.{0,20}artery)|metacarpal|palmar|dorsal.{0,15}(hand|digit)/, 'HAND'],
  [/\bwrist\b|flexor retinaculum|extensor retinaculum/, 'WRIST'],
  [/forearm|\bradius\b|\bulna\b|extensor carpi|flexor carpi|flexor digit|extensor digit/, 'ELBOW'],
  [/\belbow\b|\bhumerus\b|bicep|tricep|brachi/, 'ELBOW'],
  // Leading \b only (no trailing one): the real BodyParts3D names are
  // "Left/Right axillary artery/vein", not literally "axilla" — but a
  // trailing-boundary-free match also has to not accidentally match
  // "maxilla" (the jaw bone), which contains "axilla" as a substring too.
  // \baxilla correctly excludes it: there's a word-boundary before the "a"
  // in standalone "axilla"/"axillary", but none before the "axilla" inside
  // "m|axilla" (m and a are both word characters, so no \b there).
  [/\baxilla|armpit/, 'ARMPIT'],
  [/\bshoulder\b|\bclavicle\b|\bscapula\b|deltoid|rotator cuff|supraspinatus|infraspinatus|subscapularis|teres/, 'SHOULDER'],
  [/\barm\b/, 'SHOULDER'], // generic "[Left/Right] arm" fallback within the arm keyword group
  // Leg chain, hip-to-toe.
  [/\bfoot\b|\btoe\b|tarsal|plantar|calcane|metatarsal/, 'FOOT'],
  [/\bankle\b/, 'ANKLE'],
  [/\btibia\b|\bfibula\b|\bcalf\b|gastrocnemius|soleus|shin|tibialis/, 'SHIN'],
  [/\bknee\b|patella|meniscus|cruciate|collateral ligament of.{0,10}knee/, 'KNEE'],
  [/\bthigh\b|\bfemur\b|hamstring|quadricep|sartorius|iliotibial/, 'THIGH'],
  [/\bleg\b/, 'THIGH'], // generic "[Left/Right] leg" fallback within the leg keyword group
];

const SIDE_LEFT = /\bleft\b/;
const SIDE_RIGHT = /\bright\b/;

const LATERAL_BUCKET_TO_REGION = {
  HAND: [KB_REGIONS.HAND_LEFT, KB_REGIONS.HAND_RIGHT],
  WRIST: [KB_REGIONS.WRIST_LEFT, KB_REGIONS.WRIST_RIGHT],
  ELBOW: [KB_REGIONS.ELBOW_LEFT, KB_REGIONS.ELBOW_RIGHT],
  ARMPIT: [KB_REGIONS.ARMPIT_LEFT, KB_REGIONS.ARMPIT_RIGHT],
  SHOULDER: [KB_REGIONS.SHOULDER_LEFT, KB_REGIONS.SHOULDER_RIGHT],
  FOOT: [KB_REGIONS.FOOT_LEFT, KB_REGIONS.FOOT_RIGHT],
  ANKLE: [KB_REGIONS.ANKLE_LEFT, KB_REGIONS.ANKLE_RIGHT],
  SHIN: [KB_REGIONS.SHIN_LEFT, KB_REGIONS.SHIN_RIGHT],
  KNEE: [KB_REGIONS.KNEE_LEFT, KB_REGIONS.KNEE_RIGHT],
  THIGH: [KB_REGIONS.THIGH_LEFT, KB_REGIONS.THIGH_RIGHT],
};

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
      const [leftRegion, rightRegion] = LATERAL_BUCKET_TO_REGION[bucket];
      if (SIDE_LEFT.test(lower)) return leftRegion;
      if (SIDE_RIGHT.test(lower)) return rightRegion;
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
 * (not guessed), all as fracY = absolute_y / 1.73 (total height):
 *   head top 1.73 (1.0); clavicle/shoulder 1.41 (0.815); scapula 1.338
 *   (0.774); humerus/upper-arm 1.261 (0.729); radius+ulna/forearm 0.999
 *   (0.578); wrist (flexor retinaculum) 0.871 (0.504); hand (metacarpal/
 *   palmar) 0.84-0.867 (0.486-0.501); sacrum/hip 0.933 (0.539); iliotibial
 *   tract/thigh 0.708 (0.409); tibialis anterior/shin 0.236 (0.136);
 *   calcaneus/heel 0.034 (0.020); metatarsal/foot 0.021-0.028
 *   (0.012-0.016). Torso half-width tops out around 0.17 (hip bone/
 *   scapula) while the arm sits at 0.19-0.27 out from center — arms hang
 *   at the sides in this pose (not a T-pose), so an x-distance check
 *   alongside the y-band is what separates "arm" from "chest/abdomen" at
 *   the same height, mirroring the existing 2D system's own left/right
 *   x-position split technique (see body_map_screen.dart's
 *   `_resolveKbName`).
 */
function classifyByGeometry([hx, hy, hz], overallBounds) {
  const [min, max] = overallBounds;
  const height = max[1] - min[1];
  const fracY = (hy - min[1]) / height; // 0 = feet, 1 = top of head
  const isLeft = hx > 0; // confirmed: "Left humerus" etc. have positive x
  const isBack = hz < 0; // confirmed: sacrum/vertebrae sit at negative z

  // Arm chain: outside the torso's own width, at shoulder-to-hip height.
  // Sub-banded using the real clavicle/humerus/forearm/wrist/hand
  // landmarks above instead of one flat "arm" bucket.
  if (fracY > 0.44 && fracY < 0.83 && Math.abs(hx) > 0.185) {
    if (fracY > 0.76) return isLeft ? KB_REGIONS.SHOULDER_LEFT : KB_REGIONS.SHOULDER_RIGHT;
    if (fracY > 0.62) return isLeft ? KB_REGIONS.ELBOW_LEFT : KB_REGIONS.ELBOW_RIGHT;
    if (fracY > 0.52) return isLeft ? KB_REGIONS.WRIST_LEFT : KB_REGIONS.WRIST_RIGHT;
    return isLeft ? KB_REGIONS.HAND_LEFT : KB_REGIONS.HAND_RIGHT;
  }

  if (fracY > 0.87) return KB_REGIONS.HEAD;
  if (fracY > 0.80) return KB_REGIONS.NECK;
  if (fracY > 0.66) return isBack ? KB_REGIONS.BACK_UPPER : KB_REGIONS.CHEST;
  if (fracY > 0.58) return isBack ? KB_REGIONS.BACK_LOWER : KB_REGIONS.ABD_UPPER;
  if (fracY > 0.50) return isBack ? KB_REGIONS.BACK_LOWER : (isLeft ? KB_REGIONS.ABD_LOWER_LEFT : KB_REGIONS.ABD_LOWER_RIGHT);
  if (fracY > 0.44) return KB_REGIONS.HIPS;

  // Leg chain, sub-banded using the real thigh/shin/heel/foot landmarks
  // above instead of one flat "leg" bucket.
  if (fracY > 0.30) return isLeft ? KB_REGIONS.THIGH_LEFT : KB_REGIONS.THIGH_RIGHT;
  if (fracY > 0.22) return isLeft ? KB_REGIONS.KNEE_LEFT : KB_REGIONS.KNEE_RIGHT;
  if (fracY > 0.06) return isLeft ? KB_REGIONS.SHIN_LEFT : KB_REGIONS.SHIN_RIGHT;
  if (fracY > 0.03) return isLeft ? KB_REGIONS.ANKLE_LEFT : KB_REGIONS.ANKLE_RIGHT;
  return isLeft ? KB_REGIONS.FOOT_LEFT : KB_REGIONS.FOOT_RIGHT;
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
