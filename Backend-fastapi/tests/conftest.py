import os

import pytest
from dotenv import dotenv_values
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url


def _test_database_url() -> str:
    configured = os.getenv("TEST_DATABASE_URL")
    if configured:
        url = make_url(configured)
    else:
        values = dotenv_values(".env")
        source = os.getenv("DATABASE_URL") or values.get("DATABASE_URL")
        if not source:
            raise RuntimeError("Set DATABASE_URL or TEST_DATABASE_URL before running tests")
        url = make_url(source)
        if not url.database:
            raise RuntimeError("The test database URL must include a database name")
        url = url.set(database=f"{url.database}_test")

    database_name = url.database or ""
    if not database_name.endswith("_test"):
        raise RuntimeError("Refusing to run tests against a database not suffixed with _test")
    return url.render_as_string(hide_password=False)


def _ensure_test_database(database_url: str) -> None:
    test_url = make_url(database_url)
    admin_engine = create_engine(
        test_url.set(database="postgres"),
        isolation_level="AUTOCOMMIT",
    )
    try:
        with admin_engine.connect() as connection:
            exists = connection.execute(
                text("SELECT 1 FROM pg_database WHERE datname = :name"),
                {"name": test_url.database},
            ).scalar()
            if not exists:
                connection.exec_driver_sql(f'CREATE DATABASE "{test_url.database}"')
    finally:
        admin_engine.dispose()


TEST_DATABASE_URL = _test_database_url()
_ensure_test_database(TEST_DATABASE_URL)
os.environ["DATABASE_URL"] = TEST_DATABASE_URL

from alembic import command  # noqa: E402
from alembic.config import Config  # noqa: E402

from app.api.v1.endpoints import patients, triage  # noqa: E402
from app.api.v1.endpoints.auth import get_password_hash  # noqa: E402
from app.core.database import SessionLocal, engine  # noqa: E402
from app.models import Doctor  # noqa: E402


command.upgrade(Config("alembic.ini"), "head")

DOCTOR_EMAIL = os.getenv("SEED_DOCTOR_EMAIL", "doctor@simtack.com")
DOCTOR_PASSWORD = os.getenv("SEED_DOCTOR_PASSWORD", "Doctor123!")
DOCTOR_LOGIN = {"username": DOCTOR_EMAIL, "password": DOCTOR_PASSWORD}


def _reset_database() -> None:
    with engine.begin() as connection:
        connection.execute(
            text(
                "TRUNCATE TABLE triage_sessions, refresh_tokens, patients, doctors "
                "RESTART IDENTITY CASCADE"
            )
        )

    db = SessionLocal()
    try:
        db.add(
            Doctor(
                email=DOCTOR_EMAIL,
                hashed_password=get_password_hash(DOCTOR_PASSWORD),
                full_name="Test Doctor",
                is_active=True,
            )
        )
        db.commit()
    finally:
        db.close()


@pytest.fixture(autouse=True)
def isolated_database():
    _reset_database()
    patients._patient_rate_limit.clear()
    triage._triage_rate_limit.clear()
    yield
    patients._patient_rate_limit.clear()
    triage._triage_rate_limit.clear()


def doctor_headers(client) -> dict:
    """JWT auth headers for the seeded test practitioner."""
    token = client.post("/api/v1/auth/login", data=DOCTOR_LOGIN).json()["access_token"]
    return {"Authorization": f"Bearer {token}"}
