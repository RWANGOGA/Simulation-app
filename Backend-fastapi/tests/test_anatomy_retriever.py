"""
Unit tests for the RAG anatomy retriever service.
"""

from app.services.anatomy_retriever import (
    _tokenize,
    load_kb,
    retrieve,
    list_regions,
    MEDICAL_SYNONYMS,
)


def test_load_kb():
    kb = load_kb()
    assert isinstance(kb, dict)
    assert len(kb) > 0
    # Check key regions exist
    region_names = [c.region for c in kb.values()]
    assert any("Chest" in r for r in region_names)
    assert any("Abdomen" in r for r in region_names)


def test_tokenize_with_synonyms():
    tokens = _tokenize("I have a severe tummy headache")
    assert "tummy" in tokens
    assert "abdomen" in tokens  # expanded synonym
    assert "headache" in tokens
    assert "migraine" in tokens  # expanded synonym


def test_retrieve_by_exact_region():
    hits = retrieve(region="Chest / Heart", query="", top_k=3)
    assert len(hits) > 0
    assert "Chest" in hits[0].chunk.region or "Heart" in hits[0].chunk.region


def test_retrieve_headache_cranial():
    hits = retrieve(region="Headache / Cranial", query="throbbing migraine", top_k=3)
    assert len(hits) > 0
    assert hits[0].chunk.id in ["headache_cranial", "head_cranial", "head_neck"]


def test_retrieve_with_synonym_query():
    # Query uses "tummy" which expands to "abdomen"
    hits = retrieve(region=None, query="severe tummy pain and bloating", top_k=3)
    assert len(hits) > 0
    assert any("Abdomen" in h.chunk.region for h in hits)


def test_list_regions():
    regions = list_regions()
    assert isinstance(regions, list)
    assert len(regions) >= 10
    assert "id" in regions[0]
    assert "region" in regions[0]
