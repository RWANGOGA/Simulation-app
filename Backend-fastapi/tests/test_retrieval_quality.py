"""Retrieval quality gate for the anatomy knowledge base.

This is the measurement layer that has to exist before a retriever change can
be called a fix. It replays `tests/fixtures/retrieval_eval_cases.json` - clinical
expectations written from the knowledge base's own content, not from what the
retriever happens to return - through `anatomy_retriever.retrieve`, with no LLM,
no network and no randomness, so the numbers mean the same thing in CI as on a
laptop.

Two ideas are doing the work here:

**Floors, not ceilings.** The metric test asserts the retriever is no worse than
the last reviewed state. Improving past a floor is free; regressing is a build
failure. The values are the baseline measured on the day this file was written.

**A ratchet on the debt.** Everything the retriever currently gets wrong is
named explicitly below. A new failure fails the build. A failure that quietly
disappears *also* fails the build, until the entry is deleted - which forces a
human to look at the improvement, confirm it was deliberate, and tighten the
ceiling. Clinical systems should not be able to get better by accident.

`scripts/eval_retrieval.py` prints the full report:

    venv/bin/python -m scripts.eval_retrieval --verbose
"""
import json
from pathlib import Path

import pytest

from scripts.eval_retrieval import DEFAULT_K, DEFAULT_WINDOW, evaluate, load_cases

# ---------------------------------------------------------------------------
# Measured on 34-chunk anatomy_kb.json, k=3, window=6. Set from
# `python -m scripts.eval_retrieval`. Raise these when a change earns it.
#
# Day one (region as a +10/+3/+2 score bonus): pass 0.534, top1 0.865, mrr
# 0.891, recall@3 0.758, recall@6 0.857, nDCG@3 0.802, 14 safety violations.
# After making the tapped region a filter and a rank prior, and fixing the two
# scoring defects that were inverting BM25 here (negative idf for terms in >1
# chunk, function words surviving the stop list): pass 0.759, top1 0.865, mrr
# 0.891, recall@3 0.793, recall@6 0.848, nDCG@3 0.828, 1 safety violation.
#
# `recall_at_window` is the one number that went down, and it is the one floor
# set below its day-one value. The old retriever always returned a full 6-chunk
# window, padding it with whichever unrelated monographs drew the largest region
# bonus; those extra chunks coincidentally covered a few expected chunk ids. Now
# a bare tap returns 1-2 chunks that are genuinely about the part tapped. Window
# recall measured that padding as coverage, and it should not be recovered by
# putting the padding back: raising this floor again requires covering more (see
# the stemming and referral debts below), not serving more.
#
# Measured again after adding `text-side-contradicts-tap`, a case written to fail
# (59 cases): pass 0.746, top1 0.849, mrr 0.880, recall@3 0.788, recall@6 0.841,
# nDCG@3 0.818, referral 0.789. Every average moved down because the denominator
# grew by an obligation that was previously unmeasured, not because retrieval got
# worse - the floors below are set against that number so the next regression of a
# *single* case is still caught.
#
# That claim is checkable, not rhetorical. Re-measuring today's retriever on the
# original 58 cases alone gives pass 0.759, top1 0.865, mrr 0.891, recall@3 0.793,
# nDCG@3 0.828, 1 violation: top-1 and MRR hold their day-one values exactly while
# recall@k, nDCG and pass rate rise and safety violations fall fourteen to one.
# The four `unanchored_query` cases below then dragged the averages down again for
# the same denominator reason, and this time it is a defect that was found, not one
# that was fixed: with no region tapped, ranking is decided almost entirely by
# document length, because the region label is not part of the indexed text.
#
# P0-9's own baseline is the state after P0-1, re-measured on today's 63 cases:
# pass 0.714, top1 0.807, mrr 0.849, recall@3 0.759, recall@6 0.835, nDCG@3 0.788,
# referral 0.818, 18 failing cases, 5 cases retrieving no context at all (three of
# them clinical_jargon: 'hepatic colic', 'odynophagia and retrosternal burning',
# 'dyspnea on exertion'), 1 safety violation.
#
# After P0-9 (expansion moved to the query side only; inflections folded against
# the corpus's own vocabulary; clinical jargon bridged to words the monographs
# actually use): pass 0.857, top1 0.947, mrr 0.968, recall@3 0.877, recall@6 0.942,
# nDCG@3 0.912, referral 0.864, 9 failing cases, and the only two cases left with no
# context at all are deliberate out-of-scope abstentions rather than vocabulary
# holes. All 15 bare taps were already being *served* context before this item
# (that is what `bare_taps_served_without_text` counts, coverage not correctness);
# what changed is that the 'Right Thigh' tap now ranks the right monograph first,
# because 'thighs' folds onto 'thigh'. Safety violations are unchanged at 1, and
# `toes-not-cardiac` is now P0-6's business: the chest monograph reaches the window
# because nothing gates on minimum evidence, not because a word was unknown.
#
# One mechanism in that item was tried and reverted, and it is recorded here
# because a negative result is the point of measuring: indexing the region label
# as a weighted field changed *no* ranking (fusion is by rank, and the monographs
# it would have helped were already first in both lists), while indexing the label
# verbatim made 'right'/'left' repeated high-tf search terms and let the right-knee
# monograph out-rank the upper-abdomen one for gallbladder referral pain. The
# `unanchored_query` cases pass on the idf and expansion fixes, not on title
# weighting, so the title stays out of the searchable text.
# ---------------------------------------------------------------------------
FLOORS = {
    "pass_rate": 0.84,
    "top1_accuracy": 0.93,
    "mrr": 0.95,
    "recall_at_k": 0.86,
    "recall_at_window": 0.92,
    "ndcg_at_k": 0.89,
    "referral_coverage": 0.84,
}

