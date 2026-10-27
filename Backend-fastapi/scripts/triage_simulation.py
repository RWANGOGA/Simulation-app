"""Run the triage simulation and write its result artifacts.

What this measures — and, more importantly, what it refuses to claim
--------------------------------------------------------------------
`fixtures/vignettes.json` pairs each case with an `intended_tier`: the SATS
category the harness author *constructed* the vignette to exercise. This script
drives the real engine (`triage_service.compute_risk` + `triage_tier`) over every
case and compares the tool's tier to that intended tier.

That comparison is **specification conformance** — do the rules land where they
were built to land — and nothing more. It is *not* clinical validity and it is
*not* inter-rater reliability, for two reasons written into the fixture header
and re-checked here before a single number is emitted:

  * `provenance.clinician_label` is false. No clinician produced `intended_tier`,
    so agreement cannot be reported as "the tool agrees with a nurse".
  * `provenance.second_labeler_id` is null and there is one author. A kappa needs
    two independent labelers; with one author and a design target, the honest
    inter-rater figure is *unavailable*, so the guard below reports it as such
    instead of quietly presenting the tool-vs-intended number in its place.

When a clinician reviews the set (set `clinician_label` true, populate a
`clinician_tier`, and add a `second_labeler_id`), the same `agreement_report`
call becomes the tool-vs-clinician kappa the paper's title promises. Until then
every number here is labelled with exactly what it is.

Run it:

    venv/bin/python -m scripts.triage_simulation

Writes `docs/results/triage-simulation.json` and `docs/results/triage-simulation.md`.
"""
from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Dict, List, Tuple

BACKEND_DIR = Path(__file__).resolve().parent.parent
FIXTURE_PATH = BACKEND_DIR / "fixtures" / "vignettes.json"
RESULTS_DIR = BACKEND_DIR / "docs" / "results"
JSON_OUT = RESULTS_DIR / "triage-simulation.json"
MD_OUT = RESULTS_DIR / "triage-simulation.md"

TIER_ORDER = ("red", "orange", "yellow", "green")


class InterRaterUnavailable(RuntimeError):
    """Raised when a two-rater statistic is requested but the fixture has no
    second labeler, so no honest value exists to return."""


def inter_rater_kappa(pairs, provenance, weights=None) -> float:
    """Two-rater agreement — only when the data actually has two raters.

    The reason this is a function that can *refuse* rather than a line in the
    report: with one author and no second labeler there is no second column to
    compare, so any number produced here would just be the tool-vs-design-target
    kappa wearing an inter-rater label. The guard is checked first and raises.
    """
    guard = check_guard(provenance)
    if not guard["inter_rater_kappa_available"]:
        raise InterRaterUnavailable(
            "inter-rater kappa needs a clinician label and a second labeler; "
            f"fixture has clinician_label={guard['clinician_label']!r}, "
            f"second_labeler_id={guard['second_labeler_id']!r}"
        )
    from app.services import evaluation

    return evaluation.weighted_kappa(pairs, weights=weights)


def load_fixture(path: Path = FIXTURE_PATH) -> Dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def _reference_label(provenance: Dict[str, Any]) -> str:
    """The name the reference column gets in every report, so the metric is never
    read as a clinician comparison when it is not one."""
    if provenance.get("clinician_label"):
        return "clinician"
    return "design_target"


def run_case(engine, case: Dict[str, Any]) -> Dict[str, Any]:
    """Drive the real engine over one vignette and record what it decided."""
    triage_service, TriageCreate = engine
    inp = case["input"]
    payload = TriageCreate(
        body_region=inp["body_region"],
        pain_type=inp["pain_type"],
        severity=inp["severity"],
        heart_rate=inp["heart_rate"],
        direction=inp["direction"],
    )
    risk, contributions = triage_service.compute_risk(
        payload,
        sibling_regions=inp["siblings"],
        patient_weight=inp["patient_weight"],
        patient_height=inp["patient_height"],
    )
    verdict = triage_service.triage_tier(payload, risk)
    return {
        "id": case["id"],
        "summary": case["summary"],
        "intended_tier": case["intended_tier"],
        "tool_tier": verdict["tier"],
        "risk": round(risk, 6),
        "decided_by": verdict["decided_by"],
        "contributions": contributions,
    }


def check_guard(provenance: Dict[str, Any]) -> Dict[str, Any]:
    """Decide, from the fixture header alone, what may honestly be reported."""
    clinician = bool(provenance.get("clinician_label"))
    second = provenance.get("second_labeler_id")
    inter_rater_available = clinician and second is not None
    return {
        "clinician_label": clinician,
        "second_labeler_id": second,
        "reference_kind": provenance.get("reference_kind"),
        "author_labeler_id": provenance.get("author_labeler_id"),
        "inter_rater_kappa_available": inter_rater_available,
        "interpretation": (
            "tool-vs-design-target specification conformance"
            if not clinician
            else "tool-vs-clinician agreement"
        ),
        "note": provenance.get("note", ""),
    }


