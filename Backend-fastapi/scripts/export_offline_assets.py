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
records what `triage_service.compute_risk` / `escalation_for` / `triage_tier` and
`anatomy_retriever.retrieve` answer today, plus the raw output of the lexical
normalisation (`lexical_vectors`) that decides which words a query is made of.
The Dart ports are tested against these, so a transcription slip in either
engine fails the test suite instead of quietly giving a patient a different
score than the practitioner's server.

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
from scripts.eval_retrieval import load_cases

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
        "bmi": {"obese_at": 30.0, "underweight_below": 18.5, "bump": 0.05},
        "severity": {"max": 10, "weight": 0.50},
        "bands": {"high": 0.7, "medium": 0.4},
        "concern_bumps": CONCERN_RISK_BUMP,
        # The triage tier's own numbers, exported rather than hardcoded in Dart:
        # a category the device can disagree with the server about is worse than no
        # category, and the sensitivity analysis has to move these, not the code.
        "tiers": {
            "scale": triage_service.TRIAGE_SCALE,
            "order": list(triage_service.TIERS),
            "categories": dict(triage_service.TIER_CATEGORIES),
            "orange_score_min": triage_service.TIER_ORANGE_SCORE_MIN,
            "yellow_score_min": triage_service.TIER_YELLOW_SCORE_MIN,
            # Codes, so `decided_by` is byte-identical on both platforms and a
            # client can localise the reason without parsing English.
            "rule_codes": {
                "score_concerning_region": triage_service.TIER_RULE_SCORE_CONCERNING_REGION,
                "score_urgent_band": triage_service.TIER_RULE_SCORE_URGENT_BAND,
                "score_below_urgent_band": triage_service.TIER_RULE_SCORE_BELOW_URGENT_BAND,
                "heart_rate_critical": "heart_rate_critical",
            },
        },
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
            "patient_weight": weight,
            "patient_height": height,
            "siblings": siblings,
        },
        "expected": {
            "risk": risk,
            "level": triage_service.risk_level(risk),
            "contributions": contributions,
            "escalation": triage_service.escalation_for(payload),
            "tier": triage_service.triage_tier(payload, risk),
        },
    }


def _build_risk_cases() -> List[Dict[str, Any]]:
    cases: List[Dict[str, Any]] = []

    # Tier anchors, paired either side of each threshold. Every weight here is a
    # multiple of 0.05, so these combinations land exactly on 0.40 and 0.70, which
    # is where an inclusive/exclusive slip between the two engines would hide.
    # Each pair also shows what the tier is for: a red flag reads a category the
    # score band cannot.
    for region, pain_type, severity, heart_rate in [
        ("Left Leg", "Dull", 4, None),    # 0.35 -> green
        ("Left Leg", "Dull", 5, None),    # 0.40 -> yellow, on the boundary
        ("Left Leg", "Dull", 6, None),    # 0.45 -> yellow
        ("Headache / Cranial", "Dull", 5, None),  # 0.65 -> yellow
        ("Headache / Cranial", "Dull", 6, None),  # 0.70 -> orange, boundary + concern
        ("Left Leg", "Dull", 1, 45.0),    # 0.35 band, red on the rate alone
        ("Left Leg", "Dull", 10, None),   # 0.65 band, orange on pain_maximum
        ("Chest / Heart", "Crushing", 1, None),  # 0.65 band, red on the finding
    ]:
        cases.append(
            _risk_case(
                region=region,
                pain_type=pain_type,
                severity=severity,
                heart_rate=heart_rate,
            )
        )

    # Heart-rate floor boundaries: the rate decides a category on its own, so the
    # exact threshold matters more here than anywhere in the score.
    for heart_rate in (49.0, 50.0, 51.0, 119.0, 120.0, 121.0, 0.0, None):
        cases.append(_risk_case(region="Left Leg", heart_rate=heart_rate))

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
                weight=weight,
                height=height,
                siblings=siblings,
            )
        )

    return cases