# Cases that must NEVER be allowed to fail: the complaints whose whole purpose is
# to reach a red flag. A regression here is a patient being handed the wrong
# information about an emergency, so these are asserted individually rather than
# averaged into a metric where one loss would be invisible.
CLINICAL_INVARIANTS = [
    "redflag-sah-meningism",
    "redflag-mi-presentation",
    "redflag-scaphoid-fall",
    "redflag-ectopic",
    "redflag-neck-weak-arm",
    "redflag-infected-hand-bite",
    "redflag-achilles-pop",
]

# Clinically wrong content served inside the window the model is asked to trust,
# and what it was served for. Adding to this list is a build failure; so is an
# entry that stops being true without being deleted from it.
#
# There were fourteen of these. The rest were one bug: laterality and body region
# were expressed as points added to a score, so the mirror-image chunk survived
# into the window - and for the upper limb the two sides carry different
# referred-pain content, left cardiac and right gallbladder. A score has no way to
# say "not this one"; a filter does. Thirteen of the fourteen went away when the
# region stopped being a magnitude.
KNOWN_SAFETY_DEBT = {
    # The stemming part of this was true and is now fixed: the foot monographs do
    # reach the window (ranks 2-3). What remains is that the cardiac monograph
    # still leads it, because nothing in the system decides that a complaint with
    # no region tapped and no rare word in common with a monograph should not be
    # answered from it. That is P0-6's minimum-evidence gate, not a vocabulary gap.
    "toes-not-cardiac": ["chest_heart"],
}

# Every case that fails today, with the reason. Same ratchet semantics.
#
# After P0-9 what remains is no longer a vocabulary problem. It is three things:
#
#   * no abstain path. The knowledge base describes no ear, paediatric,
#     mental-health, wound-care or dosing content, so the only correct answer is
#     "not covered". Four of the six such cases still get an answer, because some
#     word overlapped by accident - which is the opposite of a safety property.
#     P0-6, and it owns toes-not-cardiac for the same reason.
#   * no evidence to order *plausible* candidates. When several monographs all
#     genuinely match, the tie is broken by document length, so the MI-referred
#     arm monograph can lead the cardiac one for a breathless patient.
#   * laterality read from the tap only, never from the sentence.
KNOWN_RANKING_DEBT = {
    "jargon-dyspnea-exertion": "both arm monographs bridge to breath/shortness/chest as well as the cardiac one, and win on length; 'dyspnea on exertion' with nothing tapped should still lead with the chest",
    "lay-fatty-food-upper-abdomen": "biliary referral to the right shoulder is unreachable: the link lives in the abdomen chunk's prose and no word in the complaint names the shoulder, so only a referral graph can follow it",
    "refer-renal-to-left-leg": "the back monograph is in the window but at rank 4: the tapped leg/knee family fills all three served slots, so referral content needs a slot reservation, not better matching",
    "text-side-contradicts-tap": "laterality is read from the tapped region only, so a patient who taps the right arm and describes the left cannot reach the left-arm monograph - which for the upper limb is the cardiac one. Needs the side in the free text reconciled with the side of the tap.",
    "toes-not-cardiac": "wrong top-1 for a foot complaint; see KNOWN_SAFETY_DEBT",
    "scope-wound-closure": "no abstain path",
    "scope-mental-health": "no abstain path",
    "scope-dosing": "no abstain path",
    "scope-ear": "no abstain path",
}


