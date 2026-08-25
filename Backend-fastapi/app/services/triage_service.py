import json
from typing import Any, Dict, List, Optional, Tuple
from app.schemas import TriageCreate
from app.data.body_graph import find_connection, CONCERN_RISK_BUMP

# Keys match the exact region labels BodyMapScreen actually sends (see
# lib/features/body_map/ui/body_map_screen.dart's region list) — these
# used to be short generic labels ("Chest", "Head") that never matched
# what the app really sends, so every submission silently fell back to
# the 0.10 default below regardless of where the patient tapped.
REGION_WEIGHTS: Dict[str, float] = {
    "Chest / Heart": 0.40,
    "Headache / Cranial": 0.35,
    "Abdomen (Upper)": 0.25,
    "Abdomen (Lower Right)": 0.25,
    "Abdomen (Lower Left)": 0.25,
    "Back Pain (Upper)": 0.20,
    "Back Pain (Lower)": 0.18,
    "Left Arm / Shoulder": 0.20,
    "Right Arm / Shoulder": 0.15,
    "Left Leg / Knee": 0.10,
    "Right Leg / Knee": 0.10,
}

# Same fix: the app sends capitalized labels ("Sharp", "Cramping"), not
# lowercase ("sharp") — and "Cramping" wasn't in this table in any case.
PAIN_TYPE_WEIGHTS: Dict[str, float] = {
    "Crushing": 0.20, "Stabbing": 0.15, "Sharp": 0.12,
    "Burning": 0.10, "Throbbing": 0.08, "Numb": 0.08,
    "Dull": 0.05, "Cramping": 0.10,
}


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


def compute_risk(data: TriageCreate, sibling_regions: Optional[List[str]] = None) -> Tuple[float, List[Dict[str, Any]]]:
    """sibling_regions: the body_region of every other pain point already
    submitted in this same visit (same visit_id), if any — lets the score
    reflect real relationships between pain locations reported together,
    not just this one point in isolation."""
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
    if sibling_regions:
        contributions.extend(_connectivity_contributions(data.body_region, sibling_regions))
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
