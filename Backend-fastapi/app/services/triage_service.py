import json
import math
from typing import Any, Dict, List, Optional, Tuple
from app.schemas import TriageCreate
from app.data.body_graph import (
    find_connection,
    CONCERN_RISK_BUMP,
    PROPAGATION_EDGE_WEIGHTS,
)

# Kept as the canonical reference table. Real scoring goes through the
# keyword matchers below because the mobile client sends descriptive labels
# ("Chest / Heart", "Abdomen (Upper)", "Back Pain (Lower)") rather than these
# exact keys.
REGION_WEIGHTS: Dict[str, float] = {
    "Chest": 0.40, "Head": 0.35, "Abdomen": 0.25, "Back": 0.20,
    "Left Arm": 0.20, "Right Arm": 0.15,
    "Left Leg": 0.10, "Right Leg": 0.10
}
# Lowercase keys; lookups normalize input via _pain_type_weight so the
# client's title-case labels ("Sharp", "Cramping") still match.
PAIN_TYPE_WEIGHTS: Dict[str, float] = {
    "crushing": 0.20, "stabbing": 0.15, "sharp": 0.12,
    "burning": 0.10, "cramping": 0.09, "throbbing": 0.08, "numb": 0.08,
    "dull": 0.05
}

def _region_weight(body_region: Optional[str]) -> float:
    """
    Match the region by clinical keyword instead of an exact string, so
    labels like "Chest / Heart" or "Abdomen (Upper)" resolve correctly and
    future label tweaks don't silently fall back to the 0.10 default.
    """
    r = (body_region or "").lower()
    if "chest" in r or "heart" in r:
        return 0.40
    if "head" in r or "cranial" in r:
        return 0.35
    if "neck" in r:
        return 0.30
    if "abdomen" in r or "stomach" in r:
        return 0.25
    if "back" in r:
        return 0.20
    if any(k in r for k in ["arm", "shoulder", "armpit", "elbow", "wrist", "hand"]):
        return 0.20 if "left" in r else 0.15
    if any(k in r for k in ["leg", "knee", "thigh", "shin", "calf", "ankle", "foot", "hip", "groin"]):
        return 0.10
    return 0.10

def _pain_type_weight(pain_type: Optional[str]) -> float:
    """Case-insensitive lookup — the client sends title-case labels."""
    return PAIN_TYPE_WEIGHTS.get((pain_type or "").strip().lower(), 0.05)

def _heart_rate_contribution(heart_rate: Optional[float]) -> float:
    # `not heart_rate` rather than `is None`, so a 0 is treated as "no
    # measurement" here exactly as `_heart_rate_is_critical` and the red-flag
    # rules treat it. A regenerated fixture made the contradiction visible: the
    # old version read 0 bpm as profound bradycardia and added the critical bump to
    # the score while the tier refused to call it an emergency. Two answers to the
    # same question in the same record is what the paper cannot defend, and Unit 4
    # is about to put a real camera number in this field — where a failed capture
    # reported as 0 must change nothing at all.
    if not heart_rate:
        return 0.0
    if heart_rate > 120 or heart_rate < 50:
        return 0.15
    if heart_rate > 100:
        return 0.10
    return 0.0

def _factor(factor: str, contribution: float) -> Dict[str, Any]:
    """One row of the risk explanation.

    `contribution` is the name these always should have had. Nothing here is a
    SHAP value: there is no attribution model, no background dataset and no
    cooperative-game solution behind these numbers - they are hand-set weights
    added together, and the old key asserted otherwise to anyone reading the API.
    The rename matters because a clinician or reviewer who believes the numbers are
    SHAP-derived will also believe they explain the model's *behaviour* rather than
    restating its constants.

    `shap` is mirrored for one release. Clients already shipped read that key, so a
    row carrying only `contribution` renders as "+0%" on every factor of every
    triage for those versions - a silent, total loss of the explanation rather than
    a visible break. Drop the mirror once those builds are gone; `tests/
    test_triage_service.py` pins the equivalence in the meantime.
    """
    return {
        "factor": factor,
        "contribution": contribution,
        "shap": contribution,
        "impact": "+" if contribution >= 0 else "-",
    }


