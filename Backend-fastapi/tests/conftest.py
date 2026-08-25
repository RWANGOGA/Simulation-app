# Tests talk straight to the real local database, and TestClient does NOT run
# the app's lifespan (where create_all + schema-drift ALTERs normally happen),
# so reconcile the schema here before any test module imports run.
from sqlalchemy import text

from app.core.database import Base, engine
from app.main import _SCHEMA_DRIFT_STATEMENTS
import app.models  # noqa: F401 registers all tables on Base

Base.metadata.create_all(bind=engine)
with engine.begin() as conn:
    for stmt in _SCHEMA_DRIFT_STATEMENTS:
        conn.execute(text(stmt))
