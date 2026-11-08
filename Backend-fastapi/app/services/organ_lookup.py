"""
Organ lookup for a tapped body part.

Replaces retrieval for the body map: the tap already says which part was
touched, so the answer is a plain dictionary lookup, not a search.

    part_to_organ.json   tap name -> {system, candidates}, most specific first
    organ_reports.json   report name -> description, functions, sub-parts and
                         disorders, built from the textbook dataset
    anatomy_kb.json      per-region red flags, suggested questions and common
                         conditions - the safety text the RAG answer used to
                         carry, kept here as fixed per-region data

The 34 body-map region strings ("Left Knee", "Chest / Heart", ...) are entries
in part_to_organ.json too. They matter more than the 1,433 mesh names: an
outside tap almost always lands on the single skin mesh, so the region the
viewer resolved is the only thing that says where the patient pointed.
"""

from __future__ import annotations

import json
from functools import lru_cache
from pathlib import Path
from typing import Any, Dict, List, Optional

_DATA = Path(__file__).resolve().parent.parent / "data"

COMING_SOON = "Detailed information for this part is coming soon."


@lru_cache(maxsize=1)
def reports() -> Dict[str, Dict[str, Any]]:
    return json.loads((_DATA / "organ_reports.json").read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def parts() -> Dict[str, Dict[str, Any]]:
    return json.loads((_DATA / "part_to_organ.json").read_text(encoding="utf-8"))


@lru_cache(maxsize=1)
def _regions() -> Dict[str, Dict[str, Any]]:
    kb = json.loads((_DATA / "anatomy_kb.json").read_text(encoding="utf-8"))
    return {r["region"].lower(): r for r in kb["regions"]}


def _key(name: Optional[str]) -> str:
    return " ".join((name or "").split()).lower()


def region_info(region: Optional[str]) -> Optional[Dict[str, Any]]:
    """The fixed safety text for a body-map region, or None if it is not one."""
    entry = _regions().get(_key(region))
    if entry is None:
        return None
    return {
        "region": entry["region"],
        "red_flags": list(entry.get("red_flags", [])),
        "suggested_questions": list(entry.get("suggested_questions", [])),
        "common_conditions": list(entry.get("common_conditions", [])),
    }


def lookup(name: str, region: Optional[str] = None) -> Optional[Dict[str, Any]]:
    """Information for a tap name or a report name; None if the name is unknown.

    [region] is the body-map region the tap resolved to. It only adds that
    region's safety text; when [name] is itself a region it is used for that.
    """
    key = _key(name)
    extra = region_info(region) or region_info(key)

    report_key = key.replace(" ", "_")
    if report_key in reports():
        r = reports()[report_key]
        return {"part": key, "system": r.get("system"), "about": report_key,
                "match": "report", "report": r, "related": [], "region": extra}

    entry = parts().get(key)
    if entry is None:
        return None
    found: List[str] = [c for c in entry["candidates"] if c in reports()]
    if found:
        return {"part": key, "system": entry["system"], "about": found[0],
                "match": "report", "report": reports()[found[0]],
                "related": found[1:], "region": extra}
    return {"part": key, "system": entry["system"], "about": None,
            "match": "system", "report": None, "related": [], "region": extra,
            "message": COMING_SOON}