def _connectivity_contributions(region: str, sibling_regions: List[str]) -> List[Dict[str, Any]]:
    """The direct-edge (one-hop) co-report bump — a fixed weight, not propagation.

    For each other region reported in the same visit, look up whether this
    region lists it as a connection and add that edge's fixed concern weight
    (see CONCERN_RISK_BUMP). Two regions must be *adjacent in the hand-authored
    graph* for this to fire; if neither lists the other, nothing is added even
    when both are reported.

    Named "connectivity" and not "propagation" on purpose: this term ignores the
    neighbour's own severity and never travels more than one edge. It is a fixed
    per-edge weight over hand-authored adjacency — not a weighted message pass,
    and not a learned edge.

    Both this and `propagate` run on every score. This term is the baseline the
    propagation ablation is measured against, so it is deliberately kept rather
    than folded into the message pass.
    """
    contributions: List[Dict[str, Any]] = []
    seen = set()
    for other_region in sibling_regions:
        if other_region == region or other_region in seen:
            continue
        seen.add(other_region)
        conn = find_connection(region, other_region)
        if conn is None:
            continue
        contributions.append(_factor(
            f"Connected to reported {other_region} pain: {conn['note']}",
            CONCERN_RISK_BUMP[conn["concern"]],
        ))
    return contributions


# How much of the received signal survives into the scored region's contribution.
# Stated, hand-chosen analysis parameter (not fitted): the message from a
# neighbour is its severity, scaled by the edge's concern weight, then multiplied
# by this decay so a referral informs the score without dominating it.
PROPAGATION_DECAY = 0.10


def _round2_half_up(value: float) -> float:
    """Round to two decimals, half up, matching the Dart port.

    Python's round() is banker's (half-to-even) while Dart's roundToDouble() is
    half-away-from-zero. The propagation product lands exactly on such ties —
    0.50 (moderate) x 0.10 (decay) x 5/10 = 0.025 — so inheriting either
    language's rule would put the two engines on opposite sides of a 0.01 step
    and break the 1e-6 parity contract. Rounding explicitly here removes that.

    Only ever called with the non-negative propagation values, where half-up and
    half-away-from-zero are the same rule; a negative argument would round toward
    zero and disagree with Dart.
    """
    return math.floor(value * 100.0 + 0.5) / 100.0


def propagate(
    region: str,
    co_reported: List[str],
    severity_by_region: Dict[str, int],
) -> List[Dict[str, Any]]:
    """One round of weighted message passing over the hand-authored graph.

    This is genuine graph inference in the weak, explicit sense: a region's score
    is informed by what its neighbours are *reporting*, not merely by the fact
    that a neighbour exists. For every other region reported in the same visit
    that is adjacent to `region`, the neighbour sends a message

        edge weight (concern) x neighbour severity / 10 x PROPAGATION_DECAY

    which becomes its own contribution row naming the path, e.g.
    ``"Chest / Heart → Left Arm / Shoulder referral"``. A neighbour with no
    recorded severity sends nothing (severity 0 / absent), and a pair that is
    two or more edges apart is unreachable — this walks one adjacency list, so it
    is one hop by construction, not by policy.

    Deliberately *not* a trained model: nothing here is learned, the edge weights
    are stated constants over a dict someone typed, and the output is fully
    reproducible from the inputs. It is rule-based propagation, and must be
    reported as such. See `_connectivity_contributions` for the separate fixed
    co-report bump that this is ablated against.

    Iteration is over a sorted copy of `co_reported` so the emitted row order is
    stable; the caller's final sort is stable too, which keeps tie-broken rows in
    a deterministic order across both engines.
    """
    contributions: List[Dict[str, Any]] = []
    seen = set()
    for other_region in sorted(co_reported):
        if other_region == region or other_region in seen:
            continue
        seen.add(other_region)
        conn = find_connection(region, other_region)
        if conn is None:
            continue
        severity = severity_by_region.get(other_region)
        if not severity:
            continue
        received = (
            PROPAGATION_EDGE_WEIGHTS[conn["concern"]]
            * (severity / 10.0)
            * PROPAGATION_DECAY
        )
        amount = _round2_half_up(received)
        if amount == 0.0:
            continue
        contributions.append(_factor(
            f"{region} → {other_region} referral",
            amount,
        ))
    return contributions