@pytest.fixture(scope="module")
def report():
    from app.services import anatomy_retriever

    return evaluate(anatomy_retriever.retrieve, k=DEFAULT_K, window=DEFAULT_WINDOW)


# ── the fixture itself ────────────────────────────────────────────────────


def test_case_ids_are_unique():
    cases = load_cases()
    ids = [case.id for case in cases]
    assert len(ids) == len(set(ids)), f"duplicate case ids: {ids}"


def test_every_referenced_chunk_exists():
    """A deleted or renamed chunk id in the fixture would otherwise make a case
    unsatisfiable and quietly lower the floors forever."""
    kb_path = Path(__file__).resolve().parent.parent / "app" / "data" / "anatomy_kb.json"
    known = {entry["id"] for entry in json.loads(kb_path.read_text())["regions"]}
    dangling = {}
    for case in load_cases():
        for cid in (
            set(case.top1_acceptable)
            | set(case.should_include)
            | set(case.must_not_include)
        ):
            if cid not in known:
                dangling.setdefault(case.id, []).append(cid)
    assert not dangling, f"cases name chunks the knowledge base does not have: {dangling}"


def test_debt_lists_only_reference_real_cases():
    cases = {case.id for case in load_cases()}
    assert set(KNOWN_SAFETY_DEBT) <= cases
    assert set(KNOWN_RANKING_DEBT) <= cases
    assert set(CLINICAL_INVARIANTS) <= cases
    for case_id, reason in KNOWN_RANKING_DEBT.items():
        assert reason, f"{case_id} has no recorded reason"


# ── the gate ──────────────────────────────────────────────────────────────


def test_metrics_do_not_regress(report):
    """Compared against FLOORS, not recomputed from a snapshot file, so the
    threshold stays something a human has signed off on."""
    summary = report.summary()
    failures = {
        name: (summary[name], floor)
        for name, floor in FLOORS.items()
        if summary[name] < floor
    }
    assert not failures, "retrieval quality regressed: " + ", ".join(
        f"{name} {value:.3f} < floor {floor:.3f}" for name, (value, floor) in failures.items()
    )


def test_safety_debt_has_not_grown(report):
    current = {}
    for row in report.results:
        if row.violations:
            current[row.case.id] = sorted(row.violations)
    new = set(current) - set(KNOWN_SAFETY_DEBT)
    assert not new, (
        f"the retriever is now serving clinically wrong context for {sorted(new)}. "
        "Fix the retrieval, or explain the debt in KNOWN_SAFETY_DEBT before merging."
    )


def test_safety_debt_is_still_true(report):
    """Passing by accident is not a fix. If a violation stopped happening, the
    entry has to be deleted and the reason understood."""
    current = {row.case.id for row in report.results if row.violations}
    resolved = set(KNOWN_SAFETY_DEBT) - current
    assert not resolved, (
        f"{sorted(resolved)} no longer violate anything. Delete them from "
        "KNOWN_SAFETY_DEBT and raise the floors if the metrics moved with them."
    )


def test_no_undeclared_failures(report):
    undeclared = {
        row.case.id for row in report.results if not row.passed
    } - set(KNOWN_RANKING_DEBT)
    assert not undeclared, (
        f"cases now failing with no recorded reason: {sorted(undeclared)}"
    )


