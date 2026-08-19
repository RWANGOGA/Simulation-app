import json
from typing import Any, Dict, List, Optional, Tuple
from app.schemas import TriageCreate

REGION_WEIGHTS: Dict[str, float] = {
    "Chest": 0.40, "Head": 0.35, "Abdomen": 0.25,
    "Left Arm": 0.20, "Right Arm": 0.15,
    "Left Leg": 0.10, "Right Leg": 0.10
}
PAIN_TYPE_WEIGHTS: Dict[str, float] = {
    "crushing": 0.20, "stabbing": 0.15, "sharp": 0.12,
    "burning": 0.10, "throbbing": 0.08, "numb": 0.08, "dull": 0.05
}

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
    region_c = REGION_WEIGHTS.get(data.body_region, 0.10)
    contributions.append({"factor": f"Region: {data.body_region}", "shap": region_c})
    pain_c = PAIN_TYPE_WEIGHTS.get(data.pain_type, 0.05)
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