def _bmi_contribution(weight_kg: Optional[float], height_cm: Optional[float]) -> Tuple[float, Optional[float]]:
    """
    Weight/height were collected at intake but never influenced the score.
    Extreme BMI values add a small risk factor. Returns (contribution, bmi).
    """
    if not weight_kg or not height_cm or height_cm <= 0:
        return 0.0, None
    bmi = weight_kg / ((height_cm / 100.0) ** 2)
    if bmi >= 30 or bmi < 18.5:
        return 0.05, bmi
    return 0.0, bmi

def compute_risk(
    data: TriageCreate,
    sibling_regions: Optional[List[str]] = None,
    patient_weight: Optional[float] = None,
    patient_height: Optional[float] = None,
    sibling_severities: Optional[Dict[str, int]] = None,
    include_propagation: bool = True,
) -> Tuple[float, List[Dict[str, Any]]]:
    """sibling_regions: the body_region of every other pain point already
    submitted in this same visit (same visit_id), if any — lets the score
    reflect real relationships between pain locations reported together,
    not just this one point in isolation.

    sibling_severities: those siblings' severities, keyed by body_region. Needed
    for `propagate` — a neighbour's signal is *what it reported*, so without a
    severity there is nothing to carry and no propagation row is emitted. A
    caller that omits this map still gets the fixed co-report bump, which needs
    only adjacency.

    include_propagation: the ablation seam. False reproduces the score without
    the message-passing term while leaving every other factor — including the
    co-report bump — untouched, so the simulation can measure what propagation
    adds instead of assuming it helps.
    """
    contributions: List[Dict[str, Any]] = []
    severity_c = round((data.severity / 10.0) * 0.50, 2)
    contributions.append(_factor(f"Severity {data.severity}/10", severity_c))
    region_c = _region_weight(data.body_region)
    contributions.append(_factor(f"Region: {data.body_region}", region_c))
    pain_c = _pain_type_weight(data.pain_type)
    contributions.append(_factor(f"Pain type: {data.pain_type}", pain_c))
    hr_c = _heart_rate_contribution(data.heart_rate)
    if hr_c:
        contributions.append(_factor(f"Heart rate {data.heart_rate} bpm", hr_c))
    if sibling_regions:
        contributions.extend(_connectivity_contributions(data.body_region, sibling_regions))
        if include_propagation and sibling_severities:
            contributions.extend(
                propagate(data.body_region, sibling_regions, sibling_severities)
            )
    bmi_c, bmi = _bmi_contribution(patient_weight, patient_height)
    if bmi_c:
        contributions.append(_factor(f"BMI {bmi:.1f} (weight/height)", bmi_c))
    raw = round(sum(c["contribution"] for c in contributions), 2)
    risk = min(1.0, raw)
    # The cap has to appear in the explanation, or the explanation is wrong.
    #
    # `shap` values are advertised as the reasons behind `risk_score`, and the card
    # draws a bar per factor against the total. Summing to 1.30 while the score says
    # 1.00 means the panel shows the clinician a breakdown that does not add up to
    # the number it is explaining - and the only way they can discover the
    # discrepancy is by doing the arithmetic themselves, on a screen whose purpose
    # is to save them from doing that.
    #
    # Recorded as a negative factor rather than by dropping the clamp: the score is
    # a 0..1 quantity that bands, client bars and stored rows all assume, and
    # widening it would silently re-band every historical triage. The cap is also
    # genuinely clinical information - findings that sum to 1.30 are more pressured
    # than findings that sum to exactly 1.00, and the capped number cannot show it,
    # so the row says how much was discarded.
    if risk < raw:
        contributions.append(_factor(
            f"Score capped at 1.00 (findings summed to {raw:.2f})",
            round(risk - raw, 2),
        ))
    contributions.sort(key=lambda c: c["contribution"], reverse=True)
    return risk, contributions


