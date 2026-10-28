"""The live schema is reconciled with the ORM at startup.

Written against the failure that prompted it. A host that starts the app with
its own command never runs the container entrypoint, so `alembic upgrade head`
never runs and a column added by a later migration is simply absent from the
database. Every INSERT naming that column then fails with `UndefinedColumn`, the
server answers 500, and - because Starlette builds a 500 outside CORSMiddleware -
no CORS header comes back, so the browser reports a CORS error and the real
cause stays invisible.

`triage_sessions.clinician_tier` (migration 0007) is the column that went
missing, so it is the one these tests take away. Wiring at startup is asserted
separately in `test_startup_schema_heal`.
"""
import pytest
from sqlalchemy import inspect, text

from app.core.database import engine
from app.main import _adopt_missing_columns

TABLE = "triage_sessions"
COLUMN = "clinician_tier"


def _columns() -> dict:
    return {column["name"]: column for column in inspect(engine).get_columns(TABLE)}


def _drop_column() -> None:
    with engine.begin() as connection:
        connection.execute(text(f"ALTER TABLE {TABLE} DROP COLUMN IF EXISTS {COLUMN}"))


@pytest.fixture(autouse=True)
def _always_restore_column():
    """Guarantee the column exists afterwards, even if a test fails part-way.

    Dropping it is a schema change to the shared test database; without this a
    single failure here would break every test that touches a triage session.
    """
    yield
    with engine.begin() as connection:
        connection.execute(
            text(f"ALTER TABLE {TABLE} ADD COLUMN IF NOT EXISTS {COLUMN} VARCHAR")
        )


def test_missing_column_is_adopted_back() -> None:
    assert COLUMN in _columns(), "precondition: migration 0007 is applied"

    _drop_column()
    assert COLUMN not in _columns(), "precondition: the deployed drift is reproduced"

    _adopt_missing_columns()

    adopted = _columns().get(COLUMN)
    assert adopted is not None, "the missing column must be added back"
    # Type and nullability come from the model, so the adopted column is the one
    # the ORM will actually write to rather than a lookalike.
    assert adopted["nullable"] is True
    assert "VARCHAR" in str(adopted["type"]).upper()


def test_adoption_adds_nothing_when_the_schema_is_current() -> None:
    # Compared by name. SQLAlchemy type objects do not implement value equality,
    # so two inspections of an identical schema never compare equal and the
    # whole-column comparison would fail on a false alarm.
    before = set(_columns())

    _adopt_missing_columns()

    assert set(_columns()) == before
