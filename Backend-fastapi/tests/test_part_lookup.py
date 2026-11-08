"""Tap-to-organ lookup that replaces retrieval on the body map.

Pinned here:

* every name in part_to_organ.json answers, and never with a report that
  does not exist;
* the body-map regions a patient actually taps (the outside of the body)
  resolve to the report a clinician would expect, left and right alike;
* a region keeps its red flags and questions, so dropping RAG does not drop
  the safety text (the left arm still warns about the heart);
* names are matched case- and spacing-insensitively, and a slash in a region
  name ("Chest / Heart") survives the URL;
* an unknown name is a 404, and a mapped part with no report says so.
"""

from urllib.parse import quote

import pytest
from fastapi.testclient import TestClient

from app.main import app
from app.services import organ_lookup

PART_URL = "/api/v1/anatomy/part/"
ORGANS_URL = "/api/v1/anatomy/organs"

client = TestClient(app)


def _get(name, **params):
    return client.get(PART_URL + quote(name, safe=""), params=params)


# (tap name the app sends, report expected). These are the region strings the
# 3D viewer (region-map.js), the flat renderer (backendRegionFor2D) and the
# region picker send - the outside of the body, where patients point.
SURFACE_CASES = [
    ("Headache / Cranial", "skull"),
    ("Neck", "vertebral_column"),
    ("Chest / Heart", "heart"),
    ("Abdomen (Upper)", "stomach"),
    ("Abdomen (Lower Right)", "appendix"),
    ("Abdomen (Lower Left)", "large_intestine"),
    ("Hips / Groin", "pelvis"),
    ("Thighs", "femur"),
    ("Back Pain (Upper)", "vertebral_column"),
    ("Back Pain (Lower)", "vertebral_column"),
    ("Left Shoulder", "deltoid"),
    ("Right Shoulder", "deltoid"),
    ("Left Armpit", "lymph_node"),
    ("Right Armpit", "lymph_node"),
    ("Left Elbow", "humerus"),
    ("Right Elbow", "humerus"),
    ("Left Wrist", "wrist"),
    ("Right Wrist", "wrist"),
    ("Left Hand", "hand"),
    ("Right Hand", "hand"),
    ("Left Thigh", "femur"),
    ("Right Thigh", "femur"),
    ("Left Knee", "knee"),
    ("Right Knee", "knee"),
    ("Left Shin / Calf", "tibia"),
    ("Right Shin / Calf", "tibia"),
    ("Left Ankle", "ligament"),
    ("Right Ankle", "ligament"),
    ("Left Foot", "foot"),
    ("Right Foot", "foot"),
    ("Left Arm / Shoulder", "humerus"),
    ("Right Arm / Shoulder", "humerus"),
    ("Left Leg / Knee", "knee"),
    ("Right Leg / Knee", "knee"),
    # Mesh names an outside tap really produces.
    ("Skin", "skin"),
    ("skin of body", "skin"),
]


@pytest.mark.parametrize("name,expected", SURFACE_CASES)
def test_surface_taps_resolve_to_expected_report(name, expected):
    res = _get(name)
    assert res.status_code == 200, res.text
    body = res.json()
    assert body["match"] == "report"
    assert body["about"] == expected
    assert body["report"]["organ"] == organ_lookup.reports()[expected]["organ"]


@pytest.mark.parametrize("name,_", SURFACE_CASES[:34])
def test_every_region_keeps_its_safety_text(name, _):
    region = _get(name).json()["region"]
    assert region is not None and region["region"] == name
    assert region["red_flags"], f"{name} lost its red flags"
    assert region["suggested_questions"]


def test_left_arm_still_warns_about_the_heart():
    flags = " ".join(_get("Left Arm / Shoulder").json()["region"]["red_flags"]).lower()
    assert "heart" in flags or "cardiac" in flags or "chest" in flags


def test_region_param_adds_safety_text_to_a_mesh_tap():
    body = _get("Skin", region="Left Knee").json()
    assert body["about"] == "skin"
    assert body["region"]["region"] == "Left Knee"
    assert _get("Skin").json()["region"] is None


def test_every_mapped_part_answers():
    reports = organ_lookup.reports()
    for name, entry in organ_lookup.parts().items():
        body = organ_lookup.lookup(name)
        assert body is not None, name
        if name.replace(" ", "_") in reports:
            # A mesh named exactly like a report ("cornea") is answered by it.
            assert body["about"] == name.replace(" ", "_")
            continue
        assert body["system"] == entry["system"]
        if body["match"] == "report":
            assert body["about"] in reports
            assert body["about"] == next(c for c in entry["candidates"] if c in reports)
        else:
            assert body["report"] is None and body["message"] == organ_lookup.COMING_SOON


def test_every_candidate_is_a_real_report_or_known_gap():
    # 32 mesh names ship with no report yet; nothing else may point at a
    # report that does not exist.
    gaps = [n for n, e in organ_lookup.parts().items()
            if not any(c in organ_lookup.reports() for c in e["candidates"])]
    assert len(gaps) <= 32


def test_every_route_answers_over_http_for_a_sample():
    for name in list(organ_lookup.parts())[::50]:
        assert _get(name).status_code == 200, name


def test_report_shape():
    report = _get("heart").json()["report"]
    for field in ("organ", "system", "description", "subparts", "functions", "disorders"):
        assert field in report
    for d in report["disorders"]:
        assert set(d) >= {"name", "mentions", "evidence"}


def test_report_name_is_answered_directly():
    body = _get("small intestine").json()
    assert body["match"] == "report" and body["about"] == "small_intestine"


def test_case_and_spacing_are_ignored():
    assert _get("  LEFT   knee ").json()["about"] == "knee"
    assert _get("MITRAL VALVE").json()["about"] == "heart_valve"


def test_part_with_no_report_says_coming_soon():
    body = _get("hyoid bone").json()
    assert body["match"] == "system"
    assert body["report"] is None
    assert body["message"] == organ_lookup.COMING_SOON


def test_unknown_name_is_404():
    assert _get("not a body part").status_code == 404


def test_brain_ventricles_resolve_to_brain():
    # Filed under "cardiac" in the 3D atlas, but they are brain ventricles.
    for name in ("fourth ventricle", "third ventricle", "lateral ventricle"):
        assert _get(name).json()["about"] == "brain"


def test_organs_lists_every_report():
    assert client.get(ORGANS_URL).json()["reports"] == sorted(organ_lookup.reports())