def risk_level(risk: float) -> str:
    if risk >= 0.7:
        return "high"
    if risk >= 0.4:
        return "medium"
    return "low"


def explain(contributions: List[Dict[str, Any]]) -> str:
    return json.dumps(contributions)


# ── Red-flag escalation ───────────────────────────────────────────────────
#
# The weighted score above answers "how concerning is this overall". It is a sum
# that is clamped at 1.0 and mixes unrelated factors, so it cannot express "this
# one finding is an emergency by itself": crushing chest pain that spreads to
# the arm at severity 6 can land in the medium band while clinically needing an
# ambulance now. These rules run *beside* the score, never instead of it - they
# do not change `compute_risk`, and each trigger names the finding that fired so
# a clinician can audit the decision.

ESCALATION_EMERGENCY = "emergency"
ESCALATION_URGENT = "urgent"
ESCALATION_ROUTINE = "routine"

ACTION_SEEK_EMERGENCY_CARE = "seek_emergency_care"
ACTION_SEEK_URGENT_CARE = "seek_urgent_care"
ACTION_ROUTINE_REVIEW = "routine_review"

# Vital-sign floor, shared by the red-flag rules and the tier below them. Named
# constants rather than six literals, because Unit 5's sensitivity analysis has to
# perturb "what heart rate counts as critical" in one place and see the tier flip.
HEART_RATE_CRITICAL_ABOVE = 120.0
HEART_RATE_CRITICAL_BELOW = 50.0

_ACTION_BY_LEVEL = {
    ESCALATION_EMERGENCY: ACTION_SEEK_EMERGENCY_CARE,
    ESCALATION_URGENT: ACTION_SEEK_URGENT_CARE,
    ESCALATION_ROUTINE: ACTION_ROUTINE_REVIEW,
}

# Crushing and stabbing describe the pain itself, which is what makes a chest
# report alarming regardless of how the patient rates it.
_CONCERNING_CHEST_PAIN_TYPES = ("crushing", "stabbing")
_HIGH_CONCERN_REGION_KEYWORDS = (
    "chest", "heart", "head", "cranial", "neck", "abdomen", "stomach",
)


def _is_high_concern_region(region: str) -> bool:
    return any(word in region for word in _HIGH_CONCERN_REGION_KEYWORDS)


def _heart_rate_is_critical(heart_rate: Optional[float]) -> bool:
    """True for a rate outside 50-120 bpm.

    ``0`` is read as "no measurement" and not as profound bradycardia, which is
    what the escalation rules already assume. That matters from Unit 4 onward:
    a camera pipeline that fails must send null, and a tier that called a failed
    measurement an emergency would be worse than no measurement at all.
    """
    if not heart_rate:
        return False
    rate = float(heart_rate)
    return rate > HEART_RATE_CRITICAL_ABOVE or rate < HEART_RATE_CRITICAL_BELOW


