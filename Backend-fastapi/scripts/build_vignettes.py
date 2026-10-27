"""Generate `fixtures/vignettes.json` — the standardised triage simulation set.

This builds the 150 cases the simulation runs, deterministically (no RNG, so the
committed file is reproducible and reviewable as a diff). Each case carries an
`intended_tier`: the SATS category the case was *constructed* to exercise, decided
from the plain-language scenario by the harness author before running any engine.

Provenance is deliberately modest and is written into the file's header so the
runner cannot over-claim from it:

  * The reference field is `intended_tier` (a design target), the reference kind
    is `design_target`, and `clinician_label` is false. This is NOT a clinician's
    reference standard. Agreement computed against it is specification
    conformance — do the rules land where they were built to land — not clinical
    validity.
  * `second_labeler_id` is null and there is one author, so the harness must
    report inter-rater reliability as unavailable and refuse to emit a second
    labeler's kappa. `triage_simulation.py` enforces that.

Coverage, asserted by the generator and re-asserted in tests: >=30 cases in each
of the four categories, spanning single-region reports, multi-region co-reports,
extreme severity, heart-rate outliers, and cases with missing attributes.

Regenerate with:
    venv/bin/python -m scripts.build_vignettes

The same set is mirrored to `simtack/test/fixtures/vignettes.json` so the offline
Dart engine is replayed against the *identical* vignettes the Python harness
scores (same one-source pattern as `scripts/export_offline_assets.py`).
"""
from __future__ import annotations

import json
from pathlib import Path
from typing import Any, Dict, List

OUTPUT = Path(__file__).resolve().parent.parent / "fixtures" / "vignettes.json"
# Mirror for the on-device parity test; see the module docstring.
DART_OUTPUT = (
    Path(__file__).resolve().parent.parent.parent
    / "simtack" / "test" / "fixtures" / "vignettes.json"
)

# Region labels chosen to hit each _region_weight band and, where relevant, to be
# real BODY_GRAPH keys so referred-pain edges fire in the co-report cases. The
# limb labels matter: `find_connection` matches region names exactly, so the old
# "Left Arm" / "Right Arm" / "Left Leg" spelled the same band as
# "Left Arm / Shoulder" and friends but matched no edge at all, and the co-report
# cases below were silently scoring as if no neighbour had been reported.
CHEST = "Chest / Heart"
HEAD = "Headache / Cranial"
NECK = "Neck"
ABDOMEN = "Abdomen (Upper)"
BACK = "Back Pain (Lower)"
ARM_LEFT = "Left Arm / Shoulder"
ARM_RIGHT = "Right Arm / Shoulder"
LEG_LEFT = "Left Leg / Knee"


def _case(
    cid: str,
    intended: str,
    summary: str,
    *,
    region: str,
    pain: str,
    severity: int,
    direction: str | None = None,
    heart_rate: float | None = None,
    weight: float | None = None,
    height: float | None = None,
    siblings: List[str] | None = None,
    sibling_severities: Dict[str, int] | None = None,
) -> Dict[str, Any]:
    return {
        "id": cid,
        "summary": summary,
        "intended_tier": intended,
        "input": {
            "body_region": region,
            "pain_type": pain,
            "severity": severity,
            "direction": direction,
            "heart_rate": heart_rate,
            "patient_weight": weight,
            "patient_height": height,
            "siblings": siblings or [],
            # What the other pain point in this same visit was rated. Declared
            # rather than left empty so the referral (propagation) term has
            # something to carry; without a severity a neighbour can only say
            # "I exist", which is the older fixed co-report bump.
            "sibling_severities": sibling_severities or {},
        },
    }


