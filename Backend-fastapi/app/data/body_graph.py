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
    "Headache / Cranial": {
        "system": "neurological",
        "connects_to": [
            {
                "region": "Back Pain (Upper)",
                "note": "Headache together with upper back/neck pain is common with tension-type headaches.",
                "concern": "low",
            },
            {
                "region": "Neck",
                "note": "Severe headache accompanied by neck stiffness is a warning sign of meningeal irritation.",
                "concern": "moderate",
            },
        ],
    },
    "Neck": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Headache / Cranial",
                "note": "Neck pain accompanied by severe headache can indicate meningeal irritation or tension headache.",
                "concern": "moderate",
            },
            {
                "region": "Back Pain (Upper)",
                "note": "Neck pain radiating into the upper back is common with cervical spine strains or spondylosis.",
                "concern": "low",
            },
            {
                "region": "Chest / Heart",
                "note": "Neck pain occurring alongside chest discomfort can be a warning sign of cardiac ischemia.",
                "concern": "high",
            },
            {
                "region": "Left Shoulder",
                "note": "Neck pain radiating down the left shoulder can indicate cervical nerve compression or referred cardiac pain.",
                "concern": "moderate",
            },
            {
                "region": "Left Arm / Shoulder",
                "note": "Neck pain radiating to left shoulder and arm can indicate cervical radiculopathy or cardiac distress.",
                "concern": "moderate",
            },
            {
                "region": "Right Shoulder",
                "note": "Neck pain radiating to right shoulder suggests cervical spine strain or nerve root irritation.",
                "concern": "low",
            },
            {
                "region": "Right Arm / Shoulder",
                "note": "Neck pain radiating down right arm suggests cervical nerve root compression.",
                "concern": "low",
            },
        ],
    },
    "Chest / Heart": {
        "system": "cardiovascular",
        "connects_to": [
            {
                "region": "Left Arm / Shoulder",
                "note": "Chest pain spreading to the left arm is a classic warning sign of a heart problem.",
                "concern": "high",
            },
            {
                "region": "Left Shoulder",
                "note": "Chest pain radiating to the left shoulder is a classic warning sign of cardiac ischemia.",
                "concern": "high",
            },
            {
                "region": "Left Hand",
                "note": "Chest pain with tingling or discomfort extending into the left hand can indicate severe cardiac radiation.",
                "concern": "high",
            },
            {
                "region": "Neck",
                "note": "Chest pain radiating upward to the neck or jaw is a key warning sign of a cardiac event.",
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
            {
                "region": "Left Armpit",
                "note": "Chest pain radiating toward the left axilla can indicate wall or cardiac involvement.",
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
                "region": "Right Shoulder",
                "note": "Upper abdominal pain referring up to the right shoulder is a classic sign of gallbladder or phrenic nerve irritation.",
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
            {
                "region": "Right Thigh",
                "note": "Lower right abdominal pain radiating down anterior right thigh suggests psoas or retroperitoneal irritation.",
                "concern": "low",
            },
            {
                "region": "Hips / Groin",
                "note": "Lower right abdominal pain extending into the right groin or hip can indicate appendicitis or iliopsoas inflammation.",
                "concern": "moderate",
            },
        ],
    },
    "Abdomen (Lower Left)": {
        "system": "digestive",
        "connects_to": [
            {
                "region": "Back Pain (Lower)",
                "note": "Lower abdominal pain together with lower back pain can point to a kidney issue or diverticulitis.",
                "concern": "moderate",
            },
            {
                "region": "Hips / Groin",
                "note": "Lower left abdominal pain referring to the left groin can indicate renal calculus or diverticular involvement.",
                "concern": "moderate",
            },
        ],
    },
    "Hips / Groin": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Back Pain (Lower)",
                "note": "Groin and hip pain together with lower back pain commonly indicates lumbar radiculopathy, sacroiliac dysfunction, or renal colic.",
                "concern": "moderate",
            },
            {
                "region": "Abdomen (Lower Left)",
                "note": "Groin pain with lower left abdominal pain can indicate kidney stone passage or diverticular inflammation.",
                "concern": "moderate",
            },
            {
                "region": "Abdomen (Lower Right)",
                "note": "Groin pain with lower right abdominal pain can indicate appendicitis or psoas irritation.",
                "concern": "moderate",
            },
            {
                "region": "Right Thigh",
                "note": "Groin pain radiating down anterior right thigh suggests hip pathology or obturator nerve irritation.",
                "concern": "low",
            },
            {
                "region": "Left Thigh",
                "note": "Groin pain radiating down anterior left thigh suggests hip joint pathology or femoral nerve irritation.",
                "concern": "low",
            },
            {
                "region": "Thighs",
                "note": "Groin pain extending into the thighs is characteristic of hip osteoarthrosis or pelvic girdle strain.",
                "concern": "low",
            },
        ],
    },
    "Thighs": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Back Pain (Lower)",
                "note": "Thigh discomfort associated with lower back pain suggests upper lumbar radiculopathy.",
                "concern": "low",
            },
            {
                "region": "Hips / Groin",
                "note": "Thigh pain with hip or groin discomfort often originates from hip joint pathology.",
                "concern": "low",
            },
            {
                "region": "Right Knee",
                "note": "Thigh pain extending to the knee is common with quadriceps strain or patellofemoral tracking.",
                "concern": "low",
            },
            {
                "region": "Left Knee",
                "note": "Thigh pain extending to the knee is common with quadriceps strain or patellofemoral tracking.",
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
            {
                "region": "Neck",
                "note": "Upper back pain extending up into the neck is frequent in cervical spine strains.",
                "concern": "low",
            },
            {
                "region": "Abdomen (Upper)",
                "note": "Upper back pain corresponding to upper abdominal symptoms can point to pancreatic inflammation.",
                "concern": "moderate",
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
                "region": "Right Shin / Calf",
                "note": "Lower back pain radiating down past the knee to the right calf indicates lower lumbar nerve root irritation.",
                "concern": "low",
            },
            {
                "region": "Left Shin / Calf",
                "note": "Lower back pain radiating down past the knee to the left calf indicates lower lumbar nerve root irritation.",
                "concern": "low",
            },
            {
                "region": "Abdomen (Lower Left)",
                "note": "Lower back pain together with lower abdominal pain can point to a kidney issue.",
                "concern": "moderate",
            },
            {
                "region": "Hips / Groin",
                "note": "Lower back pain radiating into hips or groin is common in lumbar radiculopathy and sacroiliac joint strain.",
                "concern": "moderate",
            },
            {
                "region": "Thighs",
                "note": "Lower back pain with bilateral thigh ache indicates upper lumbar spine involvement.",
                "concern": "low",
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
            {
                "region": "Neck",
                "note": "Right arm and shoulder discomfort with neck pain suggests cervical nerve root compression.",
                "concern": "low",
            },
            {
                "region": "Right Shoulder",
                "note": "Direct overlap with right shoulder girdle.",
                "concern": "low",
            },
            {
                "region": "Right Elbow",
                "note": "Discomfort extending down the right arm to the elbow indicates tendonitis or brachial chain pain.",
                "concern": "low",
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
            {
                "region": "Neck",
                "note": "Left arm/shoulder pain with neck symptoms suggests cervical radiculopathy or cardiac radiation.",
                "concern": "moderate",
            },
            {
                "region": "Left Shoulder",
                "note": "Direct overlap with left shoulder girdle.",
                "concern": "low",
            },
            {
                "region": "Left Elbow",
                "note": "Left arm pain extending down to the elbow.",
                "concern": "low",
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
            {
                "region": "Right Shin / Calf",
                "note": "Right leg pain extending below the knee into the calf.",
                "concern": "low",
            },
            {
                "region": "Right Knee",
                "note": "Direct overlap with right knee joint.",
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
            {
                "region": "Left Shin / Calf",
                "note": "Left leg pain extending below the knee into the calf.",
                "concern": "low",
            },
            {
                "region": "Left Knee",
                "note": "Direct overlap with left knee joint.",
                "concern": "low",
            },
        ],
    },
    "Right Shoulder": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Abdomen (Upper)",
                "note": "Right shoulder pain with upper abdominal symptoms is a classic referred pain pattern for gallbladder disease.",
                "concern": "moderate",
            },
            {
                "region": "Neck",
                "note": "Right shoulder pain with neck stiffness suggests cervical spine strain or nerve compression.",
                "concern": "low",
            },
            {
                "region": "Right Arm / Shoulder",
                "note": "Direct alignment with right upper extremity.",
                "concern": "low",
            },
            {
                "region": "Right Armpit",
                "note": "Right shoulder pain spreading into the right armpit indicates rotator cuff or axillary lymph node tension.",
                "concern": "low",
            },
        ],
    },
    "Left Shoulder": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Chest / Heart",
                "note": "Left shoulder pain combined with chest discomfort is a critical warning sign of cardiac ischemia.",
                "concern": "high",
            },
            {
                "region": "Neck",
                "note": "Left shoulder pain with neck pain can indicate cervical nerve compression or cardiac radiation.",
                "concern": "moderate",
            },
            {
                "region": "Left Arm / Shoulder",
                "note": "Direct alignment with left upper extremity.",
                "concern": "low",
            },
            {
                "region": "Left Armpit",
                "note": "Left shoulder pain extending to the axilla can indicate muscular strain or referred wall pain.",
                "concern": "low",
            },
        ],
    },
    "Right Armpit": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Right Shoulder",
                "note": "Right axillary discomfort with shoulder pain suggests rotator cuff strain or axillary lymphadenitis.",
                "concern": "low",
            },
            {
                "region": "Right Elbow",
                "note": "Discomfort extending down the medial right arm from axilla to elbow.",
                "concern": "low",
            },
        ],
    },
    "Left Armpit": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Chest / Heart",
                "note": "Left axillary pain accompanying chest discomfort can be a radiating sign of cardiac distress.",
                "concern": "moderate",
            },
            {
                "region": "Left Shoulder",
                "note": "Left armpit discomfort with shoulder symptoms suggests rotator cuff or chest wall strain.",
                "concern": "low",
            },
            {
                "region": "Left Elbow",
                "note": "Discomfort extending down the medial left arm from axilla to elbow.",
                "concern": "low",
            },
        ],
    },
    "Right Elbow": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Right Arm / Shoulder",
                "note": "Elbow pain extending up the arm to the shoulder.",
                "concern": "low",
            },
            {
                "region": "Right Armpit",
                "note": "Inner elbow pain radiating up to the axilla along ulnar nerve track.",
                "concern": "low",
            },
            {
                "region": "Right Wrist",
                "note": "Right elbow pain radiating down the forearm to the wrist is typical of epicondylitis.",
                "concern": "low",
            },
        ],
    },
    "Left Elbow": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Left Arm / Shoulder",
                "note": "Elbow pain extending up the arm to the shoulder.",
                "concern": "low",
            },
            {
                "region": "Left Armpit",
                "note": "Inner elbow pain radiating up to the axilla along ulnar nerve track.",
                "concern": "low",
            },
            {
                "region": "Left Wrist",
                "note": "Left elbow pain radiating down forearm to the wrist is typical of epicondylitis.",
                "concern": "low",
            },
        ],
    },
    "Right Wrist": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Right Elbow",
                "note": "Wrist pain radiating up the forearm to the elbow.",
                "concern": "low",
            },
            {
                "region": "Right Hand",
                "note": "Wrist pain extending into the fingers is characteristic of carpal tunnel syndrome.",
                "concern": "low",
            },
        ],
    },
    "Left Wrist": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Left Elbow",
                "note": "Wrist pain radiating up the forearm to the elbow.",
                "concern": "low",
            },
            {
                "region": "Left Hand",
                "note": "Wrist pain extending into the fingers is characteristic of carpal tunnel syndrome.",
                "concern": "low",
            },
        ],
    },
    "Right Hand": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Right Wrist",
                "note": "Hand pain associated with wrist discomfort indicates carpal tunnel or flexor tendinitis.",
                "concern": "low",
            },
        ],
    },
    "Left Hand": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Chest / Heart",
                "note": "Numbness or pain spreading into the left hand alongside chest pain can indicate severe cardiac radiation.",
                "concern": "high",
            },
            {
                "region": "Left Wrist",
                "note": "Hand pain associated with wrist discomfort indicates carpal tunnel syndrome.",
                "concern": "low",
            },
        ],
    },
    "Right Thigh": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Hips / Groin",
                "note": "Anterior thigh pain with groin discomfort suggests hip joint involvement or femoral neuropathy.",
                "concern": "low",
            },
            {
                "region": "Abdomen (Lower Right)",
                "note": "Right thigh discomfort with lower right abdominal pain suggests retroperitoneal or psoas irritation.",
                "concern": "low",
            },
            {
                "region": "Right Knee",
                "note": "Thigh pain extending down to the right knee.",
                "concern": "low",
            },
        ],
    },
    "Left Thigh": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Hips / Groin",
                "note": "Anterior left thigh pain with groin discomfort suggests hip joint pathology.",
                "concern": "low",
            },
            {
                "region": "Left Knee",
                "note": "Thigh pain extending down to the left knee.",
                "concern": "low",
            },
        ],
    },
    "Right Knee": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Right Thigh",
                "note": "Knee pain extending up the thigh.",
                "concern": "low",
            },
            {
                "region": "Right Leg / Knee",
                "note": "Direct alignment with right knee region.",
                "concern": "low",
            },
            {
                "region": "Right Shin / Calf",
                "note": "Knee discomfort radiating down into the calf.",
                "concern": "low",
            },
            {
                "region": "Thighs",
                "note": "Knee pain associated with general thigh muscle fatigue.",
                "concern": "low",
            },
        ],
    },
    "Left Knee": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Left Thigh",
                "note": "Knee pain extending up the thigh.",
                "concern": "low",
            },
            {
                "region": "Left Leg / Knee",
                "note": "Direct alignment with left knee region.",
                "concern": "low",
            },
            {
                "region": "Left Shin / Calf",
                "note": "Knee discomfort radiating down into the calf.",
                "concern": "low",
            },
            {
                "region": "Thighs",
                "note": "Knee pain associated with general thigh muscle fatigue.",
                "concern": "low",
            },
        ],
    },
    "Right Shin / Calf": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Right Knee",
                "note": "Calf/shin pain extending up to the right knee joint.",
                "concern": "low",
            },
            {
                "region": "Right Leg / Knee",
                "note": "Direct alignment with right lower leg.",
                "concern": "low",
            },
            {
                "region": "Right Ankle",
                "note": "Calf pain radiating down into the ankle or Achilles tendon.",
                "concern": "low",
            },
            {
                "region": "Back Pain (Lower)",
                "note": "Calf pain radiating from the lower back is characteristic of S1 nerve root sciatica.",
                "concern": "low",
            },
        ],
    },
    "Left Shin / Calf": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Left Knee",
                "note": "Calf/shin pain extending up to the left knee joint.",
                "concern": "low",
            },
            {
                "region": "Left Leg / Knee",
                "note": "Direct alignment with left lower leg.",
                "concern": "low",
            },
            {
                "region": "Left Ankle",
                "note": "Calf pain radiating down into the ankle or Achilles tendon.",
                "concern": "low",
            },
            {
                "region": "Back Pain (Lower)",
                "note": "Calf pain radiating from the lower back is characteristic of S1 nerve root sciatica.",
                "concern": "low",
            },
        ],
    },
    "Right Ankle": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Right Shin / Calf",
                "note": "Ankle pain extending up into the right shin or calf.",
                "concern": "low",
            },
            {
                "region": "Right Foot",
                "note": "Ankle pain spreading to the right foot.",
                "concern": "low",
            },
        ],
    },
    "Left Ankle": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Left Shin / Calf",
                "note": "Ankle pain extending up into the left shin or calf.",
                "concern": "low",
            },
            {
                "region": "Left Foot",
                "note": "Ankle pain spreading to the left foot.",
                "concern": "low",
            },
        ],
    },
    "Right Foot": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Right Ankle",
                "note": "Foot pain spreading up to the right ankle joint.",
                "concern": "low",
            },
        ],
    },
    "Left Foot": {
        "system": "musculoskeletal",
        "connects_to": [
            {
                "region": "Left Ankle",
                "note": "Foot pain spreading up to the left ankle joint.",
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
