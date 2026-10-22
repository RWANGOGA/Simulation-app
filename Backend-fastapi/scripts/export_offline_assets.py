"""
Exports everything the Flutter app needs to score a triage report and answer
anatomy questions with no server at all.

The Python services stay the single source of truth: this script reads them and
writes two kinds of artefact into the Flutter project.

``simtack/assets/clinical/`` — runtime data the app ships with:
    risk_rules.json     region keyword table, pain-type weights, escalation
                        constants, and the body-graph connections with the
                        concern bump each one carries.
    body_graph.json     region -> connections (notes and concern levels).
    anatomy_kb.json     a byte-identical copy of app/data/anatomy_kb.json.

``simtack/test/fixtures/clinical_golden.json`` — parity vectors. Every case
records what `triage_service.compute_risk` / `escalation_for` and
`anatomy_retriever.retrieve` answer today. The Dart ports are tested against
these, so a transcription slip in either engine fails the test suite instead of
quietly giving a patient a different score than the practitioner's server.

Run it whenever the clinical rules or the knowledge base change:

    venv/bin/python -m scripts.export_offline_assets
"""
import json
import random
import shutil
from pathlib import Path
from typing import Any, Dict, List

from app.data.body_graph import BODY_GRAPH, CONCERN_RISK_BUMP
from app.schemas import TriageCreate
from app.services import anatomy_retriever, triage_service

BACKEND_DIR = Path(__file__).resolve().parent.parent
APP_DIR = BACKEND_DIR.parent / "simtack"
ASSET_DIR = APP_DIR / "assets" / "clinical"
FIXTURE_PATH = APP_DIR / "test" / "fixtures" / "clinical_golden.json"

# Region labels the app actually sends. The scorer matches on keywords rather
# than exact keys, so the variants matter as much as the canonical ones.
UI_REGION_LABELS = [
    "Chest / Heart",
    "Headache / Cranial",
    "Abdomen (Upper)",
    "Abdomen (Lower)",
    "Back Pain (Upper)",
    "Back Pain (Lower)",
    "Neck",
    "Left Arm / Shoulder",
    "Right Arm / Shoulder",
    "Left Leg",
    "Right Leg",
    "Pelvis / Groin",
    "Hip",
    "Knee (Left)",
    "Knee (Right)",
    "Ankle / Foot",
    "Hand / Wrist",
    "Elbow",
    "Shoulder Blade",
    "Stomach",
    "Unmapped Region",
    "",
]

PAIN_TYPES = [
    "Crushing", "Stabbing", "Sharp", "Burning",
    "Cramping", "Throbbing", "Numb", "Dull",
    "Aching", "", "deep",
]

DIRECTIONS = [
    None,
    "Towards Back",
    "Radiating Down",
    "Radiating to left arm",
    "Spreading",
    "Stays Local",
]

HEART_RATES = [None, 45.0, 50.0, 55.0, 88.0, 100.0, 101.0, 120.0, 121.0, 150.0]
SPO2_VALUES = [None, 0.0, 88.0, 91.0, 92.0, 94.0, 95.0, 99.0]
WEIGHT_HEIGHT = [
    (None, None),
    (50.0, 160.0),   # BMI 19.5 — normal
    (100.0, 160.0),  # BMI 39.1 — obese
    (40.0, 180.0),   # BMI 12.3 — underweight
    (70.0, 0.0),     # invalid height, must not divide by zero
]


