import json
from typing import Any, Dict, List, Optional, Tuple
from app.schemas import TriageCreate

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
# client's title-case labels ("Sharp", "Cramping") still match. "cramping"
# was previously missing entirely and fell to the 0.05 default.
PAIN_TYPE_WEIGHTS: Dict[str, float] = {
    "crushing": 0.20, "stabbing": 0.15, "sharp": 0.12,
    "burning": 0.10, "cramping": 0.09, "throbbing": 0.08, "numb": 0.08,
    "dull": 0.05
}

def _region_weight(body_region: Optional[str]) -> float:
    """
    Match the region by clinical keyword instead of an exact string.
    The app sends labels like "Chest / Heart" or "Abdomen (Upper)", which
    never matched the old exact keys, so every region silently fell back to
    the 0.10 default. Keyword matching also tolerates future label tweaks.
    """
    r = (body_region or "").lower()
    if "chest" in r or "heart" in r:
        return 0.40
    if "head" in r or "cranial" in r:
        return 0.35
    if "abdomen" in r or "stomach" in r:
        return 0.25
    if "back" in r:
        return 0.20
    if "arm" in r or "shoulder" in r:
        return 0.20 if "left" in r else 0.15
    if "leg" in r or "knee" in r:
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

def compute_risk(data: TriageCreate) -> Tuple[float, List[Dict[str, Any]]]:
    contributions: List[Dict[str, Any]] = []
    severity_c = round((data.severity / 10.0) * 0.50, 2)
    contributions.append({"factor": f"Severity {data.severity}/10", "shap": severity_c})
    region_c = _region_weight(data.body_region)
    contributions.append({"factor": f"Region: {data.body_region}", "shap": region_c})
    pain_c = _pain_type_weight(data.pain_type)
    contributions.append({"factor": f"Pain type: {data.pain_type}", "shap": pain_c})
    hr_c = _heart_rate_contribution(data.heart_rate)
    if hr_c:
        contributions.append({"factor": f"Heart rate {data.heart_rate} bpm", "shap": hr_c})
    risk = min(1.0, round(sum(c["shap"] for c in contributions), 2))
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