def _red_flags(source: Any) -> List[Tuple[str, str, str]]:
    """Every red flag on [source] as ``(level, code, detail)``, in fire order.

    Shared by `escalation_for` and `triage_tier` so the two cannot disagree about
    which finding is an emergency and which is urgent. Ranking and formatting are
    the callers' business; this is the only place the rules live.
    """
    region = (getattr(source, "body_region", None) or "").strip().lower()
    pain_type = (getattr(source, "pain_type", None) or "").strip().lower()
    direction = (getattr(source, "direction", None) or "").strip().lower()
    severity = getattr(source, "severity", None) or 0
    heart_rate = getattr(source, "heart_rate", None)

    is_chest = "chest" in region or "heart" in region
    is_head = "head" in region or "cranial" in region

    findings: List[Tuple[str, str, str]] = []

    if is_chest:
        if any(word in pain_type for word in _CONCERNING_CHEST_PAIN_TYPES):
            findings.append((
                ESCALATION_EMERGENCY,
                "chest_pain_crushing",
                f"{pain_type.title()} chest pain",
            ))
        if "radiat" in direction:
            findings.append((
                ESCALATION_EMERGENCY,
                "chest_pain_radiating",
                "Chest pain that spreads to another area",
            ))
        if severity >= 8:
            findings.append((
                ESCALATION_EMERGENCY,
                "chest_pain_severe",
                f"Chest pain rated {severity}/10",
            ))

    if heart_rate:
        rate = float(heart_rate)
        if rate > HEART_RATE_CRITICAL_ABOVE or rate < HEART_RATE_CRITICAL_BELOW:
            findings.append((
                ESCALATION_EMERGENCY,
                "heart_rate_critical",
                f"Heart rate {rate:g} bpm",
            ))
        elif rate > 100:
            findings.append((
                ESCALATION_URGENT,
                "heart_rate_high",
                f"Heart rate {rate:g} bpm",
            ))

    if severity >= 10:
        if _is_high_concern_region(region):
            findings.append((
                ESCALATION_EMERGENCY,
                "pain_maximum_high_concern_region",
                f"{region or 'Reported region'} rated 10/10",
            ))
        else:
            findings.append((ESCALATION_URGENT, "pain_maximum", "Pain rated 10/10"))
    elif severity >= 8 and is_head:
        findings.append((
            ESCALATION_URGENT,
            "head_pain_severe",
            f"Head pain rated {severity}/10",
        ))

    return findings


def escalation_for(source: Any) -> Dict[str, Any]:
    """Red-flag screen for one pain point.

    ``source`` is a `TriageSession` row or a `TriageCreate` payload - both carry
    the same clinical columns, so the rules apply identically on write and on
    every read. Computing on read is deliberate: a stored row is judged by the
    current rules rather than by whatever was computed when it was submitted,
    and no migration is needed to add or correct a rule.

    Returns ``{"level", "action", "triggers"}`` where each trigger is
    ``{"code", "detail"}``: the code is stable for clients to localise (or
    count), the detail is English for logs and API consumers.
    """
    findings = _red_flags(source)

    # Emergencies first, then urgences, each in the order the rules fired.
    findings.sort(key=lambda finding: 0 if finding[0] == ESCALATION_EMERGENCY else 1)

    level = ESCALATION_ROUTINE
    if any(finding[0] == ESCALATION_EMERGENCY for finding in findings):
        level = ESCALATION_EMERGENCY
    elif findings:
        level = ESCALATION_URGENT

    return {
        "level": level,
        "action": _ACTION_BY_LEVEL[level],
        "triggers": [
            {"code": code, "detail": detail} for _, code, detail in findings
        ],
    }


# ── Triage tier (SATS categories) ─────────────────────────────────────────
#
# What this adds over the two level sets above, and why neither of them was it:
#
#   * `risk_level` bands a clamped score. It is arithmetic dressed as a clinical
#     category: 0.7 is "high" only because the weights happen to reach it there.
#   * `escalation_for` answers "does one finding need care now" in three levels
#     with no category a referral letter could carry.
#
# Neither could be compared against a clinician's judgement, which is the whole
# point of the evaluation this system is missing, so both stay as they are for
# historical rows and this maps the same findings onto a published four-category
# scale.
#
# HONESTY BOUNDARY. SATS (Gosling et al., Emergency Medicine Journal 2006) decides
# a category from vital signs, pain, mechanism of injury and available resources.
# This function borrows the scale's four categories and their colour names and
# decides them from what one pain point actually carries: region, character,
# severity, direction, a heart rate where one exists, and the score. It is
# SATS-shaped, not the SATS algorithm, so it may be described as "mapped to SATS
# categories" and never as "validated". The only evidence that could support
# agreement is the clinician-versus-tool kappa over the vignette set, which
# records the answer beside these tiers as `clinician_tier`.

TRIAGE_SCALE = "SATS"

TIER_RED = "red"
TIER_ORANGE = "orange"
TIER_YELLOW = "yellow"
TIER_GREEN = "green"

# Most urgent first: the scale's own ordering, which clients draw as a colour
# strip and Unit 5 uses as the ordinal axis for weighted kappa.
TIERS: Tuple[str, ...] = (TIER_RED, TIER_ORANGE, TIER_YELLOW, TIER_GREEN)