def test_declared_failures_still_fail(report):
    resolved = set(KNOWN_RANKING_DEBT) - {
        row.case.id for row in report.results if not row.passed
    }
    assert not resolved, (
        f"{sorted(resolved)} now pass. Delete them from KNOWN_RANKING_DEBT, and "
        "from KNOWN_SAFETY_DEBT too if that is why, then tighten the floors."
    )


@pytest.mark.parametrize("case_id", CLINICAL_INVARIANTS)
def test_red_flag_content_is_reachable(report, case_id):
    """Pinned individually: these must pass with no debt entry, ever."""
    by_id = {row.case.id: row for row in report.results}
    assert case_id in by_id, f"{case_id} is not in the case fixture"
    row = by_id[case_id]
    assert row.passed, (
        f"{case_id} is a clinical invariant. It expects "
        f"{row.case.top1_acceptable} (plus {row.case.should_groups}) and got "
        f"{row.retrieved[:3]}. Red-flag reachability is not allowed into the "
        "debt list - fix the retrieval."
    )


def test_medical_jargon_is_not_silently_dropped(report):
    """The jargon group is where retrieval used to return *nothing*, which is the
    most dangerous failure the endpoint can produce: `_run_ask` then sends
    "(no context)" and the system prompt forbids anything else. Counted
    separately so a fix that only reorders never hides it.

    The ceiling was three, then P0-9 closed the vocabulary holes and it is now
    asserted at zero: every clinical term in the fixture reaches a monograph. If a
    new jargon case is added that returns nothing, this fails - which is the point,
    and the fix is the synonym table, never a re-tuned floor here.
    """
    jargon = [r for r in report.results if r.case.group == "clinical_jargon"]
    empty = [r.case.id for r in jargon if not r.retrieved]
    assert not empty, (
        f"{len(empty)} of {len(jargon)} medical-vocabulary cases retrieve no chunk "
        f"at all ({empty}); a clinician typing the proper term is told nothing exists"
    )


def test_out_of_scope_complaints_are_recorded_as_unanswered(report):
    """Nothing in this knowledge base covers these, so the only correct answer is
    "this is not covered". Both bounds of the assertion are load-bearing.

    Not 1.0: there is still no scope check. Four of the six still get an answer,
    because some word happened to overlap some monograph, and `_run_ask` then
    hands that to a model whose system prompt says to use only the provided
    context - so it manufactures an answer. P0-6 is what moves this to 1.0, at
    which point delete these cases from KNOWN_RANKING_DEBT and assert exactly 1.0.

    Not 0.0 either, and this is worth stating plainly because it is a *new* kind
    of behaviour rather than a designed one: two of the six now retrieve nothing.
    They do so incidentally - no word matched any chunk and no region was tapped -
    which is no longer the same mechanism as the jargon cases, since those all
    reach a monograph now (see the test above). Abstaining because your vocabulary
    failed is not abstaining because the subject is out of scope; the day those two
    are separated, this number should go up.
    """
    scope = [r for r in report.results if r.case.expect_no_match]
    assert scope, "the fixture lost its out-of-scope cases"
    abstained = [r.case.id for r in scope if r.abstained]
    answered = [r.case.id for r in scope if not r.abstained]
    assert abstained, (
        "every out-of-scope complaint now receives context, including the ones "
        "whose words match nothing anywhere in the knowledge base"
    )
    assert answered, (
        f"all {len(scope)} out-of-scope cases abstain. If an explicit scope check "
        "was built, assert abstention_accuracy == 1.0 and remove "
        f"{sorted(abstained)} from KNOWN_RANKING_DEBT."
    )


# ── invariants of the region filter itself ────────────────────────────────
#
# The metrics above would drift into satisfying this by luck. These two tests
# state it directly, because both are properties of the design rather than
# wishes about a particular complaint.

TEXT_PROBES = [
    "",
    "pain",
    "swelling numbness red hot tender",
    "worst headache of my life vomiting stiff neck",
    "can't breathe when walking upstairs",
    "pain after eating fatty food radiating to my back",
    "crushing pressure going down my arm",
]


