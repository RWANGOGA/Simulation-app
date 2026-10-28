"""The schema heal runs on the startup path, not merely as a helper.

Kept apart from `test_schema_adoption` because it asserts something different:
that the heal is wired into `lifespan`. Calling the helper directly would still
pass if nothing ever called it at boot, and being called at boot is the only part
that repairs a deployed database.

Reproduces the production failure exactly - drop `clinician_tier` (migration
0007), start the application the way a host starts it, and require the column to
be back before the first request is served.
"""
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import inspect, text

from app.core.database import engine
from app.main import app

TABLE = "triage_sessions"
COLUMN = "clinician_tier"


def _has_column() -> bool:
    return COLUMN in {c["name"] for c in inspect(engine).get_columns(TABLE)}


@pytest.fixture(autouse=True)
def _always_restore_column():
    """Leave the shared test database whole even if the assertion fails."""
    yield
    with engine.begin() as connection:
        connection.execute(
            text(f"ALTER TABLE {TABLE} ADD COLUMN IF NOT EXISTS {COLUMN} VARCHAR")
        )


def test_startup_adopts_the_column_before_serving() -> None:
    assert _has_column(), "precondition: migration 0007 is applied"

    with engine.begin() as connection:
        connection.execute(text(f"ALTER TABLE {TABLE} DROP COLUMN IF EXISTS {COLUMN}"))
    assert not _has_column(), "precondition: the deployed drift is reproduced"

    with TestClient(app) as client:
        assert client.get("/api/v1/health").status_code == 200

    assert _has_column(), "startup must adopt the column before serving"