TIER_CATEGORIES: Dict[str, str] = {
    TIER_RED: "emergency",
    TIER_ORANGE: "very_urgent",
    TIER_YELLOW: "urgent",
    TIER_GREEN: "routine",
}

# Where the score is allowed to decide the category. These equal the legacy bands
# today and are still stored separately on purpose: `bands` describes the number,
# these describe how much weight the number gets, and the sensitivity analysis has
# to move one without re-banding every historical triage.
TIER_ORANGE_SCORE_MIN = 0.70
TIER_YELLOW_SCORE_MIN = 0.40

# Codes for the two decisions no finding can name. `decided_by` is then complete
# for every tier: red and orange always cite findings, yellow and green cite the
# band they came from, so an audit can always say why a patient was seated where
# they were seated.
TIER_RULE_SCORE_CONCERNING_REGION = "score_high_in_concerning_region"
TIER_RULE_SCORE_URGENT_BAND = "score_reaches_urgent_band"
TIER_RULE_SCORE_BELOW_URGENT_BAND = "score_below_urgent_band"

# Which tiers a persisted legacy band can correspond to. One-to-many, and
# deliberately documented as such rather than smoothed into a function: a `high`
# score with no red flag and an ordinary region is Yellow, while a `low` score and
# a crushing chest pain is Red. Reading the band as the tier would have been the
# claim that the score decides the category, which is exactly what the red-flag
# screen exists to contradict.
LEGACY_BAND_TIERS: Dict[str, Tuple[str, ...]] = {
    "high": (TIER_RED, TIER_ORANGE, TIER_YELLOW),
    "medium": (TIER_RED, TIER_ORANGE, TIER_YELLOW),
    "low": (TIER_RED, TIER_ORANGE, TIER_GREEN),
}


def triage_tier(source: Any, risk: Optional[float]) -> Dict[str, Any]:
    """The SATS category for one pain point, decided beside the score.

    Rules first, score second - the order a triage nurse uses. An emergency
    finding is Red whatever the total says, and a calm-looking total never
    softens a red flag. Only when nothing has fired does the number get a vote,
    and then it votes for at most Orange-on-a-concerning-region, Yellow, Green.

    Never reads or writes anything outside its own return value: a tier is derived
    on every read exactly like the escalation verdict, so changing a threshold here
    cannot mutate a stored `risk_score` (pinned by tests/test_triage_tier.py).
    """
    flags = _red_flags(source)
    emergency = [code for level, code, _ in flags if level == ESCALATION_EMERGENCY]
    urgent = [code for level, code, _ in flags if level == ESCALATION_URGENT]

    score = float(risk) if risk is not None else 0.0
    region = (getattr(source, "body_region", None) or "").strip().lower()
    heart_rate = getattr(source, "heart_rate", None)

    codes: List[str]
    tier: str
    if emergency or _heart_rate_is_critical(heart_rate):
        tier = TIER_RED
        codes = list(emergency)
        # The vital-sign floor is checked again here on purpose. It coincides with
        # the `heart_rate_critical` flag today because both read the same two
        # constants; keeping it visible is what stops a future edit to the
        # red-flag screen from quietly demoting an abnormal heart rate.
        if _heart_rate_is_critical(heart_rate) and "heart_rate_critical" not in codes:
            codes.append("heart_rate_critical")
    elif urgent or (score >= TIER_ORANGE_SCORE_MIN and _is_high_concern_region(region)):
        tier = TIER_ORANGE
        codes = list(urgent)
        if score >= TIER_ORANGE_SCORE_MIN and _is_high_concern_region(region):
            codes.append(TIER_RULE_SCORE_CONCERNING_REGION)
    elif score >= TIER_YELLOW_SCORE_MIN:
        tier = TIER_YELLOW
        codes = [TIER_RULE_SCORE_URGENT_BAND]
    else:
        tier = TIER_GREEN
        codes = [TIER_RULE_SCORE_BELOW_URGENT_BAND]

    return {
        "tier": tier,
        "scale": TRIAGE_SCALE,
        "category": TIER_CATEGORIES[tier],
        "decided_by": codes,
    }