def worked_cases(results: List[Dict[str, Any]]) -> List[Dict[str, Any]]:
    """Pick a few cases that each illustrate a different deciding rule, so the
    report shows *why* the engine chose a tier rather than only *that* it did."""
    wanted = {
        "red by vital-sign floor": lambda r: r["tool_tier"] == "red"
        and "heart_rate_critical" in r["decided_by"],
        "orange by score on a concerning region": lambda r: r["tool_tier"] == "orange"
        and "score_high_in_concerning_region" in r["decided_by"],
        "green by below urgent band": lambda r: r["tool_tier"] == "green",
    }
    picks: List[Dict[str, Any]] = []
    for label, predicate in wanted.items():
        match = next((r for r in results if predicate(r)), None)
        if match is None:
            continue
        picks.append(
            {
                "label": label,
                "id": match["id"],
                "summary": match["summary"],
                "intended_tier": match["intended_tier"],
                "tool_tier": match["tool_tier"],
                "risk": match["risk"],
                "decided_by": match["decided_by"],
                "contributions": match["contributions"],
            }
        )
    return picks


def sensitivity_analysis(engine, fixture: Dict[str, Any]) -> Dict[str, Any]:
    """How much the tier distribution depends on two score mechanisms.

    These are *counterfactual replays* of the real engine, not a re-tuned model:

    * **Heart-rate ablation** re-runs every vignette with `heart_rate=None`, so
      both the HR score bump and the HR red-flag rules go quiet. It answers
      "what would this set look like if the device had no pulse input?" — the
      safety-relevant direction is a case that drops *out* of red/orange.
    * **Score-cap ablation** un-clamps the total back to the raw weighted sum
      (the cap row the engine records is exactly the amount discarded) and
      re-derives the tier. Because every band is a *lower* bound and the cap
      only ever bites at or above 1.00, no tier can move — a fact worth stating
      plainly rather than implying the cap shapes the category.

    The graph-propagation ablation this harness will eventually report is
    deliberately *absent*: 1-hop message passing is not built yet (Unit 2), so
    there is nothing honest to switch off. The connectivity bump that exists
    today is a fixed per-edge weight, not propagation, and ablating it belongs
    with the real mechanism.
    """
    triage_service, TriageCreate = engine

    def _payload(inp: Dict[str, Any], *, drop_hr: bool):
        return TriageCreate(
            body_region=inp["body_region"],
            pain_type=inp["pain_type"],
            severity=inp["severity"],
            heart_rate=None if drop_hr else inp["heart_rate"],
            direction=inp["direction"],
        )

    def _tier(inp: Dict[str, Any], *, drop_hr: bool = False, uncap: bool = False):
        payload = _payload(inp, drop_hr=drop_hr)
        risk, contributions = triage_service.compute_risk(
            payload,
            sibling_regions=inp["siblings"],
            patient_weight=inp["patient_weight"],
            patient_height=inp["patient_height"],
        )
        capped = any("capped" in c["factor"].lower() for c in contributions)
        if uncap and capped:
            cap_row = next(
                c for c in contributions if "capped" in c["factor"].lower()
            )
            score = round(risk - cap_row["contribution"], 6)
        else:
            score = risk
        return triage_service.triage_tier(payload, score)["tier"], capped

    def _distribution(tiers):
        dist = {tier: 0 for tier in TIER_ORDER}
        for tier in tiers:
            dist[tier] += 1
        return dist

    baseline: List[str] = []
    hr_ablated: List[str] = []
    cap_ablated: List[str] = []
    hr_transitions: List[Dict[str, Any]] = []
    capped_cases = 0
    for case in fixture["cases"]:
        inp = case["input"]
        base_tier, was_capped = _tier(inp)
        baseline.append(base_tier)
        capped_cases += int(was_capped)
        hr_tier, _ = _tier(inp, drop_hr=True)
        hr_ablated.append(hr_tier)
        cap_ablated.append(_tier(inp, uncap=True)[0])
        if hr_tier != base_tier:
            hr_transitions.append({
                "id": case["id"],
                "intended": case["intended_tier"],
                "baseline_tier": base_tier,
                "hr_ablated_tier": hr_tier,
            })

    under_triage_flips = sum(
        1 for t in hr_transitions
        if TIER_ORDER.index(t["hr_ablated_tier"]) > TIER_ORDER.index(t["baseline_tier"])
    )
    return {
        "baseline_distribution": _distribution(baseline),
        "heart_rate_ablation": {
            "distribution": _distribution(hr_ablated),
            "tier_changes": len(hr_transitions),
            "under_triage_flips": under_triage_flips,
            "transitions": hr_transitions,
        },
        "score_cap_ablation": {
            "distribution": _distribution(cap_ablated),
            "capped_cases": capped_cases,
            "tier_changes": sum(
                1 for a, b in zip(cap_ablated, baseline) if a != b
            ),
        },
        "graph_propagation": {
            "available": False,
            "reason": "1-hop message passing is not built yet (Unit 2).",
        },
    }