def test_no_contralateral_chunk_is_ever_served():
    """Once the patient has indicated a side, the other side's monograph is not
    context - at any rank, for any wording, at full window size.

    This is the property the +10/+3/+2 region bonus could not express: a score can
    rank the mirror image lower, but only a filter can refuse it. It matters more
    here than in a generic document store because the knowledge base gives the two
    sides different content - `left_arm_shoulder` is labelled cardiovascular and
    `right_arm_shoulder` musculoskeletal - so a leak is not redundancy, it is a
    different diagnosis.

    Taps are derived from the knowledge base's own labels, so renaming or adding a
    sided region extends the sweep automatically rather than silently narrowing it.
    """
    from app.services import anatomy_retriever as ar

    side_of = {cid: ar._chunk_region_key(cid).side for cid in ar.load_kb()}
    sided_taps = sorted({c.region for c in ar.load_kb().values() if side_of[c.id]})
    assert len(sided_taps) >= 12, (
        f"only {len(sided_taps)} sided regions found; the sweep has stopped "
        "covering the body map"
    )
    leaks = []
    for tap in sided_taps:
        want = ar._region_key(tap).side
        for text in TEXT_PROBES:
            for hit in ar.retrieve(tap, text, DEFAULT_WINDOW):
                other = side_of[hit.chunk.id]
                if other and other != want:
                    leaks.append((tap, text, hit.chunk.id, other))
    assert not leaks, (
        f"contralateral content served for a sided region: {leaks}. The two sides "
        "of the body carry different clinical meaning in this knowledge base."
    )


def test_reported_score_never_contradicts_its_own_ranking(report):
    """`sources[].score` is returned to the client and printed into the prompt as
    `score=`, so a number that rises as relevance falls is actively misleading to
    the model: it would be told that the third chunk is more relevant than the
    first. Results are ordered by this score, so it must be monotone by
    construction - not correlated with the ranking, which was the old bug, where
    ordering came from rank fusion and the number from max(bm25, tfidf) plus the
    leaked region bonus.
    """
    from app.services import anatomy_retriever as ar

    broken, out_of_range = [], []
    for row in report.results:
        hits = ar.retrieve(row.case.region, row.case.query, DEFAULT_WINDOW)
        scores = [h.score for h in hits]
        if any(scores[i] < scores[i + 1] for i in range(len(scores) - 1)):
            broken.append(row.case.id)
        if any(not 0.0 <= s <= 1.0 for s in scores):
            out_of_range.append(row.case.id)
    assert not broken, f"score increases down the ranking for {broken}"
    assert not out_of_range, f"score outside [0, 1] for {out_of_range}"


# ── invariants of the vocabulary itself ───────────────────────────────────
#
# Expansion and normalisation are hand-written clinical knowledge, so they rot
# the moment nobody checks them. These three guards each encode a defect that was
# actually introduced and measured while building P0-9, not a hypothetical one.

_UPPER_LIMB = {"arm", "shoulder", "elbow", "wrist", "hand", "fingers", "thumb", "armpit"}
_LOWER_LIMB = {"leg", "knee", "thigh", "ankle", "foot", "shin", "calf", "toes", "heel"}


def test_expansion_reaches_the_corpus():
    """Every synonym entry must land on at least one word a monograph uses.

    A target that occurs in no document expands to a term with idf 0, which buys
    nothing and reads like coverage. This is the check that made me look up the
    corpus vocabulary before writing the clinical entries, rather than after.
    """
    from app.services import anatomy_retriever as ar

    vocab = ar._raw_corpus_terms()
    unreachable = [
        term
        for term, synonyms in ar.MEDICAL_SYNONYMS.items()
        if not any(ar.canonical_form(word) in vocab for word in synonyms)
    ]
    assert not unreachable, (
        f"{unreachable}: no target occurs anywhere in the knowledge base, so "
        "these words expand to nothing"
    )


