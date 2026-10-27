"""Agreement between the tool's SATS tier and a clinician's.

This is the arithmetic behind the number the title promises. It is deliberately
a set of *pure functions over (tool_tier, reference_tier) pairs* with no database,
no file and no fixture loading: the same code scores the vignette set in
`scripts/triage_simulation.py` and scores live `clinician_tier` reviews once the
product accumulates them, and a metric that reads its own inputs cannot be
audited against a hand-computed table the way these can.

Two honesty boundaries, because the examiner will check both:

* **SATS publishes no kappa weight matrix.** Gosling et al. (2006) define the
  four categories; they do not define how much a one-category slip should cost
  against a three-category one. So the weighted statistic below names its weights
  as an explicit, stated analysis parameter (linear/ordinal over the four
  categories, most-urgent first) rather than claiming a constant it did not get.
  The clinically salient comparison that needs *no* arbitrary weights — "did the
  system send a resus patient to the waiting room", red-versus-not-red — is
  reported alongside it as `red_boundary_kappa`.

* **One labeler is not an agreement study.** Everything here compares the tool to
  a reference. Whether *two clinicians* agree (which is what licenses treating one
  clinician's label as ground truth) is the same functions run over a second
  labeler's column — and `triage_simulation.py` refuses to emit that figure when
  no second label exists, rather than quietly substituting one number for the
  other.

`tests/test_evaluation.py` pins every function to a hand-computed table, so no
number the paper copies was ever unaudited.
"""
from __future__ import annotations

import math
from typing import Dict, List, Optional, Sequence, Tuple

from app.services import triage_service

# The ordinal axis: most urgent first. This order is the weight function's input,
# so it is imported from the single authoritative definition rather than restated
# here — a second copy of ("red", "orange", "yellow", "green") is how a kappa and
# a tier table could disagree about which direction is "worse".
TIERS: Tuple[str, ...] = triage_service.TIERS

_TIER_INDEX: Dict[str, int] = {tier: i for i, tier in enumerate(TIERS)}

# A (tool, reference) pair.
TierPair = Tuple[str, str]


def _index(tier: str) -> int:
    try:
        return _TIER_INDEX[tier]
    except KeyError as exc:
        raise ValueError(
            f"{tier!r} is not a SATS tier; expected one of {', '.join(TIERS)}"
        ) from exc


def linear_weights(tiers: Sequence[str] = TIERS) -> List[List[float]]:
    """Ordinal disagreement weights: ``w[i][j] = |i - j| / (k - 1)``.

    Zero on the diagonal, 1.0 for the widest disagreement (red vs green). This
    is a *stated* analysis parameter, not a SATS constant — see the module
    docstring. Any symmetric matrix of the same shape can be passed to
    `weighted_kappa` instead, so the sensitivity of the headline to this choice
    is a question the harness can actually answer.
    """
    n = len(tiers)
    if n < 2:
        raise ValueError("weighted kappa needs at least two categories")
    span = n - 1
    return [
        [abs(i - j) / span for j in range(n)]
        for i in range(n)
    ]


def confusion_matrix(
    pairs: Sequence[TierPair],
    tiers: Sequence[str] = TIERS,
) -> Dict[str, Dict[str, int]]:
    """Counts of ``[tool][reference]`` over the fixed category set.

    Keyed by tier name rather than by position so a serialised table cannot be
    silently re-ordered. Categories with no cases still get a row and a column
    (all zeros): dropping them would change kappa's marginals and make the
    statistic depend on which patients happened to walk in.
    """
    matrix = {a: {b: 0 for b in tiers} for a in tiers}
    for tool, reference in pairs:
        _require_in(tool, tiers)
        _require_in(reference, tiers)
        matrix[tool][reference] += 1
    return matrix


def _require_in(tier: str, tiers: Sequence[str]) -> None:
    # Validates membership against the caller's category list, which for the
    # public path is TIERS. Indexing a name-keyed table by the tier itself keeps
    # the confusion matrix readable without a positional lookup.
    if tier not in tiers:
        raise ValueError(f"{tier!r} is not in the category set {tuple(tiers)}")