def _export_runtime_assets() -> Dict[str, Any]:
    ASSET_DIR.mkdir(parents=True, exist_ok=True)

    # The region matcher is an ordered keyword chain in Python. Transcribing it
    # as data keeps the Dart side a table lookup instead of a second if/elif
    # ladder that can drift.
    region_rules: List[Dict[str, Any]] = [
        {"keywords": ["chest", "heart"], "weight": 0.40},
        {"keywords": ["head", "cranial"], "weight": 0.35},
        {"keywords": ["neck"], "weight": 0.30},
        {"keywords": ["abdomen", "stomach"], "weight": 0.25},
        {"keywords": ["back"], "weight": 0.20},
        {
            "keywords": ["arm", "shoulder", "armpit", "elbow", "wrist", "hand"],
            "weight": 0.15,
            # The Python branch returns 0.20 instead when "left" appears.
            "left_weight": 0.20,
        },
        {
            "keywords": [
                "leg", "knee", "thigh", "shin", "calf", "ankle", "foot",
                "hip", "groin",
            ],
            "weight": 0.10,
        },
    ]

    rules = {
        "version": 1,
        "region_rules": region_rules,
        "default_region_weight": 0.10,
        "pain_type_weights": triage_service.PAIN_TYPE_WEIGHTS,
        "default_pain_type_weight": 0.05,
        "heart_rate": {
            "critical_above": 120.0,
            "critical_below": 50.0,
            "high_above": 100.0,
            "critical_bump": 0.15,
            "high_bump": 0.10,
        },
        "spo2": {"low_below": 92.0, "moderate_below": 95.0, "low_bump": 0.15, "moderate_bump": 0.10},
        "bmi": {"obese_at": 30.0, "underweight_below": 18.5, "bump": 0.05},
        "severity": {"max": 10, "weight": 0.50},
        "bands": {"high": 0.7, "medium": 0.4},
        "concern_bumps": CONCERN_RISK_BUMP,
        "escalation": {
            "emergency": triage_service.ESCALATION_EMERGENCY,
            "urgent": triage_service.ESCALATION_URGENT,
            "routine": triage_service.ESCALATION_ROUTINE,
            "action_by_level": triage_service._ACTION_BY_LEVEL,
            "concerning_chest_pain_types": list(
                triage_service._CONCERNING_CHEST_PAIN_TYPES
            ),
            "high_concern_region_keywords": list(
                triage_service._HIGH_CONCERN_REGION_KEYWORDS
            ),
        },
    }
    (ASSET_DIR / "risk_rules.json").write_text(
        json.dumps(rules, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    graph = {
        region: [
            {"region": c["region"], "note": c["note"], "concern": c["concern"]}
            for c in node["connects_to"]
        ]
        for region, node in BODY_GRAPH.items()
    }
    (ASSET_DIR / "body_graph.json").write_text(
        json.dumps(graph, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    # Byte-identical copy: the RAG stays the reference implementation, and the
    # app retrieves over exactly the same knowledge base.
    shutil.copyfile(
        BACKEND_DIR / "app" / "data" / "anatomy_kb.json",
        ASSET_DIR / "anatomy_kb.json",
    )

    return {"regions": len(graph), "connections": sum(len(v) for v in graph.values())}


def _risk_case(
    *,
    region: str,
    pain_type: str = "Sharp",
    severity: int = 5,
    direction: str | None = None,
    heart_rate: float | None = None,
    spo2: float | None = None,
    weight: float | None = None,
    height: float | None = None,
    siblings: List[str] | None = None,
) -> Dict[str, Any]:
    payload = TriageCreate(
        body_region=region,
        pain_type=pain_type,
        severity=severity,
        direction=direction,
        heart_rate=heart_rate,
        spo2=spo2,
    )
    siblings = siblings or []
    risk, contributions = triage_service.compute_risk(
        payload,
        sibling_regions=siblings,
        patient_weight=weight,
        patient_height=height,
    )
    return {
        "input": {
            "body_region": region,
            "pain_type": pain_type,
            "severity": severity,
            "direction": direction,
            "heart_rate": heart_rate,
            "spo2": spo2,
            "patient_weight": weight,
            "patient_height": height,
            "siblings": siblings,
        },
        "expected": {
            "risk": risk,
            "level": triage_service.risk_level(risk),
            "contributions": contributions,
            "escalation": triage_service.escalation_for(payload),
        },
    }


def _build_risk_cases() -> List[Dict[str, Any]]:
    cases: List[Dict[str, Any]] = []

    # Every region label, everything else held constant.
    for region in UI_REGION_LABELS + sorted(BODY_GRAPH):
        cases.append(_risk_case(region=region))

    # Every pain type in both cases the client sends.
    for pain_type in PAIN_TYPES:
        cases.append(_risk_case(region="Chest / Heart", pain_type=pain_type))
        cases.append(_risk_case(region="Left Leg", pain_type=pain_type))

    # Severity ladder, including the 10/10 escalation branch on both a
    # high-concern and an ordinary region.
    for severity in range(1, 11):
        for region in ["Chest / Heart", "Headache / Cranial", "Left Leg"]:
            cases.append(_risk_case(region=region, severity=severity, pain_type="Dull"))
            cases.append(
                _risk_case(region=region, severity=severity, pain_type="Crushing")
            )

    # Directions, including the radiating-chest rule.
    for direction in DIRECTIONS:
        cases.append(
            _risk_case(region="Chest / Heart", direction=direction, pain_type="Crushing")
        )

    # Vitals.
    for heart_rate in HEART_RATES:
        cases.append(_risk_case(region="Headache / Cranial", heart_rate=heart_rate))
    for spo2 in SPO2_VALUES:
        cases.append(_risk_case(region="Chest / Heart", spo2=spo2))
    for weight, height in WEIGHT_HEIGHT:
        cases.append(_risk_case(region="Abdomen (Upper)", weight=weight, height=height))

    # Connectivity: every real edge in the body graph, one case each.
    for region, node in BODY_GRAPH.items():
        for connection in node["connects_to"]:
            cases.append(
                _risk_case(region=region, siblings=[connection["region"]])
            )

    # A fixed sample of everything at once. Seeded so the fixture is stable.
    random.seed(20261023)
    regions = UI_REGION_LABELS + sorted(BODY_GRAPH)
    for _ in range(150):
        region = random.choice(regions)
        others = [r for r in regions if r != region]
        siblings = random.sample(others, k=random.choice([0, 0, 1, 2]))
        weight, height = random.choice(WEIGHT_HEIGHT)
        cases.append(
            _risk_case(
                region=region,
                pain_type=random.choice(PAIN_TYPES),
                severity=random.randint(1, 10),
                direction=random.choice(DIRECTIONS),
                heart_rate=random.choice(HEART_RATES),
                spo2=random.choice(SPO2_VALUES),
                weight=weight,
                height=height,
                siblings=siblings,
            )
        )

    return cases


ANATOMY_QUERIES = [
    ("Chest / Heart", "crushing chest pain spreading to left arm"),
    ("Chest / Heart", "chest pain"),
    ("", "chest pain"),
    ("Headache / Cranial", "severe headache with light sensitivity"),
    ("Abdomen (Upper)", "burning stomach pain after eating"),
    ("Back Pain (Lower)", "backache after lifting"),
    ("Left Arm / Shoulder", "shoulder pain when lifting the arm"),
    ("Right Leg", "calf pain when walking"),
    ("Neck", "stiff neck with arm tingling"),
    ("", "tummy ache"),
    ("", "breathless"),
    ("Pelvis / Groin", "groin pain on one side"),
    ("Knee (Left)", ""),
    ("", ""),
    ("Ankle / Foot", "sprained ankle swelling"),
]


def _build_anatomy_cases() -> List[Dict[str, Any]]:
    cases: List[Dict[str, Any]] = []
    for region, query in ANATOMY_QUERIES:
        for top_k in (3, 5):
            hits = anatomy_retriever.retrieve(region=region, query=query, top_k=top_k)
            cases.append(
                {
                    "region": region,
                    "query": query,
                    "top_k": top_k,
                    "expected": [
                        {"id": hit.chunk.id, "score": hit.score} for hit in hits
                    ],
                }
            )
    return cases


def run() -> None:
    summary = _export_runtime_assets()
    golden = {
        "generated_by": "scripts/export_offline_assets.py",
        "note": (
            "Records what the Python services answer today. The Dart ports in "
            "lib/core/clinical are tested against these vectors; regenerate "
            "with the script whenever the rules or the KB change."
        ),
        "risk_cases": _build_risk_cases(),
        "anatomy_cases": _build_anatomy_cases(),
    }
    FIXTURE_PATH.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE_PATH.write_text(
        json.dumps(golden, indent=2, sort_keys=True) + "\n", encoding="utf-8"
    )

    print(
        f"Wrote {ASSET_DIR.relative_to(BACKEND_DIR.parent)}: "
        f"{summary['regions']} regions, {summary['connections']} connections, KB copied."
    )
    print(
        f"Wrote {FIXTURE_PATH.relative_to(BACKEND_DIR.parent)}: "
        f"{len(golden['risk_cases'])} risk cases, "
        f"{len(golden['anatomy_cases'])} anatomy cases."
    )


if __name__ == "__main__":
    run()