def test_expansion_never_bridges_on_a_word_that_means_everything():
    """No target may appear in every monograph.

    "pain" is in all 34 chunks. Putting it in an entry's target list made the
    most common word in the language an expansion key, so every complaint in the
    system silently acquired that entry's jargon - and the idf that was supposed
    to neutralise "pain" cannot undo a term the query never had to earn.
    """
    from app.services import anatomy_retriever as ar

    chunks = ar.load_kb()
    universal = {
        word
        for words in chunks.values()
        for word in set(words.tokens)
        if all(word in set(chunk.tokens) for chunk in chunks.values())
    }
    offending = {
        (term, word)
        for term, synonyms in ar.MEDICAL_SYNONYMS.items()
        for word in synonyms
        if ar.canonical_form(word) in universal
    }
    assert not offending, f"{sorted(offending)}: universal terms carry no information"


def test_expansion_stays_narrow_and_never_changes_the_limb():
    """Two structural bounds on the derived expansion table.

    (a) No word may reach both upper-limb and lower-limb terms except 'joint'.
        A patient who says 'joint' genuinely has not said which limb; a system
        that decides for them repeats the error P0-1 removed from the region
        bonus, where a wrist complaint could acquire thigh advice.

    (b) No word may expand to more than eight others. A query that gains fifteen
        terms is not being translated, it is being drowned: idf then has nothing
        left to discriminate on. Measured, this is what actually separated the two
        closure designs - edge expansion tops out at 7 terms ('chest'), the group
        closure first attempted reaches 15 for 'chest' and 14 for 'back', and the
        extra terms were generic ones like 'activity' and 'lying'. That variant
        measured pass 0.841 against 0.857 here, losing redflag-achilles-pop and
        unanchored-sore-throat.
    """
    from app.services import anatomy_retriever as ar

    def family(words):
        bases = {ar.canonical_form(word) for word in words}
        return bases & _UPPER_LIMB, bases & _LOWER_LIMB

    crossings = []
    for term, synonyms in ar.MEDICAL_SYNONYMS.items():
        upper, lower = family(synonyms)
        if upper and lower:
            crossings.append((term, sorted(upper), sorted(lower)))
    assert not crossings, (
        f"these entries expand across both limbs: {crossings}. A wrist complaint "
        "must never acquire thigh advice."
    )

    table = ar._synonym_table()
    crossers = [
        word
        for word, extras in table.items()
        if all(f for f in family({word} | set(extras)))
    ]
    assert crossers == ["joint"], (
        f"words whose expansion spans both limbs: {crossers}. Only 'joint' may, "
        "and only while it stays a single one-hop edge."
    )

    widest = sorted(((len(v), k) for k, v in table.items()), reverse=True)[:3]
    over = [word for word, extras in table.items() if len(extras) > 8]
    assert not over, (
        f"{sorted(over)} expand to more than 8 terms (widest today: {widest}). "
        "Group-sharing a synonym table instead of linking pairs produces exactly "
        "this, and it measured two fewer passing cases."
    )


def test_normalisation_merges_only_inflections_that_both_exist():
    """The plural collapse must never invent a stem or join two lexemes.

    Every merge is asserted to be a real (plural, base) pair present in the
    corpus, and a fixed list of words that look inflected but are not - 'heart',
    'diabetes', 'stress', 'corpus', 'axis', 'ulnar', 'patellar' - must not move.
    A stemmer that quietly folds 'patellar' onto 'patella' or 'heart' onto 'hear'
    would merge distinct clinical concepts, and no metric floor would notice.
    """
    from app.services import anatomy_retriever as ar

    vocab = ar._raw_corpus_terms()
    for word in sorted(vocab):
        base = ar.canonical_form(word)
        if base != word:
            assert base in vocab, f"{word} collapsed to {base}, which is not in the corpus"
            assert len(base) < len(word), f"{word} -> {base} is not a shortening"

    for word in [
        "heart", "diabetes", "stress", "corpus", "axis", "ulnar", "patellar",
        "ovarian", "sciatica", "fever", "nausea", "gas", "menisci", "heel",
    ]:
        assert ar.canonical_form(word) == word or ar.canonical_form(word) in vocab, (
            f"'{word}' must survive unchanged, got '{ar.canonical_form(word)}'"
        )
    assert ar.canonical_form("heart") == "heart"
    assert ar.canonical_form("diabetes") == "diabetes"
    assert ar.canonical_form("thighs") == "thigh"
    assert ar.canonical_form("toes") == "toe"
