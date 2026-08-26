"""
A hand-built anatomical connectivity graph for the body regions the app
actually lets a patient select (see BodyMapScreen's region list). This is
the simple, explicit stand-in for the "spatial graph" concept described in
the project's design docs — real medical referred-pain relationships,
represented as data instead of a trained model, so the risk engine can
reason about *combinations* of pain locations reported in the same visit
instead of scoring each one in total isolation.

Each entry:
  system      - which body system the region belongs to
  connects_to - other regions this one is anatomically/clinically linked to,
                each with a short plain-language note and a concern level
                ("high" / "moderate" / "low") used to scale the risk bump
                when BOTH regions are reported in the same visit.

This is a starting draft based on well-established, textbook referred-pain
patterns (e.g. cardiac pain radiating to the left arm, gallbladder pain
referring to the right shoulder, appendicitis migrating from the upper/
mid abdomen to the lower right). It is not a substitute for clinical
review — treat the concern levels and notes as a first pass to be checked
by someone with real medical knowledge before this is relied on for
anything beyond a course demo.
"""

from typing import Dict, List, TypedDict


class Connection(TypedDict):
    region: str
    note: str
    concern: str  # "high" | "moderate" | "low"


class BodyNode(TypedDict):
    system: str
    connects_to: List[Connection]


BODY_GRAPH: Dict[str, BodyNode] = {
    "Chest / Heart": {
        "system": "cardiovascular",
        "connects_to": [
            {
                "region": "Left Arm / Shoulder",
                "note": "Chest pain spreading to the left arm is a classic warning sign of a heart problem.",
                "concern": "high",
            },
            {
                "region": "Back Pain (Upper)",
                "note": "Chest pain radiating to the upper back can indicate a cardiac or aortic problem.",
                "concern": "high",
            },
            {
                "region": "Abdomen (Upper)",
                "note": "Upper abdominal pain can sometimes actually be heart-related, not digestive.",
                "concern": "moderate",
            },
        ],
    },
    "Abdomen (Upper)": {
        "system": "digestive",
        "connects_to": [
            {
                "region": "Right Arm / Shoulder",
                "note": "Upper abdominal pain referring to the right shoulder is a classic gallbladder sign.",
                "concern": "moderate",
            },
            {
                "region": "Chest / Heart",
                "note": "Upper abdominal pain can sometimes actually be heart-related, not digestive.",
                "concern": "moderate",
            },
            {
                "region": "Back Pain (Upper)",
                "note": "Upper abdominal pain radiating straight through to the back can indicate the pancreas.",
                "concern": "moderate",
            },
            {
                "region": "Abdomen (Lower Right)",
                "note": "Pain that started here and is moving to the lower right abdomen follows the classic early-appendicitis pattern.",
                "concern": "high",
            },
        ],
    },
    "Abdomen (Lower Right)": {
        "system": "digestive",
        "connects_to": [
            {
                "region": "Abdomen (Upper)",
                "note": "Pain that started near the upper/mid abdomen and moved here follows the classic early-appendicitis pattern.",
                "concern": "high",
            },
            {
                "region": "Right Leg / Knee",
                "note": "Lower right abdominal pain with right leg discomfort can indicate irritation near the appendix.",
                "concern": "low",
            },
        ],
    },
    "Abdomen (Lower Left)": {
        "system": "digestive",
        "connects_to": [
            {
                "region": "Back Pain (Lower)",
                "note": "Lower abdominal pain together with lower back pain can point to a kidney issue.",
                "concern": "moderate",
            },
        ],
    },
    "Headache / Cranial": {
        "system": "nervous",
        "connects_to": [
            {
                "region": "Back Pain (Upper)",
                "note": "Headache together with upper back/neck pain is common with tension-type headaches.",
                "concern": "low",
            },
        ],
    },
    "Back Pain (Upper)": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Chest / Heart",
                "note": "Upper back pain together with chest pain can indicate a cardiac or aortic problem.",
                "concern": "high",
            },
            {
                "region": "Headache / Cranial",
                "note": "Upper back/neck pain together with headache is common with tension-type headaches.",
                "concern": "low",
            },
        ],
    },
    "Back Pain (Lower)": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Right Leg / Knee",
                "note": "Lower back pain radiating down the right leg is the classic pattern of sciatica.",
                "concern": "low",
            },
            {
                "region": "Left Leg / Knee",
                "note": "Lower back pain radiating down the left leg is the classic pattern of sciatica.",
                "concern": "low",
            },
            {
                "region": "Abdomen (Lower Left)",
                "note": "Lower back pain together with lower abdominal pain can point to a kidney issue.",
                "concern": "moderate",
            },
        ],
    },
    "Right Arm / Shoulder": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Abdomen (Upper)",
                "note": "Right shoulder pain together with upper abdominal pain is a classic gallbladder sign.",
                "concern": "moderate",
            },
        ],
    },
    "Left Arm / Shoulder": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Chest / Heart",
                "note": "Left arm pain together with chest pain is a classic warning sign of a heart problem.",
                "concern": "high",
            },
        ],
    },
    "Right Leg / Knee": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Back Pain (Lower)",
                "note": "Right leg pain radiating from the lower back is the classic pattern of sciatica.",
                "concern": "low",
            },
            {
                "region": "Abdomen (Lower Right)",
                "note": "Right leg discomfort with lower right abdominal pain can indicate irritation near the appendix.",
                "concern": "low",
            },
        ],
    },
    "Left Leg / Knee": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Back Pain (Lower)",
                "note": "Left leg pain radiating from the lower back is the classic pattern of sciatica.",
                "concern": "low",
            },
        ],
    },
}

CONCERN_RISK_BUMP: Dict[str, float] = {
    "high": 0.25,
    "moderate": 0.12,
    "low": 0.05,
}


def get_node(region: str) -> BodyNode | None:
    return BODY_GRAPH.get(region)


def find_connection(region_a: str, region_b: str) -> Connection | None:
    """Returns the connection info from region_a's perspective if region_b
    is one of its linked regions, else None. The graph is written with
    each relationship listed on both sides, so callers only need to check
    one direction."""
    node = BODY_GRAPH.get(region_a)
    if node is None:
        return None
    for conn in node["connects_to"]:
        if conn["region"] == region_b:
            return conn
    return None