def _marginals(counts: Sequence[Sequence[float]]) -> Tuple[List[float], List[float], float]:
    total = float(sum(sum(row) for row in counts))
    rows = [float(sum(row)) for row in counts]
    cols = [float(sum(col)) for col in zip(*counts)]
    return rows, cols, total


def weighted_kappa_from_counts(
    counts: Sequence[Sequence[float]],
    weights: Sequence[Sequence[float]],
) -> float:
    """Cohen's (1968) weighted kappa for a count table and a weight matrix.

    ``kappa_w = 1 - sum(w_ij * O_ij) / sum(w_ij * E_ij)`` where ``E_ij`` is the
    product of the marginals (independence). Both sums are in the same units, so
    the counts may stay counts — no normalisation step to introduce a rounding
    difference between here and the hand computation.

    A perfect diagonal makes the numerator zero, giving 1.0. When the weighted
    observed disagreement equals what chance would produce the score is 0.0.
    """
    rows, cols, total = _marginals(counts)
    if total == 0:
        raise ValueError("weighted kappa is undefined for an empty table")

    weighted_observed = 0.0
    weighted_expected = 0.0
    for i, row_counts in enumerate(counts):
        for j, observed in enumerate(row_counts):
            w = weights[i][j]
            if w == 0.0:
                continue
            weighted_observed += w * observed
            weighted_expected += w * (rows[i] * cols[j] / total)

    if weighted_expected == 0.0:
        # Only reachable when every off-diagonal cell with a non-zero weight is
        # empty — i.e. perfect agreement under these weights. 1.0 by limit.
        return 1.0
    return 1.0 - weighted_observed / weighted_expected


def weighted_kappa(
    pairs: Sequence[TierPair],
    weights: Optional[Sequence[Sequence[float]]] = None,
    tiers: Sequence[str] = TIERS,
) -> float:
    """Weighted kappa over (tool, reference) pairs; linear weights by default."""
    if weights is None:
        weights = linear_weights(tiers)
    matrix = confusion_matrix(pairs, tiers)
    counts = [[matrix[a][b] for b in tiers] for a in tiers]
    return weighted_kappa_from_counts(counts, weights)


def cohen_kappa(pairs: Sequence[TierPair], tiers: Sequence[str] = TIERS) -> float:
    """Unweighted Cohen's kappa: every mismatch counted the same.

    Reported so the reader can see the effect of the ordinal weights rather than
    taking them on faith — unweighted treats a red/green confusion and a
    yellow/green one as the identical error, which is exactly the assumption the
    weighted figure relaxes.
    """
    if not pairs:
        raise ValueError("kappa is undefined for an empty sample")
    matrix = confusion_matrix(pairs, tiers)
    counts = [[matrix[a][b] for b in tiers] for a in tiers]
    rows, cols, total = _marginals(counts)
    observed = sum(counts[i][i] for i in range(len(tiers))) / total
    expected = sum(rows[i] * cols[i] for i in range(len(tiers))) / (total * total)
    if expected == 1.0:
        return 1.0 if observed == 1.0 else 0.0
    return (observed - expected) / (1.0 - expected)


def red_boundary_kappa(pairs: Sequence[TierPair]) -> float:
    """Unweighted kappa collapsed to the binary "red vs. not red" decision.

    This is the disagreement that costs a patient the most — the system seating an
    emergency patient in the waiting room — and it needs no ordinal weights, so
    it is the agreement figure least dependent on an analyst's judgement.
    """
    binary: List[Tuple[str, str]] = [
        ("red" if _index(tool) == 0 else "not_red",
         "red" if _index(reference) == 0 else "not_red")
        for tool, reference in pairs
    ]
    return cohen_kappa(binary, tiers=("red", "not_red"))


