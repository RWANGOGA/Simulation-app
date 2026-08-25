# Tests talk straight to the real local database, and TestClient does NOT run
# the app's lifespan (where create_all + schema-drift ALTERs normally happen),
# so reconcile the schema here before any test module imports run.
from sqlalchemy import text

from app.core.database import Base, SessionLocal, engine
from app.main import _SCHEMA_DRIFT_STATEMENTS
from app.models.doctor import Doctor
from app.api.v1.endpoints.auth import get_password_hash
import app.models  # noqa: F401 registers all tables on Base

Base.metadata.create_all(bind=engine)
with engine.begin() as conn:
    for stmt in _SCHEMA_DRIFT_STATEMENTS:
        conn.execute(text(stmt))

# test_auth.py / test_decision.py / test_history.py all log in as this
# doctor — nothing previously created it, so the suite only ever "passed"
# on a database where someone had manually registered this exact account
# beforehand. Seeding it here (idempotently) makes the suite runnable from
# a genuinely fresh database, same as anyone freshly cloning the repo would have.
_db = SessionLocal()
try:
    if not _db.query(Doctor).filter(Doctor.email == "doctor@simtack.com").first():
        _db.add(Doctor(
            email="doctor@simtack.com",
            hashed_password=get_password_hash("Doctor123!"),
            full_name="Test Doctor",
            is_active=True,
        ))
        _db.commit()
finally:
    _db.close()