def _red(cases: List[Dict[str, Any]], start: int) -> int:
    """Emergencies: a red-flag finding or a critical heart rate decides these, so
    the heart-rate outlier and extreme-severity coverage lives mostly here."""
    i = start
    # Crushing / stabbing chest pain, low to high severity — the classic MI read
    # that must be Red even when the additive score looks calm.
    for severity in (1, 2, 3, 5, 6, 7, 9):
        for pain in ("Crushing", "Stabbing"):
            cases.append(_case(
                f"V{i:03d}", "red",
                f"{pain.title()} central chest pain rated {severity}/10",
                region=CHEST, pain=pain, severity=severity,
            ))
            i += 1
    # Radiating chest pain (the direction field, not the character, is the tell).
    for severity in (2, 3, 4, 6, 7, 8):
        cases.append(_case(
            f"V{i:03d}", "red",
            f"Chest pain rated {severity}/10 spreading to the left arm",
            region=CHEST, pain="Pressure", severity=severity,
            direction="Radiating down left arm", siblings=[ARM_LEFT],
            # The arm is its own pain point in the same visit, and the patient
            # rates it 7/10 - which is what lets the referral term carry a
            # signal, not merely the fact that the arm was tapped.
            sibling_severities={ARM_LEFT: 7},
        ))
        i += 1
    # Severe chest pain by intensity alone (>=8).
    for severity in (8, 9):
        for pain in ("Sharp", "Burning"):
            cases.append(_case(
                f"V{i:03d}", "red", f"Chest pain rated {severity}/10",
                region=CHEST, pain=pain, severity=severity,
            ))
            i += 1
    # Critical heart rates on an otherwise ordinary report — proves the vital-sign
    # floor outranks the score. Outlier band above 120 and below 50.
    for rate in (125.0, 132.0, 145.0, 160.0, 44.0, 38.0, 49.0, 40.0):
        cases.append(_case(
            f"V{i:03d}", "red",
            f"Leg pain with heart rate {rate:g} bpm",
            region=LEG_LEFT, pain="Dull", severity=3, heart_rate=rate,
        ))
        i += 1
    # Maximum pain in a high-concern region (>=10 in head/abdomen/neck).
    for region, pain in (
        (HEAD, "Throbbing"), (ABDOMEN, "Sharp"), (NECK, "Cramping"),
        (HEAD, "Numb"), (ABDOMEN, "Crushing"), (NECK, "Burning"),
    ):
        cases.append(_case(
            f"V{i:03d}", "red", f"{region} pain rated 10/10",
            region=region, pain=pain, severity=10,
        ))
        i += 1
    # Chest pain plus an abnormal body habitus — multi-factor emergency.
    for bmi_pair in ((110.0, 170.0), (45.0, 165.0)):
        cases.append(_case(
            f"V{i:03d}", "red",
            "Crushing chest pain with an abnormal body habitus",
            region=CHEST, pain="Crushing", severity=6,
            weight=bmi_pair[0], height=bmi_pair[1],
        ))
        i += 1
    return i


def _orange(cases: List[Dict[str, Any]], start: int) -> int:
    """Very urgent: an urgent red flag, or a high score in a concerning region."""
    i = start
    # High (but not critical) heart rate: 101-120 bpm is the urgent band.
    for rate in (101.0, 108.0, 115.0, 120.0):
        for region, pain in ((LEG_LEFT, "Aching"), (ARM_RIGHT, "Sore"),
                             (BACK, "Dull"), (CHEST, "Sharp"), (ARM_LEFT, "Numb")):
            cases.append(_case(
                f"V{i:03d}", "orange",
                f"{region} pain with heart rate {rate:g} bpm",
                region=region, pain=pain, severity=4, heart_rate=rate,
            ))
            i += 1
    # Severe head pain (>=8, not 10) fires head_pain_severe.
    for severity in (8, 9):
        for pain in ("Throbbing", "Sharp", "Burning", "Numb"):
            cases.append(_case(
                f"V{i:03d}", "orange",
                f"Head pain rated {severity}/10",
                region=HEAD, pain=pain, severity=severity,
            ))
            i += 1
    # Maximum pain in a NON-concern region is urgent, not emergency.
    for region in (ARM_LEFT, ARM_RIGHT, LEG_LEFT, BACK):
        cases.append(_case(
            f"V{i:03d}", "orange",
            f"{region} pain rated 10/10",
            region=region, pain="Crushing", severity=10,
        ))
        i += 1
    # High score in a concerning region with nothing individually flagged:
    # the number alone must be allowed to reach Orange only where it matters.
    for region, pain, severity in (
        (HEAD, "Numb", 7), (ABDOMEN, "Sharp", 7), (NECK, "Cramping", 7),
        (NECK, "Burning", 6), (HEAD, "Throbbing", 6),
        (ABDOMEN, "Burning", 7), (NECK, "Sharp", 7), (ABDOMEN, "Cramping", 8),
    ):
        cases.append(_case(
            f"V{i:03d}", "orange",
            f"{region} pain rated {severity}/10",
            region=region, pain=pain, severity=severity,
        ))
        i += 1
    # Co-reported neck + chest (a high-concern edge) driving the score up.
    cases.append(_case(
        f"V{i:03d}", "orange", "Neck pain alongside chest discomfort",
        region=NECK, pain="Stiff", severity=5, siblings=[CHEST],
        sibling_severities={CHEST: 6},
    ))
    i += 1
    return i