ANATOMY_QUERIES = [
    ("Chest / Heart", "crushing chest pain spreading to left arm"),
    # p5: the tap and the sentence disagree about the side. These two pin that the
    # offline engine reconciles them the same way the server does - the stated side
    # governs, the tapped side's monograph disappears - and that a sentence naming
    # both sides leaves the tap in charge.
    ("Right Arm / Shoulder", "pain in my left arm and jaw"),
    ("Right Arm / Shoulder", "pain in my left and right arm"),
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
    # Minimum-evidence abstentions (P0-6). These complaints name nothing the
    # knowledge base is about, so the retriever keeps nothing and the endpoint
    # declines to answer. Recorded here so the offline engine is checked to abstain
    # on the *same* complaints - empty results, not just matching scores - rather
    # than quietly serving the closest accidental word overlap like it used to.
    ("", "how many days of antibiotics for a sinus infection"),
    ("", "anxious and cannot sleep at night"),
    ("", "ear itches and drains fluid"),
    ("", "refill my blood pressure prescription"),
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
                    # Recorded, not recomputed in Dart: the offline engine has to say
                    # the same thing about a side the narrative took over, and a
                    # hand-copied sentence in a test drifts the first time someone
                    # reworded the server.
                    "laterality_note": anatomy_retriever.laterality_note(region, query),
                    "expected": [
                        {"id": hit.chunk.id, "score": hit.score} for hit in hits
                    ],
                }
            )
    return cases


# Words the lexical vectors probe beyond the corpus itself. A stem that only ever
# fires on a word nobody indexes is a stem the parity test would never see drift.
_LEXICAL_EXTRA_WORDS = [
    "heels", "flanks", "spasms", "colics", "rashes", "nausea", "fever",
    "vomits", "throats", "lungs", "ribs", "wrists", "elbows", "hips",
    "shoulders", "neck", "heart", "stress", "gas", "axis", "corpus",
    "diabetes", "ulnar", "patellar", "ovarian", "sciatica", "menisci",
    "phalanges", "abscess", "abscesses", "feet", "teeth", "calves",
]


def _eval_query_texts() -> List[str]:
    """Every complaint the quality gate judges, as a parity probe too.

    The golden anatomy cases are a handful of hand-picked region/query pairs; the
    eval fixture is 63 phrasings chosen precisely because they are hard - jargon,
    lay words, referred pain. Those are the strings most likely to expose a
    missing synonym edge or an over-eager collapse, so the Dart tokenizer is
    checked against all of them, not only against the ones that happen to score.
    """
    return [case.query for case in load_cases()]


def _build_lexical_vectors(queries: List[str]) -> Dict[str, Any]:
    """The two new mechanisms on their own, so parity does not depend on scores.

    30 anatomy cases replaying to 1e-6 proves the ranking agrees *today*. It does
    not prove the Dart port collapses the same inflections or expands the same
    synonyms - a drifted stem or an edge present in only one engine can hide
    behind a well-matched monograph and surface on the next query that nobody
    thought to vector. These are the raw functions, asserted directly.
    """
    probe = set(anatomy_retriever._raw_corpus_terms())
    probe.update(_LEXICAL_EXTRA_WORDS)
    for text in [region for region, _ in ANATOMY_QUERIES] + queries:
        probe.update(anatomy_retriever._surface_tokens(text))

    return {
        "canonical_form": [
            {"word": word, "canonical": anatomy_retriever.canonical_form(word)}
            for word in sorted(probe)
        ],
        "expansion": {
            key: list(targets)
            for key, targets in sorted(anatomy_retriever._synonym_table().items())
        },
        "query_tokens": [
            {
                "query": text,
                "tokens": anatomy_retriever._tokenize(text),
            }
            for text in sorted(set(queries))
            if text
        ],
    }


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
        "lexical_vectors": _build_lexical_vectors(
            [query for _, query in ANATOMY_QUERIES] + _eval_query_texts()
        ),
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
        f"{len(golden['anatomy_cases'])} anatomy cases, "
        f"{len(golden['lexical_vectors']['canonical_form'])} lexical probes."
    )


if __name__ == "__main__":
    run()
