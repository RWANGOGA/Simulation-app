import json
from typing import Any, Dict, List, Optional, Tuple
from app.schemas import TriageCreate
from app.data.body_graph import find_connection, CONCERN_RISK_BUMP

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
    if heart_rate is None:
        return 0.0
    if heart_rate > 120 or heart_rate < 50:
        return 0.15
    if heart_rate > 100:
        return 0.10
    return 0.0

def _connectivity_contributions(region: str, sibling_regions: List[str]) -> List[Dict[str, Any]]:
    """Checks the current region against every other region already
    reported in the same visit. Each real anatomical connection found
    adds its own contribution, scaled by how concerning that specific
    connection is (see CONCERN_RISK_BUMP) — e.g. chest pain + left arm
    pain in the same visit is a much bigger deal than lower back pain +
    leg pain, even though both are "connected" in the graph."""
    contributions: List[Dict[str, Any]] = []
    seen = set()
    for other_region in sibling_regions:
        if other_region == region or other_region in seen:
            continue
        seen.add(other_region)
        conn = find_connection(region, other_region)
        if conn is None:
            continue
        contributions.append({
            "factor": f"Connected to reported {other_region} pain: {conn['note']}",
            "shap": CONCERN_RISK_BUMP[conn["concern"]],
        })
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
) -> Tuple[float, List[Dict[str, Any]]]:
    """sibling_regions: the body_region of every other pain point already
    submitted in this same visit (same visit_id), if any — lets the score
    reflect real relationships between pain locations reported together,
    not just this one point in isolation."""
    contributions: List[Dict[str, Any]] = []
    severity_c = round((data.severity / 10.0) * 0.50, 2)
    contributions.append({"factor": f"Severity {data.severity}/10", "shap": severity_c, "impact": "+" if severity_c >= 0 else "-"})
    region_c = _region_weight(data.body_region)
    contributions.append({"factor": f"Region: {data.body_region}", "shap": region_c, "impact": "+" if region_c >= 0 else "-"})
    pain_c = _pain_type_weight(data.pain_type)
    contributions.append({"factor": f"Pain type: {data.pain_type}", "shap": pain_c, "impact": "+" if pain_c >= 0 else "-"})
    hr_c = _heart_rate_contribution(data.heart_rate)
    if hr_c:
        contributions.append({"factor": f"Heart rate {data.heart_rate} bpm", "shap": hr_c, "impact": "+" if hr_c >= 0 else "-"})
    if sibling_regions:
        contributions.extend(_connectivity_contributions(data.body_region, sibling_regions))
    bmi_c, bmi = _bmi_contribution(patient_weight, patient_height)
    if bmi_c:
        contributions.append({"factor": f"BMI {bmi:.1f} (weight/height)", "shap": bmi_c, "impact": "+" if bmi_c >= 0 else "-"})
    raw = round(sum(c["shap"] for c in contributions), 2)
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
        contributions.append({
            "factor": f"Score capped at 1.00 (findings summed to {raw:.2f})",
            "shap": round(risk - raw, 2),
            "impact": "-",
        })
    contributions.sort(key=lambda c: c["shap"], reverse=True)
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
    region = (getattr(source, "body_region", None) or "").strip().lower()
    pain_type = (getattr(source, "pain_type", None) or "").strip().lower()
    direction = (getattr(source, "direction", None) or "").strip().lower()
    severity = getattr(source, "severity", None) or 0
    heart_rate = getattr(source, "heart_rate", None)

    is_chest = "chest" in region or "heart" in region
    is_head = "head" in region or "cranial" in region

    # (level, code, detail) - collected first, ranked afterwards.
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
        if rate > 120 or rate < 50:
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