def _yellow(cases: List[Dict[str, Any]], start: int) -> int:
    """Urgent by score only: >=0.40, nothing flagged, and not (>=0.70 in a
    concerning region)."""
    i = start
    combos = [
        (BACK, "Sharp", 5), (ARM_RIGHT, "Throbbing", 6), (LEG_LEFT, "Cramping", 8),
        (ARM_LEFT, "Burning", 5), (BACK, "Numb", 6), (LEG_LEFT, "Sharp", 6),
        (ARM_RIGHT, "Sharp", 7), (BACK, "Dull", 7), (LEG_LEFT, "Throbbing", 7),
        (ARM_LEFT, "Cramping", 6), (BACK, "Crushing", 9), (LEG_LEFT, "Stabbing", 9),
        (ARM_RIGHT, "Burning", 6), (BACK, "Throbbing", 6), (LEG_LEFT, "Numb", 8),
        (ARM_LEFT, "Sharp", 6), (BACK, "Stabbing", 8), (LEG_LEFT, "Burning", 7),
        (ARM_RIGHT, "Crushing", 8), (BACK, "Cramping", 7), (LEG_LEFT, "Sore", 8),
        (ARM_LEFT, "Throbbing", 7), (BACK, "Sore", 6), (LEG_LEFT, "Aching", 7),
        (ARM_RIGHT, "Stabbing", 7), (BACK, "Burning", 7), (LEG_LEFT, "Crushing", 8),
        (ARM_LEFT, "Dull", 7), (BACK, "Sharp", 7), (LEG_LEFT, "Dull", 9),
        (ARM_RIGHT, "Throbbing", 8), (BACK, "Sharp", 8),
    ]
    for region, pain, severity in combos:
        cases.append(_case(
            f"V{i:03d}", "yellow",
            f"{region} pain rated {severity}/10",
            region=region, pain=pain, severity=severity,
        ))
        i += 1
    # A few that carry vitals/anthropometrics that should not change the band, so
    # the score-only path is exercised with realistic extra columns present.
    for region, pain, severity, hr, w, h in (
        (BACK, "Sharp", 6, 92.0, 80.0, 175.0),
        (LEG_LEFT, "Dull", 7, 88.0, 70.0, 182.0),
        (ARM_RIGHT, "Aching", 8, 96.0, 60.0, 168.0),
        (LEG_LEFT, "Throbbing", 6, 84.0, 95.0, 160.0),
        (BACK, "Numb", 6, 99.0, 55.0, 172.0),
    ):
        cases.append(_case(
            f"V{i:03d}", "yellow",
            f"{region} pain rated {severity}/10 with routine vitals",
            region=region, pain=pain, severity=severity, heart_rate=hr,
            weight=w, height=h,
        ))
        i += 1
    return i