def wilson_interval(
    successes: int,
    total: int,
    confidence: float = 0.95,
) -> Tuple[float, float]:
    """Wilson (1927) score interval for a binomial proportion.

    Chosen over the normal-approximation ("Wald") interval because it does not
    produce a widthless or negative bound when a proportion is 0 or 1 — the
    realistic case for the red tier in a small vignette set, where a Wald
    interval on 30/30 would claim zero uncertainty and on 0/30 would claim the
    bound is below zero. `confidence=0.95` uses z = 1.96, the value the
    hand-computed test in tests/test_evaluation.py reproduces.
    """
    if total <= 0:
        raise ValueError("a proportion needs a non-zero denominator")
    if not 0 <= successes <= total:
        raise ValueError("successes must be between 0 and total")
    z = _z_for_confidence(confidence)

    phat = successes / total
    z2 = z * z
    denom = 1.0 + z2 / total
    centre = (phat + z2 / (2.0 * total)) / denom
    margin = z * math.sqrt(phat * (1.0 - phat) / total + z2 / (4.0 * total * total)) / denom
    return (centre - margin, centre + margin)


# Two-sided normal deviates for the confidence levels a report might request, so
# `wilson_interval` stays dependency-free (no scipy for one constant).
_Z_TABLE: Dict[float, float] = {
    0.80: 1.2815515655,
    0.90: 1.6448536270,
    0.95: 1.96,
    0.99: 2.5758293035,
}


def _z_for_confidence(confidence: float) -> float:
    try:
        return _Z_TABLE[confidence]
    except KeyError as exc:
        raise ValueError(
            f"unsupported confidence {confidence}; one of {sorted(_Z_TABLE)}"
        ) from exc


def under_over_triage(pairs: Sequence[TierPair]) -> Dict[str, float]:
    """How often the tool seated a patient less urgently / more urgently than the
    reference.

    Directions are fixed against the most-urgent-first order: a larger tier index
    is a *less* urgent destination, so ``tool > reference`` is under-triage (the
    system missed severity — the clinically dangerous direction) and ``tool <
    reference`` is over-triage (extra care, a resource cost). Equal tiers count
    in the agreement but in neither error term. Rates are over the whole sample;
    the counts are reported too so a percentage is never read without its n.
    """
    if not pairs:
        raise ValueError("triage rates are undefined for an empty sample")
    under = over = exact = 0
    for tool, reference in pairs:
        ti, ri = _index(tool), _index(reference)
        if ti > ri:
            under += 1
        elif ti < ri:
            over += 1
        else:
            exact += 1
    n = len(pairs)
    return {
        "n": n,
        "exact": exact,
        "under": under,
        "over": over,
        "under_rate": under / n,
        "over_rate": over / n,
        "agreement_rate": exact / n,
    }


def red_tier_sensitivity(pairs: Sequence[TierPair]) -> Dict[str, object]:
    """P(tool red | reference red) with a Wilson 95% CI.

    "Of the patients the clinician called an emergency, how many did the tool
    also call red" — the recall on the one category that must not be missed. The
    confidence interval is Wilson, not the normal approximation, because a small
    vignette set makes the difference at exactly the values (near 0 or 1) this
    statistic lives at.
    """
    reference_red = [pair for pair in pairs if _index(pair[1]) == 0]
    hits = sum(1 for tool, _ in reference_red if _index(tool) == 0)
    total = len(reference_red)
    if total == 0:
        return {"denominator": 0, "hits": 0, "sensitivity": None,
                "ci95": None}
    low, high = wilson_interval(hits, total)
    return {
        "denominator": total,
        "hits": hits,
        "sensitivity": hits / total,
        "ci95": (low, high),
    }


def agreement_report(pairs: Sequence[TierPair]) -> Dict[str, object]:
    """Every headline number for one tool-vs-reference sample, in one dict.

    Assembled here rather than at the call site so the confusion matrix, the two
    kappa variants, the triage-direction rates and the red sensitivity are always
    computed from the same pairs — a report that mixed a filtered sample into one
    statistic and the full sample into another is how an evaluation quietly stops
    describing one thing.
    """
    if not pairs:
        raise ValueError("an agreement report needs at least one pair")
    matrix = confusion_matrix(pairs)
    return {
        "n": len(pairs),
        "confusion": matrix,
        "weighted_kappa": weighted_kappa(pairs),
        "cohen_kappa": cohen_kappa(pairs),
        "red_boundary_kappa": red_boundary_kappa(pairs),
        **under_over_triage(pairs),
        "red_sensitivity": red_tier_sensitivity(pairs),
    }
