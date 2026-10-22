"""Liveness and readiness.

The two are different questions and an orchestrator needs both:

* ``/health`` — "is this process alive?" No dependencies, never touches the
  database. Restarting the container is the right response to a failure here.
* ``/health/ready`` — "should traffic be sent here?" Checks the database, and
  answers 503 when it is unreachable. Restarting would not help, so a failing
  probe should pull the instance out of rotation instead.

Before this split there was only the first, so a deployment whose database had
gone away kept reporting healthy and kept receiving traffic.
"""

from __future__ import annotations

import logging
import pathlib
import re
from functools import lru_cache

from fastapi import APIRouter, Response, status
from sqlalchemy import text

from app.core.config import settings
from app.core.database import engine

logger = logging.getLogger(__name__)

router = APIRouter()

# Alembic writes annotated assignments (``revision: str = "0001"``) in newer
# templates and plain ones in older ones, so the annotation is optional here.
_REVISION = re.compile(r'^revision(?:\s*:[^=]+)?\s*=\s*["\']([^"\']+)["\']', re.MULTILINE)
_DOWN_REVISION = re.compile(r"^down_revision(?:\s*:[^=]+)?\s*=(.*)$", re.MULTILINE)
_QUOTED = re.compile(r'["\']([^"\']+)["\']')

_VERSION_DIR = pathlib.Path(__file__).resolve().parents[4] / "alembic" / "versions"


@router.get("/health")
def health():
    """Liveness. Deliberately dependency-free: a probe that pings the database
    turns a database blip into a restart loop."""
    return {
        "status": "alive",
        "service": settings.PROJECT_NAME,
        "version": settings.VERSION,
        "environment": settings.ENVIRONMENT,
    }


@router.get("/health/ready")
def readiness(response: Response):
    database = _database_state()
    if database["reachable"]:
        schema = _schema_state(database["revision"])
        if database["revision"] is not None and not schema["up_to_date"]:
            # Reported, not fatal: a schema behind the code is a deployment
            # mistake to fix, but the instance can still serve what it knows.
            logger.warning(
                "schema_behind_code",
                extra={"current": database["revision"], "expected": schema["expected"]},
            )
    else:
        schema = {"expected": _expected_head(), "up_to_date": False}
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE

    return {
        "status": "ready" if database["reachable"] else "not_ready",
        "database": "ok" if database["reachable"] else database["error"],
        "schema": schema,
    }


def _database_state() -> dict:
    """One round trip: connection, liveness, and the applied migration."""
    try:
        with engine.connect() as connection:
            connection.execute(text("SELECT 1"))
            revision = None
            try:
                revision = connection.execute(
                    text("SELECT version_num FROM alembic_version")
                ).scalar()
            except Exception:  # noqa: BLE001 - a fresh DB may have no table yet
                revision = None
        return {"reachable": True, "revision": revision}
    except Exception as exc:  # noqa: BLE001 - any failure means "do not send traffic"
        logger.warning("readiness_database_unreachable", extra={"error": str(exc)})
        return {"reachable": False, "error": "unavailable", "revision": None}


def _schema_state(applied: str | None) -> dict:
    expected = _expected_head()
    return {
        "current": applied,
        "expected": expected,
        "up_to_date": applied is not None and (expected is None or applied == expected),
    }


@lru_cache(maxsize=1)
def _expected_head() -> str | None:
    """The head revision, derived from the migration scripts themselves.

    The alternative — importing Alembic's own script directory at request time —
    is heavier and can touch the filesystem on every probe. Cached because the
    migrations in a running image never change.
    """
    try:
        revisions: dict[str, set[str]] = {}
        for path in sorted(_VERSION_DIR.glob("*.py")):
            source = path.read_text(encoding="utf-8")
            revision = _REVISION.search(source)
            if not revision:
                continue
            down = _DOWN_REVISION.search(source)
            # A merge revision lists a tuple of parents, so collect them all
            # rather than assuming a single parent.
            parents = set(_QUOTED.findall(down.group(1))) if down else set()
            revisions[revision.group(1)] = parents

        children = {parent for parents in revisions.values() for parent in parents}
        heads = [revision for revision in revisions if revision not in children]
        if len(heads) == 1:
            return heads[0]
        logger.warning("schema_head_ambiguous", extra={"heads": heads or "none"})
        return None
    except Exception as exc:  # noqa: BLE001 - never fail readiness on a parse error
        logger.warning("schema_head_unreadable", extra={"error": str(exc)})
        return None