def _green(cases: List[Dict[str, Any]], start: int) -> int:
    """Routine: below 0.40 with nothing flagged."""
    i = start
    combos = [
        (LEG_LEFT, "Dull", 1), (LEG_LEFT, "Dull", 2), (LEG_LEFT, "Dull", 3),
        (LEG_LEFT, "Dull", 4), (LEG_LEFT, "Numb", 2), (LEG_LEFT, "Numb", 3),
        (LEG_LEFT, "Aching", 2), (LEG_LEFT, "Aching", 3), (LEG_LEFT, "Sore", 2),
        (LEG_LEFT, "Sore", 3), (LEG_LEFT, "Sore", 4), (LEG_LEFT, "Cramping", 2),
        (LEG_LEFT, "Cramping", 3), (LEG_LEFT, "Sharp", 3), (LEG_LEFT, "Burning", 3),
        (LEG_LEFT, "Throbbing", 3), (LEG_LEFT, "Throbbing", 2),
        (ARM_RIGHT, "Dull", 1), (ARM_RIGHT, "Dull", 2), (ARM_RIGHT, "Dull", 3),
        (ARM_RIGHT, "Aching", 2), (ARM_RIGHT, "Aching", 3), (ARM_RIGHT, "Numb", 3),
        (ARM_RIGHT, "Sore", 2), (ARM_RIGHT, "Sore", 3), (ARM_RIGHT, "Throbbing", 3),
        (BACK, "Dull", 1), (BACK, "Dull", 2), (BACK, "Numb", 2),
        (BACK, "Aching", 2), (BACK, "Sore", 2), (BACK, "Throbbing", 2),
    ]
    for region, pain, severity in combos:
        cases.append(_case(
            f"V{i:03d}", "green",
            f"{region} pain rated {severity}/10",
            region=region, pain=pain, severity=severity,
        ))
        i += 1
    return i


def build() -> Dict[str, Any]:
    cases: List[Dict[str, Any]] = []
    nxt = _red(cases, 1)
    nxt = _orange(cases, nxt)
    nxt = _yellow(cases, nxt)
    _green(cases, nxt)

    by_category: Dict[str, int] = {}
    for case in cases:
        by_category[case["intended_tier"]] = by_category.get(case["intended_tier"], 0) + 1

    return {
        "version": 1,
        "scale": "SATS",
        "provenance": {
            "reference_field": "intended_tier",
            "reference_kind": "design_target",
            "clinician_label": False,
            "author_labeler_id": "harness_author_v1",
            "second_labeler_id": None,
            "note": (
                "intended_tier is the SATS category each vignette was constructed "
                "to exercise, assigned by a single non-clinician author. It is a "
                "specification-conformance answer key, not a clinician's reference "
                "standard. Because there is no clinician label and no second "
                "labeler, agreement against it measures whether the rules realise "
                "their design intent — not clinical validity — and inter-rater "
                "reliability is not computed. Replace intended_tier with reviewed "
                "clinician labels (and set second_labeler_id) to produce the "
                "tool-vs-clinician kappa the paper's title promises."
            ),
        },
        "counts": by_category,
        "cases": cases,
    }


def main() -> None:
    data = build()
    counts = data["counts"]
    total = len(data["cases"])
    # Refuse to write an under-covered set: the whole point is >=30 per category.
    assert total == 150, f"expected 150 vignettes, built {total}"
    for tier in ("red", "orange", "yellow", "green"):
        assert counts[tier] >= 30, f"{tier} has only {counts[tier]} cases (<30)"

    OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    serialized = json.dumps(data, indent=2, sort_keys=False) + "\n"
    OUTPUT.write_text(serialized)
    DART_OUTPUT.parent.mkdir(parents=True, exist_ok=True)
    DART_OUTPUT.write_text(serialized)
    print(f"wrote {OUTPUT} with {total} cases: {counts}")
    print(f"mirrored to {DART_OUTPUT}")


if __name__ == "__main__":
    main()
