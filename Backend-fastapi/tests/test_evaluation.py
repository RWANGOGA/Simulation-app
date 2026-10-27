"""The agreement metrics, pinned to tables computed by hand.

Every expected value here was worked out from the confusion table below (or from
the closed-form Wilson formula) before the function was run, so the test asserts
the *arithmetic*, not the code's current output. If a formula silently changes,
these numbers are the ones that move and the reviewer can check them against the
textbook definitions named in `app/services/evaluation.py`.

Reference table (rows = the tool's tier, columns = the reference clinician's, in
the most-urgent-first SATS order red/orange/yellow/green), N = 175::

    red    [40,  5,  0,  0]   row 45
    orange [ 5, 30,  5,  0]   row 40
    yellow [ 0,  5, 40,  5]   row 50
    green  [ 0,  0,  5, 35]   row 40
             col45 col40 col50 col40
"""
import pytest

from app.services import evaluation

TABLE = [
    [40, 5, 0, 0],
    [5, 30, 5, 0],
    [0, 5, 40, 5],
    [0, 0, 5, 35],
]

TIERS = ("red", "orange", "yellow", "green")


def _pairs_from(table):
    pairs = []
    for i, row in enumerate(table):
        for j, count in enumerate(row):
            pairs.extend([(TIERS[i], TIERS[j])] * count)
    return pairs


PAIRS = _pairs_from(TABLE)


# ── the weights themselves ────────────────────────────────────────────────

def test_linear_weights_are_ordinal_and_zero_on_the_diagonal():
    weights = evaluation.linear_weights(TIERS)

    # Diagonal is disagreement-free; the widest ordinal slip (red vs green) is
    # the unit; every row is symmetric.
    assert [row[i] for i, row in enumerate(weights)] == [0.0, 0.0, 0.0, 0.0]
    assert weights[0][3] == 1.0
    assert weights[0][1] == pytest.approx(1 / 3)
    assert weights == [row[:] for row in map(list, zip(*weights))]  # symmetric


def test_weights_reject_a_single_category():
    with pytest.raises(ValueError):
        evaluation.linear_weights(("red",))


# ── weighted kappa ────────────────────────────────────────────────────────

def test_weighted_kappa_matches_the_hand_computed_table():
    # sum(w*O) = six off-diagonal 5-counts at w=1/3 = 10.0
    # sum(w*E) = 12600/175 = 72.0 (marginal products weighted by |i-j|/3)
    # kappa_w = 1 - 10/72 = 0.861111...
    assert evaluation.weighted_kappa(PAIRS) == pytest.approx(0.8611111, abs=1e-4)


def test_weighted_kappa_is_one_on_perfect_agreement():
    assert evaluation.weighted_kappa(_pairs_from(
        [[40, 0, 0, 0], [0, 30, 0, 0], [0, 0, 40, 0], [0, 0, 0, 35]]
    )) == pytest.approx(1.0)


def test_weighted_kappa_default_equals_explicit_linear_counts():
    # The convenience wrapper and the low-level count function must not diverge.
    weights = evaluation.linear_weights(TIERS)
    assert evaluation.weighted_kappa(PAIRS) == pytest.approx(
        evaluation.weighted_kappa_from_counts(TABLE, weights)
    )


def test_weighted_kappa_is_zero_when_disagreement_is_exactly_chance():
    # A uniform table makes every cell equal its marginal product (O == E), so
    # the weighted observed disagreement equals the expected-under-independence
    # value and the statistic is 0.0 by definition.
    chance = [[1, 1, 1, 1] for _ in range(4)]
    assert evaluation.weighted_kappa_from_counts(
        chance, evaluation.linear_weights(TIERS)
    ) == pytest.approx(0.0)


# ── unweighted and red-boundary kappa ─────────────────────────────────────

def test_cohen_kappa_matches_the_hand_computed_table():
    # p0 = 145/175; pe = (45*45 + 40*40 + 50*50 + 40*40)/175^2 = 7725/30625
    # kappa = (p0 - pe)/(1 - pe) = 0.770748...
    assert evaluation.cohen_kappa(PAIRS) == pytest.approx(0.770748, abs=1e-4)


def test_red_boundary_kappa_collapses_to_the_binary_decision():
    # Binary red/not-red: agreement 40+125=165 over 175; expected
    # (45*45 + 130*130)/175^2 = 18925/30625; kappa = 0.850428...
    assert evaluation.red_boundary_kappa(PAIRS) == pytest.approx(0.850428, abs=1e-4)


def test_weighted_kappa_outranks_unweighted_when_slips_are_mostly_adjacent():
    # The point of the ordinal weighting: here disagreement is concentrated one
    # category away, so the weighted figure is higher than the unweighted one
    # that treats a red/green confusion identically. The gap is the statement.
    assert evaluation.weighted_kappa(PAIRS) > evaluation.cohen_kappa(PAIRS)


