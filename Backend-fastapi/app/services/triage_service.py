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

def _spo2_contribution(spo2: Optional[float]) -> float:
    """Low blood-oxygen estimates raise the triage priority."""
    if spo2 is None or spo2 <= 0:
        return 0.0
    if spo2 < 92:
        return 0.15
    if spo2 < 95:
        return 0.10
    return 0.0

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
    patient_weight: Optional[float] = None,
    patient_height: Optional[float] = None,
) -> Tuple[float, List[Dict[str, Any]]]:
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
    spo2_c = _spo2_contribution(data.spo2)
    if spo2_c:
        contributions.append({"factor": f"SpO2 {data.spo2}%", "shap": spo2_c, "impact": "+" if spo2_c >= 0 else "-"})
    bmi_c, bmi = _bmi_contribution(patient_weight, patient_height)
    if bmi_c:
        contributions.append({"factor": f"BMI {bmi:.1f} (weight/height)", "shap": bmi_c, "impact": "+" if bmi_c >= 0 else "-"})
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