def build_report(fixture: Dict[str, Any]) -> Dict[str, Any]:
    from app.services import triage_service
    from app.schemas import TriageCreate
    from app.services import evaluation

    engine = (triage_service, TriageCreate)
    results = [run_case(engine, case) for case in fixture["cases"]]

    pairs: List[Tuple[str, str]] = [
        (r["tool_tier"], r["intended_tier"]) for r in results
    ]
    guard = check_guard(fixture["provenance"])

    # agreement_report is the tool-vs-reference statistic. The guard above is what
    # keeps its *meaning* honest; the arithmetic itself is pinned in tests.
    agreement = evaluation.agreement_report(pairs)

    # A genuine inter-rater kappa is attempted through the gate, not fabricated:
    # with one author and no second labeler the call refuses and we record *why*.
    try:
        inter_rater: Dict[str, Any] = {
            "available": True,
            "weighted_kappa": inter_rater_kappa(pairs, fixture["provenance"]),
        }
    except InterRaterUnavailable as exc:
        inter_rater = {"available": False, "reason": str(exc)}

    conformance = [
        {
            "id": r["id"],
            "intended": r["intended_tier"],
            "actual": r["tool_tier"],
            "risk": r["risk"],
            "summary": r["summary"],
        }
        for r in results
        if r["tool_tier"] != r["intended_tier"]
    ]

    return {
        "generated_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "fixture_version": fixture.get("version"),
        "scale": fixture.get("scale"),
        "n_cases": len(results),
        "counts": fixture.get("counts"),
        "reference_label": _reference_label(fixture["provenance"]),
        "guard": guard,
        "agreement": agreement,
        "inter_rater": inter_rater,
        "conformance_mismatches": conformance,
        "sensitivity": sensitivity_analysis(engine, fixture),
        "worked_cases": worked_cases(results),
    }


def _round(value: Any) -> Any:
    return round(value, 6) if isinstance(value, float) else value