# ── Wilson interval ───────────────────────────────────────────────────────

def test_wilson_interval_matches_the_hand_computed_proportion():
    low, high = evaluation.wilson_interval(40, 45)  # red sensitivity, 0.8889
    assert low == pytest.approx(0.765014, abs=1e-4)
    assert high == pytest.approx(0.951606, abs=1e-4)


def test_wilson_interval_is_sane_at_the_boundaries_a_small_set_reaches():
    # A proportion of 1.0 must not report a widthless bound (a Wald interval on
    # 30/30 does, claiming certainty the sample has not earned).
    low, high = evaluation.wilson_interval(30, 30)
    assert low > 0.0
    assert high == pytest.approx(1.0)
    assert low < 1.0

    low, high = evaluation.wilson_interval(0, 30)
    assert low == pytest.approx(0.0)
    assert high < 1.0
    assert high > 0.0


def test_wilson_interval_rejects_impossible_counts():
    with pytest.raises(ValueError):
        evaluation.wilson_interval(5, 0)
    with pytest.raises(ValueError):
        evaluation.wilson_interval(6, 5)
    with pytest.raises(ValueError):
        evaluation.wilson_interval(1, 10, confidence=0.5)  # unsupported level


# ── triage direction ──────────────────────────────────────────────────────

def test_under_and_over_triage_count_the_clinically_worse_direction_separately():
    report = evaluation.under_over_triage(PAIRS)

    # Below the diagonal (tool seated less urgently) = 5+5+5 = 15 under-triages;
    # above = 15 over-triages; 145 exact.
    assert report["under"] == 15
    assert report["over"] == 15
    assert report["exact"] == 145
    assert report["n"] == 175
    assert report["under_rate"] == pytest.approx(15 / 175)
    assert report["agreement_rate"] == pytest.approx(145 / 175)


def test_under_triage_is_the_direction_of_a_missed_emergency():
    # The tool said green where the clinician said red: that is one under-triage,
    # and must never be tallied as over- or exact.
    report = evaluation.under_over_triage([("green", "red")])
    assert report["under"] == 1
    assert report["over"] == 0


# ── red-tier sensitivity ──────────────────────────────────────────────────

def test_red_sensitivity_is_recall_on_the_reference_emergencies():
    result = evaluation.red_tier_sensitivity(PAIRS)

    assert result["denominator"] == 45  # reference-red column
    assert result["hits"] == 40
    assert result["sensitivity"] == pytest.approx(40 / 45)
    low, high = result["ci95"]
    assert low == pytest.approx(0.765014, abs=1e-4)
    assert high == pytest.approx(0.951606, abs=1e-4)


def test_red_sensitivity_is_none_not_zero_when_there_are_no_emergencies():
    # Reporting 0.0/None for "no red patients in the set" vs "the tool caught 0
    # of them" is the difference between an untested case and a failed one.
    result = evaluation.red_tier_sensitivity([("green", "yellow"), ("orange", "yellow")])
    assert result["denominator"] == 0
    assert result["sensitivity"] is None
    assert result["ci95"] is None


# ── the assembled report and its guards ───────────────────────────────────

def test_agreement_report_is_computed_from_one_sample():
    report = evaluation.agreement_report(PAIRS)

    assert report["n"] == 175
    assert report["weighted_kappa"] == pytest.approx(0.8611111, abs=1e-4)
    assert report["red_sensitivity"]["hits"] == 40
    # The confusion table round-trips through the report unchanged.
    assert [
        [report["confusion"][a][b] for b in TIERS] for a in TIERS
    ] == TABLE


def test_confusion_matrix_keeps_empty_categories_as_zero_rows():
    # Only orange/yellow appear, but red and green keep their (all-zero) rows so
    # the marginals — and therefore kappa — describe the scale, not the sample.
    matrix = evaluation.confusion_matrix([("orange", "orange"), ("yellow", "orange")])
    assert matrix["red"] == {t: 0 for t in TIERS}
    assert matrix["orange"]["orange"] == 1
    assert matrix["yellow"]["orange"] == 1


def test_a_tier_off_the_scale_is_rejected_not_silently_dropped():
    with pytest.raises(ValueError):
        evaluation.confusion_matrix([("purple", "red")])
    with pytest.raises(ValueError):
        evaluation.weighted_kappa([("red", "urgent")])


def test_metrics_need_data_rather_than_dividing_by_zero():
    for fn in (
        lambda: evaluation.weighted_kappa([]),
        lambda: evaluation.cohen_kappa([]),
        lambda: evaluation.under_over_triage([]),
        lambda: evaluation.agreement_report([]),
    ):
        with pytest.raises(ValueError):
            fn()