def format_markdown(report: Dict[str, Any]) -> str:
    guard = report["guard"]
    agreement = report["agreement"]
    red = agreement["red_sensitivity"]
    lines: List[str] = []
    lines.append("# Triage simulation — specification conformance")
    lines.append("")
    lines.append(
        f"Generated by `scripts/triage_simulation.py` over "
        f"`{report['n_cases']}` vignettes on the {report['scale']} scale."
    )
    lines.append("")
    lines.append("## How to read these numbers")
    lines.append("")
    lines.append(
        f"- **Reference column:** `{report['reference_label']}` — the "
        f"`intended_tier` each vignette was built to exercise."
    )
    lines.append(
        "- **This is specification conformance, not clinical validity.** No "
        "clinician labelled this set, so agreement says the rules land where "
        "they were designed to land, not that they match a nurse's judgement."
    )
    lines.append(
        "- **Inter-rater reliability: "
        + ("available." if guard["inter_rater_kappa_available"] else "NOT available.")
        + "**"
    )
    if not guard["inter_rater_kappa_available"]:
        lines.append(
            "  A kappa comparing two raters is deliberately **not** reported: "
            "there is a single non-clinician author and no second labeler. "
            "The tool-vs-design-target figures below are *not* a substitute for "
            "that missing statistic."
        )
        lines.append(
            f"  Attempting it returns: *{report['inter_rater'].get('reason', '')}*"
        )
    lines.append("")
    lines.append("## Category coverage")
    lines.append("")
    lines.append("| tier | vignettes |")
    lines.append("| --- | ---: |")
    for tier in TIER_ORDER:
        lines.append(f"| {tier} | {report['counts'].get(tier, 0)} |")
    lines.append("")
    lines.append(f"## Agreement (tool vs {report['reference_label']})")
    lines.append("")
    lines.append(f"- n = {agreement['n']}")
    lines.append(
        f"- weighted Cohen's kappa (linear weights, stated parameter) = "
        f"{_round(agreement['weighted_kappa'])}"
    )
    lines.append(f"- unweighted Cohen's kappa = {_round(agreement['cohen_kappa'])}")
    lines.append(
        f"- red-vs-not-red boundary kappa = {_round(agreement['red_boundary_kappa'])}"
    )
    lines.append(
        f"- exact agreement rate = {_round(agreement['agreement_rate'])} "
        f"({agreement['exact']}/{agreement['n']})"
    )
    lines.append(
        f"- under-triage rate = {_round(agreement['under_rate'])} "
        f"({agreement['under']}/{agreement['n']})"
    )
    lines.append(
        f"- over-triage rate = {_round(agreement['over_rate'])} "
        f"({agreement['over']}/{agreement['n']})"
    )
    lines.append("")
    lines.append("### Confusion matrix (rows = tool, columns = reference)")
    lines.append("")
    matrix = agreement["confusion"]
    header = "| tool \\ ref | " + " | ".join(TIER_ORDER) + " |"
    lines.append(header)
    lines.append("| --- | " + " | ".join(["---:"] * len(TIER_ORDER)) + " |")
    for tool in TIER_ORDER:
        cells = " | ".join(str(matrix[tool][ref]) for ref in TIER_ORDER)
        lines.append(f"| {tool} | {cells} |")
    lines.append("")
    lines.append("### Red-tier sensitivity (of intended-red, how many the tool called red)")
    lines.append("")
    if red["denominator"]:
        lo, hi = red["ci95"]
        lines.append(
            f"- {red['hits']}/{red['denominator']} = "
            f"{_round(red['sensitivity'])} "
            f"(Wilson 95% CI {_round(lo)}–{_round(hi)})"
        )
    else:
        lines.append("- no intended-red cases; sensitivity undefined.")
    lines.append("")
    lines.append("## Specification conformance")
    lines.append("")
    mismatches = report["conformance_mismatches"]
    if mismatches:
        lines.append(
            f"{len(mismatches)} vignette(s) did not land on their intended tier:"
        )
        lines.append("")
        for m in mismatches:
            lines.append(
                f"- `{m['id']}` intended **{m['intended']}** but engine gave "
                f"**{m['actual']}** (risk {m['risk']}): {m['summary']}"
            )
    else:
        lines.append(
            f"All {report['n_cases']} vignettes landed on their intended tier — "
            "the rules realise their design intent on this set. (This says nothing "
            "about clinical validity; see the reading note above.)"
        )
    lines.append("")
    lines.append("## Sensitivity / ablation (counterfactual replays)")
    lines.append("")
    sens = report["sensitivity"]
    lines.append(
        f"- **Baseline distribution:** "
        + ", ".join(f"{t} {sens['baseline_distribution'][t]}" for t in TIER_ORDER)
    )
    hr = sens["heart_rate_ablation"]
    lines.append(
        f"- **Heart-rate ablation** (every vignette replayed with no pulse "
        f"input): {hr['tier_changes']} of {report['n_cases']} change tier "
        f"({hr['under_triage_flips']} toward less urgent)."
    )
    lines.append(
        "  - ablated distribution: "
        + ", ".join(f"{t} {hr['distribution'][t]}" for t in TIER_ORDER)
    )
    cap = sens["score_cap_ablation"]
    lines.append(
        f"- **Score-cap ablation** (un-clamp to the raw weighted sum): "
        f"{cap['tier_changes']} tier changes across {cap['capped_cases']} "
        "capped case(s) — the cap shapes the displayed number, not the category, "
        "because every band is a lower bound."
    )
    graph = sens["graph_propagation"]
    lines.append(
        f"- **Graph-propagation ablation:** "
        + ("reported above." if graph["available"]
           else f"not reported — {graph['reason']}")
    )
    lines.append("")
    lines.append("## Worked attribution (why the engine chose)")
    lines.append("")
    for worked in report["worked_cases"]:
        lines.append(
            f"### `{worked['id']}` — {worked['label']}"
        )
        lines.append("")
        lines.append(f"> {worked['summary']}")
        lines.append("")
        lines.append(
            f"- intended **{worked['intended_tier']}**, engine **{worked['tool_tier']}**, "
            f"risk {worked['risk']}"
        )
        lines.append(f"- decided_by: `{', '.join(worked['decided_by'])}`")
        lines.append("")
    lines.append("## Provenance note")
    lines.append("")
    lines.append(f"> {guard['note']}")
    lines.append("")
    return "\n".join(lines)


def main() -> None:
    fixture = load_fixture()
    report = build_report(fixture)

    RESULTS_DIR.mkdir(parents=True, exist_ok=True)
    JSON_OUT.write_text(json.dumps(report, indent=2, sort_keys=False) + "\n", encoding="utf-8")
    MD_OUT.write_text(format_markdown(report), encoding="utf-8")

    guard = report["guard"]
    print(
        f"ran {report['n_cases']} vignettes; "
        f"interpretation={report['guard']['interpretation']}; "
        f"inter_rater_kappa_available={guard['inter_rater_kappa_available']}; "
        f"conformance_mismatches={len(report['conformance_mismatches'])}"
    )
    print(f"wrote {JSON_OUT}")
    print(f"wrote {MD_OUT}")


if __name__ == "__main__":
    main()
